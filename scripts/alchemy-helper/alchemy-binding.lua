-- Alchemist's Almanac — Mod Settings + Keybind Binding (PLAYER context)
--
-- Registers the mod's Settings page/group (keybind + Immersive Mode) and
-- wires the keybind action to the almanac UI. The keybind is read from
-- the Settings system live (no caching) so in-game rebinding takes effect
-- immediately. Default keybind: '\\'.

local input = require('openmw.input')
local alchemyUI = require('scripts.alchemy-helper.alchemy-ui')
local interface = require('openmw.interfaces')
local async = require('openmw.async')

local SETTINGS = require('scripts.alchemy-helper.shared.settings')

-- Settings
input.registerAction {
    key = SETTINGS.action,
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
    key = SETTINGS.group,
    l10n = 'AlchemyHelper',
    page = 'AlchemyHelper',
    name = 'AlchemyHelper',
    description = 'AlchemyHelperSettingsDesc',
    permanentStorage = true,
    settings = {
        {
            key = SETTINGS.keyBind,
            renderer = 'inputBinding',
            name = 'Almanac Keybind',
            description = 'Keybind to open the almanac.',
            -- Default binding: backslash. (Symbol-string format; adjust if
            -- the settings UI shows it unresolved.)
            default = '\\',
            argument = {
                key = SETTINGS.action,
                type = 'action',
            },
        },
        {
            key = SETTINGS.immersiveMode,
            renderer = 'checkbox',
            name = 'Immersive Mode',
            description = 'Only show ingredients and merchants the player has encountered.',
            default = true,
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

input.registerActionHandler(SETTINGS.action, async:callback(handleUI))

return {
}
