-- alchemy-binding.lua
-- PLAYER-context key binding for querying alchemy effects.

local KEYBIND = 'l'

local AlchemyUI = require('alchemy-ui')

return {
    engineHandlers = {
        onKeyPress = function(key)
            if key ~= KEYBIND then return end

            -- Guard: effect database not loaded yet, or reloadlua without init.
            if not interfaces.AlchemyHelper or not interfaces.AlchemyHelper.queryEffects then
                AlchemyUI.update(); return
            end

            local id = interfaces.AlchemyHelper.ingredientId()

            if not id or type(id) ~= 'string' or id == '' then
                AlchemyUI.update()
                return
            end

            AlchemyUI.update(id)
        end,
    },
}
