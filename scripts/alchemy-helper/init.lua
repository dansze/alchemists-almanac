-- Alchemist's Almanac — Global script: effect index + AlchemyHelper interface
-- + discovery sink.
--
-- Data lives in openmw.storage global sections (see shared/db.lua):
--   - effect index: GameSession lifetime, built here at script start from
--     types.Ingredient.records (GLOBAL context has no `content` access;
--     storage is unavailable until a game is loaded, so the LOAD context
--     cannot build it)
--   - discovered ingredients: Persistent lifetime, written here only
--
-- ingredient-detect.lua (LOCAL context) cannot write to storage, so it
-- reports discoveries via AlchemyHelperDiscoverIngredient /
-- AlchemyHelperDiscoverMerchant global events.

local db = require('scripts.alchemy-helper.shared.db')
local types = require('openmw.types')

--- Build and store the effect index from all ingredient records.
local function buildIndex()
    db.storeIndexes(db.buildIngredientEffects(types.Ingredient.records))
end

local ok, err = pcall(buildIndex)
if not ok and type(print) == 'function' then
    print('[AlchemyHelper] index build: ' .. tostring(err))
end

--- Event payloads from ingredient-detect.lua:
---   { id = <ingredient record ID> }
---   { id = <merchant record ID>, name, ingredients = [restocking supply IDs] }
local function onDiscoverIngredient(data)
    if data and type(data.id) == 'string' then
        db.discoverIngredient(data.id)
    end
end

local function onDiscoverMerchant(data)
    if data and type(data.id) == 'string' then
        db.discoverMerchant(data.id, data.name, data.ingredients)
    end
end

return {
    interfaceName = 'AlchemyHelper',
    interface = {
        version = 1,
        queryByEffect = db.queryByEffect,
        querySharedWith = db.querySharedWith,
        queryEffects = db.queryEffects,
        getDiscovered = db.getDiscovered,
        getMerchants = db.getMerchants,
    },
    eventHandlers = {
        AlchemyHelperDiscoverIngredient = onDiscoverIngredient,
        AlchemyHelperDiscoverMerchant = onDiscoverMerchant,
    },
}
