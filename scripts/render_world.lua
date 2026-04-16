-- ============================================================================
-- render_world.lua — 世界空间渲染（地图/玩家/敌人/子弹/粒子等）
-- ============================================================================
local G       = require("game_context")
local InvData = require("inventory_data")
local InvUI   = require("inventory_ui")

local RW = {}

-- 常量别名(不可变, 模块加载时缓存)
local TILE_SIZE       = G.TILE_SIZE
-- MAP_COLS/MAP_ROWS 随波次动态变化，不可缓存为局部变量，直接使用 G.MAP_COLS/G.MAP_ROWS
-- MAP_W/MAP_H 也随波次变化，不可缓存
local TILE_FLOOR      = G.TILE_FLOOR
local TILE_WALL       = G.TILE_WALL
local TILE_EXIT       = G.TILE_EXIT
local TILE_CRATE_WOOD = G.TILE_CRATE_WOOD
local TILE_CRATE_IRON = G.TILE_CRATE_IRON
local TILE_CRATE_GOLD = G.TILE_CRATE_GOLD
local SLASH_FRAME_COUNT = G.SLASH_FRAME_COUNT
local BULLET_FX_COLORS  = G.BULLET_FX_COLORS
local WEAPON            = G.WEAPON

-- ============================================================================
-- 局部辅助
-- ============================================================================

local function DrawTileImage(tileImg, x, y)
    local vg = G.vg
    local paint = nvgImagePattern(vg, x, y, TILE_SIZE, TILE_SIZE, 0, tileImg, 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, TILE_SIZE, TILE_SIZE)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 绘制纯白描边(用白色剪影图片在8个方向偏移绘制, 形成贴合轮廓的白色描边)
local function DrawWhiteOutline(whiteImg, halfSize, imgSize)
    local vg = G.vg
    local offDist = 1.5
    local dirs = {
        {1,0}, {-1,0}, {0,1}, {0,-1},
        {0.707,0.707}, {-0.707,0.707}, {0.707,-0.707}, {-0.707,-0.707},
    }
    for _, d in ipairs(dirs) do
        local ox, oy = d[1] * offDist, d[2] * offDist
        local paint = nvgImagePattern(vg, -halfSize + ox, -halfSize + oy, imgSize, imgSize, 0, whiteImg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, -halfSize + ox, -halfSize + oy, imgSize, imgSize)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end
end

-- 绘制红色轮廓描边(用于敌人)
local function DrawRedOutline(redImg, halfSize, imgSize)
    if not redImg or redImg < 0 then return end
    local vg = G.vg
    local offDist = 1.5
    local dirs = {
        {1,0}, {-1,0}, {0,1}, {0,-1},
        {0.707,0.707}, {-0.707,0.707}, {0.707,-0.707}, {-0.707,-0.707},
    }
    for _, d in ipairs(dirs) do
        local ox, oy = d[1] * offDist, d[2] * offDist
        local paint = nvgImagePattern(vg, -halfSize + ox, -halfSize + oy, imgSize, imgSize, 0, redImg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, -halfSize + ox, -halfSize + oy, imgSize, imgSize)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end
end

-- ============================================================================
-- 公开渲染函数
-- ============================================================================

function RW.DrawMap(viewW, viewH)
    local vg = G.vg
    local mapData = G.mapData
    local camX, camY, camZoom = G.camX, G.camY, G.camZoom

    -- 缩放后的世界可见区域
    local zoomViewW = viewW / camZoom
    local zoomViewH = viewH / camZoom
    -- 计算 SHOW_ALL 额外可见区域
    local extraW = (G.renderOffsetX or 0) / ((G.renderScale or 1) * camZoom)
    local extraH = (G.renderOffsetY or 0) / ((G.renderScale or 1) * camZoom)

    -- 深色森林背景填充
    nvgBeginPath(vg)
    nvgRect(vg, camX - extraW - 1, camY - extraH - 1, zoomViewW + extraW * 2 + 2, zoomViewH + extraH * 2 + 2)
    nvgFillColor(vg, nvgRGBA(20, 35, 15, 255))
    nvgFill(vg)

    -- 扩展绘制范围覆盖额外可见区域
    local startCol = math.max(1, math.floor((camX - extraW) / TILE_SIZE))
    local endCol = math.min(G.MAP_COLS, math.ceil((camX + zoomViewW + extraW) / TILE_SIZE) + 1)
    local startRow = math.max(1, math.floor((camY - extraH) / TILE_SIZE))
    local endRow = math.min(G.MAP_ROWS, math.ceil((camY + zoomViewH + extraH) / TILE_SIZE) + 1)

    for r = startRow, endRow do
        for c = startCol, endCol do
            local tile = mapData[r][c]
            local x = (c - 1) * TILE_SIZE
            local y = (r - 1) * TILE_SIZE

            if tile == TILE_WALL then
                local hash4 = ((r * 7 + c * 13) % 4) + 1
                local hash8 = ((r * 7 + c * 13) % 8) + 1
                local adjacentFloor = false
                local dirs4 = {{-1,0},{1,0},{0,-1},{0,1}}
                for _, d in ipairs(dirs4) do
                    local nr, nc = r + d[1], c + d[2]
                    if nr >= 1 and nr <= G.MAP_ROWS and nc >= 1 and nc <= G.MAP_COLS then
                        if mapData[nr][nc] == TILE_FLOOR or G.IsCrateTile(mapData[nr][nc]) or mapData[nr][nc] == TILE_EXIT then
                            adjacentFloor = true
                            break
                        end
                    end
                end
                if adjacentFloor then
                    DrawTileImage(G.imgEdgeTiles[hash8], x, y)
                else
                    local nearFloor = false
                    for dr = -1, 1 do
                        for dc = -1, 1 do
                            local nr, nc = r + dr, c + dc
                            if nr >= 1 and nr <= G.MAP_ROWS and nc >= 1 and nc <= G.MAP_COLS then
                                if mapData[nr][nc] == TILE_FLOOR or G.IsCrateTile(mapData[nr][nc]) or mapData[nr][nc] == TILE_EXIT then
                                    nearFloor = true
                                end
                            end
                        end
                    end
                    if nearFloor then
                        DrawTileImage(G.imgForestTiles[hash4], x, y)
                    else
                        DrawTileImage(G.imgDarkTiles[hash4], x, y)
                    end
                end
            elseif tile == TILE_FLOOR then
                local hash = ((r * 7 + c * 13) % 4) + 1
                DrawTileImage(G.imgFloorTiles[hash], x, y)
            elseif G.IsCrateTile(tile) then
                local hash = ((r * 7 + c * 13) % 4) + 1
                DrawTileImage(G.imgFloorTiles[hash], x, y)
                local crateImg = G.imgCrateByType[tile]
                if crateImg then
                    DrawTileImage(crateImg, x, y)
                end
            elseif tile == TILE_EXIT then
                local hash = ((r * 7 + c * 13) % 4) + 1
                DrawTileImage(G.imgFloorTiles[hash], x, y)
                local pulse = math.sin(GetTime():GetElapsedTime() * 3) * 0.3 + 0.7
                local ga = math.floor(120 * pulse)
                nvgBeginPath(vg)
                nvgRect(vg, x, y, TILE_SIZE, TILE_SIZE)
                nvgFillColor(vg, nvgRGBA(30, 200, 50, ga))
                nvgFill(vg)
            end
        end
    end
