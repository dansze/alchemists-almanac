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
    { id = 'a', name = 'Blue Mountain', icon = 'n\\tx_a.tga',
      effects = { { id = 'health', affectedAttribute = 'Health' } } },
    { id = 'b', name = 'Almsivito', icon = 'n\\tx_b.tga',
      effects = { { id = 'health', affectedAttribute = 'Magicka' }, { id = 'fire' } } },
    { id = 'c', name = 'Trebactadine', icon = 'n\\tx_c.tga', effects = { { id = 'frost' } } },
    { id = 'e', name = 'Alitortoise Egg',
      effects = { { id = 'health', affectedAttribute = 'Health' } } }, -- same compound as a
    { id = '', effects = {} },              -- skipped: empty id
    { id = 'd', effects = { nil, { id = '' } } },  -- no usable effects (name falls back to id)
}
db.storeIndexes(db.buildIngredientEffects(records))
db.storeIngredientInfo(db.buildIngredientInfo(records))
assert(db.getIngredientEffects('a')[1] == 'health~Health', 'compound key attr')
assert(db.getIngredientEffects('b')[2] == 'fire', 'bare effId, no trailing separator')

-- Discovered: dedupe + Persistent section
db.discoverIngredient('a')
db.discoverIngredient('c')
db.discoverIngredient('a') -- duplicate, must not double-store
db.discoverIngredient(nil) -- ignored
expectEqual(asSet(db.getDiscovered()), { a = true, c = true }, 'getDiscovered')

