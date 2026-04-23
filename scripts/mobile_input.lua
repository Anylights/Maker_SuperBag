-- ============================================================================
-- mobile_input.lua — 移动端触控输入模块（双摇杆 + 操作按钮）
-- ============================================================================
local G = require("game_context")

local MI = {}

-- ============================================================================
-- 平台检测（自适应：默认PC，第一次TouchBegin时自动切换为移动端）
-- ============================================================================
function MI.DetectMobile()
    -- 不再在启动时检测：浏览器环境下 PlatformUtils.IsWebPlatform() 对PC/手机都返回true
    -- 改为在 MI_HandleTouchBegin 中首次收到真实触控事件时自动设置 G.isMobile = true
end

-- ============================================================================
-- 摇杆配置（设计坐标）
-- ============================================================================
local JOYSTICK_RADIUS   = 60   -- 底座半径
local JOYSTICK_DEADZONE = 8    -- 死区
local JOYSTICK_MAX_DRAG = 55   -- 最大拖拽距离
local THUMB_RADIUS      = 22   -- 拇指圆点半径

-- 按钮配置
local BTN_SIZE = 50
local BTN_CONFIGS = {
    reload  = { x = 1085, y = 400, label = "R",   key = "reload" },
    bag     = { x = 1085, y = 55,  label = "背包", key = "bag" },
    pickup  = { x = 1085, y = 115, label = "拾取", key = "pickup" },
    dash    = { x = 1020, y = 400, label = "冲",   key = "dash" },
}

-- ============================================================================
-- 运行时状态
-- ============================================================================

-- 左摇杆（移动）
local leftJoy = {
    touchID  = -1,
    active   = false,
    baseX    = 0, baseY = 0,   -- 触发时的触摸位置（作为底座中心）
    thumbX   = 0, thumbY = 0,  -- 当前拇指位置
}

-- 右摇杆（瞄准+射击）
local rightJoy = {
    touchID  = -1,
    active   = false,
    baseX    = 0, baseY = 0,
    thumbX   = 0, thumbY = 0,
}

-- 公开输出
MI.moveDX    = 0     -- 归一化移动方向 [-1, 1]
MI.moveDY    = 0
MI.aimAngle  = 0     -- 瞄准弧度
MI.isShooting = false -- 右摇杆是否激活（自动射击）

-- 按钮回调（由 main.lua 设置）
MI.onReload  = nil
MI.onBag     = nil
MI.onPickup  = nil
MI.onDash    = nil

-- ============================================================================
-- 初始化
-- ============================================================================
function MI.Init()
    SubscribeToEvent("TouchBegin", "MI_HandleTouchBegin")
    SubscribeToEvent("TouchMove",  "MI_HandleTouchMove")
    SubscribeToEvent("TouchEnd",   "MI_HandleTouchEnd")
end

-- ============================================================================
-- 触控坐标转换：物理屏幕 → 设计坐标
-- ============================================================================
local function TouchToDesign(tx, ty)
    return G.ScreenToDesign(tx, ty)
end

-- ============================================================================
-- 摇杆更新辅助
-- ============================================================================
local function UpdateJoystick(joy, dx, dy)
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist > JOYSTICK_MAX_DRAG then
        dx = dx / dist * JOYSTICK_MAX_DRAG
        dy = dy / dist * JOYSTICK_MAX_DRAG
        dist = JOYSTICK_MAX_DRAG
    end
    joy.thumbX = joy.baseX + dx
    joy.thumbY = joy.baseY + dy
    return dx, dy, dist
end

-- ============================================================================
-- 按钮碰撞检测
-- ============================================================================
local function HitTestButton(dx, dy)
    for name, btn in pairs(BTN_CONFIGS) do
        if dx >= btn.x and dx <= btn.x + BTN_SIZE
           and dy >= btn.y and dy <= btn.y + BTN_SIZE then
            return name
        end
    end
    return nil
end

