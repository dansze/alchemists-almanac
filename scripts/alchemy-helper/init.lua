-- Alchemist's Almanac — Ingredient Discovery + Lookup Tables
-- Tracks individual alchemy ingredients the player has collected.
-- Pre-computes all static lookup tables for the alchemy effect system.
--
-- Discovery: ingredient IDs inserted into discoveredMap via
--   discoverIngredient(ingredientId) called from ingredient-detect.lua.
-- Save/load: ingredient discovery and UI preferences.

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
    effectNames = effectNames,
    discoverIngredient = discoverIngredient,
    engineHandlers = {
        onSave = onSave,
        onLoad = onLoad,
    },
}
