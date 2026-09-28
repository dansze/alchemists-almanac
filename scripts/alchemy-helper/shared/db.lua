local M = {}

M.ingredientEffects = {}
M.effectIngredients = {}
M.baseEffectIngredients = {}
M.discoveredIngredients = {}

--- Discover a single ingredient ID.
--- Deduplicates (checks discoveredMap), inserts if new.
function M.discoverIngredient(ingredientId)
    if not ingredientId or type(ingredientId) ~= 'string' or ingredientId == '' then
        return
    end
    if M.discoveredIngredients[ingredientId] then
        return
    end
    M.discoveredIngredients[ingredientId] = true
end

--- Rebuild effect indexes from ingredientEffects.
--- ingredientEffects entries are compound strings "effId~attribute~skill"
--- (empty parts omitted, '~' separated). effectIngredients is keyed by the
--- full compound string; baseEffectIngredients by the bare effect ID.
function M.rebuildIndexes()
    M.effectIngredients = {}
    M.baseEffectIngredients = {}
    for ingId, effList in pairs(M.ingredientEffects) do
        for _, entry in ipairs(effList) do
            local base = entry:match('^[^~]*')
            if not M.effectIngredients[entry] then
                M.effectIngredients[entry] = {}
            end
            local entries = M.effectIngredients[entry]
            entries[#entries + 1] = ingId

            if not M.baseEffectIngredients[base] then
                M.baseEffectIngredients[base] = {}
            end
            local baseEntries = M.baseEffectIngredients[base]
            baseEntries[#baseEntries + 1] = ingId
        end
    end
end

local function filterDiscovered(ids, discoveredOnly)
    local out = {}
    for _, id in ipairs(ids) do
        if not discoveredOnly or M.discoveredIngredients[id] then
            out[#out + 1] = id
        end
    end
    return out
end

--- Ingredient IDs having the given effect (any attribute/skill variant).
function M.queryByEffect(effectId, discoveredOnly)
    local ids = type(effectId) == 'string' and M.baseEffectIngredients[effectId] or nil
    if not ids then
        return {}
    end
    return filterDiscovered(ids, discoveredOnly)
end

--- Ingredient IDs sharing at least one effect with the given ingredient
--- (the ingredient itself is excluded).
function M.querySharedWith(ingredientId, discoveredOnly)
    local effList = type(ingredientId) == 'string' and M.ingredientEffects[ingredientId] or nil
    if not effList then
        return {}
    end
    local seen = { [ingredientId] = true }
    local out = {}
    for _, entry in ipairs(effList) do
        local ids = M.baseEffectIngredients[entry:match('^[^~]*')]
        if ids then
            for _, id in ipairs(ids) do
                if not seen[id] then
                    seen[id] = true
                    if not discoveredOnly or M.discoveredIngredients[id] then
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
    local out = {}
    for _, effId in ipairs(effectIds or {}) do
        if type(effId) == 'string' then
            local ids = M.baseEffectIngredients[effId]
            if ids then
                out[effId] = { ingredients = ids }
            end
        end
    end
    return out
end

--- All discovered ingredient IDs.
function M.getDiscovered()
    local out = {}
    for id in pairs(M.discoveredIngredients) do
        out[#out + 1] = id
    end
    return out
end

return M
