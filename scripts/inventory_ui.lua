-- ============================================================================
-- 背包UI渲染模块
-- NanoVG绘制、俄罗斯方块拖拽、行列完成发光、属性面板
-- 拾取物品在面板左侧显示，可拖入背包；从背包拖出放入拾取区
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
UI.dragSource = nil           -- 拖拽来源: "grid" | "pickup"
UI.dragLootRef = nil          -- 若来自pickup, 对应的lootItem引用
UI.hoverItem = nil            -- 鼠标悬停的物品
UI.hoverCol = 0               -- 鼠标悬停的格子坐标
UI.hoverRow = 0
UI.animAlpha = 0              -- 打开/关闭动画alpha
UI.glowTimer = 0              -- 完成行列发光脉冲计时
UI.onDiscardItem = nil        -- 丢弃回调: function(item) → 由main.lua设置
UI.onPickupPlaced = nil       -- 拾取物品放入背包回调: function(lootRef) → main.lua从lootItems移除

-- 拾取物品列表: { {item=inventoryItem, lootRef=lootItemRef}, ... }
UI.pickupItems = {}

-- 布局参数(在Draw中根据屏幕尺寸动态计算)
local gridOriginX = 0
local gridOriginY = 0
local cellSize = Data.CELL_SIZE
local statsAreaX = 0
local statsAreaY = 0
local panelX_ = 0
local panelY_ = 0
local panelW_ = 0
local panelH_ = 0
local pickupAreaX_ = 0
local pickupAreaY_ = 0

-- ============================================================================
-- 打开/关闭
-- ============================================================================
function UI.Toggle()
    if UI.isOpen then
        UI.Close()
    else
        UI.Open()
    end
end

function UI.Open()
    if not UI.isOpen then
        UI.isOpen = true
        UI.dragItem = nil
        UI.dragSource = nil
        UI.dragLootRef = nil
        UI.animAlpha = 0
    end
end

function UI.Close()
    if UI.isOpen then
        UI.isOpen = false
        UI.dragItem = nil
        UI.dragSource = nil
        UI.dragLootRef = nil
        -- 关闭背包时, 从格子拖出但未放回的物品(lootRef==nil)丢到地面
        for i = #UI.pickupItems, 1, -1 do
            local entry = UI.pickupItems[i]
            if entry.lootRef == nil and UI.onDiscardItem then
                UI.onDiscardItem(entry.item)
            end
        end
        UI.pickupItems = {}
    end
end

--- 设置可拾取物品(由main.lua在按F时调用)
function UI.SetPickupItems(items)
    UI.pickupItems = items or {}
end

--- 添加单个物品到拾取区
function UI.AddToPickup(item, lootRef)
    table.insert(UI.pickupItems, {item = item, lootRef = lootRef})
end

--- 从拾取列表移除指定索引
function UI.RemovePickupAt(index)
    if index >= 1 and index <= #UI.pickupItems then
        table.remove(UI.pickupItems, index)
    end
end

-- ============================================================================
-- 输入处理
-- ============================================================================

function UI.HandleMouseDown(mx, my, button)
    if not UI.isOpen then return false end

    if button == MOUSEB_LEFT then
        -- 检查是否点击了格子中的物品
        local col, row = UI.ScreenToGrid(mx, my)
        if col >= 1 and col <= Inv.cols and row >= 1 and row <= Inv.rows then
            local item = Inv.GetItemAt(col, row)
            if item then
                -- 开始拖拽(从格子)
                UI.dragItem = item
                UI.dragSource = "grid"
                UI.dragLootRef = nil
                local itemX = gridOriginX + (item.gridCol - 1) * cellSize
                local itemY = gridOriginY + (item.gridRow - 1) * cellSize
                UI.dragOffsetX = mx - itemX
                UI.dragOffsetY = my - itemY
                Inv.RemoveItem(item)
                return true
            end
        end

        -- 检查是否点击了拾取区的物品
        local pickupIdx = UI.GetPickupItemAt(mx, my)
        if pickupIdx > 0 then
            local entry = UI.pickupItems[pickupIdx]
            UI.dragItem = entry.item
            UI.dragSource = "pickup"
            UI.dragLootRef = entry.lootRef
            table.remove(UI.pickupItems, pickupIdx)
            local w, h = Inv.GetItemBounds(entry.item)
            UI.dragOffsetX = w * cellSize / 2
            UI.dragOffsetY = h * cellSize / 2
            return true
        end

        return true
    end

    if button == MOUSEB_RIGHT then
        if UI.dragItem then
            Inv.RotateItem(UI.dragItem)
            -- 交换拖拽偏移以保持视觉居中
            UI.dragOffsetX, UI.dragOffsetY = UI.dragOffsetY, UI.dragOffsetX
            return true
        end
        return true
    end

    return true
end

