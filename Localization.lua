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

L.TooltipLinePlayer = "%s has %d"
L.TooltipLinePlayerBank = "%s has %d (%d in bank)"

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
