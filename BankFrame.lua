local addonName, T = ...
local DB = _G[addonName.."_DB"]
local GB = _G[addonName.."_Guild"]
local WB = _G[addonName.."_Warband"]
local L = _G[addonName.."_Locale"].Text

local TabType = {
	Bank = "BANK",
	Inventory = "INVENTORY",
	Guild = "GUILD",
	Warband = "WARBAND",
}
L.TabType = {
	BANK = BANK,
	INVENTORY = INVENTORY_TOOLTIP,
	GUILD = GUILD_BANK,
	WARBAND = ACCOUNT_BANK_PANEL_TITLE,
}
local INVENTORY_FAKE_BAGID = -1

-- participate in synchronized inventory search
tinsert(ITEM_SEARCHBAR_LIST, "GFW_BankItemSearchBox")

------------------------------------------------------
-- support for implementations further down
------------------------------------------------------

local function MakeBankType(player, realm, type)
	local list = {player, realm, type}
	return table.concat(list, "|")
end

local function SplitBankType(bankType)
	if not bankType then return end
	return strsplit("|", bankType)
end

local function CompareCharacters(a, b)
	local aName, aRealm = strsplit("|", a)
	if aRealm == T.Realm and aName == T.Player then
		return true -- current player always first
	end
	local bName, bRealm = strsplit("|", b)
	if (aRealm == T.Realm) ~= (bRealm == T.Realm) then
		return aRealm == T.Realm -- current realm always first
	end
	
	local aData = DB[aRealm][aName]
	local bData = DB[bRealm][bName]
	return aData.updated > bData.updated
end

local function CompareGuilds(a, b)
	local aName, aRealm = strsplit("|", a)
	if aRealm == T.Realm and aName == T.Guild then
		return true -- current guild always first
	end
	
	local bName, bRealm = strsplit("|", b)
	if (aRealm == T.Realm) ~= (bRealm == T.Realm) then
		return aRealm == T.Realm -- current realm always first
	end
	
	local aData = GB[aRealm][aName]
	local bData = GB[bRealm][bName]
	return aData.updated > bData.updated
end

local function DisplayName(name, realmName)
	local displayName = name
	if realmName ~= T.Realm then
		displayName = L.PlayerRealm:format(name, realmName)
	end
	return displayName
end

local function ItemFiltered(itemLink, pattern)
	if pattern == "" then return false end
	
	-- quick match for title we always have
	local _, _, displayText = LinkUtil.ExtractLink(itemLink)
	local matches = strfind(strlower(displayText), pattern, 1, true)
	if matches then return not matches end

	-- extra/slower match for tooltip text the client might not have
	local data = C_TooltipInfo.GetHyperlink(itemLink)
	if data then
		for _, line in pairs(data.lines) do
			local text = strlower(line.leftText.." "..(line.rightText or ""))
			if strfind(text, pattern, 1, true) then
				-- print(line.leftText, line.rightText, pattern)
				matches = true
				break
			end
		end
	end
	return not matches
end

-- so we can use code from BankFrame without duplicating it
-- (or inheriting, because that'd do things we don't want)
local function DeriveMixinMembers(derivedMixin, sourceMixin, memberNames)
	for _, memberName in pairs(memberNames) do
		derivedMixin[memberName] = sourceMixin[memberName]
	end
end
------------------------------------------------------
-- Below here is customized Blizz BankFrame.lua code
------------------------------------------------------

GFW_BankFrameMixin = CreateFromMixins(CallbackRegistryMixin);
DeriveMixinMembers(GFW_BankFrameMixin, BankFrameMixin, {
	"UpdateWidthForSelectedTab",
	"GetActiveBankType",
})


function GFW_BankFrameMixin:OnLoad()
	CallbackRegistryMixin.OnLoad(self);

	local titleText = L.AddonVersion:format(T.Title, T.Version)
	self:SetTitle(titleText)

	TabSystemOwnerMixin.OnLoad(self);
	self:InitializeTabSystem();
end

function GFW_BankFrameMixin:InitializeTabSystem()
	self.TabSystem.minTabWidth = self.TabSystem.minTabWidth + 16
	self:SetTabSystem(self.TabSystem);
	self:GenerateTabs();
end

function GFW_BankFrameMixin:GenerateTabs()
	
	local id
	self.TabIDToBankType = {}
	-- TODO currency as own tab, or bank-bag tab in inventory?
	
	for _, tabType in pairs({TabType.Bank, TabType.Inventory, TabType.Guild, TabType.Warband}) do
		local id = self:AddNamedTab(L.TabType[tabType], self.BankPanel)
		self.TabIDToBankType[id] = tabType
	end
end