end

function RW.DrawPlayer()
    local vg = G.vg
    local player = G.player
    if not player.alive then return end

    local px, py = player.x + player.recoilX, player.y + player.recoilY
    local r = player.radius

    -- 受伤闪烁
    local alpha = 255
    if player.invincibleTimer > 0 then
        alpha = math.floor(math.sin(player.invincibleTimer * 30) * 127 + 128)
    end

    -- 移动时摇摆动画
    local isMoving = (input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_A) or
                      input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_D))
    local wobble = 0
    if isMoving then
        wobble = math.sin(G.gameTimeAcc * 8) * 0.15
    end

    -- 绘制角色图片
    local imgSize = r * 2.8
    local halfSize = imgSize / 2

    nvgSave(vg)
    nvgTranslate(vg, px, py)
    nvgRotate(vg, wobble)
    nvgGlobalAlpha(vg, alpha / 255)

    if G.imgPlayer >= 0 then
        local facingRight = (math.cos(player.angle) >= 0)
        if facingRight then
            nvgScale(vg, -1, 1)
        end
        DrawWhiteOutline(G.imgPlayerWhite, halfSize, imgSize)
        local paint = nvgImagePattern(vg, -halfSize, -halfSize, imgSize, imgSize, 0, G.imgPlayer, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, -halfSize, -halfSize, imgSize, imgSize)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    else
        nvgBeginPath(vg)
        nvgCircle(vg, 0, 0, r)
        nvgFillColor(vg, nvgRGBA(60, 180, 80, 255))
        nvgFill(vg)
    end

    nvgRestore(vg)

    -- 换弹环形进度条
    if player.reloading then
        local progress = 1.0 - (player.reloadTimer / WEAPON.reloadTime)
        progress = math.max(0, math.min(1, progress))

        local ringRadius = 6
        local ringY = py - r - 10
        local lineWidth = 3
        local startAngle = -math.pi / 2

        local endAngle = startAngle + progress * math.pi * 2

        nvgBeginPath(vg)
        nvgArc(vg, px, ringY, ringRadius, 0, math.pi * 2, NVG_CW)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 40))
        nvgStrokeWidth(vg, lineWidth)
        nvgStroke(vg)

        if progress > 0.01 then
            nvgBeginPath(vg)
            nvgArc(vg, px, ringY, ringRadius, startAngle, endAngle, NVG_CW)
            nvgStrokeColor(vg, nvgRGBA(100, 220, 255, 230))
            nvgStrokeWidth(vg, lineWidth)
            nvgLineCap(vg, NVG_ROUND)
            nvgStroke(vg)
        end
    end

    -- 近战挥击特效(序列帧动画)
    if player.meleeSwingTimer > 0 then
        local rawT = 1.0 - (player.meleeSwingTimer / player.meleeSwingDur)
        local easedT = 1.0 - (1.0 - rawT) * (1.0 - rawT)
        local frameIdx = math.floor(easedT * SLASH_FRAME_COUNT) + 1
        if frameIdx > SLASH_FRAME_COUNT then frameIdx = SLASH_FRAME_COUNT end
        local frameImg = G.imgSlashFrames[frameIdx]

        local slashAlpha = rawT < 0.7 and 1.0 or (1.0 - (rawT - 0.7) / 0.3)
        local scaleT = math.min(rawT / 0.15, 1.0)
        local scale = 0.6 + 0.4 * (1.0 - (1.0 - scaleT) * (1.0 - scaleT))

        local meleeR = player.meleeRange + player.radius
        local drawSize = meleeR * 2.0 * scale
        local drawW = drawSize
        local drawH = drawSize * (150 / 126)

        nvgSave(vg)
        nvgTranslate(vg, px, py)
        nvgRotate(vg, player.angle + math.pi * 0.5)

        local offsetX = -drawW * 0.5
        local offsetY = -drawH * 0.85
        local imgPat = nvgImagePattern(vg,
            offsetX, offsetY, drawW, drawH,
            0, frameImg, slashAlpha)
        nvgBeginPath(vg)
        nvgRect(vg, offsetX, offsetY, drawW, drawH)
        nvgFillPaint(vg, imgPat)
        nvgFill(vg)

        nvgRestore(vg)
    end
end

function RW.DrawDrones()
    local vg = G.vg

    for _, d in ipairs(G.drones) do
        nvgSave(vg)
        nvgTranslate(vg, d.x, d.y)

        -- 光晕底座
        nvgBeginPath(vg)
        nvgCircle(vg, 0, 0, 12)
        nvgFillColor(vg, nvgRGBA(160, 120, 255, 40))
        nvgFill(vg)

        -- 机身: 小菱形
        nvgSave(vg)
        nvgRotate(vg, d.angle)
        nvgBeginPath(vg)
        nvgMoveTo(vg, 8, 0)
        nvgLineTo(vg, -4, -5)
        nvgLineTo(vg, -6, 0)
        nvgLineTo(vg, -4, 5)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(140, 110, 220, 230))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(200, 180, 255, 200))
        nvgStrokeWidth(vg, 1.0)
        nvgStroke(vg)

        -- 炮口亮点
        nvgBeginPath(vg)
        nvgCircle(vg, 8, 0, 2)
        nvgFillColor(vg, nvgRGBA(220, 200, 255, 255))
        nvgFill(vg)
        nvgRestore(vg)

        -- 推进器尾焰
        local flicker = 0.6 + 0.4 * math.sin(G.gameTimeAcc * 15 + d.orbitAngle)
        local tailX = -math.cos(d.angle) * 7
        local tailY = -math.sin(d.angle) * 7
        nvgBeginPath(vg)
        nvgCircle(vg, tailX, tailY, 2.5 + flicker)
        nvgFillColor(vg, nvgRGBA(180, 140, 255, math.floor(120 * flicker)))
        nvgFill(vg)

        nvgRestore(vg)
    end
