-- Alchemist's Almanac — Ingredient Pickup Detection (LOCAL context)
--
-- Detects when alchemy ingredients enter the player's inventory (pickup,
-- container contents, actor in cell) and when ingredient merchants are
-- encountered (NPC/Creature offering both Barter and Ingredients services).
-- LOCAL scripts cannot write to openmw.storage, so discoveries are reported
-- to the GLOBAL script via global events; init.lua records them in the
-- Persistent discovered section.

local core = require('openmw.core')
local self = require('openmw.self')
local types = require('openmw.types')

local EVENT_NAME = 'AlchemyHelperDiscoverIngredient'
local MERCHANT_EVENT_NAME = 'AlchemyHelperDiscoverMerchant'

local function report(recordId)
    if recordId then
        core.sendGlobalEvent(EVENT_NAME, { id = recordId })
    end
end

--- Record for an NPC or Creature (whichever lookup succeeds).
local function getRecord(recordId)
    local rec = types.NPC.record(recordId)
    if not rec then
        rec = types.Creature.record(recordId)
    end
    return rec
end

--- Report a merchant: services include both Barter and Ingredients.
-- restock = ingredient record IDs held at negative count (restocking supply).
local function reportMerchant(recordId, restock)
    local rec = getRecord(recordId)
    local services = rec and rec.servicesOffered
    if services and services['Barter'] and services['Ingredients'] then
        core.sendGlobalEvent(MERCHANT_EVENT_NAME, {
            id = recordId,
            name = (rec and rec.name) or recordId,
            ingredients = restock,
        })
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
            report(v and v.recordId)
        end
    end

    if self.type == types.Actor then
        local ingredientList = types.Actor.inventory(self.object):getAll(types.Ingredient)
        local restock = {}
        for _, v in pairs(ingredientList) do
            report(v and v.recordId)
            -- Negative count = restocking supply the merchant sells.
            if v and v.count and v.count < 0 and v.recordId then
                restock[#restock + 1] = v.recordId
            end
        end
        reportMerchant(self.object and self.object.recordId, restock)
    end
end

return {
    engineHandlers = {
        onInit = discover,
    },
}
