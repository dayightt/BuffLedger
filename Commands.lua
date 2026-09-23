-- Commands: /bl and /buffledger.

local _, BL = ...

local UI = BL.UI

local HELP = {
    "/bl options - open the settings panel (also: opt, config)",
    "/bl categories - open the Categories page",
    "/bl lock, /bl unlock - lock or unlock the buff bar",
    "/bl reset - reset the buff bar position",
    "/bl toggle <category> - show or hide one category",
    "/bl scan - list buffs on your group that BuffLedger doesn't recognise",
    "/bl auras - dump your buffs and debuffs as the client reports them",
    "/bl test [0-1 | N% | off] - preview a sample of every known buff",
    "/bl debug - toggle event tracing",
}

local function printHelp()
    BL.Print("v" .. tostring(BL.VERSION) .. " commands:")
    for _, line in ipairs(HELP) do BL.Print("  " .. line) end
end

local function parseFraction(arg)
    if arg == nil or arg == "" then return 0.4 end
    if arg == "off" or arg == "0" then return nil end
    local pct = string.match(arg, "^(%d+)%%$")
    if pct then return math.max(0, math.min(1, tonumber(pct) / 100)) end
    local n = tonumber(arg)
    if n then
        if n > 1 then n = n / 100 end
        return math.max(0, math.min(1, n))
    end
    return 0.4
end

local handlers = {}

handlers.help = printHelp
handlers.options = function() UI.OpenSettings() end
handlers.opt = handlers.options
handlers.config = handlers.options
handlers.categories = function() UI.OpenSettings("categories") end

handlers.lock = function()
    BL.SetSetting("locked", true)
    BL.Print("Buff bar locked.")
end
handlers.unlock = function()
    BL.SetSetting("locked", false)
    BL.Print("Buff bar unlocked - drag it to move.")
end
handlers.reset = function()
    if BL.Bar then BL.Bar:ResetPosition() end
    BL.Print("Buff bar position reset.")
end

handlers.toggle = function(arg)
    if arg == "" then
        BL.Print("Usage: /bl toggle <category name>")
        return
    end
    local id = BL.Categories.FindByName(arg)
    if not id then
        BL.Print("No category called '" .. arg .. "'.")
        return
    end
    local cat = BL.Categories.Get(id)
    BL.Categories.SetHidden(id, not cat.hidden)
    BL.Print(cat.name .. (cat.hidden and " hidden." or " shown."))
end

handlers.scan = function() BL.Scan.PrintGroup() end
handlers.auras = function() BL.Scan.PrintPlayer() end

handlers.test = function(arg)
    local fraction = parseFraction(arg)
    BL.Preview.Set(fraction)
    if fraction then
        BL.Print(string.format("Preview on: %d%% of known buffs. /bl test off to stop.", math.floor(fraction * 100 + 0.5)))
    else
        BL.Print("Preview off.")
    end
end

handlers.debug = function()
    BL.tracing = not BL.tracing
    BL.Print("Event tracing " .. (BL.tracing and "on" or "off") .. ". Settings: " .. UI.SettingsStatus() .. ".")
    if BL.Bar and BL.Bar.PrintStatus then BL.Bar:PrintStatus() end
    if BL.DebuffBar and BL.DebuffBar.PrintStatus then BL.DebuffBar:PrintStatus() end
end

local function dispatch(msg)
    msg = strtrim(msg or "")
    local cmd, rest = string.match(msg, "^(%S+)%s*(.-)$")
    cmd = cmd and string.lower(cmd) or ""
    if cmd == "" then
        handlers.options()
        return
    end
    local handler = handlers[cmd]
    if handler then
        handler(rest or "")
    else
        BL.Print("Unknown command '" .. cmd .. "'.")
        printHelp()
    end
end

SLASH_BUFFLEDGER1 = "/bl"
SLASH_BUFFLEDGER2 = "/buffledger"
SlashCmdList.BUFFLEDGER = dispatch