end

function RW.DrawEnemies()
    local vg = G.vg
    local gameTimeAcc = G.gameTimeAcc

    for i, e in ipairs(G.enemies) do
        local alpha = 255
        local isBoss = (e.typeKey == "boss")

        if e.hitFlashTimer > 0 then
            alpha = 255
            nvgBeginPath(vg)
            nvgCircle(vg, e.x, e.y, e.radius + 2)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 120))
            nvgFill(vg)
        end

        -- Boss专属
        if isBoss then
            local glowPulse = math.sin(gameTimeAcc * 3) * 0.3 + 0.7
            local glowR = e.radius + 6 + math.sin(gameTimeAcc * 5) * 2
            nvgBeginPath(vg)
            nvgCircle(vg, e.x, e.y, glowR)
            nvgStrokeColor(vg, nvgRGBA(255, 60, 30, math.floor(120 * glowPulse)))
            nvgStrokeWidth(vg, 3)
            nvgStroke(vg)

            if e.isCharging then
                nvgBeginPath(vg)
                nvgCircle(vg, e.x, e.y, e.radius + 4)
                nvgFillColor(vg, nvgRGBA(255, 100, 40, 80))
                nvgFill(vg)
            end

            if e.shieldActive then
                local shieldPulse = math.sin(gameTimeAcc * 6) * 0.3 + 0.7
                nvgBeginPath(vg)
                nvgCircle(vg, e.x, e.y, e.radius + 5)
                nvgStrokeColor(vg, nvgRGBA(255, 200, 60, math.floor(180 * shieldPulse)))
                nvgStrokeWidth(vg, 2.5)
                nvgStroke(vg)
                nvgBeginPath(vg)
                nvgCircle(vg, e.x, e.y, e.radius + 2)
                nvgFillColor(vg, nvgRGBA(255, 220, 80, math.floor(40 * shieldPulse)))
                nvgFill(vg)
            end

            if e.isSpinning then
                local spinVis = math.sin(gameTimeAcc * 10) * 0.3 + 0.7
                nvgBeginPath(vg)
                nvgCircle(vg, e.x, e.y, e.radius + 8)
                nvgStrokeColor(vg, nvgRGBA(180, 60, 255, math.floor(100 * spinVis)))
                nvgStrokeWidth(vg, 2)
                nvgStroke(vg)
            end
        end

        -- 小Boss专属
        if e.isMiniBoss then
            local mbPulse = math.sin(gameTimeAcc * 4) * 0.3 + 0.7
            nvgBeginPath(vg)
            nvgCircle(vg, e.x, e.y, e.radius + 4)
            nvgStrokeColor(vg, nvgRGBA(220, 140, 40, math.floor(140 * mbPulse)))
            nvgStrokeWidth(vg, 2.5)
            nvgStroke(vg)
            if e.isCharging then
                nvgBeginPath(vg)
                nvgCircle(vg, e.x, e.y, e.radius + 3)
                nvgFillColor(vg, nvgRGBA(220, 120, 30, 60))
                nvgFill(vg)
            end
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 9)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 180, 60, 220))
            nvgText(vg, e.x, e.y - e.radius - 14, "灰狼队长", nil)
            local mbBarW = 30
            local mbBarH = 3
            local mbBarX = e.x - mbBarW / 2
            local mbBarY = e.y - e.radius - 8
            nvgBeginPath(vg)
            nvgRect(vg, mbBarX, mbBarY, mbBarW, mbBarH)
            nvgFillColor(vg, nvgRGBA(40, 40, 40, 180))
            nvgFill(vg)
            local hpRatio = math.max(0, e.hp / e.maxHp)
            nvgBeginPath(vg)
            nvgRect(vg, mbBarX, mbBarY, mbBarW * hpRatio, mbBarH)
            nvgFillColor(vg, nvgRGBA(220, 140, 40, 255))
            nvgFill(vg)
        end

        -- 重装兵专属
        if e.typeKey == "heavy" then
            local armorPulse = math.sin(gameTimeAcc * 2 + i * 0.5) * 0.2 + 0.8
            nvgBeginPath(vg)
            nvgCircle(vg, e.x, e.y, e.radius + 3)
            nvgStrokeColor(vg, nvgRGBA(140, 160, 200, math.floor(100 * armorPulse)))
            nvgStrokeWidth(vg, 2.5)
            nvgStroke(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, e.x, e.y, e.radius + 1)
            nvgFillColor(vg, nvgRGBA(100, 120, 160, math.floor(30 * armorPulse)))
            nvgFill(vg)
        end

        -- 摇摆动画
        local eMoving = (e.state == "chase" or e.state == "alert" or (e.state == "idle" and e.speed > 0))
        local eWobble = 0
        if eMoving then
            local phase = i * 1.7
            eWobble = math.sin(gameTimeAcc * 7 + phase) * 0.12
        end

        -- 选择敌人图片
        local eImg = G.imgEnemies[e.typeKey] or G.imgEnemies["patrol"] or -1
        local imgSize = e.radius * 2.8
        local halfSize = imgSize / 2

        nvgSave(vg)
        nvgTranslate(vg, e.x, e.y)
        nvgRotate(vg, eWobble)
        nvgGlobalAlpha(vg, alpha / 255)

        if eImg >= 0 then
            local facingRight = (math.cos(e.angle) >= 0)
            if facingRight then
                nvgScale(vg, -1, 1)
            end
            local eRedImg = G.imgEnemiesRed[e.typeKey] or G.imgEnemiesRed["patrol"] or -1
            DrawRedOutline(eRedImg, halfSize, imgSize)
            local paint = nvgImagePattern(vg, -halfSize, -halfSize, imgSize, imgSize, 0, eImg, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, -halfSize, -halfSize, imgSize, imgSize)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        else
            nvgBeginPath(vg)
            nvgCircle(vg, 0, 0, e.radius)
            nvgFillColor(vg, nvgRGBA(e.color[1], e.color[2], e.color[3], 255))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(255, 50, 50, 220))
            nvgStrokeWidth(vg, isBoss and 2.5 or 1.5)
            nvgStroke(vg)
        end

        -- 受击闪白覆盖
        if e.hitFlashTimer > 0 and eImg >= 0 then
            nvgBeginPath(vg)
            nvgRect(vg, -halfSize, -halfSize, imgSize, imgSize)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 100))
            nvgFill(vg)
        end

        nvgRestore(vg)

        -- === 状态效果视觉（增强版） ===
        if e.burnTimer and e.burnTimer > 0 then
            local flicker = math.sin(gameTimeAcc * 12 + i * 2.3) * 0.3 + 0.7
            -- 外圈火焰环
            nvgBeginPath(vg)
            nvgCircle(vg, e.x, e.y, e.radius + 5)
            nvgStrokeColor(vg, nvgRGBA(255, 120, 30, math.floor(140 * flicker)))
            nvgStrokeWidth(vg, 2.5)
            nvgStroke(vg)
            -- 内部橙色覆盖
            nvgBeginPath(vg)
            nvgCircle(vg, e.x, e.y, e.radius)
            nvgFillColor(vg, nvgRGBA(255, 80, 20, math.floor(50 * flicker)))
            nvgFill(vg)
            -- 上升火焰小三角（3个）
            for fi = 0, 2 do
                local fPhase = gameTimeAcc * 6 + fi * 2.1 + i
                local fLife = (fPhase % 1.0)  -- 0~1循环
                local fAngle = (fi / 3) * math.pi * 2 + math.sin(fPhase) * 0.5
                local fDist = e.radius * 0.6 + e.radius * 0.5 * fLife
                local fx = e.x + math.cos(fAngle) * fDist * 0.4
                local fy = e.y - fDist
                local fAlpha = math.floor(200 * (1 - fLife))
                local fSize = 3 + 2 * (1 - fLife)
                nvgSave(vg)
                nvgTranslate(vg, fx, fy)
                nvgBeginPath(vg)
                nvgMoveTo(vg, 0, -fSize)
                nvgLineTo(vg, -fSize * 0.6, fSize * 0.5)
                nvgLineTo(vg, fSize * 0.6, fSize * 0.5)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(255, 160, 40, fAlpha))
                nvgFill(vg)
                nvgRestore(vg)
            end
        end
        if e.slowTimer and e.slowTimer > 0 then
            local frostPulse = math.sin(gameTimeAcc * 4 + i * 1.7) * 0.2 + 0.8
            -- 冰霜外环
            nvgBeginPath(vg)
            nvgCircle(vg, e.x, e.y, e.radius + 3)
            nvgStrokeColor(vg, nvgRGBA(100, 180, 255, math.floor(130 * frostPulse)))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
            -- 蓝色半透明覆盖
            nvgBeginPath(vg)
            nvgCircle(vg, e.x, e.y, e.radius)
            nvgFillColor(vg, nvgRGBA(80, 160, 255, math.floor(45 * frostPulse)))
            nvgFill(vg)
            -- 冰晶十字线
            local crossSize = e.radius + 1
            nvgSave(vg)
            nvgTranslate(vg, e.x, e.y)
            nvgRotate(vg, gameTimeAcc * 0.5 + i)
            nvgBeginPath(vg)
            nvgMoveTo(vg, 0, -crossSize)
            nvgLineTo(vg, 0, crossSize)
            nvgMoveTo(vg, -crossSize, 0)
            nvgLineTo(vg, crossSize, 0)
            -- 对角线
            local diagSize = crossSize * 0.7
            nvgMoveTo(vg, -diagSize, -diagSize)
            nvgLineTo(vg, diagSize, diagSize)
            nvgMoveTo(vg, diagSize, -diagSize)
            nvgLineTo(vg, -diagSize, diagSize)
            nvgStrokeColor(vg, nvgRGBA(180, 220, 255, math.floor(100 * frostPulse)))
            nvgStrokeWidth(vg, 1.0)
            nvgStroke(vg)
            nvgRestore(vg)
        end

        -- 血条(受伤时显示)
        if e.hp < e.maxHp then
            local barW = e.radius * 2.5
            local barH = 3
            local barX = e.x - barW / 2
            local barY = e.y - e.radius * 1.4 - 8
            local ratio = e.hp / e.maxHp

            nvgBeginPath(vg)
            nvgRect(vg, barX, barY, barW, barH)
            nvgFillColor(vg, nvgRGBA(40, 40, 40, 180))
            nvgFill(vg)

            nvgBeginPath(vg)
            nvgRect(vg, barX, barY, barW * ratio, barH)
            if ratio > 0.5 then
                nvgFillColor(vg, nvgRGBA(80, 200, 80, 220))
            elseif ratio > 0.25 then
                nvgFillColor(vg, nvgRGBA(220, 180, 40, 220))
            else
                nvgFillColor(vg, nvgRGBA(220, 60, 60, 220))
            end
            nvgFill(vg)

            if e.armor and e.armor > 0 then
                local armorY = barY + barH + 1
                nvgBeginPath(vg)
                nvgRect(vg, barX, armorY, barW, 2)
                nvgFillColor(vg, nvgRGBA(120, 140, 180, 200))
                nvgFill(vg)
            end
        end

        -- 警觉标记
        if e.state == "alert" or e.state == "chase" then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 13)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 80, 80, 220))
            nvgText(vg, e.x, e.y - e.radius * 1.4 - 16, "!", nil)
        end
    end