function UI.HandleMouseUp(mx, my, button)
    if not UI.isOpen then return false end

    if button == MOUSEB_LEFT and UI.dragItem then
        local item = UI.dragItem
        local source = UI.dragSource
        local lootRef = UI.dragLootRef
        UI.dragItem = nil
        UI.dragSource = nil
        UI.dragLootRef = nil

        -- 尝试放置到格子
        local col, row = UI.ScreenToGrid(mx, my)
        local w, h = Inv.GetItemBounds(item)
        local centerOffCol = math.floor(UI.dragOffsetX / cellSize)
        local centerOffRow = math.floor(UI.dragOffsetY / cellSize)
        local placeCol = col - centerOffCol
        local placeRow = row - centerOffRow

        if Inv.CanPlace(item, placeCol, placeRow) then
            Inv.PlaceItem(item, placeCol, placeRow)
            if source == "pickup" and lootRef and UI.onPickupPlaced then
                UI.onPickupPlaced(lootRef)
            end
        else
            local outsidePanel = mx < panelX_ or mx > panelX_ + panelW_
                              or my < panelY_ or my > panelY_ + panelH_
            if outsidePanel then
                if source == "pickup" then
                    UI.AddToPickup(item, lootRef)
                else
                    -- 从格子拖出面板外: 放入拾取区(lootRef=nil, 关闭背包时丢弃)
                    UI.AddToPickup(item, nil)
                end
            else
                local returnLootRef = lootRef
                if source == "grid" then
                    returnLootRef = nil
                end
                UI.AddToPickup(item, returnLootRef)
            end
        end

        return true
    end

    return true
end

function UI.HandleKeyDown(key)
    if not UI.isOpen then return false end

    if key == KEY_R and UI.dragItem then
        Inv.RotateItem(UI.dragItem)
        UI.dragOffsetX, UI.dragOffsetY = UI.dragOffsetY, UI.dragOffsetX
        return true
    end

    return false
end

-- ============================================================================
-- 坐标转换
-- ============================================================================

function UI.ScreenToGrid(mx, my)
    local col = math.floor((mx - gridOriginX) / cellSize) + 1
    local row = math.floor((my - gridOriginY) / cellSize) + 1
    return col, row
end

function UI.GridToScreen(col, row)
    return gridOriginX + (col - 1) * cellSize, gridOriginY + (row - 1) * cellSize
end

function UI.GetPickupItemAt(mx, my)
    local x = pickupAreaX_
    local y = pickupAreaY_

    for i, entry in ipairs(UI.pickupItems) do
        local item = entry.item
        local w, h = Inv.GetItemBounds(item)
        local pw = w * cellSize
        local ph = h * cellSize

        if mx >= x and mx <= x + pw and my >= y and my <= y + ph then
            return i
        end

        y = y + ph + 6
    end

    return 0
end

-- ============================================================================
-- NanoVG 渲染
-- ============================================================================

function UI.Draw(nvg, logicalW, logicalH, mouseX, mouseY)
    if not UI.isOpen then return end

    -- 打开动画 & 发光脉冲计时
    UI.animAlpha = math.min(1.0, UI.animAlpha + 0.08)
    UI.glowTimer = UI.glowTimer + 0.02
    local alpha = UI.animAlpha

    -- 推进环绕扫光动画进度
    for _, anim in ipairs(Inv.lineAnims) do
        if not anim.done then
            anim.progress = anim.progress + 0.025  -- ~40帧完成环绕(约0.67秒)
            if anim.progress >= 1.0 then
                anim.progress = 1.0
                anim.done = true
            end
        end
    end

    -- 计算布局
    local gridW = Inv.cols * cellSize
    local gridH = Inv.rows * cellSize
    local panelW = gridW + 240
    local panelH = gridH + 60

    local panelX = (logicalW - panelW) / 2
    local panelY = (logicalH - panelH) / 2

    panelX_ = panelX
    panelY_ = panelY
    panelW_ = panelW
    panelH_ = panelH

    gridOriginX = panelX + 16
    gridOriginY = panelY + 50

    statsAreaX = gridOriginX + gridW + 16
    statsAreaY = gridOriginY

    pickupAreaX_ = panelX - cellSize * 2.5 - 16
    pickupAreaY_ = panelY + 50

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
    nvgFontSize(nvg, 18)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(220, 220, 240, math.floor(255 * alpha)))
    nvgText(nvg, panelX + 16, panelY + 25, "背包", nil)

    local placedCount = #Inv.items
    nvgFontSize(nvg, 12)
    nvgFillColor(nvg, nvgRGBA(160, 160, 180, math.floor(200 * alpha)))
    nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    local completedR, completedC = 0, 0
    for _ in pairs(Inv.completedRows) do completedR = completedR + 1 end
    for _ in pairs(Inv.completedCols) do completedC = completedC + 1 end
    local infoText = Inv.cols .. "×" .. Inv.rows .. "  物品:" .. placedCount
    if completedR + completedC > 0 then
        infoText = infoText .. "  完成行列:" .. (completedR + completedC)
    end
    nvgText(nvg, panelX + panelW - 16, panelY + 25, infoText, nil)

    -- === 4. 绘制格子 ===
    UI.DrawGrid(nvg, alpha)

    -- === 5. 完成行列发光(在物品下方绘制) ===
    UI.DrawCompletedLineGlow(nvg, alpha)

    -- === 6. 绘制已放置的物品 ===
    UI.DrawPlacedItems(nvg, alpha)

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

    -- === 11. 拾取区物品(面板左侧) ===
    UI.DrawPickupItems(nvg, alpha)

    -- === 12. 操作提示 ===
    nvgFontSize(nvg, 10)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(nvg, nvgRGBA(140, 140, 160, math.floor(160 * alpha)))
    nvgText(nvg, logicalW / 2, logicalH - 10,
        "拖拽放置 | 右键/R旋转 | 拖出面板丢弃 | 填满整行/列升级 | Tab关闭背包", nil)
