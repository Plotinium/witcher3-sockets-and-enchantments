# Sockets and Enchantments

A mod for The Witcher 3: Wild Hunt (next-gen, version 4.x) that makes runewords and glyphwords
work on all your gear.

- **Enchant every armor piece.** The runewright accepts gloves, trousers and boots, not only chest
  armor. Armor gets glyphwords, swords get runewords, as in the base game.
- **Stack enchantments.** Put 1 (base game), 3, 5 or unlimited words on the same item. Each extra
  word costs the runes or glyphs of its recipe, like a normal enchantment. The item tooltip lists
  all of them.
- **Enchant without 3 sockets** (optional switch). The runewright stops asking for 3 rune slots.
- **Optional cheats**, all off by default: enchant for free; unlock every runeword and glyphword;
  Remove gives back the recipe's runes and glyphs; keep the runes an item has when you enchant it
  (the base game destroys them); an Enchanting tab and an Add sockets tab in the main menu, each
  with its own switch, with no runewright or blacksmith needed (sockets cost their usual price and
  the engine's socket cap still applies).
- **Remove one word or all.** Select an applied word and press Remove to take off only that one;
  with nothing selected, Remove takes off all of them. The confirmation says which.
- **Raise rune slots** (optional, chosen at install). Every sword and armor piece with fewer than 3
  (or 5) slots gets 3 (or 5). Items that already have more keep theirs.
- **Safe removal.** A menu switch puts your save back in a state the base game understands before
  you uninstall.

All settings except the slots are in Options > Mods > Sockets and Enchantments and apply at once.

## Languages

The menu and messages are translated into **English** and **Italian**. Every other game language
shows the English texts. Translations live in `src/strings.tsv`, one column per language.

## Install

**Vortex:** drag the zip into the Mods tab, install, and pick the rune slot option in the installer.

**Manual:** from the zip, copy the contents of `core` into the game folder (`The Witcher 3\`). For
more rune slots, also copy the contents of `slots3` or `slots5` (only one of them).

Changing the rune slot option needs a reinstall and a game restart: the game reads item data only
at startup. Before moving to fewer slots, run the removal steps below (switch, wait for the message,
save), so runes in slots that disappear go back to your inventory.

## Uninstall

1. Make a backup save.
2. Move gear off the armor stands and weapon racks into your inventory or stash.
3. In the mod menu, turn on **Prepare to remove the mod**. Within a few seconds the mod removes the
   extra enchantments, removes enchantments the base game cannot apply (on gloves, trousers, boots
   or items with fewer than 3 slots), and takes out runes from slots that only exist with the mod.
   Runes and the glyphs of removed recipes go back to your inventory. A message tells you when it
   is done.
4. Save, then uninstall the mod.

If you skip these steps the save still loads: extra enchantments stay active but no longer show
in the tooltip, and the runewright cannot remove them.

## Compatibility

- **Scripts:** the mod hooks game functions with `@wrapMethod` annotations and replaces no game
  script file, so it works alongside other enchanting or inventory mods. It conflicts only with a
  mod that replaces the same functions entirely (`@replaceMethod`). This mod replaces one:
  `CR4EnchantingMenu.OnConfigUI`, the runewright panel's opening function.
- **Rune slots:** the slot options replace whole item XML files. Another mod that replaces the same
  files conflicts with it, and the game uses only one version. Merge them with Script Merger, or
  install the slot option "As in the base game". Known overlap: Aerondight
  (`dlc\bob\data\gameplay\items*\def_item_weapons_relic.xml`).
- **Almighty Geralt** stores extra enchantments the same way, so the two mods see each other's
  words. Its words count toward this mod's limit, and the removal step removes and refunds them too.

## Known limits

- When starting New Game+, the game recreates items: the main enchantment carries over, the extra
  ones do not.
- The same glyphword on two items does not double effects the game checks as on/off; numeric bonuses
  do add up.
- The engine caps how many slots a blacksmith can add (3 on swords and chest, 1 on gloves and boots,
  measured in game). That cap is in the game executable, not in scripts or data, so this mod cannot
  raise it: the slot options set the starting number of slots instead.

## How it works

The engine stores one enchantment per item. Extra words are added as crafted abilities named
`<word> _Stats`, which the engine saves with the item and applies while the item is equipped; the
game checks glyphwords by that ability name, so they work from any armor piece.

## Building from source

Requirements: Windows, Python 3, the game installed, and `wcc_lite.exe` (bundled with Script Merger
in `WitcherScriptMerger\Tools\wcc_lite\bin\x64\`; it shows a license window on first start).

```
set W3_GAME_DIR=C:\path\to\The Witcher 3
python build.py
```

The first run extracts the item XML files from your own game into `cache\` (they are CD PROJEKT RED
data and are not part of this repository). The build then packs the slot options with wcc_lite,
reads every package back to check it, writes the menu texts, and creates the zip in `dist/`. A check also
stops the build if a `@wrapMethod` calls `wrappedMethod` more than once, which the game's compiler
rejects.

| Path | Content |
|---|---|
| `src/scripts/` | WitcherScript sources |
| `src/menu/` | in-game menu |
| `src/strings.tsv` | English and Italian texts |
| `src/fomod/` | Vortex installer |
| `tools/` | readers and writers for the game's `.bundle` and `.w3strings` files |
| `build.py` | build, check, package, install for development |
| `TESTING.md` | in-game test checklist |

## License

The mod's own code (scripts, build script, menu, installer) is released under the MIT License, see
`LICENSE`. The item XML files in the slot options are modified copies of CD PROJEKT RED game data
and remain the property of CD PROJEKT RED; the MIT License does not apply to them.

Author: Plotinium

Source code: https://github.com/Plotinium/witcher3-sockets-and-enchantments
Nexus Mods page: https://www.nexusmods.com/witcher3/mods/14113