end

function RW.DrawBullets()
    local vg = G.vg
    local gt = GetTime():GetElapsedTime()

    for _, b in ipairs(G.bullets) do
        local fx = b.bulletFx or "normal"
        local fxc = BULLET_FX_COLORS[fx] or BULLET_FX_COLORS.normal

        -- === 拖尾轨迹 ===
        if b.trail and #b.trail > 0 then
            local cr, cg, cb
            if b.fromPlayer then
                cr, cg, cb = fxc.trail[1], fxc.trail[2], fxc.trail[3]
            else
                cr, cg, cb = 255, 100, 80
            end

            local prevX, prevY = b.x, b.y
            for ti = 1, #b.trail do
                local t = b.trail[ti]
                local frac = 1 - ti / (#b.trail + 1)
                local trailAlpha = math.floor(200 * frac)
                local width = b.radius * 2.2 * frac + 0.5

                nvgBeginPath(vg)
                nvgMoveTo(vg, prevX, prevY)
                nvgLineTo(vg, t.x, t.y)
                nvgStrokeColor(vg, nvgRGBA(cr, cg, cb, trailAlpha))
                nvgStrokeWidth(vg, width)
                nvgLineCap(vg, NVG_ROUND)
                nvgStroke(vg)

                if b.fromPlayer and (fx == "burn" or fx == "frost" or fx == "shock" or fx == "explosive") then
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, prevX, prevY)
                    nvgLineTo(vg, t.x, t.y)
                    local gc = fxc.glow
                    nvgStrokeColor(vg, nvgRGBA(gc[1], gc[2], gc[3], math.floor(trailAlpha * 0.3)))
                    nvgStrokeWidth(vg, width + 4)
                    nvgLineCap(vg, NVG_ROUND)
                    nvgStroke(vg)
                end

                prevX, prevY = t.x, t.y
            end
        end

        -- === 子弹本体 ===
        if b.fromPlayer then
            local cc = fxc.core
            local gc = fxc.glow
            local r = b.radius

            local bAngle = math.atan(b.vy, b.vx)

            if fx == "explosive" then
                -- 炸弹形: 圆头 + 短尾焰
                local pulse = 0.85 + 0.15 * math.sin(gt * 20)
                nvgSave(vg)
                nvgTranslate(vg, b.x, b.y)
                nvgRotate(vg, bAngle)
                -- 外发光
                nvgBeginPath(vg)
                nvgCircle(vg, 0, 0, (r + 5) * pulse)
                nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 45))
                nvgFill(vg)
                -- 弹体（圆头 + 尾部锥形）
                nvgBeginPath(vg)
                nvgMoveTo(vg, r + 2, 0)
                nvgArc(vg, 0, 0, r + 2, 0, math.pi, NVG_CW)
                nvgLineTo(vg, -(r + 5), 0)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(cc[1], cc[2], cc[3], 255))
                nvgFill(vg)
                -- 白色高光
                nvgBeginPath(vg)
                nvgCircle(vg, 1, 0, r * 0.35)
                nvgFillColor(vg, nvgRGBA(255, 250, 220, 200))
                nvgFill(vg)
                -- 尾焰粒子
                for fi = 1, 2 do
                    local fx2 = -(r + 4 + fi * 3)
                    local fy2 = (math.random() - 0.5) * 3
                    nvgBeginPath(vg)
                    nvgCircle(vg, fx2, fy2, 1.5 + math.random() * 1.5)
                    nvgFillColor(vg, nvgRGBA(255, 220, 80, 140))
                    nvgFill(vg)
                end
                nvgRestore(vg)

            elseif fx == "shock" then
                -- 菱形 + 电弧
                local flicker = math.random() > 0.3 and 1.0 or 0.6
                nvgSave(vg)
                nvgTranslate(vg, b.x, b.y)
                nvgRotate(vg, bAngle)
                -- 外发光
                nvgBeginPath(vg)
                nvgCircle(vg, 0, 0, r + 6)
                nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], math.floor(50 * flicker)))
                nvgFill(vg)
                -- 菱形弹体
                nvgBeginPath(vg)
                nvgMoveTo(vg, r + 4, 0)
                nvgLineTo(vg, 0, -(r * 0.6))
                nvgLineTo(vg, -(r + 2), 0)
                nvgLineTo(vg, 0, r * 0.6)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(cc[1], cc[2], cc[3], 255))
                nvgFill(vg)
                nvgRestore(vg)
                -- 随机电弧（世界坐标）
                for arc = 1, 3 do
                    local ax = b.x + (math.random() - 0.5) * 14
                    local ay = b.y + (math.random() - 0.5) * 14
                    local mx = (b.x + ax) / 2 + (math.random() - 0.5) * 6
                    local my = (b.y + ay) / 2 + (math.random() - 0.5) * 6
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, b.x, b.y)
                    nvgLineTo(vg, mx, my)
                    nvgLineTo(vg, ax, ay)
                    nvgStrokeColor(vg, nvgRGBA(200, 180, 255, math.floor(160 * flicker)))
                    nvgStrokeWidth(vg, 1.0)
                    nvgStroke(vg)
                end

            elseif fx == "burn" then
                -- 火焰形: 三角叠层向前
                nvgSave(vg)
                nvgTranslate(vg, b.x, b.y)
                nvgRotate(vg, bAngle)
                -- 外焰（大三角，半透明红）
                nvgBeginPath(vg)
                nvgMoveTo(vg, r + 5, 0)
                nvgLineTo(vg, -(r + 2), -(r + 1))
                nvgLineTo(vg, -r, 0)
                nvgLineTo(vg, -(r + 2), r + 1)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(255, 60, 0, 100))
                nvgFill(vg)
                -- 中焰（橙色）
                nvgBeginPath(vg)
                nvgMoveTo(vg, r + 3, 0)
                nvgLineTo(vg, -(r - 1), -(r * 0.6))
                nvgLineTo(vg, -(r - 2), 0)
                nvgLineTo(vg, -(r - 1), r * 0.6)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(cc[1], cc[2], cc[3], 255))
                nvgFill(vg)
                -- 内芯（亮黄）
                nvgBeginPath(vg)
                nvgMoveTo(vg, r, 0)
                nvgLineTo(vg, -(r * 0.3), -(r * 0.3))
                nvgLineTo(vg, -(r * 0.3), r * 0.3)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(255, 255, 150, 230))
                nvgFill(vg)
                nvgRestore(vg)

            elseif fx == "frost" then
                -- 六角星形（冰晶）
                nvgSave(vg)
                nvgTranslate(vg, b.x, b.y)
                local frostSpin = gt * 3
                -- 外发光
                nvgBeginPath(vg)
                nvgCircle(vg, 0, 0, r + 5)
                nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 40))
                nvgFill(vg)
                -- 六角冰晶
                nvgBeginPath(vg)
                for si = 0, 5 do
                    local a = frostSpin + si * (math.pi / 3)
                    local outerR = r + 2
                    local innerR = r * 0.5
                    local ox = math.cos(a) * outerR
                    local oy = math.sin(a) * outerR
                    local a2 = a + math.pi / 6
                    local ix = math.cos(a2) * innerR
                    local iy = math.sin(a2) * innerR
                    if si == 0 then
                        nvgMoveTo(vg, ox, oy)
                    else
                        nvgLineTo(vg, ox, oy)
                    end
                    nvgLineTo(vg, ix, iy)
                end
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(cc[1], cc[2], cc[3], 255))
                nvgFill(vg)
                -- 白色中心
                nvgBeginPath(vg)
                nvgCircle(vg, 0, 0, r * 0.3)
                nvgFillColor(vg, nvgRGBA(240, 250, 255, 230))
                nvgFill(vg)
                nvgRestore(vg)

            elseif fx == "pierce" then
                -- 细长箭头形
                nvgSave(vg)
                nvgTranslate(vg, b.x, b.y)
                nvgRotate(vg, bAngle)
                -- 外发光（拉长椭圆）
                nvgBeginPath(vg)
                nvgEllipse(vg, 0, 0, r + 8, r * 0.5)
                nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 40))
                nvgFill(vg)
                -- 箭头主体
                nvgBeginPath(vg)
                nvgMoveTo(vg, r + 6, 0)
                nvgLineTo(vg, r - 1, -(r * 0.5))
                nvgLineTo(vg, -(r + 4), -(r * 0.25))
                nvgLineTo(vg, -(r + 4), r * 0.25)
                nvgLineTo(vg, r - 1, r * 0.5)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(cc[1], cc[2], cc[3], 255))
                nvgFill(vg)
                -- 尖端高光
                nvgBeginPath(vg)
                nvgMoveTo(vg, r + 6, 0)
                nvgLineTo(vg, r, -(r * 0.3))
                nvgLineTo(vg, r, r * 0.3)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(200, 240, 255, 200))
                nvgFill(vg)
                nvgRestore(vg)

            elseif fx == "bounce" then
                -- 旋转圆 + 环绕轨道粒子
                local spin = gt * 8
                nvgBeginPath(vg)
                nvgCircle(vg, b.x, b.y, r + 4)
                nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 50))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgCircle(vg, b.x, b.y, r)
                nvgFillColor(vg, nvgRGBA(cc[1], cc[2], cc[3], 255))
                nvgFill(vg)
                -- 环绕轨道粒子
                for si = 0, 2 do
                    local sa = spin + si * (math.pi * 2 / 3)
                    local orbitR = r + 3.5
                    local sx = b.x + math.cos(sa) * orbitR
                    local sy = b.y + math.sin(sa) * orbitR
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, 1.5)
                    nvgFillColor(vg, nvgRGBA(200, 255, 200, 200))
                    nvgFill(vg)
                    -- 粒子拖尾
                    local sx2 = b.x + math.cos(sa - 0.4) * orbitR
                    local sy2 = b.y + math.sin(sa - 0.4) * orbitR
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, sx, sy)
                    nvgLineTo(vg, sx2, sy2)
                    nvgStrokeColor(vg, nvgRGBA(140, 255, 160, 80))
                    nvgStrokeWidth(vg, 1.0)
                    nvgStroke(vg)
                end
                -- 中心反弹标记（小三角）
                nvgSave(vg)
                nvgTranslate(vg, b.x, b.y)
                nvgRotate(vg, spin * 0.5)
                nvgBeginPath(vg)
                nvgMoveTo(vg, 0, -(r * 0.4))
                nvgLineTo(vg, -(r * 0.35), r * 0.25)
                nvgLineTo(vg, r * 0.35, r * 0.25)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 120))
                nvgFill(vg)
                nvgRestore(vg)

            elseif fx == "shotgun" then
                -- 小方块弹丸
                nvgSave(vg)
                nvgTranslate(vg, b.x, b.y)
                nvgRotate(vg, bAngle)
                -- 发光
                nvgBeginPath(vg)
                nvgCircle(vg, 0, 0, r + 2)
                nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 50))
                nvgFill(vg)
                -- 方形弹丸
                local halfS = r * 0.75
                nvgBeginPath(vg)
                nvgRect(vg, -halfS, -halfS, halfS * 2, halfS * 2)
                nvgFillColor(vg, nvgRGBA(cc[1], cc[2], cc[3], 255))
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(255, 240, 180, 120))
                nvgStrokeWidth(vg, 0.8)
                nvgStroke(vg)
                nvgRestore(vg)

            else
                -- normal: 水滴形（朝运动方向）
                nvgSave(vg)
                nvgTranslate(vg, b.x, b.y)
                nvgRotate(vg, bAngle)
                -- 外发光
                nvgBeginPath(vg)
                nvgEllipse(vg, 0, 0, r + 4, r + 2)
                nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 55))
                nvgFill(vg)
                -- 水滴主体
                nvgBeginPath(vg)
                nvgMoveTo(vg, r + 3, 0)
                nvgBezierTo(vg, r, -(r * 0.7), -(r * 0.5), -(r * 0.8), -(r + 1), 0)
                nvgBezierTo(vg, -(r * 0.5), r * 0.8, r, r * 0.7, r + 3, 0)
                nvgFillColor(vg, nvgRGBA(cc[1], cc[2], cc[3], 255))
                nvgFill(vg)
                -- 高光
                nvgBeginPath(vg)
                nvgCircle(vg, r * 0.3, 0, r * 0.3)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 100))
                nvgFill(vg)
                nvgRestore(vg)
            end

            -- 暴击附加
            if b.isCrit then
                nvgSave(vg)
                nvgTranslate(vg, b.x, b.y)
                nvgRotate(vg, gt * 6)
                nvgBeginPath(vg)
                nvgRect(vg, -1, -(r + 4), 2, (r + 4) * 2)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 140))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRect(vg, -(r + 4), -1, (r + 4) * 2, 2)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 140))
                nvgFill(vg)
                nvgRestore(vg)
            end
        else
            -- 敌人子弹
            nvgBeginPath(vg)
            nvgCircle(vg, b.x, b.y, b.radius + 3)
            nvgFillColor(vg, nvgRGBA(255, 120, 80, 50))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, b.x, b.y, b.radius)
            nvgFillColor(vg, nvgRGBA(255, 100, 80, 255))
            nvgFill(vg)
        end
    end
