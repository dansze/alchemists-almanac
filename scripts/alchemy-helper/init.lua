-- Alchemist's Almanac — Global script: AlchemyHelper interface + discovery sink.
--
-- Data lives in openmw.storage global sections (see shared/db.lua):
--   - effect index: GameSession lifetime, rebuilt by load-db.lua on game load
--   - discovered ingredients: Persistent lifetime, written here only
--
-- ingredient-detect.lua (LOCAL context) cannot write to storage, so it
-- reports pickups via the AlchemyHelperDiscoverIngredient global event.

local db = require('scripts.alchemy-helper.shared.db')

--- Event payload from ingredient-detect.lua: { id = <ingredient record ID> }.
local function onDiscoverIngredient(data)
    if data and type(data.id) == 'string' then
        db.discoverIngredient(data.id)
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
    },
    eventHandlers = {
        AlchemyHelperDiscoverIngredient = onDiscoverIngredient,
    },
}
