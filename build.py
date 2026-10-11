"""Builds the Sockets and Enchantments mod.

Usage:
  python build.py                          build into build/ and create the zip in dist/ (nothing goes into the game)
  python build.py --install [--slots 3|5]  build, then copy the core part and, if given, the slot
                                           option into the game folder
  python build.py --uninstall              remove every part of the mod from the game folder

Parts of the mod (folders inside build/ and inside the zip):
  core/    scripts, menu, texts: always installed
  slots3/  XML package: every item with fewer than 3 rune slots gets 3
  slots5/  XML package: every item with fewer than 5 rune slots gets 5
  fomod/   the installer Vortex shows to pick the slot option

Steps:
  1. For each threshold, take the item XML files with items below it and raise only those items;
     the rest of each file stays byte-identical. Pack with wcc_lite and read the package back to
     check it.
  2. Generate sae_vanilla_slots.ws (original slots of the raised items), which the removal cleanup
     uses to know how many runes fit without the mod.
  3. Write the localized texts and read them back; check that every key in use has a text.
  4. Create the zip for Vortex, Nexus and manual install.
"""
import os, re, shutil, subprocess, sys, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'tools'))
import bundle, w3strings  # noqa: E402

NAME = 'modSocketsAndEnchants'
SLOTS_NAME = 'modSocketsAndEnchantsSlots'
VERSION = '1.0.0'
THRESHOLDS = (3, 5)
# game folder: override with the W3_GAME_DIR environment variable
GAME = os.environ.get('W3_GAME_DIR', r'G:\SteamLibrary\steamapps\common\The Witcher 3')
WCC = os.path.join(GAME, r'WitcherScriptMerger\Tools\wcc_lite\bin\x64\wcc_lite.exe')
# item XML files extracted from the installed game (not in the repository: they belong to CD PROJEKT RED)
CACHE = os.path.join(HERE, 'cache', 'bundle')
XML_BUNDLES = ('xml', 'bob', 'ep1', 'dlc0')
SRC = os.path.join(HERE, 'src')
BUILD = os.path.join(HERE, 'build')
DIST = os.path.join(HERE, 'dist')  # release archives
MENU = r'bin\config\r4game\user_config_matrix\pc'
CATEGORIES = ('steelsword', 'silversword', 'armor', 'gloves', 'pants', 'boots')
FIRST_ID = 2119431000  # text id range reserved for this mod
LANGUAGES = ['ar', 'br', 'cn', 'cz', 'de', 'en', 'es', 'esmx', 'fr', 'hu', 'it', 'jp', 'kr', 'pl', 'ru', 'tr', 'ua', 'zh']

RE_ITEM = re.compile(r'<item\b[^>]*?(?:/>|>.*?</item>)', re.S)
RE_TAGS = re.compile(r'<tags>(.*?)</tags>', re.S)
RE_SLOT = re.compile(r'(enhancement_slots\s*=\s*")(\d+)(")')


def attr(block, name):
    m = re.search(r'\b' + name + r'\s*=\s*"([^"]*)"', block)
    return m.group(1) if m else ''


def hidden(block):
    """Technical items the player never sees (body parts, 'no show' variants)."""
    t = RE_TAGS.search(block)
    return bool(t) and 'noshow' in [x.strip().lower() for x in t.group(1).split(',')]


def to_raise(block, threshold):
    """Returns the original slots if the item must be raised, otherwise None."""
    opening = block[:block.index('>') + 1]
    if attr(opening, 'category') not in CATEGORIES or hidden(block):
        return None
    s = RE_SLOT.search(opening)
    if not s or int(s.group(2)) >= threshold:
        return None
    return int(s.group(2))


def modify_xml(threshold):
    """Returns {path_in_game: data} and {item_name: original_slots}."""
    changed_files, originals = {}, {}
    for package in sorted(os.listdir(CACHE)):
        base = os.path.join(CACHE, package)
        for root, _d, files in os.walk(base):
            if '/items' not in root.replace(os.sep, '/') + '/':
                continue
            for f in sorted(files):
                if not f.lower().endswith('.xml'):
                    continue
                path = os.path.join(root, f)
                raw = open(path, 'rb').read()
                bom = raw.startswith(b'\xef\xbb\xbf')
                changed = 0

                def change(m):
                    nonlocal changed
                    block = m.group(0)
                    orig = to_raise(block, threshold)
                    if orig is None:
                        return block
                    name = attr(block[:block.index('>') + 1], 'name')
                    originals[name] = min(originals.get(name, 99), orig)
                    changed += 1
                    return RE_SLOT.sub(lambda x: x.group(1) + str(threshold) + x.group(3), block, count=1)

                new = RE_ITEM.sub(change, raw.decode('utf-8-sig'))
                if changed:
                    changed_files[os.path.relpath(path, base)] = (b'\xef\xbb\xbf' if bom else b'') + new.encode('utf-8')
    return changed_files, originals