end

function RW.DrawLootItems()
    local vg = G.vg
    local player = G.player
    local t = GetTime():GetElapsedTime()

    for _, item in ipairs(G.lootItems) do
        local bounce = math.sin(t * 4 + item.x) * 2

        if item.type == "artifact" then
            local rarity = item.itemData.rarity or 1
            local col = InvData.RARITY_COLORS[rarity] or {200, 200, 200}
            local pulse = 0.7 + 0.3 * math.sin(t * 5 + item.y)

            nvgBeginPath(vg)
            nvgCircle(vg, item.x, item.y + bounce, 14)
            nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], math.floor(35 * pulse)))
            nvgFill(vg)

            nvgBeginPath(vg)
            nvgCircle(vg, item.x, item.y + bounce, 9)
            nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], math.floor(70 * pulse)))
            nvgFill(vg)

            nvgBeginPath(vg)
            nvgCircle(vg, item.x, item.y + bounce, 5)
            nvgFillColor(vg, nvgRGBA(
                math.min(255, col[1] + 60),
                math.min(255, col[2] + 60),
                math.min(255, col[3] + 60), 230))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, math.floor(140 * pulse)))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)

            -- 物品名称
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 9)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], 200))
            nvgText(vg, item.x, item.y + bounce - 12, item.itemData.name, nil)

            -- 靠近弹窗
            local dx = player.x - item.x
            local dy = player.y - item.y
            local distSq = dx * dx + dy * dy
            if distSq <= 60 * 60 and player.alive and not InvUI.isOpen then
                local tmpl = item.itemData.template
                local popX = item.x
                local popY = item.y + bounce - 22
                local rarityName = InvData.RARITY_NAMES[rarity] or "普通"
                local desc = tmpl and tmpl.desc or ""
                local itemType = "圣物"

                local popW = 120
                local popH = 52
                local tagLine = ""
                if tmpl and tmpl.tags and #tmpl.tags > 0 then
                    local tagNames = {}
                    for _, tag in ipairs(tmpl.tags) do
                        table.insert(tagNames, InvData.TAGS[tag] or tag)
                    end
                    tagLine = table.concat(tagNames, " ")
                    popH = popH + 11
                end

                local bgAlpha = math.floor(200 + 30 * math.sin(t * 3))
                nvgBeginPath(vg)
                nvgRoundedRect(vg, popX - popW / 2, popY - popH, popW, popH, 4)
                nvgFillColor(vg, nvgRGBA(20, 20, 30, bgAlpha))
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(col[1], col[2], col[3], 150))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)

                local titleY = popY - popH + 12
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 10)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], 255))
                nvgText(vg, popX, titleY, "[" .. rarityName .. "] " .. item.itemData.name, nil)

                local lineY = titleY + 12
                if tagLine ~= "" then
                    nvgFontSize(vg, 8)
                    nvgFillColor(vg, nvgRGBA(180, 180, 200, 200))
                    nvgText(vg, popX, lineY, itemType .. " | " .. tagLine, nil)
                    lineY = lineY + 11
                else
                    nvgFontSize(vg, 8)
                    nvgFillColor(vg, nvgRGBA(180, 180, 200, 200))
                    nvgText(vg, popX, lineY, itemType, nil)
                    lineY = lineY + 11
                end

                nvgFontSize(vg, 9)
                nvgFillColor(vg, nvgRGBA(220, 220, 240, 240))
                nvgText(vg, popX, lineY, desc, nil)

                local hintY = popY - 3
                local hintPulse = 0.6 + 0.4 * math.sin(t * 4)
                nvgFontSize(vg, 8)
                nvgFillColor(vg, nvgRGBA(255, 230, 100, math.floor(255 * hintPulse)))
                nvgText(vg, popX, hintY, "按 F 拾取", nil)
            end
        else
            nvgBeginPath(vg)
            nvgCircle(vg, item.x, item.y + bounce, 6)
            if item.type == "ammo" then
                nvgFillColor(vg, nvgRGBA(255, 200, 60, 220))
            else
                nvgFillColor(vg, nvgRGBA(100, 255, 100, 220))
            end
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 120))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end
    end
