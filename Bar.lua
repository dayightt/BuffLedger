-- Bar: the buff bar (and, through the same factory, the debuff bar).
--
-- The bar is one of the client's own aura containers. We never read aura
-- data to draw it: we register one aura group per category, filtered by
-- spell ID, tell the client how to lay the groups out (order, gaps, row
-- width, growth direction) and hand each button a texture, a cooldown
-- and two font strings. The client fills them, sorts them, moves them
-- and handles right-click cancelling - in combat too, where addon code
-- is not allowed to look at auras at all.
--
-- The client also hides which of its buttons are live (their shown
-- state, icon and geometry are secret or deliberately stale), so nothing
-- here asks a button anything. Interaction works from data instead: out
-- of combat we know each group's members and their client order, and
-- Layout.Flow is the client's own layout algorithm, so a cursor position
-- maps to (group, index) and from there to a buff by name.

local _, BL = ...

local W = BL.Widgets
local Layout = BL.Layout

local TEXT_HEIGHT = Layout.DURATION_HEIGHT
local POPOUT_LEAVE_DELAY = 0.3
local POPOUT_PAD = 8
local POPOUT_COLUMNS = 8
local HOVER_INTERVAL = 0.1
local WEAPON_INTERVAL = 0.2
local ENCHANT_KEY = "weapon"

local DISPEL_COLORS = {
    Magic = { r = 0.2, g = 0.6, b = 1.0 }, Curse = { r = 0.6, g = 0.0, b = 1.0 }, Disease = { r = 0.6, g = 0.4, b = 0.0 },
    Poison = { r = 0.0, g = 0.6, b = 0.0 }, Bleed = { r = 1.0, g = 0.0, b = 0.0 }, None = { r = 0.8, g = 0.0, b = 0.0 },
}

local function dispelColors()
    local out = {}
    for name, fallback in pairs(DISPEL_COLORS) do
        local c = DebuffTypeColor and DebuffTypeColor[name == "None" and "none" or name]
        out[name] = c and { r = c.r, g = c.g, b = c.b } or fallback
    end
    return out
end

local function inCombat() return InCombatLockdown() end

-- Frames anchored to a container must opt out of untrusted layout scripts
-- once the container has groups; inherit the opt-in template when it exists.
local function createCompanion(frameType, parent, extraTemplate)
    local templates = extraTemplate and ("DisableUntrustedLayoutScriptsTemplate," .. extraTemplate) or "DisableUntrustedLayoutScriptsTemplate"
    local ok, f = pcall(CreateFrame, frameType, nil, parent, templates)
    if ok and f then return f end
    return CreateFrame(frameType, nil, parent, extraTemplate)
end

-- Cursor position in UI units (the space GetLeft/GetTop use).
local function cursorUI()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    return x / scale, y / scale
end

-- ---------------------------------------------------------------------
-- Shift state. Shields (see below) only take the mouse while Shift is
-- held; the modifier event is the reliable source on this client.
-- ---------------------------------------------------------------------

local shields = {}
local shiftHeld = false
local editModeActive = false
local popout, popoutBack, popoutLeaveAt, popoutOwner, popoutRect, popoutShown

local function hideTooltip()
    local ok, shown = pcall(GameTooltip.IsShown, GameTooltip)
    if ok and BL.Plain(shown) == true then pcall(GameTooltip.Hide, GameTooltip) end
end

local function applyShields()
    for _, sh in ipairs(shields) do
        pcall(sh.EnableMouse, sh, (shiftHeld and not sh.suspended) and true or false)
    end
end

local function setShiftHeld(down)
    if down == shiftHeld then return end
    shiftHeld = down
    applyShields()
end

BL.RegisterEvent("MODIFIER_STATE_CHANGED", function(_, key, state)
    key, state = BL.Plain(key), BL.Plain(state)
    if type(key) ~= "string" or not string.find(key, "SHIFT") then return end
    setShiftHeld((state == 1) or (state == true) or (state == "1"))
end)
BL.RegisterEvent("PLAYER_ENTERING_WORLD", function() setShiftHeld(false) end)

-- A shield covers a container and takes clicks while Shift is held;
-- onClick receives the cursor in UI units.
local function createShield(container, strata, onClick)
    local sh = createCompanion("Button", UIParent)
    sh:SetAllPoints(container)
    sh:SetFrameStrata(strata)
    sh:SetFrameLevel(50)
    sh:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    sh:EnableMouse(false)
    sh.suspended = false
    sh:SetScript("OnClick", function()
        local x, y = cursorUI()
        onClick(x, y)
    end)
    shields[#shields + 1] = sh
    return sh
end

-- ---------------------------------------------------------------------
-- Bar mixin
-- ---------------------------------------------------------------------

local BarMixin = {}

function BarMixin:Setting(key) return BL.GetSetting(key, self.scope) end
function BarMixin:SetSetting(key, value) BL.SetSetting(key, value, self.scope) end
function BarMixin:IsDebuff() return self.scope == "debuff" end
function BarMixin:Corner() return self:Setting("growLeft") and "TOPRIGHT" or "TOPLEFT" end

-- Position -------------------------------------------------------------

-- The holder is a plain frame that carries the position; the container
-- hangs off its corner. The container's own geometry is set by the
-- client with secret values, so it can't be moved and read back itself.
function BarMixin:SavePosition()
    local ok, point, _, relativePoint, x, y = pcall(self.holder.GetPoint, self.holder, 1)
    point, relativePoint, x, y = BL.Plain(point), BL.Plain(relativePoint), BL.Plain(x), BL.Plain(y)
    if ok and type(point) == "string" and type(x) == "number" and type(y) == "number" then
        self:SetSetting("point", { point = point, relativePoint = relativePoint or point, x = x, y = y })
    end
end

-- Without a saved point the bar sits on the client's own frame for this
-- bar (BuffFrame / DebuffFrame), which Edit Mode keeps positioned even
-- while hidden, so "default" means exactly where the stock icons were.
function BarMixin:ApplyPosition()
    local p = self:Setting("point")
    local corner = self:Corner()
    self.holder:ClearAllPoints()
    if p and p.point then
        self.holder:SetPoint(p.point, UIParent, p.relativePoint or p.point, p.x or 0, p.y or 0)
    else
        local stock = self:IsDebuff() and DebuffFrame or BuffFrame
        if stock then
            self.holder:SetPoint("TOPRIGHT", stock, "TOPRIGHT", 0, 0)
        else
            self.holder:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -20)
        end
    end
    self.frame:ClearAllPoints()
    local weapons = self.weaponFrame
    if weapons then
        -- Weapon icons first, then the container off their far edge; the
        -- weapon strip's width moves the container without touching it.
        weapons:ClearAllPoints()
        weapons:SetPoint(corner, self.holder, corner, 0, 0)
        self.frame:SetPoint(corner, weapons, corner == "TOPRIGHT" and "TOPLEFT" or "TOPRIGHT", 0, 0)
    else
        self.frame:SetPoint(corner, self.holder, corner, 0, 0)
    end
