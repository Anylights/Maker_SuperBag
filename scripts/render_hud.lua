-- ============================================================================
-- render_hud.lua — HUD / 菜单 / 结算画面渲染（屏幕空间/设计分辨率坐标）
-- ============================================================================
local G       = require("game_context")
local WM      = require("wave_manager")
local Inv     = require("inventory")
local InvData = require("inventory_data")
local InvUI   = require("inventory_ui")

local RH = {}

-- 常量别名
local TILE_SIZE       = G.TILE_SIZE
-- MAP_COLS/MAP_ROWS/MAP_W/MAP_H 随波次动态变化，不缓存，直接使用 G.*
local TILE_WALL       = G.TILE_WALL
local TILE_EXIT       = G.TILE_EXIT
local TILE_CRATE_WOOD = G.TILE_CRATE_WOOD
local TILE_CRATE_IRON = G.TILE_CRATE_IRON
local TILE_CRATE_GOLD = G.TILE_CRATE_GOLD
local WEAPON          = G.WEAPON
local DEATH_ANIM_DURATION = G.DEATH_ANIM_DURATION

-- ============================================================================
-- 局部辅助
-- ============================================================================

--- 奖励图标 (简单几何图形)
local function DrawRewardIcon(cx, cy, size, iconType, selected)
    local vg = G.vg
    local r = size / 2
    local alpha = selected and 255 or 180

    if iconType == "ammo" then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - 4, cy - r, 8, size, 3)
        nvgFillColor(vg, nvgRGBA(220, 180, 60, alpha))
        nvgFill(vg)
    elseif iconType == "health" then
        local t = 5
        nvgBeginPath(vg)
        nvgRect(vg, cx - t, cy - r, t * 2, size)
        nvgFillColor(vg, nvgRGBA(60, 220, 80, alpha))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, cx - r, cy - t, size, t * 2)
        nvgFillColor(vg, nvgRGBA(60, 220, 80, alpha))
        nvgFill(vg)
    elseif iconType == "shield" then
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, r)
        nvgFillColor(vg, nvgRGBA(80, 160, 255, alpha))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, r * 0.5)
        nvgFillColor(vg, nvgRGBA(40, 80, 180, alpha))
        nvgFill(vg)
    elseif iconType == "damage" then
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx, cy - r)
        nvgLineTo(vg, cx + r * 0.6, cy)
        nvgLineTo(vg, cx, cy + r)
        nvgLineTo(vg, cx - r * 0.6, cy)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(255, 100, 60, alpha))
        nvgFill(vg)
    elseif iconType == "speed" then
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - r, cy + r * 0.5)
        nvgLineTo(vg, cx + r * 0.5, cy)
        nvgLineTo(vg, cx - r, cy - r * 0.5)
        nvgStrokeColor(vg, nvgRGBA(100, 255, 200, alpha))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
    elseif iconType == "mag" then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - r * 0.5, cy - r, r, size, 2)
        nvgFillColor(vg, nvgRGBA(180, 140, 80, alpha))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, cx - r * 0.7, cy - 2, r * 1.4, 4)
        nvgFillColor(vg, nvgRGBA(255, 220, 80, alpha))
        nvgFill(vg)
    elseif iconType == "rate" then
        for ii = -1, 1, 2 do
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx - r * 0.5 + ii * 3, cy + r * 0.5)
            nvgLineTo(vg, cx + r * 0.3 + ii * 3, cy)
            nvgLineTo(vg, cx - r * 0.5 + ii * 3, cy - r * 0.5)
            nvgStrokeColor(vg, nvgRGBA(255, 200, 100, alpha))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end
    else
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, r * 0.7)
        nvgFillColor(vg, nvgRGBA(180, 180, 180, alpha))
        nvgFill(vg)
    end
end

-- ============================================================================
-- 公开渲染函数
-- ============================================================================

