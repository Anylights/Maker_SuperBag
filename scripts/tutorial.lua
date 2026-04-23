-- ============================================================================
-- tutorial.lua — 情境式新手教程（游戏进程中逐步触发）
-- ============================================================================
local G       = require("game_context")
local InvUI   = require("inventory_ui")
local Map     = require("map")

local Tutorial = {}

-- 当前正在显示的提示 key (nil = 无)
Tutorial.currentTip = nil

-- 已展示过的提示集合
local shown = {}

-- 动画计时
local tipTimer  = 0
local blinkT    = 0
local dismissCooldown = 0  -- dismiss 后冷却，防止下一个提示立即弹出

-- 是否已初始化
local inited = false

-- 初始化时已存在的圣物 loot 引用集合（用于排除 starter artifact）
local initialArtifactRefs = {}

-- banner 边界（屏幕设计坐标系）— 用于点击检测
local bannerRect = { x = 0, y = 0, w = 0, h = 0 }

-- 设计分辨率
local DW = G.DESIGN_W
local DH = G.DESIGN_H

-- ============================================================================
-- 提示定义
-- ============================================================================
local TIPS = {
    move_dash = {
        title   = "移动 & 冲刺",
        descPC  = "WASD 移动小狼，Shift 冲刺（冲刺时无敌）",
        descMob = "左摇杆移动，冲刺按钮冲刺（冲刺时无敌）",
    },
    shoot = {
        title   = "射击",
        descPC  = "移动鼠标瞄准敌人，按住左键射击",
        descMob = "右摇杆瞄准方向并自动射击",
    },
    reload = {
        title   = "换弹",
        descPC  = "弹药耗尽！按 R 键换弹",
        descMob = "弹药耗尽！点击右侧换弹按钮",
    },
    search_crate = {
        title   = "搜刮箱子",
        descPC  = "站在箱子上自动搜刮\n木箱/铁箱/金箱 — 稀有度依次递增",
        descMob = "站在箱子上自动搜刮\n木箱/铁箱/金箱 — 稀有度依次递增",
    },
    open_bag = {
        title   = "打开背包",
        descPC  = "地上出现了圣物！按 Tab 打开背包装备",
        descMob = "地上出现了圣物！点击右上背包按钮装备",
    },
    bag_manage = {
        title   = "背包管理",
        descPC  = "拖拽圣物放入网格 · 拖到网格外丢弃\n填满整行/列触发升级 · 同元素Combo叠加增益",
        descMob = "拖拽圣物放入网格 · 拖到网格外丢弃\n填满整行/列触发升级 · 同元素Combo叠加增益",
    },
}

-- 提示显示顺序（用于进度指示点）
local TIP_ORDER = { "move_dash", "shoot", "reload", "search_crate", "open_bag", "bag_manage" }

-- ============================================================================
-- 初始化 — 加载已展示记录
-- ============================================================================
function Tutorial.Init()
    if inited then return end
    inited = true

    -- 记录初始时已存在的圣物 loot（如 starter artifact），用于排除
    initialArtifactRefs = {}
    for _, item in ipairs(G.lootItems) do
        if item.type == "artifact" then
            initialArtifactRefs[item] = true
        end
    end

    if fileSystem:FileExists("tutorial_progress.json") then
        local f = File("tutorial_progress.json", FILE_READ)
        if f:IsOpen() then
            local ok, data = pcall(cjson.decode, f:ReadString())
            f:Close()
            if ok and type(data) == "table" then
                for _, key in ipairs(data) do
                    shown[key] = true
                end
            end
        end
    end
end

-- ============================================================================
-- 是否正在阻塞游戏（教程显示中 → 主循环应暂停）
-- ============================================================================
function Tutorial.IsBlocking()
    return Tutorial.currentTip ~= nil
end

-- ============================================================================
-- 点击位置是否在 banner 区域内（用于强制点击 banner 才能关闭）
-- 参数为设计坐标系下的 (x, y)
-- ============================================================================
function Tutorial.IsPointOnBanner(x, y)
    if not Tutorial.currentTip then return false end
    local r = bannerRect
    if r.w <= 0 or r.h <= 0 then return false end
    return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