end

-- ============================================================================
-- 子绘制函数
-- ============================================================================

function UI.DrawGrid(nvg, alpha)
    for r = 1, Inv.rows do
        for c = 1, Inv.cols do
            local x = gridOriginX + (c - 1) * cellSize
            local y = gridOriginY + (r - 1) * cellSize

            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, x + 1, y + 1, cellSize - 2, cellSize - 2, 2)

            local isHover = (c == UI.hoverCol and r == UI.hoverRow and not UI.dragItem)
            if Inv.grid[r][c] then
                nvgFillColor(nvg, nvgRGBA(50, 55, 65, math.floor(200 * alpha)))
            elseif isHover then
                nvgFillColor(nvg, nvgRGBA(60, 65, 80, math.floor(200 * alpha)))
            else
                nvgFillColor(nvg, nvgRGBA(38, 42, 52, math.floor(200 * alpha)))
            end
            nvgFill(nvg)

            nvgStrokeColor(nvg, nvgRGBA(60, 65, 80, math.floor(120 * alpha)))
            nvgStrokeWidth(nvg, 0.5)
            nvgStroke(nvg)
        end
    end
end

--- 绘制完成行列的边缘发光效果
--- 1. 环绕扫光动画(填满瞬间，金光从起点沿边缘环绕一圈)
--- 2. 静态呼吸边缘光(动画结束后，边缘保持柔和向外渐隐金光)
function UI.DrawCompletedLineGlow(nvg, alpha)
    local pulse = 0.5 + 0.5 * math.sin(UI.glowTimer * 3.0)

    -- === 环绕扫光动画(进行中的 lineAnims) ===
    for _, anim in ipairs(Inv.lineAnims) do
        if not anim.done then
            local prog = anim.progress  -- 0..1 环绕进度
            if anim.type == "row" then
                local r = anim.index
                local rx = gridOriginX
                local ry = gridOriginY + (r - 1) * cellSize
                local rw = Inv.cols * cellSize
                local rh = cellSize
                -- 周长: 2*(rw+rh), 沿矩形边缘画光点
                local perimeter = 2 * (rw + rh)
                local drawLen = prog * perimeter  -- 已画到的长度

                UI.DrawSweepGlow(nvg, rx, ry, rw, rh, drawLen, perimeter, alpha)
            else -- col
                local c = anim.index
                local cx = gridOriginX + (c - 1) * cellSize
                local cy = gridOriginY
                local cw = cellSize
                local ch = Inv.rows * cellSize
                local perimeter = 2 * (cw + ch)
                local drawLen = prog * perimeter

                UI.DrawSweepGlow(nvg, cx, cy, cw, ch, drawLen, perimeter, alpha)
            end
        end
    end

    -- === 静态呼吸边缘光(已完成的行/列) ===
    local edgeAlpha = math.floor((0.35 + 0.25 * pulse) * 255 * alpha)
    local glowSpread = 4 + 2 * pulse  -- 向外渐隐宽度

    -- 行
    for r in pairs(Inv.completedRows) do
        -- 检查是否仍在播放扫光动画
        local animating = false
        for _, anim in ipairs(Inv.lineAnims) do
            if not anim.done and anim.type == "row" and anim.index == r then
                animating = true
                break
            end
        end
        if not animating then
            local rx = gridOriginX
            local ry = gridOriginY + (r - 1) * cellSize
            local rw = Inv.cols * cellSize
            local rh = cellSize
            UI.DrawEdgeGlow(nvg, rx, ry, rw, rh, edgeAlpha, glowSpread)
        end
    end

    -- 列
    for c in pairs(Inv.completedCols) do
        local animating = false
        for _, anim in ipairs(Inv.lineAnims) do
            if not anim.done and anim.type == "col" and anim.index == c then
                animating = true
                break
            end
        end
        if not animating then
            local cx = gridOriginX + (c - 1) * cellSize
            local cy = gridOriginY
            local cw = cellSize
            local ch = Inv.rows * cellSize
            UI.DrawEdgeGlow(nvg, cx, cy, cw, ch, edgeAlpha, glowSpread)
        end
    end
end

