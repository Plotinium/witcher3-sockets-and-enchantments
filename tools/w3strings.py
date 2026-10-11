"""Reader and writer for The Witcher 3 localized text files, .w3strings (version 164, next-gen).

The layout follows the open-source WolvenKit 7 reader (WolvenKit.W3Strings, version 162), adapted to
what the next-gen game files contain: texts are UTF-8, offsets and lengths are in bytes, and the
cipher works byte by byte. The `check` command proves it on any file: it reads it, writes it back
and compares texts and keys.

Usage:
  python w3strings.py read <file.w3strings> [output.tsv]   id, key hashes, text
  python w3strings.py check <file.w3strings>               read, write back, compare
"""
import os, struct, sys, tempfile

# language: (file key, id magic). Key 0 = plain text (other mods use it too).
LANGUAGES = {
    'ar': (0, 0), 'br': (0, 0), 'esmx': (0, 0), 'kr': (0, 0), 'tr': (0, 0), 'ua': (0, 0),
    'pl': (0x83496237, 0x73946816), 'en': (0x43975139, 0x79321793), 'de': (0x75886138, 0x42791159),
    'it': (0x45931894, 0x12375973), 'fr': (0x23863176, 0x75921975), 'cz': (0x24987354, 0x21793217),
    'es': (0x18796651, 0x42387566), 'zh': (0x18632176, 0x16875467), 'ru': (0x63481486, 0x42386347),
    'hu': (0x42378932, 0x67823218), 'jp': (0x54834893, 0x59825646), 'cn': (0x18632176, 0x16875467),
}
VERSION = 164


def key_hash(key):
    h = 0
    for c in key.lower():
        h = (h * 31 + ord(c)) & 0xFFFFFFFF
    return h


def _read_num(d, p):
    val, shift, i = 0, 0, 1
    while True:
        b = d[p]; p += 1
        s, mask = 6, 255
        if b > 127:
            mask, s = 127, 7
        elif b > 63 and i == 1:
            mask = 63
        val |= (b & mask) << shift
        shift += s
        i += 1
        if b < 64 or (i >= 3 and b < 128):
            return val, p


def _write_num(v):
    if v < 64:
        return bytes([v])
    out = [(v & 63) | 64]
    v >>= 6
    while v >= 128:
        out.append((v & 127) | 128)
        v >>= 7
    out.append(v)
    return bytes(out)


def _cipher(data, magic):
    """Encrypts or decrypts (same operation) n bytes."""
    if magic == 0:
        return bytes(data)
    n = len(data)
    key = (magic >> 8) & 0xFFFF
    out = bytearray()
    for b in data:
        out.append(b ^ (((n + 1) * key) & 0xFF))
        key = ((key << 1) | (key >> 15)) & 0xFFFF
    return bytes(out)


def read(path):
    d = open(path, 'rb').read()
    if d[:4] != b'RTSW':
        raise ValueError('not a w3strings file')
    version, k1 = struct.unpack('<IH', d[4:10])
    if version != VERSION:
        raise ValueError(f'version {version}: only {VERSION} is supported')
    k2 = struct.unpack('<H', d[-2:])[0]
    file_key = (k1 << 16) | k2
    magic = next((m for (k, m) in LANGUAGES.values() if k == file_key), None)
    if magic is None:
        raise ValueError(f'unknown language {file_key:#x}')
    p = 10
    n1, p = _read_num(d, p)
    b1 = [struct.unpack('<III', d[p + 12 * i:p + 12 * i + 12]) for i in range(n1)]
    p += 12 * n1
    n2, p = _read_num(d, p)
    b2 = [struct.unpack('<II', d[p + 8 * i:p + 8 * i + 8]) for i in range(n2)]
    p += 8 * n2
    _n3, p = _read_num(d, p)
    texts = {}
    for idh, off, ln in b1:
        texts[idh ^ magic] = _cipher(d[p + off:p + off + ln], magic).decode('utf-8', 'surrogateescape')
    keys = {}
    for kh, idh in b2:
        keys.setdefault(idh ^ magic, []).append(kh)
    return {'key': file_key, 'magic': magic, 'texts': texts, 'keys': keys}


def write(path, language, entries, extra_hashes=()):
    """entries: list of (id, text_key, text); an empty key means no key.
    extra_hashes: (hash, id) pairs already computed, used by the read-back check."""
    file_key, magic = LANGUAGES[language.lower()]
    k1, k2 = file_key >> 16, file_key & 0xFFFF
    buf, b1 = bytearray(), bytearray()
    for sid, _k, text in sorted(entries, key=lambda v: v[0] ^ magic):
        raw = text.encode('utf-8', 'surrogateescape')
        b1 += struct.pack('<III', sid ^ magic, len(buf), len(raw))
        buf += _cipher(raw, magic) + b'\0'
    pairs = sorted([(key_hash(k), sid) for sid, k, _t in entries if k] + list(extra_hashes))
    b2 = b''.join(struct.pack('<II', kh, sid ^ magic) for kh, sid in pairs)
    out = (b'RTSW' + struct.pack('<IH', VERSION, k1) + _write_num(len(entries)) + bytes(b1)
           + _write_num(len(pairs)) + b2 + _write_num(len(buf)) + bytes(buf) + struct.pack('<H', k2))
    with open(path, 'wb') as g:
        g.write(out)


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    cmd, path = sys.argv[1], sys.argv[2]
    f = read(path)
    if cmd == 'read':
        rows = [f'{sid}\t{",".join(map(str, f["keys"].get(sid, [])))}\t{t}' for sid, t in f['texts'].items()]
        if len(sys.argv) > 3:
            open(sys.argv[3], 'w', encoding='utf-8').write('\n'.join(rows) + '\n')
        else:
            print('\n'.join(rows))
    elif cmd == 'check':
        language = next(l for l, (k, _m) in LANGUAGES.items() if k == f['key'])
        entries = [(sid, '', t) for sid, t in f['texts'].items()]
        extra = [(kh, sid) for sid, hs in f['keys'].items() for kh in hs]
        tmp = os.path.join(tempfile.gettempdir(), 'w3strings_check.tmp')
        write(tmp, language, entries, extra)
        g = read(tmp)
        os.remove(tmp)
        same = g['texts'] == f['texts'] and g['keys'] == f['keys']
        print(f'{len(entries)} texts, {len(extra)} keys; read back identical: {same}')
