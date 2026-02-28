------------------------------------------------------
-- Addon loading & shared infrastructure
------------------------------------------------------
local addonName, T = ...
_G[addonName] = T

local L = _G[addonName.."_Locale"].Text

T.Title = C_AddOns.GetAddOnMetadata(addonName, "Title")
T.Version = C_AddOns.GetAddOnMetadata(addonName, "Version")

-- event handling
T.EventFrame = CreateFrame("Frame")
T.EventFrame:SetScript("OnEvent", function(self, event, ...)
	local handler = T.EventHandlers[event]
	assert(handler, "Missing event handler for registered event "..event)
	handler(T.EventFrame, ...)
end)
T.EventHandlers = setmetatable({}, {__newindex = function(table, key, value)
	assert(type(value) == 'function', "Members of this table must be functions")
	rawset(table, key, value)
	T.EventFrame:RegisterEvent(key)
end })
local Events = T.EventHandlers

------------------------------------------------------
-- Basic data
------------------------------------------------------

T.Realm = strtrim(GetRealmName())
T.Player = UnitName("player")

------------------------------------------------------
-- Bank preview frame launch conveniences
------------------------------------------------------

function T.ToggleBank()
	if GFW_BankFrame:IsVisible() then
		HideUIPanel(GFW_BankFrame)
	else
		GFW_BankFrame:SetPortraitTextureRaw("Interface/Icons/ability_racial_timeismoney")
		ShowUIPanel(GFW_BankFrame)
	end
end

SLASH_GFW_BANK1 = "/bank"
SlashCmdList["GFW_BANK"] = T.ToggleBank

function GFW_Bank_OnAddonCompartmentClick(name, button)
	-- LeftButton vs RightButton actions?
	T.ToggleBank()
end

------------------------------------------------------
-- Utilities
------------------------------------------------------

function T.PlayerItemCount(itemID)
	local function CountInBags()
		local includeUses = false
		local includeBank, includeReagentBank, includeAccountBank = false, false, false
		return C_Item.GetItemCount(itemID, includeBank, includeUses, includeReagentBank, includeAccountBank)
	end
	local function CountIncludingBank()
		local includeUses = false
		local includeBank, includeReagentBank, includeAccountBank = true, false, false
		return C_Item.GetItemCount(itemID, includeBank, includeUses, includeReagentBank, includeAccountBank)
	end
	local function CountIncludingWarband()
		local includeUses = false
		local includeBank, includeReagentBank, includeAccountBank = false, false, true
		return C_Item.GetItemCount(itemID, includeBank, includeUses, includeReagentBank, includeAccountBank)
	end

	local inBags = CountInBags()
	local inBank = CountIncludingBank() - inBags
	local inWarband = CountIncludingWarband() - inBags
	
	return inBags, inBank, inWarband
end

function T.CharacterItemCount(itemID, dbCharacter)
	local function CountInBag(dbBag)
		local count = 0
		for slot = 1, dbBag.count do
			local bagItemInfo = dbBag[slot]
			if bagItemInfo then
				local bagItemID = GetItemInfoFromHyperlink(bagItemInfo.l)
				if bagItemID == itemID then
					count = count + (bagItemInfo.c or 1)
				end	
			end
		end
		return count
	end
	-- check character's bags
	local bagCount = 0
	for bagID = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		local bag = dbCharacter.bags[bagID]
		if bag then
			bagCount = bagCount + CountInBag(bag)
		end
	end
	-- check character's bank
	local bankCount = 0
	for bagID = ITEM_INVENTORY_BANK_BAG_OFFSET + 1, dbCharacter.bags.last do
		local bag = dbCharacter.bags[bagID]
		if bag then
			bankCount = bankCount + CountInBag(bag)
		end
	end

	-- TODO check character's equipped inventory
	
	return bagCount, bankCount
end

------------------------------------------------------
-- Crafting Reagent Quality
------------------------------------------------------

