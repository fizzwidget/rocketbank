local addonName, T = ...
T.SettingsUI = {}
local S = T.SettingsUI
local L = _G[addonName.."_Locale"]

function T:PairsByKeys(table, comparator)
	if not comparator then
		-- descending by default seems odd, but it's what we use most in this mod
		comparator = function(a, b) return a > b end
	end
	local keys = {}
	for key in pairs(table) do
		tinsert(keys, key) 
	end
	sort(keys, comparator)
	local i = 0 -- iterator variable
	local iterator = function()
		i = i + 1
		if keys[i] == nil then return nil
		else return keys[i], table[keys[i]]
		end
	end
	return iterator
end

------------------------------------------------------
-- Proto mixin for quick settings UI element creation
------------------------------------------------------

function S:Checkbox(settingKey, defaultValue, parentInit, onValueChanged)
	assert(settingKey ~= nil, "Setting requires string key")
	assert(defaultValue ~= nil, "Setting requires default value")
	local variable = addonName .. "_" .. settingKey
	local labelText = L.Setting[settingKey] or settingKey
	local setting = Settings.RegisterAddOnSetting(
		self.category, 
		variable, 
		settingKey, 
		T.Settings,
		type(defaultValue), 
		labelText, 
		defaultValue
	)
	local init = Settings.CreateCheckbox(self.category, setting, L.SettingTooltip[settingKey])
	if parentInit then
		init:Indent()
		init:SetParentInitializer(parentInit)
	end
	if onValueChanged then
		Settings.SetOnValueChangedCallback(variable, onValueChanged)
	end
	return init
end

function S:Slider(settingKey, defaultValue, minValue, maxValue, step, formatFunc, parentInit, onValueChanged)
	assert(settingKey ~= nil, "Setting requires string key")
	assert(defaultValue ~= nil, "Setting requires default value")
	local variable = addonName .. "_" .. settingKey
	local labelText = L.Setting[settingKey] or settingKey
	local setting = Settings.RegisterAddOnSetting(
		self.category, 
		variable, 
		settingKey, 
		T.Settings,
		type(defaultValue), 
		labelText, 
		defaultValue
	)
	
	local options = Settings.CreateSliderOptions(minValue, maxValue, step)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatFunc)
	local init = Settings.CreateSlider(self.category, setting, options, L.SettingTooltip[settingKey])

	if parentInit then
		init:Indent()
		init:SetParentInitializer(parentInit)
	end
	if onValueChanged then
		Settings.SetOnValueChangedCallback(variable, onValueChanged)
	end
	return init
end

-- menuOptions: table of string -> value
-- string: key for getting text/tooltip (and referencing the option value without magic numbers in other code)
-- value: number or whatever to read/write for this settings option
function S:Dropdown(settingKey, defaultValue, menuOptions)
	assert(settingKey ~= nil, "Setting requires string key")
	assert(defaultValue ~= nil, "Setting requires default value")
	-- Blizz UI allows separate label/tooltip for the checkbox and dropdown but they always keep both same
	-- we'll follow that by using the checkbox key to get the same label/tooltip text for both
	local labelText = L.Setting[settingKey] or settingKey
	local tooltipText = L.SettingTooltip[settingKey]
	local variable = addonName .. "_" .. settingKey
	local setting = Settings.RegisterAddOnSetting(
		self.category, 
		variable,
		settingKey,
		T.Settings,
		type(defaultValue),
		labelText,
		defaultValue
	)
	local function Menu(options)
		-- invert the table so we can put the menu in value order
		local keysForValues = {}
		for key, value in pairs(menuOptions) do
			keysForValues[value] = key
		end
		
		local container = Settings.CreateControlTextContainer()
		for value, key in T:PairsByKeys(keysForValues) do
			local text = L.Setting[settingKey.."_"..key] or key
			container:Add(value, text, L.SettingTooltip[settingKey.."_"..key])
		end
		return container:GetData()
	end
	local init = Settings.CreateDropdown(self.category, setting, Menu, L.SettingTooltip[settingKey])
	return init
end

-- menuOptions: table of string -> value
-- string: key for getting text/tooltip (and referencing the option value without magic numbers in other code)
-- value: number or whatever to read/write for this settings option
function S:CheckboxDropdown(checkSettingKey, checkDefault, menuSettingKey, menuDefault, menuOptions)
	assert(checkSettingKey and menuSettingKey, "Setting requires string keys")
	assert(checkDefault ~= nil and menuDefault ~= nil, "Setting requires default values")
	-- Blizz UI allows separate label/tooltip for the checkbox and dropdown but they always keep both same
	-- we'll follow that by using the checkbox key to get the same label/tooltip text for both
	local labelText = L.Setting[checkSettingKey] or checkSettingKey
	local tooltipText = L.SettingTooltip[checkSettingKey]
	local checkVariable = addonName .. "_" .. checkSettingKey
	local checkSetting = Settings.RegisterAddOnSetting(
		self.category, 
		checkVariable, 
		checkSettingKey, 
		T.Settings,
		type(checkDefault), 
		labelText, 
		checkDefault
	)
	local menuVariable = addonName .. "_" .. menuSettingKey
	local menuSetting = Settings.RegisterAddOnSetting(
		self.category, 
		menuVariable,
		menuSettingKey,
		T.Settings,
		type(menuDefault),
		labelText,
		menuDefault
	)
	local function Menu(options)
		-- invert the table so we can put the menu in value order
		local keysForValues = {}
		for key, value in pairs(menuOptions) do
			keysForValues[value] = key
		end
		
		local container = Settings.CreateControlTextContainer()
		for value, key in T:PairsByKeys(keysForValues) do
			container:Add(value, L.Setting[menuSettingKey.."_"..key], L.SettingTooltip[menuSettingKey.."_"..key])
		end
		return container:GetData()
	end
	local initializer = CreateSettingsCheckboxDropdownInitializer(
		checkSetting, labelText, tooltipText,
		menuSetting, Menu, labelText, tooltipText
	)
	initializer:AddSearchTags(labelText, tooltipText)
	self.layout:AddInitializer(initializer)
end

function S:SectionHeader(stringKey)
	local title, tooltip = L.Setting[stringKey], L.SettingTooltip[stringKey]
	self.layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title, tooltip))
end

------------------------------------------------------
-- Settings setup
------------------------------------------------------

function S:Initialize()
	self.category, self.layout = Settings.RegisterVerticalLayoutCategory(T.Title)
	if not _G[addonName .. "_Settings"] then
		_G[addonName .. "_Settings"] = {}
	end
	T.Settings = _G[addonName .. "_Settings"]
	T.SettingsCategoryID = self.category:GetID()
	
	if T.SetupSettings then
		T.SetupSettings(T.SettingsUI)
	else
		error("addonTable missing function SetupSettings")
	end
	
	Settings.RegisterAddOnCategory(self.category)
end

S:Initialize()