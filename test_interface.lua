-- Standalone check for shared/db query functions. Run: lua test_interface.lua
package.path = './?.lua;' .. package.path
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

-- Seed like load-db.lua does (compound "effId~attribute~skill" keys)
db.ingredientEffects = {
    a = { 'health~Health' },
    b = { 'health~Magicka', 'fire~' },
    c = { 'frost~' },
}
db.discoveredIngredients = {}
db.discoverIngredient('a')
db.discoverIngredient('c')
db.rebuildIndexes()

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

-- getDiscovered
expectEqual(asSet(db.getDiscovered()), { a = true, c = true }, 'getDiscovered')

-- queryEffects (UI shape): map of effectId -> { ingredients = ... }
local qe = db.queryEffects({ 'fire', 'nope' })
assert(qe.fire and #qe.fire.ingredients == 1 and qe.fire.ingredients[1] == 'b', 'queryEffects fire')
assert(qe.nope == nil, 'queryEffects unknown effect omitted')

print('OK: all db interface checks passed')
