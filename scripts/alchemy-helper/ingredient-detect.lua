-- Alchemist's Almanac — Ingredient Pickup Detection (LOCAL context)
--
-- Detects when alchemy ingredients enter the player's inventory (pickup,
-- container contents, actor in cell). LOCAL scripts cannot write to
-- openmw.storage, so each detected ID is reported to the GLOBAL script via
-- a global event; init.lua records it in the Persistent discovered section.

local core = require('openmw.core')
local self = require('openmw.self')
local types = require('openmw.types')

local EVENT_NAME = 'AlchemyHelperDiscoverIngredient'

local function report(recordId)
    if recordId then
        core.sendGlobalEvent(EVENT_NAME, { id = recordId })
    end
end

-- Do not check again once object has been checked.
local handled = false

local function discover(init)
    if handled then return end
    handled = true

    if self.type == types.Ingredient then
        report(self.object and self.object.recordId)
    end

    if self.type == types.Container then
        local ingredientList = types.Container.inventory(self.object):getAll(types.Ingredient)
        for _, v in pairs(ingredientList) do
            report(v and v.object and v.object.recordId)
        end
    end

    if self.type == types.Actor then
        local ingredientList = types.Actor.inventory(self.object):getAll(types.Ingredient)
        for _, v in pairs(ingredientList) do
            report(v and v.object and v.object.recordId)
        end
    end
end

return {
    engineHandlers = {
        onInit = discover,
    },
}