end

function RW.DrawParticles()
    local vg = G.vg
    for _, p in ipairs(G.particles) do
        local t = p.life / p.maxLife
        local alpha = math.floor(t * 255)
        local sz = p.size * t

        if p.isShell then
            nvgSave(vg)
            nvgTranslate(vg, p.x, p.y)
            nvgRotate(vg, p.rot or 0)
            nvgBeginPath(vg)
            nvgRect(vg, -sz, -sz * 0.5, sz * 2, sz)
            nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, alpha))
            nvgFill(vg)
            nvgRestore(vg)
        elseif p.glow then
            nvgBeginPath(vg)
            nvgCircle(vg, p.x, p.y, sz * 2.5)
            nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, math.floor(alpha * 0.25)))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, p.x, p.y, sz)
            nvgFillColor(vg, nvgRGBA(
                math.min(255, p.r + 40),
                math.min(255, p.g + 40),
                math.min(255, p.b + 40), alpha))
            nvgFill(vg)
        else
            nvgBeginPath(vg)
            nvgCircle(vg, p.x, p.y, sz)
            nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, alpha))
            nvgFill(vg)
        end
    end
end

function RW.DrawDamageNumbers()
    local vg = G.vg
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    for _, d in ipairs(G.damageNumbers) do
        local alpha = math.floor((d.life / d.maxLife) * 255)
        if d.isCrit then
            nvgFontSize(vg, 18)
            nvgFillColor(vg, nvgRGBA(255, 40, 40, alpha))
        elseif d.isBurn then
            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBA(255, 150, 40, alpha))
        elseif d.isShock then
            nvgFontSize(vg, 13)
            nvgFillColor(vg, nvgRGBA(100, 180, 255, alpha))
        elseif d.isShield then
            nvgFontSize(vg, 12)
            nvgFillColor(vg, nvgRGBA(80, 180, 255, alpha))
        elseif d.isAoe then
            nvgFontSize(vg, 12)
            nvgFillColor(vg, nvgRGBA(255, 180, 60, alpha))
        elseif d.isPlayer then
            nvgFontSize(vg, 13)
            nvgFillColor(vg, nvgRGBA(255, 80, 80, alpha))
        elseif d.r and d.g and d.b then
            nvgFontSize(vg, 12)
            nvgFillColor(vg, nvgRGBA(d.r, d.g, d.b, alpha))
        else
            nvgFontSize(vg, 13)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
        end
        nvgText(vg, d.x, d.y, d.text, nil)
    end
