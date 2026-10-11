// Sockets and Enchantments - periodic check and cleanup before removal.
//
// Without the mod the game does not know three things the mod can leave in a save: extra words on
// an item, a word on an item the base game cannot enchant (gloves, trousers, boots, or fewer
// than 3 slots), and runes in the slots added by the slot options.
// "Prepare to remove the mod" takes off all three and gives back runes and glyphs.

@addField(W3PlayerWitcher)
var saeWords : array<name>;

@addField(W3PlayerWitcher)
var saeTickAcc : float;

@addField(W3PlayerWitcher)
var saeCleanReported : bool;

// set when the cleanup ran from the options menu, so its result is shown as soon as play resumes
@addField(W3PlayerWitcher)
var saeCleanPending : bool;

@addField(W3PlayerWitcher)
var saeCleanFixed : int;

// original slots of the item if one of this mod's slot options raised them, otherwise -1.
// The option is recognized by the number of slots the game reads now from the XML (3 or 5);
// if the slots come from another mod, nothing is touched.
function SAE_SlotsWithoutMod( inv : CInventoryComponent, item : SItemUniqueId ) : int
{
	var vanilla, loaded : int;
	var itemName : name;

	itemName = inv.GetItemName( item );
	vanilla = SAE_VanillaSlots( itemName );
	if( vanilla < 0 )
		return -1;
	loaded = theGame.GetDefinitionsManager().GetItemEnhancementSlotCount( itemName );
	// slots bought from a blacksmith add to the XML ones and stay without the mod
	if( ( loaded == 3 || loaded == 5 ) && loaded > vanilla )
		return vanilla + Max( 0, inv.GetItemEnhancementSlotsCount( item ) - loaded );
	return -1;
}

// the base game enchants only swords and chest armor with at least 3 slots
function SAE_VanillaCanEnchant( inv : CInventoryComponent, item : SItemUniqueId ) : bool
{
	var slots : int;

	slots = SAE_SlotsWithoutMod( inv, item );
	if( slots < 0 )
		slots = inv.GetItemEnhancementSlotsCount( item );
	return ( SAE_IsSword( inv, item ) || inv.GetItemCategory( item ) == 'armor' ) && slots >= 3;
}

// puts an item back as it would be without the mod; returns how many things it fixed
function SAE_CleanItem( inv : CInventoryComponent, item : SItemUniqueId ) : int
{
	var runes : array<name>;
	var fixed, vanilla, i : int;
	var word : name;

	if( !inv.IsIdValid( item ) || !SAE_IsGear( inv, item ) )
		return 0;

	fixed = SAE_RemoveExtras( inv, item, true );

	if( inv.IsItemEnchanted( item ) && !SAE_VanillaCanEnchant( inv, item ) )
	{
		word = inv.GetEnchantment( item );
		inv.UnenchantItem( item );
		if( !inv.IsItemEnchanted( item ) )
		{
			SAE_Refund( inv, word );
			fixed += 1;
		}
	}

	// runes in slots that do not exist without the slot option go back to the inventory
	vanilla = SAE_SlotsWithoutMod( inv, item );
	if( vanilla >= 0 && !inv.IsItemEnchanted( item ) )
	{
		inv.GetItemEnhancementItems( item, runes );
		for( i = runes.Size() - 1; i >= vanilla; i -= 1 )
		{
			if( inv.RemoveItemEnhancementByIndexScript( item, i ) )
			{
				inv.AddAnItem( runes[i], 1, true, false );
				fixed += 1;
			}
		}
	}

	if( fixed > 0 )
		inv.NotifyEnhancedItem( item );
	return fixed;
}

function SAE_CleanAll( inv : CInventoryComponent ) : int
{
	var items : array<SItemUniqueId>;
	var i, fixed : int;

	if( !inv )
		return 0;
	inv.GetAllItems( items );
	for( i = 0; i < items.Size(); i += 1 )
		fixed += SAE_CleanItem( inv, items[i] );
	return fixed;
}

function SAE_HorseInventory( w : W3PlayerWitcher ) : CInventoryComponent
{
	if( !w.GetHorseManager() )
		return NULL;
	return w.GetHorseManager().GetInventoryComponent();
}

// runs the cleanup on every inventory the mod checks and returns how many things it fixed
function SAE_CleanEverything( w : W3PlayerWitcher ) : int
{
	if( !w )
		return 0;
	return SAE_CleanAll( w.GetInventory() ) + SAE_CleanAll( SAE_HorseInventory( w ) );
}

// "Prepare to remove the mod" turned on in the options: the cleanup starts at once, while the
// menu is still open, and the player is told what is happening instead of waiting in silence
@wrapMethod(CR4IngameMenu)
function OnOptionValueChanged( groupId : int, optionName : name, optionValue : string )
{
	var w : W3PlayerWitcher;

	if( optionName == 'SAE_Uninstall' && optionValue == "true" )
	{
		w = GetWitcherPlayer();
		if( w )
		{
			theGame.GetGuiManager().ShowNotification( GetLocStringByKeyExt( "sae_msg_uninstall_started" ) );
			w.saeCleanFixed = SAE_CleanEverything( w );
			w.saeCleanPending = true;
			w.saeCleanReported = false;
		}
	}
	return wrappedMethod( groupId, optionName, optionValue );
}

@wrapMethod(W3PlayerWitcher)
function OnPlayerTickTimer( deltaTime : float )
{
	var fixed : int;

	saeTickAcc += deltaTime;
	// a cleanup started from the options reports back as soon as the game runs again
	if( ( saeTickAcc >= 3.0 || saeCleanPending ) && inv )
	{
		saeTickAcc = 0.0;
		if( SAE_UninstallMode() )
		{
			fixed = SAE_CleanEverything( this );
			if( saeCleanPending )
			{
				fixed += saeCleanFixed;
				saeCleanPending = false;
				saeCleanFixed = 0;
			}
			if( fixed > 0 )
			{
				SAE_Notify( "sae_msg_cleaned" );
				saeCleanReported = true;
			}
			else if( !saeCleanReported )
			{
				SAE_Notify( "sae_msg_ready" );
				saeCleanReported = true;
			}
		}
		else
		{
			saeCleanPending = false;
			saeCleanReported = false;
		}
	}
	return wrappedMethod( deltaTime );
}