function GFW_BankFrameMixin:UpdateTabIndicators()
	for tabID, tabType in pairs(self.TabIDToBankType) do
		local button = self.TabSystem:GetTabButton(tabID)
		if not button.SearchHighlight then
			button.SearchHighlight = CreateFrame("Frame", nil, button)
			button.SearchHighlight:SetPoint("RIGHT", button.Text)
			button.SearchHighlight:SetSize(16, 16)
			
			button.SearchHighlight.Icon = button.SearchHighlight:CreateTexture()
			button.SearchHighlight.Icon:SetAllPoints()
			button.SearchHighlight.Icon:SetAtlas("UI-HUD-MicroMenu-Communities-Icon-Notification")
			
			-- tooltip indicating which players/guilds have matches
			button.SearchHighlight:SetScript("OnEnter", function(frame)
				local matches = {} -- invert unique-key -> true table
				for entryData in pairs(frame.matches) do
					tinsert(matches, entryData)
				end
				if tabType == TabType.Guild then
					sort(matches, CompareGuilds)
				else
					sort(matches, CompareCharacters)
				end
				
				GameTooltip:SetOwner(frame, "ANCHOR_BOTTOMRIGHT")
				GameTooltip:SetText(KBASE_SEARCH_RESULTS)
				for _, entryData in pairs(matches) do
					local text = DisplayName(SplitBankType(entryData))
					GameTooltip_AddHighlightLine(GameTooltip, text)
				end
				GameTooltip:Show()
			end)
			button.SearchHighlight:SetScript("OnLeave", GameTooltip_Hide)
		end
		if self.BankPanel.matchingTabTypes[tabType] then
			button.SearchHighlight:Show()
			button.SearchHighlight.tabType = tabType
			button.SearchHighlight.matches = self.BankPanel.matchingTabTypes[tabType]
		else
			button.SearchHighlight:Hide()
			button.SearchHighlight.matches = nil
		end
	end
end

function GFW_BankFrameMixin:SetTab(tabID)
	local bankType = self.BankPanel:BankTypeForTabType(self.TabIDToBankType[tabID])
	self.BankPanel:SetBankType(bankType);
	TabSystemOwnerMixin.SetTab(self, tabID);
	self:UpdateWidthForSelectedTab();
end

function GFW_BankFrameMixin:SelectDefaultTab()
	for _index, tabID in ipairs(self:GetTabSet()) do
		if self.TabIDToBankType[tabID] == TabType.Bank then
			self:SetTab(tabID)
			return
		end
	end
end

function GFW_BankFrameMixin:OnShow()
	CallbackRegistrantMixin.OnShow(self);
	self:SelectDefaultTab();
end

function GFW_BankFrameMixin:OnHide()
	CallbackRegistrantMixin.OnHide(self);
end

GFW_BankPanelSystemMixin = {};
DeriveMixinMembers(GFW_BankPanelSystemMixin, BankPanelSystemMixin, {
	"GetActiveBankType"
})

function GFW_BankPanelSystemMixin:GetBankPanel()
	return GFW_BankPanel;
end

GFW_BankPanelTabMixin = CreateFromMixins(GFW_BankPanelSystemMixin);
DeriveMixinMembers(GFW_BankPanelTabMixin, BankPanelTabMixin, {
	"OnShow",
	"OnHide",
	"OnEvent",
	"OnEnter",
	"OnLeave",
	"OnNewBankTabSelected",
	"RefreshVisuals",
	"Init",
	"IsSelected",
})

local BANK_PANEL_TAB_EVENTS = {
	"INVENTORY_SEARCH_UPDATE",
};

function GFW_BankPanelTabMixin:OnLoad()
	self:RegisterForClicks("LeftButtonUp","RightButtonUp");

	self:AddDynamicEventMethod(self:GetBankPanel(), GFW_BankPanelMixin.Event.NewBankTabSelected, self.OnNewBankTabSelected);
end

function GFW_BankPanelTabMixin:OnClick(button)
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION);
	self:GetBankPanel():TriggerEvent(GFW_BankPanelMixin.Event.BankTabClicked, self.tabData.ID);
end

function GFW_BankPanelTabMixin:ShowTooltip()
	if not self.tabData then
		return;
	end

	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip_SetTitle(GameTooltip, self.tabData.name, NORMAL_FONT_COLOR);
	GameTooltip:Show();
end

function GFW_BankPanelTabMixin:RefreshSearchOverlay()
	local isFiltered = GFW_BankItemSearchBox:GetText() ~= "" and not self.tabData.hasMatch
	self.SearchOverlay:SetShown(isFiltered);
end

function GFW_BankPanelTabMixin:IsPurchaseTab()
	return false
end

GFW_BankPanelItemButtonMixin = {};
DeriveMixinMembers(GFW_BankPanelItemButtonMixin, BankPanelItemButtonMixin, {
	"OnLeave",
	"OnUpdate",
	"SetBankTabID",
	"GetBankTabID",
	"SetBankType",
	"GetBankType",
	"SetContainerSlotID",
	"GetContainerSlotID",
	"UpdateVisualsForBankType"
})

function GFW_BankPanelItemButtonMixin:OnLoad()
	self:RegisterForClicks("LeftButtonUp", "RightButtonUp");
end

function GFW_BankPanelItemButtonMixin:OnEnter()
	if self.itemInfo then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetHyperlink(self.itemInfo.hyperlink)
	
		if IsModifiedClick("DRESSUP") then
			ShowInspectCursor();
		end
	
		self:SetScript("OnUpdate", GFW_BankPanelItemButtonMixin.OnUpdate);
	elseif self.bankTabID == INVENTORY_FAKE_BAGID then
		local slotName = T.GetInventorySlotInfoByID(self.containerSlotID)
		if slotName then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(_G[slotName])
			-- TODO show profession name for profession tools
		end
	end
