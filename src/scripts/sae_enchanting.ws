// Sockets and Enchantments - runewright, tooltip and item crafting.

// --- which items the runewright shows ------------------------------------------------------

// besides swords and chest armor (base game), also gloves, trousers and boots
@wrapMethod(W3GuiEnchantingInventoryComponent)
function ShouldShowItem( item : SItemUniqueId ) : bool
{
	var itemTags : array<name>;

	if( wrappedMethod( item ) )
		return true;
	if( !SAE_IsSmallArmor( _inv, item ) )
		return false;

	// the same checks as the base inventory list
	_inv.GetItemTags( item, itemTags );
	if( itemTags.Contains( theGame.params.TAG_DONT_SHOW ) )
		return false;
	if( _inv.GetEntity() == thePlayer && itemTags.Contains( theGame.params.TAG_DONT_SHOW_ONLY_IN_PLAYERS ) )
		return false;
	return true;
}

// with "Enchant any item, even without 3 sockets" the runewright no longer asks for 3 slots
@wrapMethod(W3GuiEnchantingInventoryComponent)
function CheckSlotsCount( item : SItemUniqueId ) : bool
{
	if( SAE_NoSlotRequirement() )
		return true;
	return wrappedMethod( item );
}

@wrapMethod(W3GuiEnchantingInventoryComponent)
function SetInventoryFlashObjectForItem( item : SItemUniqueId, out flashObject : CScriptedFlashObject )
{
	wrappedMethod( item, flashObject );
	if( SAE_NoSlotRequirement() )
	{
		flashObject.SetMemberFlashBool( "isNotEnoughSockets", false );
		flashObject.SetMemberFlashBool( "disableAction", false );
		flashObject.SetMemberFlashString( "description", "" );
	}
}

// --- enchanting ----------------------------------------------------------------------------

// true if the chosen word is added next to the ones the item already has
function SAE_AddsInsteadOfReplacing( inv : CInventoryComponent, item : SItemUniqueId ) : bool
{
	return SAE_MaxEnchants() != 1 && inv.IsItemEnchanted( item );
}

function SAE_IsFull( inv : CInventoryComponent, item : SItemUniqueId ) : bool
{
	var maxWords : int;

	maxWords = SAE_MaxEnchants();
	return maxWords > 0 && SAE_CountWords( inv, item ) >= maxWords;
}

// text for the maximum reached, with the number in brackets
function SAE_FullText() : string
{
	return GetLocStringByKeyExt( "sae_msg_full" ) + " (" + SAE_MaxEnchants() + ")";
}

function SAE_WordName( word : name ) : string
{
	var schem : SEnchantmentSchematic;

	schem = getEnchantmentSchematicFromName( word );
	return GetLocStringByKeyExt( NameToString( schem.localizedName ) );
}

// sentence added to the removal confirmations when the refund cheat is on
function SAE_RefundNote() : string
{
	if( SAE_RefundOnRemove() )
		return " " + GetLocStringByKeyExt( "sae_refund_note" );
	return "";
}

function SAE_RemoveAllRest() : string
{
	if( SAE_RefundOnRemove() )
		return GetLocStringByKeyExt( "sae_refund_note" ) + " " + GetLocStringByKeyExt( "sae_remove_all_hint" );
	return GetLocStringByKeyExt( "sae_remove_all_rest" );
}

// the same refresh the game does after enchanting
@addMethod(CR4EnchantingMenu)
function SAE_RefreshAfterEnchant( itemId : SItemUniqueId, word : name )
{
	// the list is rebuilt and re-sorted: a selection kept from before could point to another word
	m_selectedEnchantment = '';
	UpdateItemsCounter();
	populateData();
	populateItemList();
	populateEnchantmentsList( itemId );
	populateIngredientsList( getEnchantmentData( word, m_allwordsData ) );
	theGame.GetGuiManager().ShowNotification( GetLocStringByKeyExt( "panel_enchanting_notification_enchant_done" ) + ": " + SAE_WordName( word ) );
	UpdateMerchantData();
	m_playerInventory.NotifyEnhancedItem( itemId );
}

// the same refresh the game does after a removal
@addMethod(CR4EnchantingMenu)
function SAE_RefreshAfterRemove( itemId : SItemUniqueId, message : string )
{
	// the list is rebuilt and re-sorted: a selection kept from before could point to another word
	m_selectedEnchantment = '';
	theGame.GetGuiManager().ShowNotification( message );
	UpdateMerchantData();
	UpdateItemsCounter();
	populateItemList();
	populateEnchantmentsList( itemId );
	m_playerInventory.NotifyEnhancedItem( itemId );
}

