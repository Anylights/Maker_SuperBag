-- ============================================================================
-- 背包UI渲染模块
-- NanoVG绘制、拖拽交互、放置预览、石板高亮、属性面板
-- ============================================================================

local Data = require("inventory_data")
local Inv = require("inventory")

local UI = {}

-- ============================================================================
-- UI 状态
-- ============================================================================
UI.isOpen = false             -- 背包是否打开
UI.dragItem = nil             -- 当前拖拽的物品
UI.dragOffsetX = 0            -- 拖拽偏移(鼠标相对物品左上角)
UI.dragOffsetY = 0
UI.hoverItem = nil            -- 鼠标悬停的物品
UI.hoverCol = 0               -- 鼠标悬停的格子坐标
UI.hoverRow = 0
UI.selectedPendingIndex = 0   -- 待放入列表选中索引
UI.animAlpha = 0              -- 打开/关闭动画alpha
UI.onDiscardItem = nil        -- 丢弃回调: function(item) → 由main.lua设置

-- 布局参数(在Draw中根据屏幕尺寸动态计算)
local gridOriginX = 0         -- 格子区域左上角屏幕坐标
local gridOriginY = 0
local cellSize = Data.CELL_SIZE
local pendingAreaX = 0
local pendingAreaY = 0
local statsAreaX = 0
local statsAreaY = 0
local panelX_ = 0             -- 面板边界(用于丢弃判定)
local panelY_ = 0
local panelW_ = 0
local panelH_ = 0

-- ============================================================================
-- 打开/关闭
-- ============================================================================
function UI.Toggle()
    UI.isOpen = not UI.isOpen
    UI.dragItem = nil
    UI.hoverItem = nil
    UI.selectedPendingIndex = 0

    if UI.isOpen then
        UI.animAlpha = 0
    end
end

function UI.Open()
    if not UI.isOpen then
        UI.isOpen = true
        UI.dragItem = nil
        UI.animAlpha = 0
    end
end

function UI.Close()
    if UI.isOpen then
        UI.isOpen = false
        UI.dragItem = nil
    end
end

-- ============================================================================
-- 输入处理 (在主循环中调用)
-- ============================================================================

--- 处理鼠标按下, 返回true表示事件被背包UI消费
function UI.HandleMouseDown(mx, my, button)
    if not UI.isOpen then return false end

    if button == MOUSEB_LEFT then
        -- 检查是否点击了格子中的物品
        local col, row = UI.ScreenToGrid(mx, my)
        if col >= 1 and col <= Inv.cols and row >= 1 and row <= Inv.rows then
            local item = Inv.GetItemAt(col, row)
            if item then
                -- 开始拖拽
                UI.dragItem = item
                local itemX = gridOriginX + (item.gridCol - 1) * cellSize
                local itemY = gridOriginY + (item.gridRow - 1) * cellSize
                UI.dragOffsetX = mx - itemX
                UI.dragOffsetY = my - itemY
                -- 从格子中移除(拖起来)
                Inv.RemoveItem(item)
                return true
            end
        end

        -- 检查是否点击了待放入列表中的物品
        local pendingIdx = UI.GetPendingItemAt(mx, my)
        if pendingIdx > 0 then
            local item = Inv.pendingItems[pendingIdx]
            UI.dragItem = item
            -- 从待放入列表移除以开始拖拽
            table.remove(Inv.pendingItems, pendingIdx)
            local w, h = Inv.GetItemSize(item)
            UI.dragOffsetX = w * cellSize / 2
            UI.dragOffsetY = h * cellSize / 2
            return true
        end

        return true  -- 消费点击(防止背包界面下面的射击)
    end

    if button == MOUSEB_RIGHT then
        -- 右键旋转拖拽中的物品
        if UI.dragItem then
            if UI.dragItem.sizeW ~= UI.dragItem.sizeH then
                UI.dragItem.rotated = not UI.dragItem.rotated
                -- 交换拖拽偏移以保持视觉居中
                UI.dragOffsetX, UI.dragOffsetY = UI.dragOffsetY, UI.dragOffsetX
            end
            return true
        end
        return true
    end

    return true
