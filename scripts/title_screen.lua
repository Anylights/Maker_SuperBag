-- ============================================================================
-- title_screen.lua — 标题页面
-- 背景图 + 标题"拯救小红帽" + 开始游戏/退出游戏/声音设置
-- ============================================================================

local G = require("game_context")

local Title = {}

-- 公共状态
Title.active   = false
Title.finished = false

-- 内部状态
local bgImage     = -1
local timer        = 0
local fadeIn       = 0
local hoverBtn     = 0       -- 0=无, 1=开始, 2=声音设置, 3=退出
local showSettings = false   -- 是否展开声音设置面板
local settingsAnim = 0       -- 0~1 面板展开动画

-- 音量（0~1）
local sfxVolume   = 0.8
local musicVolume = 0.5

-- 滑条拖拽
local dragging     = 0  -- 0=无, 1=音效滑条, 2=音乐滑条

-- 按钮定义（基于设计分辨率 1152x648）
local DW, DH = 1152, 648
local BTN_W, BTN_H = 220, 48
local BTN_X = DW / 2  -- 按钮中心X
local BTN_START_Y  = 380
local BTN_SOUND_Y  = 445
local BTN_EXIT_Y   = 510

-- 设置面板
local PANEL_W  = 320
local PANEL_H  = 160
local PANEL_X  = DW / 2 - PANEL_W / 2
local PANEL_Y  = BTN_SOUND_Y + BTN_H / 2 + 10

-- 滑条参数
local SLIDER_W     = 200
local SLIDER_H     = 8
local SLIDER_KNOB  = 14
local SLIDER_X     = PANEL_X + PANEL_W / 2 + 20
local SLIDER_SFX_Y   = PANEL_Y + 50
local SLIDER_MUSIC_Y = PANEL_Y + 110

-- ============================================================================
-- 初始化
-- ============================================================================
function Title.Init(vg)
    Title.active   = true
    Title.finished = false
    timer      = 0
    fadeIn      = 0
    hoverBtn   = 0
    showSettings = false
    settingsAnim = 0
    dragging   = 0

    -- 读取当前音量
    sfxVolume   = audio:GetMasterGain(SOUND_EFFECT)
    musicVolume = audio:GetMasterGain(SOUND_MUSIC)

    bgImage = nvgCreateImage(vg, "comic/title_bg.png", 0)
    if bgImage <= 0 then
        print("[Title] WARNING: Failed to load title_bg.png")
    end
    print("[Title] Title screen initialized")
end

-- ============================================================================
-- 更新
-- ============================================================================
function Title.Update(dt)
    if not Title.active then return end
    timer = timer + dt
    if fadeIn < 1 then
        fadeIn = math.min(1, fadeIn + dt / 0.8)
    end
    -- 设置面板动画
    if showSettings then
        settingsAnim = math.min(1, settingsAnim + dt / 0.25)
    else
        settingsAnim = math.max(0, settingsAnim - dt / 0.2)
    end
end

-- ============================================================================
-- 辅助：判断点击是否在矩形内（居中按钮）
-- ============================================================================
local function InCenterBtn(mx, my, cy)
    local bx = BTN_X - BTN_W / 2
    local by = cy - BTN_H / 2
    return mx >= bx and mx <= bx + BTN_W and my >= by and my <= by + BTN_H
end

-- ============================================================================
-- 辅助：获取滑条值
-- ============================================================================
local function SliderValueFromX(mx, sliderX)
    local left = sliderX
    local right = sliderX + SLIDER_W
    local v = (mx - left) / (right - left)
    return math.max(0, math.min(1, v))
end

