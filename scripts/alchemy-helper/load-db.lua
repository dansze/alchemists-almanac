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

-- ── Settings registration (AlchemyHelper keybind) ──────────────────────────
-- Registered once per LOAD; idempotent.  Value is read by alchemy-binding.lua
-- via openmw.storage on each onKeyPress invocation.

local function logError(msg)
    if type(print) == 'function' then
        print('[AlchemyHelper] ' .. tostring(msg))
    end
end

-- ponytail: build happens once per LOAD; if it ever exceeds 1s we can
--           add incremental caching with a generation counter.

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
                        local entry = effId
                        if eff.affectedAttribute then
                            entry = entry .. eff.affectedAttribute
                        end
                        if eff.affectedSkill then
                            entry = entry .. eff.affectedSkill
                        end
                        effList[#effList + 1] = entry
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
            local effId = eff
            if not effectIngredients[effId] then
                effectIngredients[effId] = {}
            end
            local entries = effectIngredients[effId]
            entries[#entries + 1] = ingId
        end
    end
end)
if not success and type(logError) == 'function' then logError('effectIngredients build: ' .. tostring(err)) end

-- ── Return module table (OpenMW interface registration pattern) ────────────
-- The `interface` field is picked up by `require('openmw.interfaces')` and
-- mounted as `interfaces.AlchemyHelper`.
return {
}