if not _G[addonName.."_ReagentQualityCache"] then
	_G[addonName.."_ReagentQualityCache"] = {}
end
local RQ = _G[addonName.."_ReagentQualityCache"]

local function pack(...)
	return { n = select("#", ...), ... } 
end
	
T.ItemInfo = setmetatable({}, {
	__index = function(t, index)
		local info = pack(C_Item.GetItemInfo(index))
		if #info > 1 then
			rawset(t, index, info)
			return info
		end
	end,
})
function T.GetItemInfo(itemID)
	local info = T.ItemInfo[itemID]
	if info then
		return unpack(info)
	end
end

local ITEM_INFO_RETRY_DELAY = 1.0
T.ReagentQualityQueue = {}
function T.CacheReagentQualityItems(itemID)
	if RQ[itemID] then
		-- local name, link = T.GetItemInfo(itemID)
		-- print("already cached", itemID, link, unpack(RQ[itemID]))
		T.ReagentQualityQueue[itemID] = nil
		return
	end
	local info = {T.GetItemInfo(itemID)}
	if #info == 0 then
		-- print("missing info, queued check for", itemID, quality)
		T.ReagentQualityQueue[itemID] = 1
		if not T.ReagentQualityRetryTimer then
			T.ReagentQualityRetryTimer = C_Timer.NewTicker(ITEM_INFO_RETRY_DELAY, T.ProcessReagentQualityQueue)
		end
		return
	end
	local name, link = info[1], info[2]
	local isReagent = info[17]
	if name and not isReagent then
		-- print(itemID, name, link, "not a reagent with quality levels")
		T.ReagentQualityQueue[itemID] = nil
		return
	end
	local qualities = {T.FindAllReagentQualityItems(itemID)}
	if qualities[1] and qualities[2] and qualities[3] then
		RQ[qualities[1]] = qualities
		RQ[qualities[2]] = qualities
		RQ[qualities[3]] = qualities
		
		-- print("cached", link, unpack(qualities))
		T.ReagentQualityQueue[itemID] = nil
	else
		-- print("can't find qualities, queued check for", itemID, quality)
		T.ReagentQualityQueue[itemID] = 1
		if not T.ReagentQualityRetryTimer then
			T.ReagentQualityRetryTimer = C_Timer.NewTicker(ITEM_INFO_RETRY_DELAY, T.ProcessReagentQualityQueue)
		end
	end
end

function T.ProcessReagentQualityQueue(timer)
	local count = 0
	for itemID in pairs(T.ReagentQualityQueue) do
		count = count + 1
		T.CacheReagentQualityItems(itemID)
	end
	if count == 0 then
		-- print("queue empty, canceling timer")
		T.ReagentQualityRetryTimer:Cancel()
		T.ReagentQualityRetryTimer = nil
	else
		-- print("queue processed", count)
	end
end

function T.FindAllReagentQualityItems(itemID)
	local name, link = T.GetItemInfo(itemID)
	local quality = C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemID)
	-- print("finding qualities for", itemID, name, quality)
	if not name then return end
	
	local items = { [quality] = itemID }
	local MAX_TRIES = 2000
	
	local function TestItem(id)
		local testName, testLink = T.GetItemInfo(id)
		-- print(testName)
		if testName and testName == name then
			local testQuality = C_TradeSkillUI.GetItemReagentQualityByItemInfo(id)
			-- print(id, testName, "testQuality", testQuality)
			if testQuality and testQuality ~= quality then
				items[testQuality] = id
			end
		end
	end
	
	-- first search in ascending itemID order from the one we started with
	do 
		-- print("searching greater")
		local testID = itemID
		repeat
			testID = testID + 1
			TestItem(testID)
			if testID - itemID > MAX_TRIES then break end
		until items[1] and items[2] and items[3]
	end

	-- if we don't have them all, search in descending itemID order from start
	if not (items[1] and items[2] and items[3]) then 
		-- print("searching lesser")
		local testID = itemID
		repeat
			testID = testID - 1
			TestItem(testID)
			if itemID - testID > MAX_TRIES then break end
		until items[3] and items[2] and items[1]
	end
	
	return items[1], items[2], items[3]
