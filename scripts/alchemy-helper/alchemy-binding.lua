-- Alchemist's Almanac — Mod Settings + Keybind Binding (PLAYER context)
--
-- Registers the mod's Settings page/group (keybind + Immersive Mode) and
-- wires the keybind action to the almanac UI. The keybind is read from
-- the Settings system live (no caching) so in-game rebinding takes effect
-- immediately. Default keybind: '\\'.

local core = require('openmw.core')
local input = require('openmw.input')
local alchemyUI = require('scripts.alchemy-helper.alchemy-ui')
local interface = require('openmw.interfaces')
local async = require('openmw.async')
local storage = require('openmw.storage')

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
    description = 'Keeps track of your ingredients and who sells them.',
}

interface.Settings.registerGroup {
    key = SETTINGS.group,
    l10n = 'AlchemyHelper',
    page = 'AlchemyHelper',
    name = 'AlchemyHelper',
    description = 'Mod settings and debug options',
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
            description = 'Only show ingredients the player has encountered. Merchants always need to be encountered to show in the almanac.',
            default = true,
        },
        {
            key = SETTINGS.resetDetection,
            renderer = 'checkbox',
            name = 'Reset Detection',
            description = 'One-shot action: clear all detected ingredients and merchants, then force re-detection when they (re)initialize. Flips itself back off after use.',
            default = false,
        },
    },
}

-- "Reset Detection" is a button in disguise: toggling it on stamps the
-- global last-reset game time (init.lua) and flips the checkbox back off.
-- The write-back must be deferred: writing to a section from inside its own
-- subscribe callback throws (storage recursion guard). OpenMW 0.52 has no
-- real-time timers, so the flip-back waits for the first simulation tick —
-- i.e. it lands as soon as the settings menu closes and the game resumes.
local settingsSection = storage.playerSection(SETTINGS.group)
settingsSection:subscribe(async:callback(function(_, key)
    if key ~= SETTINGS.resetDetection then return end
    if not settingsSection:get(SETTINGS.resetDetection) then return end
    core.sendGlobalEvent('AlchemyHelperResetDetection')
    async:newUnsavableSimulationTimer(0, function()
        settingsSection:set(SETTINGS.resetDetection, false)
    end)
end))

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
    eventHandlers = {
        -- Esc (or any other mode close) from the engine side orphans the
        -- window; close it when all modes are gone.
        UiModeChanged = function(data)
            alchemyUI.onUiModeChanged(data)
        end,
    },
}