--- 波次清除公告 (PHASE_CLEARED 时显示)
function RH.DrawWaveCleared(w, h)
    local vg = G.vg

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 100))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    local pulse = math.sin(GetTime():GetElapsedTime() * 5) * 0.2 + 0.8
    nvgFontSize(vg, 32)
    nvgFillColor(vg, nvgRGBA(80, 255, 120, math.floor(255 * pulse)))
    nvgText(vg, w / 2, h / 2 - 20, "敌人已清除!", nil)

    local wave = WM.GetCurrentWave()
    local desc = wave and wave.name or ""
    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(200, 220, 200, 200))
    nvgText(vg, w / 2, h / 2 + 16,
        "Wave " .. WM.currentWave .. " 「" .. desc .. "」 完成", nil)

    local remaining = math.max(0, math.ceil(WM.phaseTimer))
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(180, 180, 180, 180))
    nvgText(vg, w / 2, h / 2 + 44,
        remaining .. " 秒后开放出口...", nil)
end

--- 出口方向指示器
function RH.DrawExitIndicator(w, h)
    if not WM.exitReady then return end
    local vg = G.vg
    local player = G.player
    local camX, camY, camZoom = G.camX, G.camY, G.camZoom

    local t = GetTime():GetElapsedTime()

    local exitScreenX = (WM.exitX - camX) * camZoom
    local exitScreenY = (WM.exitY - camY) * camZoom

    local margin = 60
    local onScreen = exitScreenX > margin and exitScreenX < w - margin
                 and exitScreenY > margin and exitScreenY < h - margin

    local playerScreenX = (player.x - camX) * camZoom
    local playerScreenY = (player.y - camY) * camZoom

    local angle = math.atan(exitScreenY - playerScreenY, exitScreenX - playerScreenX)
    local dist = math.sqrt((WM.exitX - player.x)^2 + (WM.exitY - player.y)^2)

    if not onScreen then
        local arrowDist = math.min(w, h) * 0.4
        local ax = w / 2 + math.cos(angle) * arrowDist
        local ay = h / 2 + math.sin(angle) * arrowDist
        ax = math.max(40, math.min(w - 40, ax))
        ay = math.max(40, math.min(h - 40, ay))

        local pulse = 0.7 + 0.3 * math.sin(t * 4)
        local arrowAlpha = math.floor(220 * pulse)

        nvgBeginPath(vg)
        nvgCircle(vg, ax, ay, 18)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 140))
        nvgFill(vg)

        nvgSave(vg)
        nvgTranslate(vg, ax, ay)
        nvgRotate(vg, angle)
        nvgBeginPath(vg)
        nvgMoveTo(vg, 12, 0)
        nvgLineTo(vg, -6, -8)
        nvgLineTo(vg, -6, 8)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(80, 255, 120, arrowAlpha))
        nvgFill(vg)
        nvgRestore(vg)

        local distText = math.floor(dist / TILE_SIZE) .. "m"
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 255, 200, arrowAlpha))
        nvgText(vg, ax, ay + 24, distText, nil)
    end

    local hintPulse = 0.6 + 0.4 * math.sin(t * 3)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    if WM.phase == WM.PHASE_WALKOUT then
        nvgFillColor(vg, nvgRGBA(80, 255, 120, math.floor(255 * hintPulse)))
        nvgText(vg, w / 2, 48, "正在撤离...", nil)
    else
        nvgFillColor(vg, nvgRGBA(80, 255, 120, math.floor(200 * hintPulse)))
        nvgText(vg, w / 2, 48, "前往出口撤离!", nil)

        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(180, 220, 180, 180))
        nvgText(vg, w / 2, 68, math.floor(dist / TILE_SIZE) .. " 米", nil)
    end
end

