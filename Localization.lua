------------------------------------------------------
-- Localization.lua
-- English strings by default, localizations override with their own.
------------------------------------------------------
-- This file contains strings shown in FactionFriend's UI; all features still work if these aren't localized.
------------------------------------------------------
-- Setup for shorthand when defining strings and automatic lookup in settings
local addonName = ...
_G[addonName.."_Locale"] = {}
local Locale = _G[addonName.."_Locale"]
Locale.Text = {}
Locale.Setting = {}
Locale.SettingTooltip = {}
local L = Locale.Text
local S = Locale.Setting
local T = Locale.SettingTooltip
------------------------------------------------------

L.PlayerRealm = "%s (%s)" -- playerName, realmName
L.TooltipLinePlayer = "%s has %s" -- playerName or "warband bank", itemCount or reagentSummary
L.TooltipLinePlayerBank = "%s has %s (%s in bank)" -- playerName, itemCount or reagentSummary, itemCount or reagentSummary
L.TooltipLineBankOnly = "%s has %s (in bank)" -- playerName, itemCount or reagentSummary
L.ReagentSummary = "%s: %s" -- "6: 1* 2** 3***"

L.BindingToggleBank = "Toggle bank preview panel"

L.Updated = "Updated: %s" -- long date+time string

------------------------------------------------------

if (GetLocale() == "deDE") then
	
-- localizers: copy the rest from enUS at the top

end

------------------------------------------------------

if (GetLocale() == "frFR") then

-- localizers: copy the rest from enUS at the top

end

------------------------------------------------------

if (GetLocale() == "esES" or GetLocale() == "esMX") then

-- localizers: copy the rest from enUS at the top
	
end

------------------------------------------------------

if (GetLocale() == "ptBR") then

-- localizers: copy the rest from enUS at the top

end

------------------------------------------------------

if (GetLocale() == "ruRU") then

-- localizers: copy the rest from enUS at the top

end

------------------------------------------------------