// the game's confirmation window, with title and text chosen by the mod
@addMethod(CR4EnchantingMenu)
function SAE_AskConfirm( title : string, text : string, price : float, removing : bool )
{
	m_initDataConfirmation = new EnchantingConfirmationPopupData in this;
	m_initDataConfirmation.menuRef = this;
	m_initDataConfirmation.BlurBackground = true;
	m_initDataConfirmation.removingEnchantment = removing;
	m_initDataConfirmation.SetMessageTitle( title );
	m_initDataConfirmation.SetMessageText( text );
	m_initDataConfirmation.SetPrice( price );
	RequestSubMenu( 'PopupMenu', m_initDataConfirmation );
}

@addMethod(CR4EnchantingMenu)
function SAE_Deny( message : string )
{
	if( message != "" )
		showNotification( message );
	OnPlaySoundEvent( "gui_global_denied" );
}

@wrapMethod(CR4EnchantingMenu)
function OnEnchantItem( itemId : SItemUniqueId, enchantmentName : name )
{
	var schem : SEnchantmentSchematic;
	var runes : array<name>;
	var free, r, wasExtra, ok : bool;
	var oldWord : name;
	var i : int;

	if( SAE_UninstallMode() )
	{
		SAE_Deny( GetLocStringByKeyExt( "sae_msg_uninstall_mode" ) );
		return false;
	}
	free = SAE_FreeEnchant();

	if( !SAE_AddsInsteadOfReplacing( m_playerInventory, itemId ) )
	{
		// main word, as in the game; if the same word was among the extras, it is taken off there
		// so it is not counted twice (and put back if the engine refuses)
		oldWord = m_playerInventory.GetEnchantment( itemId );
		wasExtra = m_playerInventory.ItemHasAbility( itemId, getEnchamtmentStatName( enchantmentName ) ) && oldWord != enchantmentName;
		if( wasExtra )
			m_playerInventory.RemoveItemCraftedAbility( itemId, getEnchamtmentStatName( enchantmentName ) );
		SAE_RunesOf( m_playerInventory, itemId, runes );

		if( !free )
		{
			r = wrappedMethod( itemId, enchantmentName );
			ok = m_playerInventory.GetEnchantment( itemId ) == enchantmentName;
		}
		else
		{
			// without materials: as the game does, but without taking runes and glyphs
			m_playerInventory.UnenchantItem( itemId );
			ok = m_playerInventory.EnchantItem( itemId, enchantmentName, getEnchamtmentStatName( enchantmentName ) );
		}

		if( !ok )
		{
			// the engine refused: the item goes back to how it was
			if( IsNameValid( oldWord ) && !m_playerInventory.IsItemEnchanted( itemId ) )
				m_playerInventory.EnchantItem( itemId, oldWord, getEnchamtmentStatName( oldWord ) );
			if( wasExtra )
				SAE_AddExtra( m_playerInventory, itemId, enchantmentName );
			if( free )
				SAE_Deny( "" );
			return false;
		}

		if( SAE_KeepRunes() )
			SAE_ReturnLostRunes( m_playerInventory, itemId, runes );
		if( free )
			SAE_RefreshAfterEnchant( itemId, enchantmentName );
		return true;
	}

	if( SAE_HasWord( m_playerInventory, itemId, enchantmentName ) )
	{
		SAE_Deny( GetLocStringByKeyExt( "sae_msg_has_word" ) );
		return false;
	}
	if( SAE_IsFull( m_playerInventory, itemId ) )
	{
		SAE_Deny( SAE_FullText() );
		return false;
	}
	if( !m_enchantmentManager.GetSchematic( enchantmentName, schem ) )
	{
		SAE_Deny( "" );
		return false;
	}
	if( !free && !SAE_HasIngredients( m_playerInventory, schem ) )
	{
		SAE_Deny( GetLocStringByKeyExt( "sae_msg_missing_ingredients" ) );
		return false;
	}

	SAE_AddExtra( m_playerInventory, itemId, enchantmentName );
	if( !free )
	{
		for( i = 0; i < schem.ingredients.Size(); i += 1 )
			m_playerInventory.RemoveItemByName( schem.ingredients[i].itemName, schem.ingredients[i].quantity );
	}
	SAE_RefreshAfterEnchant( itemId, enchantmentName );
	return true;
}

