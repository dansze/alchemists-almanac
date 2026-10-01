-- Alchemist's Almanac — shared ingredient database access.
--
-- Script contexts have isolated Lua states, so module-level tables do NOT
-- share data across scripts. All data lives in openmw.storage global
-- sections; this module only provides functions over those sections.
--
-- Sections:
--   AlchemyHelperIndex      GameSession lifetime — built at global script
--                           start from types.Ingredient.records (init.lua;
--                           the LOAD context has no storage access).
--                           keys: ingredientEffects, effectIngredients,
--                                 baseEffectIngredients, ingredients
--                                 (id -> { name, icon } display info),
--                                 effectNames / targetNames (RefId -> display
--                                 name maps: effect names collected from each
--                                 record's localized MagicEffect name, target
--                                 names static + generated fallback),
--                                 lastReset (game-time seconds of the last
--                                 detection reset; 0/nil = never)
--   AlchemyHelperDiscovered Persistent lifetime — keys:
--                           ids       (array of discovered ingredient IDs)
--                           merchants (map of merchant record ID ->
--                                     { name, ingredients = [restocking
--                                     supply IDs] })
--                           Written by the GLOBAL script only.
--
-- Write paths call setLifeTime; read paths never do (only global-ish
-- contexts may modify sections).

local storage = require('openmw.storage')
local staticNames = require('scripts.alchemy-helper.shared.data.effect-names')

local M = {}

local INDEX_SECTION = 'AlchemyHelperIndex'
local DISCOVERED_SECTION = 'AlchemyHelperDiscovered'

-- Per-context flags: ensure lifetime once per Lua state, on the write path.
local indexLifetimeSet = false
local discoveredLifetimeSet = false

--- Write access to the index section (GLOBAL context). GameSession lifetime.
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

