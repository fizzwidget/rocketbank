local addonName, T = ...
local DB = _G[addonName.."_DB"]
local GB = _G[addonName.."_Guild"]
local WB = _G[addonName.."_Warband"]
local L = _G[addonName.."_Locale"].Text

local TabType = {
	Bank = "BANK",
	Inventory = "INVENTORY",
	Guild = "GUILD_BANK",
	Warband = "WARBAND",
}

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

------------------------------------------------------
-- Below here is customized Blizz BankFrame.lua code
------------------------------------------------------

GFW_BankFrameMixin = CreateFromMixins(CallbackRegistryMixin);

GFW_BankFrameMixin:GenerateCallbackEvents(
{
	"TitleUpdateRequested",
});

function GFW_BankFrameMixin:OnLoad()
	CallbackRegistryMixin.OnLoad(self);
	self:AddDynamicEventMethod(self, GFW_BankFrameMixin.Event.TitleUpdateRequested, self.OnTitleUpdateRequested);

	TabSystemOwnerMixin.OnLoad(self);
	self:InitializeTabSystem();
end

-- TODO bliz reuse: make this nop, and we can get rid of callback events and custom OnLoad?
function GFW_BankFrameMixin:OnTitleUpdateRequested(titleText)
	self:SetTitle(titleText);
end

-- TODO investigate ways to reuse bliz code without inheriting template/mixin
-- GFW_BankFrameMixin.InitializeTabSystem = BankFrameMixin.InitializeTabSystem etc?
function GFW_BankFrameMixin:InitializeTabSystem()
	self:SetTabSystem(self.TabSystem);
	self:GenerateTabs();
end

function GFW_BankFrameMixin:GenerateTabs()
	
	local id
	self.TabIDToBankType = {}
	
	id = self:AddNamedTab(BANK, self.BankPanel)
	self.TabIDToBankType[id] = TabType.Bank
	
	id = self:AddNamedTab(INVENTORY_TOOLTIP, self.BankPanel)
	self.TabIDToBankType[id] = TabType.Inventory
	self.TabSystem:SetTabEnabled(id, false, INVENTORY_TOOLTIP.." not yet implemented")
	-- TODO equipped, bags, (maybe) currency as bank-bag tabs in inventory

	id = self:AddNamedTab(GUILD_BANK, self.BankPanel)
	self.TabIDToBankType[id] = TabType.Guild

	id = self:AddNamedTab(ACCOUNT_BANK_PANEL_TITLE, self.BankPanel)
	self.TabIDToBankType[id] = TabType.Warband
	
	-- TODO highlight tabs with search results
end

function GFW_BankFrameMixin:SetTab(tabID)
	local bankType = self.BankPanel:BankTypeForTabType(self.TabIDToBankType[tabID])
	self.BankPanel:SetBankType(bankType);
	TabSystemOwnerMixin.SetTab(self, tabID);
	self:UpdateWidthForSelectedTab();
end

function GFW_BankFrameMixin:UpdateWidthForSelectedTab()
	local tabPage = self:GetElementsForTab(self:GetTab())[1];
	self:SetWidth(tabPage:GetWidth());
	UpdateUIPanelPositions(self);
end

function GFW_BankFrameMixin:SelectDefaultTab()
	for _index, tabID in ipairs(self:GetTabSet()) do
		if self.TabIDToBankType[tabID] == TabType.Bank then
			self:SetTab(tabID)
			return
		end
	end
end

function GFW_BankFrameMixin:GetActiveBankType()
	return self.BankPanel:IsShown() and self.BankPanel:GetActiveBankType() or nil;
end

function GFW_BankFrameMixin:OnShow()
	CallbackRegistrantMixin.OnShow(self);
	self:SelectDefaultTab();
end

function GFW_BankFrameMixin:OnHide()
	CallbackRegistrantMixin.OnHide(self);
end

GFW_BankPanelSystemMixin = {};

function GFW_BankPanelSystemMixin:GetBankPanel()
	return GFW_BankPanel;
end

function GFW_BankPanelSystemMixin:GetActiveBankType()
	return self:GetBankPanel():GetActiveBankType();
end

GFW_BankPanelTabMixin = CreateFromMixins(GFW_BankPanelSystemMixin);

local BANK_PANEL_TAB_EVENTS = {
	"INVENTORY_SEARCH_UPDATE",
};

function GFW_BankPanelTabMixin:OnLoad()
	self:RegisterForClicks("LeftButtonUp","RightButtonUp");

	self:AddDynamicEventMethod(self:GetBankPanel(), GFW_BankPanelMixin.Event.NewBankTabSelected, self.OnNewBankTabSelected);
