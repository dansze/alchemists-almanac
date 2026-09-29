-- Alchemist's Almanac — static display names for magic effects, attributes,
-- and skills.
--
-- There is no engine API to look up effect display names, so this mod ships
-- its own table. Keys are the exact RefId strings OpenMW exposes on
-- ingredient/potion effect entries (types.Ingredient.records[].effects[].id);
-- they mirror OpenMW's canonical tables (components/esm3/loadmgef.cpp,
-- components/esm/attr.cpp, components/esm3/loadskil.cpp). Unmapped IDs fall
-- back to the raw ID.

local M = {}

--- Magic effect RefId -> display name (all 143 vanilla MGEF records).
M.effects = {
    WaterBreathing = "Water Breathing",
    SwiftSwim = "Swift Swim",
    WaterWalking = "Water Walking",
    Shield = "Shield",
    FireShield = "Fire Shield",
    LightningShield = "Lightning Shield",
    FrostShield = "Frost Shield",
    Burden = "Burden",
    Feather = "Feather",
    Jump = "Jump",
    Levitate = "Levitate",
    SlowFall = "Slow Fall",
    Lock = "Lock",
    Open = "Open",
    FireDamage = "Fire Damage",
    ShockDamage = "Shock Damage",
    FrostDamage = "Frost Damage",
    DrainAttribute = "Drain Attribute",
    DrainHealth = "Drain Health",
    DrainMagicka = "Drain Magicka",
    DrainFatigue = "Drain Fatigue",
    DrainSkill = "Drain Skill",
    DamageAttribute = "Damage Attribute",
    DamageHealth = "Damage Health",
    DamageMagicka = "Damage Magicka",
    DamageFatigue = "Damage Fatigue",
    DamageSkill = "Damage Skill",
    Poison = "Poison",
    WeaknessToFire = "Weakness to Fire",
    WeaknessToFrost = "Weakness to Frost",
    WeaknessToShock = "Weakness to Shock",
    WeaknessToMagicka = "Weakness to Magicka",
    WeaknessToCommonDisease = "Weakness to Common Disease",
    WeaknessToBlightDisease = "Weakness to Blight Disease",
    WeaknessToCorprusDisease = "Weakness to Corprus Disease",
    WeaknessToPoison = "Weakness to Poison",
    WeaknessToNormalWeapons = "Weakness to Normal Weapons",
    DisintegrateWeapon = "Disintegrate Weapon",
    DisintegrateArmor = "Disintegrate Armor",
    Invisibility = "Invisibility",
    Chameleon = "Chameleon",
    Light = "Light",
    Sanctuary = "Sanctuary",
    NightEye = "Night Eye",
    Charm = "Charm",
    Paralyze = "Paralyze",
    Silence = "Silence",
    Blind = "Blind",
    Sound = "Sound",
    CalmHumanoid = "Calm Humanoid",
    CalmCreature = "Calm Creature",
    FrenzyHumanoid = "Frenzy Humanoid",
    FrenzyCreature = "Frenzy Creature",
    DemoralizeHumanoid = "Demoralize Humanoid",
    DemoralizeCreature = "Demoralize Creature",
    RallyHumanoid = "Rally Humanoid",
    RallyCreature = "Rally Creature",
    Dispel = "Dispel",
    Soultrap = "Soultrap",
    Telekinesis = "Telekinesis",
    Mark = "Mark",
    Recall = "Recall",
    DivineIntervention = "Divine Intervention",
    AlmsiviIntervention = "Almsivi Intervention",
    DetectAnimal = "Detect Animal",
    DetectEnchantment = "Detect Enchantment",
    DetectKey = "Detect Key",
    SpellAbsorption = "Spell Absorption",
    Reflect = "Reflect",
    CureCommonDisease = "Cure Common Disease",
    CureBlightDisease = "Cure Blight Disease",
    CureCorprusDisease = "Cure Corprus Disease",
    CurePoison = "Cure Poison",
    CureParalyzation = "Cure Paralyzation",
    RestoreAttribute = "Restore Attribute",
    RestoreHealth = "Restore Health",
    RestoreMagicka = "Restore Magicka",
    RestoreFatigue = "Restore Fatigue",
    RestoreSkill = "Restore Skill",
    FortifyAttribute = "Fortify Attribute",
    FortifyHealth = "Fortify Health",
    FortifyMagicka = "Fortify Magicka",
    FortifyFatigue = "Fortify Fatigue",
    FortifySkill = "Fortify Skill",
    FortifyMaximumMagicka = "Fortify Maximum Magicka",
    AbsorbAttribute = "Absorb Attribute",
    AbsorbHealth = "Absorb Health",
    AbsorbMagicka = "Absorb Magicka",
    AbsorbFatigue = "Absorb Fatigue",
    AbsorbSkill = "Absorb Skill",
    ResistFire = "Resist Fire",
    ResistFrost = "Resist Frost",
    ResistShock = "Resist Shock",
    ResistMagicka = "Resist Magicka",
    ResistCommonDisease = "Resist Common Disease",
    ResistBlightDisease = "Resist Blight Disease",
    ResistCorprusDisease = "Resist Corprus Disease",
    ResistPoison = "Resist Poison",
    ResistNormalWeapons = "Resist Normal Weapons",
    ResistParalysis = "Resist Paralysis",
    RemoveCurse = "Remove Curse",
    TurnUndead = "Turn Undead",
    SummonScamp = "Summon Scamp",
    SummonClannfear = "Summon Clannfear",
    SummonDaedroth = "Summon Daedroth",
    SummonDremora = "Summon Dremora",
    SummonAncestralGhost = "Summon Ancestral Ghost",
    SummonSkeletalMinion = "Summon Skeletal Minion",
    SummonBonewalker = "Summon Bonewalker",
    SummonGreaterBonewalker = "Summon Greater Bonewalker",
    SummonBonelord = "Summon Bonelord",
    SummonWingedTwilight = "Summon Winged Twilight",
    SummonHunger = "Summon Hunger",
    SummonGoldenSaint = "Summon Golden Saint",
    SummonFlameAtronach = "Summon Flame Atronach",
    SummonFrostAtronach = "Summon Frost Atronach",
    SummonStormAtronach = "Summon Storm Atronach",
    FortifyAttack = "Fortify Attack",
    CommandCreature = "Command Creature",
    CommandHumanoid = "Command Humanoid",
    BoundDagger = "Bound Dagger",
    BoundLongsword = "Bound Longsword",
    BoundMace = "Bound Mace",
    BoundBattleAxe = "Bound Battle Axe",
    BoundSpear = "Bound Spear",
    BoundLongbow = "Bound Longbow",
    ExtraSpell = "Extra Spell",
    BoundCuirass = "Bound Cuirass",
    BoundHelm = "Bound Helm",
    BoundBoots = "Bound Boots",
    BoundShield = "Bound Shield",
    BoundGloves = "Bound Gloves",
    Corprus = "Corprus",
    Vampirism = "Vampirism",
    SummonCenturionSphere = "Summon Centurion Sphere",
    SunDamage = "Sun Damage",
    StuntedMagicka = "Stunted Magicka",
    SummonFabricant = "Summon Fabricant",
    SummonWolf = "Summon Wolf",
    SummonBear = "Summon Bear",
    SummonBonewolf = "Summon Bonewolf",
    SummonCreature04 = "Summon Creature04",
    SummonCreature05 = "Summon Creature05",
}