end

--- 处理鼠标释放
function UI.HandleMouseUp(mx, my, button)
    if not UI.isOpen then return false end

    if button == MOUSEB_LEFT and UI.dragItem then
        local item = UI.dragItem
        UI.dragItem = nil

        -- 尝试放置到格子
        local col, row = UI.ScreenToGrid(mx, my)

        -- 用物品中心点对齐到格子
        local w, h = Inv.GetItemSize(item)
        local centerOffCol = math.floor(UI.dragOffsetX / cellSize)
        local centerOffRow = math.floor(UI.dragOffsetY / cellSize)
        local placeCol = col - centerOffCol
        local placeRow = row - centerOffRow

        if Inv.CanPlace(item, placeCol, placeRow) then
            Inv.PlaceItem(item, placeCol, placeRow)
        else
            -- 检查鼠标是否在面板外 → 丢弃物品
            local outsidePanel = mx < panelX_ or mx > panelX_ + panelW_
                              or my < panelY_ or my > panelY_ + panelH_ + 60
            if outsidePanel then
                -- 丢弃: 从背包移除并通知主模块
                Inv.DiscardItem(item)
                if UI.onDiscardItem then
                    UI.onDiscardItem(item)
                end
            else
                -- 面板内但放不下 → 加回待放入列表
                Inv.AddPendingItem(item)
            end
        end

        return true
    end

    return true
end

--- 处理按键, 返回true表示事件被消费
function UI.HandleKeyDown(key)
    if not UI.isOpen then return false end

    if key == KEY_R and UI.dragItem then
        -- R键旋转拖拽中的物品
        if UI.dragItem.sizeW ~= UI.dragItem.sizeH then
            UI.dragItem.rotated = not UI.dragItem.rotated
            UI.dragOffsetX, UI.dragOffsetY = UI.dragOffsetY, UI.dragOffsetX
        end
        return true
    end

    return false
end

-- ============================================================================
-- 坐标转换
-- ============================================================================

--- 屏幕坐标转格子坐标
function UI.ScreenToGrid(mx, my)
    local col = math.floor((mx - gridOriginX) / cellSize) + 1
    local row = math.floor((my - gridOriginY) / cellSize) + 1
    return col, row
end

--- 格子坐标转屏幕坐标(左上角)
function UI.GridToScreen(col, row)
    return gridOriginX + (col - 1) * cellSize, gridOriginY + (row - 1) * cellSize
end

--- 检查鼠标是否在待放入列表的物品上, 返回索引(0=无)
function UI.GetPendingItemAt(mx, my)
    local x = pendingAreaX
    local y = pendingAreaY + 28  -- 标题高度

    for i, item in ipairs(Inv.pendingItems) do
        local w, h = Inv.GetItemSize(item)
        local pw = w * cellSize * 0.6  -- 缩小显示
        local ph = h * cellSize * 0.6

        if mx >= x and mx <= x + pw and my >= y and my <= y + ph then
            return i
        end

        y = y + ph + 4
        if y > pendingAreaY + 300 then break end  -- 限制显示数量
    end

    return 0
end

-- ============================================================================
-- NanoVG 渲染
-- ============================================================================

