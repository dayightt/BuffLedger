-- Loads every file, UI included, under a permissive global environment
-- (unknown globals become do-anything objects) and drives the main paths.
-- Catches nil-index errors and typos that only the client would surface.

local stub = require("wow_stub")

local UI_FILES = { "Widgets.lua", "Bar.lua", "DebuffBar.lua", "UI_Preview.lua", "UI_Settings.lua", "UI_Minimap.lua", "Commands.lua" }

local AnyMT = {}
local function anyObject()
    return setmetatable({}, AnyMT)
end
AnyMT.__index = function(t, k)
    local v = function(...) return anyObject() end
    rawset(t, k, v)
    return v
end
AnyMT.__call = function() return anyObject() end
AnyMT.__concat = function() return "" end

local function withPermissiveGlobals(fn)
    local mt = getmetatable(_G)
    setmetatable(_G, { __index = function(_, k) return anyObject() end })
    _G.Mixin = function(t, ...)
        for i = 1, select("#", ...) do
            for k, v in pairs((select(i, ...))) do t[k] = v end
        end
        return t
    end
    _G.IsShiftKeyDown = function() return false end
    _G.Settings = {
        VarType = { Boolean = "b", Number = "n" },
        RegisterProxySetting = function() return anyObject() end,
        RegisterVerticalLayoutCategory = function() return anyObject() end,
        RegisterVerticalLayoutSubcategory = function() return anyObject() end,
        RegisterCanvasLayoutSubcategory = function() return anyObject() end,
        RegisterAddOnCategory = function() end,
        CreateCheckbox = function() end,
        CreateSlider = function() end,
        CreateSliderOptions = function() return anyObject() end,
        OpenToCategory = function() end,
    }
    _G.MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
    _G.CreateSettingsButtonInitializer = function() return anyObject() end
    _G.SettingsPanel = anyObject()
    _G.CreateScrollBoxListLinearView = function() return anyObject() end
    _G.ScrollUtil = anyObject()
    _G.CreateDataProvider = function(t) return t end
    _G.ScrollBoxConstants = {}
    _G.ColorPickerFrame = anyObject()
    _G.Minimap = CreateFrame("Frame", "Minimap"); Minimap:SetSize(140, 140)
    _G.GetCursorPosition = function() return 0, 0 end
    _G.C_Texture = { GetAtlasInfo = function() return {} end }
    _G.MenuUtil = { CreateContextMenu = function(_, fn) fn(nil, anyObject()) end }
    _G.YES, _G.NO, _G.ACCEPT, _G.CANCEL = "Yes", "No", "Accept", "Cancel"
    local ok, err = xpcall(fn, debug.traceback)
    setmetatable(_G, mt)
    if not ok then error(err, 0) end
end

local function loadEverything()
    local BL = stub.LoadAddon({ before = function() _G.BuffLedgerDB = {} end })
    for _, file in ipairs(UI_FILES) do
        local chunk, err = loadfile(file)
        if not chunk then error(err) end
        chunk("BuffLedger", BL)
    end
    return BL
end

local function groupOf(BL, key) return BL.Bar.frame.__groups[key] end