end

function BarMixin:ResetPosition()
    self:SetSetting("point", nil)
    self:ApplyPosition()
end

-- The container is only as big as its content (nothing at all with no
-- auras), so the drag handle is the holder: anchored at the bar's growth
-- corner with a minimum size.
function BarMixin:ApplyLock()
    local locked = self:Setting("locked")
    local size, spacing = self:Setting("iconSize"), self:Setting("spacing")
    local columns = math.max(1, math.floor(tonumber(self:Setting("columns")) or 1))
    local width = math.max(140, math.min(columns, 6) * (size + spacing))
    self.holder:SetSize(width, size + TEXT_HEIGHT + 4)
    self.holder:EnableMouse(not locked)
    self.overlay:SetShown(not locked)
    self:ApplyPosition()
end

function BarMixin:ApplyScale()
    local scale = tonumber(self:Setting("scale")) or 1
    self.frame:SetScale(scale)
    if self.weaponFrame then self.weaponFrame:SetScale(scale) end
end

function BarMixin:ApplyBackground()
    if self:Setting("showBackground") then
        self.background:SetBackdrop({ bgFile = W.WHITE, edgeFile = W.WHITE, edgeSize = 1 })
        self.background:SetBackdropColor(0, 0, 0, 0.5)
        self.background:SetBackdropBorderColor(0, 0, 0, 0.8)
        self.background:Show()
    else
        self.background:Hide()
    end
end

-- Container ------------------------------------------------------------

function BarMixin:Create()
    if self.frame then return end
    local ok, c = pcall(CreateFrame, "AuraContainer", self.frameName, UIParent, "CustomAuraContainerTemplate")
    if not ok or not c then
        BL.Print("This client has no aura container support (" .. tostring(c) .. "); the bar can't be shown.")
        return
    end
    self.frame = c
    self.groups = {}        -- [groupKey] = true once registered with the container
    self.buttons = {}       -- [groupKey] = { button, ... } created by the client for that group
    self.consolidated = {}  -- [groupKey] = true while the group is collapsed to one icon
    self.memberCounts = {}  -- [groupKey] = n, refreshed whenever auras are readable
    self.lastCount = 0

    c:SetUnit("player")
    c:SetFrameStrata("LOW")
    c:EnableMouse(false)

    local holder = CreateFrame("Frame", self.frameName .. "Holder", UIParent)
    holder:SetFrameStrata("LOW")
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)
    holder:RegisterForDrag("LeftButton")
    holder:SetScript("OnDragStart", function(h) h:StartMoving() end)
    holder:SetScript("OnDragStop", function(h)
        h:StopMovingOrSizing()
        self:SavePosition()
    end)
    self.holder = holder

    local background = createCompanion("Frame", c, "BackdropTemplate")
    background:SetAllPoints(c)
    background:SetFrameLevel(math.max(0, c:GetFrameLevel() - 1))
    background:EnableMouse(false)
    self.background = background

    local overlay = CreateFrame("Frame", nil, holder, "BackdropTemplate")
    overlay:SetAllPoints(holder)
    overlay:SetFrameStrata("MEDIUM")
    overlay:SetBackdrop({ bgFile = W.WHITE, edgeFile = W.WHITE, edgeSize = 1 })
    overlay:SetBackdropColor(0.2, 0.6, 1, 0.25)
    overlay:SetBackdropBorderColor(0.4, 0.7, 1, 0.9)
    overlay:EnableMouse(false)
    local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText(self.label)
    self.overlay = overlay

    if not self:IsDebuff() then
        self:CreateWeapons()
        self.shield = createShield(c, "MEDIUM", function(x, y) self:OnShiftClick(x, y) end)
        holder.accum = 0
        holder:SetScript("OnUpdate", function(_, elapsed)
            holder.accum = holder.accum + elapsed
            if holder.accum < HOVER_INTERVAL then return end
            holder.accum = 0
            self:PollHover()
        end)
    end

    self:ApplyPosition()
    self:ApplyScale()
    self:ApplyBackground()
    self:ApplyLock()
    self:ApplyFlow()
    self:ApplyGroups()
end

function BarMixin:FlowOptions()
    local size, spacing = self:Setting("iconSize"), self:Setting("spacing")
    local columns = math.max(1, math.floor(tonumber(self:Setting("columns")) or 1))
    return {
        anchorPoint = self:Corner(),
        horizontal = self:Setting("growLeft") and Layout.LEFT or Layout.RIGHT,
        vertical = Layout.DOWN,
        maximumLineSize = columns * (size + spacing),
    }
end

function BarMixin:ApplyFlow()
    local c = self.frame
    if not c then return end
    local o = self:FlowOptions()
    pcall(function()
        c:SetFlowLayoutMaximumLineSize(o.maximumLineSize)
        c:SetFlowLayoutAnchorPoint(o.anchorPoint)
        c:SetFlowLayoutGrowthDirection(o.horizontal, o.vertical)
    end)
end

function BarMixin:GroupLayout(index)
    local size, spacing = self:Setting("iconSize"), self:Setting("spacing")
    local textH = self:Setting("durationInside") and 0 or TEXT_HEIGHT
    return {
        layoutIndex = index,
        elementWidth = size,
        elementHeight = size,
        elementSpacing = spacing,
        lineSpacing = spacing + textH,
        groupSpacing = self:IsDebuff() and 0 or (self:Setting("categoryGap") or 0),
    }
