-- Data: the built-in buff-name -> category table. The aura API tells us
-- what a buff is called, not where it came from; this table fills that
-- gap for the buffs everyone sees. Ranked spells share one display name,
-- so one entry covers every rank. It is consulted at runtime and never
-- copied into saved variables, so a newer version applies immediately
-- while the player's own reassignments still win (see Classify.lua).

local _, BL = ...

local Data = {}
BL.Data = Data

local W, P, H, R, PR, S, M, WL, D = "warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid"
local WEAPON, CONSUMABLE, WORLD = "weapon", "consumable", "world"

BL.SEED_BUFFS = {
    -- Warrior
    ["Battle Shout"] = W, ["Commanding Shout"] = W, ["Bloodrage"] = W, ["Berserker Rage"] = W,
    ["Last Stand"] = W, ["Shield Wall"] = W, ["Shield Block"] = W, ["Enrage"] = W, ["Recklessness"] = W,
    ["Sweeping Strikes"] = W, ["Death Wish"] = W, ["Flurry"] = W, ["Defensive Stance"] = W,
    ["Battle Stance"] = W, ["Berserker Stance"] = W, ["Retaliation"] = W, ["Bloodthirst"] = W,
    ["Spell Reflection"] = W, ["Rampage"] = W,

    -- Paladin
    ["Blessing of Might"] = P, ["Greater Blessing of Might"] = P,
    ["Blessing of Wisdom"] = P, ["Greater Blessing of Wisdom"] = P,
    ["Blessing of Kings"] = P, ["Greater Blessing of Kings"] = P,
    ["Blessing of Salvation"] = P, ["Greater Blessing of Salvation"] = P,
    ["Blessing of Sanctuary"] = P, ["Greater Blessing of Sanctuary"] = P,
    ["Blessing of Light"] = P, ["Greater Blessing of Light"] = P,
    ["Blessing of Protection"] = P, ["Blessing of Freedom"] = P, ["Blessing of Sacrifice"] = P,
    ["Devotion Aura"] = P, ["Retribution Aura"] = P, ["Concentration Aura"] = P, ["Sanctity Aura"] = P,
    ["Shadow Resistance Aura"] = P, ["Frost Resistance Aura"] = P, ["Fire Resistance Aura"] = P,
    ["Righteous Fury"] = P, ["Divine Shield"] = P, ["Divine Protection"] = P, ["Divine Favor"] = P,
    ["Holy Shield"] = P, ["Seal of Righteousness"] = P, ["Seal of Command"] = P, ["Seal of the Crusader"] = P,
    ["Seal of Wisdom"] = P, ["Seal of Light"] = P, ["Seal of Justice"] = P, ["Vengeance"] = P,
    ["Lay on Hands"] = P, ["Holy Light"] = P,

    -- Hunter
    ["Aspect of the Hawk"] = H, ["Aspect of the Monkey"] = H, ["Aspect of the Cheetah"] = H,
    ["Aspect of the Pack"] = H, ["Aspect of the Beast"] = H, ["Aspect of the Wild"] = H,
    ["Aspect of the Falcon"] = H, ["Trueshot Aura"] = H, ["Rapid Fire"] = H, ["Feign Death"] = H,
    ["Bestial Wrath"] = H, ["Deterrence"] = H, ["Quick Shots"] = H, ["Eyes of the Beast"] = H,
    ["Eagle Eye"] = H, ["Track Beasts"] = H, ["Track Humanoids"] = H, ["Track Undead"] = H,
    ["Track Hidden"] = H, ["Track Elementals"] = H, ["Track Demons"] = H, ["Track Giants"] = H,
    ["Track Dragonkin"] = H, ["Frenzy"] = H, ["Ferocious Inspiration"] = H,

    -- Rogue
    ["Stealth"] = R, ["Sprint"] = R, ["Evasion"] = R, ["Blade Flurry"] = R, ["Adrenaline Rush"] = R,
    ["Slice and Dice"] = R, ["Cold Blood"] = R, ["Vanish"] = R, ["Remorseless"] = R, ["Ghostly Strike"] = R,
    ["Preparation"] = R, ["Cloak of Shadows"] = R,

    -- Priest
    ["Power Word: Fortitude"] = PR, ["Prayer of Fortitude"] = PR, ["Divine Spirit"] = PR,
    ["Prayer of Spirit"] = PR, ["Shadow Protection"] = PR, ["Prayer of Shadow Protection"] = PR,
    ["Power Word: Shield"] = PR, ["Fear Ward"] = PR, ["Inner Fire"] = PR, ["Renew"] = PR,
    ["Power Infusion"] = PR, ["Inner Focus"] = PR, ["Shadowform"] = PR, ["Spirit of Redemption"] = PR,
    ["Touch of Weakness"] = PR, ["Feedback"] = PR, ["Elune's Grace"] = PR, ["Abolish Disease"] = PR,
    ["Levitate"] = PR, ["Fade"] = PR, ["Prayer of Healing"] = PR, ["Blessed Recovery"] = PR,
    ["Inspiration"] = PR, ["Champion's Grace"] = PR, ["Lightwell Renew"] = PR,

    -- Shaman
    ["Lightning Shield"] = S, ["Water Shield"] = S, ["Earth Shield"] = S, ["Bloodlust"] = S,
    ["Heroism"] = S, ["Strength of Earth"] = S, ["Grace of Air"] = S, ["Windfury Totem"] = S,
    ["Mana Spring"] = S, ["Healing Stream"] = S, ["Tranquil Air"] = S, ["Stoneskin"] = S,
    ["Nature Resistance"] = S, ["Fire Resistance"] = S, ["Frost Resistance"] = S, ["Water Walking"] = S,
    ["Water Breathing"] = S, ["Ghost Wolf"] = S, ["Elemental Mastery"] = S, ["Nature's Swiftness"] = S,
    ["Ancestral Fortitude"] = S, ["Healing Way"] = S, ["Clearcasting"] = S, ["Elemental Focus"] = S,
    ["Totem of Wrath"] = S, ["Wrath of Air Totem"] = S, ["Mana Tide"] = S,

    -- Mage
    ["Arcane Intellect"] = M, ["Arcane Brilliance"] = M, ["Mage Armor"] = M, ["Ice Armor"] = M,
    ["Frost Armor"] = M, ["Dampen Magic"] = M, ["Amplify Magic"] = M, ["Ice Barrier"] = M,
    ["Mana Shield"] = M, ["Ice Block"] = M, ["Evocation"] = M, ["Arcane Power"] = M,
    ["Presence of Mind"] = M, ["Combustion"] = M, ["Slow Fall"] = M, ["Blink"] = M,
    ["Fire Ward"] = M, ["Frost Ward"] = M, ["Blazing Speed"] = M, ["Molten Armor"] = M,
    ["Icy Veins"] = M, ["Invisibility"] = M,

    -- Warlock
    ["Demon Skin"] = WL, ["Demon Armor"] = WL, ["Fel Armor"] = WL, ["Soulstone Resurrection"] = WL,
    ["Unending Breath"] = WL, ["Detect Invisibility"] = WL, ["Detect Lesser Invisibility"] = WL,
    ["Detect Greater Invisibility"] = WL, ["Blood Pact"] = WL, ["Paranoia"] = WL, ["Shadow Ward"] = WL,
    ["Fire Shield"] = WL, ["Sacrifice"] = WL, ["Soul Link"] = WL, ["Demonic Sacrifice"] = WL,
    ["Burning Wish"] = WL, ["Touch of Shadow"] = WL, ["Fel Stamina"] = WL, ["Fel Energy"] = WL,
    ["Amplify Curse"] = WL, ["Shadow Trance"] = WL, ["Nightfall"] = WL, ["Backlash"] = WL,
    ["Fel Domination"] = WL, ["Master Demonologist"] = WL, ["Demonic Frenzy"] = WL, ["Eye of Kilrogg"] = WL,

    -- Druid
    ["Mark of the Wild"] = D, ["Gift of the Wild"] = D, ["Thorns"] = D, ["Rejuvenation"] = D,
    ["Regrowth"] = D, ["Barkskin"] = D, ["Omen of Clarity"] = D, ["Nature's Grace"] = D,
    ["Innervate"] = D, ["Bear Form"] = D, ["Dire Bear Form"] = D, ["Cat Form"] = D,
    ["Aquatic Form"] = D, ["Travel Form"] = D, ["Moonkin Form"] = D, ["Tree of Life"] = D,
    ["Prowl"] = D, ["Dash"] = D, ["Tiger's Fury"] = D, ["Frenzied Regeneration"] = D,
    ["Leader of the Pack"] = D, ["Moonkin Aura"] = D,
    ["Lifebloom"] = D, ["Tranquility"] = D, ["Natural Perfection"] = D, ["Swiftmend"] = D,
    ["Abolish Poison"] = D,

    -- World buffs
    ["Rallying Cry of the Dragonslayer"] = WORLD, ["Warchief's Blessing"] = WORLD,
    ["Spirit of Zandalar"] = WORLD, ["Songflower Serenade"] = WORLD, ["Mol'dar's Moxie"] = WORLD,
    ["Fengus' Ferocity"] = WORLD, ["Slip'kik's Savvy"] = WORLD, ["Boon of Blackfathom"] = WORLD,
    ["Spark of Inspiration"] = WORLD, ["Fervor of the Temple Explorer"] = WORLD,
    ["Resist Fire"] = WORLD, ["Blessing of Blackfathom"] = WORLD, ["Darkmoon Faire Fortune"] = WORLD,
    ["Traces of Silithyst"] = WORLD, ["Chronoboon Displacer"] = WORLD, ["Spirit of the Alpha"] = WORLD,
    ["Bloodmoon Blessing"] = WORLD, ["Hakkar's Blessing"] = WORLD,

    -- Consumables
    ["Well Fed"] = CONSUMABLE, ["Rumsey Rum Black Label"] = CONSUMABLE, ["Rumsey Rum"] = CONSUMABLE,
    ["Rumsey Rum Light"] = CONSUMABLE, ["Rumsey Rum Dark"] = CONSUMABLE,
    ["Winterfall Firewater"] = CONSUMABLE, ["Ground Scorpok Assay"] = CONSUMABLE, ["R.O.I.D.S."] = CONSUMABLE,
    ["Gordok's Ogre Compound"] = CONSUMABLE, ["Lung Juice Cocktail"] = CONSUMABLE, ["Cerebral Cortex Compound"] = CONSUMABLE,
    ["Infallible Mind"] = CONSUMABLE, ["Gizzard Gum"] = CONSUMABLE, ["Crystal Ward"] = CONSUMABLE,
    ["Crystal Spire"] = CONSUMABLE, ["Crystal Force"] = CONSUMABLE, ["Crystal Yield"] = CONSUMABLE,
    ["Blessed Sunfruit"] = CONSUMABLE, ["Blessed Sunfruit Juice"] = CONSUMABLE, ["Blackened Basilisk"] = CONSUMABLE,
    ["Increased Stamina"] = CONSUMABLE, ["Increased Intellect"] = CONSUMABLE, ["Increased Agility"] = CONSUMABLE,
    ["Increased Strength"] = CONSUMABLE, ["Increased Spirit"] = CONSUMABLE, ["Mana Regeneration"] = CONSUMABLE,
    ["Health Regeneration"] = CONSUMABLE, ["Food"] = CONSUMABLE, ["Drink"] = CONSUMABLE, ["Regeneration"] = CONSUMABLE,
    ["Greater Fire Protection Potion"] = CONSUMABLE, ["Greater Frost Protection Potion"] = CONSUMABLE,
    ["Greater Nature Protection Potion"] = CONSUMABLE, ["Greater Shadow Protection Potion"] = CONSUMABLE,
    ["Greater Arcane Protection Potion"] = CONSUMABLE, ["Fire Protection"] = CONSUMABLE, ["Frost Protection"] = CONSUMABLE,
    ["Nature Protection"] = CONSUMABLE, ["Shadow Protection Potion"] = CONSUMABLE, ["Arcane Protection"] = CONSUMABLE,
    ["Holy Protection"] = CONSUMABLE, ["Mighty Rage"] = CONSUMABLE, ["Rage of Ages"] = CONSUMABLE,
    ["Strike of the Scorpok"] = CONSUMABLE, ["Spirit of Boar"] = CONSUMABLE, ["Sharpened Claws"] = CONSUMABLE,
    ["Mongoose"] = CONSUMABLE, ["Fortitude"] = CONSUMABLE, ["Armor"] = CONSUMABLE, ["Intellect"] = CONSUMABLE,
    ["Agility"] = CONSUMABLE, ["Strength"] = CONSUMABLE, ["Stamina"] = CONSUMABLE, ["Spirit"] = CONSUMABLE,
    ["Protection"] = CONSUMABLE, ["Swiftness"] = CONSUMABLE, ["Free Action"] = CONSUMABLE,
    ["Invulnerability"] = CONSUMABLE, ["Limited Invulnerability"] = CONSUMABLE, ["Restoration"] = CONSUMABLE,
    ["Nature's Beauty"] = CONSUMABLE, ["Elixir of the Mongoose"] = CONSUMABLE, ["Elixir of Fortitude"] = CONSUMABLE,
    ["Elixir of Giants"] = CONSUMABLE, ["Elixir of Superior Defense"] = CONSUMABLE, ["Elixir of Greater Firepower"] = CONSUMABLE,
    ["Elixir of Frost Power"] = CONSUMABLE, ["Elixir of Shadow Power"] = CONSUMABLE, ["Elixir of Greater Intellect"] = CONSUMABLE,
    ["Elixir of Sages"] = CONSUMABLE, ["Elixir of Brute Force"] = CONSUMABLE, ["Elixir of Demonslaying"] = CONSUMABLE,
    ["Elixir of Poison Resistance"] = CONSUMABLE, ["Elixir of Waterbreathing"] = CONSUMABLE, ["Elixir of Water Walking"] = CONSUMABLE,
    ["Flask of the Titans"] = CONSUMABLE, ["Flask of Supreme Power"] = CONSUMABLE, ["Flask of Distilled Wisdom"] = CONSUMABLE,
    ["Flask of Chromatic Resistance"] = CONSUMABLE, ["Flask of Petrification"] = CONSUMABLE,
    ["Juju Power"] = CONSUMABLE, ["Juju Might"] = CONSUMABLE, ["Juju Chill"] = CONSUMABLE, ["Juju Ember"] = CONSUMABLE,
    ["Juju Flurry"] = CONSUMABLE, ["Juju Escape"] = CONSUMABLE, ["Juju Guile"] = CONSUMABLE,
    ["Scroll of Agility"] = CONSUMABLE, ["Scroll of Intellect"] = CONSUMABLE, ["Scroll of Protection"] = CONSUMABLE,
    ["Scroll of Spirit"] = CONSUMABLE, ["Scroll of Stamina"] = CONSUMABLE, ["Scroll of Strength"] = CONSUMABLE,
    ["Dreamless Sleep"] = CONSUMABLE, ["Greater Dreamless Sleep"] = CONSUMABLE, ["Swiftness Potion"] = CONSUMABLE,
    ["Mageblood Potion"] = CONSUMABLE, ["Nightfin Soup"] = CONSUMABLE, ["Grilled Squid"] = CONSUMABLE,
    ["Runn Tum Tuber Surprise"] = CONSUMABLE, ["Smoked Desert Dumplings"] = CONSUMABLE, ["Tender Wolf Steak"] = CONSUMABLE,
    ["Sagefish Delight"] = CONSUMABLE, ["Dirge's Kickin' Chimaerok Chops"] = CONSUMABLE, ["Spirit of Zanza"] = CONSUMABLE,
    ["Swiftness of Zanza"] = CONSUMABLE, ["Sheen of Zanza"] = CONSUMABLE, ["Bogling Root"] = CONSUMABLE,
    ["Noggenfogger Elixir"] = CONSUMABLE, ["Savory Deviate Delight"] = CONSUMABLE, ["Rage Potion"] = CONSUMABLE,
    ["Great Rage Potion"] = CONSUMABLE, ["Mighty Rage Potion"] = CONSUMABLE, ["Restorative Potion"] = CONSUMABLE,
    ["Living Action Potion"] = CONSUMABLE, ["Free Action Potion"] = CONSUMABLE, ["Shadow Oil"] = CONSUMABLE,
    ["Frost Oil"] = CONSUMABLE, ["Stonescale Oil"] = CONSUMABLE, ["Nature Resistance Potion"] = CONSUMABLE,
    ["Dense Dynamite"] = CONSUMABLE, ["Goblin Rocket Fuel"] = CONSUMABLE, ["Ultra-Flash Shadow Reflector"] = CONSUMABLE,
    ["Gnomish Death Ray"] = CONSUMABLE, ["Goblin Sapper Charge"] = CONSUMABLE, ["Power Word: Strength"] = CONSUMABLE,
    ["Kreeg's Stout Beatdown"] = CONSUMABLE, ["Gordok Green Grog"] = CONSUMABLE, ["Fizzy Faire Drink"] = CONSUMABLE,
    ["Darkmoon Special Reserve"] = CONSUMABLE, ["Dragonbreath Chili"] = CONSUMABLE, ["Bright Campfire"] = CONSUMABLE,
    ["Troll's Blood"] = CONSUMABLE, ["Lesser Stoneshield"] = CONSUMABLE,
    ["Greater Stoneshield"] = CONSUMABLE, ["Stoneshield"] = CONSUMABLE, ["Ironshield"] = CONSUMABLE,

    -- Weapon enchants shown as auras by name
    ["Rockbiter Weapon"] = WEAPON, ["Flametongue Weapon"] = WEAPON, ["Frostbrand Weapon"] = WEAPON,
    ["Windfury Weapon"] = WEAPON, ["Instant Poison"] = WEAPON, ["Deadly Poison"] = WEAPON,
    ["Crippling Poison"] = WEAPON, ["Mind-numbing Poison"] = WEAPON, ["Wound Poison"] = WEAPON,
    ["Sharpened"] = WEAPON, ["Weighted"] = WEAPON, ["Blessed Wizard Oil"] = WEAPON,
}

-- Families too varied to list one by one. Tried in order after the exact
-- table; the first match wins.
BL.SEED_PATTERNS = {
    { "^Elixir of", CONSUMABLE },
    { "^Flask of", CONSUMABLE },
    { "^Greater .+ Protection Potion$", CONSUMABLE },
    { "^Juju ", CONSUMABLE },
    { "^Scroll of", CONSUMABLE },
    { "^Well Fed", CONSUMABLE },
    { "^Rumsey Rum", CONSUMABLE },
    { " Potion$", CONSUMABLE },
    { "Fortune$", WORLD },
    { "^Sayge's", WORLD },
    { "Sharpened$", WEAPON },
    { "Sharpening Stone$", WEAPON },
    { "Weightstone$", WEAPON },
    { " Oil$", WEAPON },
    { " Poison$", WEAPON },
}

function Data.Lookup(name)
    if type(name) ~= "string" then return nil end
    local hit = BL.SEED_BUFFS[name]
    if hit then return hit end
    for i = 1, #BL.SEED_PATTERNS do
        local entry = BL.SEED_PATTERNS[i]
        if string.find(name, entry[1]) then return entry[2] end
    end
    return nil
end
