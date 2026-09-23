-- Minimal fake of the WoW client API surface BuffLedger touches, so the
-- non-UI files run under a plain Lua 5.1 interpreter. Everything is driven
-- by fixtures the tests set through the `stub` table.

local stub = {}

-- ---------------------------------------------------------------------
-- Secret values. The client tags values; here a secret is a wrapper table
-- that errors on any operation except identity checks, which is close
-- enough to catch code that forgets to guard.
-- ---------------------------------------------------------------------

local SecretMT = {}
local function secretError() error("attempt to use a secret value", 2) end
SecretMT.__index = secretError
SecretMT.__newindex = secretError
SecretMT.__concat = secretError
SecretMT.__len = secretError
SecretMT.__lt = secretError
SecretMT.__le = secretError
SecretMT.__add = secretError
SecretMT.__sub = secretError
SecretMT.__call = secretError
SecretMT.__tostring = function() return "<secret>" end

function stub.MakeSecret(v)
    return setmetatable({ __secret = true, __value = v }, SecretMT)
end

function stub.MakeSecretTable()
    return setmetatable({ __secrettable = true }, SecretMT)
end

_G.issecretvalue = function(v)
    return type(v) == "table" and rawget(v, "__secret") == true
end
_G.issecrettable = function(t)
    return type(t) == "table" and rawget(t, "__secrettable") == true
end

-- ---------------------------------------------------------------------
-- Time
-- ---------------------------------------------------------------------

local wallClock = 1700000000
local upClock = 1000.0

function stub.SetTime(wall, up)
    wallClock = wall or wallClock
    upClock = up or upClock
end
function stub.Advance(seconds)
    wallClock = wallClock + seconds
    upClock = upClock + seconds
end

_G.time = function() return wallClock end
_G.GetTime = function() return upClock end
_G.date = function(fmt, t) return os.date(fmt, t or wallClock) end

-- ---------------------------------------------------------------------
-- Lua helpers the client provides globally
-- ---------------------------------------------------------------------

_G.format = string.format
_G.strmatch = string.match
_G.strfind = string.find
_G.gsub = string.gsub
_G.strlen = string.len
_G.strsub = string.sub
_G.strlower = string.lower
_G.strupper = string.upper
_G.strrep = string.rep
_G.tinsert = table.insert
_G.tremove = table.remove
_G.floor = math.floor
_G.ceil = math.ceil
_G.max = math.max
_G.min = math.min
_G.abs = math.abs

_G.wipe = function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

_G.strtrim = function(s)
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

