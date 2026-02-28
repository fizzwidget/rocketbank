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
-- Basic session info
------------------------------------------------------

T.Realm = strtrim(GetRealmName())
T.Player = UnitName("player")
-- T.Guild set lazily, not available at load

function T.SetupSettings(settings)
	-- TODO nicer settings UI
	settings:Checkbox("BagsOnOnePage", false)
	settings:Checkbox("SpatialBags", false)
	settings:Checkbox("GuildTooltip", false)
end

------------------------------------------------------
-- Bank preview frame launch conveniences
------------------------------------------------------

function GFW_ToggleBank()
	if GFW_BankFrame:IsVisible() then
		HideUIPanel(GFW_BankFrame)
	else
		GFW_BankFrame:SetPortraitTextureRaw("Interface/Icons/ability_racial_timeismoney")
		ShowUIPanel(GFW_BankFrame)
	end
end

SLASH_GFW_BANK1 = "/bank"
SlashCmdList["GFW_BANK"] = GFW_ToggleBank

function GFW_Bank_OnAddonCompartmentClick(name, button)
	-- LeftButton vs RightButton actions? tooltip?
	GFW_ToggleBank()
end

-- Bindings.xml localized text
BINDING_HEADER_GFW_BANK = "Fizzwidget " .. T.Title
BINDING_NAME_GFW_TOGGLEBANK = L.BindingToggleBank

------------------------------------------------------
-- Utilities
------------------------------------------------------

local function pack(...)
	return { n = select("#", ...), ... } 
end

local InvSlotNames = {
	-- [0] = "AMMOSLOT",
	[1] = "HEADSLOT",
	[2] = "NECKSLOT",
	[3] = "SHOULDERSLOT",
	[4] = "SHIRTSLOT",
	[5] = "CHESTSLOT",
	[6] = "WAISTSLOT",
	[7] = "LEGSSLOT",
	[8] = "FEETSLOT",
	[9] = "WRISTSLOT",
	[10] = "HANDSSLOT",
	[11] = "FINGER0SLOT",
	[12] = "FINGER1SLOT",
	[13] = "TRINKET0SLOT",
	[14] = "TRINKET1SLOT",
	[15] = "BACKSLOT",
	[16] = "MAINHANDSLOT",
	[17] = "SECONDARYHANDSLOT",
	-- [18] = "RANGEDSLOT",
	[19] = "TABARDSLOT",
	[20] = "PROF0TOOLSLOT",
	[21] = "PROF0GEAR0SLOT",
	[22] = "PROF0GEAR1SLOT",
	[23] = "PROF1TOOLSLOT",
	[24] = "PROF1GEAR0SLOT",
	[25] = "PROF1GEAR1SLOT",
	[26] = "COOKINGTOOLSLOT",
	[27] = "COOKINGGEAR0SLOT",
	[28] = "FISHINGTOOLSLOT",
	[29] = "FISHINGGEAR0SLOT",
	[30] = "FISHINGGEAR1SLOT",
}
T.InvSlotInfo = setmetatable({}, {
	__index = function(t, slotID)
		for _, slotName in pairs(InvSlotNames) do
			local info = pack(GetInventorySlotInfo(slotName))
			if info[1] == slotID then
				info[1] = slotName
				rawset(t, slotID, info)
				return info
			end
		end
	end,
})
function T.GetInventorySlotInfoByID(slotID)
	local cachedInfo = T.InvSlotInfo[slotID]
	if cachedInfo then
		return unpack(cachedInfo) -- name, texture, checkRelic
	end
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

------------------------------------------------------
-- Save items
------------------------------------------------------

if not _G[addonName.."_DB"] then
	_G[addonName.."_DB"] = {}
end
local DB = _G[addonName.."_DB"]

if not _G[addonName.."_Guild"] then
	_G[addonName.."_Guild"] = {}
end
local GB = _G[addonName.."_Guild"]

if not _G[addonName.."_Warband"] then
	_G[addonName.."_Warband"] = {}