end

function GFW_BankPanelItemButtonMixin:OnClick(button)
	if IsModifiedClick() then
		self:OnModifiedClick(button);
		return;
	end
end

function GFW_BankPanelItemButtonMixin:OnModifiedClick()
	if self.itemInfo then
		if HandleModifiedItemClick(self.itemInfo.hyperlink) then
			return;
		end
	end
end

function GFW_BankPanelItemButtonMixin:Init(bankType, bankTabID, containerSlotID)
	self:SetBankType(bankType);
	self:SetBankTabID(bankTabID);
	self:SetContainerSlotID(containerSlotID);
	self:UpdateVisualsForBankType();
	self.isInitialized = true;

	self:Refresh();
end

function GFW_BankPanelItemButtonMixin:UpdateFilter(pattern)
	if not self.itemInfo then return end
	
	-- BUG filter overlay not hiding sometimes
	local isFiltered = ItemFiltered(self.itemInfo.hyperlink, pattern)
	self.itemInfo.isFiltered = isFiltered
	self:SetMatchesSearch(not isFiltered);
	
	if not isFiltered then
		-- print("item match in",self:GetBankTabID())
		local tabData = GFW_BankPanel:GetSelectedTabData()
		if tabData then
			tabData.hasMatch = true
		end
		return true
	end
end

function GFW_BankPanelItemButtonMixin:Refresh()
	self:RefreshItemInfo();

	local itemInfo = self.itemInfo;
	if itemInfo then
		self.icon:SetTexture(itemInfo.iconFileID);
	end
	self.icon:SetShown(itemInfo ~= nil);
	SetItemButtonCount(self, itemInfo and itemInfo.stackCount or 0);

	self:UpdateItemContextMatching();
	local pattern = strlower(GFW_BankItemSearchBox:GetText())
	self:UpdateFilter(pattern)

	local quality = itemInfo and itemInfo.quality;
	local itemID = itemInfo and itemInfo.itemID;
	local isBound = itemInfo and itemInfo.isBound;
	local suppressOverlays = false;
	SetItemButtonQuality(self, quality, itemID, suppressOverlays, isBound);
end

function GFW_BankPanelItemButtonMixin:RefreshItemInfo()
	local who, realm, type = SplitBankType(self.bankType)
	local dbBags
	if type == TabType.Warband then
		dbBags = WB.bags
	elseif type == TabType.Guild and T.Guild then
		-- shouldn't get here if unguilded, should fall into no-info path
		dbBags = GB[realm][who].bags
	else
		dbBags = DB[realm][who].bags
	end
	local dbInfo
	if type == TabType.Inventory and self.bankTabID == INVENTORY_FAKE_BAGID then
		dbInfo = DB[realm][who].equipped[self.containerSlotID]
	else
		dbInfo = dbBags and dbBags[self.bankTabID][self.containerSlotID]
	end
	
	if dbInfo then
		local itemID = GetItemInfoFromHyperlink(dbInfo.l)
		local info = {T.GetItemInfo(itemID)}
		-- if not cached, we'll get UI refresh on GET_ITEM_INFO_RECEIVED
		
		self.itemInfo = {
			hyperlink = dbInfo.l,
			stackCount = dbInfo.c,
			itemID = itemID,
			iconFileID = C_Item.GetItemIconByID(dbInfo.l),
			quality = info and info[3]
		}
	else
		self.itemInfo = nil
	end
end

function GFW_BankPanelItemButtonMixin:UpdateBackgroundForBankType()
	self.Background:ClearAllPoints();
	
	local _, _, type = SplitBankType(self.bankType)
	if type == TabType.Warband then
		self.Background:SetPoint("TOPLEFT", -6, 5);
		self.Background:SetPoint("BOTTOMRIGHT", 6, -7);
		self.Background:SetAtlas("warband-bank-slot", TextureKitConstants.IgnoreAtlasSize);
	elseif type == TabType.Inventory and self.bankTabID == INVENTORY_FAKE_BAGID then
		local slotName, texture = T.GetInventorySlotInfoByID(self.containerSlotID)
		self.Background:SetPoint("TOPLEFT");
		self.Background:SetPoint("BOTTOMRIGHT");
		self.Background:SetTexture(texture)
	else
		self.Background:SetPoint("TOPLEFT");
		self.Background:SetPoint("BOTTOMRIGHT");
		self.Background:SetAtlas("bags-item-slot64", TextureKitConstants.IgnoreAtlasSize);
	end
end

