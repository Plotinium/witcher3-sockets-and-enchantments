"""Reader for The Witcher 3 .bundle packages (REDengine 3, POTATO70 header).

Usage:
  python bundle.py list <file.bundle>
  python bundle.py extract <file.bundle> <output_dir> [filter_regex]

Read-only: game files are never modified.
Handles both the next-gen game packages and the classic layout written by wcc_lite.
"""
import os, re, struct, sys, zlib


def _snappy(data, size):
    out = bytearray(); i = 0
    # leading varint length
    while data[i] & 0x80: i += 1
    i += 1
    while i < len(data):
        tag = data[i]; i += 1; t = tag & 3
        if t == 0:
            ln = tag >> 2
            if ln >= 60:
                nb = ln - 59; ln = int.from_bytes(data[i:i+nb], 'little'); i += nb
            ln += 1; out += data[i:i+ln]; i += ln; continue
        if t == 1:
            ln = ((tag >> 2) & 7) + 4; off = ((tag >> 5) << 8) | data[i]; i += 1
        elif t == 2:
            ln = (tag >> 2) + 1; off = int.from_bytes(data[i:i+2], 'little'); i += 2
        else:
            ln = (tag >> 2) + 1; off = int.from_bytes(data[i:i+4], 'little'); i += 4
        for _ in range(ln): out.append(out[-off])
    return bytes(out)


def _lz4_block(src, size):
    dst = bytearray(); i = 0; n = len(src)
    while i < n:
        tok = src[i]; i += 1
        lit = tok >> 4
        if lit == 15:
            while True:
                b = src[i]; i += 1; lit += b
                if b != 255: break
        dst += src[i:i+lit]; i += lit
        if i >= n: break
        off = src[i] | (src[i+1] << 8); i += 2
        ml = tok & 15
        if ml == 15:
            while True:
                b = src[i]; i += 1; ml += b
                if b != 255: break
        ml += 4
        start = len(dst) - off
        for k in range(ml): dst.append(dst[start + k])
    return bytes(dst)


def read_index(path):
    """Returns a list of (name, size, compressed_size, offset, compression)."""
    with open(path, 'rb') as f:
        if f.read(8) != b'POTATO70': raise ValueError('not a W3 bundle: ' + path)
        _bsize, _dummy, data_off = struct.unpack('<III', f.read(12))
        f.seek(0x20); entries = []
        while f.tell() < data_off + 0x20:
            pos = f.tell()
            rec = f.read(0x140)
            name = rec[:0x100].split(bytes(1))[0].decode('utf-8', 'replace')
            if not name:  # mod packages pad the entry table with empty space
                break
            if struct.unpack('<I', rec[0x110:0x114])[0] == 0:
                # 0x140-byte entry (classic layout, written by wcc_lite):
                # name, hash, zero, size, compressed size, offset, timestamp, padding, crc, compression
                size, zsize, off = struct.unpack('<III', rec[0x114:0x120])
                comp = struct.unpack('<I', rec[0x13c:0x140])[0]
            else:
                # 0x130-byte entry (next-gen game packages):
                # name, hash, offset, zero, size, compressed size, crc, compression
                off, _z, size, zsize, _crc, comp = struct.unpack('<IIIIII', rec[0x110:0x128])
                f.seek(pos + 0x130)
            entries.append((name, size, zsize, off, comp))
    return entries


def read_file(path, entry):
    name, size, zsize, off, comp = entry
    with open(path, 'rb') as f:
        f.seek(off); data = f.read(zsize)
    if comp == 0: return data
    if comp == 1: return zlib.decompress(data)
    if comp == 2: return _snappy(data, size)
    if comp in (4, 5): return _lz4_block(data, size)
    raise NotImplementedError(f'compression {comp} not supported ({name})')


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    cmd, path = sys.argv[1], sys.argv[2]
    entries = read_index(path)
    if cmd == 'list':
        for v in entries: print(f'{v[4]}\t{v[1]}\t{v[0]}')
    elif cmd == 'extract':
        out = sys.argv[3]; filt = re.compile(sys.argv[4], re.I) if len(sys.argv) > 4 else None
        n = 0
        for v in entries:
            if filt and not filt.search(v[0]): continue
            dest = os.path.join(out, v[0].replace(chr(92), os.sep))
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, 'wb') as g: g.write(read_file(path, v))
            n += 1
        print(f'extracted {n} files')
