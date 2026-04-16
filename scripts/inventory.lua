-- ============================================================================
-- 背包逻辑模块
-- cell-based格子管理、俄罗斯方块放置/旋转、行列完成检测、动态等级、Combo结算
-- ============================================================================

local Data = require("inventory_data")
local G = require("game_context")

local Inv = {}

-- ============================================================================
-- 背包状态
-- ============================================================================
Inv.grid = {}            -- grid[r][c] = nil | {itemRef=item}
Inv.items = {}           -- 所有已放置的物品列表
Inv.cols = Data.GRID_COLS
Inv.rows = Data.GRID_ROWS

-- 计算后的属性加成
Inv.bonusStats = {}
-- 激活的Combo
Inv.activeCombos = {}
-- 当前标签统计
Inv.tagCounts = {}
-- 完成的行/列(用于发光效果)
Inv.completedRows = {}   -- {[rowIndex] = true}
Inv.completedCols = {}   -- {[colIndex] = true}
-- 行列完成动画 {type="row"|"col", index=N, progress=0..1, done=false}
Inv.lineAnims = {}

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
    Inv.bonusStats = {}
    Inv.activeCombos = {}
    Inv.tagCounts = {}
    Inv.completedRows = {}
    Inv.completedCols = {}
    Inv.lineAnims = {}
end

-- ============================================================================
-- 物品实例创建
-- ============================================================================

--- 创建圣物实例 (level由行列完成动态计算，不再手动指定)
function Inv.CreateArtifact(templateId)
    local tmpl = Data.FindArtifactTemplate(templateId)
    if not tmpl then
        print("ERROR: Artifact template not found: " .. tostring(templateId))
        return nil
    end

    return {
        type = "artifact",
        templateId = templateId,
        template = tmpl,
        name = tmpl.name,
        rarity = tmpl.rarity,
        level = 1,           -- 动态计算，基础为1
        cells = tmpl.cells,
        boundW = tmpl.boundW,
        boundH = tmpl.boundH,
        tags = tmpl.tags,
        rotation = 0,        -- 0/1/2/3 对应 0°/90°/180°/270° 顺时针
        gridCol = 0,         -- 放置位置(0=未放置)
        gridRow = 0,
        placed = false,
    }
end

--- 随机创建圣物
--- @param maxRarity number 最高稀有度
--- @param rarityBoost number|nil 稀有度提升值(来自幸运币等)
function Inv.CreateRandomArtifact(maxRarity, rarityBoost)
    local tmpl = Data.RandomArtifactTemplate(maxRarity, rarityBoost)
    if not tmpl then return nil end
    return Inv.CreateArtifact(tmpl.id)
end

-- ============================================================================
-- 形状工具 (cells + rotation)
-- ============================================================================

--- 获取物品在当前旋转下的实际格子偏移列表
--- 返回 {{dc, dr}, ...} 相对于放置基准点的偏移
function Inv.GetItemCells(item)
    local baseCells = item.cells
    local rot = item.rotation or 0
    local bw = item.boundW
    local bh = item.boundH

    if rot == 0 then
        return baseCells
    end

    local result = {}
    for _, cell in ipairs(baseCells) do
        local dc, dr = cell[1], cell[2]
        local nc, nr
        if rot == 1 then
            -- 90° CW: (dc,dr) → (bh-1-dr, dc)
            nc = bh - 1 - dr
            nr = dc
        elseif rot == 2 then
            -- 180°: (dc,dr) → (bw-1-dc, bh-1-dr)
            nc = bw - 1 - dc
            nr = bh - 1 - dr
        else  -- rot == 3
            -- 270° CW: (dc,dr) → (dr, bw-1-dc)
            nc = dr
            nr = bw - 1 - dc
        end
        table.insert(result, {nc, nr})
    end
    return result
end

--- 获取物品在当前旋转下的包围盒尺寸
function Inv.GetItemBounds(item)
    local rot = item.rotation or 0
    if rot == 1 or rot == 3 then
        return item.boundH, item.boundW  -- 宽高互换
    end
    return item.boundW, item.boundH
end

