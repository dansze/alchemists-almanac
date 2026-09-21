-- Alchemist's Almanac — Ingredient Pickup Detection (LOCAL context)
--
-- Detects when the player picks up alchemy ingredients into their inventory.
-- Each detected ingredient ID is reported to the GLOBAL script via
-- `interfaces.AlchemyHelper.discoverIngredient(ingredientId)`.

local content = require('openmw.content')
local ingredients = require('scripts.alchemy-helper.shared.ingredients')

local function logError(msg)
    if type(print) == 'function' then
        print('[AlchemyHelper] ' .. tostring(msg))
    end
end

--- Check if an object is an ingredient-type item.
local function isIngredient(object)
    if not object then return false end
    local baseId = object.getBaseId and object:getBaseId()
    if not baseId then baseId = object.baseId end
    if not baseId then baseId = object.refId end
    if not baseId or type(baseId) ~= 'string' or baseId == '' then return false end
    return content.ingredients and content.ingredients.record(baseId) ~= nil
end

--- Get the ingredient ID from an object.
local function getIngredientId(object)
    if not object then return nil end
    local baseId = object.getBaseId and object:getBaseId()
    if not baseId then baseId = object.baseId end
    if not baseId then baseId = object.refId end
    if baseId and type(baseId) == 'string' and baseId ~= '' then
        return baseId
    end
    return nil
end

--- onObjectAdded handler: detect ingredient pickups in player inventory.
local function onObjectAdded(object)
    if not object then return end

    -- Check if the picked-up object is an ingredient.
    if not isIngredient(object) then return end

    -- Extract the ingredient ID.
    local ingredientId = getIngredientId(object)
    if not ingredientId then return end

    -- Report to the GLOBAL script via the interface.
    local ok, err = pcall(function()
        ingredients.discoverIngredient(ingredientId)
    end)
    if not ok and type(logError) == 'function' then
        logError('discoverIngredient failed: ' .. tostring(err))
    end
end

return {
    engineHandlers = {
        onObjectAdded = onObjectAdded,
    },
}
