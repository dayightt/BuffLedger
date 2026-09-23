-- Settings: Options -> AddOns -> BuffLedger. The parent page and the two
-- bar pages are native vertical layouts (sliders, checkboxes); Categories
-- is a canvas page with the editable category list and the history.

local _, BL = ...

local W = BL.Widgets
local UI = BL.UI

local parentCategory, buffCategory, debuffCategory, categoriesCategory
local registerError
local canvas

local ROW_HEIGHT = 26
local HISTORY_ROW = 22

-- ---------------------------------------------------------------------
-- Native proxy settings
-- ---------------------------------------------------------------------

local function proxy(category, key, scope, kind, label, default, tooltip)
    local variable = "BuffLedger_" .. (scope or "buff") .. "_" .. key
    local setting = Settings.RegisterProxySetting(category, variable, kind, label, default,
        function() return BL.GetSetting(key, scope) end,
        function(value) BL.SetSetting(key, value, scope) end)
    return setting
end

local function checkbox(category, key, scope, label, tooltip)
    local default = BL.DEFAULTS.settings
    if scope == "debuff" then default = default.debuff end
    local setting = proxy(category, key, scope, Settings.VarType.Boolean, label, default[key], tooltip)
    Settings.CreateCheckbox(category, setting, tooltip)
end

