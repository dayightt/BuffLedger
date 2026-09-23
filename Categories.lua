-- Categories: the editable set of buckets buffs are sorted into. The
-- shipped list below is seed data only; once seeded, BL.DB.categories and
-- BL.DB.categoryOrder are the single source of truth and every field on
-- them can be changed by the player. "other" is the permanent catch-all.

local _, BL = ...

local Categories = {}
BL.Categories = Categories

local OTHER = "other"

local function classColor(token, fallback)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c then return { c.r, c.g, c.b } end
    return fallback
end

local function class(id, token, name, icon, fallback)
    return { id = id, name = name, token = token, icon = "Interface\\Icons\\" .. icon, fallback = fallback }
end

local SHIPPED = {
    class("warrior", "WARRIOR", "Warrior", "Ability_Warrior_Rampage", { 0.78, 0.61, 0.43 }),
    class("paladin", "PALADIN", "Paladin", "Spell_Holy_HolyBolt", { 0.96, 0.55, 0.73 }),
    class("hunter", "HUNTER", "Hunter", "Ability_Hunter_BeastTaming", { 0.67, 0.83, 0.45 }),
    class("rogue", "ROGUE", "Rogue", "Ability_Stealth", { 1.00, 0.96, 0.41 }),
    class("priest", "PRIEST", "Priest", "Spell_Holy_WordFortitude", { 1.00, 1.00, 1.00 }),
    class("shaman", "SHAMAN", "Shaman", "Spell_Nature_BloodLust", { 0.00, 0.44, 0.87 }),
    class("mage", "MAGE", "Mage", "Spell_Fire_FlameBolt", { 0.41, 0.80, 0.94 }),
    class("warlock", "WARLOCK", "Warlock", "Spell_Shadow_ShadowBolt", { 0.58, 0.51, 0.79 }),
    class("druid", "DRUID", "Druid", "Ability_Racial_BearForm", { 1.00, 0.49, 0.04 }),
    { id = "weapon", name = "Weapon", icon = "Interface\\Icons\\INV_Stone_02", fallback = { 0.20, 0.85, 0.85 } },
    { id = "consumable", name = "Consumable", icon = "Interface\\Icons\\INV_Potion_62", fallback = { 0.30, 1.00, 0.40 } },
    { id = "world", name = "World", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", fallback = { 1.00, 0.82, 0.00 } },
    { id = OTHER, name = "Other", icon = nil, fallback = { 0.65, 0.65, 0.65 }, deletable = false },
}

-- Public, read-only view of the shipped list (colours resolved).
Categories.DEFAULTS = {}
for i, def in ipairs(SHIPPED) do
    Categories.DEFAULTS[i] = {
        id = def.id, name = def.name, icon = def.icon,
        color = def.token and classColor(def.token, def.fallback) or def.fallback,
        deletable = def.deletable ~= false,
    }
end

local function shippedRecord(def)
    local color = def.token and classColor(def.token, def.fallback) or def.fallback
    return {
        name = def.name,
        color = { color[1], color[2], color[3] },
        icon = def.icon,
        hidden = false,
        consolidate = false,
        builtin = true,
        deletable = def.deletable ~= false,
    }
end

local function fire() BL.Fire("CATEGORIES_CHANGED") end

local function indexOf(list, id)
    for i = 1, #list do
        if list[i] == id then return i end
    end
    return nil
end

-- First-run population only. An existing table, even one the player has
-- emptied, is never touched.
function Categories.Seed()
    if BL.DB.categories then return end
    BL.DB.categories = {}
    BL.DB.categoryOrder = {}
    for _, def in ipairs(SHIPPED) do
        BL.DB.categories[def.id] = shippedRecord(def)
        table.insert(BL.DB.categoryOrder, def.id)
    end
end

function Categories.Get(id)
    return id and BL.DB.categories[id] or nil
end

function Categories.Order()
    return BL.DB.categoryOrder
end

function Categories.Exists(id)
    return id ~= nil and BL.DB.categories[id] ~= nil
end

function Categories.Resolve(id)
    if Categories.Exists(id) then return id end
    return OTHER
end

function Categories.FindByName(name)
    if type(name) ~= "string" then return nil end
    local needle = string.lower(name)
    for id, rec in pairs(BL.DB.categories) do
        if string.lower(rec.name) == needle then return id end
    end
    return nil
end

function Categories.Create(name, color)
    local id = "custom-" .. BL.DB.nextCustomId
    BL.DB.nextCustomId = BL.DB.nextCustomId + 1
    color = color or { 0.8, 0.8, 0.8 }
    BL.DB.categories[id] = {
        name = name or "New Category",
        color = { color[1], color[2], color[3] },
        icon = nil,
        hidden = false,
        consolidate = false,
        builtin = false,
        deletable = true,
    }
    local order = BL.DB.categoryOrder
    local otherAt = indexOf(order, OTHER)
    if otherAt then
        table.insert(order, otherAt, id)
    else
        table.insert(order, id)
    end
    fire()
    return id
end

function Categories.Rename(id, name)
    local rec = Categories.Get(id)
    if not rec or type(name) ~= "string" or name == "" then return false end
    rec.name = name
    fire()
    return true
end

-- quiet: a live colour-picker update; only the colour listeners react.
-- The full CATEGORIES_CHANGED follows when the picker closes.
function Categories.SetColor(id, color, quiet)
    local rec = Categories.Get(id)
    if not rec or type(color) ~= "table" then return false end
    rec.color = { color[1], color[2], color[3] }
    if quiet then
        BL.Fire("CATEGORY_COLOR_CHANGED", id)
    else
        fire()
    end
    return true
end

function Categories.SetHidden(id, hidden)
    local rec = Categories.Get(id)
    if not rec then return false end
    rec.hidden = hidden and true or false
    fire()
    return true
end

function Categories.SetConsolidate(id, on)
    local rec = Categories.Get(id)
    if not rec then return false end
    rec.consolidate = on and true or false
    fire()
    return true
end

-- All-or-nothing switch for the per-category consolidate flag.
function Categories.AllConsolidated()
    for _, rec in pairs(BL.DB.categories) do
        if not rec.consolidate then return false end
    end
    return next(BL.DB.categories) ~= nil
end

function Categories.SetConsolidateAll(on)
    for _, rec in pairs(BL.DB.categories) do rec.consolidate = on and true or false end
    fire()
end

-- Moves a category one step up (-1) or down (+1). Other stays last.
function Categories.Move(id, delta)
    if id == OTHER or not Categories.Exists(id) then return false end
    local order = BL.DB.categoryOrder
    local from = indexOf(order, id)
    if not from then return false end
    local to = from + (delta < 0 and -1 or 1)
    if to < 1 or to > #order then return false end
    if order[to] == OTHER then return false end
    order[from], order[to] = order[to], order[from]
    fire()
    return true
end

function Categories.Delete(id)
    if id == OTHER or not Categories.Exists(id) then return false end
    BL.DB.categories[id] = nil
    local at = indexOf(BL.DB.categoryOrder, id)
    if at then table.remove(BL.DB.categoryOrder, at) end
    for name, cat in pairs(BL.DB.overrides) do
        if cat == id then BL.DB.overrides[name] = OTHER end
    end
    for name, cat in pairs(BL.DB.learned) do
        if cat == id then BL.DB.learned[name] = OTHER end
    end
    fire()
    return true
end

-- Re-adds any missing shipped category with its shipped values, rebuilds
-- the order as shipped built-ins first (in shipped order) then customs in
-- their existing relative order, with Other last. Overrides, learned
-- entries and history are untouched.
function Categories.ResetToDefault()
    Categories.Seed()
    for _, def in ipairs(SHIPPED) do
        if not BL.DB.categories[def.id] then
            BL.DB.categories[def.id] = shippedRecord(def)
        end
    end
    local newOrder = {}
    for _, def in ipairs(SHIPPED) do
        if def.id ~= OTHER then table.insert(newOrder, def.id) end
    end
    for _, id in ipairs(BL.DB.categoryOrder) do
        local rec = BL.DB.categories[id]
        if rec and not rec.builtin then table.insert(newOrder, id) end
    end
    table.insert(newOrder, OTHER)
    BL.DB.categoryOrder = newOrder
    fire()
end