end

local function groupState()
    return { inGroup = IsInGroup(), inRaid = IsInRaid() }
end

-- Registers or updates every group. Everything here is safe in combat:
-- it only talks to the container, never to the buttons.
function BarMixin:ApplyGroups()
    local c = self.frame
    if not c then return end
    self:InvalidateMembers()
    if self:IsDebuff() then
        if not self.groups.debuffs then
            local ok, err = pcall(c.AddAuraGroup, c, "debuffs", "HARMFUL", {
                sortMethod = AuraContainerSortMethod.ExpirationOnly,
                sortDirection = AuraContainerSortDirection.Normal,
                layout = self:GroupLayout(1),
                initializeFrame = function(btn) self:InitButton(btn, "debuffs") end,
            })
            if ok then self.groups.debuffs = true else BL.Print("Debuff group failed: " .. tostring(err)) end
        else
            pcall(c.SetAuraGroupLayout, c, "debuffs", self:GroupLayout(1))
        end
        self:Restyle()
        return
    end

    local sets = BL.Spells.Sets()
    local settings = BL.DB.settings
    local state = groupState()
    local present = {}
    for index, id in ipairs(BL.Categories.Order()) do
        local cat = BL.Categories.Get(id)
        present[id] = true
        if id == ENCHANT_KEY then
            self.weaponLayoutDirty = true
        elseif cat then
            local filters
            if id == "other" then
                filters = { excludeSpellIDs = sets.categorised }
            else
                filters = { includeSpellIDs = sets.byCategory[id] or {} }
            end
            local collapsed = Layout.ConsolidateAllowed(cat, settings, state)
            local max = cat.hidden and 0 or (collapsed and 1 or math.huge)
            self.consolidated[id] = (collapsed and not cat.hidden) or nil
            local layout = self:GroupLayout(index)
            if not self.groups[id] then
                local ok, err = pcall(c.AddAuraGroup, c, id, "HELPFUL", {
                    candidateFilters = filters,
                    sortMethod = AuraContainerSortMethod.ExpirationOnly,
                    sortDirection = AuraContainerSortDirection.Normal,
                    maxFrameCount = max,
                    layout = layout,
                    initializeFrame = function(btn) self:InitButton(btn, id) end,
                })
                if ok then self.groups[id] = true else BL.Print("Group " .. id .. " failed: " .. tostring(err)) end
            else
                local okF, errF = pcall(c.SetAuraGroupCandidateFilters, c, id, filters)
                local okL, errL = pcall(c.SetAuraGroupLayout, c, id, layout)
                local okM, errM = pcall(c.SetAuraGroupMaxFrameCount, c, id, max)
                if BL.tracing and not (okF and okL and okM) then
                    BL.Print(string.format("group %s update failed: %s / %s / %s", id, tostring(errF), tostring(errL), tostring(errM)))
                end
            end
        end
    end
    -- Groups for categories that no longer exist stay registered but empty.
    for key in pairs(self.groups) do
        if not present[key] then
            pcall(c.SetAuraGroupMaxFrameCount, c, key, 0)
            self.consolidated[key] = nil
        end
    end
    self:Restyle()
    self:RefreshCounts()
end

-- Weapon enchants ------------------------------------------------------------
--
-- The container's own item-enchantment slots draw nothing on this client,
-- so the weapon icons are ours: plain buttons fed from the weapon-enchant
-- API, which isn't aura data and stays readable in combat. They sit at the
-- start of the bar (where the stock frame keeps them) and the container
-- hangs off the strip's far edge, so the strip's width is all that moves.

function BarMixin:CreateWeapons()
    local f = CreateFrame("Frame", self.frameName .. "Weapons", UIParent)
    f:SetFrameStrata("LOW")
    f:SetSize(0.001, 1)
    f.buttons = {}
    f.accum = WEAPON_INTERVAL
    f:SetScript("OnUpdate", function(_, elapsed)
        f.accum = f.accum + elapsed
        if f.accum < WEAPON_INTERVAL then return end
        f.accum = 0
        self:UpdateWeapons()
    end)
    self.weaponFrame = f
    self.weaponWidth = 0
    self.weaponEntries = {}
end

local function weaponButtonOnEnter(btn)
    local e = btn.entry
    if not e then return end
    GameTooltip:SetOwner(btn, "ANCHOR_BOTTOMLEFT")
    if not pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", e.slot) then
        GameTooltip:SetText(e.name or "Weapon Enchant", 1, 1, 1)
    end
    GameTooltip:Show()
end

local function weaponButtonOnClick(btn, button)
    local e = btn.entry
    if button ~= "RightButton" or not e or IsShiftKeyDown() then return end
    if C_Spell and C_Spell.CancelItemTempEnchantment then
        pcall(C_Spell.CancelItemTempEnchantment, e.weaponSlot, e.enchantType)
    elseif CancelItemTempEnchantment then
        pcall(CancelItemTempEnchantment, e.weaponSlot + 1)
    end
end