--- 绘制环绕扫光: 从矩形左上角开始, 沿顺时针环绕
--- drawLen: 已扫过的周长距离, perimeter: 总周长
function UI.DrawSweepGlow(nvg, rx, ry, rw, rh, drawLen, perimeter, alpha)
    -- 将 drawLen 映射到矩形边缘上的点序列
    -- 边顺序: 上(→) → 右(↓) → 下(←) → 左(↑)
    local edges = {
        {rx, ry, rx + rw, ry, rw},          -- 上边
        {rx + rw, ry, rx + rw, ry + rh, rh}, -- 右边
        {rx + rw, ry + rh, rx, ry + rh, rw}, -- 下边
        {rx, ry + rh, rx, ry, rh},            -- 左边
    }

    local remain = drawLen
    -- 扫光尾迹宽度
    local trailLen = perimeter * 0.15
    local headAlpha = math.floor(255 * alpha)

    for _, edge in ipairs(edges) do
        local ex1, ey1, ex2, ey2, eLen = edge[1], edge[2], edge[3], edge[4], edge[5]
        if remain <= 0 then break end

        local segLen = math.min(remain, eLen)
        local t = segLen / eLen
        local mx = ex1 + (ex2 - ex1) * t
        local my = ey1 + (ey2 - ey1) * t

        -- 绘制已扫过的边缘段(金色发光线)
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, ex1, ey1)
        nvgLineTo(nvg, mx, my)
        nvgStrokeColor(nvg, nvgRGBA(255, 200, 40, headAlpha))
        nvgStrokeWidth(nvg, 3)
        nvgStroke(nvg)

        -- 外侧光晕(柔和)
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, ex1, ey1)
        nvgLineTo(nvg, mx, my)
        nvgStrokeColor(nvg, nvgRGBA(255, 180, 20, math.floor(80 * alpha)))
        nvgStrokeWidth(nvg, 8)
        nvgStroke(nvg)

        -- 扫光头部亮点
        if remain <= eLen then
            -- 头部在此边上
            nvgBeginPath(nvg)
            nvgCircle(nvg, mx, my, 5)
            nvgFillColor(nvg, nvgRGBA(255, 240, 120, headAlpha))
            nvgFill(nvg)

            -- 头部外晕
            nvgBeginPath(nvg)
            nvgCircle(nvg, mx, my, 10)
            nvgFillColor(nvg, nvgRGBA(255, 200, 40, math.floor(40 * alpha)))
            nvgFill(nvg)
        end

        remain = remain - eLen
    end
end

--- 绘制静态边缘呼吸光(向外渐隐, 不填充内部)
function UI.DrawEdgeGlow(nvg, rx, ry, rw, rh, edgeAlpha, spread)
    -- 四条边的外侧渐变光带(用多层细线模拟渐隐)
    local layers = 4
    for i = 1, layers do
        local offset = i * (spread / layers)
        local layerAlpha = math.floor(edgeAlpha * (1 - i / (layers + 1)))
        if layerAlpha < 1 then break end

        nvgBeginPath(nvg)
        nvgRect(nvg, rx - offset, ry - offset, rw + offset * 2, rh + offset * 2)
        nvgStrokeColor(nvg, nvgRGBA(255, 200, 40, layerAlpha))
        nvgStrokeWidth(nvg, spread / layers)
        nvgStroke(nvg)
    end

    -- 最内层亮边
    nvgBeginPath(nvg)
    nvgRect(nvg, rx, ry, rw, rh)
    nvgStrokeColor(nvg, nvgRGBA(255, 210, 50, edgeAlpha))
    nvgStrokeWidth(nvg, 1.5)
    nvgStroke(nvg)
end

function UI.DrawPlacedItems(nvg, alpha)
    local drawn = {}

    for _, item in ipairs(Inv.items) do
        if item.placed and not drawn[item] then
            drawn[item] = true
            UI.DrawItemCells(nvg, item, item.gridCol, item.gridRow, alpha)
        end
    end
end