--- 奖励选择界面 (PHASE_REWARD 时显示)
function RH.DrawRewardScreen(w, h)
    local vg = G.vg

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    local wave = WM.GetCurrentWave()
    local isSupply = (wave and wave.rewardType == "supply")

    if isSupply then
        nvgFontSize(vg, 25)
        nvgFillColor(vg, nvgRGBA(100, 220, 255, 255))
        nvgText(vg, w / 2, h / 2 - 40, "发现补给!", nil)

        nvgFontSize(vg, 15)
        nvgFillColor(vg, nvgRGBA(200, 220, 200, 220))
        nvgText(vg, w / 2, h / 2, "弹药 +20  HP +25", nil)

        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(180, 180, 180, 180))
        nvgText(vg, w / 2, h / 2 + 35, "点击继续", nil)
    else
        nvgFontSize(vg, 24)
        nvgFillColor(vg, nvgRGBA(255, 220, 80, 255))
        nvgText(vg, w / 2, h * 0.18, "选择装备强化", nil)

        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(180, 180, 180, 200))
        nvgText(vg, w / 2, h * 0.18 + 24, "点击卡片选择  |  数字键 1-3 快捷选择", nil)

        local choices = WM.rewardChoices
        local cardCount = #choices
        if cardCount == 0 then return end

        local cardW = 140
        local cardH = 170
        local gap = 20
        local totalW = cardCount * cardW + (cardCount - 1) * gap
        local startX = (w - totalW) / 2
        local cardY = (h - cardH) / 2 + 10

        local rawMX = input:GetMousePosition().x
        local rawMY = input:GetMousePosition().y
        local mouseDX, mouseDY = G.ScreenToDesign(rawMX, rawMY)

        for i, reward in ipairs(choices) do
            local cx = startX + (i - 1) * (cardW + gap)
            local hovered = (mouseDX >= cx and mouseDX <= cx + cardW
                and mouseDY >= cardY and mouseDY <= cardY + cardH)

            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx, cardY, cardW, cardH, 10)
            if hovered then
                nvgFillColor(vg, nvgRGBA(55, 60, 90, 245))
            else
                nvgFillColor(vg, nvgRGBA(35, 38, 55, 220))
            end
            nvgFill(vg)

            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx, cardY, cardW, cardH, 10)
            if hovered then
                local glow = math.sin(GetTime():GetElapsedTime() * 4) * 0.3 + 0.7
                nvgStrokeColor(vg, nvgRGBA(255, 220, 80, math.floor(220 * glow)))
                nvgStrokeWidth(vg, 2.5)
            else
                nvgStrokeColor(vg, nvgRGBA(80, 85, 100, 160))
                nvgStrokeWidth(vg, 1)
            end
            nvgStroke(vg)

            local iconY = cardY + 25
            local iconSize = 32
            local iconCX = cx + cardW / 2
            DrawRewardIcon(iconCX, iconY + iconSize / 2, iconSize, reward.icon, hovered)

            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            if hovered then
                nvgFillColor(vg, nvgRGBA(255, 240, 200, 255))
            else
                nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
            end
            nvgText(vg, cx + cardW / 2, iconY + iconSize + 20, reward.name, nil)

            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(160, 170, 180, 200))
            nvgText(vg, cx + cardW / 2, iconY + iconSize + 42, reward.desc, nil)

            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBA(120, 120, 130, 160))
            nvgText(vg, cx + cardW / 2, cardY + cardH - 16, "[" .. i .. "]", nil)
        end
    end
end

--- 波次开始公告 (waveAnnounceTimer > 0 时显示)
function RH.DrawWaveAnnounce(w, h)
    local vg = G.vg
    local waveAnnounceTimer = G.waveAnnounceTimer

    local alpha = math.min(1.0, waveAnnounceTimer / 0.5)
    if waveAnnounceTimer < 0.5 then
        alpha = waveAnnounceTimer / 0.5
    end
    local a = math.floor(255 * alpha)

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    local bandH = 70
    local bandY = h / 2 - bandH / 2
    nvgBeginPath(vg)
    nvgRect(vg, 0, bandY, w, bandH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(140 * alpha)))
    nvgFill(vg)

    local wave = WM.GetCurrentWave()
    local waveName = wave and wave.name or ""
    nvgFontSize(vg, 25)
    nvgFillColor(vg, nvgRGBA(255, 220, 80, a))
    nvgText(vg, w / 2, h / 2 - 12,
        "Wave " .. WM.currentWave .. " — " .. waveName, nil)

    if wave and wave.desc then
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(200, 210, 220, math.floor(a * 0.8)))
        nvgText(vg, w / 2, h / 2 + 16, wave.desc, nil)
    end
end

