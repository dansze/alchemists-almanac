-- Alchemist's Almanac — Ingredient Discovery + Lookup Tables
-- Tracks individual alchemy ingredients the player has collected.
-- Pre-computes all static lookup tables for the alchemy effect system.
--
-- Discovery: ingredient IDs inserted into discoveredMap via
--   discoverIngredient(ingredientId) called from ingredient-detect.lua.
-- Save/load: version 2 schema with v1→v2 migration from legacy recipe keys.

local types = require('openmw.types')
local content = require('openmw.content')
local core = require('openmw.core')

local function logError(msg)
    if type(print) == 'function' then
        print('[AlchemyHelper] ' .. tostring(msg))
    end
end

local gmstPotionStrengthMult = core.getGMST('fPotionStrengthMult')
local gmstPotionT1MagMul = core.getGMST('fPotionT1MagMult')

-- Build a lookup from effect ID to magic effect record data (name, baseCost, flags).
local magicEffectData = {}
local effectNames = {}
local success, err = pcall(function()
    for _, mge in ipairs(content.magicEffects.records) do
        if mge.id and mge.id ~= '' then
            local baseCost = mge.mData and mge.mData.baseCost or 0
            local flags = mge.mData and mge.mData.flags or 0
            magicEffectData[mge.id] = {
                name = mge.name or mge.id,
                baseCost = baseCost,
                flags = flags,
            }
            effectNames[mge.id] = mge.name or mge.id
        end
    end
end)
if not success and type(logError) == 'function' then logError('magicEffectData build: ' .. tostring(err)) end

-- MagicEffect NoMagnitude flag bitmask.
local MGF_NO_MAGNITUDE = 8