def prepare_cache():
    """Extracts the item XML files from the installed game packages, once."""
    if os.path.isdir(CACHE):
        return
    for name in XML_BUNDLES:
        src = os.path.join(GAME, 'content', 'content0', 'bundles', name + '.bundle')
        for v in bundle.read_index(src):
            rel = v[0].replace(chr(92), '/')
            if not rel.lower().endswith('.xml') or '/items' not in '/' + rel.rsplit('/', 1)[0] + '/':
                continue
            dest = os.path.join(CACHE, name, *rel.split('/'))
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            open(dest, 'wb').write(bundle.read_file(src, v))
    print('Item XML files extracted from the game into', CACHE)


def check_wraps():
    """Every @wrapMethod calls wrappedMethod exactly once: the game's compiler rejects a second
    call ("Could not find function 'wrappedMethod'")."""
    for f in sorted(os.listdir(os.path.join(SRC, 'scripts'))):
        t = open(os.path.join(SRC, 'scripts', f), encoding='utf-8').read()
        for b in t.split('@wrapMethod(')[1:]:
            body = b.split(chr(10) + '}' + chr(10), 1)[0]
            name = re.search(r'function\s+(\w+)', body).group(1)
            n = body.count('wrappedMethod(')
            if n != 1:
                raise SystemExit(f'{f}: {name} calls wrappedMethod {n} times')


# WitcherScript keywords: none of them may be used as a variable or parameter name
# ("syntax error, unexpected TOKEN_ENTRY" for a variable named entry)
KEYWORDS = {
    'abstract', 'autobind', 'break', 'case', 'class', 'cleanup', 'const', 'continue', 'default',
    'defaults', 'delete', 'do', 'editable', 'else', 'entry', 'enum', 'event', 'exec', 'extends',
    'false', 'final', 'for', 'function', 'hint', 'if', 'import', 'in', 'inlined', 'latent', 'new',
    'null', 'optional', 'out', 'parent', 'private', 'protected', 'public', 'quest', 'return',
    'reward', 'saved', 'single', 'state', 'statemachine', 'storyscene', 'struct', 'super',
    'switch', 'this', 'timer', 'true', 'var', 'virtual_parent', 'while',
}


def check_identifiers():
    """Stops the build if a variable or parameter uses a WitcherScript keyword as its name."""
    for f in sorted(os.listdir(os.path.join(SRC, 'scripts'))):
        t = open(os.path.join(SRC, 'scripts', f), encoding='utf-8').read()
        names = set()
        for m in re.finditer(r'\bvar\s+([A-Za-z_][\w\s,]*?)\s*:', t):
            names |= {x.strip() for x in m.group(1).split(',')}
        names |= set(re.findall(r'[(,]\s*(?:out\s+|optional\s+)?([A-Za-z_]\w*)\s*:', t))
        bad = sorted(n for n in names if n.lower() in KEYWORDS)
        if bad:
            raise SystemExit(f'{f}: keyword used as a name: {bad}')


def run_wcc(*args):
    r = subprocess.run([WCC, *args], cwd=os.path.dirname(WCC), capture_output=True, text=True,
                       encoding='utf-8', errors='replace', timeout=600)
    lines = (r.stdout + r.stderr).splitlines()
    if r.returncode != 0 or any('[Error]' in x for x in lines):
        print('\n'.join(lines[-20:]))
        raise SystemExit(f'wcc_lite {args[0]} failed')