--- Attribute RefId -> display name.
M.attributes = {
    Strength = 'Strength',
    Intelligence = 'Intelligence',
    Willpower = 'Willpower',
    Agility = 'Agility',
    Speed = 'Speed',
    Endurance = 'Endurance',
    Personality = 'Personality',
    Luck = 'Luck',
    Health = 'Health',
    Magicka = 'Magicka',
    Fatigue = 'Fatigue',
}

--- Skill RefId -> display name.
M.skills = {
    Block = 'Block',
    Armorer = 'Armorer',
    MediumArmor = 'Medium Armor',
    HeavyArmor = 'Heavy Armor',
    BluntWeapon = 'Blunt Weapon',
    LongBlade = 'Long Blade',
    Axe = 'Axe',
    Spear = 'Spear',
    Athletics = 'Athletics',
    Enchant = 'Enchant',
    Destruction = 'Destruction',
    Alteration = 'Alteration',
    Illusion = 'Illusion',
    Conjuration = 'Conjuration',
    Mysticism = 'Mysticism',
    Restoration = 'Restoration',
    Alchemy = 'Alchemy',
    Unarmored = 'Unarmored',
    Security = 'Security',
    Sneak = 'Sneak',
    Acrobatics = 'Acrobatics',
    LightArmor = 'Light Armor',
    ShortBlade = 'Short Blade',
    Marksman = 'Marksman',
    Mercantile = 'Mercantile',
    Speechcraft = 'Speechcraft',
    HandToHand = 'Hand-to-Hand',
}

--- Display name for one effect RefId (raw ID fallback).
function M.effectName(effId)
    if type(effId) == 'string' then
        return M.effects[effId] or effId
    end
    return ''
end

--- Display name for a compound effect key "effId[~attribute][~skill]"
-- (the key format used by shared/db.lua). Generic effects whose base name
-- ends in "Attribute"/"Skill" swap that word for the target, e.g.
-- "Fortify Attribute" + Strength -> "Fortify Strength".
function M.formatEffectName(compoundKey)
    if type(compoundKey) ~= 'string' or compoundKey == '' then
        return ''
    end
    local effId, attr, skill = compoundKey:match('^([^~]*)~?([^~]*)~?(.*)$')
    local name = M.effectName(effId)
    local target = nil
    if skill and skill ~= '' then
        target = M.skills[skill] or skill
    elseif attr and attr ~= '' then
        target = M.attributes[attr] or attr
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

return M