-- ============================================================================
-- 鼠标按下
-- ============================================================================
function Title.HandleMouseDown(mx, my, button)
    if not Title.active then return false end
    if button ~= MOUSEB_LEFT then return false end

    -- 设置面板内的滑条
    if settingsAnim > 0.5 then
        -- 音效滑条
        if my >= SLIDER_SFX_Y - SLIDER_KNOB and my <= SLIDER_SFX_Y + SLIDER_KNOB
            and mx >= SLIDER_X - SLIDER_KNOB and mx <= SLIDER_X + SLIDER_W + SLIDER_KNOB then
            dragging = 1
            sfxVolume = SliderValueFromX(mx, SLIDER_X)
            audio:SetMasterGain(SOUND_EFFECT, sfxVolume)
            return true
        end
        -- 音乐滑条
        if my >= SLIDER_MUSIC_Y - SLIDER_KNOB and my <= SLIDER_MUSIC_Y + SLIDER_KNOB
            and mx >= SLIDER_X - SLIDER_KNOB and mx <= SLIDER_X + SLIDER_W + SLIDER_KNOB then
            dragging = 2
            musicVolume = SliderValueFromX(mx, SLIDER_X)
            audio:SetMasterGain(SOUND_MUSIC, musicVolume)
            return true
        end
    end

    -- 开始游戏
    if InCenterBtn(mx, my, BTN_START_Y) then
        Title.active   = false
        Title.finished = true
        print("[Title] Start game!")
        return true
    end

    -- 声音设置
    if InCenterBtn(mx, my, BTN_SOUND_Y) then
        showSettings = not showSettings
        return true
    end

    -- 退出游戏
    if InCenterBtn(mx, my, BTN_EXIT_Y) then
        print("[Title] Exit game")
        engine:Exit()
        return true
    end

    return false
end

-- ============================================================================
-- 鼠标移动（滑条拖拽 + 按钮高亮）
-- ============================================================================
function Title.HandleMouseMove(mx, my)
    if not Title.active then return false end

    -- 拖拽滑条
    if dragging == 1 then
        sfxVolume = SliderValueFromX(mx, SLIDER_X)
        audio:SetMasterGain(SOUND_EFFECT, sfxVolume)
        return true
    elseif dragging == 2 then
        musicVolume = SliderValueFromX(mx, SLIDER_X)
        audio:SetMasterGain(SOUND_MUSIC, musicVolume)
        return true
    end

    -- 按钮悬停检测
    if InCenterBtn(mx, my, BTN_START_Y) then
        hoverBtn = 1
    elseif InCenterBtn(mx, my, BTN_SOUND_Y) then
        hoverBtn = 2
    elseif InCenterBtn(mx, my, BTN_EXIT_Y) then
        hoverBtn = 3
    else
        hoverBtn = 0
    end
    return false
end

-- ============================================================================
-- 鼠标抬起
-- ============================================================================
function Title.HandleMouseUp(mx, my, button)
    if dragging > 0 then
        dragging = 0
        return true
    end
    return false
end

-- ============================================================================
-- 键盘
-- ============================================================================
function Title.HandleKeyDown(key)
    if not Title.active then return false end
    if key == KEY_RETURN or key == KEY_SPACE then
        Title.active   = false
        Title.finished = true
        return true
    end
    if key == KEY_ESCAPE then
        if showSettings then
            showSettings = false
            return true
        end
    end
    return false
end

-- ============================================================================
-- 触摸
-- ============================================================================
function Title.HandleTouch(tx, ty)
    return Title.HandleMouseDown(tx, ty, MOUSEB_LEFT)
end

-- ============================================================================
-- 绘制按钮辅助
-- ============================================================================
local function DrawButton(vg, text, cy, btnIdx, alpha)
    local bx = BTN_X - BTN_W / 2
    local by = cy - BTN_H / 2
    local isHover = (hoverBtn == btnIdx)
    local pulse = isHover and (1 + 0.03 * math.sin(timer * 6)) or 1

    -- 按钮阴影
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx + 2, by + 3, BTN_W, BTN_H, 10)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(80 * alpha)))
    nvgFill(vg)

    -- 按钮背景
    local bgA = isHover and 220 or 180
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx, by, BTN_W * pulse, BTN_H * pulse, 10)
    if btnIdx == 1 then
        -- 开始游戏 - 绿色调
        nvgFillColor(vg, nvgRGBA(40, 120, 60, math.floor(bgA * alpha)))
    elseif btnIdx == 3 then
        -- 退出 - 暗红
        nvgFillColor(vg, nvgRGBA(100, 35, 30, math.floor(bgA * alpha)))
    else
        -- 设置 - 暗蓝
        nvgFillColor(vg, nvgRGBA(40, 55, 90, math.floor(bgA * alpha)))
    end
    nvgFill(vg)

    -- 边框
    nvgStrokeColor(vg, nvgRGBA(220, 200, 160, math.floor((isHover and 200 or 120) * alpha)))
    nvgStrokeWidth(vg, isHover and 2.5 or 1.5)
    nvgStroke(vg)

    -- 文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 245, 220, math.floor(255 * alpha)))
    nvgText(vg, BTN_X, cy, text, nil)
