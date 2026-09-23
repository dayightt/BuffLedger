-- Minimap: the addon-compartment entry (always) and an optional classic
-- button around the minimap ring.

local _, BL = ...

local UI = BL.UI

local button
local ICON = "Interface\\Icons\\Spell_Holy_WordFortitude"

local function settings() return BL.DB.settings end

function UI.AddSummaryTooltip(tooltip)
    tooltip:SetText("BuffLedger", 1, 1, 1)
    local buffs = BL.Bar and BL.Bar:Counts() or 0
    local debuffs = BL.DebuffBar and BL.DebuffBar:Counts() or 0
    tooltip:AddDoubleLine("Buffs", tostring(buffs), 0.8, 0.8, 0.8, 1, 1, 1)
    tooltip:AddDoubleLine("Debuffs", tostring(debuffs), 0.8, 0.8, 0.8, 1, 1, 1)
    tooltip:AddDoubleLine("Buff bar", settings().locked and "locked" or "unlocked", 0.8, 0.8, 0.8, 1, 1, 1)
    tooltip:AddLine(" ")
    tooltip:AddLine("|cffaaaaaaLeft-click: settings. Right-click: lock/unlock the buff bar.|r")
end

local function toggleLock()
    BL.SetSetting("locked", not settings().locked)
    BL.Print(settings().locked and "Buff bar locked." or "Buff bar unlocked - drag it to move.")
end

local function updatePosition()
    if not button then return end
    local angle = math.rad(settings().minimapAngle or 220)
    local radius = (Minimap:GetWidth() / 2) + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function onDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    settings().minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
    updatePosition()
end

local function createButton()
    button = CreateFrame("Button", "BuffLedgerMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetMovable(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDragUpdate) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then toggleLock() else UI.OpenSettings() end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        UI.AddSummaryTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    updatePosition()
end

function UI.UpdateMinimapButton()
    if settings().minimapButton then
        if not button then createButton() end
        updatePosition()
        button:Show()
    elseif button then
        button:Hide()
    end
end

function BuffLedger_OnCompartmentClick(_, mouseButton)
    if mouseButton == "RightButton" then toggleLock() else UI.OpenSettings() end
end

function BuffLedger_OnCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    UI.AddSummaryTooltip(GameTooltip)
    GameTooltip:Show()
end

function BuffLedger_OnCompartmentLeave()
    GameTooltip:Hide()
end

BL.RegisterEvent("PLAYER_LOGIN", function() UI.UpdateMinimapButton() end)
BL.On("SETTINGS_CHANGED", function(key)
    if key == "minimapButton" then UI.UpdateMinimapButton() end
end)