_G.strsplit = function(delim, s, pieces)
    local out = {}
    local start = 1
    local dlen = #delim
    while true do
        local i = string.find(s, delim, start, true)
        if not i or (pieces and #out == pieces - 1) then
            out[#out + 1] = string.sub(s, start)
            break
        end
        out[#out + 1] = string.sub(s, start, i - 1)
        start = i + dlen
    end
    return unpack(out)
end

_G.strjoin = function(delim, ...)
    return table.concat({ ... }, delim)
end

_G.tContains = function(t, v)
    for _, x in pairs(t) do if x == v then return true end end
    return false
end

_G.CopyTable = function(t)
    local out = {}
    for k, v in pairs(t) do
        if type(v) == "table" then out[k] = CopyTable(v) else out[k] = v end
    end
    return out
end

_G.securecallfunction = function(fn, ...) return fn(...) end
_G.securecall = _G.securecallfunction
_G.hooksecurefunc = function(tbl, name, fn)
    if type(tbl) == "string" then fn, name, tbl = name, tbl, _G end
    local orig = tbl[name]
    tbl[name] = function(...)
        local r = { orig(...) }
        fn(...)
        return unpack(r)
    end
end

-- ---------------------------------------------------------------------
-- Chat / output
-- ---------------------------------------------------------------------

stub.chat = {}
_G.DEFAULT_CHAT_FRAME = {
    AddMessage = function(self, msg) stub.chat[#stub.chat + 1] = msg end,
}
function stub.LastChat() return stub.chat[#stub.chat] end
_G.print = function(...) stub.chat[#stub.chat + 1] = table.concat({ tostringall(...) }, " ") end
_G.tostringall = function(...)
    local n = select("#", ...)
    local out = {}
    for i = 1, n do out[i] = tostring((select(i, ...))) end
    return unpack(out, 1, n)
end

-- ---------------------------------------------------------------------
-- Frames and events
-- ---------------------------------------------------------------------

local frames = {}
local FrameMT = {}
FrameMT.__index = function(t, k)
    -- Any widget method we didn't model is a harmless no-op. Methods are
    -- CamelCase; lowercase keys are data fields and stay nil.
    if type(k) ~= "string" or not string.find(k, "^%u") then return nil end
    local fn = function() end
    rawset(t, k, fn)
    return fn
end

local function newFrame(frameType, name, parent, template)
    local f = setmetatable({
        __type = frameType, __name = name, __parent = parent, __template = template,
        __events = {}, __unitEvents = {}, __scripts = {}, __shown = true, __attributes = {},
    }, FrameMT)
    f.RegisterEvent = function(self, event)
        if event == "COMBAT_LOG_EVENT" or event == "COMBAT_LOG_EVENT_UNFILTERED" then
            stub.forbidden = (stub.forbidden or 0) + 1
            return false
        end
        self.__events[event] = true
        return true
    end
    f.RegisterUnitEvent = function(self, event, ...)
        self.__events[event] = true
        self.__unitEvents[event] = { ... }
        return true
    end
    f.UnregisterEvent = function(self, event) self.__events[event] = nil end
    f.UnregisterAllEvents = function(self) self.__events = {} end
    f.IsEventRegistered = function(self, event) return self.__events[event] == true end
    f.SetScript = function(self, handler, fn) self.__scripts[handler] = fn end
    f.GetScript = function(self, handler) return self.__scripts[handler] end
    f.HookScript = function(self, handler, fn)
        local prev = self.__scripts[handler]
        self.__scripts[handler] = function(...) if prev then prev(...) end fn(...) end
    end
    f.Show = function(self) self.__shown = true; if self.__scripts.OnShow then self.__scripts.OnShow(self) end end
    f.Hide = function(self) self.__shown = false end
    f.IsShown = function(self) return self.__shown end
    f.IsVisible = function(self) return self.__shown end
    f.IsProtected = function() return false end
    f.GetName = function(self) return self.__name end
    f.GetParent = function(self) return self.__parent end
    f.SetParent = function(self, p) self.__parent = p end
    f.GetObjectType = function(self) return self.__type end
    f.CreateFontString = function(self) return newFrame("FontString", nil, self) end
    f.CreateTexture = function(self) return newFrame("Texture", nil, self) end
    f.GetText = function(self) return self.__text end
    f.SetText = function(self, t) self.__text = t end
    f.EnableMouse = function(self, on) self.__mouse = on and true or false end
    f.SetAttribute = function(self, k, v) self.__attributes[k] = v end
    f.GetAttribute = function(self, k) return self.__attributes[k] end
    f.SetSize = function(self, w, h) self.__w, self.__h = w, h end
    f.GetWidth = function(self) return self.__w or 0 end
    f.GetFrameLevel = function() return 1 end
    f.GetEffectiveScale = function() return 1 end
    f.GetCenter = function() return 100, 100 end
    f.GetHeight = function(self) return self.__h or 0 end
    f.SetTexture = function(self, t) self.__texture = t end
    f.ClearAllPoints = function(self) self.__points = {} end
    f.SetPoint = function(self, ...)
        self.__points = self.__points or {}
        self.__points[#self.__points + 1] = { ... }
    end
    f.GetPoint = function(self, i)
        local p = self.__points and self.__points[i or 1]
        if p then return unpack(p) end
    end
    f.GetNumPoints = function(self) return self.__points and #self.__points or 0 end
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end

-- Fake of the client's aura container: records groups and calls each
-- group's initializeFrame once with a fresh button so decoration code runs.
local function newAuraContainer(name, parent, template)
    local c = newFrame("AuraContainer", name, parent, template)
    c.__groups = {}
    c.__enchants = {}
    c.AddAuraGroup = function(self, key, filter, options)
        assert(type(key) == "string" and key ~= "", "groupKey")
        assert(self.__groups[key] == nil, "duplicate group " .. key)
        self.__groups[key] = { filter = filter, options = options, frames = {}, filters = options and options.candidateFilters,
            layout = options and options.layout, max = options and options.maxFrameCount }
        if options and options.initializeFrame then
            local btn = newFrame("Button", nil, self)
            btn.SetIcon = function() end
            btn.SetDurationCooldown = function() end
            btn.SetDurationText = function() end
            btn.SetApplicationCount = function() end
            btn.AddDispelTypeTexture = function() end
            btn.SetCancelAuraButtons = function() end
            btn.SetTooltipAnchorPoint = function() end
            btn.GetLeft = function() return 0 end
            self.__groups[key].frames[1] = btn
            options.initializeFrame(btn)
        end
    end
    c.HasAuraGroup = function(self, key) return self.__groups[key] ~= nil end
    c.SetAuraGroupCandidateFilters = function(self, key, f) assert(self.__groups[key], key); self.__groups[key].filters = f end
    c.SetAuraGroupLayout = function(self, key, l) assert(self.__groups[key], key); self.__groups[key].layout = l end
    c.SetAuraGroupMaxFrameCount = function(self, key, n) assert(self.__groups[key], key); self.__groups[key].max = n end
    c.GetAuraGroupFrameCount = function(self, key) return self.__groups[key] and #self.__groups[key].frames or 0 end
    c.GetAuraGroupFrame = function(self, key, i) return self.__groups[key] and self.__groups[key].frames[i] end
    c.AddItemEnchantment = function(self, slot, options)
        self.__enchants[slot] = options
        if options and options.initializeFrame then
            local btn = newFrame("Button", nil, self)
            btn.SetIcon = function() end
            btn.SetDurationCooldown = function() end
            btn.SetDurationText = function() end
            btn.SetApplicationCount = function() end
            btn.SetCancelAuraButtons = function() end
            btn.SetTooltipAnchorPoint = function() end
            options.initializeFrame(btn)
        end
    end
    c.SetItemEnchantmentLayout = function(self, l) self.__enchantLayout = l end
    return c
end

_G.CreateFrame = function(frameType, name, parent, template)
    if frameType == "AuraContainer" then return newAuraContainer(name, parent, template) end
    return newFrame(frameType, name, parent, template)
end
_G.AuraContainerSortMethod = { Default = 0, Expiration = 4, ExpirationOnly = 5 }
_G.AuraContainerSortDirection = { Normal = 0, Reverse = 1 }
_G.CustomAuraContainerItemEnchantmentPlacement = { BeforeAuraGroups = 0, AfterAuraGroups = 1 }
_G.AnchorUtil = { FlowDirection = { Left = 0, Right = 1, Up = 2, Down = 3 }, FlowLayoutAxis = { Horizontal = 0, Vertical = 1 } }

function stub.FireEvent(event, ...)
    for _, f in ipairs(frames) do
        if f.__events[event] and f.__scripts.OnEvent then
            f.__scripts.OnEvent(f, event, ...)
        end
    end
end

function stub.AnyFrameRegistered(event)
    for _, f in ipairs(frames) do
        if f.__events[event] then return true end
    end
    return false
end

-- ---------------------------------------------------------------------
-- Timers
-- ---------------------------------------------------------------------

local timers = {}
_G.C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = { at = upClock + delay, fn = fn } end,
    NewTicker = function(interval, fn)
        local t = { cancelled = false }
        t.Cancel = function() t.cancelled = true end
        t.IsCancelled = function() return t.cancelled end
        stub.tickers[#stub.tickers + 1] = { interval = interval, fn = fn, ticker = t }
        return t
    end,
}
stub.tickers = {}

-- Runs every pending C_Timer.After callback regardless of delay.
function stub.RunTimers()
    local pending = timers
    timers = {}
    for _, t in ipairs(pending) do t.fn() end
    return #pending
end

-- ---------------------------------------------------------------------
-- Units and group state
-- ---------------------------------------------------------------------

-- stub.SetUnits({ [token] = { name = "Bob", class = "PRIEST" } })
stub.units = {}
function stub.SetUnits(units) stub.units = units end

_G.UnitExists = function(unit) return stub.units[unit] ~= nil end
_G.UnitName = function(unit)
    local u = stub.units[unit]
    return u and u.name or nil
end
_G.UnitClass = function(unit)
    local u = stub.units[unit]
    if not u or not u.class then return nil end
    local pretty = string.upper(string.sub(u.class, 1, 1)) .. string.lower(string.sub(u.class, 2))
    return pretty, u.class, 1
end
_G.UnitIsUnit = function(a, b) return a == b end

stub.inGroup, stub.inRaid, stub.inCombat = false, false, false
function stub.SetGroup(inGroup, inRaid)
    stub.inGroup = inGroup and true or false
    stub.inRaid = inRaid and true or false
end
function stub.SetCombat(v) stub.inCombat = v and true or false end
_G.IsInGroup = function() return stub.inGroup end
_G.IsInRaid = function() return stub.inRaid end
_G.InCombatLockdown = function() return stub.inCombat end
_G.GetNumGroupMembers = function()
    local n = 0
    for token in pairs(stub.units) do
        if string.find(token, "^party%d") or string.find(token, "^raid%d") then n = n + 1 end
    end
    return stub.inGroup and (n + 1) or 0
end

-- ---------------------------------------------------------------------
-- Auras
-- ---------------------------------------------------------------------

-- stub.SetAuras("player", "HELPFUL", { { name=, icon=, duration=, expirationTime=, sourceUnit=, ... }, ... })
-- Each entry is copied into a fresh table per call, the way the client
-- hands out a new table each time. auraInstanceID defaults to the index.
stub.auras = {}
stub.secretGroupAuras = false

function stub.SetAuras(unit, filter, list)
    stub.auras[unit] = stub.auras[unit] or {}
    stub.auras[unit][filter] = list
end

local function copyAura(a, i)
    if issecrettable(a) then return a end
    local out = {}
    for k, v in pairs(a) do out[k] = v end
    if out.auraInstanceID == nil then out.auraInstanceID = i end
    if out.applications == nil then out.applications = 0 end
    if out.duration == nil then out.duration = 0 end
    if out.expirationTime == nil then out.expirationTime = 0 end
    if out.isHelpful == nil then out.isHelpful = true end
    return out
end

_G.C_UnitAuras = {
    GetAuraDataByIndex = function(unit, index, filter)
        if stub.auraReadsThrow then error("Auras cannot be accessed when secret while tainted") end
        if stub.secretGroupAuras and unit ~= "player" then return stub.MakeSecretTable() end
        local list = stub.auras[unit] and stub.auras[unit][filter]
        local a = list and list[index]
        if not a then return nil end
        return copyAura(a, index)
    end,
    GetAuraDataByAuraInstanceID = function(unit, id)
        for _, list in pairs(stub.auras[unit] or {}) do
            for i, a in ipairs(list) do
                local c = copyAura(a, i)
                if not issecrettable(c) and c.auraInstanceID == id then return c end
            end
        end
        return nil
    end,
}

-- stub.SetWeaponEnchants({ { slot = 0, timeLeft = 600000, charges = 3, enchantType = 1, enchantIconID = 135 }, ... })
stub.weaponEnchants = {}
function stub.SetWeaponEnchants(list) stub.weaponEnchants = list or {} end

_G.Enum = _G.Enum or {}
_G.Enum.WeaponSlot = { MainHand = 0, OffHand = 1, Ranged = 2 }

_G.C_Item = {
    GetWeaponEnchantInfo = function(slotID)
        local out = {}
        for _, e in ipairs(stub.weaponEnchants) do
            if e.slot == slotID then
                out[#out + 1] = { hasEnchant = true, timeLeft = e.timeLeft, charges = e.charges or 0,
                    enchantType = e.enchantType or 0, enchantIconID = e.enchantIconID }
            end
        end
        return out
    end,
}
_G.C_Spell = { CancelItemTempEnchantment = function() end }
_G.GetInventoryItemTexture = function(unit, slot) return "tex:" .. tostring(slot) end

stub.inventoryTooltips = {}
_G.C_TooltipInfo = {
    GetInventoryItem = function(unit, slot)
        return stub.inventoryTooltips[slot]
    end,
}

-- ---------------------------------------------------------------------
-- Colours and misc globals
-- ---------------------------------------------------------------------

local function color(r, g, b)
    return { r = r, g = g, b = b, colorStr = string.format("ff%02x%02x%02x", r * 255, g * 255, b * 255),
        GetRGB = function(self) return self.r, self.g, self.b end }
end

_G.RAID_CLASS_COLORS = {
    WARRIOR = color(0.78, 0.61, 0.43), PALADIN = color(0.96, 0.55, 0.73), HUNTER = color(0.67, 0.83, 0.45),
    ROGUE = color(1.00, 0.96, 0.41), PRIEST = color(1.00, 1.00, 1.00), SHAMAN = color(0.00, 0.44, 0.87),
    MAGE = color(0.25, 0.78, 0.92), WARLOCK = color(0.53, 0.53, 0.93), DRUID = color(1.00, 0.49, 0.04),
}
_G.DebuffTypeColor = {
    none = color(0.8, 0, 0), Magic = color(0.2, 0.6, 1.0), Curse = color(0.6, 0, 1.0),
    Disease = color(0.6, 0.4, 0), Poison = color(0, 0.6, 0),
}
_G.NORMAL_FONT_COLOR = color(1, 0.82, 0)
_G.HIGHLIGHT_FONT_COLOR = color(1, 1, 1)

_G.C_AddOns = {
    GetAddOnMetadata = function(name, field) if field == "Version" then return "1.0.0" end return nil end,
    IsAddOnLoaded = function() return false end,
}

_G.GetInstanceInfo = function() return "Zephras Isle", "none", 0, "", 5, 0, false, 2991, 0 end

_G.SlashCmdList = {}
_G.StaticPopupDialogs = {}
stub.lastPopup = nil
_G.StaticPopup_Show = function(key, a, b, data)
    stub.lastPopup = { key = key, a = a, b = b, data = data }
    return stub.lastPopup
end

-- ---------------------------------------------------------------------
-- Reset between tests
-- ---------------------------------------------------------------------

function stub.Reset()
    frames = {}
    _G.UIParent = newFrame("Frame", "UIParent")
    _G.GameTooltip = newFrame("GameTooltip", "GameTooltip")
    _G.BuffFrame = newFrame("Frame", "BuffFrame", UIParent)
    _G.DebuffFrame = newFrame("Frame", "DebuffFrame", UIParent)
    timers = {}
    stub.tickers = {}
    stub.chat = {}
    stub.units = { player = { name = "Shooty", class = "HUNTER" } }
    stub.auras = {}
    stub.secretGroupAuras = false
    stub.auraReadsThrow = false
    stub.weaponEnchants = {}
    stub.inventoryTooltips = {}
    stub.inGroup = false
    stub.inRaid = false
    stub.inCombat = false
    stub.forbidden = 0
    stub.lastPopup = nil
    wallClock = 1700000000
    upClock = 1000.0
    _G.BuffLedgerDB = nil
    _G.SlashCmdList = {}
    _G.StaticPopupDialogs = {}
    _G.BuffLedger_OnCompartmentClick = nil
end

stub.Reset()
return stub
