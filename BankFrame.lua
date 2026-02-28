local addonName, T = ...
local DB = _G[addonName.."_DB"]
local L = _G[addonName.."_Locale"].Text

-- participate in synchronized inventory search
tinsert(ITEM_SEARCHBAR_LIST, "GFW_BankItemSearchBox")

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
	-- TODO use tabs and banktype for player/guild/warband
	-- TODO characters in a popup instead because tabs overflow w/ too many chars
	
	self.TabIDToBankType = {}
	
	local id = self:AddNamedTab(T.Player, self.BankPanel)
	self.TabIDToBankType[id] = FULL_PLAYER_NAME:format(T.Player, T.Realm)

	for realmName, dbRealm in pairs(DB) do
		for characterName, dbCharacter in pairs(dbRealm) do
			if not (characterName == T.Player and realmName == T.Realm) then
				local displayName = characterName
				local fullName = FULL_PLAYER_NAME:format(characterName, realmName)
				if realmName ~= T.Realm then
					displayName = fullName
				end
				local id = self:AddNamedTab(displayName, self.BankPanel)
				self.TabIDToBankType[id] = fullName
			end
		end
	end
	
end

function GFW_BankFrameMixin:SetTab(tabID)
	self.BankPanel:SetBankType(self.TabIDToBankType[tabID]);
	TabSystemOwnerMixin.SetTab(self, tabID);
	self:UpdateWidthForSelectedTab();
end

function GFW_BankFrameMixin:UpdateWidthForSelectedTab()
	local tabPage = self:GetElementsForTab(self:GetTab())[1];
	self:SetWidth(tabPage:GetWidth());
	UpdateUIPanelPositions(self);
end

function GFW_BankFrameMixin:RefreshTabVisibility()
	-- TODO? tab per character, maybe we don't need to hide/show
	
	-- for _index, tabID in ipairs(self:GetTabSet()) do
	-- 	self.TabSystem:SetTabShown(tabID, C_Bank.CanViewBank(self.TabIDToBankType[tabID]));
	-- end
end

function GFW_BankFrameMixin:SelectDefaultTab()
	self:SelectFirstAvailableTab();
end

function GFW_BankFrameMixin:SelectFirstAvailableTab()
	for _index, tabID in ipairs(self:GetTabSet()) do
		if self:GetTabButton(tabID):IsShown() then
			self:SetTab(tabID);
			return;
		end
	end
end

function GFW_BankFrameMixin:GetActiveBankType()
	return self.BankPanel:IsShown() and self.BankPanel:GetActiveBankType() or nil;
end

function GFW_BankFrameMixin:OnShow()
	CallbackRegistrantMixin.OnShow(self);
	-- OpenAllBags(self);
	self:RefreshTabVisibility();
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
	-- input bankType is realm-character, which we need for looking up contents
	
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
	
	-- TODO BUG filter overlay not hiding sometimes
	local isFiltered = ItemFiltered(self.itemInfo.hyperlink, pattern)
	self.itemInfo.isFiltered = isFiltered
	self:SetMatchesSearch(not isFiltered);
	
	if not isFiltered then
		-- print("item match in",self:GetBankTabID())
		GFW_BankPanel:GetSelectedTabData().hasMatch = true
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
	local player, realm = strsplit("-", self.bankType)
	local dbCharacterBags = DB[realm][player].bags
	local dbInfo = dbCharacterBags[self.bankTabID][self.containerSlotID]
	
	if dbInfo then
		local itemID = GetItemInfoFromHyperlink(dbInfo.l)
		local info = {T.GetItemInfo(itemID)}
		-- TODO what if info not cached? maybe just include quality in saved DB?
		-- TODO or maybe keep lazy, but update bank frame on client recache
		
		self.itemInfo = {
			hyperlink = dbInfo.l,
			stackCount = dbInfo.c,
			itemID = itemID,
			iconFileID = C_Item.GetItemIconByID(dbInfo.l),
			quality = info[3]
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
	local player, realm = strsplit("-", self.bankType)
	local dbCharacter = DB[realm][player]
	local serverTimeMS = dbCharacter.updated * 1000 * 1000
	
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
	
	local player, realm = strsplit("-", self.bankType)
	
	local dbCharacterBags = DB[realm][player].bags
	for bagID = ITEM_INVENTORY_BANK_BAG_OFFSET + 1, dbCharacterBags.last do
		local bag = dbCharacterBags[bagID]
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
	
	-- TODO special tab(s) for bags, inventory, currency
end

function GFW_BankPanelMixin:GenerateItemSlotsForSelectedTab()
	self.itemButtonPool:ReleaseAll();

	if not self.selectedTabID then
		return;
	end

	local tabData = self:GetSelectedTabData()

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
	local player, realm = strsplit("-", self.bankType)
	local dbCharacterBags = DB[realm][player].bags
	for _, tabData in ipairs(self.purchasedBankTabData) do
		tabData.hasMatch = nil
		if pattern ~= "" and tabData.ID ~= self:GetSelectedTabID() then
			local dbBag = dbCharacterBags[tabData.ID]
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
				displayName = FULL_PLAYER_NAME:format(characterName, realmName)
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
	local player, realm = strsplit("-", self:GetActiveBankType())
	local dbCharacter = DB[realm][player]
	
	MoneyFrame_Update(self:GetName(), dbCharacter.money)
end