--- 绘制一个cell-based物品(一体化渲染，无内部黑线)
function UI.DrawItemCells(nvg, item, baseCol, baseRow, alpha)
    local cells = Inv.GetItemCells(item)
    local rarityCol = Data.RARITY_COLORS[item.rarity] or {200, 200, 200}
    local bgCol = Data.RARITY_BG_COLORS[item.rarity] or {40, 40, 40}
    local inset = 3  -- 外边缘内缩像素

    -- 建立cellSet用于邻居检测
    local cellSet = {}
    for _, cell in ipairs(cells) do
        cellSet[cell[1] .. "," .. cell[2]] = true
    end

    -- 1. 填充: 每格根据邻居动态计算边界(有邻居方向不内缩→融合)
    for _, cell in ipairs(cells) do
        local c = baseCol + cell[1]
        local r = baseRow + cell[2]
        local x = gridOriginX + (c - 1) * cellSize
        local y = gridOriginY + (r - 1) * cellSize
        local dc, dr = cell[1], cell[2]

        local x0 = cellSet[(dc - 1) .. "," .. dr] and x or (x + inset)
        local y0 = cellSet[dc .. "," .. (dr - 1)] and y or (y + inset)
        local x1 = cellSet[(dc + 1) .. "," .. dr] and (x + cellSize) or (x + cellSize - inset)
        local y1 = cellSet[dc .. "," .. (dr + 1)] and (y + cellSize) or (y + cellSize - inset)

        nvgBeginPath(nvg)
        nvgRect(nvg, x0, y0, x1 - x0, y1 - y0)
        nvgFillColor(nvg, nvgRGBA(bgCol[1] + 25, bgCol[2] + 25, bgCol[3] + 25, math.floor(220 * alpha)))
        nvgFill(nvg)
    end

    -- 2. 外轮廓描边(只画不与同物品格子相邻的边)
    nvgStrokeWidth(nvg, 1.5)
    nvgStrokeColor(nvg, nvgRGBA(rarityCol[1], rarityCol[2], rarityCol[3], math.floor(200 * alpha)))

    for _, cell in ipairs(cells) do
        local c = baseCol + cell[1]
        local r = baseRow + cell[2]
        local x = gridOriginX + (c - 1) * cellSize
        local y = gridOriginY + (r - 1) * cellSize
        local dc, dr = cell[1], cell[2]

        local lx = cellSet[(dc - 1) .. "," .. dr] and x or (x + inset)
        local ty = cellSet[dc .. "," .. (dr - 1)] and y or (y + inset)
        local rx = cellSet[(dc + 1) .. "," .. dr] and (x + cellSize) or (x + cellSize - inset)
        local by = cellSet[dc .. "," .. (dr + 1)] and (y + cellSize) or (y + cellSize - inset)

        -- 上边
        if not cellSet[dc .. "," .. (dr - 1)] then
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, lx, ty)
            nvgLineTo(nvg, rx, ty)
            nvgStroke(nvg)
        end
        -- 下边
        if not cellSet[dc .. "," .. (dr + 1)] then
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, lx, by)
            nvgLineTo(nvg, rx, by)
            nvgStroke(nvg)
        end
        -- 左边
        if not cellSet[(dc - 1) .. "," .. dr] then
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, lx, ty)
            nvgLineTo(nvg, lx, by)
            nvgStroke(nvg)
        end
        -- 右边
        if not cellSet[(dc + 1) .. "," .. dr] then
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, rx, ty)
            nvgLineTo(nvg, rx, by)
            nvgStroke(nvg)
        end
    end

    -- 3. 文字标签
    local minC, maxC, minR, maxR = 9999, -9999, 9999, -9999
    for _, cell in ipairs(cells) do
        local c = baseCol + cell[1]
        local r = baseRow + cell[2]
        if c < minC then minC = c end
        if c > maxC then maxC = c end
        if r < minR then minR = r end
        if r > maxR then maxR = r end
    end
    local centerX = gridOriginX + ((minC - 1) + (maxC)) * cellSize / 2
    local centerY = gridOriginY + ((minR - 1) + (maxR)) * cellSize / 2
    local spanW = maxC - minC + 1
    local numCells = #cells

    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    if numCells == 1 then
        nvgFontSize(nvg, 8)
        nvgFillColor(nvg, nvgRGBA(rarityCol[1], rarityCol[2], rarityCol[3], math.floor(230 * alpha)))
        local abbr = string.sub(item.name, 1, 3)
        nvgText(nvg, centerX, centerY, abbr, nil)
    elseif numCells <= 3 then
        local displayName = item.name
        if #displayName > 6 then displayName = string.sub(displayName, 1, 6) end
        nvgFontSize(nvg, 8)
        nvgFillColor(nvg, nvgRGBA(rarityCol[1], rarityCol[2], rarityCol[3], math.floor(240 * alpha)))
        nvgText(nvg, centerX, centerY, displayName, nil)

        if item.level and item.level > 1 then
            local topRightX = gridOriginX + maxC * cellSize - inset - 1
            local topRightY = gridOriginY + (minR - 1) * cellSize + inset + 1
            nvgFontSize(nvg, 7)
            nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            nvgFillColor(nvg, nvgRGBA(255, 220, 80, math.floor(230 * alpha)))
            nvgText(nvg, topRightX, topRightY, tostring(item.level), nil)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        end
    else
        local displayName = item.name
        local maxChars = math.min(4, spanW + 1)
        local maxBytes = maxChars * 3
        if #displayName > maxBytes then displayName = string.sub(displayName, 1, maxBytes) end

        local hasLevel = item.level and item.level > 1
        local nameY = hasLevel and (centerY - 5) or centerY
        nvgFontSize(nvg, 9)
        nvgFillColor(nvg, nvgRGBA(rarityCol[1], rarityCol[2], rarityCol[3], math.floor(255 * alpha)))
        nvgText(nvg, centerX, nameY, displayName, nil)

        if hasLevel then
            nvgFontSize(nvg, 8)
            nvgFillColor(nvg, nvgRGBA(255, 220, 80, math.floor(230 * alpha)))
            nvgText(nvg, centerX, centerY + 6, "Lv" .. item.level, nil)
        end
    end

    -- 标签小圆点(左下角)
    if item.tags then
        local dotX = gridOriginX + (minC - 1) * cellSize + inset + 3
        local dotY = gridOriginY + maxR * cellSize - inset - 2
        for ti = 1, math.min(3, #item.tags) do
            local tagCol = Data.TAG_COLORS[item.tags[ti]] or {180, 180, 180}
            nvgBeginPath(nvg)
            nvgCircle(nvg, dotX, dotY, 2)
            nvgFillColor(nvg, nvgRGBA(tagCol[1], tagCol[2], tagCol[3], math.floor(220 * alpha)))
            nvgFill(nvg)
            dotX = dotX + 6
        end
    end
end

function UI.DrawDragPreview(nvg, mouseX, mouseY, alpha)
    local item = UI.dragItem
    local cells = Inv.GetItemCells(item)
    local w, h = Inv.GetItemBounds(item)

    -- 计算目标格子位置
    local col, row = UI.ScreenToGrid(mouseX, mouseY)
    local centerOffCol = math.floor(UI.dragOffsetX / cellSize)
    local centerOffRow = math.floor(UI.dragOffsetY / cellSize)
    local placeCol = col - centerOffCol
    local placeRow = row - centerOffRow

    -- 放置预览(绿色可放/红色冲突) - cell-based
    local canPlace = Inv.CanPlace(item, placeCol, placeRow)

    for _, cell in ipairs(cells) do
        local c = placeCol + cell[1]
        local r = placeRow + cell[2]
        if c >= 1 and c <= Inv.cols and r >= 1 and r <= Inv.rows then
            local x = gridOriginX + (c - 1) * cellSize
            local y = gridOriginY + (r - 1) * cellSize

            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, x + 1, y + 1, cellSize - 2, cellSize - 2, 2)
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

    -- 面板外检测
    local outsidePanel = mouseX < panelX_ or mouseX > panelX_ + panelW_
                      or mouseY < panelY_ or mouseY > panelY_ + panelH_

    -- 跟随鼠标的物品(半透明)
    local drawX = mouseX - UI.dragOffsetX
    local drawY = mouseY - UI.dragOffsetY
    nvgSave(nvg)
    if outsidePanel and UI.dragSource == "grid" then
        nvgGlobalAlpha(nvg, 0.4)
    else
        nvgGlobalAlpha(nvg, 0.75)
    end

    -- 绘制拖拽中的cell-based物品(一体化渲染)
    local rarityCol = Data.RARITY_COLORS[item.rarity] or {200, 200, 200}
    local bgCol = Data.RARITY_BG_COLORS[item.rarity] or {40, 40, 40}
    local dinset = 3

    -- 建立cellSet用于邻居检测
    local dragCellSet = {}
    for _, cell in ipairs(cells) do
        dragCellSet[cell[1] .. "," .. cell[2]] = true
    end

    -- 填充
    for _, cell in ipairs(cells) do
        local cx = drawX + cell[1] * cellSize
        local cy = drawY + cell[2] * cellSize
        local dc, dr = cell[1], cell[2]

        local x0 = dragCellSet[(dc - 1) .. "," .. dr] and cx or (cx + dinset)
        local y0 = dragCellSet[dc .. "," .. (dr - 1)] and cy or (cy + dinset)
        local x1 = dragCellSet[(dc + 1) .. "," .. dr] and (cx + cellSize) or (cx + cellSize - dinset)
        local y1 = dragCellSet[dc .. "," .. (dr + 1)] and (cy + cellSize) or (cy + cellSize - dinset)

        nvgBeginPath(nvg)
        nvgRect(nvg, x0, y0, x1 - x0, y1 - y0)
        nvgFillColor(nvg, nvgRGBA(bgCol[1] + 25, bgCol[2] + 25, bgCol[3] + 25, math.floor(220 * alpha)))
        nvgFill(nvg)
    end

    -- 外轮廓描边
    nvgStrokeWidth(nvg, 1.5)
    nvgStrokeColor(nvg, nvgRGBA(rarityCol[1], rarityCol[2], rarityCol[3], math.floor(200 * alpha)))
    for _, cell in ipairs(cells) do
        local cx = drawX + cell[1] * cellSize
        local cy = drawY + cell[2] * cellSize
        local dc, dr = cell[1], cell[2]

        local lx = dragCellSet[(dc - 1) .. "," .. dr] and cx or (cx + dinset)
        local ty = dragCellSet[dc .. "," .. (dr - 1)] and cy or (cy + dinset)
        local rx = dragCellSet[(dc + 1) .. "," .. dr] and (cx + cellSize) or (cx + cellSize - dinset)
        local by = dragCellSet[dc .. "," .. (dr + 1)] and (cy + cellSize) or (cy + cellSize - dinset)

        if not dragCellSet[dc .. "," .. (dr - 1)] then
            nvgBeginPath(nvg); nvgMoveTo(nvg, lx, ty); nvgLineTo(nvg, rx, ty); nvgStroke(nvg)
        end
        if not dragCellSet[dc .. "," .. (dr + 1)] then
            nvgBeginPath(nvg); nvgMoveTo(nvg, lx, by); nvgLineTo(nvg, rx, by); nvgStroke(nvg)
        end
        if not dragCellSet[(dc - 1) .. "," .. dr] then
            nvgBeginPath(nvg); nvgMoveTo(nvg, lx, ty); nvgLineTo(nvg, lx, by); nvgStroke(nvg)
        end
        if not dragCellSet[(dc + 1) .. "," .. dr] then
            nvgBeginPath(nvg); nvgMoveTo(nvg, rx, ty); nvgLineTo(nvg, rx, by); nvgStroke(nvg)
        end
    end

    -- 拖拽物品名称
    local cxCenter = drawX + w * cellSize / 2
    local cyCenter = drawY + h * cellSize / 2
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 9)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(rarityCol[1], rarityCol[2], rarityCol[3], math.floor(255 * alpha)))
    nvgText(nvg, cxCenter, cyCenter, item.name, nil)

    nvgRestore(nvg)

    -- 面板外: 显示丢弃提示
    if outsidePanel and UI.dragSource == "grid" then
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, 11)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(nvg, nvgRGBA(255, 80, 80, math.floor(220 * alpha)))
        nvgText(nvg, mouseX, mouseY + h * cellSize / 2 + 4, "松开丢弃", nil)
    end
