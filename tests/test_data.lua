local stub = require("wow_stub")

T.test("every seed entry and pattern points at a shipped category id", function()
    local BL = stub.LoadAddon()
    local valid = {}
    for _, def in ipairs(BL.Categories.DEFAULTS) do valid[def.id] = true end
    local n = 0
    for name, id in pairs(BL.SEED_BUFFS) do
        T.truthy(valid[id], "SEED_BUFFS[" .. name .. "] = " .. tostring(id))
        T.eq(type(name), "string")
        n = n + 1
    end
    T.truthy(n > 200, "seed table is substantial: " .. n)
    for i, entry in ipairs(BL.SEED_PATTERNS) do
        T.eq(type(entry[1]), "string", "pattern " .. i)
        T.truthy(valid[entry[2]], "pattern " .. i .. " -> " .. tostring(entry[2]))
    end
end)

T.test("Lookup: exact match beats patterns, patterns catch families, unknown is nil", function()
    local BL = stub.LoadAddon()
    T.eq(BL.Data.Lookup("Arcane Intellect"), "mage")
    T.eq(BL.Data.Lookup("Power Word: Fortitude"), "priest")
    T.eq(BL.Data.Lookup("Rallying Cry of the Dragonslayer"), "world")
    T.eq(BL.Data.Lookup("Elixir of the Mongoose"), "consumable")
    T.eq(BL.Data.Lookup("Elixir of Something New"), "consumable", "pattern")
    T.eq(BL.Data.Lookup("Flask of Whatever"), "consumable", "pattern")
    T.eq(BL.Data.Lookup("Sayge's Dark Fortune of Damage"), "world", "pattern")
    T.eq(BL.Data.Lookup("Dense Sharpening Stone"), "weapon", "pattern")
    T.eq(BL.Data.Lookup("Brilliant Wizard Oil"), "weapon", "pattern")
    T.isnil(BL.Data.Lookup("Totally Unknown Buff"))
    T.isnil(BL.Data.Lookup(nil))
    T.isnil(BL.Data.Lookup(42))
end)

T.test("Lookup: an explicit entry wins over a pattern that would also match", function()
    local BL = stub.LoadAddon()
    BL.SEED_BUFFS["Elixir of Warriorness"] = "warrior"
    T.eq(BL.Data.Lookup("Elixir of Warriorness"), "warrior")
    BL.SEED_BUFFS["Elixir of Warriorness"] = nil
end)
