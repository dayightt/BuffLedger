local stub = require("wow_stub")

local function entry(name, spellId, extra)
    local e = { kind = "aura", name = name, spellId = spellId, sourceUnit = "player" }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end

T.test("Learn records spell id -> name and reports changes once", function()
    local BL = stub.LoadAddon()
    local fired = 0
    BL.On("SPELLS_CHANGED", function() fired = fired + 1 end)
    T.truthy(BL.Spells.Learn({ entry("Arcane Intellect", 1459), entry("Well Fed", 433) }))
    T.eq(BL.Spells.Name(1459), "Arcane Intellect")
    T.eq(BL.DB.spells[433], "Well Fed")
    T.eq(fired, 1)
    T.falsy(BL.Spells.Learn({ entry("Arcane Intellect", 1459) }), "nothing new")
    T.eq(fired, 1)
    T.truthy(BL.Spells.Learn({ entry("Arcane Intellect", 1460) }), "another rank is new")
end)

T.test("Learn ignores entries without a plain name or spell id, and weapons", function()
    local BL = stub.LoadAddon()
    T.noerror(function()
        T.falsy(BL.Spells.Learn({
            entry(nil, 5), entry("X", nil), entry(stub.MakeSecret("Y"), 7), entry("Z", stub.MakeSecret(8)),
            { kind = "weapon", name = "Sharpened", spellId = 9 }, { kind = "preview", name = "P", spellId = 10 },
        }))
    end)
    T.eq(T.count(BL.DB.spells), 0)
end)

T.test("Learn teaches the caster's class through Classify", function()
    local BL = stub.LoadAddon()
    stub.SetUnits({ player = { name = "Me", class = "HUNTER" }, party1 = { name = "Bob", class = "PRIEST" } })
    BL.Spells.Learn({ entry("Mystery Ward", 999, { sourceUnit = "party1" }) })
    T.eq(BL.DB.learned["Mystery Ward"], "priest")
    T.eq(BL.Spells.CategoryOf(999), "priest")
end)

T.test("CategoryOf follows overrides, seeds and deletions; unknown ids are other", function()
    local BL = stub.LoadAddon()
    BL.Spells.Learn({ entry("Arcane Intellect", 1459), entry("Odd Buff", 77) })
    T.eq(BL.Spells.CategoryOf(1459), "mage")
    T.eq(BL.Spells.CategoryOf(77), "other")
    T.eq(BL.Spells.CategoryOf(12345), "other")
    BL.Classify.Assign("Arcane Intellect", "priest")
    T.eq(BL.Spells.CategoryOf(1459), "priest")
    BL.Categories.Delete("priest")
    T.eq(BL.Spells.CategoryOf(1459), "other")
end)

T.test("Sets groups known ids by category and lists every known id", function()
    local BL = stub.LoadAddon()
    BL.Spells.Learn({ entry("Arcane Intellect", 1459), entry("Arcane Intellect", 1460), entry("Well Fed", 433), entry("Odd Buff", 77) })
    local sets = BL.Spells.Sets()
    T.deq(sets.byCategory.mage, { [1459] = true, [1460] = true })
    T.deq(sets.byCategory.consumable, { [433] = true })
    T.deq(sets.byCategory.other, { [77] = true })
    T.deq(sets.known, { [1459] = true, [1460] = true, [433] = true, [77] = true })
    T.deq(sets.categorised, { [1459] = true, [1460] = true, [433] = true }, "Other-bound ids are not categorised")
    T.deq(sets.byCategory.priest, {}, "every category has a set, even empty")
end)

T.test("IdsForName returns every rank sharing a name", function()
    local BL = stub.LoadAddon()
    BL.Spells.Learn({ entry("Arcane Intellect", 1459), entry("Arcane Intellect", 1460), entry("Well Fed", 433) })
    local ids = BL.Spells.IdsForName("Arcane Intellect")
    table.sort(ids)
    T.deq(ids, { 1459, 1460 })
    T.deq(BL.Spells.IdsForName("Nope"), {})
end)