--- 主绘制函数(在NanoVGRender事件中调用, 屏幕空间)
function UI.Draw(nvg, logicalW, logicalH, mouseX, mouseY)
    if not UI.isOpen then return end

    -- 打开动画
    UI.animAlpha = math.min(1.0, UI.animAlpha + 0.08)
    local alpha = UI.animAlpha

    -- 计算布局
    local gridW = Inv.cols * cellSize
    local gridH = Inv.rows * cellSize
    local panelW = gridW + 240  -- 格子 + 右侧属性面板
    local panelH = math.max(gridH + 80, 380)

    -- 面板居中
    local panelX = (logicalW - panelW) / 2
    local panelY = (logicalH - panelH) / 2

    -- 保存面板边界(供丢弃判定使用)
    panelX_ = panelX
    panelY_ = panelY
    panelW_ = panelW
    panelH_ = panelH

    -- 格子区域
    gridOriginX = panelX + 16
    gridOriginY = panelY + 50

    -- 属性面板区域
    statsAreaX = gridOriginX + gridW + 16
    statsAreaY = gridOriginY

    -- 待放入物品区域(格子下方)
    pendingAreaX = gridOriginX
    pendingAreaY = gridOriginY + gridH + 12

    -- 更新悬停状态
    UI.hoverCol, UI.hoverRow = UI.ScreenToGrid(mouseX, mouseY)
    UI.hoverItem = nil
    if UI.hoverCol >= 1 and UI.hoverCol <= Inv.cols and
       UI.hoverRow >= 1 and UI.hoverRow <= Inv.rows then
        UI.hoverItem = Inv.GetItemAt(UI.hoverCol, UI.hoverRow)
    end

    -- === 1. 半透明遮罩 ===
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, logicalW, logicalH)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(140 * alpha)))
    nvgFill(nvg)

    -- === 2. 主面板 ===
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, panelX, panelY, panelW, panelH, 8)
    nvgFillColor(nvg, nvgRGBA(25, 28, 38, math.floor(240 * alpha)))
    nvgFill(nvg)
    nvgStrokeColor(nvg, nvgRGBA(80, 90, 120, math.floor(180 * alpha)))
    nvgStrokeWidth(nvg, 1.5)
    nvgStroke(nvg)

    -- === 3. 标题 ===
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 17)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(220, 220, 240, math.floor(255 * alpha)))
    nvgText(nvg, panelX + 16, panelY + 25, "背包", nil)

    -- 背包容量提示
    local placedCount = #Inv.items
    nvgFontSize(nvg, 11)
    nvgFillColor(nvg, nvgRGBA(160, 160, 180, math.floor(200 * alpha)))
    nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgText(nvg, panelX + panelW - 16, panelY + 25,
        Inv.cols .. "×" .. Inv.rows .. "  物品: " .. placedCount, nil)

    -- === 4. 绘制格子 ===
    UI.DrawGrid(nvg, alpha)

    -- === 5. 绘制已放置的物品 ===
    UI.DrawPlacedItems(nvg, alpha)

    -- === 6. 石板高亮 ===
    UI.DrawTabletHighlights(nvg, alpha)

    -- === 7. 拖拽预览 ===
    if UI.dragItem then
        UI.DrawDragPreview(nvg, mouseX, mouseY, alpha)
    end

    -- === 8. 悬停提示 ===
    if UI.hoverItem and not UI.dragItem then
        UI.DrawItemTooltip(nvg, UI.hoverItem, mouseX, mouseY, logicalW, logicalH, alpha)
    end

    -- === 9. 属性面板 ===
    UI.DrawStatsPanel(nvg, alpha)

    -- === 10. 激活的Combo ===
    UI.DrawCombos(nvg, alpha)

    -- === 11. 待放入物品 ===
    UI.DrawPendingItems(nvg, alpha)

    -- === 12. 操作提示 ===
    nvgFontSize(nvg, 9)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(nvg, nvgRGBA(140, 140, 160, math.floor(160 * alpha)))
    nvgText(nvg, logicalW / 2, logicalH - 10,
        "拖拽放置 | 右键/R旋转 | 拖出面板丢弃 | Tab关闭背包", nil)
end

-- ============================================================================
-- 子绘制函数
-- ============================================================================