--- 兼容旧API: 返回占用格子数的等效"尺寸"（用于UI绘制pickup区域等）
function Inv.GetItemSize(item)
    return Inv.GetItemBounds(item)
end

-- ============================================================================
-- 格子操作
-- ============================================================================

--- 检查物品是否可以放在指定位置
function Inv.CanPlace(item, col, row)
    local cells = Inv.GetItemCells(item)

    for _, cell in ipairs(cells) do
        local c = col + cell[1]
        local r = row + cell[2]

        -- 边界检查
        if c < 1 or c > Inv.cols or r < 1 or r > Inv.rows then
            return false
        end

        -- 格子是否被占用(排除自身)
        local gridCell = Inv.grid[r][c]
        if gridCell ~= nil and gridCell.itemRef ~= item then
            return false
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

    local cells = Inv.GetItemCells(item)
    item.gridCol = col
    item.gridRow = row
    item.placed = true

    -- 标记格子
    local cellInfo = {itemRef = item}
    for _, cell in ipairs(cells) do
        local c = col + cell[1]
        local r = row + cell[2]
        Inv.grid[r][c] = cellInfo
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

    -- 重新计算属性
    Inv.RecalculateStats()

    return true
end

--- 移除物品(从格子中取出)
function Inv.RemoveItem(item)
    if not item.placed then return end

    local cells = Inv.GetItemCells(item)

    -- 清除格子
    for _, cell in ipairs(cells) do
        local c = item.gridCol + cell[1]
        local r = item.gridRow + cell[2]
        if r >= 1 and r <= Inv.rows and c >= 1 and c <= Inv.cols then
            if Inv.grid[r][c] and Inv.grid[r][c].itemRef == item then
                Inv.grid[r][c] = nil
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

    -- 重新计算属性
    Inv.RecalculateStats()
end

--- 旋转物品 (4方向: 0→1→2→3→0)
function Inv.RotateItem(item)
    -- 单格不需要旋转
    if #item.cells <= 1 then return false end
    -- 正方形且旋转对称的不需要旋转(如O形)
    if item.boundW == item.boundH then
        -- 检查是否旋转后形状相同(O形方块)
        local oldRot = item.rotation
        item.rotation = (item.rotation + 1) % 4
        local newCells = Inv.GetItemCells(item)
        item.rotation = oldRot
        local oldCells = Inv.GetItemCells(item)
        -- 简单比较: 排序后比较
        local function cellKey(c) return c[1] * 100 + c[2] end
        local oldKeys, newKeys = {}, {}
        for _, c in ipairs(oldCells) do table.insert(oldKeys, cellKey(c)) end
        for _, c in ipairs(newCells) do table.insert(newKeys, cellKey(c)) end
        table.sort(oldKeys)
        table.sort(newKeys)
        local same = true
        if #oldKeys == #newKeys then
            for i = 1, #oldKeys do
                if oldKeys[i] ~= newKeys[i] then same = false; break end
            end
        else
            same = false
        end
        if same then return false end
    end

    if item.placed then
        -- 先移除, 尝试旋转后放回
        local oldCol, oldRow = item.gridCol, item.gridRow
        local oldRot = item.rotation
        Inv.RemoveItem(item)
        item.rotation = (oldRot + 1) % 4

        -- 尝试在原位放置(旋转后)
        if not Inv.CanPlace(item, oldCol, oldRow) then
            -- 旋转后放不下, 恢复
            item.rotation = oldRot
            Inv.PlaceItem(item, oldCol, oldRow)
            return false
        end

        Inv.PlaceItem(item, oldCol, oldRow)
        return true
    else
        -- 未放置的直接旋转
        item.rotation = (item.rotation + 1) % 4
        return true
    end
end

--- 丢弃物品(从游戏中完全移除)
function Inv.DiscardItem(item)
    if item.placed then
        Inv.RemoveItem(item)
    end
end

