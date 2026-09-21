-- Alchemist's Almanac — Ingredient Discovery + Lookup Tables
-- Tracks individual alchemy ingredients the player has collected.
-- Pre-computes all static lookup tables for the alchemy effect system.
--
-- Discovery: ingredient IDs inserted into discoveredMap via
--   discoverIngredient(ingredientId) called from ingredient-detect.lua.
-- Save/load: ingredient discovery and UI preferences.

-- ── Persistence: discovered ingredients & preferences ──────────────────────
-- Per-ingredient-ID tracking. Key = ingredient ID string, value = true.

local ingredients = require('scripts.alchemy-helper.shared.ingredients')

--- onSave handler: serialize discoveredMap and preferences.
local function onSave()
    local discovered = {}
    for ingId in pairs(ingredients.discoveredIngredients) do
        discovered[#discovered + 1] = ingId
    end
    return {
        discovered = discovered,
    }
end

--- onLoad handler: deserialize discovered ingredients and preferences.
local function onLoad(saved)
    if not saved then return end

    if saved.discovered then
        for _, ingId in ipairs(saved.discovered) do
            ingredients.discoveredIngredients[ingId] = true
        end
    end
end


return {
    engineHandlers = {
        onSave = onSave,
        onLoad = onLoad,
    }
}