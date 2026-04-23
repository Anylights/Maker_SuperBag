-- ============================================================================
-- comic_intro.lua — 开场分镜漫画系统
-- 3页8分镜，严格按照《开场分镜漫画脚本》
-- 童话黑森林 + 轻卡通 + 少年冒险感
-- Esc跳过 / 点击翻页 / 空格翻页
-- ============================================================================

local G = require("game_context")

local Comic = {}

-- 状态
Comic.active   = false
Comic.finished = false
Comic.page     = 1
Comic.timer    = 0
Comic.fadeIn   = 0
Comic.pageFade = 0
Comic.skipHintAlpha = 0

-- 图片句柄
Comic.images = {}

local FADE_IN_TIME  = 0.6
local PAGE_COUNT    = 3

-- ============================================================================
-- 每页的分镜布局：定义每个分镜在设计分辨率(1152x648)中的位置和大小
-- 第1页: 2个分镜（左大右小）
-- 第2页: 3个分镜（上1大 + 下2小）
-- 第3页: 3个分镜（上2小 + 下1大）
-- ============================================================================
local pageLayouts = {
    -- 第1页：出发（2分镜）
    {
        { imgIdx = 1, x = 8,   y = 8,   w = 680, h = 632 },   -- 分镜1：告别（大）
        { imgIdx = 2, x = 696, y = 8,   w = 448, h = 632 },   -- 分镜2：独行（窄长）
    },
    -- 第2页：相遇与转折（3分镜）
    {
        { imgIdx = 3, x = 8,   y = 8,   w = 1136, h = 340 },  -- 分镜3：拦路（宽幅）
        { imgIdx = 4, x = 8,   y = 356, w = 560,  h = 284 },  -- 分镜4：哀求（左下）
        { imgIdx = 5, x = 576, y = 356, w = 568,  h = 284 },  -- 分镜5：放行（右下）
    },
    -- 第3页：绑架与启程（3分镜）
    {
        { imgIdx = 6, x = 8,   y = 8,   w = 560,  h = 340 },  -- 分镜6：伏击（左上）
        { imgIdx = 7, x = 576, y = 8,   w = 568,  h = 340 },  -- 分镜7：震惊（右上）
        { imgIdx = 8, x = 8,   y = 356, w = 1136, h = 284 },  -- 分镜8：启程（宽幅底）
    },
}

-- ============================================================================
-- 对话气泡数据：严格按照分镜脚本的文字内容
-- pos: 基于设计分辨率(1152x648)的气泡中心坐标
-- style: "narrate"(旁白) | "speech"(对话) | "shout"(喊叫) | "thought"(思考)
-- delay: 出现延迟(秒)
-- ============================================================================
local pageBubbles = {
    -- ====== 第1页: 出发 ======
    {
        -- 分镜1 旁白
        {
            text = "小狼成年这天，\n父亲让他独自进森林历练。",
            style = "narrate",
            pos = { x = 200, y = 50 },
            maxW = 320,
            delay = 0.3,
        },
        -- 分镜1 父亲对话
        {
            text = "你该自己去看看\n外面的世界了。",
            style = "speech",
            pos = { x = 450, y = 540 },
            maxW = 260,
            delay = 1.0,
        },
        -- 分镜2 旁白
        {
            text = "他想证明，\n自己已经是一只真正的狼。",
            style = "narrate",
            pos = { x = 920, y = 100 },
            maxW = 300,
            delay = 1.8,
        },
    },

    -- ====== 第2页: 相遇与转折 ======
    {
        -- 分镜3 旁白
        {
            text = "途中，他拦下了\n前往外婆家的小红帽。",
            style = "narrate",
            pos = { x = 200, y = 30 },
            maxW = 340,
            delay = 0.3,
        },
        -- 分镜3 小狼喊叫
        {
            text = "站住，把东西留下！",
            style = "shout",
            pos = { x = 860, y = 250 },
            maxW = 260,
            delay = 0.9,
        },
        -- 分镜4 小红帽对话
        {
            text = "求你别抢……\n我外婆病得很重，\n这些药必须送到。",
            style = "speech",
            pos = { x = 290, y = 460 },
            maxW = 280,
            delay = 1.6,
        },
        -- 分镜5 旁白
        {
            text = "小狼被她打动，\n最终还是放她离开。",
            style = "narrate",
            pos = { x = 750, y = 380 },
            maxW = 260,
            delay = 2.2,
        },
        -- 分镜5 小狼对话
        {
            text = "快走，\n我这次不抢你。",
            style = "speech",
            pos = { x = 680, y = 560 },
            maxW = 230,
            delay = 2.8,
        },
    },

    -- ====== 第3页: 绑架与启程 ======
    {
        -- 分镜6 旁白
        {
            text = "可暗中埋伏的\n大灰狼集团，\n立刻掳走了她。",
            style = "narrate",
            pos = { x = 160, y = 30 },
            maxW = 280,
            delay = 0.3,
        },
        -- 分镜6 小红帽呼救
        {
            text = "救命！",
            style = "shout",
            pos = { x = 400, y = 260 },
            maxW = 150,
            delay = 0.8,
        },
        -- 分镜7 旁白
        {
            text = "这一刻，他第一次明白，\n强大不是欺负弱小，\n而是敢于承担后果。",
            style = "narrate",
            pos = { x = 860, y = 50 },
            maxW = 340,
            delay = 1.4,
        },
        -- 分镜8 旁白
        {
            text = "于是，小狼背起行囊，\n踏上了拯救小红帽的旅程。",
            style = "narrate",
            pos = { x = 576, y = 400 },
            maxW = 400,
            delay = 2.2,
        },
    },
}