--- 自动放置物品(找到第一个可用位置, 尝试4个旋转方向)
function Inv.AutoPlace(item)
    local origRot = item.rotation

    for rot = 0, 3 do
        item.rotation = (origRot + rot) % 4
        for r = 1, Inv.rows do
            for c = 1, Inv.cols do
                if Inv.CanPlace(item, c, r) then
                    return Inv.PlaceItem(item, c, r)
                end
            end
        end
    end

    -- 恢复原始旋转
    item.rotation = origRot
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
-- 行列完成检测 & 动态等级
-- ============================================================================

--- 更新完成的行和列，新完成的行/列触发环绕动画
function Inv.UpdateCompletedLines()
    local oldRows = Inv.completedRows
    local oldCols = Inv.completedCols
    Inv.completedRows = {}
    Inv.completedCols = {}

    -- 检查每一行
    for r = 1, Inv.rows do
        local full = true
        for c = 1, Inv.cols do
            if Inv.grid[r][c] == nil then
                full = false
                break
            end
        end
        if full then
            Inv.completedRows[r] = true
            -- 新完成的行 → 触发动画
            if not oldRows[r] then
                table.insert(Inv.lineAnims, {type = "row", index = r, progress = 0, done = false})
                G.PlaySfx(G.sndLineClear, 0.5)
            end
        end
    end

    -- 检查每一列
    for c = 1, Inv.cols do
        local full = true
        for r = 1, Inv.rows do
            if Inv.grid[r][c] == nil then
                full = false
                break
            end
        end
        if full then
            Inv.completedCols[c] = true
            -- 新完成的列 → 触发动画
            if not oldCols[c] then
                table.insert(Inv.lineAnims, {type = "col", index = c, progress = 0, done = false})
                G.PlaySfx(G.sndLineClear, 0.5)
            end
        end
    end

    -- 清理已完成的旧动画（保留最近1秒的）
    for i = #Inv.lineAnims, 1, -1 do
        if Inv.lineAnims[i].done then
            table.remove(Inv.lineAnims, i)
        end
    end
end

--- 计算某个圣物的动态等级
--- 等级 = 1 + 该圣物在已完成行中占据的格子数 + 该圣物在已完成列中占据的格子数
--- 上限 = 格子数 * 2
function Inv.CalculateArtifactLevel(item)
    if not item.placed then return 1 end

    local cells = Inv.GetItemCells(item)
    local bonus = 0

    for _, cell in ipairs(cells) do
        local c = item.gridCol + cell[1]
        local r = item.gridRow + cell[2]

        if Inv.completedRows[r] then
            bonus = bonus + 1
        end
        if Inv.completedCols[c] then
            bonus = bonus + 1
        end
    end

    local maxLevel = #item.cells * 2
    return math.min(1 + bonus, maxLevel)
end

-- ============================================================================
-- 属性结算
-- ============================================================================
function Inv.RecalculateStats()
    local stats = {}

    -- 0. 更新行列完成状态 & 动态等级
    Inv.UpdateCompletedLines()
    for _, item in ipairs(Inv.items) do
        if item.placed then
            item.level = Inv.CalculateArtifactLevel(item)
        end
    end

    -- 1. 统计标签
    Inv.tagCounts = {}
    for _, item in ipairs(Inv.items) do
        if item.placed then
            for _, tag in ipairs(item.tags) do
                Inv.tagCounts[tag] = (Inv.tagCounts[tag] or 0) + 1
            end
        end
    end

    -- 2. 累加圣物基础属性 + 等级成长
    for _, item in ipairs(Inv.items) do
        if item.placed then
            local tmpl = item.template
            -- 基础值
            for k, v in pairs(tmpl.baseStats) do
                if type(v) == "number" then
                    stats[k] = (stats[k] or 0) + v
                else
                    stats[k] = v  -- 布尔值等非数字直接赋值
                end
            end
            -- 等级成长: growthStats * (Level - 1)
            if item.level > 1 and tmpl.growthStats then
                for k, v in pairs(tmpl.growthStats) do
                    if type(v) == "number" then
                        stats[k] = (stats[k] or 0) + v * (item.level - 1)
                    end
                end
            end
        end
    end

    -- 3. 评估Combo
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

    -- 4. 应用Combo加成(百分比加成存入独立字段)
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
        {key = "rarityBoost", name = "稀有度提升", fmt = "+%d%%"},
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

return Inv