GFW_BankPanelMixin = CreateFromMixins(CallbackRegistryMixin);
DeriveMixinMembers(GFW_BankPanelMixin, BankPanelMixin, {
	"OnShow",
	"MarkDirty",
	"OnUpdate",
	"OnBankTabClicked",
	"OnNewBankTabSelected",
	"GetSelectedTabID",
	"GetTabData",
	"GetSelectedTabData",
	"GetActiveBankType",
	"RefreshHeaderText",
	"RefreshAllItemsForSelectedTab",
	"EnumerateValidItems",
	"FindItemButtonByContainerSlotID",
})
local BankPanelEvents = {
	"ACCOUNT_MONEY",
	"BANK_TABS_CHANGED",
	"BAG_UPDATE",
	"BANK_TAB_SETTINGS_UPDATED",
	"INVENTORY_SEARCH_UPDATE",
	"ITEM_LOCK_CHANGED",
	"PLAYER_MONEY",
	"GET_ITEM_INFO_RECEIVED", -- causes UI refresh to fill in quality colors
	"GUILDBANK_UPDATE_TABS",
	"GUILDBANKBAGSLOTS_CHANGED",
	"UNIT_INVENTORY_CHANGED"
};

GFW_BankPanelMixin:GenerateCallbackEvents(
{
	"BankTabClicked",
	"NewBankTabSelected",
});

function GFW_BankPanelMixin:GetBankContainerFrame()
	return GFW_BankFrame;
end

function GFW_BankPanelMixin:OnLoad()
	CallbackRegistryMixin.OnLoad(self);
	self:AddDynamicEventMethod(self, GFW_BankPanelMixin.Event.BankTabClicked, self.OnBankTabClicked);
	self:AddDynamicEventMethod(self, GFW_BankPanelMixin.Event.NewBankTabSelected, self.OnNewBankTabSelected);

	self.bankTabPool = CreateFramePool("BUTTON", self, "GFW_BankPanelTabTemplate");

	local function BankItemButtonResetter(itemButtonPool, itemButton)
		itemButton.isInitialized = false;
		Pool_HideAndClearAnchors(itemButtonPool, itemButton);
	end
	self.itemButtonPool = CreateFramePool("ItemButton", self, "GFW_BankItemButtonTemplate", BankItemButtonResetter);

	self.selectedTabID = nil;
end

function GFW_BankPanelMixin:OnHide()
	CallbackRegistrantMixin.OnHide(self);
	FrameUtil.UnregisterFrameForEvents(self, BankPanelEvents);

	self.selectedTabID = nil;

	ItemButtonUtil.TriggerEvent(ItemButtonUtil.Event.ItemContextChanged);
end

function GFW_BankPanelMixin:Clean()
	if not self.isDirty then
		return;
	end
		
	local hasItemSlots = self.itemButtonPool:GetNumActive() > 0;
	if hasItemSlots then
		self:RefreshAllItemsForSelectedTab();
	else
		-- Newly purchased bank tabs may need to have item slots generated
		self:GenerateItemSlotsForSelectedTab();
	end
	
	self:UpdateSearchResults()

	self.isDirty = false;
	self:SetScript("OnUpdate", nil);
end

function GFW_BankPanelMixin:OnEvent(event, ...)
	if event == "INVENTORY_SEARCH_UPDATE" then
		self:UpdateSearchResults();
	elseif event == "ACCOUNT_MONEY" or event == "PLAYER_MONEY" then
		self.MoneyFrame:Refresh();
	else
		self:MarkDirty();
	end
end

function GFW_BankPanelMixin:RefreshUpdatedText()
	local who, realm, type = SplitBankType(self.bankType)
	local db
	if type == TabType.Warband then
		db = WB
	elseif type == TabType.Guild and T.Guild then
		-- leave nil if unguilded, fall into updated-never path
		db = GB[realm][who]
	else
		db = DB[realm][who]
	end
	if not db or not db.updated then
		self.UpdatedText:SetText(L.Updated:format(NEVER))
		return
	end
	
	local serverTimeMS = db.updated * 1000 * 1000
	
	local function GetFullDate(dateInfo)
		local weekdayName = CALENDAR_WEEKDAY_NAMES[dateInfo.weekday];
		local monthName = CALENDAR_FULLDATE_MONTH_NAMES[dateInfo.month]
		return weekdayName, monthName, dateInfo.monthDay, dateInfo.year
	end
	
	local calendarDate = C_DateAndTime.GetCalendarTimeFromEpoch(serverTimeMS)
	local dateText = FULLDATE:format(GetFullDate(calendarDate))
	local timeText = GameTime_GetFormattedTime(calendarDate.hour, calendarDate.minute, true)
	local fullDate = FULLDATE_AND_TIME:format(dateText, timeText)
	self.UpdatedText:SetText(L.Updated:format(fullDate))
end