--- Boss血条 (屏幕顶部)
function RH.DrawBossHPBar(w, h)
    if not WM.boss then return end
    local vg = G.vg

    local boss = WM.boss
    local barW = math.min(400, w * 0.5)
    local barH = 14
    local barX = (w - barW) / 2
    local barY = 8

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(255, 100, 80, 240))
    nvgText(vg, w / 2, barY - 2, boss.name or "BOSS", nil)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 4)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgFill(vg)

    local hpRatio = math.max(0, boss.hp / boss.maxHp)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW * hpRatio, barH, 4)
    local phase = WM.GetBossPhase(boss)
    if phase == 1 then
        nvgFillColor(vg, nvgRGBA(220, 60, 60, 240))
    elseif phase == 2 then
        nvgFillColor(vg, nvgRGBA(220, 140, 40, 240))
    else
        local pulse = math.sin(GetTime():GetElapsedTime() * 8) * 0.3 + 0.7
        nvgFillColor(vg, nvgRGBA(255, 40, 40, math.floor(240 * pulse)))
    end
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 4)
    nvgStrokeColor(vg, nvgRGBA(200, 80, 60, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
    nvgText(vg, w / 2, barY + barH / 2,
        math.floor(boss.hp) .. " / " .. boss.maxHp, nil)
end

--- HUD 主界面
function RH.DrawHUD(w, h, getNearbyArtifactLoot)
    local vg = G.vg
    local player = G.player

    nvgFontFace(vg, "sans")

    -- === 左上: 血条 ===
    local hpBarX = 16
    local hpBarY = 16
    local hpBarW = 160
    local hpBarH = 16
    local effectiveMaxHp = player.maxHp + Inv.GetStat("maxHp", 0)
    local hpRatio = player.hp / effectiveMaxHp

    nvgBeginPath(vg)
    nvgRoundedRect(vg, hpBarX, hpBarY, hpBarW, hpBarH, 4)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, hpBarX, hpBarY, hpBarW * hpRatio, hpBarH, 4)
    if hpRatio > 0.5 then
        nvgFillColor(vg, nvgRGBA(60, 200, 60, 240))
    elseif hpRatio > 0.25 then
        nvgFillColor(vg, nvgRGBA(220, 180, 40, 240))
    else
        local pulse = math.sin(GetTime():GetElapsedTime() * 8) * 0.3 + 0.7
        nvgFillColor(vg, nvgRGBA(220, 50, 50, math.floor(240 * pulse)))
    end
    nvgFill(vg)

    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, hpBarX + hpBarW / 2, hpBarY + hpBarH / 2,
        math.floor(player.hp) .. " / " .. math.floor(effectiveMaxHp), nil)

    -- === 护盾条 ===
    if player.shieldMax > 0 then
        local shieldBarY = hpBarY + hpBarH + 2
        local shieldBarH = 8
        local shieldRatio = player.shield / player.shieldMax
        nvgBeginPath(vg)
        nvgRoundedRect(vg, hpBarX, shieldBarY, hpBarW, shieldBarH, 3)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
        nvgFill(vg)
        if shieldRatio > 0 then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, hpBarX, shieldBarY, hpBarW * shieldRatio, shieldBarH, 3)
            nvgFillColor(vg, nvgRGBA(80, 160, 255, 220))
            nvgFill(vg)
        end
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 230, 255, 255))
        nvgText(vg, hpBarX + hpBarW / 2, shieldBarY + shieldBarH / 2,
            "🛡 " .. math.floor(player.shield) .. "/" .. math.floor(player.shieldMax), nil)
    end

    -- === 弹药 ===
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    local ammoColor
    if player.reloading then
        ammoColor = nvgRGBA(255, 200, 60, 255)
    elseif player.ammo <= 3 then
        ammoColor = nvgRGBA(255, 80, 80, 255)
    else
        ammoColor = nvgRGBA(255, 255, 255, 255)
    end
    local ammoText
    if player.reloading then
        ammoText = WEAPON.name .. "  换弹中..."
    elseif player.ammo <= 0 and player.totalAmmo <= 0 then
        ammoText = "近战模式  (点击攻击)"
        ammoColor = nvgRGBA(255, 160, 60, 255)
    else
        ammoText = WEAPON.name .. "  " .. player.ammo .. " / " .. player.totalAmmo
    end
    nvgFillColor(vg, ammoColor)
    local ammoYOff = player.shieldMax > 0 and (hpBarH + 12 + 6) or (hpBarH + 6)
    nvgText(vg, hpBarX, hpBarY + ammoYOff, ammoText, nil)

    -- === 右上: 波次信息 ===
    local wave = WM.GetCurrentWave()
    local waveName = wave and wave.name or ("第" .. WM.currentWave .. "波")
    local waveLabel = "Wave " .. WM.currentWave .. "/" .. #WM.WAVES .. "  " .. waveName
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 220, 80, 240))
    nvgText(vg, w - 16, 16, waveLabel, nil)

    -- === 右上第二行: 时间 + 击杀 ===
    local timeMin = math.floor(G.gameTime / 60)
    local timeSec = math.floor(G.gameTime % 60)
    local timeStr = string.format("%d:%02d", timeMin, timeSec)
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
    nvgText(vg, w - 16, 36, timeStr .. "  击杀:" .. G.killCount .. "  分数:" .. G.score, nil)

    -- === 右上第三行: 剩余敌人 ===
    local enemyAlive = #G.enemies
    if enemyAlive > 0 then
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(255, 120, 120, 200))
        nvgText(vg, w - 16, 54, "敌人剩余: " .. enemyAlive, nil)
    end

    -- === 附近可拾取配件提示 ===
    if not InvUI.isOpen and getNearbyArtifactLoot then
        local nearbyArtifacts = getNearbyArtifactLoot(60)
        if #nearbyArtifacts > 0 then
            local pulse = math.sin(GetTime():GetElapsedTime() * 4) * 0.3 + 0.7
            local notifyAlpha = math.floor(255 * pulse)

            local nbW = 220
            local nbH = 28
            local nbX = (w - nbW) / 2
            local nbY = h - 56

            nvgBeginPath(vg)
            nvgRoundedRect(vg, nbX, nbY, nbW, nbH, 6)
            nvgFillColor(vg, nvgRGBA(30, 30, 50, math.floor(200 * pulse)))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(255, 200, 80, math.floor(180 * pulse)))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            nvgFontSize(vg, 12)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 220, 80, notifyAlpha))
            nvgText(vg, w / 2, nbY + nbH / 2,
                "按 F 拾取 (" .. #nearbyArtifacts .. "个配件)", nil)
        end
    end

    -- === 底部: 操作提示 ===
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 160))
    nvgText(vg, w / 2, h - 12, "WASD移动 | 鼠标瞄准 | 左键射击 | R换弹 | Tab背包", nil)

    -- === 小地图 ===
    RH.DrawMinimap(w, h)