--- Convert a list of ingredient records ({ id, effects = { { id,
--- affectedAttribute?, affectedSkill? } } }) into the ingredientEffects
--- map. Entries are compound strings "effId~attribute~skill" (empty parts
--- omitted, '~' separated).
function M.buildIngredientEffects(records)
    local ingredientEffects = {}
    for _, ing in ipairs(records or {}) do
        if ing and ing.id and ing.id ~= '' then
            local effList = {}
            if ing.effects then
                for _, eff in ipairs(ing.effects) do
                    local effId = eff and eff.id
                    if effId and effId ~= '' then
                        local entry = effId
                        if eff.affectedAttribute then
                            entry = entry .. '~' .. eff.affectedAttribute
                        end
                        if eff.affectedSkill then
                            entry = entry .. '~' .. eff.affectedSkill
                        end
                        effList[#effList + 1] = entry
                    end
                end
            end
            ingredientEffects[ing.id] = effList
        end
    end
    return ingredientEffects
end

--- Store the full ingredientEffects map and rebuild both effect indexes.
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

--- Record a discovered ingredient merchant. GLOBAL context only.
--- An NPC/Creature offering both Barter and Ingredients services.
--- Restocking supply = ingredients held at negative count in its inventory.
--- Re-encounters update the name/location and union the restocking supply.
function M.discoverMerchant(merchantId, name, ingredientIds, location)
    if type(merchantId) ~= 'string' or merchantId == '' then
        return
    end
    local s = discoveredSection()
    local merchants = s:getCopy('merchants') or {}
    local entry = merchants[merchantId]
    if not entry then
        entry = { ingredients = {} }
        merchants[merchantId] = entry
    end
    if type(name) == 'string' and name ~= '' then
        entry.name = name
    end
    if type(location) == 'string' and location ~= '' then
        entry.location = location
    end
    local seen = {}
    for _, id in ipairs(entry.ingredients) do
        seen[id] = true
    end
    for _, id in ipairs(ingredientIds or {}) do
        if type(id) == 'string' and not seen[id] then
            seen[id] = true
            entry.ingredients[#entry.ingredients + 1] = id
        end
    end
    s:set('merchants', merchants)
end

--- All discovered ingredient merchants: map of record ID -> { name, ingredients }.
function M.getMerchants()
    return storage.globalSection(DISCOVERED_SECTION):get('merchants') or {}
end

--- Every ingredient the merchant restocks (union across all encounters) as
-- { name = displayName, value = goldValue } entries sorted by name. {} for
-- unknown merchants or an empty supply.
function M.getMerchantRestock(merchantId)
    if type(merchantId) ~= 'string' then return {} end
    local m = M.getMerchants()[merchantId]
    local info = readIndex().ingredients or {}
    local out = {}
    for _, ingId in ipairs(m and m.ingredients or {}) do
        local meta = info[ingId]
        out[#out + 1] = { name = (meta and meta.name) or ingId, value = (meta and meta.value) or 0 }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

--- Clear all discovered ingredients and merchants. GLOBAL context only.
--- Used by the detection reset so re-detection starts from a clean slate.
function M.clearDiscovered()
    local s = discoveredSection()
    s:set('ids', {})
    s:set('merchants', {})
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
-- Effect/ingredient ids are matched case-insensitively: index keys come from
-- engine-serialized (lowercase) RefIds, callers may pass CamelCase.
function M.queryByEffect(effectId, discoveredOnly)
    local ids = nil
    if type(effectId) == 'string' then
        local idx = readIndex()
        ids = idx.baseEffectIngredients and idx.baseEffectIngredients[effectId:lower()] or nil
    end
    if not ids then
        return {}
    end
    return filterDiscovered(ids, discoveredOnly)
end

--- Ingredient IDs sharing at least one effect with the given ingredient
--- (the ingredient itself is excluded).
function M.querySharedWith(ingredientId, discoveredOnly)
    if type(ingredientId) ~= 'string' or ingredientId == '' then
        return {}
    end
    local id = ingredientId:lower()
    local effList = M.getIngredientEffects(id)
    if not effList then
        return {}
    end
    local idx = readIndex()
    local disc = discoveredOnly and discoveredSet() or nil
    local seen = { [id] = true }
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
            local ids = idx.baseEffectIngredients and idx.baseEffectIngredients[effId:lower()] or nil
            if ids then
                out[effId] = { ingredients = ids }
            end
        end
    end
    return out
end

--- Build the display-info map id -> { name, icon } from ingredient records.
function M.buildIngredientInfo(records)
    local info = {}
    for _, ing in ipairs(records or {}) do
        if ing and ing.id and ing.id ~= '' then
            info[ing.id] = { name = ing.name or ing.id, icon = ing.icon, value = ing.value or 0 }
        end
    end
    return info
end

--- Store the display-info map (GameSession index section).
function M.storeIngredientInfo(info)
    indexSection():set('ingredients', info)
end

-- Display names are generated from CamelCase RefIds at runtime (no engine
-- API exposes MGEF names). One hand-tuned exception keeps the vanilla skill
-- spelling.
-- NOTE: the engine serializes RefIds LOWERCASE into Lua (RefId::serializeText
-- lowercases StringRefIds), so ids arriving from record properties look like
-- "fortifyattribute" / "handtohand". Lookups are therefore case-insensitive,
-- and generated names capitalize the first letter when no CamelCase boundary
-- exists to split on.
local NAME_EXCEPTIONS = { handtohand = 'Hand-to-hand' }

--- Display name for a RefId ("WeaknessToFire" -> "Weakness to Fire",
-- "weaknesstofire" -> "Weaknesstofire").
function M.displayName(id)
    if type(id) ~= 'string' or id == '' then return '' end
    local name = NAME_EXCEPTIONS[id] or NAME_EXCEPTIONS[id:lower()]
    if not name then
        name = id:gsub('([a-z])([A-Z])', '%1 %2'):gsub(' To ', ' to ')
        if not id:find('[A-Z]') then
            name = name:sub(1, 1):upper() .. name:sub(2)
        end
    end
    return name
end

--- Build name maps from ingredient records. Effect display names come
--- straight from the engine: each effect params entry references its
--- MagicEffect record (eff.effect), whose .name is the localized display
--- name — mod-added MGEFs included. IDs whose effect record or name is
--- missing fall back to a generated CamelCase name. Attribute/skill target
--- names come from the static table (no engine API for them), with
--- generation as fallback.
function M.buildEffectNames(records)
    local effectNames = {}
    -- Target names keyed by LOWERCASE id: the engine hands ids to Lua in
    -- lowercase, and formatEffectName looks them up case-insensitively.
    local targetNames = {}
    for k, v in pairs(staticNames.attributes) do targetNames[k:lower()] = v end
    for k, v in pairs(staticNames.skills) do targetNames[k:lower()] = v end
    -- No {attr, skill} table: a nil first entry would hide the second from
    -- ipairs.
    local function addTarget(t)
        if type(t) == 'string' and t ~= '' then
            local key = t:lower()
            if not targetNames[key] then
                targetNames[key] = M.displayName(t)
            end
        end
    end
    for _, ing in ipairs(records or {}) do
        if ing and ing.effects then
            for _, eff in ipairs(ing.effects) do
                local effId = eff and eff.id
                if type(effId) == 'string' and effId ~= '' and not effectNames[effId] then
                    local name = nil
                    local me = eff.effect
                    if me and type(me.name) == 'string' and me.name ~= '' then
                        name = me.name
                    end
                    effectNames[effId] = name or M.displayName(effId)
                end
                addTarget(eff and eff.affectedAttribute)
                addTarget(eff and eff.affectedSkill)
            end
        end
    end
    return { effectNames = effectNames, targetNames = targetNames }
end

--- Store the runtime name maps (GameSession index section).
function M.storeEffectNames(names)
    local s = indexSection()
    s:set('effectNames', names and names.effectNames or {})
    s:set('targetNames', names and names.targetNames or {})
end

--- Name maps { effectNames, targetNames }: the stored (record-built) maps
--- with the static attribute/skill names merged on top. targetNames is keyed
--- by lowercase id (see buildEffectNames).
function M.getEffectNames()
    local idx = readIndex()
    local effectNames = {}
    for k, v in pairs(idx.effectNames or {}) do effectNames[k] = v end
    local targetNames = {}
    for k, v in pairs(idx.targetNames or {}) do targetNames[k:lower()] = v end
    for k, v in pairs(staticNames.attributes) do targetNames[k:lower()] = v end
    for k, v in pairs(staticNames.skills) do targetNames[k:lower()] = v end
    return { effectNames = effectNames, targetNames = targetNames }
end

--- Display name for a compound effect key "effId[~attribute][~skill]" using
-- the runtime name maps (see getEffectNames). Generic effects whose base
-- name ends in "Attribute"/"Skill" swap that word for the target, e.g.
-- "Fortify Attribute" + Strength -> "Fortify Strength". Unmapped IDs fall
-- back to a generated name.
function M.formatEffectName(compoundKey, names)
    if type(compoundKey) ~= 'string' or compoundKey == '' then return '' end
    local effectNames = (names and names.effectNames) or {}
    local targetNames = (names and names.targetNames) or {}
    -- Split on '~' (gmatch avoids pattern-alternation portability issues).
    local parts = {}
    for part in compoundKey:gmatch('[^~]+') do
        parts[#parts + 1] = part
    end
    local effId, attr, skill = parts[1], parts[2], parts[3]
    local name = effectNames[effId] or M.displayName(effId)
    -- Target lookup is case-insensitive: the engine serializes RefIds to
    -- lowercase, the static table ships CamelCase keys.
    local function targetDisplay(t)
        return targetNames[t] or targetNames[t:lower()] or M.displayName(t)
    end
    local target = nil
    if skill and skill ~= '' then
        target = targetDisplay(skill)
    elseif attr and attr ~= '' then
        target = targetDisplay(attr)
    end
    if target then
        -- No '|' alternation: pattern semantics differ across Lua versions.
        local base = name:match('^(.*) Attribute$') or name:match('^(.*) Skill$')
        if base then
            name = base .. ' ' .. target
        else
            name = name .. ' ' .. target
        end
    end
    return name
end

--- Game-time (seconds) of the last detection reset; 0 if never.
function M.getLastReset()
    local v = storage.globalSection(INDEX_SECTION):get('lastReset')
    return type(v) == 'number' and v or 0
end

--- Stamp a detection reset at the given game time (seconds).
--- GLOBAL context only (writes storage).
function M.setLastReset(time)
    if type(time) ~= 'number' then return end
    indexSection():set('lastReset', time)
end

--- Detection gate: an object should (re-)run detection when it has never
--- been handled (lastHandled == nil) or its last-handled game time is
--- before the last-reset stamp.
function M.needsDetection(lastHandled, lastReset)
    return lastHandled == nil or lastHandled < (lastReset or 0)
end

--- Full ingredient list for UI display: array of { id, name, icon,
--- effects = [compoundKeys] }, sorted by name (case-insensitive). When
--- discoveredOnly is set, only discovered ingredients are included.
function M.getIngredientList(discoveredOnly)
    local idx = readIndex()
    local info = idx.ingredients or {}
    local effMap = idx.ingredientEffects or {}
    local disc = discoveredOnly and discoveredSet() or nil
    local out = {}
    for id, meta in pairs(info) do
        if not disc or disc[id] then
            out[#out + 1] = {
                id = id,
                name = meta.name,
                icon = meta.icon,
                value = meta.value or 0,
                effects = effMap[id] or {},
            }
        end
    end
    table.sort(out, function(a, b)
        local la = (a.name or ''):lower()
        local lb = (b.name or ''):lower()
        if la == lb then return (a.id or '') < (b.id or '') end
        return la < lb
    end)
    return out
end

--- Display info { name, icon } for one ingredient, or nil.
function M.getIngredientInfo(ingredientId)
    local idx = readIndex()
    local info = idx.ingredients
    if not info then return nil end
    return info[ingredientId]
end

--- Distinct compound effect keys present across all ingredients (or only
--- discovered ones when discoveredOnly). Array, for the planner's effects list.
function M.getEffectList(discoveredOnly)
    local idx = readIndex()
    local effMap = idx.ingredientEffects or {}
    local disc = discoveredOnly and discoveredSet() or nil
    local seen = {}
    local out = {}
    for id, effs in pairs(effMap) do
        if not disc or disc[id] then
            for _, entry in ipairs(effs) do
                if not seen[entry] then
                    seen[entry] = true
                    out[#out + 1] = entry
                end
            end
        end
    end
    return out
end

--- Map of ingredientId -> number of discovered merchants whose restocking
--- supply includes it.
function M.restockCounts()
    local counts = {}
    for _, m in pairs(M.getMerchants()) do
        for _, ingId in ipairs(m.ingredients or {}) do
            counts[ingId] = (counts[ingId] or 0) + 1
        end
    end
    return counts
end

--- Query merchants against selected compound effects (AND semantics).
--- effectKeys: array of compound effect keys. strict: require >=2 distinct
--- restocking ingredients per effect (otherwise >=1). A merchant qualifies
--- only if it satisfies EVERY selected effect. Returns an array of
--- { id, name, location, ingredients = [restock names matching any key] }.
--- With no keys, all merchants are returned with their full restocking supply.
function M.queryMerchantsForEffects(effectKeys, strict)
    local idx = readIndex()
    local effMap = idx.ingredientEffects or {}
    local info = idx.ingredients or {}
    local merchants = M.getMerchants()

    local need = strict and 2 or 1
    local keys = effectKeys or {}
    local keySet = {}
    for _, k in ipairs(keys) do keySet[k] = true end

    local function nameOf(ingId)
        local meta = info[ingId]
        return (meta and meta.name) or ingId
    end

    local out = {}
    for id, m in pairs(merchants) do
        local restock = m.ingredients or {}
        local perKey = {}  -- key -> count of distinct restocking ingredients
        local matched = {} -- ingredientId -> true (matches any selected key)
        for _, ingId in ipairs(restock) do
            local effs = effMap[ingId]
            if effs then
                for _, entry in ipairs(effs) do
                    if keySet[entry] then
                        matched[ingId] = true
                        perKey[entry] = (perKey[entry] or 0) + 1
                    end
                end
            end
        end
        local ok = true
        for _, k in ipairs(keys) do
            if (perKey[k] or 0) < need then ok = false break end
        end
        if ok then
            local list
            if #keys == 0 then
                list = {}
                for _, ingId in ipairs(restock) do list[#list + 1] = nameOf(ingId) end
            else
                list = {}
                for ingId in pairs(matched) do list[#list + 1] = nameOf(ingId) end
            end
            -- Canonical (sorted) order in both cases: the planner's expanded
            -- row lists getMerchantRestockNames (sorted), and the collapsed
            -- short form must be a prefix of it.
            table.sort(list)
            out[#out + 1] = {
                id = id,
                name = m.name or id,
                location = m.location,
                ingredients = list,
            }
        end
    end
    return out
end

return M