function GFW_BankPanelMixin:RefreshMenu()
	-- "who" can mean character or guild based on tabType
	
	local _, _, tabType = SplitBankType(self.bankType)
	if tabType == TabType.Warband then
		if self.whoMenu then
			self.whoMenu:Hide()
		end
		return
	elseif self.whoMenu then
		self.whoMenu:Show()
	end
		
	-- menu entry for current player character / guild always comes first
	local whoList = {}
	if tabType == TabType.Guild then
		tinsert(whoList, {T.Guild or "", MakeBankType(T.Guild or "", T.Realm)})
	else
		tinsert(whoList, {T.Player, MakeBankType(T.Player, T.Realm)})
	end

	local function listWhoInRealm(realmName, dbRealm, skip)
		if not dbRealm then return end
		for name in pairs(dbRealm) do
			if not (name == skip and realmName == T.Realm) then
				local displayName = name
				if realmName ~= T.Realm then
					displayName = L.PlayerRealm:format(name, realmName)
				end
				tinsert(whoList, {displayName, MakeBankType(name, realmName)})
			end
		end
	end
	
	-- next comes list of other characters/guilds on same realm
	if tabType == TabType.Guild then
		listWhoInRealm(T.Realm, GB[T.Realm], T.Guild)
	else
		listWhoInRealm(T.Realm, DB[T.Realm], T.Player)
	end
	
	-- skip current character/guild and realm to make rest of the list
	local db = DB
	if tabType == TabType.Guild then
		db = GB
	end
	for realmName, dbRealm in pairs(db) do
		if realmName ~= T.Realm then
			listWhoInRealm(realmName, dbRealm)
		end
	end
	if tabType == TabType.Guild then
		sort(whoList, function(a, b)
			CompareGuilds(a[2], b[2])
		end)
	else
		sort(whoList, function(a, b)
			CompareCharacters(a[2], b[2])
		end)
	end
	
	if not self.whoMenu then
		self.whoMenu = CreateFrame("DropdownButton", nil, self, "WowStyle1DropdownTemplate")
		self.whoMenu:SetPoint("BOTTOMLEFT", 2, 3)
		self.whoMenu:SetWidth(180)
	end
	if tabType == TabType.Guild then
		self.whoMenu:SetDefaultText(T.Guild)
	else
		self.whoMenu:SetDefaultText(T.Player)
	end
		
	local function isSelected(entryData)
		-- match playerName|realmName only at start of playerName|realmName|tabType
		return strfind(self.bankType, entryData, 1, true) == 1
	end
	local function setSelected(entryData)
		self:SetBankType(strjoin("|", entryData, tabType))
	end

	-- class colors, faction icons in menu? maybe just faction icons for guilds?
	
	self.whoMenu:SetSelectionTranslator(function(selection)
		if selection.text == "" then
			return GRAY_FONT_COLOR:WrapTextInColorCode(L.NotInGuild:format(T.Player))
		else
			return selection.text
		end
	end)
	
	local searchResults = {}
	for bankTabType, results in pairs(self.matchingTabTypes) do
		for whoRealm in pairs(results) do
			if not searchResults[whoRealm] then
				searchResults[whoRealm] = {}
			end
			tinsert(searchResults[whoRealm], bankTabType)
		end
	end
	
	-- indicator on dropdown button if menu has search results
	if not self.whoMenu.SearchHighlight then
		self.whoMenu.SearchHighlight = CreateFrame("Frame", nil, self.whoMenu)
		self.whoMenu.SearchHighlight:SetPoint("RIGHT", self.whoMenu.Text)
		self.whoMenu.SearchHighlight:SetSize(16, 16)
		
		self.whoMenu.SearchHighlight.Icon = self.whoMenu.SearchHighlight:CreateTexture()
		self.whoMenu.SearchHighlight.Icon:SetAllPoints()
		self.whoMenu.SearchHighlight.Icon:SetAtlas("UI-HUD-MicroMenu-Communities-Icon-Notification")
	end
	if TableHasAnyEntries(searchResults) then
		self.whoMenu.SearchHighlight:Show()
	else
		self.whoMenu.SearchHighlight:Hide()
	end	
	
	self.whoMenu:SetupMenu(function(dropdown, root)
		for _, entry in pairs(whoList) do
			local displayText, entryData = entry[1], entry[2]
			local radio = root:CreateRadio(displayText, isSelected, setSelected, entryData)
			if searchResults[entryData] then
				radio:SetTooltip(function(tooltip, element)
					tooltip:SetText(KBASE_SEARCH_RESULTS)
					if tabType ~= TabType.Guild then
						for _, bankTabType in pairs(searchResults[entryData]) do
							GameTooltip_AddHighlightLine(tooltip, L.TabType[bankTabType])
						end
					end
				end)
			end
			radio:AddInitializer(function(frame, description, menu)
				-- placeholder text for unguilded
				if displayText == "" then
					frame.fontString:SetText(L.NotInGuild:format(T.Player))
					frame.fontString:SetTextColor(GRAY_FONT_COLOR:GetRGBA())
				end
				
				local who, realm = SplitBankType(entryData)
				if realm == T.Realm and (who == T.Player or who == T.Guild) then
					-- highlight logged-in player or their guild
					frame.fontString:SetTextColor(LIGHTBLUE_FONT_COLOR:GetRGBA())
				elseif not isSelected(entryData) then
					-- data not for the current player we can offer to delete
					local deleteButton = MenuTemplates.AttachAutoHideCancelButton(frame)
					deleteButton:SetPoint("RIGHT")
					deleteButton:SetScript("OnClick", function()
						if tabType == TabType.Guild then
							T.AskToDeleteGuild(who, realm)
						else
							T.AskToDeleteCharacter(who, realm)
						end
						menu:Close()
					end)
					MenuUtil.HookTooltipScripts(deleteButton, function(tooltip)
						GameTooltip_SetTitle(tooltip, L.DeleteTooltip);
					end);

				end
				
				if searchResults[entryData] then
					frame.searchResult = frame:AttachTexture()
					frame.searchResult:SetSize(16, 16)
					frame.searchResult:SetPoint("LEFT", frame.fontString, "RIGHT")
					frame.searchResult:SetAtlas("UI-HUD-MicroMenu-Communities-Icon-Notification")
				end
			end)
		end
	end)
