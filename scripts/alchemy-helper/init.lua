-- Alchemist's Almanac — Ingredient Discovery + Lookup Tables
-- Tracks individual alchemy ingredients the player has collected.
-- Pre-computes all static lookup tables for the alchemy effect system.
--
-- Discovery: ingredient IDs inserted into discoveredMap via
--   discoverIngredient(ingredientId) called from ingredient-detect.lua.
-- Save/load: ingredient discovery and UI preferences.

-- init.lua exports are populated by load-db.lua during LOAD context
-- (content package is unavailable in GLOBAL context).

local ingredientEffects = {}
local effectIngredients = {}
local sharedIngredients = {}

-- ── Persistence: discovered ingredients & preferences ──────────────────────
-- Per-ingredient-ID tracking. Key = ingredient ID string, value = true.
local discoveredMap = {}

-- User UI preferences placeholder. Plain table.
local preferences = {}

--- Discover a single ingredient ID.
--- Deduplicates (checks discoveredMap), inserts if new.
local function discoverIngredient(ingredientId)
    if not ingredientId or type(ingredientId) ~= 'string' or ingredientId == '' then
        return
    end
    if discoveredMap[ingredientId] then
        return
    end
    discoveredMap[ingredientId] = true
end

--- onSave handler: serialize discoveredMap and preferences.
local function onSave()
    local discovered = {}
    for ingId in pairs(discoveredMap) do
        discovered[#discovered + 1] = ingId
    end
    return {
        discovered = discovered,
        preferences = preferences,
    }
end

--- onLoad handler: deserialize discovered ingredients and preferences.
local function onLoad(saved)
    if not saved then return end

    if saved.discovered then
        for _, ingId in ipairs(saved.discovered) do
            discoveredMap[ingId] = true
        end
    end

    if saved.preferences then
        for k, v in pairs(saved.preferences) do
            preferences[k] = v
        end
    end
end

return {
    ingredientEffects = ingredientEffects,
    effectIngredients = effectIngredients,
    sharedIngredients = sharedIngredients,
    discoverIngredient = discoverIngredient,
    engineHandlers = {
        onSave = onSave,
        onLoad = onLoad,
    },
}