end

function RH.DrawMinimap(sw, sh)
    local vg = G.vg
    local player = G.player
    local mapData = G.mapData

    local mmSize = 100
    local mmX = sw - mmSize - 12
    local mmY = sh - mmSize - 30
    local scale = mmSize / math.max(G.MAP_W, G.MAP_H)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, mmX - 2, mmY - 2, mmSize + 4, mmSize + 4, 4)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgFill(vg)

    for r = 1, G.MAP_ROWS do
        for c = 1, G.MAP_COLS do
            local tile = mapData[r][c]
            if tile ~= TILE_WALL then
                local tx = mmX + (c - 1) * TILE_SIZE * scale
                local ty = mmY + (r - 1) * TILE_SIZE * scale
                local tw = math.max(1, TILE_SIZE * scale)

                nvgBeginPath(vg)
                nvgRect(vg, tx, ty, tw, tw)

                if tile == TILE_CRATE_WOOD then
                    nvgFillColor(vg, nvgRGBA(180, 140, 60, 200))
                elseif tile == TILE_CRATE_IRON then
                    nvgFillColor(vg, nvgRGBA(160, 190, 220, 200))
                elseif tile == TILE_CRATE_GOLD then
                    nvgFillColor(vg, nvgRGBA(255, 200, 50, 200))
                elseif tile == TILE_EXIT then
                    nvgFillColor(vg, nvgRGBA(80, 255, 80, 200))
                else
                    nvgFillColor(vg, nvgRGBA(80, 85, 90, 200))
                end
                nvgFill(vg)
            end
        end
    end

    for _, e in ipairs(G.enemies) do
        nvgBeginPath(vg)
        nvgCircle(vg, mmX + e.x * scale, mmY + e.y * scale, 1.5)
        nvgFillColor(vg, nvgRGBA(255, 80, 80, 220))
        nvgFill(vg)
    end

    nvgBeginPath(vg)
    nvgCircle(vg, mmX + player.x * scale, mmY + player.y * scale, 2.5)
    nvgFillColor(vg, nvgRGBA(60, 255, 60, 255))
    nvgFill(vg)
end