end
local WB = _G[addonName.."_Warband"]

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
					link = "containerHyperlink", -- just name not link for bank tabs
					icon = "customIcon", -- for bank tabs only
					updated = 1755412000 -- server time (overrides character updated time because bank updates only when at bank)
				},
				[2] = nil, -- can be empty
				-- ...
				[6] = { -- includes bank tabs
					-- ...
				}
				last = 6, -- containerID of last bank tab
			},
			currency = { -- skips isAccountWide currencies
				[391] = 1, -- currencyID = quantity
			},
			equipped = {
				-- inventory slot
				[1] = "itemHyperlink",
			}
			money = 10000, -- copper
			updated = 1755412000, -- server time since epoch (sec)
		}
	},
}
GB = {
	[realmName] = {
		[guildName] = {
			bags = { ... } -- same as character bags but different IDs
			money = 10000, -- same as character
			updated = 1755412000, -- same as character
		}
	},
}
WB = {
	bags = { ... } -- same as character bags but bagID 12+
	money = 10000, -- same as character
	updated = 1755412000, -- same as character
	currency = { -- isAccountWide currencies
		[391] = 1, -- currencyID = quantity
	},

}
	
]]

function Events:PLAYER_ENTERING_WORLD()
	T.InitializeDB()
	T.InitializeGuild()
	T.UpdateDBForAllBags()
	T.UpdateDBForInventory()
	T.UpdateDBMoney()
	T.UpdateWarbankMoney()
	T.UpdateDBProfessions()
	T.UpdateDBCurrency()
end

function Events:GUILD_ROSTER_UPDATE()
	T.InitializeGuild()
	if T.Guild then
		self:UnregisterEvent("GUILD_ROSTER_UPDATE")
	end
end

function Events:PLAYER_GUILD_UPDATE(unit)
	if unit ~= "player" then return end
	T.InitializeGuild()
	if T.Guild then
		self:UnregisterEvent("PLAYER_GUILD_UPDATE")
	end
end

function Events:BANKFRAME_OPENED()
	T.BankIsOpen = true
	T.UpdateDBForAllBags(true)
end

function Events:BANKFRAME_CLOSED()
	T.BankIsOpen = false
end

function Events:PLAYER_INTERACTION_MANAGER_FRAME_SHOW(type)
	if type == Enum.PlayerInteractionType.GuildBanker then
		T.GuildBankIsOpen = true
	end
	T.InitializeGuild()
	T.UpdateGuildMoney()
	T.UpdateDBForGuild()
end

function Events:PLAYER_INTERACTION_MANAGER_FRAME_HIDE(type)
	if type == Enum.PlayerInteractionType.GuildBanker then
		T.GuildBankIsOpen = false
	end
end

function Events:GUILDBANK_UPDATE_TABS()
	T.UpdateDBForGuild()
end

function Events:GUILDBANKBAGSLOTS_CHANGED()
	local numTabs = GetNumGuildBankTabs()
	local dbGuild = GB[T.Realm][T.Guild]
	for index = 1, numTabs do
		T.UpdateDBForGuildTab(index)
	end
end

T.BagUpdateQueue = {}
function Events:BAG_UPDATE(bagID)
	-- print("queuing bag", bagID)
	T.BagUpdateQueue[bagID] = true
end

function Events:BAG_UPDATE_DELAYED()
	T.ProcessBagUpdateQueue()
end

function Events:PLAYER_EQUIPMENT_CHANGED(equipmentSlot, hasCurrent)
	T.UpdateDBForInventory()
end

function Events:PROFESSION_EQUIPMENT_CHANGED(skillLineID, isTool)
	T.UpdateDBForInventory()
end

function Events:SKILL_LINES_CHANGED()
	T.UpdateDBProfessions()	
end

function Events:PLAYER_MONEY()
	T.UpdateDBMoney()	
end

function Events:ACCOUNT_MONEY()
	T.UpdateWarbankMoney()	
end

function Events:GUILDBANK_UPDATE_MONEY()
	T.UpdateGuildMoney()
end

function Events:CURRENCY_DISPLAY_UPDATE()
	T.UpdateDBCurrency()
end

------------------------------------------------------
-- Saved data management 
------------------------------------------------------

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
	
	if not WB then
		WB = {}
	end
	if not WB.bags then
		WB.bags = {}
	end
end

