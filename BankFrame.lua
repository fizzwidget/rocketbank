local addonName, T = ...
local DB = _G[addonName.."_DB"]
local WB = _G[addonName.."_Warband"]
local L = _G[addonName.."_Locale"].Text

-- participate in synchronized inventory search
tinsert(ITEM_SEARCHBAR_LIST, "GFW_BankItemSearchBox")

local function MakeBankType(player, realm, type)
	local list = {player, realm, type}
	return table.concat(list, "|")
end

local function SplitBankType(bankType)
	if not bankType then return end
	return strsplit("|", bankType)
end

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
	self.TabIDToBankType[id] = "BANK"
	
	id = self:AddNamedTab(INVENTORY_TOOLTIP, self.BankPanel)
	self.TabIDToBankType[id] = "INVENTORY"
	self.TabSystem:SetTabEnabled(id, false, INVENTORY_TOOLTIP.." not yet implemented")
	
	id = self:AddNamedTab(CURRENCY, self.BankPanel)
	self.TabIDToBankType[id] = "CURRENCY"
	self.TabSystem:SetTabEnabled(id, false, CURRENCY.." not yet implemented")

	id = self:AddNamedTab(GUILD_BANK, self.BankPanel)
	self.TabIDToBankType[id] = "GUILD_BANK"
	self.TabSystem:SetTabEnabled(id, false, GUILD_BANK.." not yet implemented")

	id = self:AddNamedTab(ACCOUNT_BANK_PANEL_TITLE, self.BankPanel)
	self.TabIDToBankType[id] = "WARBAND"
	
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
		if self.TabIDToBankType[tabID] == "BANK" then
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
	if type == "WARBAND" then
		dbBags = WB.bags
	else
		dbBags = DB[realm][who].bags -- who can be guild for guild bank
	end
	local dbInfo = dbBags[self.bankTabID][self.containerSlotID]
	
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
	
	-- TODO revisit this when we support warbank
	--[[
		Notes:
		- ItemButtonMixin's notion of BankType limited to selecting background texture
		- GFW_Bank's notion of BankType is actually Realm-Character pair for DB lookup
	]]
	
	-- if self.bankType == Enum.BankType.Account then
	-- 	self.Background:SetPoint("TOPLEFT", -6, 5);
	-- 	self.Background:SetPoint("BOTTOMRIGHT", 6, -7);
	-- 	self.Background:SetAtlas("warband-bank-slot", TextureKitConstants.IgnoreAtlasSize);
	-- else
		self.Background:SetPoint("TOPLEFT");
		self.Background:SetPoint("BOTTOMRIGHT");
		self.Background:SetAtlas("bags-item-slot64", TextureKitConstants.IgnoreAtlasSize);
	-- end
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

function GFW_BankPanelMixin:CreateCharacterMenu()
	
	local _, _, type = SplitBankType(self.bankType)
	if type == "WARBAND" then
		if self.characterMenu then
			self.characterMenu:Hide()
		end
		return
	elseif self.characterMenu then
		self.characterMenu:Show()
		-- this list should be constant within session, so only create it once
		return
	end
		
	-- menu entry for current player character always comes first
	self.characterList = { {T.Player, MakeBankType(T.Player, T.Realm)} }
	
	local function listCharactersInRealm(realmName, dbRealm)
		for characterName in pairs(dbRealm) do
			if not (characterName == T.Player and realmName == T.Realm) then
				local displayName = characterName
				if realmName ~= T.Realm then
					displayName = L.PlayerRealm:format(characterName, realmName)
				end
				tinsert(self.characterList, {displayName, MakeBankType(characterName, realmName)})
			end
		end
	end
	
	-- next comes list other characters on same realm
	local dbRealm = DB[T.Realm]
	listCharactersInRealm(T.Realm, dbRealm)
	
	-- skip current player character and realm to make rest of the list
	for realmName, dbRealm in pairs(DB) do
		if realmName ~= T.Realm then
			listCharactersInRealm(realmName, dbRealm)
		end
	end
		
	self.characterMenu = CreateFrame("DropdownButton", nil, self, "WowStyle1DropdownTemplate")
	self.characterMenu:SetDefaultText(T.Player)
	self.characterMenu:SetPoint("BOTTOMLEFT", 2, 3)
	self.characterMenu:SetWidth(180)
	
	local function isSelected(characterInfo)
		-- match playerName|realmName only at start of playerName|realmName|tabType
		return strfind(self.bankType, characterInfo, 1, true) == 1
		-- 		local selectedPlayer, selectedRealm = SplitBankType(characterInfo)
		-- local player, realm = SplitBankType(self.bankType)
		-- return selectedRealm == realm and selectedPlayer == player
	end
	local function setSelected(characterInfo)
		self:SetBankType(strjoin("|", characterInfo, "BANK"))
	end
	-- TODO don't do the convenience version; use AddInitializer to highlight search results
	MenuUtil.CreateRadioMenu(self.characterMenu, isSelected, setSelected, unpack(self.characterList))

end

function GFW_BankPanelMixin:BankTypeForTabType(tabType)
	local currentType = self.bankType
	if tabType == "BANK" or tabType == "INVENTORY" or tabType == "CURRENCY" then
		-- try to select same player/realm as previous tab
		local player, realm, type = SplitBankType(currentType)
		if type == "GUILD_BANK" then
			player = nil
		end
		if type == "WARBAND" then
			player = nil
			realm = nil
		end
		return MakeBankType(player or T.Player, realm or T.Realm, tabType)
	elseif tabType == "GUILD_BANK" then
		-- try to select same guild/realm as previous tab
		local guild, realm = SplitBankType(currentType)
		local guildName = GetGuildInfo("player") -- can return nil if too soon
		if type ~= "GUILD_BANK" then
			guild = nil
		end
		if type == "WARBAND" then
			guild = nil
			realm = nil
		end
		return MakeBankType(guild or guildName, realm or T.Realm, tabType)
	elseif tabType == "WARBAND" then
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
	local who, realm, type = SplitBankType(self.bankType)
	local db
	if type == "WARBAND" then
		db = WB
	else
		db = DB[realm][who] -- who can be guild for guild bank
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
	self:CreateCharacterMenu()
	self:RequestTitleRefresh();
	ItemButtonUtil.TriggerEvent(ItemButtonUtil.Event.ItemContextChanged);
end

function GFW_BankPanelMixin:RequestTitleRefresh()
	local bestTitleForBankType = "Fizzwidget " .. T.Title
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
	if type == "WARBAND" then
		dbBags = WB.bags
	else
		dbBags = DB[realm][who].bags -- who can be guild for guild bank
	end
	for bagID = ITEM_INVENTORY_BANK_BAG_OFFSET + 1, dbBags.last do
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
	if type == "WARBAND" then
		dbBags = WB.bags
	else
		dbBags = DB[realm][who].bags -- who can be guild for guild bank
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
	self.CopperButton:SetScript("OnClick", nop);
	self.SilverButton:SetScript("OnClick", nop);
	self.GoldButton:SetScript("OnClick", nop);
end

function GFW_BankPanelMoneyFrameMoneyDisplayMixin:Refresh()
	local who, realm, type = SplitBankType(self:GetActiveBankType())
	local db
	if type == "WARBAND" then
		db = WB
	else
		db = DB[realm][who] -- who can be guild for guild bank
	end
	
	MoneyFrame_Update(self:GetName(), db.money)
end

