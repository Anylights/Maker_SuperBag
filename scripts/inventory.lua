-- ============================================================================
-- 背包逻辑模块
-- 格子管理、物品放置/移除/旋转、碰撞检测、石板范围、Combo评估、属性结算
-- ============================================================================

local Data = require("inventory_data")

local Inv = {}

-- ============================================================================
-- 背包状态
-- ============================================================================
Inv.grid = {}            -- grid[r][c] = nil | {type="artifact"|"tablet", itemRef=item}
Inv.items = {}           -- 所有已放置的物品列表
Inv.pendingItems = {}    -- 未放入背包的物品(等待放入)
Inv.cols = Data.GRID_COLS
Inv.rows = Data.GRID_ROWS

-- 计算后的属性加成
Inv.bonusStats = {}
-- 激活的Combo
Inv.activeCombos = {}
-- 当前标签统计
Inv.tagCounts = {}

-- ============================================================================
-- 初始化
-- ============================================================================
function Inv.Init()
    Inv.grid = {}
    for r = 1, Inv.rows do
        Inv.grid[r] = {}
        for c = 1, Inv.cols do
            Inv.grid[r][c] = nil
        end
    end
    Inv.items = {}
    Inv.pendingItems = {}
    Inv.bonusStats = {}
    Inv.activeCombos = {}
    Inv.tagCounts = {}
end

-- ============================================================================
-- 物品实例创建
-- ============================================================================
--- 创建圣物实例
function Inv.CreateArtifact(templateId, level)
    local tmpl = Data.FindArtifactTemplate(templateId)
    if not tmpl then
        print("ERROR: Artifact template not found: " .. tostring(templateId))
        return nil
    end
    level = level or 1

    return {
        type = "artifact",
        templateId = templateId,
        template = tmpl,
        name = tmpl.name,
        rarity = tmpl.rarity,
        level = level,
        sizeW = tmpl.sizeW,
        sizeH = tmpl.sizeH,
        tags = tmpl.tags,
        rotated = false,  -- 是否旋转90°
        gridCol = 0,      -- 放置位置(0=未放置)
        gridRow = 0,
        placed = false,
    }
end

--- 创建石板实例
function Inv.CreateTablet(templateId)
    local tmpl = Data.FindTabletTemplate(templateId)
    if not tmpl then
        print("ERROR: Tablet template not found: " .. tostring(templateId))
        return nil
    end

    return {
        type = "tablet",
        templateId = templateId,
        template = tmpl,
        name = tmpl.name,
        rarity = tmpl.rarity,
        sizeW = tmpl.sizeW,
        sizeH = tmpl.sizeH,
        maskType = tmpl.maskType,
        rotated = false,
        gridCol = 0,
        gridRow = 0,
        placed = false,
    }
end

--- 随机创建圣物
function Inv.CreateRandomArtifact(maxRarity, level)
    local tmpl = Data.RandomArtifactTemplate(maxRarity)
    if not tmpl then return nil end
    return Inv.CreateArtifact(tmpl.id, level or 1)
end

--- 随机创建石板
function Inv.CreateRandomTablet()
    local tmpl = Data.RandomTabletTemplate()
    if not tmpl then return nil end
    return Inv.CreateTablet(tmpl.id)
end

-- ============================================================================
-- 尺寸工具(考虑旋转)
-- ============================================================================
function Inv.GetItemSize(item)
    if item.rotated then
        return item.sizeH, item.sizeW  -- 宽高互换
    end
    return item.sizeW, item.sizeH
end

-- ============================================================================
-- 格子操作
-- ============================================================================

--- 检查物品是否可以放在指定位置
function Inv.CanPlace(item, col, row)
    local w, h = Inv.GetItemSize(item)

    -- 边界检查
    if col < 1 or row < 1 then return false end
    if col + w - 1 > Inv.cols then return false end
    if row + h - 1 > Inv.rows then return false end

    -- 检查格子是否被占用(排除自身)
    for r = row, row + h - 1 do
        for c = col, col + w - 1 do
            local cell = Inv.grid[r][c]
            if cell ~= nil and cell.itemRef ~= item then
                return false
            end
        end
    end

    return true
end

--- 放置物品到格子
function Inv.PlaceItem(item, col, row)
    if not Inv.CanPlace(item, col, row) then
        return false
    end

    -- 如果已放置，先移除
    if item.placed then
        Inv.RemoveItem(item)
    end

    local w, h = Inv.GetItemSize(item)
    item.gridCol = col
    item.gridRow = row
    item.placed = true

    -- 标记格子
    local cellInfo = {type = item.type, itemRef = item}
    for r = row, row + h - 1 do
        for c = col, col + w - 1 do
            Inv.grid[r][c] = cellInfo
        end
    end

    -- 加入物品列表(如果还没在)
    local found = false
    for _, existing in ipairs(Inv.items) do
        if existing == item then
            found = true
            break
        end
    end
    if not found then
        table.insert(Inv.items, item)
    end

    -- 从待放入列表中移除
    for i = #Inv.pendingItems, 1, -1 do
        if Inv.pendingItems[i] == item then
            table.remove(Inv.pendingItems, i)
            break
        end
    end

    -- 重新计算属性
    Inv.RecalculateStats()

    return true
