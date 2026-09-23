-- Preview: /bl test draws a sample of known buffs with our own buttons,
-- laid out by the same flow algorithm the client uses for the live bar,
-- so the categorised look can be judged without a raid. The live bar is
-- hidden underneath while a preview is showing.

local _, BL = ...

local W = BL.Widgets
local Layout = BL.Layout

local frame
local pool, active = {}, {}
local TIMER_INTERVAL = 0.1

local function acquire(i)
    local b = pool[i]
    if b then return b end
    b = W.CreateIconButton(frame)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", function(self)
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(self.entry.name or "Preview", 1, 1, 1)
        local cat = BL.Categories.Get(BL.Classify.Resolve(self.entry))
        if cat then GameTooltip:AddLine(W.ColorText(cat.color, cat.name)) end
        GameTooltip:AddLine("|cffaaaaaaPreview buff - /bl test off to stop. Shift-click: change category.|r")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if IsShiftKeyDown() and self.entry and self.entry.name then
            local name = self.entry.name
            W.CategoryMenu(self, BL.Classify.Resolve(self.entry), function(id)
                BL.Classify.Assign(name, id, "preview")
            end, name)
        end
    end)
    pool[i] = b
    return b
end

local function ensureFrame()
    if frame then return end
    frame = CreateFrame("Frame", "BuffLedgerPreview", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(1, 1)
    frame.accum = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.accum = self.accum + elapsed
        if self.accum < TIMER_INTERVAL then return end
        self.accum = 0
        local now = BL.Clock()
        for _, b in ipairs(active) do
            local e = b.entry
            if e then b:SetTimeLeft(e.timed and (e.expirationTime - now) or nil, e.timed) end
        end
    end)
    frame:Hide()
end

local function render()
    local entries = BL.Preview.Entries()
    if not entries then
        if frame then frame:Hide() end
        return
    end
    ensureFrame()
    local s = BL.DB.settings
    local size, spacing, thickness = s.iconSize, s.spacing, s.borderThickness or 1
    local textH = s.durationInside and 0 or Layout.DURATION_HEIGHT
    local corner = s.growLeft and "TOPRIGHT" or "TOPLEFT"
    local state = { inGroup = IsInGroup(), inRaid = IsInRaid() }

    -- Same inputs the live bar gives the client.
    local clusters = Layout.ClusterEntries(entries, BL.DB.categories, BL.Categories.Order())
    local byKey, groups = {}, {}
    for _, cluster in ipairs(clusters) do
        local cat = BL.Categories.Get(cluster.categoryId)
        local collapsed = Layout.ConsolidateAllowed(cat, s, state) and #cluster.entries >= 2
        byKey[cluster.categoryId] = { entries = cluster.entries, collapsed = collapsed, color = cat.color }
        groups[#groups + 1] = {
            key = cluster.categoryId, count = collapsed and 1 or #cluster.entries,
            elementWidth = size, elementHeight = size, elementSpacing = spacing,
            lineSpacing = spacing + textH, groupSpacing = s.categoryGap or 0,
        }
    end
    local columns = math.max(1, math.floor(tonumber(s.columns) or 1))
    local flow = Layout.Flow(groups, {
        anchorPoint = corner, horizontal = s.growLeft and Layout.LEFT or Layout.RIGHT, vertical = Layout.DOWN,
        maximumLineSize = columns * (size + spacing),
    })

    frame:ClearAllPoints()
    local anchor = BL.Bar and BL.Bar.holder or UIParent
    frame:SetPoint(corner, anchor, corner, 0, 0)
    frame:SetScale(tonumber(s.scale) or 1)
    frame:SetSize(math.max(flow.width, size), math.max(flow.height, size))

    active = {}
    for i, e in ipairs(flow.elements) do
        local group = byKey[e.key]
        local entry = group.entries[e.index]
        local b = acquire(i)
        b.entry = entry
        b:SetIconSize(size)
        b:SetBorderThickness(thickness)
        b:SetDurationInside(s.durationInside)
        b:SetBorderColor(group.color[1], group.color[2], group.color[3])
        W.ScaleOverlays(b, size)
        b:SetOverlay("buff")
        b.Icon:SetTexture(entry.icon or W.QUESTION_ICON)
        if group.collapsed then
            b.Count:SetText(#group.entries)
            b.Count:Show()
        else
            b:SetCount(entry.applications)
        end
        b:ClearAllPoints()
        b:SetPoint(corner, frame, corner, e.x, e.y)
        b:Show()
        active[#active + 1] = b
    end
    for i = #flow.elements + 1, #pool do pool[i]:Hide() end
    frame:Show()
end

BL.On("AURAS_CHANGED", render)
BL.On("CATEGORIES_CHANGED", function() if BL.Preview.Active() then render() end end)
BL.On("CATEGORY_COLOR_CHANGED", function() if BL.Preview.Active() then render() end end)
BL.On("OVERRIDES_CHANGED", function() if BL.Preview.Active() then render() end end)
BL.On("SETTINGS_CHANGED", function() if BL.Preview.Active() then render() end end)
BL.RegisterEvent("GROUP_ROSTER_UPDATE", function() if BL.Preview.Active() then render() end end)