function BarMixin:WeaponButton(i)
    local f = self.weaponFrame
    local b = f.buttons[i]
    if b then return b end
    b = W.CreateIconButton(f)
    b:RegisterForClicks("RightButtonUp")
    b:SetScript("OnEnter", weaponButtonOnEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", weaponButtonOnClick)
    f.buttons[i] = b
    return b
end

-- Places n weapon buttons and sizes the strip. Runs only when the count or
-- the look changed.
function BarMixin:LayoutWeapons(n)
    local f = self.weaponFrame
    local size, spacing = self:Setting("iconSize"), self:Setting("spacing")
    local t = self:Setting("borderThickness") or 1
    local corner = self:Corner()
    local dir = corner == "TOPRIGHT" and -1 or 1
    local cat = BL.Categories.Get(ENCHANT_KEY) or BL.Categories.Get("other")
    local color = cat and cat.color or { 0.65, 0.65, 0.65 }
    for i = 1, n do
        local b = self:WeaponButton(i)
        -- The border sits outside the icon, like the container's buttons.
        b:SetIconSize(size + 2 * t)
        b:SetBorderThickness(t)
        b:SetBorderColor(color[1], color[2], color[3])
        b:SetDurationInside(self:Setting("durationInside"))
        b:SetOverlay(nil)
        b:ClearAllPoints()
        b:SetPoint(corner, f, corner, dir * ((i - 1) * (size + spacing) - t), t)
        b:Show()
    end
    for i = n + 1, #f.buttons do
        f.buttons[i].entry = nil
        f.buttons[i]:Hide()
    end
    local width = 0
    if n > 0 then width = n * size + (n - 1) * spacing + (self:Setting("categoryGap") or 0) end
    self.weaponWidth = width
    f:SetSize(math.max(width, 0.001), size)
end

function BarMixin:UpdateWeapons()
    local f = self.weaponFrame
    if not f then return end
    local entries, restricted = BL.Auras.CollectWeapons(true)
    -- A refused read keeps the last known enchants; their expiry times
    -- are absolute, so the countdown carries on.
    if restricted then entries = self.weaponEntries else self.weaponEntries = entries end
    local cat = BL.Categories.Get(ENCHANT_KEY)
    if (cat and cat.hidden) or self.previewActive or editModeActive then entries = {} end
    local n = #entries
    if n ~= self.weaponCount or self.weaponLayoutDirty then
        self.weaponCount = n
        self.weaponLayoutDirty = false
        self:LayoutWeapons(n)
    end
    local now = BL.Clock()
    for i, e in ipairs(entries) do
        local b = f.buttons[i]
        b.entry = e
        b.Icon:SetTexture(e.icon or W.QUESTION_ICON)
        b:SetCount(e.applications)
        b:SetTimeLeft(e.expirationTime - now, true)
    end
end

-- Buttons --------------------------------------------------------------

-- Called by the client once per button it creates for a group. The
-- button belongs to the client; we only decorate it and register the
-- pieces it should drive. Nothing is ever read back from it.
function BarMixin:InitButton(btn, groupKey)
    local size = self:Setting("iconSize")
    btn:SetSize(size, size)
    btn.groupKey = groupKey

    -- Category-coloured edge: a flat square one border-width larger than
    -- the icon, behind it.
    btn.Edge = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
    btn.Edge:SetTexture(W.WHITE)

    btn.Icon = btn:CreateTexture(nil, "BACKGROUND", nil, 0)
    btn.Icon:SetAllPoints()
    btn.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn:SetIcon(btn.Icon)

    btn.Cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.Cooldown:SetAllPoints()
    btn.Cooldown:SetHideCountdownNumbers(true)
    btn.Cooldown:SetDrawSwipe(false)
    btn.Cooldown:SetDrawEdge(false)
    btn.Cooldown:SetDrawBling(false)
    btn.Cooldown:EnableMouse(false)
    btn:SetDurationCooldown(btn.Cooldown)

    btn.Duration = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.Duration:SetJustifyH("CENTER")
    btn:SetDurationText(btn.Duration)

    btn.Count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    btn.Count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    btn:SetApplicationCount(btn.Count)

    -- Our own badge for consolidated groups (member count).
    btn.Badge = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    btn.Badge:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 1, 1)
    btn.Badge:SetTextColor(1, 0.82, 0)
    btn.Badge:Hide()

    if self:IsDebuff() then
        -- Edge tinted by dispel type (the client picks the colour), plus
        -- the stock dispel border with its corner badge on top.
        local white = { asset = W.WHITE }
        pcall(btn.AddDispelTypeTexture, btn, btn.Edge, {
            style = "CustomAsset", showWhenHarmful = true, showWithoutDispelType = true,
            customDispelAssetMap = { Magic = white, Curse = white, Disease = white, Poison = white, Bleed = white, None = white },
            customDispelColorMap = dispelColors(),
        })
        btn.dispelBorder = btn:CreateTexture(nil, "OVERLAY", nil, 1)
        btn.dispelBorder:SetPoint("CENTER", btn, "CENTER")
        pcall(btn.AddDispelTypeTexture, btn, btn.dispelBorder, { style = "BorderWithIcon", showWhenHarmful = true, showWithoutDispelType = true })
    else
        btn:SetCancelAuraButtons("RightButtonUp")
    end
    pcall(btn.SetTooltipAnchorPoint, btn, "ANCHOR_BOTTOMLEFT")

    self.buttons[groupKey] = self.buttons[groupKey] or {}
    table.insert(self.buttons[groupKey], btn)
    self:StyleButton(btn, groupKey)
end

function BarMixin:StyleButton(btn, groupKey)
    local size = self:Setting("iconSize")
    local t = self:Setting("borderThickness") or 1
    local inside = self:Setting("durationInside")
    btn:SetSize(size, size)
    btn.Edge:ClearAllPoints()
    btn.Edge:SetPoint("TOPLEFT", btn, "TOPLEFT", -t, t)
    btn.Edge:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", t, -t)
    if not self:IsDebuff() then
        local cat = BL.Categories.Get(groupKey) or BL.Categories.Get("other")
        local c = cat and cat.color or { 0.65, 0.65, 0.65 }
        btn.Edge:SetVertexColor(c[1], c[2], c[3], 1)
    end
    btn.Duration:ClearAllPoints()
    if inside then
        btn.Duration:SetPoint("CENTER", btn, "CENTER", 0, 0)
    else
        btn.Duration:SetPoint("TOP", btn, "BOTTOM", 0, -1)
    end
    if btn.dispelBorder then btn.dispelBorder:SetSize(size * 40 / 30, size * 40 / 30) end
end

-- Re-applies sizes and colours to every button. Buttons can't be touched
-- while the client is hiding aura data (combat), so it waits for the
-- next PLAYER_REGEN_ENABLED in that case.
function BarMixin:Restyle()
    if not self.frame then return end
    if inCombat() then
        self.restylePending = true
        return
    end
    self.restylePending = false
    for key, list in pairs(self.buttons) do
        for _, btn in ipairs(list) do pcall(self.StyleButton, self, btn, key) end
    end
    self.weaponLayoutDirty = true
end

-- Readable data (out of combat) ------------------------------------------