end

--- 移除物品(从格子中取出)
function Inv.RemoveItem(item)
    if not item.placed then return end

    local w, h = Inv.GetItemSize(item)

    -- 清除格子
    for r = item.gridRow, item.gridRow + h - 1 do
        for c = item.gridCol, item.gridCol + w - 1 do
            if r >= 1 and r <= Inv.rows and c >= 1 and c <= Inv.cols then
                if Inv.grid[r][c] and Inv.grid[r][c].itemRef == item then
                    Inv.grid[r][c] = nil
                end
            end
        end
    end

    item.placed = false
    item.gridCol = 0
    item.gridRow = 0

    -- 从物品列表中移除
    for i = #Inv.items, 1, -1 do
        if Inv.items[i] == item then
            table.remove(Inv.items, i)
            break
        end
    end

    -- 加入待放入列表
    table.insert(Inv.pendingItems, item)

    -- 重新计算属性
    Inv.RecalculateStats()
end

--- 旋转物品90°
function Inv.RotateItem(item)
    if item.sizeW == item.sizeH then return end  -- 正方形不需要旋转

    if item.placed then
        -- 先移除, 尝试旋转后放回
        local oldCol, oldRow = item.gridCol, item.gridRow
        Inv.RemoveItem(item)
        item.rotated = not item.rotated

        -- 尝试在原位放置(旋转后)
        if not Inv.CanPlace(item, oldCol, oldRow) then
            -- 旋转后放不下, 恢复
            item.rotated = not item.rotated
            Inv.PlaceItem(item, oldCol, oldRow)
            return false
        end

        Inv.PlaceItem(item, oldCol, oldRow)
        return true
    else
        -- 未放置的直接旋转
        item.rotated = not item.rotated
        return true
    end
end

--- 丢弃物品(从游戏中完全移除)
function Inv.DiscardItem(item)
    if item.placed then
        Inv.RemoveItem(item)
    end
    -- 从待放入列表也移除
    for i = #Inv.pendingItems, 1, -1 do
        if Inv.pendingItems[i] == item then
            table.remove(Inv.pendingItems, i)
            break
        end
    end
end

--- 自动放置物品(找到第一个可用位置)
function Inv.AutoPlace(item)
    local w, h = Inv.GetItemSize(item)

    -- 尝试正常方向
    for r = 1, Inv.rows do
        for c = 1, Inv.cols do
            if Inv.CanPlace(item, c, r) then
                return Inv.PlaceItem(item, c, r)
            end
        end
    end

    -- 尝试旋转后
    if w ~= h then
        item.rotated = not item.rotated
        for r = 1, Inv.rows do
            for c = 1, Inv.cols do
                if Inv.CanPlace(item, c, r) then
                    return Inv.PlaceItem(item, c, r)
                end
            end
        end
        item.rotated = not item.rotated  -- 恢复
    end

    return false  -- 没有空间
end

--- 获取物品在指定格子
function Inv.GetItemAt(col, row)
    if row < 1 or row > Inv.rows or col < 1 or col > Inv.cols then
        return nil
    end
    local cell = Inv.grid[row][col]
    if cell then
        return cell.itemRef
    end
    return nil
end

-- ============================================================================
-- 石板范围计算
-- ============================================================================

--- 获取石板影响的格子坐标列表
function Inv.GetTabletAffectedCells(tablet)
    if tablet.type ~= "tablet" or not tablet.placed then return {} end

    local mask = Data.TABLET_MASKS[tablet.maskType]
    if not mask then return {} end

    local cells = {}
    -- 石板中心点(1x1石板直接用其位置)
    local cx = tablet.gridCol
    local cy = tablet.gridRow

    for _, offset in ipairs(mask.offsets) do
        local tc = cx + offset[1]
        local tr = cy + offset[2]
        if tc >= 1 and tc <= Inv.cols and tr >= 1 and tr <= Inv.rows then
            table.insert(cells, {col = tc, row = tr})
        end
    end

    return cells
end

--- 获取石板影响的圣物列表(去重)
function Inv.GetTabletAffectedArtifacts(tablet)
    local cells = Inv.GetTabletAffectedCells(tablet)
    local affected = {}
    local seen = {}

    for _, cell in ipairs(cells) do
        local item = Inv.GetItemAt(cell.col, cell.row)
        if item and item.type == "artifact" and not seen[item] then
            seen[item] = true
            table.insert(affected, item)
        end
    end

    return affected
end

--- 获取一个圣物受到多少个石板影响
function Inv.GetTabletCountForArtifact(artifact)
    local count = 0
    for _, item in ipairs(Inv.items) do
        if item.type == "tablet" and item.placed then
            local affected = Inv.GetTabletAffectedArtifacts(item)
            for _, a in ipairs(affected) do
                if a == artifact then
                    count = count + 1
                    break
                end
            end
        end
    end
    return count