function T.InitializeGuild()
	if not IsInGuild() then return end
	local guildName = GetGuildInfo("player")
	if not guildName then return end

	T.Guild = guildName
	
	if not GB[T.Realm] then
		GB[T.Realm] = {}
	end
	if not GB[T.Realm][T.Guild] then
		GB[T.Realm][T.Guild] = {}
	end
	if not GB[T.Realm][T.Guild].bags then
		GB[T.Realm][T.Guild].bags = {}
	end
end

function T.AskToDeleteGuild(guildName, realmName)
	local guildRealm = L.PlayerRealm:format(guildName, realmName)
	local coloredText = NORMAL_FONT_COLOR:WrapTextInColorCode(guildRealm)
	local data = { guildName = guildName, realmName = realmName }
	StaticPopup_Show(addonName.."_DeleteGuild", coloredText, T.Title, data)
end

function T.ConfirmedDeleteGuild(self, data)
	GB[data.realmName][data.guildName] = nil
	local realmEmpty = true
	for realm in pairs(GB[data.realmName]) do
		realmEmpty = false
		break
	end
	if realmEmpty then
		GB[data.realmName] = nil
	end
	local guildRealm = L.PlayerRealm:format(data.guildName, data.realmName)
	print(L.DeleteDone:format(T.Title, guildRealm))
	if GFW_BankPanel:IsVisible() then
		GFW_BankPanel:RefreshMenu()
	end
end

StaticPopupDialogs[addonName.."_DeleteGuild"] = {
	text = L.DeleteGuild,
	OnAccept = T.ConfirmedDeleteGuild,
	button1 = DELETE,
	button2 = CANCEL,
	wide = true,
	wideText = true,
	timeout = 30,
	hideOnEscape = true,
	whileDead = true,
}

function T.AskToDeleteCharacter(characterName, realmName)
	local playerRealm = L.PlayerRealm:format(characterName, realmName)
	local coloredText = NORMAL_FONT_COLOR:WrapTextInColorCode(playerRealm)
	local data = { characterName = characterName, realmName = realmName }
	StaticPopup_Show(addonName.."_DeleteCharacter", coloredText, T.Title, data)
end

function T.ConfirmedDeleteCharacter(self, data)
	DB[data.realmName][data.characterName] = nil
	local realmEmpty = true
	for realm in pairs(DB[data.realmName]) do
		realmEmpty = false
		break
	end
	if realmEmpty then
		DB[data.realmName] = nil
	end
	local playerRealm = L.PlayerRealm:format(data.characterName, data.realmName)
	print(L.DeleteDone:format(T.Title, playerRealm))
	if GFW_BankPanel:IsVisible() then
		GFW_BankPanel:RefreshMenu()
	end
end

StaticPopupDialogs[addonName.."_DeleteCharacter"] = {
	text = L.DeleteCharacter,
	OnAccept = T.ConfirmedDeleteCharacter,
	button1 = DELETE,
	button2 = CANCEL,
	wide = true,
	wideText = true,
	timeout = 30,
	hideOnEscape = true,
	whileDead = true,
}

------------------------------------------------------
-- Updating saved data 
------------------------------------------------------

function T.UpdateDBForAllBags(includeBank)
	for bagID = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		T.UpdateDBForBag(bagID)
	end
	
	local bankTabIDs = C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Character)
	DB[T.Realm][T.Player].bags.last = #bankTabIDs > 0 and max(unpack(bankTabIDs)) or 0
	
	local warbandTabIDs = C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Account)
	WB.bags.last = #warbandTabIDs > 0 and max(unpack(warbandTabIDs)) or 0
	
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
		
		for _, bagID in pairs(warbandTabIDs) do
			T.UpdateDBForBag(bagID)	
		end
		
		-- bags already saved, update info for bank-tab bags
		local data = C_Bank.FetchPurchasedBankTabData(Enum.BankType.Account)
		for _, tabData in pairs(data) do
			local dbBag = WB.bags[tabData.ID]
			assert(dbBag, "should have been created already")
			dbBag.icon = tabData.icon
			dbBag.link = tabData.name
		end

	end
end

