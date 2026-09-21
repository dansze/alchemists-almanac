-- Alchemist's Almanac — Alchemy Keybind Binding (PLAYER context)
--
-- Reads the keybind from the Settings system (registered via
-- openmw.interfaces.Settings in load-db.lua) on each onKeyPress call —
-- no caching — so in-game rebinding takes effect immediately.
-- Falls back to 'l' when no custom value is stored.

local interfaces = require('openmw.interfaces')
local storage = require('openmw.storage')

-- Settings group / field keys (must match load-db.lua registration).
local SETTINGS_GROUP = 'SettingsPlayerAlchemyHelper'
local SETTINGS_KEY   = 'AlchemyHelperKeybind'

-- Settings
local interface = require('openmw.interfaces')

interface.Settings.registerPage {
    key = 'AlchemyHelper',
    l10n = 'AlchemyHelper',
    name = 'Alchemist\'s Almanac',
    description = 'AlchemyHelper',
}

interface.Settings.registerGroup {
    key = SETTINGS_GROUP,
    page = 'AlchemyHelper',
    l10n = 'AlchemyHelper',
    name = 'AlchemyHelper',
    description = 'AlchemyHelperSettingsDesc',
    permanentStorage = false,
    settings = {
        {
            key = SETTINGS_KEY,
            renderer = 'inputBinding',
            name = 'Almanac Keybind',
            description = 'Keybind to open the almanac.',
            default = '\\',
            argument = {
                key = SETTINGS_KEY,
                type = 'trigger',
            },
        },
    },
}

--- Read the current keybind from the Settings group registered via
--- openmw.interfaces.Settings.  Returns 'l' when the setting is unset.
local function getAlchemyHelperKeybind()
    local section = storage.playerSection(SETTINGS_GROUP)
    local value = section and section:get(SETTINGS_KEY)
    return value or '\\'
end

local function logError(msg)
    if type(print) == 'function' then
        print('[AlchemyHelper] ' .. tostring(msg))
    end
end

local AlchemyUI = nil
local success, err = pcall(function()
    AlchemyUI = require('alchemy-ui')
end)
if not success and type(logError) == 'function' then logError('require alchemy-ui: ' .. tostring(err)) end

return {
    engineHandlers = {
        onKeyPress = function(key)
            if key ~= getAlchemyHelperKeybind() then return end

            -- Guard: effect database not loaded yet, or reloadlua without init.
            if not interfaces.AlchemyHelper or not interfaces.AlchemyHelper.queryEffects then
                if AlchemyUI then AlchemyUI.update() end
                return
            end

            local id = nil
            local success, err = pcall(function()
                id = interfaces.AlchemyHelper.ingredientId()
            end)
            if not success and type(logError) == 'function' then logError('ingredientId: ' .. tostring(err)) end

            if not id or type(id) ~= 'string' or id == '' then
                if AlchemyUI then AlchemyUI.update() end
                return
            end

            if AlchemyUI then AlchemyUI.update(id) end
        end,
    },
}