function UI.DrawGrid(nvg, alpha)
    for r = 1, Inv.rows do
        for c = 1, Inv.cols do
            local x = gridOriginX + (c - 1) * cellSize
            local y = gridOriginY + (r - 1) * cellSize

            -- 格子背景
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, x + 1, y + 1, cellSize - 2, cellSize - 2, 3)

            local isHover = (c == UI.hoverCol and r == UI.hoverRow and not UI.dragItem)
            if Inv.grid[r][c] then
                nvgFillColor(nvg, nvgRGBA(50, 55, 65, math.floor(200 * alpha)))
            elseif isHover then
                nvgFillColor(nvg, nvgRGBA(60, 65, 80, math.floor(200 * alpha)))
            else
                nvgFillColor(nvg, nvgRGBA(38, 42, 52, math.floor(200 * alpha)))
            end
            nvgFill(nvg)

            -- 格子边框
            nvgStrokeColor(nvg, nvgRGBA(60, 65, 80, math.floor(120 * alpha)))
            nvgStrokeWidth(nvg, 0.5)
            nvgStroke(nvg)
        end
    end
end

function UI.DrawPlacedItems(nvg, alpha)
    -- 收集已绘制的物品(避免同一物品重复绘制)
    local drawn = {}

    for _, item in ipairs(Inv.items) do
        if item.placed and not drawn[item] then
            drawn[item] = true
            UI.DrawItem(nvg, item, gridOriginX + (item.gridCol - 1) * cellSize,
                gridOriginY + (item.gridRow - 1) * cellSize, 1.0, alpha)
        end
    end
end

function UI.DrawItem(nvg, item, x, y, scale, alpha)
    local w, h = Inv.GetItemSize(item)
    local pw = w * cellSize * scale
    local ph = h * cellSize * scale

    -- 稀有度背景色
    local bgCol = Data.RARITY_BG_COLORS[item.rarity] or {40, 40, 40}
    local rarityCol = Data.RARITY_COLORS[item.rarity] or {200, 200, 200}

    -- 物品背景
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x + 2, y + 2, pw - 4, ph - 4, 4)
    nvgFillColor(nvg, nvgRGBA(bgCol[1] + 20, bgCol[2] + 20, bgCol[3] + 20, math.floor(220 * alpha)))
    nvgFill(nvg)

    -- 稀有度边框
    nvgStrokeColor(nvg, nvgRGBA(rarityCol[1], rarityCol[2], rarityCol[3], math.floor(200 * alpha)))
    nvgStrokeWidth(nvg, 1.5)
    nvgStroke(nvg)

    -- 物品图标(简化: 用文字代替)
    nvgFontFace(nvg, "sans")

    if item.type == "tablet" then
        -- 石板用特殊标记
        local tmplColor = item.template.color or {200, 200, 200}
        nvgFontSize(nvg, 14 * scale)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(tmplColor[1], tmplColor[2], tmplColor[3], math.floor(255 * alpha)))
        nvgText(nvg, x + pw / 2, y + ph / 2 - 4 * scale, "◆", nil)

        -- 石板名称(小字)
        nvgFontSize(nvg, 8 * scale)
        nvgFillColor(nvg, nvgRGBA(200, 200, 220, math.floor(200 * alpha)))
        nvgText(nvg, x + pw / 2, y + ph / 2 + 10 * scale, item.name, nil)
    else
        -- 圣物: 显示图标文字 + 名称
        nvgFontSize(nvg, 9 * scale)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(rarityCol[1], rarityCol[2], rarityCol[3], math.floor(255 * alpha)))

        -- 名称
        local displayName = item.name
        if #displayName > 4 and w == 1 then
            displayName = string.sub(displayName, 1, 6) -- UTF8 可能截断, 简化处理
        end
        nvgText(nvg, x + pw / 2, y + ph / 2 - 2 * scale, displayName, nil)

        -- 等级标记
        if item.level and item.level > 1 then
            nvgFontSize(nvg, 8 * scale)
            nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
            nvgFillColor(nvg, nvgRGBA(255, 220, 80, math.floor(220 * alpha)))
            nvgText(nvg, x + pw - 4, y + ph - 3, "Lv" .. item.level, nil)
        end

        -- 标签小圆点(左下角)
        if item.tags then
            local dotX = x + 6
            local dotY = y + ph - 7
            for ti = 1, math.min(3, #item.tags) do
                local tagCol = Data.TAG_COLORS[item.tags[ti]] or {180, 180, 180}
                nvgBeginPath(nvg)
                nvgCircle(nvg, dotX, dotY, 2.5 * scale)
                nvgFillColor(nvg, nvgRGBA(tagCol[1], tagCol[2], tagCol[3], math.floor(220 * alpha)))
                nvgFill(nvg)
                dotX = dotX + 7 * scale
            end
        end
    end
end

function UI.DrawTabletHighlights(nvg, alpha)
    -- 高亮所有石板影响的格子
    for _, item in ipairs(Inv.items) do
        if item.type == "tablet" and item.placed then
            local cells = Inv.GetTabletAffectedCells(item)
            local tmplColor = item.template.color or {200, 200, 200}

            for _, cell in ipairs(cells) do
                local x = gridOriginX + (cell.col - 1) * cellSize
                local y = gridOriginY + (cell.row - 1) * cellSize

                -- 半透明高亮
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, x + 1, y + 1, cellSize - 2, cellSize - 2, 3)
                nvgFillColor(nvg, nvgRGBA(tmplColor[1], tmplColor[2], tmplColor[3], math.floor(25 * alpha)))
                nvgFill(nvg)

                -- 发光边框
                nvgStrokeColor(nvg, nvgRGBA(tmplColor[1], tmplColor[2], tmplColor[3], math.floor(60 * alpha)))
                nvgStrokeWidth(nvg, 1)
                nvgStroke(nvg)
            end
        end
    end
