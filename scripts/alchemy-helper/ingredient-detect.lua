-- Alchemist's Almanac — Ingredient Pickup Detection (LOCAL context)
--
-- Detects when the player picks up alchemy ingredients into their inventory.
-- Each detected ingredient ID is reported to the GLOBAL script via
-- `interfaces.AlchemyHelper.discoverIngredient(ingredientId)`.

local db = require('scripts.alchemy-helper.shared.db')
local self = require('openmw.self')
local types = require('openmw.types')

-- Do not check again once object has been checked.
local handled = false

local function discover(init)
    if handled then return end
    handled = true

    if self.type == types.Ingredient then
        db.discoverIngredient(self.object.recordId)
    end

    if self.type == types.Container then
        local ingredientList = types.Container.inventory(self.object):getAll(types.Ingredient)
        for _, v in pairs(ingredientList) do
            db.discoverIngredient()
        end
    end

    if self.type == types.Actor then
        local ingredientList = types.Actor.inventory(self.object):getAll(types.Ingredient)
        for _, v in pairs(ingredientList) do
            db.discoverIngredient()
        end
    end
end

return {
    engineHandlers = {
        onInit = discover,
    },
}