-- Members of a group as the container shows them (client order), or nil
-- when the client refuses to share aura data right now.
function BarMixin:GroupMembers(groupKey)
    if groupKey == ENCHANT_KEY then return BL.Auras.CollectWeapons() end
    local entries, restricted = BL.Auras.Collect(self:IsDebuff() and "HARMFUL" or "HELPFUL")
    if restricted then return nil end
    if self:IsDebuff() then return Layout.SortLikeClient(entries) end
    local sets = BL.Spells.Sets()
    local members = {}
    for _, e in ipairs(entries) do
        local id = e.spellId
        local inGroup
        if groupKey == "other" then
            inGroup = id == nil or not sets.categorised[id]
        else
            inGroup = id ~= nil and sets.byCategory[groupKey] and sets.byCategory[groupKey][id]
        end
        if inGroup then members[#members + 1] = e end
    end
    return Layout.SortLikeClient(members)
end

-- Every group's members at once: { [groupKey] = members }, or nil when
-- restricted. Cached until the next aura change or group update, so the
-- hover poll doesn't re-read auras and rebuild spell sets ten times a second.
function BarMixin:AllMembers()
    if self.membersCache then return self.membersCache end
    local entries, restricted = BL.Auras.Collect("HELPFUL")
    if restricted then return nil end
    local sets = BL.Spells.Sets()
    local byGroup = {}
    for _, id in ipairs(BL.Categories.Order()) do byGroup[id] = {} end
    for _, e in ipairs(entries) do
        local id = e.spellId
        local key = (id ~= nil and sets.categorised[id]) and BL.Spells.CategoryOf(id) or "other"
        if not byGroup[key] then key = "other" end
        table.insert(byGroup[key], e)
    end
    for key, list in pairs(byGroup) do byGroup[key] = Layout.SortLikeClient(list) end
    byGroup[ENCHANT_KEY] = BL.Auras.CollectWeapons()
    self.membersCache = byGroup
    return byGroup
end

function BarMixin:InvalidateMembers()
    self.membersCache = nil
end

-- The client's flow-layout input for this bar, from readable data: one
-- group per category in layout order with the number of buttons it shows.
-- Weapons are drawn outside the container and take no part.
function BarMixin:FlowGroups(members)
    local groups = {}
    for index, id in ipairs(BL.Categories.Order()) do
        local cat = BL.Categories.Get(id)
        if cat and id ~= ENCHANT_KEY then
            local layout = self:GroupLayout(index)
            local count = #(members[id] or {})
            if cat.hidden then
                count = 0
            elseif self.consolidated[id] then
                count = math.min(count, 1)
            end
            groups[#groups + 1] = {
                key = id, count = count,
                elementWidth = layout.elementWidth, elementHeight = layout.elementHeight,
                elementSpacing = layout.elementSpacing, lineSpacing = layout.lineSpacing, groupSpacing = layout.groupSpacing,
            }
        end
    end
    return groups
end

-- Maps the cursor (UI units) to the element under it, plus the group's
-- members, or nil. Only meaningful out of combat.
function BarMixin:ElementAt(x, y)
    if inCombat() or not self.holder then return nil end
    local members = self:AllMembers()
    if not members then return nil end
    local flow = Layout.Flow(self:FlowGroups(members), self:FlowOptions())
    local corner = self:Corner()
    local originX = corner == "TOPRIGHT" and self.holder:GetRight() or self.holder:GetLeft()
    local originY = self.holder:GetTop()
    if not originX or not originY then return nil end
    local scale = tonumber(self:Setting("scale")) or 1
    -- The container starts past the weapon strip.
    local offset = (self.weaponWidth or 0) * scale
    originX = corner == "TOPRIGHT" and (originX - offset) or (originX + offset)
    local element = Layout.HitTest(flow, corner, (x - originX) / scale, (y - originY) / scale)
    if not element then return nil end
    return element, members[element.key] or {}, originX, originY, scale
end

-- Learns spell ids from whatever is readable and refreshes counts.
function BarMixin:Learn()
    if self:IsDebuff() then
        self:RefreshCounts()
        return
    end
    self:InvalidateMembers()
    local entries, restricted = BL.Auras.Collect("HELPFUL")
    if restricted then return end
    self.lastCount = #entries
    local changed = BL.Spells.Learn(entries)
    if not changed then self:RefreshCounts() end
    -- On change SPELLS_CHANGED re-applies the groups, which refreshes counts.
end

function BarMixin:RefreshCounts()
    if not self.frame or inCombat() then return end
    if self:IsDebuff() then
        local entries, restricted = BL.Auras.Collect("HARMFUL")
        if not restricted then self.lastCount = #entries end
        return
    end
    local members = self:AllMembers()
    for key, list in pairs(self.buttons) do
        local n = 0
        if self.consolidated[key] then
            n = members and #(members[key] or {}) or (self.memberCounts[key] or 0)
        end
        self.memberCounts[key] = n
        for _, btn in ipairs(list) do
            pcall(function()
                if n > 1 then
                    btn.Badge:SetText(n)
                    btn.Badge:Show()
                else
                    btn.Badge:Hide()
                end
            end)
        end
    end
end

function BarMixin:Counts()
    return self.lastCount or 0
end

-- /bl debug: what each group is set to and how many members it has.
function BarMixin:PrintStatus()
    if not self.frame then
        BL.Print(self.scope .. " bar: no container")
        return
    end
    local state = groupState()
    BL.Print(string.format("%s bar: %s, in group %s, in raid %s", self.scope,
        inCombat() and "in combat (aura data withheld)" or "out of combat", tostring(state.inGroup), tostring(state.inRaid)))
    if self:IsDebuff() then return end
    local members = self:AllMembers()
    for _, id in ipairs(BL.Categories.Order()) do
        local cat = BL.Categories.Get(id)
        if cat then
            local n = members and #(members[id] or {}) or -1
            BL.Print(string.format("  %s: consolidate=%s hidden=%s -> %s, members=%d",
                cat.name, tostring(cat.consolidate), tostring(cat.hidden),
                self.consolidated[id] and "one icon" or "all icons", n))
        end
    end
end

-- Interaction ------------------------------------------------------------

function BarMixin:OpenCategoryMenu(entry, owner)
    local name = entry and BL.Plain(entry.name)
    if type(name) ~= "string" then return end
    W.CategoryMenu(owner or self.shield or UIParent, BL.Classify.Resolve(entry), function(id)
        BL.Classify.Assign(name, id, "bar")
    end, name)
end

function BarMixin:OnShiftClick(x, y)
    if inCombat() then
        BL.Print("Categories can't be changed while in combat.")
        return
    end
    local element, members = self:ElementAt(x, y)
    if not element then
        if BL.tracing then BL.Print("shift-click: nothing under the cursor") end
        return
    end
    local entry = members[element.index]
    if BL.tracing then BL.Print(string.format("shift-click: %s #%d -> %s", element.key, element.index, tostring(entry and entry.name))) end
    if entry then self:OpenCategoryMenu(entry) end
end

-- Hover for consolidated groups: the client's buttons can't tell us when
-- the cursor enters them, so a light poll maps the cursor through the
-- layout instead.
function BarMixin:PollHover()
    if not next(self.consolidated) or inCombat() or self.previewActive then return end
    if popoutShown then return end
    local x, y = cursorUI()
    local element, members, originX, originY, scale = self:ElementAt(x, y)
    if not element or not self.consolidated[element.key] then return end
    local l, b, r = Layout.ElementRect(element, self:Corner())
    self:ShowPopout(element.key, members, originX + (l + r) / 2 * scale, originY + b * scale)
end

-- Consolidated popout: a second container showing the whole group ----------

function BarMixin:EnsurePopout()
    if popout then return popout end
    local ok, c = pcall(CreateFrame, "AuraContainer", "BuffLedgerPopout", UIParent, "CustomAuraContainerTemplate")
    if not ok or not c then return nil end
    popout = c
    c:SetUnit("player")
    c:SetFrameStrata("DIALOG")
    c:SetClampedToScreen(true)
    c:EnableMouse(false)
    c:Hide()
    local back = createCompanion("Frame", UIParent, "TooltipBackdropTemplate")
    back:SetFrameStrata("DIALOG")
    back:SetFrameLevel(math.max(0, c:GetFrameLevel() - 1))
    back:SetPoint("TOPLEFT", c, "TOPLEFT", -POPOUT_PAD, POPOUT_PAD)
    back:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", POPOUT_PAD, -(POPOUT_PAD + TEXT_HEIGHT))
    back:EnableMouse(false)
    back:Hide()
    popoutBack = back
    c.back = back
    c.shield = createShield(c, "DIALOG", function(x, y)
        local bar = c.bar
        if bar then bar:OnPopoutShiftClick(x, y) end
    end)
    -- Keep the popout while the cursor is inside it or over its owner
    -- slot. Both rectangles come from our own layout numbers: the frames'
    -- geometry derives from the container's secret size and can't be asked.
    local function inside(rect, x, y)
        return rect and x >= rect.left and x <= rect.right and y >= rect.bottom and y <= rect.top
    end
    back:SetScript("OnUpdate", function()
        if not popoutShown or not popoutLeaveAt then return end
        local x, y = cursorUI()
        -- The consolidated icon itself has no tooltip: its popout is the
        -- detail. The client shows one on enter, so hide it every frame.
        if inside(popoutOwner, x, y) and not inside(popoutRect, x, y) then hideTooltip() end
        if inside(popoutRect, x, y) or inside(popoutOwner, x, y) then
            popoutLeaveAt = BL.Clock() + POPOUT_LEAVE_DELAY
            return
        end
        if BL.Clock() >= popoutLeaveAt then
            c:Hide()
            back:Hide()
            popoutShown = false
            popoutOwner = nil
            popoutLeaveAt = nil
        end
    end)
    return c
end

-- anchorX/anchorY: UI-unit point (bottom centre of the owning icon).
function BarMixin:ShowPopout(groupKey, members, anchorX, anchorY)
    local c = self:EnsurePopout()
    if not c then return end
    local sets = BL.Spells.Sets()
    local filters = (groupKey == "other") and { excludeSpellIDs = sets.categorised } or { includeSpellIDs = sets.byCategory[groupKey] or {} }
    local layout = self:GroupLayout(1)
    layout.groupSpacing = 0
    c.bar = self
    c.groupKey = groupKey
    c.members = members
    if not c.hasGroup then
        local ok = pcall(c.AddAuraGroup, c, "members", "HELPFUL", {
            candidateFilters = filters,
            sortMethod = AuraContainerSortMethod.ExpirationOnly,
            sortDirection = AuraContainerSortDirection.Normal,
            layout = layout,
            initializeFrame = function(btn) self:InitPopoutButton(btn) end,
        })
        c.hasGroup = ok
    else
        pcall(c.SetAuraGroupCandidateFilters, c, "members", filters)
        pcall(c.SetAuraGroupLayout, c, "members", layout)
    end
    local size, spacing = self:Setting("iconSize"), self:Setting("spacing")
    c.flowOptions = { anchorPoint = "TOPLEFT", horizontal = Layout.RIGHT, vertical = Layout.DOWN, maximumLineSize = POPOUT_COLUMNS * (size + spacing) }
    c.flowGroup = { key = groupKey, count = #members, elementWidth = size, elementHeight = size, elementSpacing = spacing,
        lineSpacing = layout.lineSpacing, groupSpacing = 0 }
    pcall(function()
        c:SetFlowLayoutMaximumLineSize(c.flowOptions.maximumLineSize)
        c:SetFlowLayoutAnchorPoint("TOPLEFT")
        c:SetFlowLayoutGrowthDirection(Layout.RIGHT, Layout.DOWN)
    end)
    -- Position: centred under the icon, in UI units.
    local scale = tonumber(self:Setting("scale")) or 1
    local flow = Layout.Flow({ c.flowGroup }, c.flowOptions)
    -- Member tooltips hang below the whole popout, clear of every row.
    c.tooltipOffset = -(flow.height - size + TEXT_HEIGHT + POPOUT_PAD)
    for _, btn in ipairs(c.buttons or {}) do pcall(self.StylePopoutButton, self, btn, groupKey) end
    c.originX = anchorX - flow.width * scale / 2
    c.originY = anchorY - POPOUT_PAD - TEXT_HEIGHT
    c:SetScale(scale)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", c.originX / scale, c.originY / scale)
    popoutOwner = { left = anchorX - size * scale / 2, right = anchorX + size * scale / 2, bottom = anchorY, top = anchorY + size * scale }
    popoutRect = {
        left = c.originX - POPOUT_PAD, right = c.originX + flow.width * scale + POPOUT_PAD,
        top = c.originY + POPOUT_PAD, bottom = c.originY - (flow.height + TEXT_HEIGHT) * scale - POPOUT_PAD,
    }
    popoutLeaveAt = BL.Clock() + POPOUT_LEAVE_DELAY
    popoutShown = true
    c:Show()
    popoutBack:Show()
    hideTooltip()
end

function BarMixin:OnPopoutShiftClick(x, y)
    local c = popout
    if not c or inCombat() then return end
    local scale = tonumber(self:Setting("scale")) or 1
    local flow = Layout.Flow({ c.flowGroup }, c.flowOptions)
    local element = Layout.HitTest(flow, "TOPLEFT", (x - c.originX) / scale, (y - c.originY) / scale)
    local entry = element and c.members and c.members[element.index]
    if entry then self:OpenCategoryMenu(entry, c.shield) end
end

function BarMixin:InitPopoutButton(btn)
    local c = popout
    c.buttons = c.buttons or {}
    table.insert(c.buttons, btn)
    btn.Edge = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
    btn.Edge:SetTexture(W.WHITE)
    btn.Icon = btn:CreateTexture(nil, "BACKGROUND", nil, 0)
    btn.Icon:SetAllPoints()
    btn.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn:SetIcon(btn.Icon)
    btn.Cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.Cooldown:SetAllPoints()
    btn.Cooldown:SetHideCountdownNumbers(true)
    btn.Cooldown:SetDrawSwipe(false)
    btn.Cooldown:SetDrawEdge(false)
    btn.Cooldown:SetDrawBling(false)
    btn:SetDurationCooldown(btn.Cooldown)
    btn.Duration = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.Duration:SetPoint("TOP", btn, "BOTTOM", 0, -1)
    btn:SetDurationText(btn.Duration)
    btn.Count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    btn.Count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    btn:SetApplicationCount(btn.Count)
    btn:SetCancelAuraButtons("RightButtonUp")
    self:StylePopoutButton(btn, c.groupKey)
end

function BarMixin:StylePopoutButton(btn, groupKey)
    local size = self:Setting("iconSize")
    local t = self:Setting("borderThickness") or 1
    btn:SetSize(size, size)
    btn.Edge:ClearAllPoints()
    btn.Edge:SetPoint("TOPLEFT", btn, "TOPLEFT", -t, t)
    btn.Edge:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", t, -t)
    local cat = BL.Categories.Get(groupKey) or BL.Categories.Get("other")
    local c = cat and cat.color or { 0.65, 0.65, 0.65 }
    btn.Edge:SetVertexColor(c[1], c[2], c[3], 1)
    -- The client places these tooltips itself; its anchor API is the only
    -- way to move them.
    local offset = popout and popout.tooltipOffset or -(TEXT_HEIGHT + POPOUT_PAD)
    pcall(btn.SetTooltipAnchorPoint, btn, "ANCHOR_BOTTOM", 0, offset)
end

-- Preview (fake buffs) hides the live container while it runs ---------------

function BarMixin:SetPreviewActive(active)
    if not self.frame then return end
    self.previewActive = active
    self.frame:SetAlpha(active and 0 or 1)
    self:UpdateWeapons()
    if self.shield then
        self.shield.suspended = active and true or false
        applyShields()
    end
end

-- Coalesced refresh ---------------------------------------------------------

function BarMixin:MarkDirty()
    if self.scheduled or not self.frame then return end
    self.scheduled = true
    C_Timer.After(0, function()
        self.scheduled = false
        self:ApplyGroups()
    end)
end

function BL.CreateBar(spec)
    local bar = Mixin({}, BarMixin)
    bar.scope = spec.scope
    bar.frameName = spec.frameName
    bar.label = spec.label
    return bar
end

-- ---------------------------------------------------------------------
-- The buff bar
-- ---------------------------------------------------------------------

BL.Bar = BL.CreateBar({ scope = "buff", frameName = "BuffLedgerBar", label = "BuffLedger - drag to move" })

local function eachBar(fn)
    if BL.Bar and BL.Bar.frame then fn(BL.Bar) end
    if BL.DebuffBar and BL.DebuffBar.frame then fn(BL.DebuffBar) end
end

-- ---------------------------------------------------------------------
-- Hiding the client's own buff/debuff frames
-- ---------------------------------------------------------------------

local hidingHooked = false
local pendingHide = false

local guarding = false
local function guardShow(frame)
    if guarding then return end
    if BL.DB.settings.hideBlizzardFrames and not inCombat() and not editModeActive then
        guarding = true
        frame:Hide()
        frame:SetAlpha(0)
        guarding = false
    end
end

local function setStockFramesHidden(hidden)
    for _, frame in ipairs({ BuffFrame, DebuffFrame }) do
        if hidden then
            frame:Hide()
            frame:SetAlpha(0)
        else
            frame:SetAlpha(1)
            frame:Show()
        end
    end
end

-- Never trust our own Edit Mode flag alone: ask the client.
local function refreshEditModeFlag()
    if EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive then
        local ok, active = pcall(EditModeManagerFrame.IsEditModeActive, EditModeManagerFrame)
        if ok then editModeActive = (active == true) end
    end
end

function BL.Bar.ApplyBlizzardHiding()
    if not (BuffFrame and DebuffFrame) then return end
    if inCombat() then
        pendingHide = true
        return
    end
    pendingHide = false
    refreshEditModeFlag()
    if not hidingHooked then
        hidingHooked = true
        for _, frame in ipairs({ BuffFrame, DebuffFrame }) do
            -- HookScript needs an existing handler; these frames have none.
            if frame:GetScript("OnShow") then
                pcall(frame.HookScript, frame, "OnShow", guardShow)
            else
                pcall(frame.SetScript, frame, "OnShow", guardShow)
            end
            -- And catch the Show() call itself, so the re-hide happens in the same frame.
            pcall(hooksecurefunc, frame, "Show", guardShow)
        end
        -- Blizzard re-shows these when Edit Mode (re)applies its layout.
        if EventRegistry and EventRegistry.RegisterCallback then
            pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.SavedLayouts.LayoutsApplied", function()
                if not editModeActive then BL.Bar.ApplyBlizzardHiding() end
            end, BL)
        end
    end
    setStockFramesHidden(BL.DB.settings.hideBlizzardFrames and not editModeActive)