end

function RW.DrawFogOfWar(viewW, viewH)
    local vg = G.vg
    local player = G.player
    local camX, camY, camZoom = G.camX, G.camY, G.camZoom

    local fogAlpha = 178
    local innerR = 100 / camZoom
    local outerR = 260 / camZoom

    local t = GetTime():GetElapsedTime()
    local breathe = math.sin(t * 1.5) * 6

    local px = player.x
    local py = player.y
    local iR = innerR + breathe
    local oR = outerR + breathe

    nvgSave(vg)

    local zoomViewW = viewW / camZoom
    local zoomViewH = viewH / camZoom
    local fogExtraW = (G.renderOffsetX or 0) / ((G.renderScale or 1) * camZoom)
    local fogExtraH = (G.renderOffsetY or 0) / ((G.renderScale or 1) * camZoom)
    nvgBeginPath(vg)
    nvgRect(vg, camX - fogExtraW - 20, camY - fogExtraH - 20, zoomViewW + fogExtraW * 2 + 40, zoomViewH + fogExtraH * 2 + 40)
    nvgPathWinding(vg, NVG_HOLE)
    nvgCircle(vg, px, py, oR)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, fogAlpha))
    nvgFill(vg)

    local grad = nvgRadialGradient(vg, px, py, iR, oR,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, fogAlpha))
    nvgBeginPath(vg)
    nvgCircle(vg, px, py, oR)
    nvgFillPaint(vg, grad)
    nvgFill(vg)

    local glowGrad = nvgRadialGradient(vg, px, py,
        0, iR * 0.8,
        nvgRGBA(255, 220, 160, 14),
        nvgRGBA(255, 200, 120, 0))
    nvgBeginPath(vg)
    nvgCircle(vg, px, py, iR * 0.8)
    nvgFillPaint(vg, glowGrad)
    nvgFill(vg)

    nvgRestore(vg)