end

-- ============================================================================
-- 绘制滑条
-- ============================================================================
local function DrawSlider(vg, label, sliderY, value, alpha)
    -- 标签
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 210, 190, math.floor(230 * alpha)))
    nvgText(vg, SLIDER_X - 14, sliderY, label, nil)

    -- 滑条背景轨道
    nvgBeginPath(vg)
    nvgRoundedRect(vg, SLIDER_X, sliderY - SLIDER_H / 2, SLIDER_W, SLIDER_H, 4)
    nvgFillColor(vg, nvgRGBA(40, 40, 50, math.floor(180 * alpha)))
    nvgFill(vg)

    -- 已填充部分
    local fillW = SLIDER_W * value
    if fillW > 0 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, SLIDER_X, sliderY - SLIDER_H / 2, fillW, SLIDER_H, 4)
        nvgFillColor(vg, nvgRGBA(120, 180, 100, math.floor(220 * alpha)))
        nvgFill(vg)
    end

    -- 滑块圆点
    local knobX = SLIDER_X + fillW
    nvgBeginPath(vg)
    nvgCircle(vg, knobX, sliderY, SLIDER_KNOB / 2)
    nvgFillColor(vg, nvgRGBA(255, 240, 200, math.floor(255 * alpha)))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(180, 160, 120, math.floor(200 * alpha)))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 百分比
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 190, 170, math.floor(180 * alpha)))
    nvgText(vg, SLIDER_X + SLIDER_W + 10, sliderY,
        string.format("%d%%", math.floor(value * 100)), nil)
end