-- 图片文件路径（8张分镜）
local imageFiles = {
    "comic/panel1_farewell.png",
    "comic/panel2_departure.png",
    "comic/panel3_encounter.png",
    "comic/panel4_plea.png",
    "comic/panel5_letgo.png",
    "comic/panel6_ambush.png",
    "comic/panel7_shock.png",
    "comic/panel8_resolve.png",
}

-- ============================================================================
-- 初始化
-- ============================================================================
function Comic.Init(vg)
    Comic.active   = true
    Comic.finished = false
    Comic.page     = 1
    Comic.timer    = 0
    Comic.fadeIn   = 0
    Comic.pageFade = 0
    Comic.skipHintAlpha = 0

    -- 加载8张分镜图片
    for i, path in ipairs(imageFiles) do
        Comic.images[i] = nvgCreateImage(vg, path, 0)
        if Comic.images[i] == 0 or Comic.images[i] == -1 then
            print("[Comic] WARNING: Failed to load " .. path)
        end
    end
    print("[Comic] Intro initialized, " .. #Comic.images .. " panels loaded")
end

-- ============================================================================
-- 更新
-- ============================================================================
function Comic.Update(dt)
    if not Comic.active then return end

    if Comic.fadeIn < 1 then
        Comic.fadeIn = math.min(1, Comic.fadeIn + dt / FADE_IN_TIME)
    end

    Comic.timer = Comic.timer + dt
    Comic.pageFade = math.min(1, Comic.timer / 0.8)
    Comic.skipHintAlpha = 0.4 + 0.3 * math.sin(Comic.timer * 2.5)
end

-- ============================================================================
-- 翻页 / 跳过
-- ============================================================================
function Comic.NextPage()
    if not Comic.active then return end

    if Comic.page < PAGE_COUNT then
        Comic.page = Comic.page + 1
        Comic.timer = 0
        Comic.pageFade = 0
    else
        Comic.Skip()
    end
end

function Comic.Skip()
    Comic.active   = false
    Comic.finished = true
    print("[Comic] Intro skipped/finished")
end

-- ============================================================================
-- 绘制单个分镜面板（图片 + 漫画边框）
-- ============================================================================
local function DrawPanel(vg, panel, alpha, DW, DH)
    local img = Comic.images[panel.imgIdx]
    if not img or img <= 0 then return end

    local px, py, pw, ph = panel.x, panel.y, panel.w, panel.h

    nvgSave(vg)
    nvgScissor(vg, px, py, pw, ph)

    -- 图片 cover 模式填充面板区域
    local imgW, imgH = 1024, 1536
    local imgAspect = imgW / imgH
    local panelAspect = pw / ph

    local drawW, drawH, drawX, drawY
    if panelAspect > imgAspect then
        drawW = pw
        drawH = pw / imgAspect
        drawX = px
        drawY = py + (ph - drawH) / 2
    else
        drawH = ph
        drawW = ph * imgAspect
        drawX = px + (pw - drawW) / 2
        drawY = py
    end

    local imgPaint = nvgImagePattern(vg, drawX, drawY, drawW, drawH, 0, img, alpha)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, ph, 4)
    nvgFillPaint(vg, imgPaint)
    nvgFill(vg)

    nvgResetScissor(vg)
    nvgRestore(vg)

    -- 漫画格子边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, ph, 4)
    nvgStrokeColor(vg, nvgRGBA(30, 25, 20, math.floor(220 * alpha)))
    nvgStrokeWidth(vg, 2.5)
    nvgStroke(vg)