-- ============================================================================
-- 保存进度
-- ============================================================================
local function SaveProgress()
    local list = {}
    for k, _ in pairs(shown) do
        table.insert(list, k)
    end
    local f = File("tutorial_progress.json", FILE_WRITE)
    if f:IsOpen() then
        f:WriteString(cjson.encode(list))
        f:Close()
    end
end

-- ============================================================================
-- 显示 / 关闭提示
-- ============================================================================
function Tutorial.Show(key)
    if shown[key] then return false end
    if Tutorial.currentTip then return false end  -- 已有提示正在显示
    if dismissCooldown > 0 then return false end  -- 冷却中，等玩家消化上一个
    if not TIPS[key] then return false end

    Tutorial.currentTip = key
    tipTimer = 0
    blinkT   = 0
    return true
end

function Tutorial.Dismiss()
    if not Tutorial.currentTip then return end
    shown[Tutorial.currentTip] = true
    Tutorial.currentTip = nil
    dismissCooldown = 0.6  -- 关闭后 0.6 秒内不弹新提示
    SaveProgress()
end

function Tutorial.IsShown(key)
    return shown[key] == true
end

-- ============================================================================
-- 条件检测 — 每帧在 HandleUpdate 中调用
-- ============================================================================
function Tutorial.CheckTriggers()
    if Tutorial.currentTip then return end  -- 已有提示
    if dismissCooldown > 0 then return end  -- 冷却中
    local player = G.player
    if not player.alive then return end

    -- 1) 开场: 移动+冲刺（等第一波 banner 消失后再弹出）
    if not shown["move_dash"] then
        if G.waveAnnounceTimer <= 0 then
            Tutorial.Show("move_dash")
        end
        return
    end

    -- 2) 靠近敌人 → 射击
    if not shown["shoot"] then
        for _, e in ipairs(G.enemies) do
            if e.hp > 0 then
                local dx = e.x - player.x
                local dy = e.y - player.y
                if dx * dx + dy * dy < 250 * 250 then
                    Tutorial.Show("shoot")
                    return
                end
            end
        end
    end

    -- 3) 弹药耗尽 → 换弹
    if not shown["reload"] then
        if player.ammo <= 0 and not player.reloading then
            Tutorial.Show("reload")
            return
        end
    end

    -- 4) 靠近箱子 → 搜刮教学
    if not shown["search_crate"] then
        local pc = math.floor(player.x / G.TILE_SIZE) + 1
        local pr = math.floor(player.y / G.TILE_SIZE) + 1
        -- 检查周围 3x3 范围
        for dr = -1, 1 do
            for dc = -1, 1 do
                local r, c = pr + dr, pc + dc
                if r >= 1 and r <= G.MAP_ROWS and c >= 1 and c <= G.MAP_COLS then
                    if G.mapData and G.mapData[r] and G.IsCrateTile(G.mapData[r][c]) then
                        Tutorial.Show("search_crate")
                        return
                    end
                end
            end
        end
    end

    -- 5) 出现"新"圣物 → 打开背包（排除游戏开始时的 starter artifact）
    if not shown["open_bag"] then
        for _, item in ipairs(G.lootItems) do
            if item.type == "artifact" and not initialArtifactRefs[item] then
                Tutorial.Show("open_bag")
                return
            end
        end
    end

    -- 6) 背包首次打开 → 管理教学
    if not shown["bag_manage"] then
        if InvUI.isOpen then
            Tutorial.Show("bag_manage")
            return
        end
    end
end

-- ============================================================================
-- 更新动画
-- ============================================================================
function Tutorial.Update(dt)
    -- dismiss 冷却递减（无论是否有当前提示）
    if dismissCooldown > 0 then
        dismissCooldown = dismissCooldown - dt
        if dismissCooldown < 0 then dismissCooldown = 0 end
    end
    if not Tutorial.currentTip then return end
    tipTimer = tipTimer + dt
    blinkT   = blinkT + dt