end

------------------------------------------------------
-- Save items
------------------------------------------------------

if not _G[addonName.."_DB"] then
	_G[addonName.."_DB"] = {}
end
local DB = _G[addonName.."_DB"]

--[[
DB = {
	[realmName] = {
		[characterName] = {
			bags = {
				[1] = { -- bag slot ID / bank tab containerID 
					[1] = { -- item slot in container
						-- minimal item info
						l = "itemHyperlink",
						c = 12, -- count in slot if > 1
					}
					[2] = nil, -- can be empty
					count = 36, -- num slots
					link = "containerHyperlink"
				},
				[2] = nil, -- can be empty
				-- ...
				[6] = { -- includes bank tabs
					-- ...
				}
				last = 6, -- containerID of last bag
			},
			currency = {
				-- TBD
			},
			equipped = {
				-- inventory slot
				[1] = "itemHyperlink",
			}
			money = 10000, -- copper
		}
	}
}	
]]

function Events:PLAYER_ENTERING_WORLD()
	T.InitializeDB()
	T.UpdateDBForAllBags()
	T.UpdateDBMoney()
end

function Events:BANKFRAME_OPENED()
	T.BankIsOpen = true
	T.UpdateDBForAllBags(true)
end

function Events:BANKFRAME_CLOSED()
	T.BankIsOpen = false
end

T.BagUpdateQueue = {}
function Events:BAG_UPDATE(bagID)
	-- print("queuing bag", bagID)
	T.BagUpdateQueue[bagID] = true
end

function Events:BAG_UPDATE_DELAYED()
	T.ProcessBagUpdateQueue()
end

function T.ProcessBagUpdateQueue()
	for bagID in pairs(T.BagUpdateQueue) do
		-- print("handling queued UpdateDBForBag", bagID)
		T.UpdateDBForBag(bagID)
	end
	wipe(T.BagUpdateQueue)
end

function T.InitializeDB()

	if not DB[T.Realm] then
		DB[T.Realm] = {}
	end
	if not DB[T.Realm][T.Player] then
		DB[T.Realm][T.Player] = {}
	end
	if not DB[T.Realm][T.Player].bags then
		DB[T.Realm][T.Player].bags = {}
	end
	
end

function T.UpdateDBForAllBags(includeBank)
	for bagID = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		T.UpdateDBForBag(bagID)
	end
	local bankTabIDs = C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Character)
	local lastBagID = max(unpack(bankTabIDs))
	DB[T.Realm][T.Player].bags.last = lastBagID

	if includeBank and T.BankIsOpen then
		for _, bagID in pairs(bankTabIDs) do
			T.UpdateDBForBag(bagID)	
		end
		
		-- bags already saved, update info for bank-tab bags
		local data = C_Bank.FetchPurchasedBankTabData(Enum.BankType.Character)
		for _, tabData in pairs(data) do
			local dbBag = DB[T.Realm][T.Player].bags[tabData.ID]
			assert(dbBag, "should have been created already")
			dbBag.icon = tabData.icon
			dbBag.link = tabData.name
		end
		-- TODO warbank, warbank tab info
	end
end

function T.BagIDIsBankType(bagID, bankType)
	local tabIDs = C_Bank.FetchPurchasedBankTabIDs(bankType)
	for _, tabID in pairs(tabIDs) do
		if tabID == bagID then
			return true
		end
	end
end

