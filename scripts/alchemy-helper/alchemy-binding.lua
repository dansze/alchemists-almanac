-- alchemy-binding.lua
-- PLAYER-context key binding for querying alchemy effects.

local KEYBIND = 'l'

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
            if key ~= KEYBIND then return end

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