// before the confirmation: a full item or a word already applied is reported at once, with the reason;
// a removal says whether it takes off one word or all of them.
// wrappedMethod appears only once per function: the game's compiler rejects a second call.
@wrapMethod(CR4EnchantingMenu)
function OnConfrimAction( itemId : SItemUniqueId, price : float, removing : bool )
{
	var word : name;
	var count : int;

	count = SAE_CountWords( m_playerInventory, itemId );

	if( removing )
	{
		word = m_selectedEnchantment;
		if( IsNameValid( word ) && count > 1 && SAE_HasWord( m_playerInventory, itemId, word ) )
		{
			SAE_AskConfirm( GetLocStringByKeyExt( "sae_remove_one_title" ),
				GetLocStringByKeyExt( "sae_remove_one_text" ) + " " + SAE_WordName( word ) + ". " + GetLocStringByKeyExt( "sae_remove_one_rest" ) + SAE_RefundNote(),
				price, true );
			return true;
		}
		if( count > 1 )
		{
			SAE_AskConfirm( GetLocStringByKeyExt( "sae_remove_all_title" ),
				GetLocStringByKeyExt( "sae_remove_all_text" ) + " (" + count + "). " + SAE_RemoveAllRest(),
				price, true );
			return true;
		}
		if( SAE_RefundOnRemove() )
		{
			SAE_AskConfirm( GetLocStringByKeyExt( "input_remove_enchant" ),
				GetLocStringByKeyExt( "panel_enchanting_popup_message_warning_has_enchant" ) + SAE_RefundNote(),
				price, true );
			return true;
		}
	}

	// item with runes and no enchantment: the game warns that the runes will be destroyed
	if( !removing && SAE_KeepRunes() && !m_playerInventory.IsItemEnchanted( itemId ) && m_playerInventory.GetItemEnhancementCount( itemId ) > 0 )
	{
		SAE_AskConfirm( GetLocStringByKeyExt( "input_enchant_item" ), GetLocStringByKeyExt( "sae_keep_runes_text" ), price, false );
		return true;
	}

	if( !removing && SAE_AddsInsteadOfReplacing( m_playerInventory, itemId ) )
	{
		if( SAE_HasWord( m_playerInventory, itemId, m_selectedEnchantment ) )
		{
			SAE_Deny( GetLocStringByKeyExt( "sae_msg_has_word" ) );
			return false;
		}
		if( SAE_IsFull( m_playerInventory, itemId ) )
		{
			SAE_Deny( SAE_FullText() );
			return false;
		}
		// the word is added, not replaced: the game's warning does not apply
		m_fxStartApplying.InvokeSelf();
		return true;
	}
	return wrappedMethod( itemId, price, removing );
}

// the button stays enabled on a full item, so the click explains why; it is disabled only by
// "Prepare to remove the mod". With the free cheat it is enabled even when runes or glyphs are missing.
@wrapMethod(CR4EnchantingMenu)
function OnSelectEnchantment( EnchantmentName : name )
{
	var r : bool;

	r = wrappedMethod( EnchantmentName );
	if( m_readonly || m_notEnoughSlots || !m_playerInventory.IsIdValid( m_prevItem ) )
		return r;
	if( SAE_UninstallMode() )
		m_fxEnableEnchantment.InvokeSelfThreeArgs( FlashArgBool( false ), FlashArgNumber( 0 ), FlashArgBool( false ) );
	else if( SAE_FreeEnchant() && m_playerInventory.GetEnchantment( m_prevItem ) != EnchantmentName )
		m_fxEnableEnchantment.InvokeSelfThreeArgs( FlashArgBool( true ), FlashArgNumber( 0 ), FlashArgBool( false ) );
	return r;
}

// Remove with an applied word selected in the list: takes off only that word.
// With no selection, or with a word the item does not have: takes off every word, as the game
// does (without giving runes back).
@wrapMethod(CR4EnchantingMenu)
function OnRemoveEnchantment( itemId : SItemUniqueId )
{
	var word : name;
	var count : int;

	var primary : name;
	var r, refund : bool;

	word = m_selectedEnchantment;
	count = SAE_CountWords( m_playerInventory, itemId );
	refund = SAE_RefundOnRemove();
	if( count <= 1 )
	{
		primary = m_playerInventory.GetEnchantment( itemId );
		r = wrappedMethod( itemId );
		if( refund && IsNameValid( primary ) && !m_playerInventory.IsItemEnchanted( itemId ) )
			SAE_Refund( m_playerInventory, primary );
		return r;
	}

	if( IsNameValid( word ) && SAE_HasWord( m_playerInventory, itemId, word ) )
	{
		if( !SAE_RemoveWord( m_playerInventory, itemId, word ) )
		{
			SAE_Deny( "" );
			return false;
		}
		if( refund )
			SAE_Refund( m_playerInventory, word );
		SAE_RefreshAfterRemove( itemId, GetLocStringByKeyExt( "sae_msg_removed_one" ) + " " + SAE_WordName( word ) );
		return true;
	}

	primary = m_playerInventory.GetEnchantment( itemId );
	SAE_RemoveExtras( m_playerInventory, itemId, refund );
	m_playerInventory.UnenchantItem( itemId );
	if( refund && IsNameValid( primary ) && !m_playerInventory.IsItemEnchanted( itemId ) )
		SAE_Refund( m_playerInventory, primary );
	SAE_RefreshAfterRemove( itemId, GetLocStringByKeyExt( "sae_msg_removed_all" ) + " (" + count + ")" );
	return true;
}

