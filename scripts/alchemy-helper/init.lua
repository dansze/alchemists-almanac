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
-- For effects with magnitude (NoMagnitude flag unset), stores {id, minMagMult, maxMagMult}.
-- Magnitude multiplier range derived from the C++ formula:
--   magnitude = x / fPotionT1MagMul / baseCost
--   where x = (AlchemySkill + 0.1*Intelligence + 0.1*Luck) * mortarQuality * fPotionStrengthMult
--   min: skill=0, mortarQuality=0.5 -> x = 0.5 * fPotionStrengthMult
--   max: skill=100, mortarQuality=1.0 -> x = 100 * fPotionStrengthMult
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
-- Must be outside the pcall so tripleEffects can access it.
local ingredientIds = {}
for ingId in pairs(ingredientEffects) do
    ingredientIds[#ingredientIds + 1] = ingId
end
local n = #ingredientIds

-- Build pairEffects: maps sorted "id1:id2" to the list of shared effect IDs.
-- C++ listEffects() for 2 ingredients: iterates all effects of ingredient A,
-- checks if each exists on ingredient B (by full EffectKey including attribute/skill),
-- collects the matching effects.
-- Here we match by effect ID only (same as the effect ID used in lookup tables).
local pairEffects = {}
local success, err = pcall(function()
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
end)
if not success and type(logError) == 'function' then logError('pairEffects build: ' .. tostring(err)) end

-- Build tripleEffects: maps sorted "id1:id2:id3" to the list of shared effect IDs.
-- C++ listEffects() for 3+ ingredients: iterates all pairs (slotI, slotJ) with slotI < slotJ,
-- for each pair collects effects from slotI that also exist on slotJ.
-- Result = union of all pairwise intersections.
local tripleEffects = {}
local success, err = pcall(function()
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
end)
if not success and type(logError) == 'function' then logError('tripleEffects build: ' .. tostring(err)) end

-- Build recipeEffects: maps any ingredient set key to its predicted effects.
-- For 2 ingredients: pair intersection.
-- For 3+ ingredients: union-of-pairwise-intersections (matches C++ listEffects()).
local recipeEffects = {}
local success, err = pcall(function()
    -- Process 2-ingredient combinations (reuse pairEffects data)
    for key, effs in pairs(pairEffects) do
        recipeEffects[key] = effs
    end
    -- Process 3-ingredient combinations (reuse tripleEffects data)
    for key, effs in pairs(tripleEffects) do
        recipeEffects[key] = effs
    end
end)
if not success and type(logError) == 'function' then logError('recipeEffects build: ' .. tostring(err)) end

-- Build sharedIngredients: maps sorted effect ID key "effect1:effect2:..."
-- to the single ingredient that provides ALL listed effects simultaneously.
-- Single-effect keys are bare effect IDs (e.g. "FireDamage").
-- Multi-effect keys are colon-separated sorted effect IDs (e.g.
-- "DamageHealth:FireDamage").
local sharedIngredients = {}
local success, err = pcall(function()
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
end)
if not success and type(logError) == 'function' then logError('sharedIngredients build: ' .. tostring(err)) end

-- Export the complete lookup table.
-- All subtables contain only plain Lua values: nil, strings, numbers, nested plain tables.
-- No functions, no metatables, no circular references.

-- ── Persistence: discovered recipes & preferences ──────────────────────────
-- Module-level plain Lua table. No functions, metatables, or userdata.
-- Keys are canonical sorted-string ingredient combos: "id1:id2", "id1:id2:id3".
local discoveredMap = {}

-- User UI preferences placeholder. Plain table, no metatables.
local preferences = {}

--- Resolve a potion base ID to a deduplicated list of distinct ingredient IDs.
--- Checks content.potions.record first, then types.Potion.record.
--- Returns nil if the potion record has no ingredient data.
local function getPotionIngredients(potionId)
    if not potionId or type(potionId) ~= 'string' or potionId == '' then
        return nil
    end
    local record = content.potions and content.potions.record(potionId)
    if record then
        local ingredients = {}
        if record.effects then
            for _, eff in ipairs(record.effects) do
                if eff and eff.ingredient then
                    ingredients[#ingredients + 1] = eff.ingredient
                end
            end
        end
        if #ingredients > 0 then return ingredients end
    end
    record = types.Potion and types.Potion.record(potionId)
    if record then
        local ingredients = {}
        if record.effects then
            for _, eff in ipairs(record.effects) do
                if eff and eff.ingredient then
                    ingredients[#ingredients + 1] = eff.ingredient
                end
            end
        end
        if #ingredients > 0 then return ingredients end
    end
    return nil
end

--- Discover a recipe from ingredient IDs.
--- Deduplicates, sorts, builds canonical key, and inserts into discoveredMap
--- if the key exists in pairEffects or tripleEffects.
local function discoverRecipe(ingredientIds)
    if not ingredientIds or #ingredientIds == 0 then return end
    local seen = {}
    local distinct = {}
    for _, id in ipairs(ingredientIds) do
        if type(id) == 'string' and id ~= '' and not seen[id] then
            seen[id] = true
            distinct[#distinct + 1] = id
        end
    end
    local n = #distinct
    if n < 2 or n > 3 then return end
    table.sort(distinct)
    local key
    if n == 2 then
        key = distinct[1] .. ':' .. distinct[2]
    else
        key = distinct[1] .. ':' .. distinct[2] .. ':' .. distinct[3]
    end
    if pairEffects[key] or tripleEffects[key] then
        discoveredMap[key] = true
    end
end

--- onSave handler: serialize discoveredMap into versioned schema.
--- Returns plain table: { version = 1, discovered = { keys... }, preferences = {} }
--- No functions, metatables, userdata, or non-serializable values.
local function onSave()
    local discovered = {}
    for key in pairs(discoveredMap) do
        discovered[#discovered + 1] = key
    end
    return {
        version = 1,
        discovered = discovered,
        preferences = preferences,
    }
end

--- onLoad handler: deserialize, migrate, restore, re-discover from inventory.
local function onLoad(saved)
    if not saved then return end

    -- Version-gated migration switch.
    local version = saved.version
    if version == 1 then
        -- No migration needed for v1.
    elseif version == 2 then
        -- Migration from v2 (stub).
    elseif version == 3 then
        -- Migration from v3 (stub).
    else
        -- Unknown version — reject silently.
        return
    end

    -- Restore discovered recipes from saved array.
    if saved.discovered then
        for _, key in ipairs(saved.discovered) do
            discoveredMap[key] = true
        end
    end

    -- Restore preferences.
    if saved.preferences then
        for k, v in pairs(saved.preferences) do
            preferences[k] = v
        end
    end

    -- Re-discover recipes for potions already in player inventory at load time.
    local inventory = openmw.player and openmw.player.getInventory and openmw.player.getInventory()
    if inventory then
        for _, item in ipairs(inventory) do
            local baseId = item.getBaseId and item:getBaseId()
            if not baseId then baseId = item.baseId end
            if not baseId then baseId = item.refId end
            if baseId and type(baseId) == 'string' and baseId ~= '' then
                local ingredients = getPotionIngredients(baseId)
                if ingredients then
                    discoverRecipe(ingredients)
                end
            end
        end
    end
end

--- onObjectAdded handler: filter to player inventory, resolve, discover.
--- Rejects world/container spawns; only processes player-inventory potions.
local function onObjectAdded(object)
    if not object then return end

    -- Confirm object belongs to player's inventory via reference comparison.
    local inventory = openmw.player and openmw.player.getInventory and openmw.player.getInventory()
    local isPlayerItem = false
    if inventory then
        for _, item in ipairs(inventory) do
            if item == object then
                isPlayerItem = true
                break
            end
        end
    end
    if not isPlayerItem then return end

    -- Get potion base ID.
    local baseId = object.getBaseId and object:getBaseId()
    if not baseId then baseId = object.baseId end
    if not baseId then baseId = object.refId end
    if not baseId or type(baseId) ~= 'string' or baseId == '' then return end

    -- Resolve ingredients and discover recipe.
    local ingredients = getPotionIngredients(baseId)
    if ingredients then
        discoverRecipe(ingredients)
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
    engineHandlers = {
        onSave = onSave,
        onLoad = onLoad,
        onObjectAdded = onObjectAdded,
    },
}