--- 死亡电影化渲染
function RH.DrawDeathCinematic(w, h)
    local vg = G.vg
    local progress = math.min(1.0, G.deathAnimTimer / DEATH_ANIM_DURATION)

    local grayAlpha = math.floor(math.min(140, progress * 200))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(30, 30, 35, grayAlpha))
    nvgFill(vg)

    local textProgress = math.max(0, (progress - 0.4) / 0.6)
    if textProgress > 0 then
        local textAlpha = math.floor(math.min(255, textProgress * 300))
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        nvgFontSize(vg, 36)
        local textOffY = (1.0 - math.min(1.0, textProgress * 2)) * 20
        nvgFillColor(vg, nvgRGBA(220, 60, 60, textAlpha))
        nvgText(vg, w / 2, h / 2 - 10 + textOffY, "你失败了...", nil)

        if textProgress > 0.4 then
            local subAlpha = math.floor(math.min(180, (textProgress - 0.4) * 350))
            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(180, 180, 180, subAlpha))
            nvgText(vg, w / 2, h / 2 + 30 + textOffY,
                "进度: Wave " .. WM.currentWave .. "/" .. #WM.WAVES, nil)
        end
    end

    local vignetteAlpha = math.floor(math.min(80, progress * 120))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    local vignette = nvgRadialGradient(vg, w/2, h/2, math.min(w,h)*0.3, math.max(w,h)*0.7,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, vignetteAlpha))
    nvgFillPaint(vg, vignette)
    nvgFill(vg)
end

function RH.DrawEndScreen(w, h)
    local vg = G.vg

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgFill(vg)

    local isVictory = (G.gameState == G.STATE_VICTORY)

    local panelW = math.min(340, w - 40)
    local panelH = isVictory and 260 or 220
    local panelX = (w - panelW) / 2
    local panelY = (h - panelH) / 2

    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 12)
    nvgFillColor(vg, nvgRGBA(30, 35, 50, 240))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 12)
    if isVictory then
        nvgStrokeColor(vg, nvgRGBA(255, 200, 60, 220))
    else
        nvgStrokeColor(vg, nvgRGBA(220, 80, 80, 200))
    end
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    nvgFontSize(vg, 28)
    if isVictory then
        local pulse = math.sin(GetTime():GetElapsedTime() * 3) * 0.15 + 0.85
        nvgFillColor(vg, nvgRGBA(255, 220, 60, math.floor(255 * pulse)))
        nvgText(vg, w / 2, panelY + 42, "小红帽获救!", nil)
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(180, 220, 255, 220))
        nvgText(vg, w / 2, panelY + 68, "大灰狼集团已被击溃!", nil)
    else
        nvgFillColor(vg, nvgRGBA(255, 80, 80, 255))
        nvgText(vg, w / 2, panelY + 45, "小狼倒下了...", nil)
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(180, 180, 180, 200))
        nvgText(vg, w / 2, panelY + 72,
            "进度: Wave " .. WM.currentWave .. "/" .. #WM.WAVES, nil)
    end

    local statY = panelY + 100
    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
    nvgText(vg, w / 2, statY, "击退灰狼: " .. G.killCount, nil)
    nvgText(vg, w / 2, statY + 25, "分数: " .. G.score, nil)

    local survMin = math.floor(G.gameTime / 60)
    local survSec = math.floor(G.gameTime % 60)
    nvgText(vg, w / 2, statY + 50,
        string.format("冒险用时: %d:%02d", survMin, survSec), nil)

    if isVictory then
        local modsText = {}
        if WM.weaponMods.bonusDamage > 0 then
            table.insert(modsText, "攻击+" .. WM.weaponMods.bonusDamage)
        end
        if WM.weaponMods.bonusMagSize > 0 then
            table.insert(modsText, "弹匣+" .. WM.weaponMods.bonusMagSize)
        end
        if #modsText > 0 then
            nvgFontSize(vg, 12)
            nvgFillColor(vg, nvgRGBA(160, 220, 255, 200))
            nvgText(vg, w / 2, statY + 78,
                "获得强化: " .. table.concat(modsText, "  "), nil)
        end
    end

    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(160, 160, 160, 200))
    local bottomY = panelY + panelH - 30
    nvgText(vg, w / 2, bottomY, "点击任意处再次出发", nil)
end

return RH
