local ADDON_NAME = ...
local RB = {}
_G.ReagentBankUI = RB

RB.PREFIX = "RBANK"
RB.COLUMNS = 19
RB.ROWS = 11
RB.PAGE_SIZE = RB.COLUMNS * RB.ROWS
RB.SLOT_SIZE = 32
RB.SLOT_SPACING_X = 2
RB.SLOT_SPACING_Y = 2
RB.CATEGORY_ICON_SIZE = 21 --підігнати висоту колонки категорій
RB.CATEGORY_BUTTON_PADDING_X = 5
RB.CATEGORY_BUTTON_PADDING_Y = 4
RB.TAB_GAP = 1
RB.BANKER_NPC_ENTRY = 290011
RB.SEARCH_HEIGHT = 30
RB.BOTTOM_BAR_HEIGHT = 28
RB.STATUS_HEIGHT = 0
RB.OUTER_PAD = 10
RB.SLOT_PAD_X = 10
RB.SLOT_PAD_Y = 10
RB.SIDE_PANEL_INNER_PAD = 4

RB.categories = {
    { id = 5,  name = "Тканина",               icon = "Interface\\Icons\\INV_Fabric_Linen_01" },
    { id = 8,  name = "М'ясо",                 icon = "Interface\\Icons\\INV_Misc_Food_14" },
    { id = 7,  name = "Метал і Каміння",       icon = "Interface\\Icons\\INV_Ore_Copper_01" },
    { id = 12, name = "Зачарування",           icon = "Interface\\Icons\\INV_Enchant_DustDream" },
    { id = 10, name = "Стихії",                icon = "Interface\\Icons\\INV_Elemental_Mote_Fire01" },
    { id = 1,  name = "Деталі",                icon = "Interface\\Icons\\INV_Gizmo_BronzeFramework_01" },
    { id = 11, name = "Інші товари",           icon = "Interface\\Icons\\INV_Misc_Gear_01" },
    { id = 9,  name = "Трави",                 icon = "Interface\\Icons\\INV_Misc_Herb_19" },
    { id = 6,  name = "Шкіра",                 icon = "Interface\\Icons\\INV_Misc_LeatherScrap_03" },
    { id = 4,  name = "Ювелірна справа",       icon = "Interface\\Icons\\INV_Misc_Gem_01" },
    { id = 2,  name = "Вибухівка",             icon = "Interface\\Icons\\INV_Misc_Bomb_05" },
    { id = 3, name = "Пристрої",              icon = "Interface\\Icons\\INV_Gizmo_08" },
    { id = 13, name = "Матеріали Пустки",      icon = "Interface\\Icons\\INV_Enchant_VoidCrystal" },
    { id = 14, name = "Веллум для броні",      iconItemID = 38682, fallbackIcon = "Interface\\Icons\\INV_Misc_Note_01" },
    { id = 15, name = "Веллум для зброї",      iconItemID = 39349, fallbackIcon = "Interface\\Icons\\INV_Misc_Note_01" },
}

RB.state = {
    currentCategory = 5,
    lastCategory = 5,
    currentPage = 1,
    totalPages = 1,
    isSearchMode = false,
    searchQuery = "",
    statusText = "ПКМ по предмету в сховищі — зняти 1 стак. Перетягніть предмет із сумки у вікно банку, щоб вкласти його.",
    pageCache = {},
    demoMode = false,
    pendingOpen = false,
    registered = false,
}

RB.DEBUG = false

RB.dragState = nil
RB.dragVisual = nil
RB.pendingBagDrag = nil
RB.pendingDepositCategory = nil
RB.pendingDepositItemID = nil
RB.pendingDepositTargetSlotIndex = nil
RB.pendingDepositPage = nil


local function wipeTable(tbl)
    if not tbl then
        return
    end

    for k in pairs(tbl) do
        tbl[k] = nil
    end
end

local function split(str, sep)
    local result = {}
    if not str or str == "" then
        return result
    end

    sep = sep or "|"
    local pattern = string.format("([^%s]+)", sep)
    for value in string.gmatch(str, pattern) do
        table.insert(result, value)
    end
    return result
end

local function trim(str)
    if not str then
        return ""
    end
    return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

local BAG_DRAG_CATEGORY_BY_SUBCLASS = {
    ["Cloth"] = 5,
    ["Ткань"] = 5,
    ["Тканина"] = 5,
    ["Meat"] = 8,
    ["Мясо"] = 8,
    ["М'ясо"] = 8,
    ["Metal & Stone"] = 7,
    ["Metal and Stone"] = 7,
    ["Металл и камень"] = 7,
    ["Метал і Каміння"] = 7,
    ["Enchanting"] = 12,
    ["Наложение чар"] = 12,
    ["Зачарування"] = 12,
    ["Elemental"] = 10,
    ["Стихии"] = 10,
    ["Стихії"] = 10,
    ["Parts"] = 1,
    ["Детали"] = 1,
    ["Деталі"] = 1,
    ["Other"] = 11,
    ["Разное"] = 11,
    ["Інші товари"] = 11,
    ["Herb"] = 9,
    ["Трава"] = 9,
    ["Трави"] = 9,
    ["Leather"] = 6,
    ["Кожа"] = 6,
    ["Шкіра"] = 6,
    ["Jewelcrafting"] = 4,
    ["Ювелирное дело"] = 4,
    ["Ювелірна справа"] = 4,
    ["Explosives"] = 2,
    ["Взрывчатка"] = 2,
    ["Вибухівка"] = 2,
    ["Devices"] = 3,
    ["Устройства"] = 3,
    ["Пристрої"] = 3,
}


local function shallowItemCopy(item)
    if not item then
        return nil
    end

    return {
        itemID = item.itemID,
        count = item.count,
    }
end

local function getCursorItemID()
    if not GetCursorInfo then
        return nil
    end

    local cursorType, itemID = GetCursorInfo()
    if cursorType == "item" then
        return tonumber(itemID)
    end

    return nil
end

local function itemEquals(a, b)
    if a == nil and b == nil then
        return true
    end

    if a == nil or b == nil then
        return false
    end

    return a.itemID == b.itemID and a.count == b.count
end

local function getVisibleCategoryForRefresh()
    if RB.state.currentCategory and RB.state.currentCategory > 0 then
        return RB.state.currentCategory
    end

    if RB.state.lastCategory and RB.state.lastCategory > 0 then
        return RB.state.lastCategory
    end

    return RB.categories[1].id
end


local function getCategoryById(categoryId)
    for _, category in ipairs(RB.categories) do
        if category.id == categoryId then
            return category
        end
    end
    return RB.categories[1]
end

local function ensurePageBucket(categoryId)
    if not RB.state.pageCache[categoryId] then
        RB.state.pageCache[categoryId] = {
            totalPages = 1,
            pages = {},
        }
    end
    return RB.state.pageCache[categoryId]
end

local function getLayoutKey(categoryId, page)
    return tostring(categoryId) .. ":" .. tostring(page or 1)
end

function RB:EnsureDatabase()
    if not ReagentBankUI_DB then
        ReagentBankUI_DB = {}
    end

    ReagentBankUI_DB.layout = ReagentBankUI_DB.layout or {}
    ReagentBankUI_DB.categoryOrder = ReagentBankUI_DB.categoryOrder or {}
end

function RB:GetLayoutBucket(categoryId, page)
    self:EnsureDatabase()

    local key = getLayoutKey(categoryId, page)
    if not ReagentBankUI_DB.layout[key] then
        ReagentBankUI_DB.layout[key] = {}
    end

    return ReagentBankUI_DB.layout[key]
end

function RB:ClearMissingLayoutEntries(categoryId, page, rawItems)
    if self.state.isSearchMode or not categoryId or categoryId <= 0 then
        return
    end

    if not rawItems or #rawItems == 0 then
        return
    end

    local bucket = self:GetLayoutBucket(categoryId, page)
    local present = {}

    for _, item in ipairs(rawItems or {}) do
        if item and item.itemID then
            present[item.itemID] = true
        end
    end

    for slotIndex, itemID in pairs(bucket) do
        if not present[itemID] then
            bucket[slotIndex] = nil
        end
    end
end

function RB:SaveDisplayedLayout(categoryId, page, displayedItems)
    if self.state.isSearchMode or not categoryId or categoryId <= 0 then
        return
    end

    local bucket = self:GetLayoutBucket(categoryId, page)
    wipeTable(bucket)

    for slotIndex = 1, self.PAGE_SIZE do
        local item = displayedItems[slotIndex]
        if item and item.itemID then
            bucket[slotIndex] = item.itemID
        end
    end
end