function T.UpdateDBForBag(bagID)
	if T.BagIDIsBankType(bagID, Enum.BankType.Account) then
		-- print("don't save warband bank", bagID) -- for now
		-- it'll need different storage so it's not repeated across characters
		-- and reading item counts doesn't need it
		return
	end 

	if T.BagIDIsBankType(bagID, Enum.BankType.Guild) then
		-- print("don't save guild bank", bagID) -- for now
		-- it'll need different storage so it's not repeated across characters
		return
	end

	if T.BagIDIsBankType(bagID, Enum.BankType.Character) and not T.BankIsOpen then
		-- print("don't save bank when not at bank", bagID)
		return
	end
	
	local inventoryID = C_Container.ContainerIDToInventoryID(bagID)
	local bagItemLink = GetInventoryItemLink("player", inventoryID)
	
	-- save as empty bag slot if no bag equipped
	if not bagItemLink then
		DB[T.Realm][T.Player].bags[bagID] = nil
		return
	end
	
	-- otherwise save its info
	if not DB[T.Realm][T.Player].bags[bagID] then
		DB[T.Realm][T.Player].bags[bagID] = {}
	end
	local dbBag = DB[T.Realm][T.Player].bags[bagID]
	dbBag.link = bagItemLink
	dbBag.count = C_Container.GetContainerNumSlots(bagID)
	-- print(bagID, ":", dbBag.link, dbBag.count, "slots")
	
	-- and then iterate to save its contents
	for slot = 1, dbBag.count do
		local data = C_Container.GetContainerItemInfo(bagID, slot)
		if data then
			-- minimal item info for minimal memory usage
			-- TODO save more item info if we find a need?
			-- TODO more minimal by reducing hyperlink to link code only?
			dbBag[slot] = {
				l = data.hyperlink,
				c = data.stackCount > 1 and data.stackCount or nil
			}
			
			-- if it's a crafting reagent
			-- make sure we know all three qualities of the same reagent
			local itemID = GetItemInfoFromHyperlink(data.hyperlink)
			local quality = C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemID)
			if quality then
				T.CacheReagentQualityItems(itemID)
			end
			
			-- print("-", data.hyperlink, "x", data.stackCount)
		end
	end

end

function T.UpdateDBForInventory()
	
end

function T.UpdateDBMoney()
	DB[T.Realm][T.Player].money = GetMoney()
end


------------------------------------------------------
-- Item tooltip 
------------------------------------------------------

function T.OnTooltipSetItem(tooltip, data)
	local name, link = TooltipUtil.GetDisplayedItem(tooltip)
	if not link then return end

	local type, info = LinkUtil.ExtractLink(link)
	if type == "item" then 
		local id = strsplit(":", info)
		local itemID = tonumber(id)
		if RQ[itemID] then
			-- it's a crafting reagent with quality levels, show detailed breakdown
			T:TooltipAddReagentInfo(tooltip, itemID)
		else
			T:TooltipAddItemInfo(tooltip, itemID)
		end
	end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, T.OnTooltipSetItem)

function T:TooltipAddItemInfo(tooltip, itemID)
	local function TooltipLine(name, inBags, inBank)
		if inBank > 0 and inBags == 0 then
			return L.TooltipLineBankOnly:format(name, inBank)
		elseif inBank > 0 then
			return L.TooltipLinePlayerBank:format(name, inBags + inBank, inBank)
		elseif inBags > 0 then
			return L.TooltipLinePlayer:format(name, inBags)
		end
	end
	
	-- check current player's total in bags, in bank, in warbank with API
	local inBags, inBank, inWarband = T.PlayerItemCount(itemID)
	local playerLine = TooltipLine(T.Player, inBags, inBank)
	if playerLine then
		GameTooltip_AddColoredLine(tooltip, playerLine, BRIGHTBLUE_FONT_COLOR)
	end
	
	-- check other characters' totals in saved DB
	for realmName, dbRealm in pairs(DB) do
		for characterName, dbCharacter in pairs(dbRealm) do
			if characterName ~= T.Player then
				if realmName ~= T.Realm then
					characterName = FULL_PLAYER_NAME:format(characterName, realmName)
				end
				local inBags, inBank = T.CharacterItemCount(itemID, dbCharacter)
				local characterLine = TooltipLine(characterName, inBags, inBank)
				if characterLine then
					GameTooltip_AddColoredLine(tooltip, characterLine, BRIGHTBLUE_FONT_COLOR)
				end
			end
		end
	end
	
	-- warband bank last
	if inWarband > 0 then
		local warbandLine = L.TooltipLinePlayer:format(ACCOUNT_BANK_PANEL_TITLE, inWarband)
		GameTooltip_AddColoredLine(tooltip, warbandLine, BRIGHTBLUE_FONT_COLOR)
	end