end

-- ---------------------------------------------------------------------
-- Edit Mode: the stock buff/debuff frames are the handles. While Edit
-- Mode is open they are shown and our bars step aside; on exit, a stock
-- frame that was moved becomes the bar's anchor again (any custom drag
-- position is dropped), so "move Buffs in Edit Mode" just works.
-- ---------------------------------------------------------------------

local function stockPoint(frame)
    if not frame then return "" end
    local ok, point, rel, relPoint, x, y = pcall(frame.GetPoint, frame, 1)
    if not ok then return "" end
    return table.concat({ tostring(point), tostring(rel and rel.GetName and rel:GetName() or rel), tostring(relPoint),
        string.format("%.1f", x or 0), string.format("%.1f", y or 0) }, "|")
end

local editModeStart = {}

local function onEditModeEnter()
    editModeActive = true
    editModeStart.buff = stockPoint(BuffFrame)
    editModeStart.debuff = stockPoint(DebuffFrame)
    if BuffFrame and DebuffFrame and not inCombat() then setStockFramesHidden(false) end
    eachBar(function(bar) bar.frame:SetAlpha(0); bar.overlay:Hide(); bar:UpdateWeapons() end)
end

local function onEditModeExit()
    editModeActive = false
    if BL.Bar.frame and stockPoint(BuffFrame) ~= editModeStart.buff and BL.GetSetting("point") then
        BL.SetSetting("point", nil)
    end
    if BL.DebuffBar and BL.DebuffBar.frame and stockPoint(DebuffFrame) ~= editModeStart.debuff and BL.GetSetting("point", "debuff") then
        BL.SetSetting("point", nil, "debuff")
    end
    eachBar(function(bar)
        bar:ApplyLock()
        bar.frame:SetAlpha(bar.previewActive and 0 or 1)
        bar:UpdateWeapons()
    end)
    BL.Bar.ApplyBlizzardHiding()
