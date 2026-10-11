// Sockets and Enchantments - cheats: every word unlocked, runewright panel in the main menu.

// --- every word unlocked -------------------------------------------------------------------

// the words of the requested kinds, read from the recipes (runewords, glyphwords or both)
function SAE_WordsOfType( addRuneword : bool, addGlyphword : bool, out list : array<name> )
{
	var words : array<name>;
	var i : int;

	list.Clear();
	SAE_Words( words );
	for( i = 0; i < words.Size(); i += 1 )
	{
		if( StrStartsWith( NameToString( words[i] ), "Runeword" ) )
		{
			if( addRuneword )
				list.PushBack( words[i] );
		}
		else if( addGlyphword )
			list.PushBack( words[i] );
	}
}

// the runewright offers only the words of their level; with the cheat it offers all of them
@wrapMethod(W3CraftsmanComponent)
function GetEnchanterItems( addRuneword : bool, addGlyphword : bool ) : array< CName >
{
	var list : array<name>;

	if( !SAE_AllWordsUnlocked() )
		return wrappedMethod( addRuneword, addGlyphword );
	SAE_WordsOfType( addRuneword, addGlyphword, list );
	return list;
}

// without a runewright the game loads only part of the recipes: here it loads all of them
@wrapMethod(W3EnchantmentManager)
function Init( masterComp : W3CraftsmanComponent )
{
	var words : array<name>;

	if( masterComp )
	{
		wrappedMethod( masterComp );
		return;
	}
	craftMasterComp = NULL;
	SAE_Words( words );
	LoadSchematicsXMLData( words );
}

// --- runewright panel in the main menu -----------------------------------------------------

@wrapMethod(CR4CommonMenu)
function DefineMenuStructure()
{
	wrappedMethod();
	if( !isCiri && SAE_EnchantAnywhere() && !HasMenuDefined( 'EnchantingMenu' ) )
		DefineMenuItem( 'EnchantingMenu', "panel_title_enchanting" );
}

// The game's panel closes when there is no runewright. This is the game's own function with one
// difference: opened from the main menu (no runewright) it stays open and offers every word.
@replaceMethod(CR4EnchantingMenu)
function OnConfigUI()
{
	var initData		   : IScriptable;
	var inventoryInitData  : W3InventoryInitData;
	var enchanterEntity	   : CGameplayEntity;
	var currentFilters	   : SEnchantmentFilters;
	var pinnedTag		   : int;

	super.OnConfigUI();

	m_notEnoughSlots = false;
	m_readonly = false;
	initData = GetMenuInitData();
	inventoryInitData = (W3InventoryInitData)initData;

	m_playerInventory = thePlayer.GetInventory();
	m_playerInvComponent = new W3GuiEnchantingInventoryComponent in this;
	m_playerInvComponent.Initialize( m_playerInventory );

	m_tooltipDataProvider = new W3TooltipComponent in this;
	m_tooltipDataProvider.initialize(m_playerInventory, m_flashValueStorage);
	m_tooltipDataProvider.setCurrentInventory(m_playerInventory);

	m_definitionsManager = theGame.GetDefinitionsManager();
	m_fxEnableRemovingEnchantment = m_flashModule.GetMemberFlashFunction("enableRemovingEnchantment");
	m_fxEnableEnchantment = m_flashModule.GetMemberFlashFunction("enableEnchantment");
	m_fxSetFilters = m_flashModule.GetMemberFlashFunction("setFiltersData");
	m_fxSetLocalization = m_flashModule.GetMemberFlashFunction("setLocalization");

	m_fxStartApplying = m_flashModule.GetMemberFlashFunction("startEnchanting");
	m_fxStartRemoving = m_flashModule.GetMemberFlashFunction("startRemovingEnchantments");

	m_fxSelectFirstEnchantment = m_flashModule.GetMemberFlashFunction("selectFirstEnchantment");
	m_fxSetPinnedRecipe = m_flashModule.GetMemberFlashFunction("setPinnedRecipe");

	if (inventoryInitData)
	{
		enchanterEntity = inventoryInitData.containerNPC;
	}
	else
	{
		enchanterEntity = (CGameplayEntity)initData;
	}

	if (!enchanterEntity && !SAE_EnchantAnywhere())
	{
		CloseMenu();
	}

	if (enchanterEntity)
	{
		m_enchanterNpc = (CNewNPC)enchanterEntity;
		m_enchanterInventory = enchanterEntity.GetInventory();
		if (m_enchanterNpc)
			m_craftsmanComponent = (W3CraftsmanComponent)m_enchanterNpc.GetComponentByClassName( 'W3CraftsmanComponent' );
	}
	m_tooltipDataProvider.setCrafter(m_craftsmanComponent);

	m_enchantmentManager = new W3EnchantmentManager in this;
	m_enchantmentManager.Init(m_craftsmanComponent);

	if (m_craftsmanComponent)
	{
		m_runewordsList = m_craftsmanComponent.GetEnchanterItems(true, false);
		m_glyphwordsList = m_craftsmanComponent.GetEnchanterItems(false, true);
		m_allWordsList = m_craftsmanComponent.GetEnchanterItems(true, true);
	}
	else
	{
		SAE_WordsOfType( true, false, m_runewordsList );
		SAE_WordsOfType( false, true, m_glyphwordsList );
		SAE_WordsOfType( true, true, m_allWordsList );
	}

	populateData();

	currentFilters = theGame.GetGuiManager().GetEnchantmentFilters();

	m_fxSetLocalization.InvokeSelfFiveArgs( FlashArgString(GetLocStringByKeyExt("gui_panel_filter_has_ingredients")),
									FlashArgString(GetLocStringByKeyExt("gui_panel_filter_elements_missing")),
									FlashArgString(GetLocStringByKeyExt("panel_enchanting_filter_level_1_enchant")),
									FlashArgString(GetLocStringByKeyExt("panel_enchanting_filter_level_2_enchant")),
									FlashArgString(GetLocStringByKeyExt("panel_enchanting_filter_level_3_enchant")) );

	m_fxSetFilters.InvokeSelfFiveArgs( FlashArgBool(currentFilters.showHasIngredients),
									   FlashArgBool(currentFilters.showMissingIngredients),
									   FlashArgBool(currentFilters.showLevel1),
									   FlashArgBool(currentFilters.showLevel2),
									   FlashArgBool(currentFilters.showLevel3) );

	pinnedTag = NameToFlashUInt(theGame.GetGuiManager().PinnedCraftingRecipe);
	m_fxSetPinnedRecipe.InvokeSelfOneArg(FlashArgUInt(pinnedTag));

	populateItemList();
	UpdateMerchantData();
}
