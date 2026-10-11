# In-game test checklist

Scripts cannot be compiled outside the game: every change is tested in game. Use a **copy** of a
save. The game compiles scripts at startup; a compile error shows a window before the main menu,
with the file and line.

The script log is written to `Documents\The Witcher 3\scriptslog.txt` when the game is started
with the `-debugscripts` launch option.

## Setup

Build with `python build.py`, then install the zip with Vortex and pick "At least 3" in the
installer. Turn every cheat off in the mod menu unless a step says otherwise.

## Steps

1. **Startup**: the game starts with no script error window.
2. **Menu**: Options > Mods shows "Sockets and Enchantments" with all its entries, in the game
   language (English or Italian).
3. **Slots**: in the inventory, gloves, trousers, boots, swords and chest armor have at least 3
   rune slots.
4. **Enchant gloves** (Enchantments per item: 1): at a runewright, enchant gloves with a
   glyphword. The word applies and shows in the tooltip.
5. **Effect**: with the gloves equipped, the glyphword works (for example one that changes Aard or
   Igni behaves as it does on chest armor).
6. **Without 3 slots**: reinstall with "As in the base game", turn on "Enchant any item, even
   without 3 sockets" and enchant an item with 1 or 2 slots.
7. **Several words** (Enchantments per item: 3): add a second and a third word to the same item.
   Each time the recipe's runes are spent and the tooltip lists every word; the list marks them
   "applied". A fourth word is refused with "Maximum number of enchantments allowed on this item
   reached (3)".
8. **Remove one word**: select an applied word, press Remove. The confirmation names that word;
   only that word goes away.
9. **Remove all**: with no word selected, press Remove. The confirmation says every word will be
   removed, with the count.
10. **Save and reload**: after reloading, items keep their words and runes.
11. **Cheats**, one at a time:
    - Enchant without runes or glyphs: the apply button works with missing ingredients and
      nothing is spent.
    - Unlock every runeword and glyphword: the runewright lists every word.
    - Removing a word gives back its runes and glyphs: the recipe returns, the panel's ingredient
      counts update at once and a message says so.
    - Keep runes when enchanting: enchant an item that holds a rune; the rune comes back to the
      inventory. Before turning this on, check once with it off whether the game already returns
      the rune: if it does, the cheat would return it twice.
    - Enchanting tab in the main menu: the tab appears next to Inventory and Alchemy and the panel
      opens; the runewright's own panel still opens too.
    - Add sockets tab in the main menu: the tab appears, adds a socket at the usual price (money
      drops by that price once), stops at the engine's cap; a blacksmith's panel still works.
12. **Removal**: follow the uninstall steps in the README, then load the save without the mod.
    Inventory and items are fine, and the returned runes are there.
