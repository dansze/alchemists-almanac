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

--- Last-known cell display name of an object, or nil.
local function cellName(obj)
    local cell = obj and obj.cell
    if not cell then return nil end
    return cell.displayName or cell.name
end

--- Report a merchant: services include both Barter and Ingredients.
-- restock = ingredient record IDs held at negative count (restocking supply).
local function reportMerchant(recordId, restock, location)
    local rec = getRecord(recordId)
    local services = rec and rec.servicesOffered
    if services and services['Barter'] and services['Ingredients'] then
        core.sendGlobalEvent(MERCHANT_EVENT_NAME, {
            id = recordId,
            name = (rec and rec.name) or recordId,
            location = location,
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

    -- NPCs/creatures report their specific package (types.NPC / types.Creature),
    -- never the base types.Actor table.
    if self.type == types.NPC or self.type == types.Creature then
        local ingredientList = types.Actor.inventory(self.object):getAll(types.Ingredient)
        local restock = {}
        for _, v in pairs(ingredientList) do
            report(v and v.recordId)
            -- Negative count = restocking supply the merchant sells.
            if v and v.count and v.count < 0 and v.recordId then
                restock[#restock + 1] = v.recordId
            end
        end
        reportMerchant(
            self.object and self.object.recordId,
            restock,
            cellName(self.object))
    end
end

return {
    engineHandlers = {
        onInit = discover,
    },
}