end

-- ============================================================================
-- 绘制对话气泡
-- ============================================================================
local function DrawBubble(vg, bubble, alpha, DW, DH)
    local bx = bubble.pos.x
    local by = bubble.pos.y
    local style = bubble.style
    local maxW = bubble.maxW or 300

    nvgFontFace(vg, "sans")

    -- 根据样式选择字号和颜色
    local fontSize, textColor, bgColor, borderColor, borderW
    if style == "narrate" then
        fontSize = 17
        textColor = nvgRGBA(240, 235, 220, math.floor(255 * alpha))
        bgColor = nvgRGBA(10, 10, 15, math.floor(210 * alpha))
        borderColor = nvgRGBA(180, 170, 140, math.floor(150 * alpha))
        borderW = 1.5
    elseif style == "shout" then
        fontSize = 21
        textColor = nvgRGBA(255, 240, 200, math.floor(255 * alpha))
        bgColor = nvgRGBA(140, 30, 20, math.floor(220 * alpha))
        borderColor = nvgRGBA(255, 100, 50, math.floor(200 * alpha))
        borderW = 2.5
    elseif style == "thought" then
        fontSize = 15
        textColor = nvgRGBA(200, 220, 255, math.floor(240 * alpha))
        bgColor = nvgRGBA(15, 25, 50, math.floor(200 * alpha))
        borderColor = nvgRGBA(80, 140, 220, math.floor(160 * alpha))
        borderW = 1.5
    else -- speech
        fontSize = 16
        textColor = nvgRGBA(255, 255, 255, math.floor(250 * alpha))
        bgColor = nvgRGBA(20, 20, 30, math.floor(200 * alpha))
        borderColor = nvgRGBA(200, 200, 210, math.floor(180 * alpha))
        borderW = 2
    end

    nvgFontSize(vg, fontSize)

    -- 计算多行文本尺寸
    local lines = {}
    for line in bubble.text:gmatch("[^\n]+") do
        table.insert(lines, line)
    end

    local lineH = fontSize * 1.45
    local textH = #lines * lineH
    local textW = 0
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    for _, line in ipairs(lines) do
        local advance, bounds = nvgTextBounds(vg, 0, 0, line)
        if bounds then
            local lw = bounds[3] - bounds[1]
            if lw > textW then textW = lw end
        elseif advance then
            if advance > textW then textW = advance end
        end
    end
    textW = math.min(textW, maxW)

    local padX = 14
    local padY = 10
    local boxW = textW + padX * 2
    local boxH = textH + padY * 2
    local boxX = bx - boxW / 2
    local boxY = by - boxH / 2

    -- 确保不越界
    if boxX < 6 then boxX = 6 end
    if boxX + boxW > DW - 6 then boxX = DW - 6 - boxW end
    if boxY < 6 then boxY = 6 end
    if boxY + boxH > DH - 6 then boxY = DH - 6 - boxH end

    -- 气泡阴影
    nvgBeginPath(vg)
    nvgRoundedRect(vg, boxX + 2, boxY + 2, boxW, boxH, 7)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(90 * alpha)))
    nvgFill(vg)

    -- 气泡背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, boxX, boxY, boxW, boxH, 7)
    nvgFillColor(vg, bgColor)
    nvgFill(vg)

    -- 气泡边框
    nvgStrokeColor(vg, borderColor)
    nvgStrokeWidth(vg, borderW)
    nvgStroke(vg)

    -- 对话指示三角（speech 和 shout 样式）
    if style == "speech" or style == "shout" then
        local triX = math.max(boxX + 16, math.min(boxX + boxW - 16, bx))
        local triY = boxY + boxH
        nvgBeginPath(vg)
        nvgMoveTo(vg, triX - 6, triY - 1)
        nvgLineTo(vg, triX, triY + 8)
        nvgLineTo(vg, triX + 6, triY - 1)
        nvgClosePath(vg)
        nvgFillColor(vg, bgColor)
        nvgFill(vg)
    end

    -- 思考泡的小圆点
    if style == "thought" then
        for i = 1, 3 do
            nvgBeginPath(vg)
            nvgCircle(vg, boxX + boxW / 2 - 10 + i * 7,
                boxY + boxH + 3 + i * 4, 1.5 + i * 0.8)
            nvgFillColor(vg, bgColor)
            nvgFill(vg)
            nvgStrokeColor(vg, borderColor)
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end
    end

    -- 绘制文字
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, textColor)
    nvgFontSize(vg, fontSize)
    local startY = boxY + padY + lineH / 2
    for li, line in ipairs(lines) do
        nvgText(vg, boxX + boxW / 2, startY + (li - 1) * lineH, line, nil)
    end
