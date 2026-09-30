-- Alchemist's Almanac — display names for attributes and skills.
--
-- OpenMW exposes no Lua API for attribute/skill display names, so
-- these are shipped statically (sourced from the game's GMST
-- strings). Magic effect names need no table: they are collected
-- at init from each record's effect.effect.name (the localized
-- MagicEffect name), with generated CamelCase fallback for IDs
-- whose effect record or name is missing.

local M = {
    attributes = {
        Strength = 'Strength',
        Intelligence = 'Intelligence',
        Willpower = 'Willpower',
        Agility = 'Agility',
        Speed = 'Speed',
        Endurance = 'Endurance',
        Personality = 'Personality',
        Luck = 'Luck',
    },
    skills = {
        Acrobatics = 'Acrobatics',
        Alchemy = 'Alchemy',
        Alteration = 'Alteration',
        Armorer = 'Armorer',
        Athletics = 'Athletics',
        Axe = 'Axe',
        Block = 'Block',
        BluntWeapon = 'Blunt Weapon',
        Conjuration = 'Conjuration',
        Destruction = 'Destruction',
        Enchant = 'Enchant',
        HandToHand = 'Hand-to-hand',
        HeavyArmor = 'Heavy Armor',
        Illusion = 'Illusion',
        LightArmor = 'Light Armor',
        LongBlade = 'Long Blade',
        Marksman = 'Marksman',
        MediumArmor = 'Medium Armor',
        Mercantile = 'Mercantile',
        Mysticism = 'Mysticism',
        Restoration = 'Restoration',
        Security = 'Security',
        ShortBlade = 'Short Blade',
        Sneak = 'Sneak',
        Spear = 'Spear',
        Speechcraft = 'Speechcraft',
        Unarmored = 'Unarmored',
    },
}

return M