function T.UpdateDBForGuild()
	if not T.GuildBankIsOpen then return end
	T.InitializeGuild()

	local dbGuild = GB[T.Realm][T.Guild]
	local numTabs = GetNumGuildBankTabs()
	dbGuild.bags.last = numTabs
	
	for index = 1, MAX_GUILDBANK_TABS do
		if index > numTabs then
			dbGuild.bags[index] = {}
		else
			local name, icon, isViewable = GetGuildBankTabInfo(index)
			if not name or name == "" then
				name = format(GUILDBANK_TAB_NUMBER, i)
			end
			if not dbGuild.bags[index] then
				dbGuild.bags[index] = {}
			end
			local dbBag = dbGuild.bags[index]
			dbBag.link = name
			dbBag.icon = icon
			dbBag.disabled = (not isViewable) or nil
			
			QueryGuildBankTab(index)
		end
	end
	dbGuild.updated = GetServerTime()
end

local MAX_GUILDBANK_SLOTS_PER_TAB = 98
function T.UpdateDBForGuildTab(tabIndex)
	local dbGuild =  GB[T.Realm][T.Guild]
	local dbBag = dbGuild.bags[tabIndex]
	assert(dbBag)
	
	-- print("Guild bank tab", tabIndex)
	dbBag.count = MAX_GUILDBANK_SLOTS_PER_TAB
	for slot = 1, dbBag.count do
		local link = GetGuildBankItemLink(tabIndex, slot)
		if link then
			local _, count = GetGuildBankItemInfo(tabIndex, slot)
			-- minimal item info for minimal memory usage
			dbBag[slot] = {
				l = link,
				c = count > 1 and count or nil
			}
			
			-- if it's a crafting reagent
			-- make sure we know all three qualities of the same reagent
			local itemID = GetItemInfoFromHyperlink(link)
			local quality = C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemID)
			if quality then
				T.CacheReagentQualityItems(itemID)
			end
			
			-- print("-", slot, ":", link, "x", count)
		else
			dbBag[slot] = nil
		end
	end
	dbGuild.updated = GetServerTime()
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
	
	local dbCharacter = DB[T.Realm][T.Player]
	-- can be character section of DB, specific-guild section of GB, or WB
	
	if T.BagIDIsBankType(bagID, Enum.BankType.Account) then
		dbCharacter = WB
		if not T.BankIsOpen then
			-- print("don't save warband bank when not at bank", bagID)
			return
		end
	end 

	if T.BagIDIsBankType(bagID, Enum.BankType.Guild) then -- unused?
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
	if bagID ~= BACKPACK_CONTAINER and not bagItemLink then
		dbCharacter.bags[bagID] = nil
		return
	end
	
	-- otherwise save its info
	if not dbCharacter.bags[bagID] then
		dbCharacter.bags[bagID] = {}
	end
	local dbBag = dbCharacter.bags[bagID]
	
	if bagID ~= BACKPACK_CONTAINER then
		local _, linkData, displayText = LinkUtil.ExtractLink(bagItemLink)
		if displayText == "" then
			print("[] item detected")
			if dbBag.link then
				local itemID = LinkUtil.SplitLinkOptions(linkData)
				local _, savedLinkData = LinkUtil.ExtractLink(dbBag.link)
				local savedID = LinkUtil.SplitLinkOptions(savedLinkData)
				if itemID ~= savedID then
					local _, itemLink = T.GetItemInfo(linkData)
					dbBag.link = itemLink
				end
			else
				local _, itemLink = T.GetItemInfo(linkData)
				dbBag.link = itemLink
			end 
		end
	end
	
	dbBag.link = bagItemLink
	dbBag.count = C_Container.GetContainerNumSlots(bagID)
	-- print(bagID, ":", dbBag.link, dbBag.count, "slots")
	
	-- and then iterate to save its contents
	for slot = 1, dbBag.count do
		local data = C_Container.GetContainerItemInfo(bagID, slot)
		if data then
			-- minimal item info for minimal memory usage
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
		else
			dbBag[slot] = nil
		end
	end
	
	-- timestamp per bag because can't update some bags when not at bank
	if bagID > NUM_TOTAL_EQUIPPED_BAG_SLOTS then
		dbBag.updated = GetServerTime()
	end
	dbCharacter.updated = GetServerTime()

end

