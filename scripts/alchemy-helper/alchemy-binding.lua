-- Alchemist's Almanac — Alchemy Keybind Binding (PLAYER context)
--
-- Reads the keybind from the Settings system (registered via
-- openmw.interfaces.Settings in load-db.lua) on each onKeyPress call —
-- no caching — so in-game rebinding takes effect immediately.
-- Falls back to 'l' when no custom value is stored.

local input = require('openmw.input')
local alchemyUI = require('scripts.alchemy-helper.alchemy-ui')
local interface = require('openmw.interfaces')
local ui = require('openmw.ui')
local async = require('openmw.async')

-- Settings group / field keys (must match load-db.lua registration).
local SETTINGS_GROUP = 'SettingsPlayerAlchemyHelper'
local SETTINGS_KEY   = 'AlchemyHelperKeyBind'
local SETTINGS_ACTION = 'AlchemyHelperKey'

-- Settings
input.registerAction {
    key = SETTINGS_ACTION,
    type = input.ACTION_TYPE.Boolean,
    name = '',
    l10n = 'AlchemyHelper',
    description = '',
    defaultValue = false,
}

interface.Settings.registerPage {
    key = 'AlchemyHelper',
    l10n = 'AlchemyHelper',
    name = 'Alchemist\'s Almanac',
    description = 'AlchemyHelper',
}

interface.Settings.registerGroup {
    key = SETTINGS_GROUP,
    l10n = 'AlchemyHelper',
    page = 'AlchemyHelper',
    name = 'AlchemyHelper',
    description = 'AlchemyHelperSettingsDesc',
    permanentStorage = true,
    settings = {
        {
            key = SETTINGS_KEY,
            renderer = 'inputBinding',
            name = 'Almanac Keybind',
            description = 'Keybind to open the almanac.',
            default = '',
            argument = {
                key = SETTINGS_ACTION,
                type = 'action',
            },
        },
    },
}

local function handleUI(val)
    if not val then return end
    if not alchemyUI.isVisible() then
        alchemyUI.show()
    else
        alchemyUI.hide()
    end
end

input.registerActionHandler(SETTINGS_ACTION, async:callback(handleUI))

return {
}