end

function UI.DrawItemTooltip(nvg, item, mx, my, logicalW, logicalH, alpha)
    local tipW = 200
    local tipH = 120

    tipH = 140 + (#item.tags * 14)

    -- 显示cells数量
    local cellCount = #item.cells
    tipH = tipH + 16  -- level info行

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
    nvgFontSize(nvg, 14)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(nvg, nvgRGBA(rarityCol[1], rarityCol[2], rarityCol[3], math.floor(255 * alpha)))
    nvgText(nvg, tipX + 10, tipY + 8, item.name, nil)

    -- 稀有度 + 格子数
    nvgFontSize(nvg, 10)
    nvgFillColor(nvg, nvgRGBA(160, 160, 180, math.floor(200 * alpha)))
    local rarityName = Data.RARITY_NAMES[item.rarity] or ""
    nvgText(nvg, tipX + 10, tipY + 28, rarityName .. " | " .. cellCount .. "格", nil)

    local yOff = tipY + 48

    -- 等级
    if item.level then
        nvgFillColor(nvg, nvgRGBA(255, 220, 80, math.floor(220 * alpha)))
        nvgText(nvg, tipX + 10, yOff, "Lv." .. item.level, nil)

        -- 等级说明
        if item.level > 1 then
            nvgFillColor(nvg, nvgRGBA(200, 180, 80, math.floor(160 * alpha)))
            nvgFontSize(nvg, 9)
            nvgText(nvg, tipX + 50, yOff + 1, "(行列完成加成)", nil)
            nvgFontSize(nvg, 10)
        end
        yOff = yOff + 16
    end

    -- 描述
    local tmpl = item.template
    if tmpl and tmpl.desc then
        nvgFillColor(nvg, nvgRGBA(200, 200, 220, math.floor(200 * alpha)))
        nvgFontSize(nvg, 10)
        nvgText(nvg, tipX + 10, yOff, tmpl.desc, nil)
        yOff = yOff + 18
    end

    -- 成长属性预览
    if tmpl and tmpl.growthStats and item.level then
        nvgFillColor(nvg, nvgRGBA(120, 200, 120, math.floor(180 * alpha)))
        nvgFontSize(nvg, 9)
        local growthText = "每级成长: "
        local first = true
        for k, v in pairs(tmpl.growthStats) do
            if not first then growthText = growthText .. ", " end
            growthText = growthText .. k .. "+" .. v
            first = false
        end
        nvgText(nvg, tipX + 10, yOff, growthText, nil)
        yOff = yOff + 14
    end

    -- 标签
    if item.tags and #item.tags > 0 then
        nvgFontSize(nvg, 10)
        for _, tag in ipairs(item.tags) do
            local tagCol = Data.TAG_COLORS[tag] or {180, 180, 180}
            local tagName = Data.TAGS[tag] or tag
            nvgFillColor(nvg, nvgRGBA(tagCol[1], tagCol[2], tagCol[3], math.floor(220 * alpha)))
            nvgText(nvg, tipX + 10, yOff, "● " .. tagName, nil)
            yOff = yOff + 14
        end
    end
end

function UI.DrawStatsPanel(nvg, alpha)
    local x = statsAreaX
    local y = statsAreaY

    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 13)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(nvg, nvgRGBA(200, 200, 220, math.floor(240 * alpha)))
    nvgText(nvg, x, y, "装备加成", nil)

    y = y + 22

    local statLines = Inv.GetStatSummary()
    if #statLines == 0 then
        nvgFontSize(nvg, 10)
        nvgFillColor(nvg, nvgRGBA(120, 120, 140, math.floor(160 * alpha)))
        nvgText(nvg, x, y, "放入圣物以获得加成", nil)
        return
    end

    nvgFontSize(nvg, 10)
    for _, line in ipairs(statLines) do
        nvgFillColor(nvg, nvgRGBA(160, 160, 180, math.floor(200 * alpha)))
        nvgText(nvg, x, y, line.name, nil)

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
    nvgFontSize(nvg, 13)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(nvg, nvgRGBA(200, 200, 220, math.floor(240 * alpha)))
    nvgText(nvg, x, y, "Combo", nil)
    y = y + 20

    if #Inv.activeCombos == 0 then
        nvgFontSize(nvg, 10)
        nvgFillColor(nvg, nvgRGBA(120, 120, 140, math.floor(160 * alpha)))
        nvgText(nvg, x, y, "集齐同类标签激活", nil)
        return
    end

    nvgFontSize(nvg, 10)
    for _, ac in ipairs(Inv.activeCombos) do
        local tagCol = Data.TAG_COLORS[ac.combo.tag] or {200, 200, 200}

        nvgFillColor(nvg, nvgRGBA(tagCol[1], tagCol[2], tagCol[3], math.floor(240 * alpha)))
        nvgText(nvg, x, y, ac.combo.name .. " Lv" .. ac.level, nil)
        y = y + 14

        nvgFillColor(nvg, nvgRGBA(180, 180, 200, math.floor(180 * alpha)))
        nvgFontSize(nvg, 10)
        nvgText(nvg, x + 8, y, ac.effect.desc, nil)
        nvgFontSize(nvg, 10)
        y = y + 16
    end