end

function UI.DrawDragPreview(nvg, mouseX, mouseY, alpha)
    local item = UI.dragItem
    local w, h = Inv.GetItemSize(item)

    -- 计算目标格子位置
    local col, row = UI.ScreenToGrid(mouseX, mouseY)
    local centerOffCol = math.floor(UI.dragOffsetX / cellSize)
    local centerOffRow = math.floor(UI.dragOffsetY / cellSize)
    local placeCol = col - centerOffCol
    local placeRow = row - centerOffRow

    -- 放置预览(绿色可放/红色冲突)
    local canPlace = Inv.CanPlace(item, placeCol, placeRow)

    if placeCol >= 1 and placeRow >= 1 and
       placeCol + w - 1 <= Inv.cols and placeRow + h - 1 <= Inv.rows then
        for r = placeRow, placeRow + h - 1 do
            for c = placeCol, placeCol + w - 1 do
                local x = gridOriginX + (c - 1) * cellSize
                local y = gridOriginY + (r - 1) * cellSize

                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, x + 1, y + 1, cellSize - 2, cellSize - 2, 3)
                if canPlace then
                    nvgFillColor(nvg, nvgRGBA(60, 200, 80, math.floor(60 * alpha)))
                    nvgStrokeColor(nvg, nvgRGBA(60, 200, 80, math.floor(150 * alpha)))
                else
                    nvgFillColor(nvg, nvgRGBA(220, 60, 60, math.floor(60 * alpha)))
                    nvgStrokeColor(nvg, nvgRGBA(220, 60, 60, math.floor(150 * alpha)))
                end
                nvgFill(nvg)
                nvgStrokeWidth(nvg, 1.5)
                nvgStroke(nvg)
            end
        end
    end

    -- 检测是否在面板外(丢弃区域)
    local outsidePanel = mouseX < panelX_ or mouseX > panelX_ + panelW_
                      or mouseY < panelY_ or mouseY > panelY_ + panelH_ + 60

    -- 跟随鼠标的物品(半透明)
    local drawX = mouseX - UI.dragOffsetX
    local drawY = mouseY - UI.dragOffsetY
    nvgSave(nvg)
    if outsidePanel then
        nvgGlobalAlpha(nvg, 0.4)
    else
        nvgGlobalAlpha(nvg, 0.75)
    end
    UI.DrawItem(nvg, item, drawX, drawY, 1.0, alpha)
    nvgRestore(nvg)

    -- 面板外: 显示丢弃提示
    if outsidePanel then
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, 10)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(nvg, nvgRGBA(255, 80, 80, math.floor(220 * alpha)))
        nvgText(nvg, mouseX, mouseY + h * cellSize / 2 + 4, "松开丢弃", nil)
    end
