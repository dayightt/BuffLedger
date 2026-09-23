-- Widgets: the icon button both bars use, plus small helpers around the
-- client's own templates (popups, menus, swatches, checkboxes).

local _, BL = ...

local Widgets = {}
BL.Widgets = Widgets
BL.UI = BL.UI or {}

Widgets.QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
Widgets.WHITE = "Interface\\Buttons\\WHITE8X8"
Widgets.TEMP_ENCHANT_BORDER = "Interface\\Buttons\\UI-TempEnchant-Border"

-- Client thresholds for the duration text colour and the icon pulse.
Widgets.DURATION_WARNING = 60
Widgets.PULSE_WARNING = 31

local DEBUFF_BORDER_ATLAS = {
    Magic = "ui-debuff-border-magic-icon",
    Curse = "ui-debuff-border-curse-icon",
    Disease = "ui-debuff-border-disease-icon",
    Poison = "ui-debuff-border-poison-icon",
    Bleed = "ui-debuff-border-bleed-icon",
}
local DEBUFF_BORDER_DEFAULT = "ui-debuff-border-default-noicon"

local function atlasExists(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- ---------------------------------------------------------------------
-- Icon button
-- ---------------------------------------------------------------------

local IconButtonMixin = {}

function IconButtonMixin:SetIconSize(size)
    self.iconSize = size
    self:SetSize(size, size)
    self:ApplyInset()
end

function IconButtonMixin:SetBorderThickness(px)
    self.borderThickness = px
    self:SetBackdrop({ edgeFile = Widgets.WHITE, edgeSize = px })
    if self.borderColor then
        self:SetBackdropBorderColor(self.borderColor[1], self.borderColor[2], self.borderColor[3], 1)
    end
    self:ApplyInset()
end

function IconButtonMixin:ApplyInset()
    local px = self.borderThickness or 1
    self.Icon:ClearAllPoints()
    self.Icon:SetPoint("TOPLEFT", px, -px)
    self.Icon:SetPoint("BOTTOMRIGHT", -px, px)
    self.Cooldown:ClearAllPoints()
    self.Cooldown:SetPoint("TOPLEFT", px, -px)
    self.Cooldown:SetPoint("BOTTOMRIGHT", -px, px)
end

function IconButtonMixin:SetBorderColor(r, g, b)
    self.borderColor = { r, g, b }
    self:SetBackdropBorderColor(r, g, b, 1)
end

function IconButtonMixin:SetDurationInside(inside)
    self.Duration:ClearAllPoints()
    if inside then
        self.Duration:SetPoint("CENTER", self, "CENTER", 0, 0)
    else
        self.Duration:SetPoint("TOP", self, "BOTTOM", 0, -1)
    end
end

-- Overlay the client's own dispel-type border (with its corner badge) for
-- debuffs, or the temp-enchant ring for weapons; hide both for buffs.
function IconButtonMixin:SetOverlay(kind, dispelName)
    self.DebuffBorder:Hide()
    self.TempEnchantBorder:Hide()
    if kind == "debuff" then
        local atlas = DEBUFF_BORDER_ATLAS[dispelName] or DEBUFF_BORDER_DEFAULT
        if atlasExists(atlas) then
            self.DebuffBorder:SetAtlas(atlas, false)
            self.DebuffBorder:Show()
        end
    elseif kind == "weapon" then
        self.TempEnchantBorder:Show()
    end
end

function IconButtonMixin:SetTimeLeft(seconds, timed)
    if not timed then
        self.Duration:SetText("")
        self:SetAlpha(1)
        return
    end
    seconds = seconds or 0
    self.Duration:SetText(BL.FormatTime(seconds))
    local color = (seconds < Widgets.DURATION_WARNING) and HIGHLIGHT_FONT_COLOR or NORMAL_FONT_COLOR
    if color then self.Duration:SetTextColor(color.r, color.g, color.b) end
    if seconds < Widgets.PULSE_WARNING and seconds > 0 then
        -- Same pulse as the stock frame: alpha bounces between 0.3 and 1.
        local t = BL.Clock() % 1.5
        local phase = t < 0.75 and (t / 0.75) or (1 - (t - 0.75) / 0.75)
        self:SetAlpha(0.3 + 0.7 * phase)
    else
        self:SetAlpha(1)
    end
end

-- When the client hides the expiration from us, its own Cooldown widget
-- can still draw the swipe from the secret values.
function IconButtonMixin:SetSecretTimer(expiration, duration)
    local cd = self.Cooldown
    if expiration ~= nil and cd.SetCooldownFromExpirationTime then
        cd:SetDrawSwipe(true)
        local ok = pcall(cd.SetCooldownFromExpirationTime, cd, expiration, duration)
        if not ok then cd:SetDrawSwipe(false); cd:Clear() end
    else
        cd:SetDrawSwipe(false)
        cd:Clear()
    end
end

function IconButtonMixin:SetCount(n)
    if n and n > 1 then
        self.Count:SetText(n)
        self.Count:Show()
    else
        self.Count:Hide()
    end
end

-- Secure so a right-click can cancel a buff through the client's own
-- "cancelaura" action; attributes are set by the bar out of combat.
function Widgets.CreateIconButton(parent, secure)
    local template = secure and "SecureActionButtonTemplate,BackdropTemplate" or "BackdropTemplate"
    local button = CreateFrame("Button", nil, parent, template)
    Mixin(button, IconButtonMixin)

    button.Icon = button:CreateTexture(nil, "BACKGROUND")
    button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.Cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.Cooldown:SetHideCountdownNumbers(true)
    button.Cooldown:SetDrawSwipe(false)
    button.Cooldown:SetDrawEdge(false)
    button.Cooldown:SetDrawBling(false)
    if button.Cooldown.SetUseAuraDisplayTime then button.Cooldown:SetUseAuraDisplayTime(true) end

    -- Fonts and anchors mirror the stock aura button.
    button.Count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.Count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    button.Count:Hide()

    button.Duration = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.Duration:SetJustifyH("CENTER")

    button.DebuffBorder = button:CreateTexture(nil, "OVERLAY", nil, 1)
    button.DebuffBorder:SetPoint("CENTER", button.Icon, "CENTER")
    button.DebuffBorder:Hide()

    button.TempEnchantBorder = button:CreateTexture(nil, "OVERLAY", nil, 1)
    button.TempEnchantBorder:SetTexture(Widgets.TEMP_ENCHANT_BORDER)
    button.TempEnchantBorder:SetPoint("CENTER", button.Icon, "CENTER")
    button.TempEnchantBorder:Hide()

    button:SetBorderThickness(1)
    button:SetIconSize(30)
    button:SetDurationInside(false)
    button:SetBorderColor(0.65, 0.65, 0.65)
    return button
end

-- Keeps the overlay rings proportional to the icon (stock: 40 over 30, 32 over 30).
function Widgets.ScaleOverlays(button, size)
    button.DebuffBorder:SetSize(size * 40 / 30, size * 40 / 30)
    button.TempEnchantBorder:SetSize(size * 32 / 30, size * 32 / 30)
end

-- ---------------------------------------------------------------------
-- Popups and menus
-- ---------------------------------------------------------------------

function Widgets.Confirm(id, text, onAccept)
    local which = "BUFFLEDGER_" .. id
    if not StaticPopupDialogs[which] then
        StaticPopupDialogs[which] = {
            text = "%s",
            button1 = YES or "Yes",
            button2 = NO or "No",
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnAccept = function(self, data)
                if data and data.onAccept then data.onAccept() end
            end,
        }
    end
    StaticPopup_Show(which, text, nil, { onAccept = onAccept })
end

-- Popup with a text box. The edit box belongs to the client's popup, so
-- nothing here creates an EditBox at load.
function Widgets.Prompt(id, text, onAccept, initial)
    local which = "BUFFLEDGER_PROMPT_" .. id
    if not StaticPopupDialogs[which] then
        StaticPopupDialogs[which] = {
            text = "%s",
            button1 = ACCEPT or "Accept",
            button2 = CANCEL or "Cancel",
            hasEditBox = true,
            editBoxWidth = 260,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnShow = function(self, data)
                local box = self.editBox or self.EditBox
                if box then
                    box:SetText(data and data.initial or "")
                    box:HighlightText()
                    box:SetFocus()
                end
            end,
            OnAccept = function(self, data)
                local box = self.editBox or self.EditBox
                local value = box and strtrim(box:GetText() or "") or ""
                if value ~= "" and data and data.onAccept then data.onAccept(value) end
            end,
            EditBoxOnEnterPressed = function(box)
                local parent = box:GetParent()
                local value = strtrim(box:GetText() or "")
                if value ~= "" and parent.data and parent.data.onAccept then parent.data.onAccept(value) end
                parent:Hide()
            end,
            EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
        }
    end
    StaticPopup_Show(which, text, nil, { onAccept = onAccept, initial = initial })
end

local function colorText(color, text)
    return string.format("|cff%02x%02x%02x%s|r", color[1] * 255, color[2] * 255, color[3] * 255, text)
end
Widgets.ColorText = colorText

-- Menu of every category, coloured, with the current one marked.
function Widgets.CategoryMenu(owner, currentId, onPick, title)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        if title then root:CreateTitle(title) end
        for _, id in ipairs(BL.Categories.Order()) do
            local cat = BL.Categories.Get(id)
            if cat then
                local label = colorText(cat.color, cat.name)
                if root.CreateRadio then
                    root:CreateRadio(label, function() return currentId == id end, function() onPick(id) end)
                else
                    root:CreateButton(label, function() onPick(id) end)
                end
            end
        end
    end)
