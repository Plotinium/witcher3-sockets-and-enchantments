// Sockets and Enchantments - settings and shared functions.
//
// How extra enchantments work: the engine keeps one enchantment per item (EnchantItem /
// GetEnchantment). The others are added as crafted abilities of the item, "<word> _Stats"
// (AddItemCraftedAbility): they are saved with the game and applied while the item is equipped.
// Almighty Geralt uses the same form.

// --- settings from the menu -----------------------------------------------------------------

// maximum number of words on one item; 0 = unlimited
function SAE_MaxEnchants() : int
{
	var v : string;

	v = theGame.GetInGameConfigWrapper().GetVarValue( 'SocketsAndEnchants', 'SAE_MaxEnchants' );
	if( v == "1" )
		return 3;
	if( v == "2" )
		return 5;
	if( v == "3" )
		return 0;
	return 1;
}

// true if the runewright also accepts items with fewer than 3 slots
function SAE_NoSlotRequirement() : bool
{
	return theGame.GetInGameConfigWrapper().GetVarValue( 'SocketsAndEnchants', 'SAE_NoSlotRequirement' ) == "true";
}

// cheat: enchant without spending runes or glyphs
function SAE_FreeEnchant() : bool
{
	return theGame.GetInGameConfigWrapper().GetVarValue( 'SocketsAndEnchants', 'SAE_FreeEnchant' ) == "true";
}

function SAE_CfgOn( varName : name ) : bool
{
	return theGame.GetInGameConfigWrapper().GetVarValue( 'SocketsAndEnchants', varName ) == "true";
}

// cheat: the runewright offers every word, not only those of their level
function SAE_AllWordsUnlocked() : bool
{
	return SAE_CfgOn( 'SAE_AllWords' );
}

// cheat: Remove gives back the runes and glyphs of the recipe
function SAE_RefundOnRemove() : bool
{
	return SAE_CfgOn( 'SAE_RefundOnRemove' );
}

// cheat: when an item is enchanted, the runes in its slots go back to the inventory
function SAE_KeepRunes() : bool
{
	return SAE_CfgOn( 'SAE_KeepRunes' );
}

// cheat: the blacksmith's "Add sockets" panel is a tab of the main menu
function SAE_AddSocketsAnywhere() : bool
{
	return SAE_CfgOn( 'SAE_AddSocketsAnywhere' );
}

// cheat: the runewright panel is a tab of the main menu
function SAE_EnchantAnywhere() : bool
{
	return SAE_CfgOn( 'SAE_EnchantAnywhere' );
}

// the runes in the item, to give back those the game destroys when enchanting it
function SAE_RunesOf( inv : CInventoryComponent, item : SItemUniqueId, out runes : array<name> )
{
	runes.Clear();
	inv.GetItemEnhancementItems( item, runes );
}

// puts back in the inventory the runes that were there before and are gone now
function SAE_ReturnLostRunes( inv : CInventoryComponent, item : SItemUniqueId, before : array<name> )
{
	var now : array<name>;
	var i, j : int;

	inv.GetItemEnhancementItems( item, now );
	for( i = 0; i < before.Size(); i += 1 )
	{
		j = now.FindFirst( before[i] );
		if( j >= 0 )
			now.Erase( j );
		else
			inv.AddAnItem( before[i], 1, true, false );
	}
}

function SAE_UninstallMode() : bool
{
	return theGame.GetInGameConfigWrapper().GetVarValue( 'SocketsAndEnchants', 'SAE_Uninstall' ) == "true";
}

// --- gear --------------------------------------------------------------------------------

function SAE_IsSword( inv : CInventoryComponent, item : SItemUniqueId ) : bool
{
	var cat : name;

	cat = inv.GetItemCategory( item );
	return ( cat == 'steelsword' || cat == 'silversword' ) && !inv.ItemHasTag( item, 'SecondaryWeapon' );
}

// gloves, trousers, boots: the base game does not enchant them
function SAE_IsSmallArmor( inv : CInventoryComponent, item : SItemUniqueId ) : bool
{
	var cat : name;

	cat = inv.GetItemCategory( item );
	return cat == 'gloves' || cat == 'pants' || cat == 'boots';
}

function SAE_IsGear( inv : CInventoryComponent, item : SItemUniqueId ) : bool
{
	return SAE_IsSword( inv, item ) || inv.GetItemCategory( item ) == 'armor' || SAE_IsSmallArmor( inv, item );
}

// --- words (runewords and glyphwords) -----------------------------------------------------

// every word the game can apply, read from the recipes
function SAE_AllWords( out words : array<name> )
{
	var dm : CDefinitionsManagerAccessor;
	var main : SCustomNode;
	var n : name;
	var s : string;
	var i : int;

	words.Clear();
	dm = theGame.GetDefinitionsManager();
	main = dm.GetCustomDefinition( 'crafting_schematics' );
	for( i = 0; i < main.subNodes.Size(); i += 1 )
	{
		if( !dm.GetCustomNodeAttributeValueName( main.subNodes[i], 'name_name', n ) )
			continue;
		s = NameToString( n );
		if( !StrStartsWith( s, "Runeword" ) && !StrStartsWith( s, "Glyphword" ) )
			continue;
		if( !IsNameValid( getEnchamtmentStatName( n ) ) || words.Contains( n ) )
			continue;
		words.PushBack( n );
	}
}