end

-- ============================================================================
-- 渲染 — 轻量弹窗，不遮挡游戏画面
-- ============================================================================
function Tutorial.Draw(vg, w, h)
    if not Tutorial.currentTip then return end
    local tip = TIPS[Tutorial.currentTip]
    if not tip then return end

    -- 淡入动画
    local fadeIn = math.min(1.0, tipTimer * 4.0)

    -- ── 极轻微的全屏暗化（alpha ~30），不遮挡游戏 ──
    local dimAlpha = math.floor(30 * fadeIn)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, dimAlpha))
    nvgFill(vg)

    -- ── 弹窗卡片 ──
    local desc = G.isMobile and tip.descMob or tip.descPC

    -- 计算卡片高度（根据文本行数）
    local lineCount = 1
    for _ in desc:gmatch("\n") do lineCount = lineCount + 1 end
    local cardW = 340
    local cardH = 56 + lineCount * 22 + 40  -- 标题+行+底部

    -- 位置：屏幕上方居中（不遮挡游戏主体）
    local cardX = (w - cardW) / 2
    local cardY = 40

    -- 记录 banner 区域用于点击检测
    bannerRect.x = cardX
    bannerRect.y = cardY
    bannerRect.w = cardW
    bannerRect.h = cardH

    local cardAlpha = math.floor(240 * fadeIn)

    -- 卡片背景（圆角，深色半透明）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cardX, cardY, cardW, cardH, 10)
    nvgFillColor(vg, nvgRGBA(15, 22, 40, cardAlpha))
    nvgFill(vg)

    -- 顶部装饰条
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cardX, cardY, cardW, 3, 10)
    nvgFillColor(vg, nvgRGBA(255, 200, 60, math.floor(200 * fadeIn)))
    nvgFill(vg)

    -- 卡片边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cardX, cardY, cardW, cardH, 10)
    nvgStrokeColor(vg, nvgRGBA(80, 120, 200, math.floor(120 * fadeIn)))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 220, 80, math.floor(255 * fadeIn)))
    nvgText(vg, cardX + cardW / 2, cardY + 12, tip.title, nil)

    -- 说明文字（支持多行）
    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(210, 220, 240, math.floor(240 * fadeIn)))
    local lineY = cardY + 40
    for line in desc:gmatch("[^\n]+") do
        nvgText(vg, cardX + cardW / 2, lineY, line, nil)
        lineY = lineY + 22
    end

    -- 进度指示点
    local dotY = cardY + cardH - 24
    local totalDots = #TIP_ORDER
    local dotSpacing = 12
    local dotsStartX = cardX + cardW / 2 - (totalDots - 1) * dotSpacing / 2

    -- 找到当前 tip 在 TIP_ORDER 中的索引
    local curIdx = 0
    for i, k in ipairs(TIP_ORDER) do
        if k == Tutorial.currentTip then curIdx = i; break end
    end

    for i = 1, totalDots do
        local dx = dotsStartX + (i - 1) * dotSpacing
        nvgBeginPath(vg)
        if i == curIdx then
            nvgCircle(vg, dx, dotY, 3.5)
            nvgFillColor(vg, nvgRGBA(255, 200, 60, math.floor(255 * fadeIn)))
        elseif shown[TIP_ORDER[i]] then
            nvgCircle(vg, dx, dotY, 2.5)
            nvgFillColor(vg, nvgRGBA(120, 160, 80, math.floor(180 * fadeIn)))
        else
            nvgCircle(vg, dx, dotY, 2.5)
            nvgFillColor(vg, nvgRGBA(100, 110, 130, math.floor(100 * fadeIn)))
        end
        nvgFill(vg)
    end

    -- "点击关闭" 提示（闪烁）
    local blinkAlpha = math.floor((120 + 60 * math.sin(blinkT * 4.0)) * fadeIn)
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(180, 190, 210, blinkAlpha))
    nvgText(vg, cardX + cardW / 2, cardY + cardH - 10, "点击此卡片继续", nil)
end

return Tutorial