end

function RW.DrawSearchProgress()
    local vg = G.vg
    local searchingCrate = G.searchingCrate
    if not searchingCrate then return end

    local cx = (searchingCrate.col - 0.5) * TILE_SIZE
    local cy = (searchingCrate.row - 0.5) * TILE_SIZE
    local sTime = searchingCrate.searchTime or 1.0
    local progress = 1.0 - (searchingCrate.timer / sTime)

    local barR, barG, barB = 255, 200, 60
    if searchingCrate.crateType == TILE_CRATE_IRON then
        barR, barG, barB = 160, 200, 240
    elseif searchingCrate.crateType == TILE_CRATE_GOLD then
        barR, barG, barB = 255, 180, 40
    end

    local barW = 40
    local barH = 5
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - barW/2, cy - 20, barW, barH, 2)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - barW/2, cy - 20, barW * progress, barH, 2)
    nvgFillColor(vg, nvgRGBA(barR, barG, barB, 255))
    nvgFill(vg)

    local radius = TILE_SIZE * 0.35
    nvgBeginPath(vg)
    nvgArc(vg, cx, cy, radius, -math.pi * 0.5, -math.pi * 0.5 + math.pi * 2 * progress, NVG_CW)
    nvgStrokeColor(vg, nvgRGBA(barR, barG, barB, 200))
    nvgStrokeWidth(vg, 2.5)
    nvgStroke(vg)
end

-- ============================================================================
-- 闪电连线特效渲染（世界空间坐标，不需要手动相机变换）
-- ============================================================================
function RW.DrawLightningEffects()
    local vg = G.vg
    for _, le in ipairs(G.lightningEffects) do
        local alpha = math.floor(255 * (le.life / le.maxLife))
        local x1, y1 = le.x1, le.y1
        local x2, y2 = le.x2, le.y2
        local segments = 6

        -- 主电弧线（亮色锯齿）
        nvgBeginPath(vg)
        nvgMoveTo(vg, x1, y1)
        for seg = 1, segments - 1 do
            local t = seg / segments
            local mx = x1 + (x2 - x1) * t + (math.random() - 0.5) * 12
            local my = y1 + (y2 - y1) * t + (math.random() - 0.5) * 12
            nvgLineTo(vg, mx, my)
        end
        nvgLineTo(vg, x2, y2)
        nvgStrokeColor(vg, nvgRGBA(160, 200, 255, alpha))
        nvgStrokeWidth(vg, 2.5)
        nvgStroke(vg)

        -- 外发光层（宽模糊线）
        nvgBeginPath(vg)
        nvgMoveTo(vg, x1, y1)
        for seg = 1, segments - 1 do
            local t = seg / segments
            local mx = x1 + (x2 - x1) * t + (math.random() - 0.5) * 18
            local my = y1 + (y2 - y1) * t + (math.random() - 0.5) * 18
            nvgLineTo(vg, mx, my)
        end
        nvgLineTo(vg, x2, y2)
        nvgStrokeColor(vg, nvgRGBA(80, 140, 255, math.floor(alpha * 0.25)))
        nvgStrokeWidth(vg, 7)
        nvgStroke(vg)

        -- 内芯高光（细亮白线）
        nvgBeginPath(vg)
        nvgMoveTo(vg, x1, y1)
        for seg = 1, segments - 1 do
            local t = seg / segments
            local mx = x1 + (x2 - x1) * t + (math.random() - 0.5) * 6
            local my = y1 + (y2 - y1) * t + (math.random() - 0.5) * 6
            nvgLineTo(vg, mx, my)
        end
        nvgLineTo(vg, x2, y2)
        nvgStrokeColor(vg, nvgRGBA(220, 240, 255, math.floor(alpha * 0.8)))
        nvgStrokeWidth(vg, 1.0)
        nvgStroke(vg)

        -- 端点亮光
        nvgBeginPath(vg)
        nvgCircle(vg, x2, y2, 4)
        nvgFillColor(vg, nvgRGBA(160, 200, 255, math.floor(alpha * 0.6)))
        nvgFill(vg)
    end
end

-- ============================================================================
-- 玩家护盾光环渲染（世界空间坐标）
-- ============================================================================
function RW.DrawShield()
    local vg = G.vg
    local player = G.player
    if player.shield > 0 and player.shieldMax > 0 then
        local px, py = player.x, player.y
        local shieldRatio = player.shield / player.shieldMax
        local shieldAlpha = math.floor(60 + 120 * shieldRatio)
        local shieldRadius = player.radius + 6

        nvgBeginPath(vg)
        nvgCircle(vg, px, py, shieldRadius)
        nvgStrokeColor(vg, nvgRGBA(80, 160, 255, shieldAlpha))
        nvgStrokeWidth(vg, 2.0)
        nvgStroke(vg)

        local startAngle = -math.pi / 2
        local endAngle = startAngle + math.pi * 2 * shieldRatio
        nvgBeginPath(vg)
        nvgArc(vg, px, py, shieldRadius + 2, startAngle, endAngle, NVG_CW)
        nvgStrokeColor(vg, nvgRGBA(100, 200, 255, math.floor(shieldAlpha * 1.2)))
        nvgStrokeWidth(vg, 3.0)
        nvgStroke(vg)

        nvgBeginPath(vg)
        nvgCircle(vg, px, py, shieldRadius + 4)
        nvgStrokeColor(vg, nvgRGBA(60, 140, 255, math.floor(shieldAlpha * 0.3)))
        nvgStrokeWidth(vg, 5)
        nvgStroke(vg)
    end
end

return RW