-- ============================================================================
-- 事件处理
-- ============================================================================
function MI_HandleTouchBegin(eventType, eventData)
    -- 自适应检测：收到真实触控事件 → 切换为移动端模式
    -- PC浏览器不产生TouchBegin，手机浏览器第一次触摸时自动激活
    if not G.isMobile then
        G.isMobile = true
        print("[MI] 检测到触控输入，已切换为移动端模式")
    end

    local touchID = eventData["TouchID"]:GetInt()
    local px = eventData["X"]:GetInt()
    local py = eventData["Y"]:GetInt()
    local dx, dy = TouchToDesign(px, py)

    -- 先检测按钮
    local btnHit = HitTestButton(dx, dy)
    if btnHit then
        if btnHit == "reload"  and MI.onReload  then MI.onReload()  end
        if btnHit == "bag"     and MI.onBag     then MI.onBag()     end
        if btnHit == "pickup"  and MI.onPickup  then MI.onPickup()  end
        if btnHit == "dash"    and MI.onDash    then MI.onDash()    end
        return
    end

    local halfW = G.DESIGN_W / 2

    -- 左半屏 → 左摇杆（移动）
    if dx < halfW and not leftJoy.active then
        leftJoy.active  = true
        leftJoy.touchID = touchID
        leftJoy.baseX   = dx
        leftJoy.baseY   = dy
        leftJoy.thumbX  = dx
        leftJoy.thumbY  = dy
        return
    end

    -- 右半屏 → 右摇杆（瞄准）
    if dx >= halfW and not rightJoy.active then
        rightJoy.active  = true
        rightJoy.touchID = touchID
        rightJoy.baseX   = dx
        rightJoy.baseY   = dy
        rightJoy.thumbX  = dx
        rightJoy.thumbY  = dy
        return
    end
end

function MI_HandleTouchMove(eventType, eventData)
    local touchID = eventData["TouchID"]:GetInt()
    local px = eventData["X"]:GetInt()
    local py = eventData["Y"]:GetInt()
    local dx, dy = TouchToDesign(px, py)

    -- 左摇杆跟踪
    if leftJoy.active and leftJoy.touchID == touchID then
        local ox = dx - leftJoy.baseX
        local oy = dy - leftJoy.baseY
        local clampedX, clampedY, dist = UpdateJoystick(leftJoy, ox, oy)

        if dist > JOYSTICK_DEADZONE then
            MI.moveDX = clampedX / JOYSTICK_MAX_DRAG
            MI.moveDY = clampedY / JOYSTICK_MAX_DRAG
        else
            MI.moveDX = 0
            MI.moveDY = 0
        end
        return
    end

    -- 右摇杆跟踪
    if rightJoy.active and rightJoy.touchID == touchID then
        local ox = dx - rightJoy.baseX
        local oy = dy - rightJoy.baseY
        local clampedX, clampedY, dist = UpdateJoystick(rightJoy, ox, oy)

        if dist > JOYSTICK_DEADZONE then
            MI.aimAngle = math.atan(clampedY, clampedX)
            MI.isShooting = true
        else
            MI.isShooting = false
        end
        return
    end
end

function MI_HandleTouchEnd(eventType, eventData)
    local touchID = eventData["TouchID"]:GetInt()

    if leftJoy.active and leftJoy.touchID == touchID then
        leftJoy.active  = false
        leftJoy.touchID = -1
        MI.moveDX = 0
        MI.moveDY = 0
        return
    end

    if rightJoy.active and rightJoy.touchID == touchID then
        rightJoy.active  = false
        rightJoy.touchID = -1
        MI.isShooting = false
        return
    end
end

