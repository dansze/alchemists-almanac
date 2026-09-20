-- Alchemist's Almanac — Alchemy Effect Database + Settings Registration (LOAD context)
--
-- Runs once during content load. Builds the complete effect lookup database
-- from `content.ingredients.records` and `content.magicEffects.records`,
-- then registers `queryEffects(ids)` on `interfaces.AlchemyHelper`.
--
-- Also registers the Settings page / group / keybind field so users can
-- view and change the alchemy-helper keybind in-game.  Settings
-- persistence is handled by `openmw.interfaces.Settings` — no custom
-- config files or ad-hoc storage.
--
-- All tables live at module scope. `queryEffects` is a live closure over them
-- — nothing is serialized. Database is fully rebuilt from scratch on every
-- LOAD event.
--
-- Constraints: Lua 5.1 sandbox only. No `openmw.world.*` calls
-- (world not initialized in LOAD). No prohibited ops.

local content = require('openmw.content')
local I = require('openmw.interfaces')

-- ── Settings registration (AlchemyHelper keybind) ──────────────────────────
-- Registered once per LOAD; idempotent.  Value is read by alchemy-binding.lua
-- via openmw.storage on each onKeyPress invocation.

I.Settings.registerPage {
    key = 'AlchemyHelper',
    l10n = 'AlchemyHelper',
    name = 'AlchemyHelper',
    description = 'AlchemyHelper',
}

I.Settings.registerGroup {
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

local function logError(msg)
    if type(print) == 'function' then
        print('[AlchemyHelper] ' .. tostring(msg))
    end
end

-- ponytail: build happens once per LOAD; if it ever exceeds 1s we can
--           add incremental caching with a generation counter.

-- ── Step 1: magic effect metadata ──────────────────────────────────────────
-- Build a lookup from effect ID to magic effect record data.
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

-- MagicEffect NoMagnitude flag bitmask (same as init.lua for consistency).
local MGF_NO_MAGNITUDE = 8

-- ── Step 2: ingredientEffects ──────────────────────────────────────────────
-- ingredientEffects[ingId] = { {effId, minMagMult?, maxMagMult?}, ... }
local ingredientEffects = {}
local success, err = pcall(function()
    for _, ing in ipairs(content.ingredients.records) do
        if ing and ing.id and ing.id ~= '' then
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
                                local potionStrength = 1.0  -- fPotionStrengthMult not available in LOAD without core
                                local minMagMult = (0.5 * potionStrength) / baseCost
                                local maxMagMult = (100 * potionStrength) / baseCost
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

-- ── Step 3: effectIngredients ──────────────────────────────────────────────
-- effectIngredients[effId] = { ingId1, ingId2, ... }
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

-- ── Step 4: pairEffects ────────────────────────────────────────────────────
-- pairEffects["ing1:ing2"] = { effId1, effId2, ... }
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

-- ── Step 5: tripleEffects ──────────────────────────────────────────────────
-- tripleEffects["ing1:ing2:ing3"] = { effId1, effId2, ... }
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

-- ── Step 6: recipeEffects ──────────────────────────────────────────────────
-- recipeEffects[key] = { effId1, effId2, ... }
-- For 2-ingredient keys: same data as pairEffects.
-- For 3-ingredient keys: same data as tripleEffects.
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

-- ── Step 7: sharedIngredients ──────────────────────────────────────────────
-- sharedIngredients[effKey] = ingId
-- Single-effect key: bare effect ID.
-- Multi-effect key: colon-separated sorted effect IDs.
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

-- ── Step 8: reverse indices ────────────────────────────────────────────────
-- effectToPairKeys[effId] = { "ing1:ing2", ... }
-- effectToTripleKeys[effId] = { "ing1:ing2:ing3", ... }
-- effectToRecipeKeys[effId] = { pair_keys ∪ triple_keys, ... }
local effectToPairKeys = {}
local effectToTripleKeys = {}
local effectToRecipeKeys = {}
local success, err = pcall(function()
    for pairKey, effs in pairs(pairEffects) do
        for _, effId in ipairs(effs) do
            if not effectToPairKeys[effId] then
                effectToPairKeys[effId] = {}
            end
            effectToPairKeys[effId][#effectToPairKeys[effId] + 1] = pairKey
            if not effectToRecipeKeys[effId] then
                effectToRecipeKeys[effId] = {}
            end
            effectToRecipeKeys[effId][#effectToRecipeKeys[effId] + 1] = pairKey
        end
    end

    for tripleKey, effs in pairs(tripleEffects) do
        for _, effId in ipairs(effs) do
            if not effectToTripleKeys[effId] then
                effectToTripleKeys[effId] = {}
            end
            effectToTripleKeys[effId][#effectToTripleKeys[effId] + 1] = tripleKey
            if not effectToRecipeKeys[effId] then
                effectToRecipeKeys[effId] = {}
            end
            effectToRecipeKeys[effId][#effectToRecipeKeys[effId] + 1] = tripleKey
        end
    end
end)
if not success and type(logError) == 'function' then logError('reverse indices build: ' .. tostring(err)) end

-- ── Step 9: queryEffects registration ──────────────────────────────────────
-- Returns, for each requested effect ID, all lookup-table data.
local function queryEffects(ids)
    local result = {}
    for _, effId in ipairs(ids) do
        local ingredients = effectIngredients[effId] or {}
        local sharedIngredient = sharedIngredients[effId]
        local pairs = effectToPairKeys[effId] or {}
        local triples = effectToTripleKeys[effId] or {}
        local recipes = effectToRecipeKeys[effId] or {}
        result[effId] = {
            ingredients = ingredients,
            sharedIngredient = sharedIngredient,
            pairs = pairs,
            triples = triples,
            recipes = recipes,
        }
    end
    return result
end

-- ── Return module table (OpenMW interface registration pattern) ────────────
-- The `interface` field is picked up by `require('openmw.interfaces')` and
-- mounted as `interfaces.AlchemyHelper`.
return {
    interfaceName = 'AlchemyHelper',
    interface = {
        queryEffects = queryEffects,
    },
    engineHandlers = {
        -- No-op onUpdate; the database is fully built above during LOAD.
        -- Other scripts call interfaces.AlchemyHelper.queryEffects(ids).
        onUpdate = function() end,
    },
}