end

function UI.DrawItemTooltip(nvg, item, mx, my, logicalW, logicalH, alpha)
    local tipW = 200
    local tipH = 120

    -- 根据物品类型调整高度
    if item.type == "artifact" then
        tipH = 140 + (#item.tags * 14)
    end

    -- 确保不超出屏幕
    local tipX = mx + 16
    local tipY = my - 10
    if tipX + tipW > logicalW - 10 then tipX = mx - tipW - 10 end
    if tipY + tipH > logicalH - 10 then tipY = logicalH - tipH - 10 end
    if tipY < 10 then tipY = 10 end

    -- 背景
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, tipX, tipY, tipW, tipH, 6)
    nvgFillColor(nvg, nvgRGBA(20, 22, 30, math.floor(240 * alpha)))
    nvgFill(nvg)

    local rarityCol = Data.RARITY_COLORS[item.rarity] or {200, 200, 200}
    nvgStrokeColor(nvg, nvgRGBA(rarityCol[1], rarityCol[2], rarityCol[3], math.floor(180 * alpha)))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)

    -- 名称
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 13)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(nvg, nvgRGBA(rarityCol[1], rarityCol[2], rarityCol[3], math.floor(255 * alpha)))
    nvgText(nvg, tipX + 10, tipY + 8, item.name, nil)

    -- 稀有度
    nvgFontSize(nvg, 9)
    nvgFillColor(nvg, nvgRGBA(160, 160, 180, math.floor(200 * alpha)))
    local sizeStr = item.sizeW .. "×" .. item.sizeH
    local rarityName = Data.RARITY_NAMES[item.rarity] or ""
    nvgText(nvg, tipX + 10, tipY + 28, rarityName .. " | " .. sizeStr, nil)

    local yOff = tipY + 48

    if item.type == "artifact" then
        -- 等级
        if item.level then
            nvgFillColor(nvg, nvgRGBA(255, 220, 80, math.floor(220 * alpha)))
            nvgText(nvg, tipX + 10, yOff, "Lv." .. item.level, nil)
            yOff = yOff + 16
        end

        -- 描述
        local tmpl = item.template
        if tmpl and tmpl.desc then
            nvgFillColor(nvg, nvgRGBA(200, 200, 220, math.floor(200 * alpha)))
            nvgFontSize(nvg, 9)
            nvgText(nvg, tipX + 10, yOff, tmpl.desc, nil)
            yOff = yOff + 18
        end

        -- 标签
        if item.tags and #item.tags > 0 then
            nvgFontSize(nvg, 9)
            for _, tag in ipairs(item.tags) do
                local tagCol = Data.TAG_COLORS[tag] or {180, 180, 180}
                local tagName = Data.TAGS[tag] or tag
                nvgFillColor(nvg, nvgRGBA(tagCol[1], tagCol[2], tagCol[3], math.floor(220 * alpha)))
                nvgText(nvg, tipX + 10, yOff, "● " .. tagName, nil)
                yOff = yOff + 14
            end
        end
    elseif item.type == "tablet" then
        local tmpl = item.template
        -- 范围类型
        local mask = Data.TABLET_MASKS[item.maskType]
        if mask then
            nvgFillColor(nvg, nvgRGBA(180, 180, 200, math.floor(200 * alpha)))
            nvgText(nvg, tipX + 10, yOff, "范围: " .. mask.name, nil)
            yOff = yOff + 16
        end

        -- 描述
        if tmpl.desc then
            nvgFillColor(nvg, nvgRGBA(200, 200, 220, math.floor(200 * alpha)))
            nvgFontSize(nvg, 9)
            nvgText(nvg, tipX + 10, yOff, tmpl.desc, nil)
            yOff = yOff + 16
        end

        -- 负面效果
        if tmpl.penaltyStats then
            nvgFillColor(nvg, nvgRGBA(255, 80, 80, math.floor(220 * alpha)))
            nvgFontSize(nvg, 9)
            for k, v in pairs(tmpl.penaltyStats) do
                nvgText(nvg, tipX + 10, yOff, "负面: " .. k .. " " .. v, nil)
                yOff = yOff + 14
            end
        end
    end