-- ============================================================================
-- NanoVG 渲染（设计坐标系，由 main.lua 在 HUD 层调用）
-- ============================================================================
local function DrawJoystick(vg, joy, isRight)
    local alpha = joy.active and 160 or 80

    -- 底座圆
    nvgBeginPath(vg)
    nvgCircle(vg, joy.baseX, joy.baseY, JOYSTICK_RADIUS)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(alpha * 0.3)))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, alpha))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 拇指圆点
    local tx = joy.active and joy.thumbX or joy.baseX
    local ty = joy.active and joy.thumbY or joy.baseY
    nvgBeginPath(vg)
    nvgCircle(vg, tx, ty, THUMB_RADIUS)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(alpha * 0.7)))
    nvgFill(vg)

    -- 方向指示（右摇杆激活时显示瞄准线）
    if isRight and joy.active and MI.isShooting then
        local lineLen = JOYSTICK_RADIUS * 0.8
        local lx = joy.baseX + math.cos(MI.aimAngle) * lineLen
        local ly = joy.baseY + math.sin(MI.aimAngle) * lineLen
        nvgBeginPath(vg)
        nvgMoveTo(vg, joy.baseX, joy.baseY)
        nvgLineTo(vg, lx, ly)
        nvgStrokeColor(vg, nvgRGBA(255, 100, 100, 180))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end
end

local function DrawButton(vg, btn, label)
    local alpha = 120

    -- 按钮背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btn.x, btn.y, BTN_SIZE, BTN_SIZE, 10)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(alpha * 0.5)))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, alpha))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(alpha * 0.9)))
    nvgText(vg, btn.x + BTN_SIZE / 2, btn.y + BTN_SIZE / 2, label, nil)
end

-- 默认摇杆位置（未触摸时的静态展示）
local DEFAULT_LEFT_X  = 120
local DEFAULT_LEFT_Y  = 520
local DEFAULT_RIGHT_X = 1032
local DEFAULT_RIGHT_Y = 520

function MI.DrawControls(w, h)
    local vg = G.vg

    -- 左摇杆
    local leftShow = {
        baseX  = leftJoy.active and leftJoy.baseX or DEFAULT_LEFT_X,
        baseY  = leftJoy.active and leftJoy.baseY or DEFAULT_LEFT_Y,
        thumbX = leftJoy.active and leftJoy.thumbX or DEFAULT_LEFT_X,
        thumbY = leftJoy.active and leftJoy.thumbY or DEFAULT_LEFT_Y,
        active = leftJoy.active,
    }
    DrawJoystick(vg, leftShow, false)

    -- 右摇杆
    local rightShow = {
        baseX  = rightJoy.active and rightJoy.baseX or DEFAULT_RIGHT_X,
        baseY  = rightJoy.active and rightJoy.baseY or DEFAULT_RIGHT_Y,
        thumbX = rightJoy.active and rightJoy.thumbX or DEFAULT_RIGHT_X,
        thumbY = rightJoy.active and rightJoy.thumbY or DEFAULT_RIGHT_Y,
        active = rightJoy.active,
    }
    DrawJoystick(vg, rightShow, true)

    -- 普通按钮
    for name, btn in pairs(BTN_CONFIGS) do
        if name ~= "dash" then
            DrawButton(vg, btn, btn.label)
        end
    end

    -- 冲刺按钮（带冷却遮罩）
    local dashBtn = BTN_CONFIGS.dash
    local dashCool = (G.player and G.player.dashCooldown) or 0
    local dashBusy = dashCool > 0 or ((G.player and G.player.dashTimer) or 0) > 0
    local dashAlpha = dashBusy and 60 or 120
    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dashBtn.x, dashBtn.y, BTN_SIZE, BTN_SIZE, 10)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(dashAlpha * 0.5)))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, dashAlpha))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    -- 文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(dashAlpha * 0.9)))
    nvgText(vg, dashBtn.x + BTN_SIZE / 2, dashBtn.y + BTN_SIZE / 2, dashBtn.label, nil)
    -- 冷却遮罩（从上往下的灰色遮罩）
    if dashCool > 0 then
        local maskH = BTN_SIZE * math.min(1, dashCool / 2.0)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, dashBtn.x, dashBtn.y, BTN_SIZE, maskH, 10)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
        nvgFill(vg)
    end
end

return MI
