-- Alchemist's Almanac — shared ingredient database access.
--
-- Script contexts have isolated Lua states, so module-level tables do NOT
-- share data across scripts. All data lives in openmw.storage global
-- sections; this module only provides functions over those sections.
--
-- Sections:
--   AlchemyHelperIndex      GameSession lifetime — rebuilt on every game load
--                           by load-db.lua (LOAD context).
--                           keys: ingredientEffects, effectIngredients,
--                                 baseEffectIngredients
--   AlchemyHelperDiscovered Persistent lifetime — key: ids (array of
--                           discovered ingredient ID strings). Written by
--                           the GLOBAL script only.
--
-- Write paths call setLifeTime; read paths never do (only global-ish
-- contexts may modify sections).

local storage = require('openmw.storage')

local M = {}

local INDEX_SECTION = 'AlchemyHelperIndex'
local DISCOVERED_SECTION = 'AlchemyHelperDiscovered'

-- Per-context flags: ensure lifetime once per Lua state, on the write path.
local indexLifetimeSet = false
local discoveredLifetimeSet = false

--- Write access to the index section (LOAD context). GameSession lifetime.
local function indexSection()
    local s = storage.globalSection(INDEX_SECTION)
    if not indexLifetimeSet then
        s:setLifeTime(storage.LIFE_TIME.GameSession)
        indexLifetimeSet = true
    end
    return s
end

--- Write access to the discovered section (GLOBAL context). Persistent lifetime.
local function discoveredSection()
    local s = storage.globalSection(DISCOVERED_SECTION)
    if not discoveredLifetimeSet then
        s:setLifeTime(storage.LIFE_TIME.Persistent)
        discoveredLifetimeSet = true
    end
    return s
end

--- Read-only view of the index section.
local function readIndex()
    return storage.globalSection(INDEX_SECTION):asTable()
end

--- Store the full ingredientEffects map and rebuild both effect indexes.
--- Called from the LOAD script after scanning content records.
--- ingredientEffects entries are compound strings "effId~attribute~skill"
--- (empty parts omitted, '~' separated).
function M.storeIndexes(ingredientEffects)
    local effIngredients = {}
    local baseIngredients = {}
    for ingId, effList in pairs(ingredientEffects or {}) do
        for _, entry in ipairs(effList) do
            local base = entry:match('^[^~]*')
            if not effIngredients[entry] then
                effIngredients[entry] = {}
            end
            local entries = effIngredients[entry]
            entries[#entries + 1] = ingId

            if not baseIngredients[base] then
                baseIngredients[base] = {}
            end
            local baseEntries = baseIngredients[base]
            baseEntries[#baseEntries + 1] = ingId
        end
    end
    local s = indexSection()
    s:set('ingredientEffects', ingredientEffects)
    s:set('effectIngredients', effIngredients)
    s:set('baseEffectIngredients', baseIngredients)
end

--- Record a discovered ingredient ID. GLOBAL context only (writes storage).
--- Deduplicates against the stored list.
function M.discoverIngredient(ingredientId)
    if not ingredientId or type(ingredientId) ~= 'string' or ingredientId == '' then
        return
    end
    local s = discoveredSection()
    local ids = s:getCopy('ids') or {}
    for _, id in ipairs(ids) do
        if id == ingredientId then
            return
        end
    end
    ids[#ids + 1] = ingredientId
    s:set('ids', ids)
end

--- All discovered ingredient IDs (array).
function M.getDiscovered()
    return storage.globalSection(DISCOVERED_SECTION):get('ids') or {}
end

local function discoveredSet()
    local seen = {}
    for _, id in ipairs(M.getDiscovered()) do
        seen[id] = true
    end
    return seen
end

local function filterDiscovered(ids, discoveredOnly)
    if not discoveredOnly then
        return ids
    end
    local seen = discoveredSet()
    local out = {}
    for _, id in ipairs(ids) do
        if seen[id] then
            out[#out + 1] = id
        end
    end
    return out
end

--- Effect list (array of compound strings, read-only) for one ingredient, or nil.
function M.getIngredientEffects(ingredientId)
    local idx = readIndex()
    if not idx.ingredientEffects then
        return nil
    end
    return idx.ingredientEffects[ingredientId]
end

--- Ingredient IDs having the given effect (any attribute/skill variant).
function M.queryByEffect(effectId, discoveredOnly)
    local ids = nil
    if type(effectId) == 'string' then
        local idx = readIndex()
        ids = idx.baseEffectIngredients and idx.baseEffectIngredients[effectId] or nil
    end
    if not ids then
        return {}
    end
    return filterDiscovered(ids, discoveredOnly)
end

--- Ingredient IDs sharing at least one effect with the given ingredient
--- (the ingredient itself is excluded).
function M.querySharedWith(ingredientId, discoveredOnly)
    local effList = type(ingredientId) == 'string' and M.getIngredientEffects(ingredientId) or nil
    if not effList then
        return {}
    end
    local idx = readIndex()
    local disc = discoveredOnly and discoveredSet() or nil
    local seen = { [ingredientId] = true }
    local out = {}
    for _, entry in ipairs(effList) do
        local ids = idx.baseEffectIngredients and idx.baseEffectIngredients[entry:match('^[^~]*')] or nil
        if ids then
            for _, id in ipairs(ids) do
                if not seen[id] then
                    seen[id] = true
                    if not disc or disc[id] then
                        out[#out + 1] = id
                    end
                end
            end
        end
    end
    return out
end

--- Map of effectId -> { ingredients = ids } for the given effect IDs.
--- Minimal shape consumed by alchemy-ui (names/recipes unimplemented).
function M.queryEffects(effectIds)
    local idx = readIndex()
    local out = {}
    for _, effId in ipairs(effectIds or {}) do
        if type(effId) == 'string' then
            local ids = idx.baseEffectIngredients and idx.baseEffectIngredients[effId] or nil
            if ids then
                out[effId] = { ingredients = ids }
            end
        end
    end
    return out
end

return M