function RB:SyncLayoutWithRawItems(categoryId, page, rawItems)
    if self.state.isSearchMode or not categoryId or categoryId <= 0 then
        return
    end

    if not rawItems or #rawItems == 0 then
        return
    end

    self:ClearMissingLayoutEntries(categoryId, page, rawItems)

    local bucket = self:GetLayoutBucket(categoryId, page)
    local used = {}

    for slotIndex = 1, self.PAGE_SIZE do
        local itemID = bucket[slotIndex]
        if itemID then
            used[itemID] = true
        end
    end

    local nextFreeSlot = 1
    for _, item in ipairs(rawItems) do
        if item and item.itemID and not used[item.itemID] then
            while nextFreeSlot <= self.PAGE_SIZE and bucket[nextFreeSlot] do
                nextFreeSlot = nextFreeSlot + 1
            end

            if nextFreeSlot > self.PAGE_SIZE then
                break
            end

            bucket[nextFreeSlot] = item.itemID
            used[item.itemID] = true
            nextFreeSlot = nextFreeSlot + 1
        end
    end

    self:Debug("SyncLayoutWithRawItems: category=" .. tostring(categoryId) .. ", page=" .. tostring(page) .. ", entries=" .. tostring(#rawItems), true)
end

function RB:GetDisplayedItems()
    local rawItems = self:GetCurrentItems()
    if self.state.isSearchMode or not self.state.currentCategory or self.state.currentCategory <= 0 then
        return rawItems
    end

    local categoryId = self.state.currentCategory
    local page = self.state.currentPage or 1
    local bucket = self:GetLayoutBucket(categoryId, page)
    local arranged = {}
    local used = {}
    local byItemID = {}

    for _, item in ipairs(rawItems) do
        if item and item.itemID then
            byItemID[item.itemID] = shallowItemCopy(item)
        end
    end

    for slotIndex = 1, self.PAGE_SIZE do
        local itemID = bucket[slotIndex]
        if itemID and byItemID[itemID] and not used[itemID] then
            arranged[slotIndex] = shallowItemCopy(byItemID[itemID])
            used[itemID] = true
        end
    end

    local nextFreeSlot = 1
    for _, item in ipairs(rawItems) do
        if item and item.itemID and not used[item.itemID] then
            while nextFreeSlot <= self.PAGE_SIZE and arranged[nextFreeSlot] do
                nextFreeSlot = nextFreeSlot + 1
            end

            if nextFreeSlot > self.PAGE_SIZE then
                break
            end

            arranged[nextFreeSlot] = shallowItemCopy(item)
            nextFreeSlot = nextFreeSlot + 1
        end
    end

    return arranged
end

function RB:MoveDisplayedItem(sourceSlotIndex, targetSlotIndex)
    if self.state.isSearchMode or not sourceSlotIndex or not targetSlotIndex or sourceSlotIndex == targetSlotIndex then
        self:Debug("MoveDisplayedItem skipped: source=" .. tostring(sourceSlotIndex) .. ", target=" .. tostring(targetSlotIndex), true)
        return
    end

    local categoryId = self.state.currentCategory
    local page = self.state.currentPage or 1
    local displayedItems = self:GetDisplayedItems()
    local sourceItem = displayedItems[sourceSlotIndex]
    if not sourceItem then
        self:Debug("MoveDisplayedItem skipped: no source item at slot " .. tostring(sourceSlotIndex), true)
        return
    end

    local targetItem = displayedItems[targetSlotIndex]
    displayedItems[sourceSlotIndex] = targetItem and shallowItemCopy(targetItem) or nil
    displayedItems[targetSlotIndex] = shallowItemCopy(sourceItem)

    self:SaveDisplayedLayout(categoryId, page, displayedItems)

    self:Debug(
        "MoveDisplayedItem saved: category=" .. tostring(categoryId)
        .. ", page=" .. tostring(page)
        .. ", sourceSlot=" .. tostring(sourceSlotIndex)
        .. ", targetSlot=" .. tostring(targetSlotIndex)
        .. ", sourceItemID=" .. tostring(sourceItem.itemID)
        .. ", targetItemID=" .. tostring(targetItem and targetItem.itemID or nil),
        true
    )

    self:Render()
end

function RB:NormalizeCategoryOrder()
    self:EnsureDatabase()

    local normalized = {}
    local seen = {}

    for _, categoryId in ipairs(ReagentBankUI_DB.categoryOrder) do
        local category = getCategoryById(categoryId)
        if category and category.id == categoryId and not seen[categoryId] then
            table.insert(normalized, categoryId)
            seen[categoryId] = true
        end
    end

    for _, category in ipairs(self.categories) do
        if not seen[category.id] then
            table.insert(normalized, category.id)
            seen[category.id] = true
        end
    end

    ReagentBankUI_DB.categoryOrder = normalized
    return normalized
end

function RB:GetOrderedCategories()
    local ordered = {}
    local order = self:NormalizeCategoryOrder()

    for _, categoryId in ipairs(order) do
        table.insert(ordered, getCategoryById(categoryId))
    end

    return ordered
end

function RB:MoveCategory(draggedCategoryId, targetCategoryId, insertAfter)
    if not draggedCategoryId or not targetCategoryId or draggedCategoryId == targetCategoryId then
        return
    end

    local order = self:NormalizeCategoryOrder()
    local draggedIndex, targetIndex

    for index, categoryId in ipairs(order) do
        if categoryId == draggedCategoryId then
            draggedIndex = index
        end
        if categoryId == targetCategoryId then
            targetIndex = index
        end
    end

    if not draggedIndex or not targetIndex then
        return
    end

    table.remove(order, draggedIndex)
    if draggedIndex < targetIndex then
        targetIndex = targetIndex - 1
    end

    if insertAfter then
        targetIndex = targetIndex + 1
    end

    if targetIndex < 1 then
        targetIndex = 1
    end
    if targetIndex > (#order + 1) then
        targetIndex = #order + 1
    end

    table.insert(order, targetIndex, draggedCategoryId)
    ReagentBankUI_DB.categoryOrder = order

    self:ApplyCategoryTabLayout()
    self:Render()
end

function RB:BuildCategoryPreviewOrderByIndex(draggedCategoryId, insertIndex)
    local order = self:NormalizeCategoryOrder()
    local preview = {}

    for _, categoryId in ipairs(order) do
        if categoryId ~= draggedCategoryId then
            table.insert(preview, categoryId)
        end
    end

    if insertIndex < 1 then
        insertIndex = 1
    end
    if insertIndex > (#preview + 1) then
        insertIndex = #preview + 1
    end

    table.insert(preview, insertIndex, draggedCategoryId)
    return preview
end

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

function RB:GetCategoryInsertIndexFromCursor()
    if not self.frame or not self.frame.sidePanelInner then
        return 1
    end

    local order = self:NormalizeCategoryOrder()
    local total = #order
    if total < 1 then
        return 1
    end

    local _, cursorY = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale() or 1
    cursorY = cursorY / scale

    local top = self.frame.sidePanelInner:GetTop() or 0
    local bottom = self.frame.sidePanelInner:GetBottom() or 0
    local buttonHeight = self.CATEGORY_ICON_SIZE + self.CATEGORY_BUTTON_PADDING_Y * 2
    local step = buttonHeight + self.TAB_GAP

    local minY = bottom + buttonHeight / 2
    local maxY = top - buttonHeight / 2
    cursorY = clamp(cursorY, minY, maxY)

    local insertIndex = math.floor(((top - cursorY) / step) + 0.5) + 1
    insertIndex = clamp(insertIndex, 1, total)

    return insertIndex, cursorY
end

function RB:GetCategoryDragVisualPosition()
    if not self.frame or not self.frame.sidePanelInner then
        return nil, nil, nil
    end

    local insertIndex, clampedY = self:GetCategoryInsertIndexFromCursor()
    local left = self.frame.sidePanelInner:GetLeft() or 0
    local right = self.frame.sidePanelInner:GetRight() or left
    local centerX = (left + right) / 2

    return centerX, clampedY, insertIndex
end

function RB:UpdateCategoryDragPreview()
    local dragState = self.dragState
    if not dragState or dragState.kind ~= "category" then
        return
    end

    local insertIndex = self:GetCategoryInsertIndexFromCursor()
    if not insertIndex then
        return
    end

    if dragState.previewInsertIndex ~= insertIndex then
        dragState.previewInsertIndex = insertIndex
        dragState.previewOrder = self:BuildCategoryPreviewOrderByIndex(dragState.categoryId, insertIndex)
        self:ApplyCategoryTabLayout(dragState.previewOrder, dragState.categoryId)
    end
end


function RB:GetSlotIndexFromCursor()
    if not self.frame or not self.frame.slotArea then
        return nil
    end

    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale() or 1
    x = x / scale
    y = y / scale

    local left = self.frame.slotArea:GetLeft() or 0
    local right = self.frame.slotArea:GetRight() or 0
    local top = self.frame.slotArea:GetTop() or 0
    local bottom = self.frame.slotArea:GetBottom() or 0

    if x < left or x > right or y > top or y < bottom then
        return nil
    end

    local localX = x - left - self.SLOT_PAD_X
    local localY = (top - y) - self.SLOT_PAD_Y

    if localX < 0 or localY < 0 then
        return nil
    end

    local stepX = self.SLOT_SIZE + self.SLOT_SPACING_X
    local stepY = self.SLOT_SIZE + self.SLOT_SPACING_Y

    local col = math.floor(localX / stepX) + 1
    local row = math.floor(localY / stepY) + 1

    if col < 1 or col > self.COLUMNS or row < 1 or row > self.ROWS then
        return nil
    end

    local withinX = math.fmod(localX, stepX)
    local withinY = math.fmod(localY, stepY)

    if withinX > self.SLOT_SIZE or withinY > self.SLOT_SIZE then
        return nil
    end

    return (row - 1) * self.COLUMNS + col
end

function RB:UpdateItemDragPreview()
    local dragState = self.dragState
    if not dragState or dragState.kind ~= "item" or not self.frame or not self.frame.slotButtons then
        return
    end

    local slotIndex = self:GetSlotIndexFromCursor()
    if slotIndex ~= dragState.previewTargetSlotIndex then
        dragState.previewTargetSlotIndex = slotIndex
        self:Debug("UpdateItemDragPreview: targetSlot=" .. tostring(slotIndex), true)
    end

    if slotIndex and self.frame.slotButtons[slotIndex] then
        self:SetDragHover(self.frame.slotButtons[slotIndex])
    else
        self:SetDragHover(nil)
    end
end

local function setButtonCount(button, count)
    local countWidget = button.CountText
    if not countWidget then
        return
    end

    if count and count > 1 then
        local text = tostring(count)
        local fontSize = 13

        if count > 9999 then
            text = "∞"
            fontSize = 12
        elseif count > 999 then
            fontSize = 9
        else
            fontSize = 13
        end

        countWidget:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
        countWidget:SetTextColor(1, 1, 1, 1)
        countWidget:SetShadowColor(0, 0, 0, 1)
        countWidget:SetShadowOffset(1, -1)
        countWidget:SetText(text)
        countWidget:Show()
    else
        countWidget:SetText("")
        countWidget:Hide()
    end
end

local function createBorderedPanel(parent, inset)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 14,
        insets = inset or { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.96)
    frame:SetBackdropBorderColor(0.65, 0.52, 0.16, 0.95)
    return frame
end

local function setTabVisual(tab, isActive, isHover)
    if tab.StateFill then
        if isActive then
            tab.StateFill:SetVertexColor(0.16, 0.05, 0.03, 0.98)
        elseif isHover then
            tab.StateFill:SetVertexColor(0.14, 0.06, 0.03, 0.98)
        else
            tab.StateFill:SetVertexColor(0.10, 0.04, 0.03, 0.96)
        end
        tab.StateFill:Show()
    end

    if tab.IconHolder then
        if isActive then
            tab.IconHolder:SetBackdropColor(0.93, 0.88, 0.62, 0.98)
            tab.IconHolder:SetBackdropBorderColor(1.00, 0.96, 0.78, 1.00)
        elseif isHover then
            tab.IconHolder:SetBackdropColor(0.30, 0.10, 0.08, 0.98)
            tab.IconHolder:SetBackdropBorderColor(0.88, 0.52, 0.18, 0.95)
        else
            tab.IconHolder:SetBackdropColor(0.16, 0.04, 0.05, 0.96)
            tab.IconHolder:SetBackdropBorderColor(0.36, 0.10, 0.10, 0.92)
        end
        tab.IconHolder:Show()
    end

    if isActive then
        tab:SetBackdropColor(0.18, 0.10, 0.04, 0.98)
        tab:SetBackdropBorderColor(1.00, 0.92, 0.58, 1.00)
        tab.icon:SetVertexColor(1.0, 1.0, 1.0)
        if tab.ActiveGlow then
            tab.ActiveGlow:Show()
        end
    elseif isHover then
        tab:SetBackdropColor(0.14, 0.07, 0.03, 0.98)
        tab:SetBackdropBorderColor(0.92, 0.62, 0.24, 1.00)
        tab.icon:SetVertexColor(1.0, 1.0, 1.0)
        if tab.ActiveGlow then
            tab.ActiveGlow:Hide()
        end
    else
        tab:SetBackdropColor(0.08, 0.04, 0.03, 0.96)
        tab:SetBackdropBorderColor(0.40, 0.16, 0.10, 0.90)
        tab.icon:SetVertexColor(0.95, 0.95, 0.95)
        if tab.ActiveGlow then
            tab.ActiveGlow:Hide()
        end
    end
end

local function getCategoryButtonWidth()
    return RB.CATEGORY_ICON_SIZE + RB.CATEGORY_BUTTON_PADDING_X * 2
end

local function getCategoryButtonHeight()
    return RB.CATEGORY_ICON_SIZE + RB.CATEGORY_BUTTON_PADDING_Y * 2
end

local function getSidePanelWidth()
    return getCategoryButtonWidth() + RB.SIDE_PANEL_INNER_PAD * 2
end

local function getCategoryIconTexture(category)
    if category.icon then
        return category.icon
    end

    if category.iconItemID and GetItemIcon then
        local icon = GetItemIcon(category.iconItemID)
        if icon then
            return icon
        end
    end

    return category.fallbackIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function getSlotAreaWidth()
    return RB.SLOT_PAD_X * 2 + RB.COLUMNS * RB.SLOT_SIZE + (RB.COLUMNS - 1) * RB.SLOT_SPACING_X
end

local function getSlotAreaHeight()
    return RB.SLOT_PAD_Y * 2 + RB.ROWS * RB.SLOT_SIZE + (RB.ROWS - 1) * RB.SLOT_SPACING_Y
end

RB.SIDE_PANEL_EXTRA_HEIGHT = 30 -- підбирай це число

local function getSidePanelHeight()
    return RB.SEARCH_HEIGHT + RB.OUTER_PAD + getSlotAreaHeight() + RB.SIDE_PANEL_EXTRA_HEIGHT
end

local function getOuterInsetWidth()
    return RB.OUTER_PAD * 3 + getSlotAreaWidth() + getSidePanelWidth()
end

local function getOuterInsetHeight()
    return RB.OUTER_PAD * 2 + RB.SEARCH_HEIGHT + getSlotAreaHeight() + RB.BOTTOM_BAR_HEIGHT + 8
end

local function getFrameWidth()
    return getOuterInsetWidth() + 48
end

local function getFrameHeight()
    return getOuterInsetHeight() + 70
end

local function boolToString(value)
    return value and "true" or "false"
end

function RB:Print(message)
    local line = "|cffffd100ReagentBank|r " .. tostring(message or "")
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(line)
    elseif print then
        print(line)
    end
end

function RB:IsDebugEnabled()
    if ReagentBankUI_DB and ReagentBankUI_DB.debug ~= nil then
        return ReagentBankUI_DB.debug
    end

    return self.DEBUG
end

function RB:SetDebugEnabled(enabled)
    enabled = not not enabled

    if not ReagentBankUI_DB then
        ReagentBankUI_DB = {}
    end

    ReagentBankUI_DB.debug = enabled
    self.DEBUG = enabled
    self:Print("Debug mode: " .. boolToString(enabled))
end

function RB:Debug(message, force)
    if not self:IsDebugEnabled() then
        return
    end

    local line = "|cff33ff99RBANK DEBUG|r " .. tostring(message or "")
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(line)
    elseif print then
        print(line)
    end
end

function RB:SendCommand(command)
    if not command or command == "" then
        self:Debug("SendCommand skipped: empty command")
        return
    end

    if self.state.demoMode then
        self:Debug("SendCommand skipped in demo mode: " .. command)
        return
    end

    local target = UnitName("player")
    if not target then
        self:Debug("SendCommand failed: UnitName(player) is nil", true)
        return
    end

    self:Debug("SendCommand -> prefix=" .. self.PREFIX .. ", channel=WHISPER, target=" .. target .. ", payload=" .. command, true)
    SendAddonMessage(self.PREFIX, command, "WHISPER", target)
end

function RB:SendRegistration()
    if self.state.demoMode then
        self:Debug("SendRegistration skipped in demo mode")
        return
    end

    local registeredPrefix = "n/a"
    if RegisterAddonMessagePrefix then
        registeredPrefix = tostring(RegisterAddonMessagePrefix(self.PREFIX))
    end

    self:Debug("SendRegistration: RegisterAddonMessagePrefix(" .. self.PREFIX .. ") -> " .. registeredPrefix, true)
    self:SendCommand("REGISTER")
    self.state.registered = true
end

function RB:ParseItems(raw)
    local items = {}
    if not raw or raw == "" then
        return items
    end

    for itemData in string.gmatch(raw, "[^;]+") do
        local itemId, count = string.match(itemData, "^(%d+),(%d+)$")
        if itemId and count then
            table.insert(items, {
                itemID = tonumber(itemId),
                count = tonumber(count),
            })
        end
    end

    return items
end

function RB:SetPageData(categoryId, page, totalPages, items)
    local bucket = ensurePageBucket(categoryId)
    bucket.totalPages = totalPages or 1
    bucket.pages[page] = items or {}

    if self.state.currentCategory == categoryId then
        self.state.currentPage = page
        self.state.totalPages = bucket.totalPages
    end
end

function RB:GetCurrentItems()
    local bucket = self.state.pageCache[self.state.currentCategory]
    if not bucket then
        return {}
    end

    return bucket.pages[self.state.currentPage] or {}
end

function RB:ClearAllData()
    wipeTable(self.state.pageCache)
    self.state.currentPage = 1
    self.state.totalPages = 1
    self.state.isSearchMode = false
    self.state.searchQuery = ""
end

function RB:BuildDemoData()
    self:ClearAllData()
    self.state.demoMode = true
    self.state.statusText = "Демо-режим. ПКМ по предмету в сховищі — зняти 1 стак. Перетягніть предмет із сумки у вікно банку, щоб вкласти його."

    local demoByCategory = {
        [5] = { 2589, 2592, 4306, 4338, 14047, 14342, 21877, 33470, 2320, 2996, 2997, 3182, 4305, 10285, 4339, 14048, 14256, 21840, 21845, 24271 },
        [7] = { 2770, 2771, 2772, 3858, 7911, 10620, 36909, 36910, 36912, 36913 },
        [12] = { 10938, 10939, 10940, 11082, 11083, 11134, 11135, 11137, 11138, 22445, 22446, 34052, 34053, 34054, 34055, 34056 },
        [9] = { 765, 2447, 2450, 2452, 2453, 3355, 3356, 3357, 3369, 3818, 3820, 3821, 4625, 13463, 13464, 36901, 36903, 36904, 36905, 37921 },
        [6] = { 2318, 2319, 4234, 4304, 8170, 15407, 15408, 21887, 25649, 33568 },
        [4] = { 1206, 7909, 12361, 12799, 12800, 23077, 23436, 23437, 36917, 36918, 36919, 36920, 36921, 36922, 36923, 36924, 42225 },
        [10] = { 7076, 7080, 7082, 7081, 7067, 7068, 7075, 7077, 37700 },
        [8] = { 2672, 2673, 2674, 2675, 2677, 2678, 3730, 6522 },
        [1] = { 4357, 4359, 4361, 4363, 10558, 16006, 23782 },
        [2] = { 4358, 4364, 4365, 4366 },
        [3] = { 4382, 4387, 4389, 4399, 4400 },
        [13] = { 22450, 22451, 22452, 22456, 21884, 24243, 22457, 22445 },
        [11] = { 2604, 2320, 6260, 2324, 2325, 4340, 4341, 4342, 6261 },
        [14] = { 38682, 37602, 43145 },
        [15] = { 39349, 44499 },
    }

    for _, category in ipairs(self.categories) do
        local source = demoByCategory[category.id] or {}
        local bucket = ensurePageBucket(category.id)
        local totalPages = math.max(1, math.ceil(#source / self.PAGE_SIZE))
        bucket.totalPages = totalPages

        for page = 1, totalPages do
            local startIndex = (page - 1) * self.PAGE_SIZE + 1
            local endIndex = math.min(page * self.PAGE_SIZE, #source)
            local items = {}
            for i = startIndex, endIndex do
                table.insert(items, {
                    itemID = source[i],
                    count = (i * 73) % 12000 + 1,
                })
            end
            bucket.pages[page] = items
        end
    end

    self.state.currentCategory = 5
    self.state.lastCategory = 5
    self.state.currentPage = 1
    self.state.totalPages = ensurePageBucket(5).totalPages
    self.state.isSearchMode = false
    self.state.searchQuery = ""
end

function RB:SearchDemo(query)
    query = string.lower(trim(query or ""))
    if query == "" then
        self.state.isSearchMode = false
        self.state.searchQuery = ""
        self:RequestCategory(self.state.lastCategory or self.categories[1].id, 1)
        return
    end

    local matches = {}
    for _, category in ipairs(self.categories) do
        local bucket = ensurePageBucket(category.id)
        for _, pageItems in pairs(bucket.pages) do
            for _, item in ipairs(pageItems) do
                local itemName = GetItemInfo(item.itemID)
                if itemName and string.find(string.lower(itemName), query, 1, true) then
                    table.insert(matches, item)
                end
            end
        end
    end

    local searchCategoryId = -1
    local bucket = ensurePageBucket(searchCategoryId)
    wipeTable(bucket.pages)

    local totalPages = math.max(1, math.ceil(#matches / self.PAGE_SIZE))
    bucket.totalPages = totalPages
    for page = 1, totalPages do
        local startIndex = (page - 1) * self.PAGE_SIZE + 1
        local endIndex = math.min(page * self.PAGE_SIZE, #matches)
        local pageItems = {}
        for i = startIndex, endIndex do
            table.insert(pageItems, matches[i])
        end
        bucket.pages[page] = pageItems
    end

    self.state.currentCategory = searchCategoryId
    self.state.currentPage = 1
    self.state.totalPages = totalPages
    self.state.isSearchMode = true
    self.state.searchQuery = query
    self.state.statusText = (#matches > 0) and ("Результати пошуку: " .. query) or ("Нічого не знайдено: " .. query)
    self:Render()
end


function RB:ShowCenterMessage(text)
    if not text or text == "" then
        return
    end

    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(text, 1.0, 0.82, 0.0, 1.0)
    elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00" .. text .. "|r")
    end
end

function RB:ScheduleRefresh(delay)
    if self.state.demoMode then
        return
    end

    delay = delay or 0.20
    self.refreshPending = true

    if not self.refreshTicker then
        self.refreshTicker = CreateFrame("Frame")
        self.refreshTicker:Hide()
        self.refreshTicker:SetScript("OnUpdate", function(frame, elapsed)
            frame.remaining = (frame.remaining or 0) - elapsed
            if frame.remaining > 0 then
                return
            end

            frame:Hide()
            RB.refreshPending = false

            local page = RB.state.currentPage or 1
            if RB.state.isSearchMode and RB.state.searchQuery ~= "" then
                RB:RequestSearch(RB.state.searchQuery, page, true)
            else
                RB:RequestCategory(getVisibleCategoryForRefresh(), page, true)
            end
        end)
    end

    self.refreshTicker.remaining = delay
    self.refreshTicker:Show()
end

function RB:ApplyOptimisticWithdraw(itemID)
    local bucket = self.state.pageCache[self.state.currentCategory]
    if not bucket then
        return
    end

    local items = bucket.pages[self.state.currentPage]
    if not items then
        return
    end

    for index, item in ipairs(items) do
        if item.itemID == itemID then
            local _, _, _, _, _, _, _, maxStack = GetItemInfo(itemID)
            if not maxStack or maxStack < 1 then
                return
            end

            if item.count > maxStack then
                item.count = item.count - maxStack
            else
                table.remove(items, index)
            end
            return
        end
    end
end

function RB:RequestOpen()
    self.state.demoMode = false
    self.state.pendingOpen = true
    self:ClearAllData()
    self.state.statusText = "Запит до сервера..."
    self:SendRegistration()
    self:SendCommand("REQ_OPEN")
    self:Show()
    self:Render()
end

function RB:RequestCategory(categoryId, page, forceRefresh)
    page = page or 1
    self:Debug("RequestCategory: categoryId=" .. tostring(categoryId) .. ", page=" .. tostring(page), true)
    self.state.currentCategory = categoryId
    self.state.lastCategory = categoryId
    self.state.currentPage = page
    self.state.isSearchMode = false
    self.state.searchQuery = ""

    local bucket = self.state.pageCache[categoryId]
    if not forceRefresh and bucket and bucket.pages[page] then
        self.state.totalPages = bucket.totalPages or 1
        self.state.statusText = "ПКМ по предмету в сховищі — зняти 1 стак. Перетягніть предмет із сумки у вікно банку, щоб вкласти його."
        self:Render()
        return
    end

    self.state.totalPages = 1
    self.state.statusText = "Завантаження..."
    self:Render()

    if not self.state.demoMode then
        self:SendCommand(string.format("REQ_CAT|%d|%d", categoryId, page))
    else
        self:Debug("RequestCategory served from demo mode cache")
    end
end

function RB:RequestSearch(query, page, forceRefresh)
    query = trim(query or "")
    self:Debug("RequestSearch: query='" .. query .. "', page=" .. tostring(page or 1), true)
    if self.frame and self.frame.searchBox and self.frame.searchBox:GetText() ~= query then
        self.frame.searchBox:SetText(query)
    end

    if query == "" then
        self.state.isSearchMode = false
        self.state.searchQuery = ""
        self:RequestCategory(self.state.lastCategory or self.categories[1].id, 1)
        return
    end

    if self.state.demoMode then
        self:SearchDemo(query)
        return
    end

    self.state.isSearchMode = true
    self.state.searchQuery = query
    self.state.currentCategory = -1
    self.state.currentPage = page or 1

    local searchBucket = self.state.pageCache[-1]
    if not forceRefresh and searchBucket and searchBucket.pages[self.state.currentPage] then
        self.state.totalPages = searchBucket.totalPages or 1
        self.state.statusText = "Пошук: " .. query
        self:Render()
        return
    end

    self.state.totalPages = 1
    self.state.statusText = "Пошук: " .. query
    self:Render()
    self:SendCommand(string.format("REQ_SEARCH|%s|%d", query, self.state.currentPage))
end

function RB:RequestWithdraw(itemID)
    if not itemID then
        self:Debug("RequestWithdraw skipped: itemID is nil")
        return
    end

    self:Debug("RequestWithdraw: itemID=" .. tostring(itemID), true)

    if self.state.demoMode then
        self.state.statusText = "Демо: знято 1 стак предмета " .. itemID
        self:Render()
        return
    end

    self:ApplyOptimisticWithdraw(itemID)
    self:Render()
    self:SendCommand(string.format("WITHDRAW|%d", itemID))
end

function RB:RequestDepositBagItem(bag, slot, itemID, itemCount)
    if bag == nil or slot == nil then
        self:Debug("RequestDepositBagItem skipped: bag/slot is nil")
        return
    end

    self:Debug("RequestDepositBagItem: bag=" .. tostring(bag) .. ", slot=" .. tostring(slot) .. ", itemID=" .. tostring(itemID) .. ", itemCount=" .. tostring(itemCount), true)

    if self.state.demoMode then
        self.state.statusText = "Демо: вкладено предмет " .. (itemID or "")
        self:Render()
        return
    end

    self.state.statusText = "Запит на внесення предмета..."
    self:Render()

    local payload = string.format("DEPOSIT_BAG|%d|%d", bag, slot)
    if tonumber(itemID) then
        payload = payload .. "|" .. tostring(tonumber(itemID))
        if tonumber(itemCount) then
            payload = payload .. "|" .. tostring(tonumber(itemCount))
        end
    end

    self:SendCommand(payload)
end

function RB:RequestDepositAll()
    self:Debug("RequestDepositAll called", true)
    if self.state.demoMode then
        self.state.statusText = "Демо: вкладено всі реагенти"
        self:Render()
        return
    end

    self:SendCommand("DEPOSIT_ALL")
end

function RB:PrevPage()
    if self.state.currentPage <= 1 then
        return
    end

    self.state.currentPage = self.state.currentPage - 1
    if self.state.isSearchMode then
        self:RequestSearch(self.state.searchQuery, self.state.currentPage)
    else
        self:RequestCategory(self.state.currentCategory, self.state.currentPage)
    end
end

function RB:NextPage()
    if self.state.currentPage >= (self.state.totalPages or 1) then
        return
    end

    self.state.currentPage = self.state.currentPage + 1
    if self.state.isSearchMode then
        self:RequestSearch(self.state.searchQuery, self.state.currentPage)
    else
        self:RequestCategory(self.state.currentCategory, self.state.currentPage)
    end
end

function RB:HandleInboundPayload(payload)
    if not payload or payload == "" then
        self:Debug("HandleInboundPayload skipped: empty payload")
        return
    end

    self:Debug("HandleInboundPayload raw: " .. payload, true)

    if string.sub(payload, 1, string.len(self.PREFIX) + 1) == (self.PREFIX .. "\t") then
        payload = string.sub(payload, string.len(self.PREFIX) + 2)
        self:Debug("HandleInboundPayload stripped prefix -> " .. payload, true)
    end

    self:HandleServerMessage(payload)
end

function RB:HandleServerMessage(message)
    self:Debug("HandleServerMessage: " .. tostring(message), true)

    local separator = "|"
    if string.find(message, "	", 1, true) then
        separator = "	"
    end

    local parts = split(message, separator)
    local opcode = parts[1]

    if opcode == "OPEN" then
        self:Debug("Opcode OPEN received", true)
        self.state.pendingOpen = false
        self:Show()
        return
    end

    if opcode == "RESET" then
        self:Debug("Opcode RESET received", true)
        self.state.statusText = "Оновлено."
        if self.pendingDepositCategory then
            self.state.isSearchMode = false
            self.state.currentCategory = self.pendingDepositCategory
            self.state.lastCategory = self.pendingDepositCategory
            self.state.currentPage = 1
            self.pendingDepositCategory = nil
        end
        self:ScheduleRefresh(0.20)
        return
    end

    if opcode == "STATUS" then
        self:Debug("Opcode STATUS received: " .. tostring(parts[2] or ""))
        self.state.statusText = parts[2] or ""
        if self.pendingDepositItemID and string.sub(self.state.statusText, 1, string.len("Покладено до сховища:")) ~= "Покладено до сховища:" then
            self.pendingDepositItemID = nil
            self.pendingDepositTargetSlotIndex = nil
            self.pendingDepositCategory = nil
            self.pendingDepositPage = nil
        end
        if self.state.statusText ~= "" then
            self:Print(self.state.statusText)
        end
        return
    end

    if opcode == "PAGE" then
        self:Debug("Opcode PAGE received: category=" .. tostring(parts[2]) .. ", page=" .. tostring(parts[3]) .. ", totalPages=" .. tostring(parts[4]) .. ", rawItemsLength=" .. tostring(string.len(parts[5] or "")), true)
        local categoryId = tonumber(parts[2]) or self.state.currentCategory
        local page = tonumber(parts[3]) or 1
        local totalPages = tonumber(parts[4]) or 1
        local items = self:ParseItems(parts[5] or "")
        self:SetPageData(categoryId, page, totalPages, items)
        if categoryId and categoryId > 0 then
            self:SyncLayoutWithRawItems(categoryId, page, items)
            self:ApplyPendingDepositPlacement(categoryId, page, items)
        end
        self.state.currentCategory = categoryId
        self.state.currentPage = page
        self.state.totalPages = totalPages
        self.state.isSearchMode = categoryId == -1
        if not self.state.isSearchMode then
            self.state.lastCategory = categoryId
        end

        if #items == 0 then
            if self.state.isSearchMode then
                self.state.statusText = "Нічого не знайдено."
            else
                self.state.statusText = "Категорія порожня."
            end
        else
            self.state.statusText = "ПКМ по предмету в сховищі — зняти 1 стак. Перетягніть предмет із сумки у вікно банку, щоб вкласти його."
        end

        self:Show()
        self:Render()
        return
    end

    self:Debug("Unknown opcode received: " .. tostring(opcode), true)
end

function RB:CreateDragVisual()
    if self.dragVisual then
        return
    end

    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetToplevel(true)
    frame:EnableMouse(false)
    frame:Hide()

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    frame.icon = icon

    local countText = frame:CreateFontString(nil, "OVERLAY")
    countText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    countText:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
    countText:SetTextColor(1, 1, 1, 1)
    countText:SetJustifyH("RIGHT")
    countText:SetShadowColor(0, 0, 0, 1)
    countText:SetShadowOffset(1, -1)
    countText:Hide()
    frame.countText = countText

    frame:SetScript("OnUpdate", function(selfFrame)
        if not RB.dragState then
            selfFrame:Hide()
            return
        end

        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale() or 1
        x = x / scale
        y = y / scale

        selfFrame:ClearAllPoints()

        if RB.dragState.kind == "category" then
            local visualX, visualY = RB:GetCategoryDragVisualPosition()
            if visualX and visualY then
                selfFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", visualX, visualY)
            else
                selfFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
            end

            RB:UpdateCategoryDragPreview()
        else
            selfFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x + 12, y - 12)
            RB:UpdateItemDragPreview()
        end

        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            RB:CompleteActiveDrag()
        end
    end)

    self.dragVisual = frame
end

function RB:UpdateDragVisualCount(count)
    if not self.dragVisual or not self.dragVisual.countText then
        return
    end

    local widget = self.dragVisual.countText
    local fontSize = 13
    local text = ""

    if count and count > 1 then
        text = tostring(count)

        if count > 9999 then
            text = "∞"
            fontSize = 12
        elseif count > 999 then
            fontSize = 9
        end
    end

    widget:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
    widget:SetTextColor(1, 1, 1, 1)
    widget:SetShadowColor(0, 0, 0, 1)
    widget:SetShadowOffset(1, -1)
    widget:SetText(text)

    if text ~= "" then
        widget:Show()
    else
        widget:Hide()
    end
end

function RB:SetSlotDropHighlight(button, enabled)
    if not button then
        return
    end

    if not button.RBDropHighlight then
        local texture = button:CreateTexture(nil, "OVERLAY")
        texture:SetTexture("Interface\Buttons\UI-ActionButton-Border")
        texture:SetBlendMode("ADD")
        texture:SetAlpha(0.95)
        texture:SetPoint("TOPLEFT", button, "TOPLEFT", -10, 10)
        texture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 10, -10)
        texture:Hide()
        button.RBDropHighlight = texture
    end

    if enabled then
        button.RBDropHighlight:Show()
    else
        button.RBDropHighlight:Hide()
    end
end

function RB:SetTabDropHighlight(button, enabled)
    if not button then
        return
    end

    if enabled then
        button:SetBackdropBorderColor(1.00, 0.95, 0.30, 1.00)
        button:SetBackdropColor(0.28, 0.14, 0.05, 1.00)
    else
        self:RefreshTabs()
    end
end

function RB:ClearActiveDrag()
    local dragState = self.dragState
    if not dragState then
        return
    end

    if dragState.hoverButton then
        if dragState.kind == "item" then
            self:SetSlotDropHighlight(dragState.hoverButton, false)
        elseif dragState.kind == "category" then
            self:SetTabDropHighlight(dragState.hoverButton, false)
        end
    end

    if dragState.kind == "item" and dragState.sourceButton then
        dragState.sourceButton:SetAlpha(1)
    end

    self.dragState = nil

    if self.dragVisual then
        self.dragVisual:Hide()
    end

    self:ApplyCategoryTabLayout()
end

function RB:SetDragHover(button)
    local dragState = self.dragState
    if not dragState then
        return
    end

    if dragState.hoverButton == button then
        return
    end

    if dragState.hoverButton then
        if dragState.kind == "item" then
            self:SetSlotDropHighlight(dragState.hoverButton, false)
        elseif dragState.kind == "category" then
            self:SetTabDropHighlight(dragState.hoverButton, false)
        end
    end

    dragState.hoverButton = button

    if button then
        if dragState.kind == "item" then
            self:SetSlotDropHighlight(button, true)
        elseif dragState.kind == "category" then
            self:SetTabDropHighlight(button, true)
        end
    end
end

function RB:StartItemDrag(button)
    if self.state.isSearchMode or not button or not button.itemData or (IsModifiedClick and IsModifiedClick()) then
        return
    end

    self:ClearActiveDrag()
    self:CreateDragVisual()

    self.dragState = {
        kind = "item",
        sourceButton = button,
        sourceSlotIndex = button.slotIndex,
        itemData = shallowItemCopy(button.itemData),
        hoverButton = nil,
        previewTargetSlotIndex = button.slotIndex,
    }

    self:Debug(
        "StartItemDrag: sourceSlot=" .. tostring(button.slotIndex)
        .. ", itemID=" .. tostring(button.itemData.itemID)
        .. ", count=" .. tostring(button.itemData.count),
        true
    )

    button:SetAlpha(0.35)

    self.dragVisual:SetSize(self.SLOT_SIZE, self.SLOT_SIZE)
    self.dragVisual.icon:SetTexture(GetItemIcon(button.itemData.itemID))
    self:UpdateDragVisualCount(button.itemData.count)
    self.dragVisual:Show()
end

function RB:StartCategoryDrag(button)
    if self.state.isSearchMode or not button or not button.categoryId then
        return
    end

    self:ClearActiveDrag()
    self:CreateDragVisual()

    local order = self:NormalizeCategoryOrder()
    local sourceIndex = 1

    for index, categoryId in ipairs(order) do
        if categoryId == button.categoryId then
            sourceIndex = index
            break
        end
    end

    self.dragState = {
        kind = "category",
        sourceButton = button,
        categoryId = button.categoryId,
        previewInsertIndex = sourceIndex,
        previewOrder = self:BuildCategoryPreviewOrderByIndex(button.categoryId, sourceIndex),
    }

    self.dragVisual:SetSize(getCategoryButtonWidth(), getCategoryButtonHeight())
    self.dragVisual.icon:SetTexture(button.icon:GetTexture())
    self:UpdateDragVisualCount(0)
    self.dragVisual:Show()

    self:ApplyCategoryTabLayout(self.dragState.previewOrder, self.dragState.categoryId)
    self:UpdateCategoryDragPreview()
end

function RB:CompleteActiveDrag()
    local dragState = self.dragState
    if not dragState then
        return
    end

    if dragState.kind == "item" then
        local targetSlotIndex = dragState.previewTargetSlotIndex
        local targetButton = dragState.hoverButton

        if not targetSlotIndex and targetButton and targetButton.slotIndex then
            targetSlotIndex = targetButton.slotIndex
        end

        self:Debug(
            "CompleteActiveDrag(item): sourceSlot=" .. tostring(dragState.sourceSlotIndex)
            .. ", targetSlot=" .. tostring(targetSlotIndex),
            true
        )

        if targetSlotIndex then
            self:MoveDisplayedItem(dragState.sourceSlotIndex, targetSlotIndex)
        end
    elseif dragState.kind == "category" then
        if dragState.previewOrder and #dragState.previewOrder > 0 then
            ReagentBankUI_DB.categoryOrder = dragState.previewOrder
        end
    end

    self:ClearActiveDrag()
    self:Render()
end

function RB:ApplyCategoryTabLayout(orderOverride, placeholderCategoryId)
    if not self.frame or not self.frame.categoryTabs then
        return
    end

    local orderedIds
    if orderOverride then
        orderedIds = orderOverride
    else
        orderedIds = self:NormalizeCategoryOrder()
    end

    local previous = nil

    for index, categoryId in ipairs(orderedIds) do
        local tab = self.frame.categoryTabs[index]
        if tab then
            tab:ClearAllPoints()
            tab:SetAlpha(1)
            if previous then
                tab:SetPoint("TOP", previous, "BOTTOM", 0, -self.TAB_GAP)
            else
                tab:SetPoint("TOP", 0, -1)
            end

            if placeholderCategoryId and categoryId == placeholderCategoryId then
                tab.categoryId = nil
                tab.categoryName = nil
                tab.isPlaceholder = true
                tab.icon:SetTexture(nil)
                tab:SetBackdropColor(0.06, 0.06, 0.06, 0.35)
                tab:SetBackdropBorderColor(1.00, 0.82, 0.18, 0.95)
                if tab.StateFill then
                    tab.StateFill:SetVertexColor(0.06, 0.06, 0.06, 0.35)
                    tab.StateFill:Show()
                end
                if tab.IconHolder then
                    tab.IconHolder:SetBackdropColor(0.06, 0.06, 0.06, 0.25)
                    tab.IconHolder:SetBackdropBorderColor(0.85, 0.72, 0.20, 0.85)
                    tab.IconHolder:Show()
                end
                if tab.ActiveGlow then
                    tab.ActiveGlow:Hide()
                end
                tab:Show()
            else
                local category = getCategoryById(categoryId)
                tab.categoryId = category.id
                tab.categoryName = category.name
                tab.isPlaceholder = false
                tab.icon:SetTexture(getCategoryIconTexture(category))

                local isActive = (self.state.currentCategory == tab.categoryId and not self.state.isSearchMode)
                setTabVisual(tab, isActive, tab.isHovered)
                tab:Show()
            end

            previous = tab
        end
    end

    for index = #orderedIds + 1, #self.frame.categoryTabs do
        local tab = self.frame.categoryTabs[index]
        tab.categoryId = nil
        tab.categoryName = nil
        tab.isPlaceholder = false
        tab.icon:SetTexture(nil)
        tab:SetAlpha(1)
        if tab.ActiveGlow then
            tab.ActiveGlow:Hide()
        end
        tab:Hide()
    end
end

function RB:CreateBackdrop(parent)
    parent:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    parent:SetBackdropColor(0.56, 0.08, 0.08, 0.94)

    local header = parent:CreateTexture(nil, "ARTWORK")
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    header:SetSize(320, 64)
    header:SetPoint("TOP", 0, 12)
    parent.header = header

    local outerInset = createBorderedPanel(parent)
    outerInset:SetSize(getOuterInsetWidth(), getOuterInsetHeight())
    outerInset:SetPoint("TOP", 0, -36)
    outerInset:SetBackdropColor(0.03, 0.03, 0.03, 0.97)
    outerInset:SetBackdropBorderColor(0.58, 0.46, 0.13, 0.92)
    parent.outerInset = outerInset

    local searchBar = CreateFrame("Frame", nil, outerInset)
    searchBar:SetSize(getSlotAreaWidth(), self.SEARCH_HEIGHT)
    searchBar:SetPoint("TOPLEFT", self.OUTER_PAD, -self.OUTER_PAD)
    searchBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    searchBar:SetBackdropColor(0.10, 0.04, 0.04, 0.95)
    searchBar:SetBackdropBorderColor(0.52, 0.09, 0.09, 0.95)
    parent.searchBar = searchBar

    local slotArea = createBorderedPanel(outerInset)
    slotArea:SetSize(getSlotAreaWidth(), getSlotAreaHeight())
    slotArea:SetPoint("TOPLEFT", searchBar, "BOTTOMLEFT", 0, -self.OUTER_PAD)
    slotArea:SetBackdropColor(0.06, 0.06, 0.06, 0.98)
    slotArea:SetBackdropBorderColor(0.62, 0.50, 0.15, 0.95)
    parent.slotArea = slotArea

    local sidePanel = createBorderedPanel(outerInset)
    sidePanel:SetSize(getSidePanelWidth(), getSidePanelHeight())
    sidePanel:SetPoint("TOPLEFT", searchBar, "TOPRIGHT", self.OUTER_PAD, 0)
    sidePanel:SetBackdropColor(0.08, 0.04, 0.02, 0.97)
    sidePanel:SetBackdropBorderColor(0.62, 0.50, 0.15, 0.92)
    parent.sidePanel = sidePanel

    local sidePanelInner = CreateFrame("Frame", nil, sidePanel)
    sidePanelInner:SetPoint("TOPLEFT", self.SIDE_PANEL_INNER_PAD, -self.SIDE_PANEL_INNER_PAD)
    sidePanelInner:SetPoint("BOTTOMRIGHT", -self.SIDE_PANEL_INNER_PAD, self.SIDE_PANEL_INNER_PAD)
    sidePanelInner:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    sidePanelInner:SetBackdropColor(0.02, 0.02, 0.02, 0.95)
    sidePanelInner:SetBackdropBorderColor(0.35, 0.24, 0.08, 0.85)
    parent.sidePanelInner = sidePanelInner
end

function RB:CreateHeader(parent)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:ClearAllPoints()
    title:SetPoint("TOP", parent, "TOP", 0, 0)
    title:SetText("Тканина")
    title:SetTextColor(0.10, 1.0, 0.10)
    parent.title = title

    local close = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
    close:ClearAllPoints()
    close:SetPoint("TOPRIGHT", -4, -2)
    close:SetScript("OnClick", function()
        RB:Hide()
    end)
    parent.closeButton = close

    local searchBox = CreateFrame("EditBox", nil, parent.searchBar, "InputBoxTemplate")
    searchBox:SetAutoFocus(false)
    searchBox:SetSize(210, 22)
    searchBox:SetPoint("LEFT", 10, -1)
    searchBox:SetText("")
    searchBox:SetScript("OnEnterPressed", function(box)
        box:ClearFocus()
        RB:RequestSearch(box:GetText(), 1)
    end)
    searchBox:SetScript("OnEscapePressed", function(box)
        box:ClearFocus()
    end)
    parent.searchBox = searchBox

    local searchButton = CreateFrame("Button", nil, parent.searchBar, "UIPanelButtonTemplate")
    searchButton:SetSize(78, 22)
    searchButton:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
    searchButton:SetText("Пошук")
    searchButton:SetScript("OnClick", function()
        RB:RequestSearch(parent.searchBox:GetText(), 1)
    end)
    parent.searchButton = searchButton

    local clearButton = CreateFrame("Button", nil, parent.searchBar, "UIPanelButtonTemplate")
    clearButton:SetSize(78, 22)
    clearButton:SetPoint("LEFT", searchButton, "RIGHT", 6, 0)
    clearButton:SetText("Скинути")
    clearButton:SetScript("OnClick", function()
        parent.searchBox:SetText("")
        RB:RequestSearch("", 1)
    end)
    parent.clearButton = clearButton
end

function RB:CreateFooter(parent)
    local pageText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pageText:SetPoint("BOTTOM", parent.outerInset, "BOTTOM", 0, 16)
    pageText:SetText("Сторінка 1 / 1")
    parent.pageText = pageText

    local prev = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    prev:SetSize(88, 24)
    prev:SetPoint("BOTTOM", parent.outerInset, "BOTTOM", -52, 6)
    prev:SetText("Назад")
    prev:SetScript("OnClick", function()
        RB:PrevPage()
    end)
    parent.prevPageButton = prev

    local nextBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    nextBtn:SetSize(88, 24)
    nextBtn:SetPoint("BOTTOM", parent.outerInset, "BOTTOM", 52, 6)
    nextBtn:SetText("Далі")
    nextBtn:SetScript("OnClick", function()
        RB:NextPage()
    end)
    parent.nextPageButton = nextBtn

    local depositAllButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    depositAllButton:SetSize(110, 24)
    depositAllButton:SetPoint("BOTTOMRIGHT", parent.outerInset, "BOTTOMRIGHT", -self.OUTER_PAD - 42, 6)
    depositAllButton:SetText("Вкласти все")
    depositAllButton:SetScript("OnClick", function()
        RB:RequestDepositAll()
    end)
    parent.depositAllButton = depositAllButton
end

function RB:CreateTabs(parent)
    parent.categoryTabs = {}

    for index = 1, #self.categories do
        local tab = CreateFrame("Button", nil, parent.sidePanelInner)
        tab:SetSize(getCategoryButtonWidth(), getCategoryButtonHeight())
        tab:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false,
            edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        tab:RegisterForDrag("LeftButton")

        local stateFill = tab:CreateTexture(nil, "BACKGROUND")
        stateFill:SetTexture("Interface\\Buttons\\WHITE8X8")
        stateFill:SetPoint("TOPLEFT", tab, "TOPLEFT", 2, -2)
        stateFill:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -2, 2)
        stateFill:SetVertexColor(0.10, 0.04, 0.03, 0.96)
        tab.StateFill = stateFill

        local iconHolder = CreateFrame("Frame", nil, tab)
        iconHolder:SetSize(self.CATEGORY_ICON_SIZE + 8, self.CATEGORY_ICON_SIZE + 8)
        iconHolder:SetPoint("CENTER", 0, 0)
        iconHolder:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false,
            edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        iconHolder:SetBackdropColor(0.16, 0.04, 0.05, 0.96)
        iconHolder:SetBackdropBorderColor(0.36, 0.10, 0.10, 0.92)
        tab.IconHolder = iconHolder

        local icon = iconHolder:CreateTexture(nil, "ARTWORK")
        icon:SetSize(self.CATEGORY_ICON_SIZE, self.CATEGORY_ICON_SIZE)
        icon:SetPoint("CENTER", 0, 0)
        tab.icon = icon

        local activeGlow = tab:CreateTexture(nil, "OVERLAY")
        activeGlow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        activeGlow:SetBlendMode("ADD")
        activeGlow:SetAlpha(0.95)
        activeGlow:SetPoint("TOPLEFT", iconHolder, "TOPLEFT", -10, 10)
        activeGlow:SetPoint("BOTTOMRIGHT", iconHolder, "BOTTOMRIGHT", 10, -10)
        activeGlow:Hide()
        tab.ActiveGlow = activeGlow

        tab.categoryId = nil
        tab.categoryName = nil
        tab.isHovered = false

        tab:SetScript("OnClick", function(button)
            if RB.dragState and RB.dragState.kind == "category" then
                return
            end

            if button.categoryId then
                RB.state.currentCategory = button.categoryId
                RB.state.currentPage = 1
                RB:RequestCategory(button.categoryId, 1)
            end
        end)

        tab:SetScript("OnDragStart", function(button)
            RB:StartCategoryDrag(button)
        end)

        tab:SetScript("OnEnter", function(button)
            button.isHovered = true
            if RB.dragState and RB.dragState.kind == "category" then
                return
            end

            setTabVisual(button, RB.state.currentCategory == button.categoryId and not RB.state.isSearchMode, true)
            GameTooltip:SetOwner(button, "ANCHOR_LEFT")
            GameTooltip:SetText(button.categoryName or "")
            GameTooltip:AddLine("ЛКМ: відкрити категорію", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Перетягування: змінити порядок", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)

        tab:SetScript("OnLeave", function(button)
            button.isHovered = false
            if RB.dragState and RB.dragState.kind == "category" then
                GameTooltip:Hide()
                return
            end

            setTabVisual(button, RB.state.currentCategory == button.categoryId and not RB.state.isSearchMode, false)
            GameTooltip:Hide()
        end)

        parent.categoryTabs[index] = tab
    end

    self:ApplyCategoryTabLayout()
end

function RB:CreateSlots(parent)
    parent.slotButtons = {}
    parent.slotArea:EnableMouse(true)
    parent.slotArea:SetScript("OnUpdate", function()
        if RB.pendingBagDrag and CursorHasItem and not CursorHasItem() then
            RB:ClearPendingBagDrag()
        elseif RB.pendingBagDrag then
            RB:UpdatePendingBagDragCategory()
            local slotIndex = RB:GetPendingBagDragTargetSlotIndex()
            if slotIndex ~= RB.pendingBagDrag.targetSlotIndex then
                if RB.pendingBagDrag.targetSlotIndex and RB.frame and RB.frame.slotButtons then
                    local previous = RB.frame.slotButtons[RB.pendingBagDrag.targetSlotIndex]
                    if previous then
                        RB:SetSlotDropHighlight(previous, false)
                    end
                end
                RB.pendingBagDrag.targetSlotIndex = slotIndex
                if slotIndex and RB.frame and RB.frame.slotButtons then
                    local current = RB.frame.slotButtons[slotIndex]
                    if current then
                        RB:SetSlotDropHighlight(current, true)
                    end
                end
            end
        end
    end)
    parent.slotArea:SetScript("OnReceiveDrag", function()
        RB:TryDepositPendingBagDrag(nil)
    end)
    parent.slotArea:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "LeftButton" then
            RB:TryDepositPendingBagDrag(nil)
        end
    end)
    parent.slotArea:SetScript("OnEnter", function()
        RB:HandleBankDropTargetEnter(nil)
    end)
    parent.slotArea:SetScript("OnLeave", function()
        RB:HandleBankDropTargetLeave(nil)
    end)

    local startX = self.SLOT_PAD_X
    local startY = -self.SLOT_PAD_Y

    for row = 1, self.ROWS do
        for col = 1, self.COLUMNS do
            local index = (row - 1) * self.COLUMNS + col
            local button = CreateFrame("Button", ADDON_NAME .. "Slot" .. index, parent.slotArea, "ItemButtonTemplate")
            button:SetSize(self.SLOT_SIZE, self.SLOT_SIZE)
            button:SetPoint(
                "TOPLEFT",
                startX + (col - 1) * (self.SLOT_SIZE + self.SLOT_SPACING_X),
                startY - (row - 1) * (self.SLOT_SIZE + self.SLOT_SPACING_Y)
            )
            button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            button:RegisterForDrag("LeftButton")
            button.slotIndex = index
            button.itemData = nil

            local emptyBg = button:CreateTexture(nil, "BACKGROUND")
            emptyBg:SetTexture("Interface\Buttons\WHITE8X8")
            emptyBg:SetPoint("TOPLEFT", 5, -5)
            emptyBg:SetPoint("BOTTOMRIGHT", -5, 5)
            emptyBg:SetVertexColor(0.11, 0.11, 0.11, 0.95)
            button.emptyBg = emptyBg

            if button.Count then
                button.Count:Hide()
            end

            local countText = button:CreateFontString(nil, "OVERLAY")
            countText:SetDrawLayer("OVERLAY", 7)
            countText:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
            countText:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
            countText:SetTextColor(1, 1, 1, 1)
            countText:SetJustifyH("RIGHT")
            countText:SetShadowColor(0, 0, 0, 1)
            countText:SetShadowOffset(1, -1)
            countText:Hide()
            button.CountText = countText

            button:SetScript("OnEnter", function(selfButton)
                if RB.dragState and RB.dragState.kind == "item" then
                    RB:SetDragHover(selfButton)
                    return
                end

                if RB.pendingBagDrag and CursorHasItem and CursorHasItem() then
                    RB:HandleBankDropTargetEnter(selfButton)
                    return
                end

                if not selfButton.itemData then
                    return
                end

                GameTooltip:SetOwner(selfButton, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink("item:" .. selfButton.itemData.itemID)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("ПКМ: зняти 1 стак", 0.7, 1.0, 0.7)
                GameTooltip:AddLine("ЛКМ+перетягування: змінити слот", 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end)

            button:SetScript("OnLeave", function(selfButton)
                if RB.dragState and RB.dragState.kind == "item" and RB.dragState.hoverButton == selfButton then
                    RB:SetDragHover(nil)
                end
                if RB.pendingBagDrag then
                    RB:HandleBankDropTargetLeave(selfButton)
                end
                GameTooltip:Hide()
            end)

            button:SetScript("OnDragStart", function(selfButton)
                RB:StartItemDrag(selfButton)
            end)

            button:SetScript("OnReceiveDrag", function(selfButton)
                if RB:TryDepositPendingBagDrag(selfButton.slotIndex) then
                    RB:SetSlotDropHighlight(selfButton, false)
                end
            end)

            button:SetScript("OnMouseUp", function(selfButton, mouseButton)
                if mouseButton == "LeftButton" and RB.pendingBagDrag and CursorHasItem and CursorHasItem() then
                    if RB:TryDepositPendingBagDrag(selfButton.slotIndex) then
                        RB:SetSlotDropHighlight(selfButton, false)
                    end
                end
            end)

            button:SetScript("OnClick", function(selfButton, mouseButton)
                if RB.dragState and RB.dragState.kind == "item" and mouseButton == "LeftButton" then
                    return
                end

                if not selfButton.itemData then
                    return
                end

                if mouseButton == "RightButton" then
                    RB:RequestWithdraw(selfButton.itemData.itemID)
                    return
                end

                if IsModifiedClick() then
                    local _, itemLink = GetItemInfo(selfButton.itemData.itemID)
                    if itemLink then
                        HandleModifiedItemClick(itemLink)
                    end
                end
            end)

            parent.slotButtons[index] = button
        end
    end
end

function RB:RefreshTabs()
    if not self.frame or not self.frame.categoryTabs then
        return
    end

    if self.dragState and self.dragState.kind == "category" and self.dragState.previewOrder then
        self:ApplyCategoryTabLayout(self.dragState.previewOrder, self.dragState.categoryId)
    else
        self:ApplyCategoryTabLayout()
    end

    for _, tab in ipairs(self.frame.categoryTabs) do
        if tab:IsShown() and not tab.isPlaceholder then
            local isActive = (self.state.currentCategory == tab.categoryId and not self.state.isSearchMode)
            setTabVisual(tab, isActive, tab.isHovered)
        end
    end
end

function RB:RefreshSlots()
    local items = self:GetDisplayedItems()
    for index, button in ipairs(self.frame.slotButtons) do
        local item = items[index]
        local previous = button.itemData

        if not itemEquals(previous, item) then
            if item then
                SetItemButtonTexture(button, GetItemIcon(item.itemID))
                SetItemButtonDesaturated(button, false)
                setButtonCount(button, item.count)
                button.emptyBg:Hide()
                if button.IconBorder then
                    button.IconBorder:Show()
                end
            else
                SetItemButtonTexture(button, nil)
                setButtonCount(button, nil)
                button.emptyBg:Show()
                if button.IconBorder then
                    button.IconBorder:Hide()
                end
            end
        end

        button.itemData = shallowItemCopy(item)
    end
end

function RB:RefreshText()
    local category = getCategoryById(self.state.currentCategory > 0 and self.state.currentCategory or self.state.lastCategory)

    if self.state.isSearchMode then
        self.frame.title:SetText(self.state.searchQuery ~= "" and ("Пошук: " .. self.state.searchQuery) or "Пошук")
        self.frame.title:SetTextColor(0.10, 1.0, 0.10)
    else
        self.frame.title:SetText(category.name)
        self.frame.title:SetTextColor(0.10, 1.0, 0.10)
    end

    local showPagination = (self.state.totalPages or 1) > 1
    if showPagination then
        self.frame.pageText:SetText(string.format("Сторінка %d / %d", self.state.currentPage or 1, self.state.totalPages or 1))
        self.frame.pageText:Show()
        self.frame.prevPageButton:Show()
        self.frame.nextPageButton:Show()
        self.frame.prevPageButton:SetEnabled((self.state.currentPage or 1) > 1)
        self.frame.nextPageButton:SetEnabled((self.state.currentPage or 1) < (self.state.totalPages or 1))
    else
        self.frame.pageText:Hide()
        self.frame.prevPageButton:Hide()
        self.frame.nextPageButton:Hide()
    end

    if self.frame.searchBox then
        if self.state.isSearchMode then
            if self.frame.searchBox:GetText() ~= (self.state.searchQuery or "") then
                self.frame.searchBox:SetText(self.state.searchQuery or "")
            end
        elseif self.frame.searchBox:GetText() == self.state.searchQuery then
            -- keep whatever the user typed only when searching; otherwise leave box editable
        end
    end
end

function RB:Render()
    if not self.frame then
        return
    end

    self:RefreshTabs()
    self:RefreshSlots()
    self:RefreshText()
end

function RB:Show()
    if not self.frame then
        self:CreateFrame()
    end
    self.frame:Show()
    self:Render()
end

function RB:Hide()
    self:ClearActiveDrag()
    self:ClearPendingBagDrag()
    if self.frame then
        self.frame:Hide()
    end
end

function RB:Toggle()
    if not self.frame then
        self:CreateFrame()
    end

    if self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function RB:IsShown()
    return self.frame and self.frame:IsShown()
end

function RB:IsDepositableBagItem(bag, slot)
    if bag == nil or slot == nil then
        return false
    end

    local itemLink = GetContainerItemLink(bag, slot)
    if not itemLink then
        return false
    end

    local _, itemCount, locked = GetContainerItemInfo(bag, slot)
    if locked then
        return false
    end

    local itemID = GetContainerItemID and GetContainerItemID(bag, slot)
    if not itemID then
        local itemString = string.match(itemLink, "item:([-%d:]+)")
        if itemString then
            itemID = tonumber(string.match(itemString, "^(%d+)"))
        end
    end
    if not itemID then
        return false
    end

    local _, _, _, _, _, _, _, maxStack = GetItemInfo(itemID)
    if not maxStack or maxStack <= 1 then
        return false
    end

    return true, itemID, itemCount
end

function RB:InferCategoryIdForItem(itemID)
    itemID = tonumber(itemID)
    if not itemID then
        return nil
    end

    if itemID == 34055 or itemID == 46849 then
        return 12
    end
    if itemID == 38682 then
        return 14
    end
    if itemID == 39349 then
        return 15
    end

    local _, _, _, _, _, _, itemSubClass = GetItemInfo(itemID)
    if itemSubClass then
        return BAG_DRAG_CATEGORY_BY_SUBCLASS[itemSubClass]
    end

    return nil
end

function RB:QueuePendingDepositPlacement(categoryId, slotIndex, itemID)
    if not categoryId or categoryId <= 0 or not slotIndex or slotIndex < 1 or slotIndex > self.PAGE_SIZE or not itemID then
        self.pendingDepositItemID = nil
        self.pendingDepositTargetSlotIndex = nil
        self.pendingDepositPage = nil
        return
    end

    self.pendingDepositCategory = categoryId
    self.pendingDepositItemID = tonumber(itemID)
    self.pendingDepositTargetSlotIndex = tonumber(slotIndex)
    self.pendingDepositPage = self.state.currentPage or 1
    self:ApplyPendingDepositPlacement(categoryId, self.pendingDepositPage, nil)
end

function RB:ApplyPendingDepositPlacement(categoryId, page, rawItems)
    local targetSlotIndex = self.pendingDepositTargetSlotIndex
    local itemID = self.pendingDepositItemID
    if not targetSlotIndex or not itemID or categoryId ~= self.pendingDepositCategory or page ~= (self.pendingDepositPage or 1) then
        return
    end

    if rawItems then
        local itemPresent = false
        for _, item in ipairs(rawItems) do
            if item and item.itemID == itemID then
                itemPresent = true
                break
            end
        end

        if not itemPresent then
            return
        end
    end

    local bucket = self:GetLayoutBucket(categoryId, page)
    local previousSlotIndex = nil
    local displacedItemID = bucket[targetSlotIndex]

    for slotIndex = 1, self.PAGE_SIZE do
        if bucket[slotIndex] == itemID then
            previousSlotIndex = slotIndex
            bucket[slotIndex] = nil
            break
        end
    end

    bucket[targetSlotIndex] = itemID

    if displacedItemID and displacedItemID ~= itemID then
        if previousSlotIndex and previousSlotIndex ~= targetSlotIndex then
            bucket[previousSlotIndex] = displacedItemID
        else
            for slotIndex = 1, self.PAGE_SIZE do
                if slotIndex ~= targetSlotIndex and not bucket[slotIndex] then
                    bucket[slotIndex] = displacedItemID
                    break
                end
            end
        end
    end

    self.pendingDepositItemID = nil
    self.pendingDepositTargetSlotIndex = nil
    self.pendingDepositPage = nil
end

function RB:UpdatePendingBagDragCategory()
    local drag = self.pendingBagDrag
    if not drag or drag.categoryId or not drag.itemID then
        return
    end

    drag.categoryId = self:InferCategoryIdForItem(drag.itemID)
    if not drag.categoryId then
        return
    end

    if self.state.isSearchMode or self.state.currentCategory ~= drag.categoryId or self.state.currentPage ~= 1 then
        self.state.isSearchMode = false
        self.state.currentCategory = drag.categoryId
        self.state.lastCategory = drag.categoryId
        self.state.currentPage = 1
        self:RequestCategory(drag.categoryId, 1)
    end
end

function RB:SetBankDropActive(enabled)
    if not self.frame or not self.frame.slotArea then
        return
    end

    local slotArea = self.frame.slotArea
    if enabled then
        slotArea:SetBackdropBorderColor(1.00, 0.88, 0.20, 1.00)
        slotArea:SetBackdropColor(0.12, 0.10, 0.04, 0.98)
    else
        slotArea:SetBackdropColor(0.06, 0.06, 0.06, 0.98)
        slotArea:SetBackdropBorderColor(0.62, 0.50, 0.15, 0.95)
    end
end

function RB:ClearPendingBagDrag()
    if self.pendingBagDrag and self.pendingBagDrag.targetSlotIndex and self.frame and self.frame.slotButtons then
        local button = self.frame.slotButtons[self.pendingBagDrag.targetSlotIndex]
        if button then
            self:SetSlotDropHighlight(button, false)
        end
    end
    self.pendingBagDrag = nil
    self:SetBankDropActive(false)
end

function RB:TrackBagItemDrag(button)
    if not self:IsShown() or not button then
        return
    end

    local bag, slot = self:GetContainerItemButtonInfo(button)
    if bag == nil or slot == nil then
        return
    end

    local _, itemID, itemCount = self:IsDepositableBagItem(bag, slot)
    if not itemID then
        itemID = getCursorItemID()
    end

    self.pendingBagDrag = {
        bag = bag,
        slot = slot,
        itemID = itemID,
        itemCount = itemCount,
        categoryId = self:InferCategoryIdForItem(itemID),
        targetSlotIndex = nil,
    }
    self:SetBankDropActive(true)

    self:Debug(
        "TrackBagItemDrag: bag=" .. tostring(bag)
        .. ", slot=" .. tostring(slot)
        .. ", itemID=" .. tostring(itemID)
        .. ", categoryId=" .. tostring(self.pendingBagDrag.categoryId),
        true
    )

    if self.pendingBagDrag.categoryId and (self.state.isSearchMode or self.state.currentCategory ~= self.pendingBagDrag.categoryId or self.state.currentPage ~= 1) then
        self.state.isSearchMode = false
        self.state.currentCategory = self.pendingBagDrag.categoryId
        self.state.lastCategory = self.pendingBagDrag.categoryId
        self.state.currentPage = 1
        self:RequestCategory(self.pendingBagDrag.categoryId, 1)
    else
        self:UpdatePendingBagDragCategory()
    end
end

function RB:HandleBankDropTargetEnter(button)
    if self.dragState and self.dragState.kind == "item" then
        self:SetDragHover(button)
        return
    end

    if self.pendingBagDrag and CursorHasItem and CursorHasItem() then
        self:SetBankDropActive(true)
        if button then
            self.pendingBagDrag.targetSlotIndex = button.slotIndex
            self:SetSlotDropHighlight(button, true)
        end
    end
end

function RB:HandleBankDropTargetLeave(button)
    if self.dragState and self.dragState.kind == "item" and self.dragState.hoverButton == button then
        self:SetDragHover(nil)
    end

    if button then
        self:SetSlotDropHighlight(button, false)
        if self.pendingBagDrag and self.pendingBagDrag.targetSlotIndex == button.slotIndex then
            self.pendingBagDrag.targetSlotIndex = nil
        end
    end

    if self.pendingBagDrag and CursorHasItem and CursorHasItem() then
        self:SetBankDropActive(true)
    else
        self:SetBankDropActive(false)
    end
end

function RB:GetSlotIndexUnderCursor()
    if not self.frame or not self.frame.slotButtons then
        return nil
    end

    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale() or 1
    x = x / scale
    y = y / scale

    for _, button in ipairs(self.frame.slotButtons) do
        if button and button:IsShown() then
            local left = button:GetLeft()
            local right = button:GetRight()
            local top = button:GetTop()
            local bottom = button:GetBottom()
            if left and right and top and bottom and x >= left and x <= right and y >= bottom and y <= top then
                return button.slotIndex
            end
        end
    end

    return nil
end

function RB:GetPendingBagDragTargetSlotIndex()
    local drag = self.pendingBagDrag
    if not drag then
        return nil
    end

    return self:GetSlotIndexUnderCursor() or drag.targetSlotIndex
end

function RB:TryDepositPendingBagDrag(targetSlotIndex)
    if not self:IsShown() then
        return false
    end

    local drag = self.pendingBagDrag
    if not drag then
        return false
    end

    local bag = tonumber(drag.bag)
    local slot = tonumber(drag.slot)
    if bag == nil or slot == nil then
        self:ClearPendingBagDrag()
        return false
    end

    local itemID = tonumber(drag.itemID)
    local itemCount = tonumber(drag.itemCount)
    local itemName = itemID and GetItemInfo(itemID) or nil
    targetSlotIndex = tonumber(targetSlotIndex) or self:GetPendingBagDragTargetSlotIndex()

    self.pendingDepositCategory = drag.categoryId or (self.state.currentCategory and self.state.currentCategory > 0 and self.state.currentCategory or self.state.lastCategory)
    if self.pendingDepositCategory then
        self.state.isSearchMode = false
        self.state.currentCategory = self.pendingDepositCategory
        self.state.lastCategory = self.pendingDepositCategory
        self.state.currentPage = 1
    end

    self:QueuePendingDepositPlacement(self.pendingDepositCategory, targetSlotIndex, itemID)

    self.state.statusText = itemName and ("Перенесення: " .. itemName .. "...") or "Перенесення предмета..."
    self:Render()

    if ClearCursor then
        ClearCursor()
    end

    self:RequestDepositBagItem(bag, slot, itemID, itemCount)
    self:ClearPendingBagDrag()
    return true
end

function RB:GetContainerItemButtonInfo(button)
    if not button then
        return nil, nil
    end

    local parent = button.GetParent and button:GetParent()
    local bag = parent and parent.GetID and parent:GetID()
    local slot = button.GetID and button:GetID()

    return bag, slot
end

function RB:InstallBagHook()
    if self.bagHookInstalled then
        return
    end

    self.bagHookInstalled = true
    if type(ContainerFrameItemButton_OnDrag) == "function" then
        hooksecurefunc("ContainerFrameItemButton_OnDrag", function(button)
            RB:TrackBagItemDrag(button)
        end)
    end
end

function RB:CreateFrame()
    local frame = CreateFrame("Frame", "ReagentBankUIFrame", UIParent)
    frame:SetSize(getFrameWidth(), getFrameHeight())
    frame:SetPoint("CENTER", 0, 0)
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    frame:Hide()

    table.insert(UISpecialFrames, "ReagentBankUIFrame")

    self.frame = frame

    self:CreateBackdrop(frame)
    self:CreateHeader(frame)
    self:CreateFooter(frame)
    self:CreateSlots(frame)
    self:CreateTabs(frame)
    self:CreateDragVisual()
    self:InstallBagHook()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("CHAT_MSG_WHISPER")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= ADDON_NAME then
            return
        end

        if not ReagentBankUI_DB then
            ReagentBankUI_DB = {}
        end

        ReagentBankUI_DB.layout = ReagentBankUI_DB.layout or {}
        ReagentBankUI_DB.categoryOrder = ReagentBankUI_DB.categoryOrder or {}
        ReagentBankUI_DB.debug = false
        RB.DEBUG = false
        RB:NormalizeCategoryOrder()

        RB:InstallBagHook()

        SLASH_REAGENTBANKUI1 = "/rbank"
        SlashCmdList["REAGENTBANKUI"] = function(msg)
            msg = trim(msg or "")
            RB:Debug("Slash command: '" .. msg .. "'")

            if msg == "debug" then
                RB:SetDebugEnabled(not RB:IsDebugEnabled())
                return
            end

            if msg == "debug on" then
                RB:SetDebugEnabled(true)
                return
            end

            if msg == "debug off" then
                RB:SetDebugEnabled(false)
                return
            end

            if msg == "debug status" then
                RB:Print("Debug status: " .. boolToString(RB:IsDebugEnabled()))
                return
            end

            if msg == "demo" then
                RB:BuildDemoData()
                RB:Show()
                return
            end

            if msg == "hide" then
                RB:Hide()
                return
            end

            if msg == "next" then
                RB:NextPage()
                return
            end

            if msg == "prev" then
                RB:PrevPage()
                return
            end

            if msg == "reload" then
                RB:RequestCategory(RB.state.currentCategory > 0 and RB.state.currentCategory or RB.state.lastCategory or RB.categories[1].id, RB.state.currentPage or 1)
                return
            end

            if msg ~= "" then
                RB:RequestSearch(msg, 1)
                return
            end

            RB:RequestOpen()
        end
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        RB:SendRegistration()
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        RB:Debug("CHAT_MSG_ADDON: prefix=" .. tostring(prefix) .. ", channel=" .. tostring(channel) .. ", sender=" .. tostring(sender) .. ", message=" .. tostring(message))
        if prefix == RB.PREFIX then
            RB:HandleInboundPayload(message)
        end
    elseif event == "CHAT_MSG_WHISPER" then
        local message, sender = ...
        RB:Debug("CHAT_MSG_WHISPER: sender=" .. tostring(sender) .. ", message=" .. tostring(message))
        if type(message) == "string" and string.sub(message, 1, string.len(RB.PREFIX) + 1) == (RB.PREFIX .. "\t") then
            RB:HandleInboundPayload(message)
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if RB.frame and RB.frame:IsShown() then
            RB:Render()
        end
    end
end)