end

function GFW_BankPanelMixin:BankTypeForTabType(tabType)
	local currentType = self.bankType
	if tabType == TabType.Bank or tabType == TabType.Inventory then
		-- keep player/realm selected if switching player-specific tab types
		-- otherwise revert to curent player
		local player, realm, type = SplitBankType(currentType)
		if type == TabType.Guild or type == TabType.Warband then
			player = nil
			realm = nil
		end
		return MakeBankType(player or T.Player, realm or T.Realm, tabType)
	elseif tabType == TabType.Guild then
		-- just select current player's guild
		return MakeBankType(T.Guild or "", T.Realm, tabType)
	elseif tabType == TabType.Warband then
		return MakeBankType(tabType, tabType, tabType) -- silly but makes stuff easy
	else
		error("illegal tabType")
	end
end

function GFW_BankPanelMixin:SetBankType(bankType)
	self.bankType = bankType;
	if self:IsShown() then
		self:Reset();
	end
end

function GFW_BankPanelMixin:SelectTab(tabID)
	local alreadySelected = self.selectedTabID == tabID;
	if not alreadySelected then
		self.selectedTabID = tabID;
		self:TriggerEvent(GFW_BankPanelMixin.Event.NewBankTabSelected, tabID);
	end
end

function GFW_BankPanelMixin:RefreshBankPanel()
	self:RefreshUpdatedText()
	
	local noTabSelected = self.selectedTabID == nil;
	if noTabSelected then
		-- TODO display something when we have no bank data in DB
		return;
	end
		
	self:RefreshHeaderText();
	self.MoneyFrame:Refresh()
	self:GenerateItemSlotsForSelectedTab();
end

function GFW_BankPanelMixin:Reset()
	self:FetchPurchasedBankTabData();
	self:SelectFirstAvailableTab();
	self:UpdateSearchResults()
	self:RefreshBankTabs();
	self:RefreshBankPanel();
	self:RefreshMenu()
	ItemButtonUtil.TriggerEvent(ItemButtonUtil.Event.ItemContextChanged);
end

function GFW_BankPanelMixin:SelectFirstAvailableTab()
	local hasPurchasedTabs = self.purchasedBankTabData and #self.purchasedBankTabData > 0;
	if hasPurchasedTabs then
		self:SelectTab(self.purchasedBankTabData[1].ID);
	end
end

local SpecialBags = {
	[BACKPACK_CONTAINER] = { BAG_NAME_BACKPACK, "Interface/Buttons/Button-Backpack-Up" },
	[INVENTORY_FAKE_BAGID] = { BAG_FILTER_EQUIPMENT, "Interface/Icons/inv_shirt_01" }
}
function GFW_BankPanelMixin:FetchPurchasedBankTabData()	
	self.purchasedBankTabData = {}
	
	local who, realm, type = SplitBankType(self.bankType)
	local dbBags
	local first = ITEM_INVENTORY_BANK_BAG_OFFSET + 1
	local last -- set by some tabTypes, otherwise dbBags.last
	if type == TabType.Warband then
		dbBags = WB.bags
	elseif type == TabType.Guild then
		if not T.Guild then
			-- not in a guild, far as we can tell, so leave purchasedBankTabData empty
			return
		end
		first = 1
		dbBags = GB[realm][who].bags
		if not dbBags or not dbBags.last then
			-- haven't seen guild bank
			return
		end
	elseif type == TabType.Inventory then
		first = INVENTORY_FAKE_BAGID
		last = NUM_TOTAL_EQUIPPED_BAG_SLOTS
		dbBags = DB[realm][who].bags
	else
		dbBags = DB[realm][who].bags
	end
	for bagID = first, last or dbBags.last do
		local bag
		if type == TabType.Inventory and bagID == INVENTORY_FAKE_BAGID then
			bag = DB[realm][who].equipped
		else
			bag = dbBags[bagID]
		end
		if bag then
			local name = bag.link -- is just a name if a bank tab
			local icon = bag.icon
			if not name and type == TabType.Inventory then
				local info = SpecialBags[bagID]
				if info then
					name, icon = unpack(info)
				end
			elseif not icon then
				icon = C_Item.GetItemIconByID(bag.link)
			end 
			local data = {
				ID = bagID,
				name = name,
				icon = icon,
				slots = bag.count
			}
			tinsert(self.purchasedBankTabData, data)
		end
	end

end