-- queryByEffect: matches all attribute/skill variants of an effect
expectEqual(asSet(db.queryByEffect('health')), { a = true, b = true, e = true }, 'queryByEffect health')
expectEqual(asSet(db.queryByEffect('frost')), { c = true }, 'queryByEffect frost')
assert(#db.queryByEffect('nope') == 0, 'queryByEffect unknown effect')

-- discoveredOnly filter
expectEqual(asSet(db.queryByEffect('health', true)), { a = true }, 'queryByEffect health discovered-only')

-- querySharedWith: shares >=1 effect, excludes the ingredient itself
expectEqual(asSet(db.querySharedWith('a')), { b = true, e = true }, 'querySharedWith a')
expectEqual(asSet(db.querySharedWith('b')), { a = true, e = true }, 'querySharedWith b')
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

-- Merchants: store + union on re-encounter + Persistent section
db.discoverMerchant('merchant_a', 'Aldori', { 'a', 'c' })
db.discoverMerchant('merchant_a', 'Aldori', { 'c', 'b' }) -- union, no dupes
assert(db.getMerchants().merchant_a.name == 'Aldori', 'merchant name')
expectEqual(asSet(db.getMerchants().merchant_a.ingredients), { a = true, b = true, c = true }, 'merchant restock union')
db.discoverMerchant('merchant_b', nil, {}) -- merchant without restocking supply
assert(db.getMerchants().merchant_b and #db.getMerchants().merchant_b.ingredients == 0, 'merchant empty restock')
db.discoverMerchant(nil, 'x', {}) -- ignored
assert(db.getMerchants().x == nil, 'merchant nil id ignored')
-- merchants live in the same Persistent section as discovered ingredients
local stored = require('openmw.storage').globalSection('AlchemyHelperDiscovered'):asTable()
assert(stored.ids and stored.merchants, 'merchants stored in discovered section')

-- Display info + ingredient list (sorted by name, case-insensitive)
assert(db.getIngredientInfo('b').name == 'Almsivito', 'getIngredientInfo name')
assert(db.getIngredientInfo('b').icon == 'n\\tx_b.tga', 'getIngredientInfo icon')
assert(db.getIngredientInfo('nope') == nil, 'getIngredientInfo unknown')
local all = db.getIngredientList(false)
local names = {}
for _, it in ipairs(all) do names[#names + 1] = it.name end
assert(table.concat(names, '|') == 'Alitortoise Egg|Almsivito|Blue Mountain|d|Trebactadine',
    'getIngredientList sort: ' .. table.concat(names, '|'))
assert(all[3].icon == 'n\\tx_a.tga' and #all[3].effects == 1, 'list row carries icon+effects')
local disc = db.getIngredientList(true) -- discovered = a, c
assert(#disc == 2 and disc[1].id == 'a' and disc[2].id == 'c', 'getIngredientList discovered-only')

-- Effect list: distinct compound keys; discoveredOnly filters by ingredient
db.discoverIngredient('e') -- now discovered = a, c, e
local effAll = db.getEffectList(false)
expectEqual(asSet(effAll),
    { ['health~Health'] = true, ['health~Magicka'] = true, fire = true, frost = true },
    'getEffectList all')
local effDisc = db.getEffectList(true) -- a: health~Health, c: frost, e: health~Health
expectEqual(asSet(effDisc), { ['health~Health'] = true, frost = true }, 'getEffectList discovered-only')

-- More merchants for planner queries (with locations)
db.discoverMerchant('sachis', 'Sachis', { 'a' }, 'Sadrith Mora')
db.discoverMerchant('goro', 'Goro', { 'b' }, 'Balmora')
db.discoverMerchant('vevagun', 'Vevagun', { 'a', 'e' }, 'Cheydinhal')
assert(db.getMerchants().sachis.location == 'Sadrith Mora', 'merchant location stored')
db.discoverMerchant('sachis', 'Sachis II', { 'c' }, 'Anvil') -- re-encounter: union + new location
expectEqual(asSet(db.getMerchants().sachis.ingredients), { a = true, c = true }, 're-encounter union')
assert(db.getMerchants().sachis.location == 'Anvil', 'location updated on re-encounter')

-- restockCounts: a -> merchant_a, sachis, vevagun; b -> merchant_a, goro; c -> merchant_a, sachis
local rc = db.restockCounts()
assert(rc.a == 3 and rc.b == 2 and rc.c == 2 and rc.e == 1, 'restockCounts')

-- Planner: no keys -> all merchants with full restocking supply (names)
local allM = db.queryMerchantsForEffects({}, false)
assert(#allM == 5, 'no keys returns all 5 merchants')
local byId = {}
for _, m in ipairs(allM) do byId[m.id] = m end
expectEqual(asSet(byId.merchant_a.ingredients),
    { ['Blue Mountain'] = true, Almsivito = true, Trebactadine = true }, 'no-keys full restock names')
assert(byId.merchant_b and #byId.merchant_b.ingredients == 0, 'no-keys empty restock')

-- Single key, non-strict: >=1 distinct restocking ingredient with that effect
local fireM = db.queryMerchantsForEffects({ 'fire' }, false)
byId = {}
for _, m in ipairs(fireM) do byId[m.id] = m end
assert(#fireM == 2 and byId.merchant_a and byId.goro, 'fire non-strict: merchant_a + goro')
expectEqual(asSet(byId.goro.ingredients), { Almsivito = true }, 'matched = union of selected effects')

-- AND semantics: every selected key must be satisfied
local andM = db.queryMerchantsForEffects({ 'fire', 'frost' }, false)
assert(#andM == 1 and andM[1].id == 'merchant_a', 'AND: only merchant_a has fire+frost')
expectEqual(asSet(andM[1].ingredients),
    { Almsivito = true, Trebactadine = true }, 'AND matched union (b=fire, c=frost)')

-- Strict: >=2 DISTINCT ingredient records per key (same-name dupes count separately)
local strictM = db.queryMerchantsForEffects({ 'health~Health' }, true)
assert(#strictM == 1 and strictM[1].id == 'vevagun', 'strict: only vevagun has 2x health~Health')
expectEqual(asSet(strictM[1].ingredients),
    { ['Blue Mountain'] = true, ['Alitortoise Egg'] = true }, 'strict matched names')
local nonStrictHH = db.queryMerchantsForEffects({ 'health~Health' }, false)
assert(#nonStrictHH == 3, 'non-strict health~Health: merchant_a, sachis, vevagun')

-- Effect display names: collected at init from each record's localized
-- MagicEffect name (eff.effect.name); IDs without an effect record or with
-- an empty name fall back to generated CamelCase. Attribute/skill target
-- names come from the static table.
local nameRecords = {
    { id = 'x1', effects = {
        { id = 'WeaknessToFire', effect = { name = 'Weakness to Fire' } },
        { id = 'FortifyAttribute', affectedAttribute = 'Strength', effect = { name = 'Fortify Attribute' } },
        { id = 'FortifySkill', affectedSkill = 'HandToHand', effect = { name = 'Fortify Skill' } },
        { id = 'SummonCreature04', effect = { name = '' } }, -- no GMST value -> generated
        { id = 'Sleep' }, -- mod-added MGEF, no effect record -> generated
    } },
}
local names = db.buildEffectNames(nameRecords)
assert(names.effectNames.WeaknessToFire == 'Weakness to Fire', 'name collected from localized MagicEffect name')
assert(names.effectNames.SummonCreature04 == 'Summon Creature04', 'empty effect name -> generated (digits stay attached)')
assert(names.effectNames.Sleep == 'Sleep', 'no effect record -> generated name')
assert(names.targetNames.Strength == 'Strength', 'target name: attribute')
assert(names.targetNames.HandToHand == 'Hand-to-hand', 'target name: static GMST spelling')
db.storeEffectNames(names)
local stored = db.getEffectNames()
assert(stored.effectNames.WeaknessToFire == 'Weakness to Fire', 'name maps survive the index section round-trip')
assert(stored.effectNames.Sleep == 'Sleep', 'generated name survives the round-trip')
assert(db.formatEffectName('WeaknessToFire', stored) == 'Weakness to Fire', 'format: bare key')
assert(db.formatEffectName('FortifyAttribute~Strength', stored) == 'Fortify Strength', 'format: attribute swap')
assert(db.formatEffectName('FortifySkill~HandToHand', stored) == 'Fortify Hand-to-hand', 'format: skill swap (GMST spelling)')
assert(db.formatEffectName('FortifySkill~LongBlade', stored) == 'Fortify Long Blade', 'format: multi-word GMST skill name')
assert(db.formatEffectName('WeaknessToFire~Weird', {}) == 'Weakness to Fire Weird', 'format: unmapped target falls back to raw ID')
assert(db.formatEffectName('BrandNewModEffect', {}) == 'Brand New Mod Effect', 'format: unmapped effId gets generated name')

-- Detection reset stamp + gate
assert(db.getLastReset() == 0, 'lastReset defaults to 0')
assert(db.needsDetection(nil, 0), 'never handled -> detect even with no reset')
assert(not db.needsDetection(100, 0), 'handled after default reset -> skip')
db.setLastReset(50)
assert(db.getLastReset() == 50, 'setLastReset stamps the index section')
assert(db.needsDetection(49, 50), 'handled before reset -> re-detect')
assert(not db.needsDetection(50, 50), 'handled at reset time -> skip (strict <)')
assert(not db.needsDetection(51, 50), 'handled after reset -> skip')
assert(db.needsDetection(nil, 50), 'never handled -> detect regardless of reset')
db.setLastReset('not-a-number') -- ignored
assert(db.getLastReset() == 50, 'non-number stamp ignored')

print('OK: all db interface checks passed')