-- https://warcraft.wiki.gg/wiki/InventorySlotID
-- 1-15+19: gear slots on sides of paperdollframe
-- 16-18: weapon slots (offhand or ranged not both?)
-- 20-22: profesion 0 gear
-- 23-25: profesion 1 gear
-- 26-27: cooking gear
-- 28: fishing rod (29-30 unused fishing accessories)
local MAX_INVSLOTS = 28

function T.UpdateDBForInventory()
	local dbCharacter = DB[T.Realm][T.Player]
	if not dbCharacter.equipped then
		dbCharacter.equipped = {}
		-- just project a fake bag schema here for the sake of bank UI?
		dbCharacter.equipped.count = MAX_INVSLOTS
	end
	
	for inventoryID = 1, MAX_INVSLOTS do
		local itemLink = GetInventoryItemLink("player", inventoryID)
		if itemLink then
			dbCharacter.equipped[inventoryID] = {
				l = itemLink,
			}
		else
			dbCharacter.equipped[inventoryID] = nil
		end
	end
		
	dbCharacter.updated = GetServerTime()
end

function T.UpdateDBProfessions()
	local function GetProfessionID(index)
		if not index then return nil end
		
		local name, texture, rank, maxRank, numSpells, spellOffset, skillLine, rankModifier, specializationIndex, specializationOffset, skillLineName = GetProfessionInfo(index)
		assert(skillLine)
		local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLine)
		assert(name == info.professionName)
		return skillLine, name
	end
	
	T.InitializeDB()
	local dbCharacter = DB[T.Realm][T.Player]
	dbCharacter.profSlots = {}
	
	local spellbookTabIndexes = {GetProfessions()}
	for i, profIndex in pairs(spellbookTabIndexes) do
		if i > 2 then break end -- only care about primary professions
		local name, texture, rank, maxRank, numSpells, spellOffset, skillLine, rankModifier, specializationIndex, specializationOffset, skillLineName = GetProfessionInfo(profIndex)
		assert(skillLine)
		local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLine)
		assert(name == info.professionName)
		local slots = C_TradeSkillUI.GetProfessionSlots(info.profession)
		for _, slot in pairs(slots) do
			dbCharacter.profSlots[slot] = skillLine
			-- print(slot, skillLine, name, T.GetInventorySlotInfoByID(slot))
		end
	end
end

function T.UpdateDBMoney()
	local dbCharacter = DB[T.Realm][T.Player]
	dbCharacter.money = GetMoney()
	dbCharacter.updated = GetServerTime()
end

function T.UpdateWarbankMoney()
	WB.money = C_Bank.FetchDepositedMoney(Enum.BankType.Account)
	WB.updated = GetServerTime()
	-- print("updated warband money", WB.money)
end

function T.UpdateGuildMoney()
	if not T.GuildBankIsOpen then return end
	T.InitializeGuild()
	local dbGuild = GB[T.Realm][T.Guild]
	dbGuild.money = GetGuildBankMoney()
	dbGuild.updated = GetServerTime()
	-- print("updated guild money", dbGuild.money)
end

local MAX_CURRENCIES = 5000 -- highest currency id is 3400-ish as of 12.0 alpha 10/2025
function T.UpdateDBCurrency()
	T.InitializeDB()
	local dbCharacter = DB[T.Realm][T.Player]
	if not dbCharacter.currency then 
		dbCharacter.currency = {}
	end
	
	for id = 1, MAX_CURRENCIES do
	   local data = C_CurrencyInfo.GetCurrencyInfo(id)
	   -- this saves way more currencies than ever show up in the UI
	   -- but we only use them for tooltips so we don't have to worry what to list
	   -- iconFileID helps filter out those that don't appear in UI (but not all of them)
	   -- don't save account wide currency, because builtin tooltips always have it
	   if data and data.discovered and not data.isAccountWide and data.iconFileID then
			dbCharacter.currency[id] = data.quantity
	   end
	end
end

function T.ProfessionName(inventoryID, character, realm)
	local dbSlotInfo = DB[realm][character].profSlots
	local skillLine = dbSlotInfo and dbSlotInfo[inventoryID]
	local info = skillLine and C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLine)
	return info and info.professionName
end