end

-- ============================================================================
-- 绘制
-- ============================================================================
function Comic.Draw(vg, screenW, screenH)
    if not Comic.active then return end

    local DW = G.DESIGN_W
    local DH = G.DESIGN_H

    local scaleX = screenW / DW
    local scaleY = screenH / DH
    local scale  = math.min(scaleX, scaleY)
    local offX   = (screenW - DW * scale) / 2
    local offY   = (screenH - DH * scale) / 2

    nvgSave(vg)
    nvgTranslate(vg, offX, offY)
    nvgScale(vg, scale, scale)

    local globalAlpha = Comic.fadeIn

    -- 全屏黑底
    nvgBeginPath(vg)
    nvgRect(vg, -offX / scale, -offY / scale, screenW / scale, screenH / scale)
    nvgFillColor(vg, nvgRGBA(8, 8, 12, math.floor(255 * globalAlpha)))
    nvgFill(vg)

    -- 页面底色（米黄旧纸感）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 0, 0, DW, DH, 6)
    nvgFillColor(vg, nvgRGBA(35, 30, 25, math.floor(240 * globalAlpha)))
    nvgFill(vg)

    -- 绘制当前页面的所有分镜面板
    local layout = pageLayouts[Comic.page]
    if layout then
        local imgAlpha = globalAlpha * Comic.pageFade
        for _, panel in ipairs(layout) do
            DrawPanel(vg, panel, imgAlpha, DW, DH)
        end
    end

    -- 绘制当前页面的对话气泡（逐个淡入）
    local bubbles = pageBubbles[Comic.page]
    if bubbles then
        for _, bubble in ipairs(bubbles) do
            local bDelay = bubble.delay or 0
            local elapsed = Comic.timer - bDelay
            if elapsed > 0 then
                local bAlpha = math.min(1, elapsed / 0.5) * globalAlpha
                DrawBubble(vg, bubble, bAlpha, DW, DH)
            end
        end
    end

    -- 漫画外边框
    nvgStrokeColor(vg, nvgRGBA(50, 45, 35, math.floor(200 * globalAlpha)))
    nvgStrokeWidth(vg, 3)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 2, 2, DW - 4, DH - 4, 6)
    nvgStroke(vg)

    -- 页码指示器（底部圆点）
    local dotR = 4
    local dotGap = 16
    local dotsW = PAGE_COUNT * dotGap
    local dotBaseX = DW / 2 - dotsW / 2 + dotGap / 2
    local dotBaseY = DH - 18
    for i = 1, PAGE_COUNT do
        nvgBeginPath(vg)
        nvgCircle(vg, dotBaseX + (i - 1) * dotGap, dotBaseY, dotR)
        if i == Comic.page then
            nvgFillColor(vg, nvgRGBA(255, 210, 100, math.floor(230 * globalAlpha)))
        else
            nvgFillColor(vg, nvgRGBA(100, 90, 70, math.floor(140 * globalAlpha)))
        end
        nvgFill(vg)
    end

    -- 跳过/翻页提示
    local hintAlpha = math.floor(Comic.skipHintAlpha * 255 * globalAlpha)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(180, 170, 140, hintAlpha))
    if Comic.page < PAGE_COUNT then
        nvgText(vg, DW - 24, DH - 10, "点击翻页  |  Esc 跳过", nil)
    else
        nvgText(vg, DW - 24, DH - 10, "点击开始游戏  |  Esc 跳过", nil)
    end

    -- 页码文字
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(140, 130, 110, math.floor(110 * globalAlpha)))
    nvgText(vg, DW - 14, 14,
        string.format("%d / %d", Comic.page, PAGE_COUNT), nil)

    nvgRestore(vg)
end

return Comic