end

T.ReagentQualityIcon = setmetatable({}, {
	__index = function(t, index)
		local icon = C_Texture.GetCraftingReagentQualityChatIcon(index)
		rawset(t, index, icon)
		return icon
	end
})
function T:TooltipAddReagentInfo(tooltip, itemID)
	local function Summary(counts, counts2)
		local strings = {}
		local total = 0
		for quality, count in pairs(counts) do
			local count2 = counts2 and counts2[quality] or 0
			if count > 0 or count2 > 0 then
				tinsert(strings, count + count2 .. T.ReagentQualityIcon[quality])
				total = total + count + count2
			end
		end
		if total == 0 then
			return 0
		elseif #strings == 1 then
			return total, strings[1]
		else
			return total, L.ReagentTotalAndQualities:format(total, table.concat(strings))
		end
	end
	local function TooltipLine(name, inBags, inBank)
		-- inBags and inBank are tables here
		local totalBags, bagSummary = Summary(inBags)
		local totalBank, bankSummary = Summary(inBank)
				
		if totalBank > 0 and totalBags == 0 then
			return L.TooltipLineBankOnly:format(name, bankSummary)
		elseif totalBags > 0 and totalBank == 0 then
			return L.TooltipLinePlayer:format(name, bagSummary)
		elseif totalBank > 0 then
			local totalCombined, combinedSummary = Summary(inBags, inBank)
			return L.TooltipLinePlayerBank:format(name, combinedSummary, bankSummary)
		end
	end
	
	-- itemIDs for all qualities of the same reagent
	local quality1, quality2, quality3 = unpack(RQ[itemID])
	
	local inWarband = {}
	do -- check current player's total in bags, in bank, in warbank with API
		local inBags, inBank = {}, {}
		inBags[1], inBank[1], inWarband[1] = T.PlayerItemCount(quality1)
		inBags[2], inBank[2], inWarband[2] = T.PlayerItemCount(quality2)
		inBags[3], inBank[3], inWarband[3] = T.PlayerItemCount(quality3)
				
		local playerLine = TooltipLine(T.Player, inBags, inBank)
		if playerLine then
			GameTooltip_AddColoredLine(tooltip, playerLine, BRIGHTBLUE_FONT_COLOR, false)
		end
	end
	
	-- check other characters' totals in saved DB
	for realmName, dbRealm in pairs(DB) do
		for characterName, dbCharacter in pairs(dbRealm) do
			if characterName ~= T.Player then
				if realmName ~= T.Realm then
					characterName = FULL_PLAYER_NAME:format(characterName, realmName)
				end
				local inBags, inBank = {}, {}, {}
				inBags[1], inBank[1] = T.CharacterItemCount(quality1, dbCharacter)
				inBags[2], inBank[2] = T.CharacterItemCount(quality2, dbCharacter)
				inBags[3], inBank[3] = T.CharacterItemCount(quality3, dbCharacter)	
				
				local characterLine = TooltipLine(characterName, inBags, inBank)
				if characterLine then
					GameTooltip_AddColoredLine(tooltip, characterLine, BRIGHTBLUE_FONT_COLOR, false)
				end
			end
		end
	end
	
	-- warband bank last
	local totalWarband, warbandSummary = Summary(inWarband)
	if totalWarband > 0 then
		local warbandLine = L.TooltipLinePlayer:format(ACCOUNT_BANK_PANEL_TITLE, warbandSummary)
		GameTooltip_AddColoredLine(tooltip, warbandLine, BRIGHTBLUE_FONT_COLOR, false)
	end
end