end

if EventRegistry and EventRegistry.RegisterCallback then
    pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Enter", onEditModeEnter, BL)
    pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Exit", onEditModeExit, BL)
end

-- ---------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------

-- Each login step runs on its own: a failure in one is reported and the
-- rest still happen.
local function step(label, fn)
    local ok, err = pcall(fn)
    if not ok then BL.Print(label .. " failed: " .. tostring(err)) end
end

BL.RegisterEvent("PLAYER_LOGIN", function()
    step("Buff bar", function() BL.Bar:Create() end)
    step("Debuff bar", function() if BL.DebuffBar then BL.DebuffBar:Create() end end)
    step("Hiding the default frames", function() BL.Bar.ApplyBlizzardHiding() end)
    step("Reading buffs", function() eachBar(function(bar) bar:Learn() end) end)
end)

BL.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    eachBar(function(bar) bar:Learn() end)
    if BL.Bar.frame then C_Timer.After(1, BL.Bar.ApplyBlizzardHiding) end
end)
BL.RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function()
    if BL.Bar.frame and not editModeActive then BL.Bar.ApplyBlizzardHiding() end
end)

-- Out of combat every aura change is a chance to learn a new spell id.
-- In combat the client keeps the bar current by itself.
BL.RegisterEvent("UNIT_INVENTORY_CHANGED", function(_, unit)
    if BL.Plain(unit) == "player" and BL.Bar.frame then
        BL.Bar:InvalidateMembers()
        BL.Bar:UpdateWeapons()
    end
end)