function GFW_BankPanelMixin:RefreshBankTabs()
	self.bankTabPool:ReleaseAll();

	-- TODO handle restricted guild bank tabs?
	local lastBankTab;
	if self.purchasedBankTabData then
		for index, bankTabData in ipairs(self.purchasedBankTabData) do
			local newBankTab = self.bankTabPool:Acquire();

			if lastBankTab == nil then
				newBankTab:SetPoint("TOPLEFT", self, "TOPRIGHT", 2, -25);
			else
				newBankTab:SetPoint("TOPLEFT", lastBankTab, "BOTTOMLEFT", 0, -17);
			end
			
			newBankTab:Init(bankTabData);
			newBankTab:Show();
			
			lastBankTab = newBankTab;
		end
	end
end

function GFW_BankPanelMixin:GenerateItemSlotsForSelectedTab()
	self.itemButtonPool:ReleaseAll();

	if not self.selectedTabID then
		return;
	end

	local tabData = self:GetSelectedTabData()
	if not tabData then return end
	
	-- TODO different layouts for equipped, bags
	
	-- bigger todo later: combine multiple bags on one panel 

	local numRows = 7;
	local numSubColumns = 2;
	local lastColumnStarterButton;
	local lastCreatedButton;
	local currentColumn = 1;
	for containerSlotID = 1, tabData.slots do
		local button = self.itemButtonPool:Acquire();
			
		local isFirstButton = containerSlotID == 1;
		local needNewColumn = (containerSlotID % numRows) == 1;
		if isFirstButton then
			local xOffset, yOffset = 26, -63;
			button:SetPoint("TOPLEFT", self, "TOPLEFT", currentColumn * xOffset, yOffset);
			lastColumnStarterButton = button;
		elseif needNewColumn then
			currentColumn = currentColumn + 1;

			local xOffset, yOffset = 8, 0;
			-- We reached the last subcolumn, time to add space for a new "big" column
			local startNewBigColumn = (currentColumn % numSubColumns == 1);
			if startNewBigColumn then
				xOffset = 19;
			end
			button:SetPoint("TOPLEFT", lastColumnStarterButton, "TOPRIGHT", xOffset, yOffset);
			lastColumnStarterButton = button;
		else
			local xOffset, yOffset = 0, -10;
			button:SetPoint("TOPLEFT", lastCreatedButton, "BOTTOMLEFT", xOffset, yOffset);
		end
		
		button:Init(self.bankType, self.selectedTabID, containerSlotID);
		button:Show();

		lastCreatedButton = button;
	end
end