-- ============================================================================
-- 绘制
-- ============================================================================
function Title.Draw(vg, screenW, screenH)
    if not Title.active then return end

    local scaleX = screenW / DW
    local scaleY = screenH / DH
    local scale  = math.min(scaleX, scaleY)
    local offX   = (screenW - DW * scale) / 2
    local offY   = (screenH - DH * scale) / 2

    nvgSave(vg)
    nvgTranslate(vg, offX, offY)
    nvgScale(vg, scale, scale)

    local alpha = fadeIn

    -- 全屏黑底
    nvgBeginPath(vg)
    nvgRect(vg, -offX / scale, -offY / scale, screenW / scale, screenH / scale)
    nvgFillColor(vg, nvgRGBA(5, 5, 8, math.floor(255 * alpha)))
    nvgFill(vg)

    -- 背景图（cover 模式）
    if bgImage and bgImage > 0 then
        local imgW, imgH = 1536, 1024
        local imgAspect = imgW / imgH
        local screenAspect = DW / DH

        local drawW, drawH, drawX, drawY
        if screenAspect > imgAspect then
            drawW = DW
            drawH = DW / imgAspect
            drawX = 0
            drawY = (DH - drawH) / 2
        else
            drawH = DH
            drawW = DH * imgAspect
            drawX = (DW - drawW) / 2
            drawY = 0
        end

        local imgPaint = nvgImagePattern(vg, drawX, drawY, drawW, drawH, 0, bgImage, alpha * 0.85)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DW, DH)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)
    end

    -- 半透明暗色覆盖层（让文字和按钮更清晰）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DW, DH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(100 * alpha)))
    nvgFill(vg)

    -- 顶部渐变（让标题区域更暗）
    local topGrad = nvgLinearGradient(vg, 0, 0, 0, 250,
        nvgRGBA(0, 0, 0, math.floor(160 * alpha)),
        nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, DW, 250)
    nvgFillPaint(vg, topGrad)
    nvgFill(vg)

    -- 底部渐变
    local botGrad = nvgLinearGradient(vg, 0, DH - 200, 0, DH,
        nvgRGBA(0, 0, 0, 0),
        nvgRGBA(0, 0, 0, math.floor(180 * alpha)))
    nvgBeginPath(vg)
    nvgRect(vg, 0, DH - 200, DW, 200)
    nvgFillPaint(vg, botGrad)
    nvgFill(vg)

    -- ============ 标题 ============
    nvgFontFace(vg, "sans")

    -- 标题阴影
    nvgFontSize(vg, 56)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(180 * alpha)))
    nvgText(vg, DW / 2 + 3, 160 + 3, "拯救小红帽", nil)

    -- 标题文字（带轻微浮动动画）
    local titleY = 160 + math.sin(timer * 1.5) * 4
    nvgFontSize(vg, 56)
    nvgFillColor(vg, nvgRGBA(255, 230, 160, math.floor(255 * alpha)))
    nvgText(vg, DW / 2, titleY, "拯救小红帽", nil)

    -- 副标题
    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(200, 190, 160, math.floor(180 * alpha)))
    nvgText(vg, DW / 2, titleY + 46, "— 小狼少年的冒险之旅 —", nil)

    -- 装饰线
    local lineW = 180
    nvgBeginPath(vg)
    nvgMoveTo(vg, DW / 2 - lineW, titleY + 70)
    nvgLineTo(vg, DW / 2 + lineW, titleY + 70)
    nvgStrokeColor(vg, nvgRGBA(200, 180, 120, math.floor(100 * alpha)))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- ============ 按钮 ============
    DrawButton(vg, "开始游戏", BTN_START_Y, 1, alpha)
    DrawButton(vg, "声音设置", BTN_SOUND_Y, 2, alpha)
    DrawButton(vg, "退出游戏", BTN_EXIT_Y, 3, alpha)

    -- ============ 声音设置面板 ============
    if settingsAnim > 0.01 then
        local pAlpha = alpha * settingsAnim
        local pScale = 0.8 + 0.2 * settingsAnim
        local panelCenterX = PANEL_X + PANEL_W / 2
        local panelCenterY = PANEL_Y + PANEL_H / 2

        nvgSave(vg)
        nvgTranslate(vg, panelCenterX, PANEL_Y)
        nvgScale(vg, pScale, pScale)
        nvgTranslate(vg, -panelCenterX, -PANEL_Y)

        -- 面板背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, PANEL_X, PANEL_Y, PANEL_W, PANEL_H, 12)
        nvgFillColor(vg, nvgRGBA(15, 18, 28, math.floor(230 * pAlpha)))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(100, 90, 70, math.floor(150 * pAlpha)))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 面板标题
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(255, 240, 200, math.floor(220 * pAlpha)))
        nvgText(vg, PANEL_X + PANEL_W / 2, PANEL_Y + 14, "声音设置", nil)

        -- 分隔线
        nvgBeginPath(vg)
        nvgMoveTo(vg, PANEL_X + 20, PANEL_Y + 36)
        nvgLineTo(vg, PANEL_X + PANEL_W - 20, PANEL_Y + 36)
        nvgStrokeColor(vg, nvgRGBA(80, 70, 50, math.floor(120 * pAlpha)))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 滑条
        DrawSlider(vg, "音效", SLIDER_SFX_Y, sfxVolume, pAlpha)
        DrawSlider(vg, "音乐", SLIDER_MUSIC_Y, musicVolume, pAlpha)

        nvgRestore(vg)
    end

    -- ============ 底部提示 ============
    local hintA = 0.4 + 0.3 * math.sin(timer * 2.5)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(160, 150, 120, math.floor(hintA * 255 * alpha)))
    nvgText(vg, DW / 2, DH - 12, "按空格键或点击「开始游戏」", nil)

    nvgRestore(vg)
end

return Title