end

function Widgets.ContextMenu(owner, title, entries)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, function(_, root)
            if title then root:CreateTitle(title) end
            for _, entry in ipairs(entries) do
                root:CreateButton(entry.text, entry.func)
            end
        end)
        return
    end
    if entries[1] then entries[1].func() end
end

-- ---------------------------------------------------------------------
-- Small controls for the Categories page
-- ---------------------------------------------------------------------

function Widgets.CreateButton(parent, text, width, height, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 80, height or 22)
    button:SetText(text)
    if onClick then button:SetScript("OnClick", onClick) end
    return button
end

function Widgets.CreateLabel(parent, template, text, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if text then fs:SetText(text) end
    if justify then fs:SetJustifyH(justify) end
    return fs
end

function Widgets.CreateCheckbox(parent, label, tooltip, onChanged)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    local text = check.Text or check.text
    if not text then
        text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", check, "RIGHT", 2, 0)
    end
    text:SetText(label)
    check.Label = text
    check.tooltipText = tooltip
    check:SetScript("OnClick", function(self)
        if onChanged then onChanged(self:GetChecked() and true or false) end
    end)
    check:SetScript("OnEnter", function(self)
        if not self.tooltipText then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, 1, 1, 1)
        GameTooltip:AddLine(self.tooltipText, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return check
end

-- Opens the client's colour picker. onChange({r,g,b}, done) is called
-- with done = false for every live movement and once with done = true
-- when the picker closes (accepted or cancelled), so callers can keep the
-- live path cheap and do the expensive work once.
local pickerCommit
function Widgets.OpenColorPicker(start, onChange)
    local previous = { start[1], start[2], start[3] }
    local function current()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        return { r, g, b }
    end
    if not Widgets.pickerHooked then
        Widgets.pickerHooked = true
        ColorPickerFrame:HookScript("OnHide", function()
            local commit = pickerCommit
            pickerCommit = nil
            if commit then commit() end
        end)
    end
    pickerCommit = function() onChange(current(), true) end
    local info = {
        r = start[1], g = start[2], b = start[3],
        hasOpacity = false,
        swatchFunc = function() onChange(current(), false) end,
        cancelFunc = function()
            pickerCommit = nil
            onChange(previous, true)
        end,
    }
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow(info)
    else
        ColorPickerFrame.func = info.swatchFunc
        ColorPickerFrame.cancelFunc = info.cancelFunc
        ColorPickerFrame:SetColorRGB(info.r, info.g, info.b)
        ColorPickerFrame:Show()
    end
end

-- Small square that shows a colour and opens the picker with live preview.
-- getColor() -> {r,g,b}; onChange({r,g,b}, done) as for OpenColorPicker.
function Widgets.CreateColorSwatch(parent, getColor, onChange, size)
    size = size or 18
    local swatch = CreateFrame("Button", nil, parent, "BackdropTemplate")
    swatch:SetSize(size, size)
    swatch:SetBackdrop({ bgFile = Widgets.WHITE, edgeFile = Widgets.WHITE, edgeSize = 1 })
    swatch:SetBackdropBorderColor(0, 0, 0, 1)
    function swatch:Refresh()
        local c = getColor()
        self:SetBackdropColor(c[1], c[2], c[3], 1)
    end
    swatch:SetScript("OnClick", function(self)
        Widgets.OpenColorPicker(getColor(), function(color, done)
            onChange(color, done)
            self:Refresh()
        end)
    end)
    swatch:Refresh()
    return swatch
end
