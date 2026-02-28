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

-- TEST TEMP
local ProblematicItemIDs = {
   [189143] = 1, [188658] = 1, [190311] = 1, --Draconium Ore
   [190395] = 1, [190396] = 1, [190394] = 1, --Serevite Ore 
   [192852] = 1, [192853] = 1, [192855] = 1, --Alexstraszite
   [192862] = 1, [192863] = 1, [192865] = 1, --Neltharite
   [193208] = 1, [193210] = 1, [193211] = 1, --Resilient Leather
   [194817] = 1, [194819] = 1, [194820] = 1  --Howling Rune
}

function FindTest()
   for k in pairs(ProblematicItemIDs) do
	  print(FindAllReagentQualityItems(k))
   end
end

function FindTestAsync()
   for k in pairs(ProblematicItemIDs) do
	  FindReagentQualityAsync(k)
   end
end

function CacheTest()
   for k in pairs(ProblematicItemIDs) do
	  CacheReagentQualityItems(k)
   end
end
-- END TEST TEMP

local ITEM_INFO_RETRY_DELAY = 1.0
T.ReagentQualityQueue = {}
function CacheReagentQualityItems(itemID)
	if RQ[itemID] then
		local name, link = C_Item.GetItemInfo(itemID)
		print("already cached", link, unpack(RQ[itemID]))
		T.ReagentQualityQueue[itemID] = nil
		return
	end
	local qualities = {FindAllReagentQualityItems(itemID)}
	if qualities[1] and qualities[2] and qualities[3] then
		RQ[qualities[1]] = qualities
		RQ[qualities[2]] = qualities
		RQ[qualities[3]] = qualities
		
		local name, link = C_Item.GetItemInfo(itemID)
		print("cached", link, unpack(qualities))
		T.ReagentQualityQueue[itemID] = nil
	else
		print("queued check for", itemID)
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
		CacheReagentQualityItems(itemID)
	end
	if count == 0 then
		print("queue empty, canceling timer")
		T.ReagentQualityRetryTimer:Cancel()
		T.ReagentQualityRetryTimer = nil
	else
		print("queue processed", count)
	end
end

function FindAllReagentQualityItems(itemID)
	local name, link = C_Item.GetItemInfo(itemID)
	local quality = C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemID)
	-- print("finding qualities for", itemID, name, quality)
	if not name then return end
	
	local items = { [quality] = itemID }
	local MAX_TRIES = 2000
	
	local function TestItem(id)
		local testName, testLink = C_Item.GetItemInfo(id)
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
	T.Realm = strtrim(GetRealmName())
	T.Player = UnitName("player")

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
	
	if includeBank and T.BankIsOpen then
		local bankTabIDs = C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Character)
		local lastBagID = NUM_TOTAL_EQUIPPED_BAG_SLOTS
		for _, bagID in pairs(bankTabIDs) do
			T.UpdateDBForBag(bagID)	
			lastBagID = bagID			
		end
		DB[T.Realm][T.Player].bags.last = lastBagID
	end
end

function T.UpdateDBForBag(bagID)
	if bagID > ITEM_INVENTORY_BANK_BAG_OFFSET and not T.BankIsOpen then
		-- don't update bank bags when not at bank
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
	
	-- TODO: if bank / warbank tab, get/save tab info
	
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
		T:TooltipAddItemInfo(tooltip, itemID)
	end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, T.OnTooltipSetItem)

function T:TooltipAddItemInfo(tooltip, itemID)
	function TooltipLine(name, inBags, inBank)
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