// in the word list the game highlights only the word the engine keeps: every word the item has
// gets the label "applied".
// Each list entry is matched to its word through the entry's own "name" member, never by position:
// the interface sorts the list it receives, so after the first display the position of an entry no
// longer matches the word list (a position-based label made a click enchant a different word).
function SAE_MarkList( menuInv : CInventoryComponent, item : SItemUniqueId, words : array<CName>, data : CScriptedFlashArray, manager : W3EnchantmentManager )
{
	var schem : SEnchantmentSchematic;
	var listEntry : CScriptedFlashObject;
	var listEntryName : int;
	var label : string;
	var i, j : int;

	if( !data )
		return;
	for( i = 0; i < data.GetLength(); i += 1 )
	{
		listEntry = data.GetElementFlashObject( i );
		listEntryName = listEntry.GetMemberFlashUInt( "name" );
		for( j = 0; j < words.Size(); j += 1 )
		{
			if( NameToFlashUInt( words[j] ) != listEntryName )
				continue;
			if( manager.GetSchematic( words[j], schem ) )
			{
				label = GetLocStringByKeyExt( NameToString( schem.localizedName ) );
				if( menuInv.IsIdValid( item ) && SAE_HasWord( menuInv, item, words[j] ) )
					label += " - " + GetLocStringByKeyExt( "sae_list_applied" );
				listEntry.SetMemberFlashString( "localizedName", label );
			}
			break;
		}
	}
}

@wrapMethod(CR4EnchantingMenu)
function populateEnchantmentsList( itemId : SItemUniqueId )
{
	SAE_MarkList( m_playerInventory, itemId, m_runewordsList, m_runewordsData, m_enchantmentManager );
	SAE_MarkList( m_playerInventory, itemId, m_glyphwordsList, m_glyphwordsData, m_enchantmentManager );
	wrappedMethod( itemId );
}

// --- tooltip ----------------------------------------------------------------------------------

// below the main word, one line for each extra word
@wrapMethod(W3TooltipComponent)
function AddEnchantmentData( itemId : SItemUniqueId, itemInvComponent : CInventoryComponent, out flashDataObj : CScriptedFlashObject )
{
	var extras : array<name>;
	var text : string;
	var i : int;

	wrappedMethod( itemId, itemInvComponent, flashDataObj );

	SAE_GetExtras( itemInvComponent, itemId, extras );
	if( extras.Size() == 0 )
		return;

	text = SAE_WordTooltip( itemInvComponent, itemInvComponent.GetEnchantment( itemId ) );
	for( i = 0; i < extras.Size(); i += 1 )
		text += "<br>" + SAE_WordTooltip( itemInvComponent, extras[i] );
	flashDataObj.SetMemberFlashString( "appliedEnchantmentInfo", text );
}

// --- crafting an upgraded item -------------------------------------------------------------

// the game carries the main word over to the new item; here the extra words come along too
@wrapMethod(W3CraftingManager)
function Craft( schemName : name, out item : SItemUniqueId ) : ECraftingException
{
	var schem : SCraftingSchematic;
	var ids : array<SItemUniqueId>;
	var carry, extras : array<name>;
	var res : ECraftingException;
	var i, j : int;

	if( GetSchematic( schemName, schem ) )
	{
		for( i = 0; i < schem.ingredients.Size(); i += 1 )
		{
			ids = thePlayer.inv.GetItemsByName( schem.ingredients[i].itemName );
			if( ids.Size() > 0 && SAE_IsGear( thePlayer.inv, ids[0] ) )
			{
				SAE_GetExtras( thePlayer.inv, ids[0], extras );
				for( j = 0; j < extras.Size(); j += 1 )
					carry.PushBack( extras[j] );
			}
		}
	}

	res = wrappedMethod( schemName, item );

	if( res == ECE_NoException && carry.Size() > 0 && thePlayer.inv.IsIdValid( item ) )
	{
		for( i = 0; i < carry.Size(); i += 1 )
		{
			if( !SAE_HasWord( thePlayer.inv, item, carry[i] ) )
				SAE_AddExtra( thePlayer.inv, item, carry[i] );
		}
		thePlayer.inv.NotifyEnhancedItem( item );
	}
	return res;
}
