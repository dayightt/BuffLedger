local stub = require("wow_stub")

T.test("Collect maps aura data to plain entries and stops at the first gap", function()
    local BL = stub.LoadAddon()
    stub.SetAuras("player", "HELPFUL", {
        { name = "Spirit", icon = 136126, spellId = 8112, duration = 1800, expirationTime = 2500, sourceUnit = "player", dispelName = "Magic", applications = 0, auraInstanceID = 1 },
        { name = "Aspect of the Monkey", icon = 132159, spellId = 13163, duration = 0, expirationTime = 0, sourceUnit = "player", applications = 0, auraInstanceID = 3 },
        { name = "Stacky", icon = 1, applications = 5, auraInstanceID = 9, expirationTime = 1100, duration = 100 },
    })
    local entries = BL.Auras.Collect("HELPFUL")
    T.eq(#entries, 3)
    local e = entries[1]
    T.eq(e.kind, "aura")
    T.eq(e.index, 1)
    T.eq(e.auraInstanceID, 1)
    T.eq(e.name, "Spirit")
    T.eq(e.icon, 136126)
    T.eq(e.spellId, 8112)
    T.eq(e.duration, 1800)
    T.eq(e.expirationTime, 2500)
    T.eq(e.sourceUnit, "player")
    T.eq(e.dispelName, "Magic")
    T.eq(e.applications, 0)
    T.eq(e.filter, "HELPFUL")
    T.eq(e.timed, true)
    T.eq(entries[2].timed, false, "permanent aura")
    T.eq(entries[3].applications, 5)
    T.eq(#BL.Auras.Collect("HARMFUL"), 0)
end)

T.test("Collect caps at MAX", function()
    local BL = stub.LoadAddon()
    local list = {}
    for i = 1, BL.Auras.MAX + 20 do list[i] = { name = "B" .. i, icon = i } end
    stub.SetAuras("player", "HELPFUL", list)
    T.eq(#BL.Auras.Collect("HELPFUL"), BL.Auras.MAX)
end)

T.test("secret fields drop out, secret tables are skipped, nothing errors", function()
    local BL = stub.LoadAddon()
    stub.SetAuras("player", "HELPFUL", {
        { name = stub.MakeSecret("Hidden"), icon = 5, expirationTime = stub.MakeSecret(99), duration = 10, sourceUnit = stub.MakeSecret("party1"), auraInstanceID = 4 },
        stub.MakeSecretTable(),
        { name = "Plain", icon = 6, auraInstanceID = 7 },
    })
    local entries
    T.noerror(function() entries = BL.Auras.Collect("HELPFUL") end)
    T.eq(#entries, 2)
    T.isnil(entries[1].name)
    T.isnil(entries[1].expirationTime)
    T.truthy(issecretvalue(entries[1].secretExpiration), "raw secret kept for the Cooldown widget")
    T.isnil(entries[2].secretExpiration)
    T.isnil(entries[1].sourceUnit)
    T.eq(entries[1].icon, 5)
    T.eq(entries[1].timed, false)
    T.eq(entries[2].name, "Plain")
    T.eq(entries[2].index, 3, "index is the API slot, not the position")
end)

T.test("CollectWeapons builds entries from C_Item.GetWeaponEnchantInfo", function()
    local BL = stub.LoadAddon()
    stub.SetTime(nil, 1000)
    stub.SetWeaponEnchants({
        { slot = 0, timeLeft = 600000, charges = 3, enchantType = 1, enchantIconID = 555 },
        { slot = 1, timeLeft = 30000, charges = 0, enchantType = 2 },
    })
    stub.inventoryTooltips[17] = { lines = { { leftText = "Sword" }, { leftText = "Frost Oil (30 min)", leftColor = { r = 0, g = 1, b = 0 } } } }
    local w = BL.Auras.CollectWeapons()
    T.eq(#w, 2)
    T.eq(w[1].kind, "weapon")
    T.eq(w[1].slot, 16)
    T.eq(w[1].weaponSlot, 0)
    T.eq(w[1].enchantType, 1)
    T.eq(w[1].icon, 555)
    T.eq(w[1].applications, 3)
    T.near(w[1].expirationTime, 1600, 0.001)
    T.eq(w[1].timed, true)
    T.eq(w[1].name, "Weapon Enchant")
    T.eq(w[2].slot, 17)
    T.eq(w[2].icon, "tex:17", "falls back to the item texture")
    T.eq(w[2].name, "Frost Oil", "green tooltip line, duration suffix stripped")
    T.near(w[2].expirationTime, 1030, 0.001)
end)

T.test("CollectWeapons is empty with nothing enchanted and survives a missing API", function()
    local BL = stub.LoadAddon()
    T.eq(#BL.Auras.CollectWeapons(), 0)
    local saved = C_Item.GetWeaponEnchantInfo
    C_Item.GetWeaponEnchantInfo = nil
    T.noerror(function() T.eq(#BL.Auras.CollectWeapons(), 0) end)
    C_Item.GetWeaponEnchantInfo = saved
end)

T.test("CollectWeapons flags a refused read and can skip the name lookup", function()
    local BL = stub.LoadAddon()
    stub.SetWeaponEnchants({ { slot = 1, timeLeft = 30000, charges = 0, enchantType = 2 } })
    stub.inventoryTooltips[17] = { lines = { { leftText = "Sword" }, { leftText = "Frost Oil", leftColor = { r = 0, g = 1, b = 0 } } } }
    local w, restricted = BL.Auras.CollectWeapons(true)
    T.eq(#w, 1); T.falsy(restricted)
    T.eq(w[1].name, "Weapon Enchant", "no tooltip lookup")
    local saved = C_Item.GetWeaponEnchantInfo
    C_Item.GetWeaponEnchantInfo = function() error("refused") end
    w, restricted = BL.Auras.CollectWeapons()
    T.eq(#w, 0); T.truthy(restricted)
    C_Item.GetWeaponEnchantInfo = saved
end)

T.test("Signature is order-sensitive and ignores timers", function()
    local BL = stub.LoadAddon()
    local a = { { kind = "aura", auraInstanceID = 1, expirationTime = 10 }, { kind = "aura", auraInstanceID = 2 }, { kind = "weapon", slot = 16 } }
    local b = { { kind = "aura", auraInstanceID = 1, expirationTime = 99 }, { kind = "aura", auraInstanceID = 2 }, { kind = "weapon", slot = 16 } }
    local c = { { kind = "aura", auraInstanceID = 2 }, { kind = "aura", auraInstanceID = 1 }, { kind = "weapon", slot = 16 } }
    T.eq(BL.Auras.Signature(a), BL.Auras.Signature(b))
    T.truthy(BL.Auras.Signature(a) ~= BL.Auras.Signature(c))
    T.eq(BL.Auras.Signature({}), "")
end)