-- Build ingredientEffects: maps ingredient ID to list of effect IDs.
local ingredientEffects = {}
local success, err = pcall(function()
    for _, ing in ipairs(types.Ingredient.records) do
        if ing.id and ing.id ~= '' then
            local effList = {}
            if ing.effects then
                for _, eff in ipairs(ing.effects) do
                    local effId = eff and eff.id
                    if effId and effId ~= '' then
                        local me = magicEffectData[effId]
                        if me and me.baseCost and me.baseCost > 0 then
                            local entry = { effId }
                            if (me.flags and bit.band(me.flags, MGF_NO_MAGNITUDE)) == 0 then
                                local baseCost = me.baseCost
                                local potionStrength = gmstPotionStrengthMult
                                local minMagMult = (0.5 * potionStrength) / (gmstPotionT1MagMul * baseCost)
                                local maxMagMult = (100 * potionStrength) / (gmstPotionT1MagMul * baseCost)
                                entry[2] = minMagMult
                                entry[3] = maxMagMult
                            end
                            effList[#effList + 1] = entry
                        end
                    end
                end
            end
            ingredientEffects[ing.id] = effList
        end
    end
end)
if not success and type(logError) == 'function' then logError('ingredientEffects build: ' .. tostring(err)) end

-- Build effectIngredients: reverse map from effect ID to sorted list of ingredient IDs.
local effectIngredients = {}
local success, err = pcall(function()
    for ingId, effList in pairs(ingredientEffects) do
        for _, eff in ipairs(effList) do
            local effId = eff[1]
            if not effectIngredients[effId] then
                effectIngredients[effId] = {}
            end
            local entries = effectIngredients[effId]
            local found = false
            for _, v in ipairs(entries) do
                if v == ingId then
                    found = true
                    break
                end
            end
            if not found then
                entries[#entries + 1] = ingId
            end
        end
    end
end)
if not success and type(logError) == 'function' then logError('effectIngredients build: ' .. tostring(err)) end

-- Ingredient ID list shared by pairEffects and tripleEffects builds.
local ingredientIds = {}
for ingId in pairs(ingredientEffects) do
    ingredientIds[#ingredientIds + 1] = ingId
end
local n = #ingredientIds

-- Build pairEffects: maps sorted "id1:id2" to the list of shared effect IDs.
local pairEffects = {}
local success, err = pcall(function()
    for i = 1, n - 1 do
        for j = i + 1, n do
            local a = ingredientIds[i]
            local b = ingredientIds[j]
            local key
            if a < b then
                key = a .. ':' .. b
            else
                key = b .. ':' .. a
            end
            local effectsA = ingredientEffects[a]
            local effectsB = ingredientEffects[b]
            local result = {}
            for _, effA in ipairs(effectsA) do
                local idA = effA[1]
                for _, effB in ipairs(effectsB) do
                    if effB[1] == idA then
                        result[#result + 1] = idA
                        break
                    end
                end
            end
            if #result > 0 then
                pairEffects[key] = result
            end
        end
    end
end)
if not success and type(logError) == 'function' then logError('pairEffects build: ' .. tostring(err)) end

-- Build tripleEffects: maps sorted "id1:id2:id3" to the list of shared effect IDs.
local tripleEffects = {}
local success, err = pcall(function()
    for i = 1, n - 2 do
        for j = i + 1, n - 1 do
            for k = j + 1, n do
                local a = ingredientIds[i]
                local b = ingredientIds[j]
                local c = ingredientIds[k]
                if a > b or b > c or a > c then
                    if a > b then a, b = b, a end
                    if b > c then b, c = c, b end
                    if a > b then a, b = b, a end
                end
                local key = a .. ':' .. b .. ':' .. c
                local effectsA = ingredientEffects[a]
                local effectsB = ingredientEffects[b]
                local effectsC = ingredientEffects[c]
                local result = {}
                local seen = {}
                for _, effA in ipairs(effectsA) do
                    for _, effB in ipairs(effectsB) do
                        if effB[1] == effA[1] then
                            if not seen[effA[1]] then
                                seen[effA[1]] = true
                                result[#result + 1] = effA[1]
                            end
                            break
                        end
                    end
                end
                for _, effA in ipairs(effectsA) do
                    for _, effC in ipairs(effectsC) do
                        if effC[1] == effA[1] then
                            if not seen[effA[1]] then
                                seen[effA[1]] = true
                                result[#result + 1] = effA[1]
                            end
                            break
                        end
                    end
                end
                for _, effB in ipairs(effectsB) do
                    for _, effC in ipairs(effectsC) do
                        if effC[1] == effB[1] then
                            if not seen[effB[1]] then
                                seen[effB[1]] = true
                                result[#result + 1] = effB[1]
                            end
                            break
                        end
                    end
                end
                if #result > 0 then
                    tripleEffects[key] = result
                end
            end
        end
    end
end)
if not success and type(logError) == 'function' then logError('tripleEffects build: ' .. tostring(err)) end

-- Build recipeEffects: maps any ingredient set key to its predicted effects.
local recipeEffects = {}
local success, err = pcall(function()
    for key, effs in pairs(pairEffects) do
        recipeEffects[key] = effs
    end
    for key, effs in pairs(tripleEffects) do
        recipeEffects[key] = effs
    end
end)
if not success and type(logError) == 'function' then logError('recipeEffects build: ' .. tostring(err)) end

-- Build sharedIngredients: maps effect key to ingredient providing all listed effects.
local sharedIngredients = {}
local success, err = pcall(function()
    for effId, ingList in pairs(effectIngredients) do
        if #ingList >= 1 then
            sharedIngredients[effId] = ingList[1]
        end
    end
    for ingId, effList in pairs(ingredientEffects) do
        if #effList >= 2 then
            local effs = {}
            for _, e in ipairs(effList) do
                effs[#effs + 1] = e[1]
            end
            for s = 2, #effs do
                local tmp = effs[s]
                local t = s - 1
                while t >= 1 and effs[t] > tmp do
                    effs[t + 1] = effs[t]
                    t = t - 1
                end
                effs[t + 1] = tmp
            end
            local key = effs[1]
            for s = 2, #effs do
                key = key .. ':' .. effs[s]
            end
            sharedIngredients[key] = ingId
        end
    end
end)
if not success and type(logError) == 'function' then logError('sharedIngredients build: ' .. tostring(err)) end

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

--- onSave handler: serialize discoveredMap into versioned schema.
--- Returns { version = 2, discovered = { "ingId1", ... }, preferences = {} }
local function onSave()
    local discovered = {}
    for ingId in pairs(discoveredMap) do
        discovered[#discovered + 1] = ingId
    end
    return {
        version = 2,
        discovered = discovered,
        preferences = preferences,
    }
end

--- onLoad handler: deserialize, migrate v1→v2, restore.
local function onLoad(saved)
    if not saved then return end

    local version = saved.version
    if version == 1 then
        -- Migration: legacy recipe keys are colon-separated ingredient IDs.
        -- Split each key and insert individual ingredient IDs into discoveredMap.
        if saved.discovered then
            for _, key in ipairs(saved.discovered) do
                for part in string.gmatch(key, '[^:]+') do
                    discoveredMap[part] = true
                end
            end
        end
        -- Restore preferences.
        if saved.preferences then
            for k, v in pairs(saved.preferences) do
                preferences[k] = v
            end
        end
        return
    elseif version == 2 then
        -- Current format: ingredient IDs stored directly.
        -- No migration needed; fall through to restore.
    else
        -- Unknown version — reject silently.
        return
    end

    -- Restore discovered ingredients (v2: ingredient IDs stored directly).
    if saved.discovered then
        for _, ingId in ipairs(saved.discovered) do
            discoveredMap[ingId] = true
        end
    end

    -- Restore preferences.
    if saved.preferences then
        for k, v in pairs(saved.preferences) do
            preferences[k] = v
        end
    end
end

return {
    ingredientEffects = ingredientEffects,
    effectIngredients = effectIngredients,
    pairEffects = pairEffects,
    tripleEffects = tripleEffects,
    recipeEffects = recipeEffects,
    sharedIngredients = sharedIngredients,
    effectNames = effectNames,
    discoverIngredient = discoverIngredient,
    engineHandlers = {
        onSave = onSave,
        onLoad = onLoad,
    },
}
