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
-- The settings "Reset Detection" button (PLAYER context) likewise cannot
-- write global sections, so it signals AlchemyHelperResetDetection; this
-- script stamps the last-reset game time in the index section.

local core = require('openmw.core')
local db = require('scripts.alchemy-helper.shared.db')
local types = require('openmw.types')

--- Build and store the effect index + display info from all ingredient
--- records.
local function buildIndex()
    local records = types.Ingredient.records
    db.storeIndexes(db.buildIngredientEffects(records))
    db.storeIngredientInfo(db.buildIngredientInfo(records))
    db.storeEffectNames(db.buildEffectNames(records))
end

local ok, err = pcall(buildIndex)
if not ok and type(print) == 'function' then
    print('[AlchemyHelper] index build: ' .. tostring(err))
end

--- Event payloads from ingredient-detect.lua:
---   { id = <ingredient record ID> }
---   { id = <merchant record ID>, name, location,
---     ingredients = [restocking supply IDs] }
local function onDiscoverIngredient(data)
    if data and type(data.id) == 'string' then
        db.discoverIngredient(data.id)
    end
end

local function onDiscoverMerchant(data)
    if data and type(data.id) == 'string' then
        db.discoverMerchant(data.id, data.name, data.ingredients, data.location)
    end
end

--- Reset detection: clear all discovered ingredients/merchants and stamp
--- lastReset with the current game time so objects (re-)initializing from
--- now on re-run detection into the clean slate.
local function onResetDetection()
    db.clearDiscovered()
    db.setLastReset(core.getGameTime())
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
        AlchemyHelperResetDetection = onResetDetection,
    },
}
