-- Standalone check for shared/db query functions. Run: lua test_interface.lua
package.path = './?.lua;' .. package.path

-- Minimal in-memory fake of openmw.storage (global sections only).
local sections = {}
local function deepcopy(v)
    if type(v) ~= 'table' then return v end
    local c = {}
    for k, val in pairs(v) do c[k] = deepcopy(val) end
    return c
end
package.preload['openmw.storage'] = function()
    local M = { LIFE_TIME = { GameSession = '1', Persistent = '0', Temporary = '2' } }
    -- Methods take self (colon calls), matching the real API.
    function M.globalSection(name)
        if not sections[name] then sections[name] = {} end
        local data = sections[name]
        return {
            get = function(self, k) return data[k] end, -- real API: readonly tables
            getCopy = function(self, k) return deepcopy(data[k]) end,
            set = function(self, k, v) data[k] = v end,
            asTable = function(self) return deepcopy(data) end, -- real API returns a copy
            setLifeTime = function(self, lt) end,
        }
    end
    return M
end

local db = require('scripts.alchemy-helper.shared.db')

local function asSet(list)
    local s = {}
    for _, v in ipairs(list) do s[v] = true end
    return s
end

local function expectEqual(set, expected, msg)
    for k in pairs(set) do
        if not expected[k] then print('FAIL ' .. msg .. ': unexpected ' .. tostring(k)) end
    end
    for k in pairs(expected) do
        if not set[k] then print('FAIL ' .. msg .. ': missing ' .. tostring(k)) end
    end
end

-- Seed via the real path: records -> buildIngredientEffects -> storeIndexes
local records = {
    { id = 'a', effects = { { id = 'health', affectedAttribute = 'Health' } } },
    { id = 'b', effects = { { id = 'health', affectedAttribute = 'Magicka' }, { id = 'fire' } } },
    { id = 'c', effects = { { id = 'frost' } } },
    { id = '', effects = {} },              -- skipped: empty id
    { id = 'd', effects = { nil, { id = '' } } },  -- skipped: no usable effects
}
db.storeIndexes(db.buildIngredientEffects(records))
assert(db.getIngredientEffects('a')[1] == 'health~Health', 'compound key attr')
assert(db.getIngredientEffects('b')[2] == 'fire', 'bare effId, no trailing separator')

-- Discovered: dedupe + Persistent section
db.discoverIngredient('a')
db.discoverIngredient('c')
db.discoverIngredient('a') -- duplicate, must not double-store
db.discoverIngredient(nil) -- ignored
expectEqual(asSet(db.getDiscovered()), { a = true, c = true }, 'getDiscovered')

-- queryByEffect: matches all attribute/skill variants of an effect
expectEqual(asSet(db.queryByEffect('health')), { a = true, b = true }, 'queryByEffect health')
expectEqual(asSet(db.queryByEffect('frost')), { c = true }, 'queryByEffect frost')
assert(#db.queryByEffect('nope') == 0, 'queryByEffect unknown effect')

-- discoveredOnly filter
expectEqual(asSet(db.queryByEffect('health', true)), { a = true }, 'queryByEffect health discovered-only')

-- querySharedWith: shares >=1 effect, excludes the ingredient itself
expectEqual(asSet(db.querySharedWith('a')), { b = true }, 'querySharedWith a')
expectEqual(asSet(db.querySharedWith('b')), { a = true }, 'querySharedWith b')
expectEqual(asSet(db.querySharedWith('c', true)), {}, 'querySharedWith c discovered-only (a,b undiscovered)')
assert(#db.querySharedWith('nope') == 0, 'querySharedWith unknown ingredient')

-- getIngredientEffects (UI accessor)
local effA = db.getIngredientEffects('a')
assert(effA and #effA == 1 and effA[1] == 'health~Health', 'getIngredientEffects a')
assert(db.getIngredientEffects('nope') == nil, 'getIngredientEffects unknown')

-- queryEffects (UI shape): map of effectId -> { ingredients = ... }
local qe = db.queryEffects({ 'fire', 'nope' })
assert(qe.fire and #qe.fire.ingredients == 1 and qe.fire.ingredients[1] == 'b', 'queryEffects fire')
assert(qe.nope == nil, 'queryEffects unknown effect omitted')

print('OK: all db interface checks passed')
