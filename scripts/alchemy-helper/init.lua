-- Alchemist's Almanac — Alchemy Lookup Tables
-- Pre-computes all static lookup tables required for the OpenMW alchemy effect system.
-- Replicates the MWMechanics::Alchemy C++ logic:
--   ingredient effects from types.Ingredient.records
--   pair effects via intersection of two ingredient effect sets
--   triple effects via union-of-pairwise-intersections of three ingredient effect sets
--   shared ingredients via intersection of all ingredients providing each effect
--   magnitude ranges derived from magic effect baseCost and GMST alchemy settings
--
-- This script runs at module load time (LOAD context). All tables are pre-computed
-- into plain Lua values (no functions, metatables, or circular references) for
-- sandbox and save serialization compatibility.

local types = require('openmw.types')
local content = require('openmw.content')
local core = require('openmw.core')

local gmstPotionStrengthMult = core.getGMST('fPotionStrengthMult')
local gmstPotionT1MagMul = core.getGMST('fPotionT1MagMult')

-- Build a lookup from effect ID to magic effect record data (name, baseCost, flags).
local magicEffectData = {}
local effectNames = {}
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

-- MagicEffect NoMagnitude flag bitmask.
local MGF_NO_MAGNITUDE = 8

-- Build ingredientEffects: maps ingredient ID to list of effect IDs.
-- For effects with magnitude (NoMagnitude flag unset), stores {id, minMagMult, maxMagMult}.
-- Magnitude multiplier range derived from the C++ formula:
--   magnitude = x / fPotionT1MagMul / baseCost
--   where x = (AlchemySkill + 0.1*Intelligence + 0.1*Luck) * mortarQuality * fPotionStrengthMult
--   min: skill=0, mortarQuality=0.5 → x = 0.5 * fPotionStrengthMult
--   max: skill=100, mortarQuality=1.0 → x = 100 * fPotionStrengthMult
local ingredientEffects = {}
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
                        if (me.flags and (me.flags & MGF_NO_MAGNITUDE)) == 0 then
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

-- Build effectIngredients: reverse map from effect ID to sorted list of ingredient IDs.
local effectIngredients = {}
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

-- Build pairEffects: maps sorted "id1:id2" to the list of shared effect IDs.
-- C++ listEffects() for 2 ingredients: iterates all effects of ingredient A,
-- checks if each exists on ingredient B (by full EffectKey including attribute/skill),
-- collects the matching effects.
-- Here we match by effect ID only (same as the effect ID used in lookup tables).
local pairEffects = {}
local ingredientIds = {}
for ingId in pairs(ingredientEffects) do
    ingredientIds[#ingredientIds + 1] = ingId
end
local n = #ingredientIds
for i = 1, n - 1 do
    for j = i + 1, n do
        local a = ingredientIds[i]
        local b = ingredientIds[j]
        -- Canonical sorted key
        local key
        if a < b then
            key = a .. ':' .. b
        else
            key = b .. ':' .. a
        end
        -- Intersection: find effects common to both ingredients
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

-- Build tripleEffects: maps sorted "id1:id2:id3" to the list of shared effect IDs.
-- C++ listEffects() for 3+ ingredients: iterates all pairs (slotI, slotJ) with slotI < slotJ,
-- for each pair collects effects from slotI that also exist on slotJ.
-- Result = union of all pairwise intersections.
local tripleEffects = {}
for i = 1, n - 2 do
    for j = i + 1, n - 1 do
        for k = j + 1, n do
            local a = ingredientIds[i]
            local b = ingredientIds[j]
            local c = ingredientIds[k]
            -- Canonical sorted key
            if a > b or b > c or a > c then
                -- Re-sort a, b, c
                if a > b then a, b = b, a end
                if b > c then b, c = c, b end
                if a > b then a, b = b, a end
            end
            local key = a .. ':' .. b .. ':' .. c
            -- Pairwise intersections: A∩B ∪ A∩C ∪ B∩C
            local effectsA = ingredientEffects[a]
            local effectsB = ingredientEffects[b]
            local effectsC = ingredientEffects[c]
            local result = {}
            local seen = {}
            -- A ∩ B
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
            -- A ∩ C
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
            -- B ∩ C
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

-- Build recipeEffects: maps any ingredient set key to its predicted effects.
-- For 2 ingredients: pair intersection.
-- For 3+ ingredients: union-of-pairwise-intersections (matches C++ listEffects()).
local recipeEffects = {}

-- Process 2-ingredient combinations (reuse pairEffects data)
for key, effs in pairs(pairEffects) do
    recipeEffects[key] = effs
end

-- Process 3-ingredient combinations (reuse tripleEffects data)
for key, effs in pairs(tripleEffects) do
    recipeEffects[key] = effs
end

-- Build sharedIngredients: maps sorted effect ID key "effect1:effect2:..."
-- to the single ingredient that provides ALL listed effects simultaneously.
-- Single-effect keys are bare effect IDs (e.g. "FireDamage").
-- Multi-effect keys are colon-separated sorted effect IDs (e.g.
-- "DamageHealth:FireDamage").
local sharedIngredients = {}

-- Single-effect entries: effectId → first ingredient that provides it
for effId, ingList in pairs(effectIngredients) do
    if #ingList >= 1 then
        sharedIngredients[effId] = ingList[1]
    end
end

-- Multi-effect entries: for each ingredient with 2+ effects, build
-- the sorted effect key and map it to this ingredient.
for ingId, effList in pairs(ingredientEffects) do
    if #effList >= 2 then
        local effs = {}
        for _, e in ipairs(effList) do
            effs[#effs + 1] = e[1]
        end
        -- Insertion sort for canonical key
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

-- Export the complete lookup table.
-- All subtables contain only plain Lua values: nil, strings, numbers, nested plain tables.
-- No functions, no metatables, no circular references.
return {
    ingredientEffects = ingredientEffects,
    effectIngredients = effectIngredients,
    pairEffects = pairEffects,
    tripleEffects = tripleEffects,
    recipeEffects = recipeEffects,
    sharedIngredients = sharedIngredients,
    effectNames = effectNames,
}