end

function UI.DrawPickupItems(nvg, alpha)
    if #UI.pickupItems == 0 then return end

    local x = pickupAreaX_
    local y = pickupAreaY_

    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 12)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(nvg, nvgRGBA(255, 200, 80, math.floor(240 * alpha)))
    nvgText(nvg, x + cellSize, y - 20, "可拾取", nil)

    for i, entry in ipairs(UI.pickupItems) do
        local item = entry.item
        local w, h = Inv.GetItemBounds(item)
        local pw = w * cellSize
        local ph = h * cellSize

        -- 背景
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x - 2, y - 2, pw + 4, ph + 4, 5)
        nvgFillColor(nvg, nvgRGBA(20, 22, 30, math.floor(180 * alpha)))
        nvgFill(nvg)
        nvgStrokeColor(nvg, nvgRGBA(255, 200, 80, math.floor(100 * alpha)))
        nvgStrokeWidth(nvg, 1)
        nvgStroke(nvg)

        -- 绘制cell-based物品(一体化渲染)
        local cells = Inv.GetItemCells(item)
        local rarityCol = Data.RARITY_COLORS[item.rarity] or {200, 200, 200}
        local bgCol = Data.RARITY_BG_COLORS[item.rarity] or {40, 40, 40}
        local pinset = 3

        local pickCellSet = {}
        for _, cell in ipairs(cells) do
            pickCellSet[cell[1] .. "," .. cell[2]] = true
        end

        -- 填充
        for _, cell in ipairs(cells) do
            local cx = x + cell[1] * cellSize
            local cy = y + cell[2] * cellSize
            local dc, dr = cell[1], cell[2]

            local x0 = pickCellSet[(dc - 1) .. "," .. dr] and cx or (cx + pinset)
            local y0 = pickCellSet[dc .. "," .. (dr - 1)] and cy or (cy + pinset)
            local x1 = pickCellSet[(dc + 1) .. "," .. dr] and (cx + cellSize) or (cx + cellSize - pinset)
            local y1 = pickCellSet[dc .. "," .. (dr + 1)] and (cy + cellSize) or (cy + cellSize - pinset)

            nvgBeginPath(nvg)
            nvgRect(nvg, x0, y0, x1 - x0, y1 - y0)
            nvgFillColor(nvg, nvgRGBA(bgCol[1] + 25, bgCol[2] + 25, bgCol[3] + 25, math.floor(220 * alpha)))
            nvgFill(nvg)
        end

        -- 外轮廓描边
        nvgStrokeWidth(nvg, 1)
        nvgStrokeColor(nvg, nvgRGBA(rarityCol[1], rarityCol[2], rarityCol[3], math.floor(180 * alpha)))
        for _, cell in ipairs(cells) do
            local cx = x + cell[1] * cellSize
            local cy = y + cell[2] * cellSize
            local dc, dr = cell[1], cell[2]

            local lx = pickCellSet[(dc - 1) .. "," .. dr] and cx or (cx + pinset)
            local ty = pickCellSet[dc .. "," .. (dr - 1)] and cy or (cy + pinset)
            local rx = pickCellSet[(dc + 1) .. "," .. dr] and (cx + cellSize) or (cx + cellSize - pinset)
            local by = pickCellSet[dc .. "," .. (dr + 1)] and (cy + cellSize) or (cy + cellSize - pinset)

            if not pickCellSet[dc .. "," .. (dr - 1)] then
                nvgBeginPath(nvg); nvgMoveTo(nvg, lx, ty); nvgLineTo(nvg, rx, ty); nvgStroke(nvg)
            end
            if not pickCellSet[dc .. "," .. (dr + 1)] then
                nvgBeginPath(nvg); nvgMoveTo(nvg, lx, by); nvgLineTo(nvg, rx, by); nvgStroke(nvg)
            end
            if not pickCellSet[(dc - 1) .. "," .. dr] then
                nvgBeginPath(nvg); nvgMoveTo(nvg, lx, ty); nvgLineTo(nvg, lx, by); nvgStroke(nvg)
            end
            if not pickCellSet[(dc + 1) .. "," .. dr] then
                nvgBeginPath(nvg); nvgMoveTo(nvg, rx, ty); nvgLineTo(nvg, rx, by); nvgStroke(nvg)
            end
        end

        -- 名称
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, 8)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(rarityCol[1], rarityCol[2], rarityCol[3], math.floor(240 * alpha)))
        nvgText(nvg, x + pw / 2, y + ph / 2, item.name, nil)

        -- 箭头
        nvgFontSize(nvg, 14)
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(255, 200, 80, math.floor(140 * alpha)))
        nvgText(nvg, x + pw + 6, y + ph / 2, "→", nil)

        y = y + ph + 10
        if i >= 8 then break end
    end
end

return UI
