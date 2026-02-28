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

L.AddonVersion = "Fizzwidget %s v.%s" -- addonName, versionNum

L.PlayerRealm = "%s (%s)" -- playerName, realmName
L.TooltipLinePlayer = "%s has %s" -- playerName or "warband bank", itemCount or reagentSummary
L.TooltipLinePlayerBank = "%s has %s (%s in bank)" -- playerName, itemCount or reagentSummary, itemCount or reagentSummary
L.TooltipLineBankOnly = "%s has %s (in bank)" -- playerName, itemCount or reagentSummary
L.ReagentSummary = "%s: %s" -- "6: 1* 2** 3***"

L.BindingToggleBank = "Toggle bank preview panel"

L.Updated = "Updated: %s" -- long date+time string
L.NotInGuild = "(%s — no guild)" -- playerName
L.MissingBank = "No bank data cached for %1$s.|n|n %2$s will not show bank information until that character visits the bank." 
L.MissingGuild = "No guild bank data cached for %1$s.|n|n %2$s will not show guild bank information until a character that guild visits the guild bank."
L.DeleteTooltip = "Delete cached data"

-- addonName, playerName + realmName
L.DeleteCharacter = "Delete this addon‘s data cache for the character |n%1$s?|n|n %2$s will not show information from their inventory, bank, etc until the next time you log into that character." 
-- addonName, guildName + realmName
L.DeleteGuild = "Delete this addon's data cache for the guild |n%1$s?|n|n %2$s will not show guild bank information until you log into a character in that guild and visit the guild bank." 

L.DeleteDone = "%s: Deleted data cache for %s" -- addonName, playerName/guildName + realmName


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