end

function GFW_BankPanelTabMixin:OnShow()
	CallbackRegistrantMixin.OnShow(self);
	FrameUtil.RegisterFrameForEvents(self, BANK_PANEL_TAB_EVENTS);
end

function GFW_BankPanelTabMixin:OnHide()
	CallbackRegistrantMixin.OnHide(self);
	FrameUtil.UnregisterFrameForEvents(self, BANK_PANEL_TAB_EVENTS);
end

function GFW_BankPanelTabMixin:OnEvent(event, ...)
	if event == "INVENTORY_SEARCH_UPDATE" then
		self:RefreshSearchOverlay();
	end
end

function GFW_BankPanelTabMixin:OnClick(button)
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION);
	self:GetBankPanel():TriggerEvent(GFW_BankPanelMixin.Event.BankTabClicked, self.tabData.ID);
end

function GFW_BankPanelTabMixin:OnEnter()
	if not self:IsPurchaseTab() then
		self:ShowTooltip();
	end
end

function GFW_BankPanelTabMixin:ShowTooltip()
	if not self.tabData then
		return;
	end

	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip_SetTitle(GameTooltip, self.tabData.name, NORMAL_FONT_COLOR);
	GameTooltip:Show();
end

function GFW_BankPanelTabMixin:OnLeave()
	GameTooltip_Hide();
end

function GFW_BankPanelTabMixin:OnNewBankTabSelected(tabID)
	self:RefreshVisuals();
end

function GFW_BankPanelTabMixin:RefreshVisuals()
	local enabled = self:IsEnabled();
	self.Icon:SetDesaturated(not enabled);
	self.SelectedTexture:SetShown(enabled and self:IsSelected());
	self:RefreshSearchOverlay();
end

function GFW_BankPanelTabMixin:RefreshSearchOverlay()
	local isFiltered = GFW_BankItemSearchBox:GetText() ~= "" and not self.tabData.hasMatch
	self.SearchOverlay:SetShown(isFiltered);
end

function GFW_BankPanelTabMixin:Init(tabData)
	if not tabData then
		return;
	end

	self.tabData = tabData;
	if self:IsPurchaseTab() then
		self.Icon:SetAtlas("Garr_Building-AddFollowerPlus", TextureKitConstants.UseAtlasSize);
	else
		self.Icon:SetTexture(self.tabData.icon or QUESTION_MARK_ICON);
	end

	self:RefreshVisuals();
end

function GFW_BankPanelTabMixin:IsSelected()
	return self.tabData.ID == self:GetBankPanel():GetSelectedTabID();
end

function GFW_BankPanelTabMixin:IsPurchaseTab()
	return false
end

GFW_BankPanelItemButtonMixin = {};

function GFW_BankPanelItemButtonMixin:OnLoad()
	-- self:RegisterForDrag("LeftButton");
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
	end
end

function GFW_BankPanelItemButtonMixin:OnLeave()
	GameTooltip_Hide();
	ResetCursor();

	self:SetScript("OnUpdate", nil);
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

function GFW_BankPanelItemButtonMixin:OnUpdate()
	if GameTooltip:IsOwned(self) then
		if IsModifiedClick("DRESSUP") then
			ShowInspectCursor();
		else
			ResetCursor();
		end
	end
end

function GFW_BankPanelItemButtonMixin:SetBankTabID(bankTabID)
	self.bankTabID = bankTabID;
end

function GFW_BankPanelItemButtonMixin:GetBankTabID()
	return self.bankTabID;
end

function GFW_BankPanelItemButtonMixin:SetBankType(bankType)
	self.bankType = bankType;
end

function GFW_BankPanelItemButtonMixin:GetBankType()
	return self.bankType;
end 

function GFW_BankPanelItemButtonMixin:Init(bankType, bankTabID, containerSlotID)
	self:SetBankType(bankType);
	self:UpdateVisualsForBankType();
	self:SetBankTabID(bankTabID);
	self:SetContainerSlotID(containerSlotID);
	self.isInitialized = true;

	self:Refresh();
end

function GFW_BankPanelItemButtonMixin:SetContainerSlotID(containerSlotID)
	self.containerSlotID = containerSlotID;
end

function GFW_BankPanelItemButtonMixin:GetContainerSlotID()
	return self.containerSlotID;
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
	local dbInfo = dbBags and dbBags[self.bankTabID][self.containerSlotID]
	
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

function GFW_BankPanelItemButtonMixin:UpdateVisualsForBankType()
	self:UpdateBackgroundForBankType();
end