local function slider(category, key, scope, label, minV, maxV, step, tooltip, formatter)
    local default = BL.DEFAULTS.settings
    if scope == "debuff" then default = default.debuff end
    local setting = proxy(category, key, scope, Settings.VarType.Number, label, default[key], tooltip)
    local options = Settings.CreateSliderOptions(minV, maxV, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
    Settings.CreateSlider(category, setting, options, tooltip)
end

local function button(category, label, buttonText, onClick, tooltip)
    local initializer = CreateSettingsButtonInitializer(label, buttonText, onClick, tooltip, true)
    local layout = SettingsPanel:GetLayout(category)
    layout:AddInitializer(initializer)
end

local function scaleText(v) return string.format("%.2f", v) end
local function pxText(v) return string.format("%d", v) end

local function buildBarPage(category, scope)
    local isBuff = scope ~= "debuff"
    checkbox(category, "locked", scope, "Lock the bar", "Locked bars can't be dragged. Unlock to move them.")
    slider(category, "iconSize", scope, "Icon size", 16, 64, 1, "Size of each icon in pixels.", pxText)
    slider(category, "spacing", scope, "Spacing", 0, 16, 1, "Gap between icons.", pxText)
    if isBuff then
        slider(category, "categoryGap", scope, "Category gap", 0, 32, 1, "Extra gap between one category's cluster and the next on the same row.", pxText)
    end
    slider(category, "columns", scope, "Icons per row", 1, 40, 1, "Maximum icons on a row before wrapping.", pxText)
    slider(category, "borderThickness", scope, "Border thickness", 1, 3, 1, "Thickness of the coloured edge around each icon.", pxText)
    slider(category, "scale", scope, "Scale", 0.5, 2, 0.05, "Overall scale of the bar.", scaleText)
    checkbox(category, "growLeft", scope, "Grow to the left", "Icons fill from the bar's right edge leftward (the default) instead of left to right.")
    checkbox(category, "showBackground", scope, "Show background", "A dark panel behind the bar, sized to fit.")
    checkbox(category, "durationInside", scope, "Duration inside the icon", "Draw the remaining time over the icon instead of below it.")
    if isBuff then
        checkbox(category, "consolidateOnlyGroup", scope, "Consolidate only in a group", "Categories marked to consolidate only collapse while you are in a party or raid.")
        checkbox(category, "consolidateOnlyRaid", scope, "Consolidate only in a raid", "Categories marked to consolidate only collapse while you are in a raid.")
    end
    button(category, "Position", "Reset Position", function()
        local bar = isBuff and BL.Bar or BL.DebuffBar
        if bar then bar:ResetPosition() end
    end, "Move the bar back to its starting spot.")
end

-- ---------------------------------------------------------------------
-- Lists (ScrollBox, with a ScrollFrame fallback)
-- ---------------------------------------------------------------------

local function createList(parent, rowHeight, initRow)
    local ok, list = pcall(function()
        local scrollBox = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
        scrollBox:SetPoint("TOPLEFT", 4, -4)
        scrollBox:SetPoint("BOTTOMRIGHT", -20, 4)
        local scrollBar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
        scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 2, 0)
        scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 2, 0)
        local view = CreateScrollBoxListLinearView()
        view:SetElementExtent(rowHeight)
        view:SetElementInitializer("Frame", initRow)
        ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
        local obj = { scrollBox = scrollBox }
        function obj:SetElements(elements)
            self.scrollBox:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
        end
        return obj
    end)
    if ok and list then return list end

    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 4)
    local child = CreateFrame("Frame", nil, scrollFrame)
    child:SetSize(1, 1)
    scrollFrame:SetScrollChild(child)
    local pool = {}
    local obj = {}
    function obj:SetElements(elements)
        child:SetWidth(scrollFrame:GetWidth())
        for i, data in ipairs(elements) do
            local row = pool[i]
            if not row then
                row = CreateFrame("Frame", nil, child)
                row:SetHeight(rowHeight)
                pool[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
            row:SetPoint("TOPRIGHT", 0, -(i - 1) * rowHeight)
            initRow(row, data)
            row:Show()
        end
        for i = #elements + 1, #pool do pool[i]:Hide() end
        child:SetHeight(math.max(#elements * rowHeight, 1))
    end
    return obj
end

-- ---------------------------------------------------------------------
-- Categories canvas
-- ---------------------------------------------------------------------

local function initCategoryRow(row, data)
    local id = data.id
    local cat = BL.Categories.Get(id)
    if not cat then return end
    if not row.built then
        row.built = true
        row.swatch = W.CreateColorSwatch(row, function()
                local c = BL.Categories.Get(row.id)
                return c and c.color or { 1, 1, 1 }
            end,
            function(color, done) if row.id then BL.Categories.SetColor(row.id, color, not done) end end)
        row.swatch:SetPoint("LEFT", 6, 0)

        row.nameButton = CreateFrame("Button", nil, row)
        row.nameButton:SetPoint("LEFT", row.swatch, "RIGHT", 8, 0)
        row.nameButton:SetSize(200, ROW_HEIGHT - 4)
        row.name = row.nameButton:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT")
        row.name:SetJustifyH("LEFT")
        local hl = row.nameButton:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        row.nameButton:SetScript("OnClick", function()
            local current = BL.Categories.Get(row.id)
            W.Prompt("RENAME", "Rename " .. (current and current.name or "category") .. ":", function(text)
                BL.Categories.Rename(row.id, text)
            end, current and current.name)
        end)
        row.nameButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Click to rename", 1, 1, 1)
            GameTooltip:Show()
        end)
        row.nameButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Right-hand controls in fixed columns, right to left.
        row.delete = W.CreateButton(row, "Delete", 64, 20, function()
            local current = BL.Categories.Get(row.id)
            W.Confirm("DELETE_CATEGORY", "Delete " .. (current and current.name or "this category") .. "? Buffs assigned to it will show under Other.", function()
                BL.Categories.Delete(row.id)
            end)
        end)
        row.delete:SetPoint("RIGHT", -8, 0)
        row.down = W.CreateButton(row, "Down", 56, 20, function() BL.Categories.Move(row.id, 1) end)
        row.down:SetPoint("RIGHT", row.delete, "LEFT", -4, 0)
        row.up = W.CreateButton(row, "Up", 48, 20, function() BL.Categories.Move(row.id, -1) end)
        row.up:SetPoint("RIGHT", row.down, "LEFT", -4, 0)

        row.hidden = W.CreateCheckbox(row, "Hide", "Hide this category from the bar entirely.", function(checked)
            BL.Categories.SetHidden(row.id, checked)
        end)
        row.hidden:SetPoint("RIGHT", row.up, "LEFT", -56, 0)
        row.consolidate = W.CreateCheckbox(row, "Consolidate", "Collapse this category into one icon whenever it holds two or more buffs (hover to see them all).", function(checked)
            BL.Categories.SetConsolidate(row.id, checked)
        end)
        row.consolidate:SetPoint("RIGHT", row.hidden, "LEFT", -96, 0)
    end
    row.id = id
    row.swatch:Refresh()
    row.name:SetText(cat.name .. (cat.builtin and "" or "  |cff888888(custom)|r"))
    row.hidden:SetChecked(cat.hidden)
    row.consolidate:SetChecked(cat.consolidate)
    local order = BL.Categories.Order()
    local isOther = id == "other"
    row.delete:SetEnabled(cat.deletable ~= false and not isOther)
    row.up:SetEnabled(not isOther and order[1] ~= id)
    row.down:SetEnabled(not isOther and order[#order - 1] ~= id)
    row.hidden:SetEnabled(not isOther)
end

local function initHistoryRow(row, data)
    if not row.built then
        row.built = true
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetPoint("RIGHT", -8, 0)
        row.text:SetJustifyH("LEFT")
        row:EnableMouse(true)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        row:SetScript("OnMouseUp", function(self, mouseButton)
            if mouseButton == "RightButton" and self.buffName then
                W.CategoryMenu(self, BL.Classify.GetOverride(self.buffName), function(id)
                    BL.Classify.Assign(self.buffName, id, "history")
                end, self.buffName)
            end
        end)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.buffName or "", 1, 1, 1)
            GameTooltip:AddLine("Right-click to move this buff again.", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local entry = data.entry
    row.buffName = entry.buffName
    local function catName(id)
        local c = BL.Categories.Get(id)
        return c and W.ColorText(c.color, c.name) or ("|cff888888" .. tostring(id) .. "|r")
    end
    local when = entry.time and date("%b %d %H:%M", entry.time) or ""
    row.text:SetText(string.format("%s: %s -> %s  |cff888888%s|r", entry.buffName, catName(entry.from), catName(entry.to), when))
end

local function refreshCanvas()
    if not canvas then return end
    local elements = {}
    for _, id in ipairs(BL.Categories.Order()) do elements[#elements + 1] = { id = id } end
    canvas.categoryList:SetElements(elements)
    canvas.consolidateAll:SetText(BL.Categories.AllConsolidated() and "Consolidate None" or "Consolidate All")
    local history = {}
    for _, entry in ipairs(BL.Classify.History()) do history[#history + 1] = { entry = entry } end
    canvas.historyList:SetElements(history)
    canvas.historyEmpty:SetShown(#history == 0)
    canvas.clearHistory:SetEnabled(#history > 0)
end
UI.RefreshCategories = refreshCanvas

local function buildCanvas()
    canvas = CreateFrame("Frame")
    canvas:SetSize(640, 560)

    local title = W.CreateLabel(canvas, "GameFontNormalLarge", "Categories", "LEFT")
    title:SetPoint("TOPLEFT", 16, -16)
    local desc = W.CreateLabel(canvas, "GameFontHighlightSmall",
        "Click a name to rename it, the swatch to recolour, Up/Down to reorder. Shift-click any buff on the bar (left or right) to move it to another category; a plain right-click cancels it.", "LEFT")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetPoint("RIGHT", canvas, "RIGHT", -16, 0)
    desc:SetWordWrap(true)

    local newButton = W.CreateButton(canvas, "New Category", 120, 22, function()
        W.Prompt("NEW_CATEGORY", "Name for the new category:", function(text)
            local id = BL.Categories.Create(text, { 0.8, 0.8, 0.8 })
            refreshCanvas()
            local cat = BL.Categories.Get(id)
            if cat and ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
                W.OpenColorPicker(cat.color, function(color, done) BL.Categories.SetColor(id, color, not done) end)
            end
        end)
    end)
    newButton:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -10)
    canvas.consolidateAll = W.CreateButton(canvas, "Consolidate All", 130, 22, function()
        BL.Categories.SetConsolidateAll(not BL.Categories.AllConsolidated())
    end)
    local resetButton = W.CreateButton(canvas, "Reset to Default", 130, 22, function()
        W.Confirm("RESET_CATEGORIES", "Restore any missing default categories in their original order? Custom categories and your reassignments are kept.", function()
            BL.Categories.ResetToDefault()
        end)
    end)
    resetButton:SetPoint("LEFT", newButton, "RIGHT", 6, 0)
    canvas.consolidateAll:SetPoint("LEFT", resetButton, "RIGHT", 6, 0)

    local inset = CreateFrame("Frame", nil, canvas, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", newButton, "BOTTOMLEFT", 0, -8)
    inset:SetPoint("RIGHT", canvas, "RIGHT", -16, 0)
    inset:SetHeight(ROW_HEIGHT * 8 + 8)
    canvas.categoryList = createList(inset, ROW_HEIGHT, initCategoryRow)

    -- Assign a buff by name.
    local assignTitle = W.CreateLabel(canvas, "GameFontNormal", "Assign a buff", "LEFT")
    assignTitle:SetPoint("TOPLEFT", inset, "BOTTOMLEFT", 0, -12)
    local assignDesc = W.CreateLabel(canvas, "GameFontHighlightSmall", "Type a buff's exact name and pick where it belongs.", "LEFT")
    assignDesc:SetPoint("TOPLEFT", assignTitle, "BOTTOMLEFT", 0, -2)

    -- The edit box is created on first show: an EditBox made at load time
    -- grabs keyboard focus on this client.
    local assignButton = W.CreateButton(canvas, "Assign to...", 110, 22)
    assignButton:SetPoint("TOPLEFT", assignDesc, "BOTTOMLEFT", 254, -6)
    canvas.EnsureAssignBox = function()
        if canvas.assignBox then return end
        local box = CreateFrame("EditBox", nil, canvas, "InputBoxTemplate")
        box:SetAutoFocus(false)
        box:SetSize(240, 22)
        box:SetPoint("TOPLEFT", assignDesc, "BOTTOMLEFT", 6, -6)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEnterPressed", function() assignButton:Click() end)
        canvas.assignBox = box
    end
    assignButton:SetScript("OnClick", function(self)
        local box = canvas.assignBox
        local name = box and strtrim(box:GetText() or "") or ""
        if name == "" then return end
        W.CategoryMenu(self, BL.Classify.GetOverride(name), function(id)
            BL.Classify.Assign(name, id, "settings")
            box:SetText("")
            box:ClearFocus()
        end, name)
    end)

    -- History.
    local historyTitle = W.CreateLabel(canvas, "GameFontNormal", "Assignment history", "LEFT")
    historyTitle:SetPoint("TOPLEFT", assignDesc, "BOTTOMLEFT", 0, -36)
    canvas.clearHistory = W.CreateButton(canvas, "Clear History", 110, 22, function()
        W.Confirm("CLEAR_HISTORY", "Clear the assignment history? Your assignments themselves are kept.", function()
            BL.Classify.ClearHistory()
        end)
    end)
    canvas.clearHistory:SetPoint("BOTTOMRIGHT", -16, 16)

    local historyInset = CreateFrame("Frame", nil, canvas, "InsetFrameTemplate")
    historyInset:SetPoint("TOPLEFT", historyTitle, "BOTTOMLEFT", 0, -6)
    historyInset:SetPoint("RIGHT", canvas, "RIGHT", -16, 0)
    historyInset:SetPoint("BOTTOM", canvas.clearHistory, "TOP", 0, 8)
    canvas.historyList = createList(historyInset, HISTORY_ROW, initHistoryRow)
    canvas.historyEmpty = W.CreateLabel(historyInset, "GameFontDisable", "No reassignments yet.", "CENTER")
    canvas.historyEmpty:SetPoint("TOP", 0, -12)

    canvas:SetScript("OnShow", function()
        canvas.EnsureAssignBox()
        refreshCanvas()
    end)
end

-- ---------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------

local function register()
    if parentCategory then return true end
    if not (Settings and Settings.RegisterVerticalLayoutCategory) then
        registerError = "Settings API missing"
        return false
    end
    local ok, err = pcall(function()
        parentCategory = Settings.RegisterVerticalLayoutCategory("BuffLedger")
        checkbox(parentCategory, "hideBlizzardFrames", nil, "Hide the default buff and debuff frames",
            "BuffLedger replaces them. Untick to keep the default frames visible as well.")
        checkbox(parentCategory, "minimapButton", nil, "Minimap button",
            "The addon is always in the minimap's addon menu; this adds a classic button around the minimap too.")
        button(parentCategory, "Preview", "Show sample buffs", function() BL.Preview.Set(BL.Preview.Active() and nil or 0.4) end,
            "Fill the bar with a sample of every buff BuffLedger knows about. Click again (or /bl test off) to stop.")

        buffCategory = Settings.RegisterVerticalLayoutSubcategory(parentCategory, "Buff Bar")
        buildBarPage(buffCategory, "buff")
        debuffCategory = Settings.RegisterVerticalLayoutSubcategory(parentCategory, "Debuff Bar")
        buildBarPage(debuffCategory, "debuff")

        buildCanvas()
        categoriesCategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, canvas, "Categories")

        Settings.RegisterAddOnCategory(parentCategory)
    end)
    if not ok then
        registerError = tostring(err)
        parentCategory = nil
        BL.Print("Settings panel could not be registered: " .. registerError)
        return false
    end
    return true
end

function UI.OpenSettings(page)
    if not register() then return end
    local target = parentCategory
    if page == "categories" and categoriesCategory then target = categoriesCategory
    elseif page == "buff" and buffCategory then target = buffCategory
    elseif page == "debuff" and debuffCategory then target = debuffCategory end
    local id = target.GetID and target:GetID() or target.ID or target
    local ok, err = pcall(Settings.OpenToCategory, id)
    if not ok then BL.Print("Could not open settings: " .. tostring(err)) end
end

function UI.SettingsStatus()
    return parentCategory and "registered" or ("not registered: " .. tostring(registerError))
end

BL.On("DB_READY", function() register() end)
BL.On("CATEGORIES_CHANGED", function() if canvas and canvas:IsShown() then refreshCanvas() end end)
BL.On("OVERRIDES_CHANGED", function() if canvas and canvas:IsShown() then refreshCanvas() end end)