end

function UI.DrawStatsPanel(nvg, alpha)
    local x = statsAreaX
    local y = statsAreaY

    -- 面板标题
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 12)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(nvg, nvgRGBA(200, 200, 220, math.floor(240 * alpha)))
    nvgText(nvg, x, y, "装备加成", nil)

    y = y + 22

    local statLines = Inv.GetStatSummary()
    if #statLines == 0 then
        nvgFontSize(nvg, 9)
        nvgFillColor(nvg, nvgRGBA(120, 120, 140, math.floor(160 * alpha)))
        nvgText(nvg, x, y, "放入圣物以获得加成", nil)
        return
    end

    nvgFontSize(nvg, 9)
    for _, line in ipairs(statLines) do
        -- 属性名
        nvgFillColor(nvg, nvgRGBA(160, 160, 180, math.floor(200 * alpha)))
        nvgText(nvg, x, y, line.name, nil)

        -- 属性值(正=绿, 负=红)
        nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        if line.positive then
            nvgFillColor(nvg, nvgRGBA(80, 220, 80, math.floor(240 * alpha)))
        else
            nvgFillColor(nvg, nvgRGBA(220, 80, 80, math.floor(240 * alpha)))
        end
        nvgText(nvg, x + 190, y, line.text, nil)
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

        y = y + 16
    end
end

function UI.DrawCombos(nvg, alpha)
    local x = statsAreaX
    local y = statsAreaY + 180

    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 12)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(nvg, nvgRGBA(200, 200, 220, math.floor(240 * alpha)))
    nvgText(nvg, x, y, "Combo", nil)
    y = y + 20

    if #Inv.activeCombos == 0 then
        nvgFontSize(nvg, 9)
        nvgFillColor(nvg, nvgRGBA(120, 120, 140, math.floor(160 * alpha)))
        nvgText(nvg, x, y, "集齐同类标签激活", nil)
        return
    end

    nvgFontSize(nvg, 9)
    for _, ac in ipairs(Inv.activeCombos) do
        local tagCol = Data.TAG_COLORS[ac.combo.tag] or {200, 200, 200}

        -- Combo名称 + 等级
        nvgFillColor(nvg, nvgRGBA(tagCol[1], tagCol[2], tagCol[3], math.floor(240 * alpha)))
        nvgText(nvg, x, y, ac.combo.name .. " Lv" .. ac.level, nil)
        y = y + 14

        -- 效果描述
        nvgFillColor(nvg, nvgRGBA(180, 180, 200, math.floor(180 * alpha)))
        nvgFontSize(nvg, 9)
        nvgText(nvg, x + 8, y, ac.effect.desc, nil)
        nvgFontSize(nvg, 9)
        y = y + 16
    end
end

function UI.DrawPendingItems(nvg, alpha)
    if #Inv.pendingItems == 0 then return end

    local x = pendingAreaX
    local y = pendingAreaY

    -- 标题
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 11)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(nvg, nvgRGBA(255, 200, 80, math.floor(240 * alpha)))
    nvgText(nvg, x, y, "待放入 (" .. #Inv.pendingItems .. ")", nil)
    y = y + 20

    -- 横排显示
    local drawX = x
    for i, item in ipairs(Inv.pendingItems) do
        local w, h = Inv.GetItemSize(item)
        local pw = w * cellSize * 0.6
        local ph = h * cellSize * 0.6

        -- 缩小绘制
        nvgSave(nvg)
        UI.DrawItem(nvg, item, drawX, y, 0.6, alpha)
        nvgRestore(nvg)

        drawX = drawX + pw + 6
        if drawX > gridOriginX + Inv.cols * cellSize - 40 then
            drawX = x
            y = y + ph + 6
        end

        if i >= 10 then break end  -- 最多显示10个
    end
end

return UI