def build_slots(threshold):
    changed_files, originals = modify_xml(threshold)
    xml_in = os.path.join(BUILD, f'_xml{threshold}')
    for rel, data in changed_files.items():
        dest = os.path.join(xml_in, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        open(dest, 'wb').write(data)
    content = os.path.join(BUILD, f'slots{threshold}', 'Mods', SLOTS_NAME, 'content')
    os.makedirs(content, exist_ok=True)
    run_wcc('pack', f'-dir={xml_in}', f'-outdir={content}')
    run_wcc('metadatastore', f'-path={content}')
    shutil.rmtree(xml_in)

    # check: every XML in the package is the prepared one, and no item is left below the threshold
    package = os.path.join(content, 'blob0.bundle')
    entries = {v[0].lower(): v for v in bundle.read_index(package)}
    for rel, data in changed_files.items():
        v = entries.get(rel.replace(os.sep, chr(92)).lower())
        if not v or bundle.read_file(package, v) != data:
            raise SystemExit(f'package {threshold}: {rel} missing or different')
    below = sum(1 for v in entries.values()
                for m in RE_ITEM.finditer(bundle.read_file(package, v).decode('utf-8-sig'))
                if to_raise(m.group(0), threshold) is not None)
    if below or len(entries) != len(changed_files):
        raise SystemExit(f'package {threshold}: {below} items below threshold, {len(entries)} files')
    print(f'Slots {threshold}: {len(originals)} items raised in {len(changed_files)} files; package read back, '
          f'identical and with no item below {threshold}.')
    return originals


def vanilla_slots_script(originals, per_function=50):
    """Table of original slots, split into functions of at most `per_function` cases: the game's
    compiler runs out of memory on a switch of about 400 cases."""
    names = sorted(originals)
    for name in names:
        if "'" in name or chr(92) in name:
            raise SystemExit(f'name cannot be written as a name literal: {name}')
    chunks = [names[i:i + per_function] for i in range(0, len(names), per_function)]
    lines = ['// Generated by build.py: do not edit by hand.',
             '// Original slots of the items the slot options raise. -1 = item never raised.',
             f'// Split into functions of {per_function} cases: a longer switch does not compile.',
             '']
    for k, group in enumerate(chunks):
        lines += [f'function SAE_VanillaSlots{k}( itemName : name ) : int', '{', '\tswitch( itemName )', '\t{']
        lines += [f"\t\tcase '{name}': return {originals[name]};" for name in group]
        lines += ['\t}', '\treturn -1;', '}', '']
    lines += ['function SAE_VanillaSlots( itemName : name ) : int', '{', '\tvar n : int;', '']
    for k in range(len(chunks)):
        lines += [f'\tn = SAE_VanillaSlots{k}( itemName );', '\tif( n >= 0 )', '\t\treturn n;']
    lines += ['\treturn -1;', '}', '']
    return chr(10).join(lines)


def read_strings():
    rows = []
    with open(os.path.join(SRC, 'strings.tsv'), encoding='utf-8') as g:
        header = g.readline().rstrip('\n').split('\t')
        for line in g:
            if line.strip():
                rows.append(dict(zip(header, line.rstrip('\n').split('\t'))))
    return rows


def keys_in_use():
    """The text keys that scripts and menu ask for."""
    used = set()
    for f in os.listdir(os.path.join(SRC, 'scripts')):
        t = open(os.path.join(SRC, 'scripts', f), encoding='utf-8').read()
        used |= set(re.findall(r'"(sae_[a-z0-9_]+)"', t))
    t = open(os.path.join(SRC, 'menu', NAME + '.xml'), encoding='utf-8').read()
    for m in re.finditer(r'<(Group|Var|Option)\b[^>]*displayName="([^"]+)"', t):
        kind, name = m.group(1), m.group(2)
        if kind == 'Group':
            used |= {'panel_' + x.lower() for x in name.split('.')}
        else:
            used.add(('option_' if kind == 'Var' else 'preset_value_') + name)
    return used


def build_core(originals):
    content = os.path.join(BUILD, 'core', 'Mods', NAME, 'content')
    scripts = os.path.join(content, 'scripts', 'local')
    shutil.copytree(os.path.join(SRC, 'scripts'), scripts)
    open(os.path.join(scripts, 'sae_vanilla_slots.ws'), 'w', encoding='utf-8', newline='\n').write(
        vanilla_slots_script(originals))

    rows = read_strings()
    # with the customDisplayName/customNames tags the menu looks the key up without a prefix (like
    # New Game Plus Plus); without tags it adds option_/preset_value_ (like Gwent Players Map):
    # both are written
    for t in list(rows):
        for prefix in ('option_', 'preset_value_'):
            if t['key'].startswith(prefix):
                rows.append(dict(t, key=t['key'][len(prefix):]))
    missing = keys_in_use() - {t['key'] for t in rows}
    if missing:
        raise SystemExit(f'texts missing from strings.tsv: {sorted(missing)}')
    for language in LANGUAGES:
        column = 'it' if language == 'it' else 'en'
        entries = [(FIRST_ID + i, t['key'], t[column]) for i, t in enumerate(rows)]
        path = os.path.join(content, f'{language}.w3strings')
        w3strings.write(path, language, entries)
        if sorted(w3strings.read(path)['texts'].values()) != sorted(v[2] for v in entries):
            raise SystemExit(f'{language}.w3strings does not read back identical')

    menu = os.path.join(BUILD, 'core', MENU)
    os.makedirs(menu, exist_ok=True)
    shutil.copy(os.path.join(SRC, 'menu', NAME + '.xml'), menu)
    print(f'Core: {len(os.listdir(scripts))} scripts, {len(rows)} texts in {len(LANGUAGES)} languages read back '
          f'identical, every key in use present, {len(originals)} items in the original slots table.')


def build_fomod():
    """Copies the installer. An option shows a picture when src/fomod/images/<option>.png exists
    (base, slots3, slots5): without pictures Vortex leaves the left half of the window empty."""
    fomod = os.path.join(BUILD, 'fomod')
    os.makedirs(fomod, exist_ok=True)
    images = os.path.join(SRC, 'fomod', 'images')
    for f in ('info.xml', 'ModuleConfig.xml'):
        t = open(os.path.join(SRC, 'fomod', f), encoding='utf-8').read().replace('{VERSION}', VERSION)

        def image(m):
            name = m.group(1) + '.png'
            if not os.path.isfile(os.path.join(images, name)):
                return ''
            os.makedirs(os.path.join(fomod, 'images'), exist_ok=True)
            shutil.copy(os.path.join(images, name), os.path.join(fomod, 'images', name))
            return '<image path="fomod' + chr(92) + 'images' + chr(92) + name + '" />'

        t = re.sub(r'<!--IMAGE:(\w+)-->', image, t)
        t = re.sub(r'\n[ \t]*\n', '\n', t)  # drop the lines left empty by a missing picture
        open(os.path.join(fomod, f), 'w', encoding='utf-8', newline='\n').write(t)


def make_zip():
    os.makedirs(DIST, exist_ok=True)
    dest = os.path.join(DIST, f'{NAME}-{VERSION}.zip')
    with zipfile.ZipFile(dest, 'w', zipfile.ZIP_DEFLATED) as z:
        for root, _d, files in os.walk(BUILD):
            for f in sorted(files):
                p = os.path.join(root, f)
                z.write(p, os.path.relpath(p, BUILD))
        for f in ('README.md', 'LICENSE'):
            if os.path.isfile(os.path.join(HERE, f)):
                z.write(os.path.join(HERE, f), f)
    print('Archive:', dest)


def build():
    check_wraps()
    check_identifiers()
    prepare_cache()
    shutil.rmtree(BUILD, ignore_errors=True)
    originals = {}
    for threshold in THRESHOLDS:
        for name, n in build_slots(threshold).items():
            originals[name] = min(originals.get(name, 99), n)
    build_core(originals)
    build_fomod()
    make_zip()


def install(threshold):
    uninstall()
    shutil.copytree(os.path.join(BUILD, 'core', 'Mods'), os.path.join(GAME, 'Mods'), dirs_exist_ok=True)
    shutil.copy(os.path.join(BUILD, 'core', MENU, NAME + '.xml'), os.path.join(GAME, MENU))
    if threshold:
        shutil.copytree(os.path.join(BUILD, f'slots{threshold}', 'Mods'), os.path.join(GAME, 'Mods'), dirs_exist_ok=True)
    print('Installed into', GAME, f'(slots: {threshold or "as in the base game"})')


def uninstall():
    for name in (NAME, SLOTS_NAME):
        folder = os.path.join(GAME, 'Mods', name)
        if os.path.isdir(folder):
            shutil.rmtree(folder)
    menu = os.path.join(GAME, MENU, NAME + '.xml')
    if os.path.isfile(menu):
        os.remove(menu)


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    if '--uninstall' in sys.argv:
        uninstall()
        print('Mod removed from the game folder.')
    else:
        build()
        if '--install' in sys.argv:
            s = int(sys.argv[sys.argv.index('--slots') + 1]) if '--slots' in sys.argv else 0
            if s and s not in THRESHOLDS:
                raise SystemExit(f'--slots must be one of {THRESHOLDS}')
            install(s)