end

-- ============================================================================
-- 属性结算
-- ============================================================================
function Inv.RecalculateStats()
    local stats = {}

    -- 1. 统计标签
    Inv.tagCounts = {}
    for _, item in ipairs(Inv.items) do
        if item.type == "artifact" and item.placed then
            for _, tag in ipairs(item.tags) do
                Inv.tagCounts[tag] = (Inv.tagCounts[tag] or 0) + 1
            end
        end
    end

    -- 2. 累加圣物基础属性 + 等级成长
    for _, item in ipairs(Inv.items) do
        if item.type == "artifact" and item.placed then
            local tmpl = item.template
            -- 基础值
            for k, v in pairs(tmpl.baseStats) do
                stats[k] = (stats[k] or 0) + v
            end
            -- 等级成长: BaseValue * GrowthRate * (Level - 1)
            if item.level > 1 and tmpl.growthStats then
                for k, v in pairs(tmpl.growthStats) do
                    stats[k] = (stats[k] or 0) + v * (item.level - 1)
                end
            end
        end
    end

    -- 3. 应用石板加成
    for _, tablet in ipairs(Inv.items) do
        if tablet.type == "tablet" and tablet.placed then
            local tmpl = tablet.template
            local affected = Inv.GetTabletAffectedArtifacts(tablet)

            for _, artifact in ipairs(affected) do
                -- 检查石板叠加数量(同一圣物最多3个石板增强,超过衰减)
                local tabletCount = Inv.GetTabletCountForArtifact(artifact)
                local multiplier = 1.0
                if tabletCount > 3 then
                    multiplier = 0.35  -- 第4个及以后只生效35%
                end

                if tmpl.bonusStats then
                    for k, v in pairs(tmpl.bonusStats) do
                        stats[k] = (stats[k] or 0) + v * multiplier
                    end
                end
                if tmpl.penaltyStats then
                    for k, v in pairs(tmpl.penaltyStats) do
                        stats[k] = (stats[k] or 0) + v * multiplier
                    end
                end
            end
        end
    end

    -- 4. 评估Combo
    Inv.activeCombos = {}
    for _, combo in ipairs(Data.COMBO_TEMPLATES) do
        local count = Inv.tagCounts[combo.tag] or 0
        local activeLevel = 0
        for lvl, threshold in ipairs(combo.thresholds) do
            if count >= threshold then
                activeLevel = lvl
            end
        end
        if activeLevel > 0 then
            table.insert(Inv.activeCombos, {
                combo = combo,
                level = activeLevel,
                effect = combo.effects[activeLevel],
                tagCount = count,
            })
        end
    end

    -- 5. 应用Combo加成(百分比加成存入独立字段)
    for _, ac in ipairs(Inv.activeCombos) do
        local eff = ac.effect
        for k, v in pairs(eff) do
            if k ~= "desc" and type(v) == "number" then
                stats["combo_" .. k] = (stats["combo_" .. k] or 0) + v
            elseif type(v) == "boolean" and v then
                stats["combo_" .. k] = true
            end
        end
    end

    Inv.bonusStats = stats
end

--- 获取某属性的加成值
function Inv.GetStat(key, default)
    return Inv.bonusStats[key] or default or 0
end

--- 获取所有加成的格式化文本(用于UI展示)
function Inv.GetStatSummary()
    local lines = {}

    local display = {
        {key = "damage", name = "伤害", fmt = "+%d"},
        {key = "maxHp", name = "最大生命", fmt = "%+d"},
        {key = "moveSpeed", name = "移速", fmt = "%+d"},
        {key = "fireRate", name = "射速", fmt = "+%.2f"},
        {key = "critChance", name = "暴击率", fmt = "+%d%%"},
        {key = "critDamage", name = "暴击伤害", fmt = "+%d%%"},
        {key = "magSize", name = "弹匣", fmt = "+%d"},
        {key = "pierce", name = "穿透", fmt = "+%d"},
        {key = "burnDamage", name = "燃烧伤害", fmt = "+%d"},
        {key = "slowAmount", name = "减速", fmt = "+%d%%"},
        {key = "shockChance", name = "感电率", fmt = "+%d%%"},
        {key = "hpRegen", name = "生命回复", fmt = "+%.1f/s"},
        {key = "lootBonus", name = "掉落率", fmt = "+%d%%"},
        {key = "totalAmmo", name = "弹药", fmt = "+%d"},
    }

    for _, d in ipairs(display) do
        local v = Inv.bonusStats[d.key]
        if v and v ~= 0 then
            table.insert(lines, {
                name = d.name,
                text = string.format(d.fmt, v),
                positive = v > 0,
            })
        end
    end

    return lines
end

-- ============================================================================
-- 添加物品到待放入列表
-- ============================================================================
function Inv.AddPendingItem(item)
    table.insert(Inv.pendingItems, item)
end

--- 获取待放入物品数量
function Inv.GetPendingCount()
    return #Inv.pendingItems
end

return Inv
