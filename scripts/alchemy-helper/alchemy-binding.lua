-- Alchemist's Almanac — Alchemy Keybind Binding (PLAYER context)
--
-- Reads the keybind from the Settings system (registered via
-- openmw.interfaces.Settings in load-db.lua) on each onKeyPress call —
-- no caching — so in-game rebinding takes effect immediately.
-- Falls back to 'l' when no custom value is stored.

local input = require('openmw.input')
local alchemyUI = require('alchemy-ui')
local interface = require('openmw.interfaces')
local ui = require('openmw.ui')

-- Settings group / field keys (must match load-db.lua registration).
local SETTINGS_GROUP = 'SettingsPlayerAlchemyHelper'
local SETTINGS_KEY   = 'AlchemyHelperKeyBind'
local SETTINGS_ACTION = 'AlchemyHelperKey'

-- Settings
input.registerAction {
    key = SETTINGS_ACTION,
    type = input.ACTION_TYPE.Boolean,
    name = '',
    description = '',
    defaultValue = false,
}

interface.Settings.registerPage {
    key = 'AlchemyHelper',
    name = 'Alchemist\'s Almanac',
    description = 'AlchemyHelper',
}

interface.Settings.registerGroup {
    key = SETTINGS_GROUP,
    page = 'AlchemyHelper',
    name = 'AlchemyHelper',
    description = 'AlchemyHelperSettingsDesc',
    permanentStorage = false,
    settings = {
        {
            key = SETTINGS_KEY,
            renderer = 'inputBinding',
            name = 'Almanac Keybind',
            description = 'Keybind to open the almanac.',
            default = input.KEY.BackSlash,
            argument = {
                key = SETTINGS_ACTION,
                type = 'action',
            },
        },
    },
}

ui.showMessage('Settings and binding loaded!')

local showing = false
local function handleUI(val)
    if ~val then return end
    if ~showing then
        alchemyUI.show()
    else
        alchemyUI.hide()
    end
end

input.registerActionHandler(SETTINGS_ACTION, handleUI)

return {
}
