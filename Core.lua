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