// like SAE_AllWords, but read only once per game session
function SAE_Words( out words : array<name> )
{
	var w : W3PlayerWitcher;
	var tmp : array<name>;

	w = GetWitcherPlayer();
	if( !w )
	{
		SAE_AllWords( words );
		return;
	}
	if( w.saeWords.Size() == 0 )
	{
		SAE_AllWords( tmp );
		w.saeWords = tmp;
	}
	words = w.saeWords;
}

// the extra words on the item, excluding the one the engine keeps
function SAE_GetExtras( inv : CInventoryComponent, item : SItemUniqueId, out extras : array<name> )
{
	var words : array<name>;
	var primary : name;
	var i : int;

	extras.Clear();
	primary = inv.GetEnchantment( item );
	SAE_Words( words );
	for( i = 0; i < words.Size(); i += 1 )
	{
		if( words[i] != primary && inv.ItemHasAbility( item, getEnchamtmentStatName( words[i] ) ) )
			extras.PushBack( words[i] );
	}
}

function SAE_HasWord( inv : CInventoryComponent, item : SItemUniqueId, word : name ) : bool
{
	return inv.GetEnchantment( item ) == word || inv.ItemHasAbility( item, getEnchamtmentStatName( word ) );
}

function SAE_CountWords( inv : CInventoryComponent, item : SItemUniqueId ) : int
{
	var extras : array<name>;
	var n : int;

	SAE_GetExtras( inv, item, extras );
	n = extras.Size();
	if( inv.IsItemEnchanted( item ) )
		n += 1;
	return n;
}

function SAE_AddExtra( inv : CInventoryComponent, item : SItemUniqueId, word : name )
{
	inv.AddItemCraftedAbility( item, getEnchamtmentStatName( word ), false );
}

// removes the extra words; with refund, gives back the runes or glyphs of the recipe
function SAE_RemoveExtras( inv : CInventoryComponent, item : SItemUniqueId, refund : bool ) : int
{
	var extras : array<name>;
	var stat : name;
	var i, removed : int;

	SAE_GetExtras( inv, item, extras );
	for( i = 0; i < extras.Size(); i += 1 )
	{
		stat = getEnchamtmentStatName( extras[i] );
		inv.RemoveItemCraftedAbility( item, stat );
		// if the ability does not come from us and stays, no refund: otherwise it would be paid every pass
		if( inv.ItemHasAbility( item, stat ) )
			continue;
		if( refund )
			SAE_Refund( inv, extras[i] );
		removed += 1;
	}
	return removed;
}

// removes a single word. If it is the one the engine keeps, the first extra word takes its place,
// so the item stays enchanted with the others.
function SAE_RemoveWord( inv : CInventoryComponent, item : SItemUniqueId, word : name ) : bool
{
	var extras : array<name>;
	var promoted : name;

	if( inv.GetEnchantment( item ) != word )
	{
		inv.RemoveItemCraftedAbility( item, getEnchamtmentStatName( word ) );
		return !inv.ItemHasAbility( item, getEnchamtmentStatName( word ) );
	}

	SAE_GetExtras( inv, item, extras );
	inv.UnenchantItem( item );
	if( inv.IsItemEnchanted( item ) )
		return false;
	if( extras.Size() > 0 )
	{
		promoted = extras[0];
		inv.RemoveItemCraftedAbility( item, getEnchamtmentStatName( promoted ) );
		inv.EnchantItem( item, promoted, getEnchamtmentStatName( promoted ) );
		// if the engine refuses, the word goes back where it was: it is never lost
		if( !inv.IsItemEnchanted( item ) )
			SAE_AddExtra( inv, item, promoted );
	}
	return true;
}

function SAE_Refund( inv : CInventoryComponent, word : name )
{
	var schem : SEnchantmentSchematic;
	var i : int;

	schem = getEnchantmentSchematicFromName( word );
	for( i = 0; i < schem.ingredients.Size(); i += 1 )
	{
		if( IsNameValid( schem.ingredients[i].itemName ) && schem.ingredients[i].quantity > 0 )
			inv.AddAnItem( schem.ingredients[i].itemName, schem.ingredients[i].quantity, true, false );
	}
}

function SAE_HasIngredients( inv : CInventoryComponent, schem : SEnchantmentSchematic ) : bool
{
	var i : int;

	for( i = 0; i < schem.ingredients.Size(); i += 1 )
	{
		if( inv.GetItemQuantityByName( schem.ingredients[i].itemName ) < schem.ingredients[i].quantity )
			return false;
	}
	return true;
}

// tooltip text for a word: "Name: description", as the game writes it
function SAE_WordTooltip( inv : CInventoryComponent, word : name ) : string
{
	var schem : SEnchantmentSchematic;
	var pInts : array<int>;
	var pFloats : array<float>;
	var pStrs : array<string>;

	schem = getEnchantmentSchematicFromName( word );
	inv.GetParamsForRunewordTooltip( word, pInts, pFloats, pStrs );
	return "<font face=\"$BoldFont\">" + GetLocStringByKeyExt( NameToString( schem.localizedName ) ) + ":</font> "
		+ GetLocStringByKeyExtWithParams( schem.localizedDescriptionName, pInts, pFloats, pStrs );
}

function SAE_Notify( key : string )
{
	theGame.GetGuiManager().ShowNotification( GetLocStringByKeyExt( key ) );
}