T.test("all files load and the login path runs", function()
    withPermissiveGlobals(function()
        local BL = loadEverything()
        stub.SetAuras("player", "HELPFUL", {
            { name = "Arcane Intellect", icon = 1, spellId = 1459, duration = 1800, expirationTime = 2800, sourceUnit = "party1" },
            { name = "Well Fed", icon = 2, spellId = 433, duration = 900, expirationTime = 1900, sourceUnit = "player" },
            { name = "Aspect of the Monkey", icon = 3, spellId = 13163 },
            { name = "Camp Benefits", icon = 9, spellId = 9999, duration = 3600, expirationTime = 4600 },
        })
        stub.SetAuras("player", "HARMFUL", { { name = "Weakened Soul", icon = 4, spellId = 6788, dispelName = "Magic", duration = 15, expirationTime = 1015 } })
        stub.FireEvent("PLAYER_LOGIN")
        stub.FireEvent("PLAYER_ENTERING_WORLD", true, false)
        stub.RunTimers()

        for _, m in ipairs(stub.chat) do T.falsy(string.find(m, "failed", 1, true), m) end
        T.truthy(BL.Bar.frame, "buff container created")
        T.truthy(BL.DebuffBar.frame, "debuff container created")
        T.truthy(BuffFrame.__shown == false, "stock buff frame hidden")
        T.eq(BL.Bar.frame.__groups.mage ~= nil, true, "one group per category")
        T.truthy(groupOf(BL, "other"))
        T.isnil(groupOf(BL, "weapon"), "weapon is item enchantments, not a group")
        T.eq(next(BL.Bar.frame.__enchants), nil, "the container's enchant slots aren't used")
        T.truthy(BL.DebuffBar.frame.__groups.debuffs)

        -- spell ids were learned and routed into the group filters
        T.eq(BL.DB.spells[1459], "Arcane Intellect")
        T.eq(BL.DB.spells[433], "Well Fed")
        local mage = groupOf(BL, "mage")
        T.truthy(mage.filters.includeSpellIDs[1459], "mage filter has Arcane Intellect")
        T.falsy(mage.filters.includeSpellIDs[433])
        T.truthy(groupOf(BL, "consumable").filters.includeSpellIDs[433])
        T.truthy(groupOf(BL, "other").filters.excludeSpellIDs[1459], "other excludes categorised ids")
        T.truthy(groupOf(BL, "other").filters.excludeSpellIDs[13163], "seeded hunter buff is categorised")
        T.falsy(groupOf(BL, "other").filters.excludeSpellIDs[9999], "an unrecognised buff stays visible in Other")
        T.eq(BL.Spells.CategoryOf(9999), "other")
        T.eq(BL.Bar:Counts(), 4)
        T.eq(BL.DebuffBar:Counts(), 1)

        -- layout indexes follow category order; buttons got decorated
        T.eq(groupOf(BL, "warrior").layout.layoutIndex, 1)
        T.eq(groupOf(BL, "other").layout.layoutIndex, 13)
        local btn = mage.frames[1]
        T.truthy(btn.Edge and btn.Icon and btn.Duration and btn.Count and btn.Badge)

        -- weapon enchants are our own buttons at the start of the bar
        T.eq(BL.Bar.weaponWidth, 0, "no strip without an enchant")
        stub.SetWeaponEnchants({ { slot = 0, timeLeft = 600000, charges = 0, enchantType = 1, enchantIconID = 777 } })
        stub.FireEvent("UNIT_INVENTORY_CHANGED", "player")
        local wbtn = BL.Bar.weaponFrame.buttons[1]
        T.truthy(wbtn and wbtn.__shown, "weapon button shown")
        T.eq(wbtn.Icon.__texture, 777)
        T.eq(BL.Bar.weaponWidth, 30 + 12, "one icon plus the category gap")
        T.eq(select(3, BL.Bar.frame:GetPoint(1)), "TOPLEFT", "container hangs off the strip's far edge")
        T.noerror(function() wbtn.__scripts.OnEnter(wbtn); wbtn.__scripts.OnClick(wbtn, "RightButton") end)
        -- a refused read in combat keeps the icon
        stub.SetCombat(true)
        local saved = C_Item.GetWeaponEnchantInfo
        C_Item.GetWeaponEnchantInfo = function() error("refused") end
        BL.Bar:UpdateWeapons()
        T.truthy(wbtn.__shown, "icon kept through a refused read")
        C_Item.GetWeaponEnchantInfo = saved
        stub.SetCombat(false)
        BL.Categories.SetHidden("weapon", true)
        BL.Bar:UpdateWeapons()
        T.falsy(wbtn.__shown, "hidden Weapon category hides the strip")
        T.eq(BL.Bar.weaponWidth, 0)
        BL.Categories.SetHidden("weapon", false)
        stub.RunTimers()
        BL.Bar:UpdateWeapons()
        T.eq(BL.Bar.weaponWidth, 42)

        -- in combat: no reads, nothing errors, groups untouched
        stub.SetCombat(true)
        stub.auraReadsThrow = true
        T.noerror(function()
            stub.FireEvent("UNIT_AURA", "player", stub.MakeSecretTable())
            BL.SetSetting("iconSize", 36)
            stub.RunTimers()
            BL.Bar:OnShiftClick(0, 0)
        end)
        T.truthy(BL.Bar.restylePending, "button restyle deferred to after combat")
        stub.auraReadsThrow = false
        stub.SetCombat(false)
        stub.FireEvent("PLAYER_REGEN_ENABLED")
        T.falsy(BL.Bar.restylePending)

        -- reassignment out of combat moves the id between filters
        BL.Classify.Assign("Arcane Intellect", "priest", "test")
        stub.RunTimers()
        T.truthy(groupOf(BL, "priest").filters.includeSpellIDs[1459])
        T.falsy(groupOf(BL, "mage").filters.includeSpellIDs[1459])

        -- hidden category -> zero frames; consolidation -> one frame + badge
        BL.Categories.SetHidden("hunter", true)
        stub.RunTimers()
        T.eq(groupOf(BL, "hunter").max, 0)
        BL.Categories.SetConsolidate("consumable", true)
        stub.SetAuras("player", "HELPFUL", {
            { name = "Well Fed", icon = 2, spellId = 433, duration = 900, expirationTime = 1900 },
            { name = "Elixir of the Mongoose", icon = 5, spellId = 17538, duration = 900, expirationTime = 1500 },
            { name = "Arcane Intellect", icon = 1, spellId = 1459, duration = 1800, expirationTime = 2800 },
        })
        stub.FireEvent("UNIT_AURA", "player", { isFullUpdate = false })
        stub.RunTimers()
        T.eq(groupOf(BL, "consumable").max, 1)
        T.eq(BL.Bar.memberCounts.consumable, 2)
        local cbtn = groupOf(BL, "consumable").frames[1]
        T.eq(cbtn.Badge.__text, 2)

        -- the cursor maps through the client's flow layout to (group, index) -> entry
        -- holder at UI (1000, 500) top-right corner, growLeft: priest(AI, moved) ... consumable(collapsed)
        BL.Bar.holder.GetRight = function() return 1000 end
        BL.Bar.holder.GetLeft = function() return 860 end
        BL.Bar.holder.GetTop = function() return 500 end
        local members = BL.Bar:AllMembers()
        T.eq(#members.priest, 1)
        T.eq(#members.consumable, 2)
        local flow = BL.Layout.Flow(BL.Bar:FlowGroups(members), BL.Bar:FlowOptions())
        T.eq(#flow.elements, 2, "priest icon + one collapsed consumable icon")
        T.eq(flow.elements[1].key, "priest")
        T.eq(flow.elements[2].key, "consumable")
        -- the weapon strip (42) comes first, then the first icon occupies
        -- x in [-30, 0] from the container's right edge
        local W0 = 1000 - 42
        local element, list = BL.Bar:ElementAt(W0 - 10, 490)
        T.eq(element.key, "priest")
        T.eq(list[element.index].name, "Arcane Intellect")
        -- second icon: 30 + 4 spacing + 12 gap further left
        element, list = BL.Bar:ElementAt(W0 - 46 - 10, 490)
        T.eq(element.key, "consumable")
        T.eq(list[element.index].name, "Elixir of the Mongoose", "soonest expiry first, like the client")
        T.isnil((BL.Bar:ElementAt(W0 - 42, 490)), "the gap hits nothing")
        T.isnil((BL.Bar:ElementAt(1000 - 10, 490)), "the weapon strip isn't a container slot")

        -- shift makes the shield take the mouse; a click there opens the menu for the hovered entry
        T.falsy(BL.Bar.shield.__mouse)
        stub.FireEvent("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
        T.truthy(BL.Bar.shield.__mouse)
        _G.GetCursorPosition = function() return W0 - 10, 490 end
        local menuFor
        BL.Bar.OpenCategoryMenu = function(_, entry) menuFor = entry.name end
        BL.Bar.shield.__scripts.OnClick(BL.Bar.shield, "RightButton")
        T.eq(menuFor, "Arcane Intellect")
        stub.FireEvent("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
        T.falsy(BL.Bar.shield.__mouse)

        -- hovering the collapsed icon opens the popout
        _G.GetCursorPosition = function() return W0 - 46 - 10, 490 end
        BL.Bar:PollHover()
        T.truthy(BuffLedgerPopout and BuffLedgerPopout.__shown, "popout opened for a consolidated group")
        local hidden = 0
        _G.GameTooltip = { IsShown = function() return true end, Hide = function() hidden = hidden + 1 end }
        BuffLedgerPopout.back.__scripts.OnUpdate(BuffLedgerPopout.back, 0.01)
        T.truthy(hidden > 0, "no tooltip on the consolidated icon itself")
        _G.GameTooltip = anyObject()
        T.eq(BuffLedgerPopout.tooltipOffset, -(BL.Layout.DURATION_HEIGHT + 8), "member tooltips anchored below a one-row popout")
        _G.GetCursorPosition = function() return 0, 0 end

        -- deleted category: its group is emptied, ids fall to other
        BL.Categories.Delete("priest")
        stub.RunTimers()
        T.eq(groupOf(BL, "priest").max, 0)
        T.eq(BL.Spells.CategoryOf(1459), "other")
        T.falsy(groupOf(BL, "other").filters.excludeSpellIDs[1459], "a deleted category's buffs show under Other")

        -- settings changes reach the bars
        BL.SetSetting("locked", false)
        BL.SetSetting("scale", 1.5, "debuff")
        BL.SetSetting("growLeft", false)
        BL.SetSetting("hideBlizzardFrames", false)
        stub.RunTimers()
        T.truthy(BuffFrame.__shown, "stock buff frame shown again")

        -- preview + commands
        SlashCmdList.BUFFLEDGER("test 50%")
        stub.RunTimers()
        T.truthy(BuffLedgerPreview and BuffLedgerPreview.__shown)
        SlashCmdList.BUFFLEDGER("test off")
        stub.RunTimers()
        T.falsy(BuffLedgerPreview.__shown)
        SlashCmdList.BUFFLEDGER("toggle mage")
        T.eq(BL.Categories.Get("mage").hidden, true)
        SlashCmdList.BUFFLEDGER("lock")
        SlashCmdList.BUFFLEDGER("unlock")
        SlashCmdList.BUFFLEDGER("reset")
        SlashCmdList.BUFFLEDGER("auras")
        SlashCmdList.BUFFLEDGER("scan")
        SlashCmdList.BUFFLEDGER("debug")
        SlashCmdList.BUFFLEDGER("debug")
        SlashCmdList.BUFFLEDGER("help")
        SlashCmdList.BUFFLEDGER("bogus")
        SlashCmdList.BUFFLEDGER("")

        -- compartment + minimap
        BuffLedger_OnCompartmentEnter(nil, anyObject())
        BuffLedger_OnCompartmentLeave()
        BuffLedger_OnCompartmentClick(nil, "RightButton")
        BL.SetSetting("minimapButton", true)
        BL.SetSetting("minimapButton", false)

        -- category editing through the canvas refresh
        BL.UI.RefreshCategories()
    end)
end)