function GFW_BankPanelItemButtonMixin:UpdateBackgroundForBankType()
	self.Background:ClearAllPoints();
	
	local _, _, type = SplitBankType(self.bankType)
	if type == TabType.Warband then
		self.Background:SetPoint("TOPLEFT", -6, 5);
		self.Background:SetPoint("BOTTOMRIGHT", 6, -7);
		self.Background:SetAtlas("warband-bank-slot", TextureKitConstants.IgnoreAtlasSize);
	else
		self.Background:SetPoint("TOPLEFT");
		self.Background:SetPoint("BOTTOMRIGHT");
		self.Background:SetAtlas("bags-item-slot64", TextureKitConstants.IgnoreAtlasSize);
	end
end

GFW_BankPanelMixin = CreateFromMixins(CallbackRegistryMixin);

local BankPanelEvents = {
	"ACCOUNT_MONEY",
	"BANK_TABS_CHANGED",
	"BAG_UPDATE",
	"BANK_TAB_SETTINGS_UPDATED",
	"INVENTORY_SEARCH_UPDATE",
	"ITEM_LOCK_CHANGED",
	"PLAYER_MONEY",
	"GET_ITEM_INFO_RECEIVED" -- causes UI refresh to fill in quality colors
	-- TODO guild bank refresh events
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

function GFW_BankPanelMixin:OnShow()
	CallbackRegistrantMixin.OnShow(self);
	FrameUtil.RegisterFrameForEvents(self, BankPanelEvents);

	self:Reset();
end

function GFW_BankPanelMixin:OnHide()
	CallbackRegistrantMixin.OnHide(self);
	FrameUtil.UnregisterFrameForEvents(self, BankPanelEvents);

	self.selectedTabID = nil;

	ItemButtonUtil.TriggerEvent(ItemButtonUtil.Event.ItemContextChanged);
end

function GFW_BankPanelMixin:MarkDirty()
	self.isDirty = true;
	self:SetScript("OnUpdate", self.OnUpdate);
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

function GFW_BankPanelMixin:OnUpdate()
	self:Clean();
end

function GFW_BankPanelMixin:SetItemDisplayEnabled(enable)
	if not enable then
		self.itemButtonPool:ReleaseAll();
	end
end

function GFW_BankPanelMixin:SetMoneyFrameEnabled(enable)
	self.MoneyFrame:SetEnabled(enable);
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

function GFW_BankPanelMixin:OnBankTabClicked(clickedTabID)
	self:SelectTab(clickedTabID);
end

function GFW_BankPanelMixin:OnNewBankTabSelected(tabID)
	self:RefreshBankPanel();
end

function GFW_BankPanelMixin:GetSelectedTabID()
	return self.selectedTabID;
end

function GFW_BankPanelMixin:GetTabData(tabID)
	if not self.purchasedBankTabData then
		return;
	end

	for index, tabData in ipairs(self.purchasedBankTabData) do
		if tabData.ID == tabID then
			return tabData;
		end
	end
end

function GFW_BankPanelMixin:GetSelectedTabData()
	return self:GetTabData(self.selectedTabID);
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

	self.whoMenu:SetupMenu(function(dropdown, root)
		for _, entry in pairs(whoList) do
			local displayText, entryData = entry[1], entry[2]
			local element = root:CreateRadio(displayText, isSelected, setSelected, entryData)
			element:AddInitializer(function(frame, description, menu)
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
				
				-- TODO highlight search results
				-- local isSearchResult = true -- TEMP
				if isSearchResult then
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

function GFW_BankPanelMixin:GetActiveBankType()
	return self.bankType;
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
		
	self:SetHeaderEnabled(true);
	self:SetItemDisplayEnabled(true);
	self:SetMoneyFrameEnabled(true);
	self:GenerateItemSlotsForSelectedTab();
end

function GFW_BankPanelMixin:SetHeaderEnabled(enabled)
	self.Header:SetShown(enabled);

	if enabled then
		self:RefreshHeaderText();
	end
end

function GFW_BankPanelMixin:RefreshHeaderText()
	local selectedBankTabData = self:GetTabData(self.selectedTabID);
	self.Header.Text:SetText(selectedBankTabData and selectedBankTabData.name or "");
end

function GFW_BankPanelMixin:Reset()
	self:FetchPurchasedBankTabData();
	self:SelectFirstAvailableTab();
	self:UpdateSearchResults()
	self:RefreshBankTabs();
	self:RefreshBankPanel();
	self:RefreshMenu()
	self:RequestTitleRefresh();
	ItemButtonUtil.TriggerEvent(ItemButtonUtil.Event.ItemContextChanged);
end

function GFW_BankPanelMixin:RequestTitleRefresh()
	local bestTitleForBankType = L.AddonVersion:format(T.Title, T.Version)
	self:GetBankContainerFrame():TriggerEvent(GFW_BankFrameMixin.Event.TitleUpdateRequested, bestTitleForBankType);
end

function GFW_BankPanelMixin:SelectFirstAvailableTab()
	local hasPurchasedTabs = self.purchasedBankTabData and #self.purchasedBankTabData > 0;
	if hasPurchasedTabs then
		self:SelectTab(self.purchasedBankTabData[1].ID);
	end
end

function GFW_BankPanelMixin:FetchPurchasedBankTabData()	
	self.purchasedBankTabData = {}
	
	local who, realm, type = SplitBankType(self.bankType)
	local dbBags
	local first  = ITEM_INVENTORY_BANK_BAG_OFFSET + 1
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
		first = 1
		-- TODO reconsider with inventory tab containing bags + equipped
		dbBags = { DB[realm][who].equipped } -- list of 1 so loop below can index
	else
		dbBags = DB[realm][who].bags
	end
	for bagID = first, dbBags.last do
		local bag = dbBags[bagID]
		if bag then
			local link = bag.link -- is just a name if a bank bag
			local icon = bag.icon or C_Item.GetItemIconByID(link)
			local data = {
				ID = bagID,
				name = link,
				icon = icon,
				slots = bag.count
			}
			tinsert(self.purchasedBankTabData, data)
		end
	end

end

function GFW_BankPanelMixin:RefreshBankTabs()
	self.bankTabPool:ReleaseAll();

	-- List bank tabs first...
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

function GFW_BankPanelMixin:RefreshAllItemsForSelectedTab()
	for itemButton in self:EnumerateValidItems() do
		itemButton:Refresh();
	end
end

function GFW_BankPanelMixin:UpdateSearchResults()
	local pattern = strlower(GFW_BankItemSearchBox:GetText())
			
	-- search inactive tabs only enough to see if there's a match
	local who, realm, type = SplitBankType(self.bankType)
	local dbBags
	if type == TabType.Warband then
		dbBags = WB.bags
	elseif type == TabType.Guild then
		-- nil if unguilded; won't enter loop because purchasedBankTabData empty
		dbBags = T.Guild and GB[realm][who].bags
	else
		dbBags = DB[realm][who].bags
	end
	for _, tabData in ipairs(self.purchasedBankTabData) do
		tabData.hasMatch = nil
		if pattern ~= "" and tabData.ID ~= self:GetSelectedTabID() then
			local dbBag = dbBags[tabData.ID]
			for slot = 1, dbBag.count do
				local bagItemInfo = dbBag[slot]
				if bagItemInfo and not ItemFiltered(bagItemInfo.l, pattern) then
					tabData.hasMatch = true
					-- print("match in",tabData.ID)
					break
				end
			end
		end
	end
	
	-- search active tab by item slots
	for itemButton in self:EnumerateValidItems() do
		if itemButton.itemInfo then
			itemButton:UpdateFilter(pattern)
		end
	end

end

function GFW_BankPanelMixin:EnumerateValidItems()
	return self.itemButtonPool:EnumerateActive();
end

function GFW_BankPanelMixin:FindItemButtonByContainerSlotID(containerSlotID)
	for itemButton in self:EnumerateValidItems() do
		if itemButton:GetContainerSlotID() == containerSlotID then
			return itemButton;
		end
	end
end


GFW_BankPanelMoneyFrameMixin = CreateFromMixins(GFW_BankPanelSystemMixin);

function GFW_BankPanelMoneyFrameMixin:OnShow()
	self:Refresh();
end

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
	end
	GameTooltip:Show();

end

function GFW_BankPanelMoneyFrameMixin:OnLeave()
	GameTooltip_Hide();
end

function GFW_BankPanelMoneyFrameMixin:SetEnabled(enable)
	self:SetShown(enable);
	self:Refresh();
end

function GFW_BankPanelMoneyFrameMixin:Refresh()
	if not self:IsShown() then
		return;
	end

	self:RefreshContents();
end

function GFW_BankPanelMoneyFrameMixin:RefreshContents()
	self.MoneyDisplay:Refresh();
end

GFW_BankPanelMoneyFrameMoneyDisplayMixin = CreateFromMixins(GFW_BankPanelSystemMixin);

function GFW_BankPanelMoneyFrameMoneyDisplayMixin:OnLoad()
	SmallMoneyFrame_OnLoad(self);

	-- We don't want the money popup functionality in the bank panel
	self:DisableMoneyPopupFunctionality();
end

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
	
	MoneyFrame_Update(self:GetName(), db and db.money or 0)
end