function GFW_BankPanelMixin:UpdateSearchResults()
	local pattern = strlower(GFW_BankItemSearchBox:GetText())
	
	-- will searches be slow? do them as background tasks somehow? debounce input?
	
	local function BagContainsMatch(bagData, pattern)
		for slot = 1, (bagData.count or 0) do
			local bagItemInfo = bagData[slot]
			if bagItemInfo and not ItemFiltered(bagItemInfo.l, pattern) then
				return true
			end
		end
	end

	local function BagCollection(who, realm, tabType)
		if tabType == TabType.Warband then
			return WB.bags
		elseif tabType == TabType.Guild then
			-- empty if unguilded
			return who and GB[realm][who].bags or {}
		else
			return DB[realm][who].bags
		end
	end
			
	local function ContainsMatch(pattern, who, realm, tabType)
		if tabType == TabType.Inventory and BagContainsMatch(DB[realm][who].equipped, pattern) then
			return true
			-- print("match in equipped")
			-- no need to check bags if match in equipped 
		else
			local dbBags = BagCollection(who, realm, tabType)
			local first, last
			if tabType == TabType.Inventory then
				first = 0
				last = NUM_TOTAL_EQUIPPED_BAG_SLOTS
			elseif tabType == TabType.Guild then
				first = 1
			else
				first = ITEM_INVENTORY_BANK_BAG_OFFSET + 1
			end
			for bagID = first, last or dbBags.last do
				local dbBag = dbBags[bagID]
				if dbBag and BagContainsMatch(dbBag, pattern) then
					return true
					-- print("match in", bagID, tabType)
					-- stop at first matching bag
					-- only need to know if at least one match in this tabType
				end
			end
		end
	end
	
	self.matchingTabTypes = {}
	local function AddMatch(tabType, who, realm)
		if not self.matchingTabTypes[tabType] then
			self.matchingTabTypes[tabType] = {}
		end
		if tabType == TabType.Warband then 
			return -- no further match data for this tab
		end
		local match = MakeBankType(who, realm)
		self.matchingTabTypes[tabType][match] = true
	end
	
	-- search non-selected tabTypes and players/guilds (selected needs deeper search)
	local currentWho, currentRealm, currentTabType = SplitBankType(self.bankType)
	if pattern ~= "" then
		-- first loop over non-selected guilds 
		for searchRealm, dbRealm in pairs(GB) do
			for searchGuild, dbGuild in pairs(dbRealm) do
				if not (searchRealm == currentRealm and searchGuild == currentWho and currentTabType == TabType.Guild) then
					if ContainsMatch(pattern, searchGuild, searchRealm, TabType.Guild) then
						AddMatch(TabType.Guild, searchGuild, searchRealm)
					end
				end
			end
		end
		
		-- loop over non-selected players for TabType.Inventory, TabType.Bank
		for searchRealm, dbRealm in pairs(DB) do
			for searchCharacter, dbCharacter in pairs(dbRealm) do
				for _, tabType in pairs({TabType.Inventory, TabType.Bank}) do
					if not (searchRealm == currentRealm and searchCharacter == currentWho and currentTabType == tabType) then
						if ContainsMatch(pattern, searchCharacter, searchRealm, tabType) then
							AddMatch(tabType, searchCharacter, searchRealm)
						end
					end
				end
			end
		end
		
		-- check warband only once 
		-- (unless it's selected tabType, then we search it further below)
		if currentTabType ~= TabType.Warband then
			if ContainsMatch(pattern, "", "", TabType.Warband) then
				AddMatch(TabType.Warband)
			end
		end
	end
	
	-- search inactive bank/bag tabs in current type+realm+player/guild
	local dbBags = BagCollection(currentWho, currentRealm, currentTabType)
	for _, tabData in ipairs(self.purchasedBankTabData) do
		tabData.hasMatch = nil
		if pattern ~= "" and tabData.ID ~= self:GetSelectedTabID() then
			local dbBag = dbBags[tabData.ID]
			if currentTabType == TabType.Inventory and bagID == INVENTORY_FAKE_BAGID then
				dbBag = DB[currentRealm][currentWho].equipped
			end
			assert(dbBag)
			if BagContainsMatch(dbBag, pattern) then
				tabData.hasMatch = true
				AddMatch(currentTabType, currentWho, currentRealm)
				-- print("match in",tabData.ID)
			end
		end
	end
	
	-- search active bank/bag tab by item slots
	for itemButton in self:EnumerateValidItems() do
		if itemButton.itemInfo then
			if itemButton:UpdateFilter(pattern) and pattern ~= "" then
				AddMatch(currentTabType, currentWho, currentRealm)
			end
		end
	end

	-- show indicators on tabs
	self:GetBankContainerFrame():UpdateTabIndicators()
	self:RefreshMenu()
end

GFW_BankPanelMoneyFrameMixin = CreateFromMixins(GFW_BankPanelSystemMixin);
DeriveMixinMembers(GFW_BankPanelMoneyFrameMixin, BankPanelMoneyFrameMixin, {
	"OnShow",
})

function GFW_BankPanelMoneyFrameMixin:OnEnter()
	
	local who, realm, type = SplitBankType(self:GetActiveBankType())
	if type == TabType.Warband or type == TabType.Guild then
		-- nothing to total in warband
		-- doesn't really make sense to total up different guilds
		return
	end

	local function AddMoneyLine(name, money)
		local moneyText = GetMoneyString(money, true)
		GameTooltip_AddColoredDoubleLine(GameTooltip, name, moneyText, NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR)
	end
	
	-- collect money per character
	local lines = {}
	local total = 0
	for realmName, dbRealm in pairs(DB) do
		for characterName, dbCharacter in pairs(dbRealm) do
			local displayName = characterName
			if realmName ~= T.Realm then
				displayName = L.PlayerRealm:format(characterName, realmName)
			end
			tinsert(lines, {displayName, dbCharacter.money})
			total = total + dbCharacter.money
		end
	end
	
	-- sort by money descending
	sort(lines, function(a, b) return a[2] > b[2] end)

	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM");
	AddMoneyLine(TOTAL, total)
	for index, line in pairs(lines) do
		AddMoneyLine(line[1], line[2])
		-- TODO use number font and make it line up somehow
		-- also GetMoneyString has no option to show zero copper, which also makes alignment hard
	end
	GameTooltip:Show();

end

function GFW_BankPanelMoneyFrameMixin:OnLeave()
	GameTooltip_Hide();
end

function GFW_BankPanelMoneyFrameMixin:Refresh()
	if not self:IsShown() then
		return;
	end

	self.MoneyDisplay:Refresh();
end

GFW_BankPanelMoneyFrameMoneyDisplayMixin = CreateFromMixins(GFW_BankPanelSystemMixin);

DeriveMixinMembers(GFW_BankPanelMoneyFrameMoneyDisplayMixin, BankPanelMoneyFrameMoneyDisplayMixin, {
	"OnLoad",
})

function GFW_BankPanelMoneyFrameMoneyDisplayMixin:DisableMoneyPopupFunctionality()
	-- no clicking buttons for money pickup
	-- no mousing over them either because that breaks parent frame's tooltip
	self:EnableMouse(false)
	self.CopperButton:EnableMouse(false)
	self.SilverButton:EnableMouse(false)
	self.GoldButton:EnableMouse(false)
end

function GFW_BankPanelMoneyFrameMoneyDisplayMixin:Refresh()
	local who, realm, type = SplitBankType(self:GetActiveBankType())
	local db
	if type == TabType.Warband then
		db = WB
	elseif type == TabType.Guild and T.Guild then
		db = GB[realm][who]
	else
		db = DB[realm][who]
	end
	
	MoneyFrame_Update(self:GetName(), db and db.money or 0, true)
end

