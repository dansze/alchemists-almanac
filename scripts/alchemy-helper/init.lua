-- Alchemist's Almanac — Ingredient Discovery + Lookup Tables
-- Tracks individual alchemy ingredients the player has collected.
-- Pre-computes all static lookup tables for the alchemy effect system.
--
-- Discovery: ingredient IDs inserted into discoveredMap via
--   discoverIngredient(ingredientId) called from ingredient-detect.lua.
-- Save/load: ingredient discovery and UI preferences.

-- ── Persistence: discovered ingredients & preferences ──────────────────────
-- Per-ingredient-ID tracking. Key = ingredient ID string, value = true.

local db = require('scripts.alchemy-helper.load-db')

-- Settings
local interface = require('openmw.interface')

interface.Settings.registerPage {
    key = 'AlchemyHelper',
    l10n = 'AlchemyHelper',
    name = 'AlchemyHelper',
    description = 'AlchemyHelper',
}

interface.Settings.registerGroup {
    key = 'SettingsPlayerAlchemyHelper',
    page = 'AlchemyHelper',
    l10n = 'AlchemyHelper',
    name = 'AlchemyHelper',
    description = 'AlchemyHelperSettingsDesc',
    permanentStorage = false,
    settings = {
        {
            key = 'AlchemyHelperKeybind',
            renderer = 'inputBinding',
            name = 'AlchemyHelperKeybind',
            description = 'AlchemyHelperKeybindDesc',
            default = 'l',
            argument = {
                key = 'AlchemyHelperKeybind',
                type = 'trigger',
            },
        },
    },
}

local discoveredMap = {}

--- Discover a single ingredient ID.
--- Deduplicates (checks discoveredMap), inserts if new.
function DiscoverIngredient(ingredientId)
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
end


return {
    engineHandlers = {
        onSave = onSave,
        onLoad = onLoad,
    }
}