BL.RegisterEvent("UNIT_AURA", function(_, unit)
    if BL.Plain(unit) ~= "player" or inCombat() then return end
    if BL.tracing then BL.Print("UNIT_AURA") end
    eachBar(function(bar) bar:Learn() end)
    if BL.Bar.frame and BL.DB.settings.hideBlizzardFrames and BuffFrame and BuffFrame:IsShown() then
        BL.Bar.ApplyBlizzardHiding()
    end
end, "player")

BL.RegisterEvent("GROUP_ROSTER_UPDATE", function()
    if BL.Bar.frame then BL.Bar:MarkDirty() end
end)

BL.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if pendingHide then BL.Bar.ApplyBlizzardHiding() end
    eachBar(function(bar)
        bar:InvalidateMembers()
        if bar.restylePending then bar:Restyle() end
        bar:Learn()
    end)
end)

-- Saved data can arrive after the bars exist; re-apply everything then.
BL.On("DB_READY", function()
    eachBar(function(bar)
        bar:ApplyScale()
        bar:ApplyBackground()
        bar:ApplyLock()
        bar:ApplyFlow()
        bar:MarkDirty()
    end)
    if BL.Bar.frame then BL.Bar.ApplyBlizzardHiding() end
end)

BL.On("CATEGORIES_CHANGED", function() if BL.Bar.frame then BL.Bar:MarkDirty() end end)
BL.On("CATEGORY_COLOR_CHANGED", function() if BL.Bar.frame then BL.Bar:Restyle() end end)
BL.On("OVERRIDES_CHANGED", function() if BL.Bar.frame then BL.Bar:MarkDirty() end end)
BL.On("SPELLS_CHANGED", function() if BL.Bar.frame then BL.Bar:MarkDirty() end end)
BL.On("AURAS_CHANGED", function()
    if BL.Bar.frame then BL.Bar:SetPreviewActive(BL.Preview.Active()) end
end)
BL.On("SETTINGS_CHANGED", function(key, scope)
    local bar = (scope == "debuff") and BL.DebuffBar or BL.Bar
    if not (bar and bar.frame) then return end
    if key == "locked" then bar:ApplyLock()
    elseif key == "scale" then bar:ApplyScale()
    elseif key == "showBackground" then bar:ApplyBackground()
    elseif key == "point" then bar:ApplyPosition()
    elseif key == "hideBlizzardFrames" then BL.Bar.ApplyBlizzardHiding()
    elseif key == "minimapButton" or key == "minimapAngle" then return
    else
        bar:ApplyFlow()
        bar:ApplyLock()
        bar:MarkDirty()
    end
end)
