local stub = require("wow_stub")

T.test("Scan.Group lists only unrecognised buffs with the caster's class", function()
    local BL = stub.LoadAddon()
    stub.SetGroup(true, false)
    stub.SetUnits({
        player = { name = "Me", class = "HUNTER" },
        party1 = { name = "Bob", class = "PRIEST" },
        party2 = { name = "Ann", class = "MAGE" },
    })
    stub.SetAuras("party1", "HELPFUL", {
        { name = "Mystery Ward", sourceUnit = "party1" },
        { name = "Power Word: Fortitude", sourceUnit = "party1" },
    })
    stub.SetAuras("party2", "HELPFUL", {
        { name = "Arcane Intellect", sourceUnit = "party2" },
        { name = "Odd Glow", sourceUnit = "party1" },
        { name = "No Source" },
    })
    BL.DB.overrides["Odd Glow"] = "world"
    local report = BL.Scan.Group()
    T.eq(#report, 2)
    local byName = {}
    for _, r in ipairs(report) do byName[r.buffName] = r end
    T.eq(byName["Mystery Ward"].sourceClass, "priest")
    T.eq(byName["Mystery Ward"].unit, "party1")
    T.eq(byName["Mystery Ward"].name, "Bob")
    T.isnil(byName["No Source"].sourceClass)
    T.isnil(byName["Odd Glow"], "overridden buffs are not unrecognised")
end)

T.test("Scan.Group uses raid tokens in a raid and dedupes buff names", function()
    local BL = stub.LoadAddon()
    stub.SetGroup(true, true)
    stub.SetUnits({ player = { name = "Me", class = "HUNTER" }, raid1 = { name = "A", class = "DRUID" }, raid2 = { name = "B", class = "DRUID" } })
    stub.SetAuras("raid1", "HELPFUL", { { name = "Weird", sourceUnit = "raid1" } })
    stub.SetAuras("raid2", "HELPFUL", { { name = "Weird", sourceUnit = "raid1" } })
    local report = BL.Scan.Group()
    T.eq(#report, 1)
    T.eq(report[1].sourceClass, "druid")
end)

T.test("Scan.Group returns nil when group auras are unreadable, empty when solo", function()
    local BL = stub.LoadAddon()
    T.eq(#BL.Scan.Group(), 0)
    stub.SetGroup(true, false)
    stub.SetUnits({ player = { name = "Me", class = "HUNTER" }, party1 = { name = "Bob", class = "PRIEST" } })
    stub.SetAuras("party1", "HELPFUL", { { name = "X" } })
    stub.secretGroupAuras = true
    T.noerror(function() T.isnil(BL.Scan.Group()) end)
    stub.secretGroupAuras = false
    stub.auraReadsThrow = true
    T.noerror(function() T.isnil(BL.Scan.Group()) end, "a refused read reports unreadable instead of erroring")
end)

T.test("Scan.PrintGroup and PrintPlayer write to chat", function()
    local BL = stub.LoadAddon()
    stub.SetAuras("player", "HELPFUL", { { name = "Spirit", duration = 100, expirationTime = 1050 } })
    stub.SetAuras("player", "HARMFUL", { { name = "Weakened Soul", dispelName = "Magic" } })
    BL.Scan.PrintPlayer()
    T.truthy(#stub.chat >= 2)
    local joined = table.concat(stub.chat, "\n")
    T.truthy(string.find(joined, "Spirit", 1, true))
    T.truthy(string.find(joined, "Weakened Soul", 1, true))
    stub.chat = {}
    BL.Scan.PrintGroup()
    T.truthy(string.find(stub.LastChat(), "group", 1, true))
end)

T.test("Preview yields a fraction of the seed buffs with fake timers", function()
    local BL = stub.LoadAddon()
    T.falsy(BL.Preview.Active())
    T.isnil(BL.Preview.Entries())
    local total = T.count(BL.SEED_BUFFS)
    BL.Preview.Set(0.5)
    T.truthy(BL.Preview.Active())
    local entries = BL.Preview.Entries()
    T.truthy(math.abs(#entries - math.floor(total * 0.5)) <= 1)
    T.eq(entries[1].kind, "preview")
    T.truthy(entries[1].icon)
    T.truthy(entries[1].expirationTime > BL.Clock())
    T.eq(entries[1].timed, true)
    BL.Preview.Set(1)
    T.eq(#BL.Preview.Entries(), total)
    BL.Preview.Set(nil)
    T.isnil(BL.Preview.Entries())
    T.falsy(BL.Preview.Active())
end)
