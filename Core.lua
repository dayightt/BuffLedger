-- Core: namespace, output, secret-value guards, event bus, saved variables,
-- settings access, and the small formatting helpers every other file uses.

local ADDON_NAME, BL = ...

BL.ADDON_NAME = ADDON_NAME
BL.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "dev"
BL.ACCENT = "|cffa335ee"
BL.DB_VERSION = 1

-- ---------------------------------------------------------------------
-- Output
-- ---------------------------------------------------------------------

function BL.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(BL.ACCENT .. "BuffLedger:|r " .. tostring(msg))
end

-- ---------------------------------------------------------------------
-- Secret values. Any value that came from aura data, a unit API or an
-- event payload goes through here before it is compared, formatted, or
-- used as a table key. A secret becomes nil, so the worst case is
-- missing data rather than an error.
-- ---------------------------------------------------------------------

function BL.Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

function BL.PlainTable(t)
    if type(t) ~= "table" then return nil end
    if issecrettable and issecrettable(t) then return nil end
    return t
end

-- ---------------------------------------------------------------------
-- Clock indirection (tests replace these)
-- ---------------------------------------------------------------------

function BL.Now() return time() end
function BL.Clock() return GetTime() end

-- ---------------------------------------------------------------------
-- Internal event bus
-- ---------------------------------------------------------------------

local listeners = {}

function BL.On(event, fn)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
end

function BL.Fire(event, ...)
    local list = listeners[event]
    if not list then return end
    for i = 1, #list do
        list[i](...)
    end
end

-- ---------------------------------------------------------------------
-- Client events: one hidden frame, handlers registered by name.
-- ---------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then return end
    for i = 1, #list do
        list[i](event, ...)
    end
end)

function BL.RegisterEvent(event, fn, unit)
    if not eventHandlers[event] then
        eventHandlers[event] = {}
        if unit then
            eventFrame:RegisterUnitEvent(event, unit)
        else
            eventFrame:RegisterEvent(event)
        end
    end
    table.insert(eventHandlers[event], fn)
end

-- ---------------------------------------------------------------------
-- Saved variables
-- ---------------------------------------------------------------------

local function copyDeep(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = copyDeep(val) end
    return out
end

-- Fills missing keys in tbl from defaults, recursing into tables that
-- exist on both sides. Never overwrites a value that is already set.
function BL.ApplyDefaults(tbl, defaults)
    for k, dv in pairs(defaults) do
        local tv = tbl[k]
        if tv == nil then
            tbl[k] = copyDeep(dv)
        elseif type(tv) == "table" and type(dv) == "table" then
            BL.ApplyDefaults(tv, dv)
        end
    end
    return tbl
end

BL.DEFAULTS = {
    version = BL.DB_VERSION,
    settings = {
        locked = true,
        scale = 1,
        iconSize = 30,
        spacing = 4,
        categoryGap = 12,
        columns = 10,
        growLeft = true,
        showBackground = false,
        durationInside = false,
        borderThickness = 1,
        consolidateOnlyGroup = false,
        consolidateOnlyRaid = false,
        hideBlizzardFrames = true,
        minimapButton = false,
        minimapAngle = 220,
        -- point is absent by default: the bar then sits exactly where the
        -- client's own buff frame is (and follows it in Edit Mode) until
        -- the player drags it somewhere.
        debuff = {
            locked = true,
            scale = 1,
            iconSize = 30,
            spacing = 4,
            columns = 10,
            growLeft = true,
            showBackground = false,
            durationInside = false,
            borderThickness = 1,
        },
    },
    -- categories is intentionally absent: nil means "never seeded" and
    -- Categories.Seed fills it exactly once.
    categoryOrder = {},
    overrides = {},
    learned = {},
    spells = {},      -- [spellId] = name, learned whenever aura data is readable
    history = {},
    nextCustomId = 1,
}

-- Forward migrations keyed by the version they upgrade FROM. An
-- unversioned table counts as version 0.
local MIGRATIONS = {
    [0] = function(db) end, -- v1 is the first shipped layout; defaults do the work
}

local function migrate(db)
    local v = tonumber(db.version) or 0
    while v < BL.DB_VERSION do
        local step = MIGRATIONS[v]
        if step then step(db) end
        v = v + 1
        db.version = v
    end
end

function BL.InitDB()
    BuffLedgerDB = type(BuffLedgerDB) == "table" and BuffLedgerDB or {}
    migrate(BuffLedgerDB)
    BL.ApplyDefaults(BuffLedgerDB, BL.DEFAULTS)
    BL.DB = BuffLedgerDB
    if BL.Categories and BL.Categories.Seed then BL.Categories.Seed() end
    return BL.DB
end

-- If the client restores the saved table after our first init, the global
-- gets replaced under us. Adopt whatever is there now.
function BL.AdoptDB(reason)
    if type(BuffLedgerDB) ~= "table" or BuffLedgerDB == BL.DB then return false end
    BL.InitDB()
    BL.loadedFromDisk = { account = true, late = reason }
    BL.Fire("DB_READY")
    return true
end

BL.RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then return end
    local hadData = type(BuffLedgerDB) == "table" and BuffLedgerDB.version ~= nil
    BL.InitDB()
    BL.loadedFromDisk = { account = hadData }
    BL.Fire("DB_READY")
end)

BL.RegisterEvent("PLAYER_LOGIN", function() BL.AdoptDB("PLAYER_LOGIN") end)
BL.RegisterEvent("PLAYER_ENTERING_WORLD", function() BL.AdoptDB("PLAYER_ENTERING_WORLD") end)

-- One line at login: what came back from disk.
BL.RegisterEvent("PLAYER_LOGIN", function()
    local cats, overrides = 0, 0
    for _ in pairs(BL.DB.categories or {}) do cats = cats + 1 end
    for _ in pairs(BL.DB.overrides) do overrides = overrides + 1 end
    local fresh = BL.loadedFromDisk and not BL.loadedFromDisk.account
    BL.Print(string.format("v%s - %d categories, %d %s assigned by hand%s. /bl for options.",
        tostring(BL.VERSION), cats, overrides, overrides == 1 and "buff" or "buffs",
        fresh and " (no saved data found, starting fresh)" or ""))
end)

-- ---------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------

local function settingsTable(scope)
    if scope == "debuff" then return BL.DB.settings.debuff end
    return BL.DB.settings
end

function BL.GetSetting(key, scope)
    return settingsTable(scope)[key]
end

function BL.SetSetting(key, value, scope)
    settingsTable(scope)[key] = value
    BL.Fire("SETTINGS_CHANGED", key, scope == "debuff" and "debuff" or "buff")
end

-- ---------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------

-- Aura-style duration abbreviation: whole units, largest that fits.
function BL.FormatTime(seconds)
    seconds = tonumber(seconds)
    if not seconds or seconds <= 0 then return "" end
    if seconds < 60 then return string.format("%ds", math.floor(seconds)) end
    if seconds < 3600 then return string.format("%dm", math.floor(seconds / 60)) end
    if seconds < 86400 then return string.format("%dh", math.floor(seconds / 3600)) end
    return string.format("%dd", math.floor(seconds / 86400))
end

-- Lowercase class file token for a unit ("priest"), nil when unknown or secret.
function BL.ClassToken(unit)
    unit = BL.Plain(unit)
    if type(unit) ~= "string" then return nil end
    local _, token = UnitClass(unit)
    token = BL.Plain(token)
    if type(token) ~= "string" then return nil end
    return string.lower(token)
end
