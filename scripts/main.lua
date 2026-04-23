-- ============================================================================
-- 《小狼救红帽》 Little Wolf's Rescue
-- 2D俯视角PVE射击游戏 - 主循环调度器
-- ============================================================================

require "LuaScripts/Utilities/Sample"

-- 共享状态
local G       = require("game_context")

-- 背包系统模块
local InvData = require("inventory_data")
local Inv     = require("inventory")
local InvUI   = require("inventory_ui")

-- 波次管理器
local WM = require("wave_manager")

-- 拆分模块
local Map    = require("map")
local Fx     = require("fx")
local Enemy  = require("enemy")
local Bullet = require("bullet")
local Combat = require("combat")
local RW     = require("render_world")
local RH     = require("render_hud")
local MI     = require("mobile_input")
local Comic    = require("comic_intro")
local Title    = require("title_screen")
local Tutorial = require("tutorial")
local BGM      = require("bgm")

-- 常量别名(不可变, 仅本文件使用)
local TILE_SIZE   = G.TILE_SIZE
local DESIGN_W    = G.DESIGN_W
local DESIGN_H    = G.DESIGN_H
local WEAPON      = G.WEAPON

-- 冲刺参数
local DASH_DURATION = 0.18   -- 冲刺时长(秒)
local DASH_SPEED    = 680    -- 冲刺速度(像素/秒)
local DASH_COOLDOWN = 2.0    -- 冷却时间(秒)

-- ============================================================================
-- 入口
-- ============================================================================
function Start()
    SampleStart()

    local g = GetGraphics()
    G.screenW = g:GetWidth()
    G.screenH = g:GetHeight()
    G.dpr = g:GetDPR()

    G.vg = nvgCreate(1)
    if G.vg == nil then
        print("ERROR: Failed to create NanoVG context")
        return
    end
    local vg = G.vg

    G.fontNormal = nvgCreateFont(vg, "sans", "fonts/KNMaiyuan/KNMaiyuan-Regular.ttf")
    if G.fontNormal == -1 then
        print("ERROR: Failed to load font")
    end

    -- 加载角色图片
    G.imgPlayer = nvgCreateImage(vg, "image/wolf_player.png", 0)
    G.imgPlayerWhite = nvgCreateImage(vg, "image/wolf_player_white.png", 0)
    for i = 1, G.SLASH_FRAME_COUNT do
        G.imgSlashFrames[i] = nvgCreateImage(vg, string.format("image/slash_vfx/slash_%02d.png", i), 0)
    end
    G.imgEnemies = {
        patrol = nvgCreateImage(vg, "image/wolf_patrol.png", 0),
        sentry = nvgCreateImage(vg, "image/wolf_sentry.png", 0),
        rusher = nvgCreateImage(vg, "image/wolf_rusher.png", 0),
        heavy  = nvgCreateImage(vg, "image/wolf_heavy.png", 0),
        alpha  = nvgCreateImage(vg, "image/wolf_elite.png", 0),
        elite  = nvgCreateImage(vg, "image/wolf_elite.png", 0),
        boss   = nvgCreateImage(vg, "image/wolf_boss.png", 0),
    }
    G.imgEnemiesWhite = {
        patrol = nvgCreateImage(vg, "image/wolf_patrol_white.png", 0),
        sentry = nvgCreateImage(vg, "image/wolf_sentry_white.png", 0),
        rusher = nvgCreateImage(vg, "image/wolf_rusher_white.png", 0),
        heavy  = nvgCreateImage(vg, "image/wolf_heavy_white.png", 0),
        alpha  = nvgCreateImage(vg, "image/wolf_elite_white.png", 0),
        elite  = nvgCreateImage(vg, "image/wolf_elite_white.png", 0),
        boss   = nvgCreateImage(vg, "image/wolf_boss_white.png", 0),
    }
    G.imgEnemiesRed = {
        patrol = nvgCreateImage(vg, "image/wolf_patrol_red.png", 0),
        sentry = nvgCreateImage(vg, "image/wolf_sentry_red.png", 0),
        rusher = nvgCreateImage(vg, "image/wolf_rusher_red.png", 0),
        heavy  = nvgCreateImage(vg, "image/wolf_heavy_red.png", 0),
        alpha  = nvgCreateImage(vg, "image/wolf_elite_red.png", 0),
        elite  = nvgCreateImage(vg, "image/wolf_elite_red.png", 0),
        boss   = nvgCreateImage(vg, "image/wolf_boss_red.png", 0),
    }
    -- 加载地形瓦片图片
    G.imgFloorTiles = {
        nvgCreateImage(vg, "image/tiles32/floor_0.png", 0),
        nvgCreateImage(vg, "image/tiles32/floor_1.png", 0),
        nvgCreateImage(vg, "image/tiles32/floor_2.png", 0),
        nvgCreateImage(vg, "image/tiles32/floor_3.png", 0),
    }
    G.imgForestTiles = {
        nvgCreateImage(vg, "image/tiles32/forest_0.png", 0),
        nvgCreateImage(vg, "image/tiles32/forest_1.png", 0),
        nvgCreateImage(vg, "image/tiles32/forest_2.png", 0),
        nvgCreateImage(vg, "image/tiles32/forest_3.png", 0),
    }
    G.imgDarkTiles = {
        nvgCreateImage(vg, "image/tiles32/dark_0.png", 0),
        nvgCreateImage(vg, "image/tiles32/dark_1.png", 0),
        nvgCreateImage(vg, "image/tiles32/dark_2.png", 0),
        nvgCreateImage(vg, "image/tiles32/dark_3.png", 0),
    }
    G.imgEdgeTiles = {
        nvgCreateImage(vg, "image/tiles32/edge_0.png", 0),
        nvgCreateImage(vg, "image/tiles32/edge_1.png", 0),
        nvgCreateImage(vg, "image/tiles32/edge_2.png", 0),
        nvgCreateImage(vg, "image/tiles32/edge_3.png", 0),
        nvgCreateImage(vg, "image/tiles32/edge_4.png", 0),
        nvgCreateImage(vg, "image/tiles32/edge_5.png", 0),
        nvgCreateImage(vg, "image/tiles32/edge_6.png", 0),
        nvgCreateImage(vg, "image/tiles32/edge_7.png", 0),
    }
    G.imgCrateTiles = {
        nvgCreateImage(vg, "image/tiles32/crate_0.png", 0),
        nvgCreateImage(vg, "image/tiles32/crate_1.png", 0),
    }
    G.imgCrateByType = {
        [G.TILE_CRATE_WOOD] = nvgCreateImage(vg, "image/crate_wood.png", 0),
        [G.TILE_CRATE_IRON] = nvgCreateImage(vg, "image/crate_iron.png", 0),
        [G.TILE_CRATE_GOLD] = nvgCreateImage(vg, "image/crate_gold.png", 0),
    }

    print("Player image: " .. tostring(G.imgPlayer))
    for k, v in pairs(G.imgEnemies) do
        print("Enemy image [" .. k .. "]: " .. tostring(v))
    end
    print("Tile images loaded: floor=" .. #G.imgFloorTiles .. " forest=" .. #G.imgForestTiles .. " dark=" .. #G.imgDarkTiles .. " edge=" .. #G.imgEdgeTiles)

    SampleInitMouseMode(MM_FREE)

    -- 加载音效
    G.audioScene = Scene()
    G.audioScene:CreateComponent("Octree")

    G.sndShoot      = cache:GetResource("Sound", "audio/sfx/sfx_shoot.ogg")
    G.sndReload     = cache:GetResource("Sound", "audio/sfx/sfx_reload.ogg")
    G.sndHit        = cache:GetResource("Sound", "audio/sfx/sfx_hit.ogg")
    G.sndKill       = cache:GetResource("Sound", "audio/sfx/sfx_kill.ogg")
    G.sndSplat      = cache:GetResource("Sound", "audio/sfx/sfx_splat.ogg")
    G.sndReloadDone = cache:GetResource("Sound", "audio/sfx/sfx_reload_done.ogg")
    G.sndFootstep   = cache:GetResource("Sound", "audio/sfx/sfx_footstep.ogg")
    G.sndLevelClear = cache:GetResource("Sound", "audio/sfx/sfx_level_clear.ogg")

    -- 战斗音效
    G.sndMeleeSwing    = cache:GetResource("Sound", "audio/sfx/sfx_melee_swing.ogg")
    G.sndMeleeHit      = cache:GetResource("Sound", "audio/sfx/sfx_melee_hit.ogg")
    G.sndExplosion     = cache:GetResource("Sound", "audio/sfx/sfx_explosion.ogg")
    G.sndBulletBounce  = cache:GetResource("Sound", "audio/sfx/sfx_bullet_bounce.ogg")
    G.sndEnemyShoot    = cache:GetResource("Sound", "audio/sfx/sfx_enemy_shoot.ogg")
    G.sndEnemyBurst    = cache:GetResource("Sound", "audio/sfx/sfx_enemy_burst.ogg")
    G.sndEnemyShotgun  = cache:GetResource("Sound", "audio/sfx/sfx_enemy_shotgun.ogg")
    G.sndEnemyDeath    = cache:GetResource("Sound", "audio/sfx/sfx_enemy_death.ogg")
    G.sndDroneShoot    = cache:GetResource("Sound", "audio/sfx/sfx_drone_shoot.ogg")
    G.sndChainLightning = cache:GetResource("Sound", "audio/sfx/sfx_chain_lightning.ogg")

    -- 状态效果音效
    G.sndFrostHit      = cache:GetResource("Sound", "audio/sfx/sfx_frost_hit.ogg")
    G.sndBurnHit       = cache:GetResource("Sound", "audio/sfx/sfx_burn_hit.ogg")
    G.sndShockHit      = cache:GetResource("Sound", "audio/sfx/sfx_shock_hit.ogg")

    -- Boss/波次音效
    G.sndBossAppear    = cache:GetResource("Sound", "audio/sfx/sfx_boss_appear.ogg")
    G.sndBossPhase     = cache:GetResource("Sound", "audio/sfx/sfx_boss_phase.ogg")
    G.sndBossDeath     = cache:GetResource("Sound", "audio/sfx/sfx_boss_death.ogg")
    G.sndBossSummon    = cache:GetResource("Sound", "audio/sfx/sfx_boss_summon.ogg")
    G.sndBossCharge    = cache:GetResource("Sound", "audio/sfx/sfx_boss_charge.ogg")
    G.sndWaveStart     = cache:GetResource("Sound", "audio/sfx/sfx_wave_start.ogg")

    -- 玩家事件音效
    G.sndPlayerHurt    = cache:GetResource("Sound", "audio/sfx/sfx_player_hurt.ogg")
    G.sndPlayerDeath   = cache:GetResource("Sound", "audio/sfx/sfx_player_death.ogg")
    G.sndShieldAbsorb  = cache:GetResource("Sound", "audio/sfx/sfx_shield_absorb.ogg")
    G.sndShieldBreak   = cache:GetResource("Sound", "audio/sfx/sfx_shield_break.ogg")

    -- 背包/物品音效
    G.sndInventoryOpen  = cache:GetResource("Sound", "audio/sfx/sfx_inventory_open.ogg")
    G.sndInventoryClose = cache:GetResource("Sound", "audio/sfx/sfx_inventory_close.ogg")
    G.sndItemPickup     = cache:GetResource("Sound", "audio/sfx/sfx_item_pickup.ogg")
    G.sndItemPlace      = cache:GetResource("Sound", "audio/sfx/sfx_item_place.ogg")
    G.sndItemRotate     = cache:GetResource("Sound", "audio/sfx/sfx_item_rotate.ogg")
    G.sndLineClear      = cache:GetResource("Sound", "audio/sfx/sfx_line_clear.ogg")
    G.sndItemDiscard    = cache:GetResource("Sound", "audio/sfx/sfx_item_discard.ogg")

    -- 世界事件音效
    G.sndCrateSearch    = cache:GetResource("Sound", "audio/sfx/sfx_crate_search.ogg")
    G.sndCrateOpen      = cache:GetResource("Sound", "audio/sfx/sfx_crate_open.ogg")
    G.sndPortalAppear   = cache:GetResource("Sound", "audio/sfx/sfx_portal_appear.ogg")
    G.sndPortalEnter    = cache:GetResource("Sound", "audio/sfx/sfx_portal_enter.ogg")
    G.sndRewardSelect   = cache:GetResource("Sound", "audio/sfx/sfx_reward_select.ogg")

    -- 初始化背包系统
    Inv.Init()
    local starterArtifact = Inv.CreateArtifact("a_bullet_core")
    if starterArtifact then
        table.insert(G.lootItems, {
            x = G.player.x + math.random(-12, 12),
            y = G.player.y + math.random(-12, 12),
            type = "artifact",
            itemData = starterArtifact,
        })
    end

    -- 设置背包丢弃回调
    InvUI.onDiscardItem = function(item)
        table.insert(G.lootItems, {
            x = G.player.x + math.random(-16, 16),
            y = G.player.y + math.random(-16, 16),
            type = "artifact",
            itemData = item,
        })
    end

    -- 设置拾取放入背包回调
    InvUI.onPickupPlaced = function(lootRef)
        for i = #G.lootItems, 1, -1 do
            if G.lootItems[i] == lootRef then
                table.remove(G.lootItems, i)
                break
            end
        end
    end

    -- 初始化波次管理器
    WM.Init()
    Map.GenerateMap()
    Enemy.SpawnEnemies()
    local w1 = WM.GetCurrentWave()
    G.waveAnnounceTimer = 3.0
    G.waveAnnounceText = "Wave " .. WM.currentWave .. " - " .. (w1 and w1.name or "")

    print("=== 小狼救红帽 - 森林冒险模式 ===")

    -- 输入初始化（始终初始化，自动检测设备类型）
    -- 默认PC模式(G.isMobile=false)；手机浏览器第一次触摸时自动切换为移动端模式
    MI.Init()
    MI.onReload = function()
        local p = G.player
        local effectiveMag = WEAPON.magSize + WM.weaponMods.bonusMagSize + math.floor(Inv.GetStat("magSize", 0))
        if G.gameState == G.STATE_PLAYING and p.alive and not p.reloading
           and p.ammo < effectiveMag and p.totalAmmo > 0 then
            p.reloading = true
            p.reloadTimer = WEAPON.reloadTime
            G.PlaySfx(G.sndReload, 0.5)
        end
    end
    MI.onBag = function()
        if G.gameState == G.STATE_PLAYING and G.player.alive then
            InvUI.Toggle()
            if InvUI.isOpen then
                G.gameTimeScale = 0.15
                UI_CollectNearbyPickups()
                G.PlaySfx(G.sndInventoryOpen, 0.5)
            else
                G.gameTimeScale = 1.0
                G.PlaySfx(G.sndInventoryClose, 0.4)
            end
        end
    end
    MI.onPickup = function()
        if G.gameState == G.STATE_PLAYING and G.player.alive and not InvUI.isOpen then
            local nearby = GetNearbyArtifactLoot(60)
            if #nearby > 0 then
                InvUI.Open()
                G.gameTimeScale = 0.15
                UI_CollectNearbyPickups()
            end
        end
    end
    MI.onDash = function()
        TryDash()
    end
    print("输入模式: 自动检测 (PC=WASD+鼠标 / 手机=触控摇杆)")
    print("消灭所有敌人进入下一波!")

    -- 初始化开场漫画并设置初始游戏状态
    Comic.Init(G.vg)
    G.gameState = G.STATE_COMIC

    SubscribeToEvent(G.vg, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    -- 始终订阅触控事件（PC浏览器不会触发，手机自动激活）
    SubscribeToEvent("TouchBegin", "HandleTouchBeginUI")

    -- 初始化背景音乐（开场漫画/标题界面均播放标题曲）
    BGM.Init()
    BGM.PlayTitle()
end

-- 移动端触控 UI 层（奖励点击、结束重启）
function HandleTouchBeginUI(eventType, eventData)
    local px = eventData["X"]:GetInt()
    local py = eventData["Y"]:GetInt()
    local mx, my = G.ScreenToDesign(px, py)

    -- 漫画阶段: 触摸翻页
    if G.gameState == G.STATE_COMIC and Comic.active then
        Comic.NextPage()
        if Comic.finished then
            G.gameState = G.STATE_TITLE
            Title.Init(G.vg)
        end
        return
    end

    -- 标题页面: 触摸交互
    if G.gameState == G.STATE_TITLE and Title.active then
        Title.HandleTouch(mx, my)
        if Title.finished then
            G.gameState = G.STATE_PLAYING
            Tutorial.Init()
            BGM.PlayForWave(WM.currentWave, WM.GetWaveCount())
        end
        return
    end

    -- 游戏结束/胜利: 点击任意处重启
    if G.gameState == G.STATE_GAMEOVER or G.gameState == G.STATE_EXTRACTED or G.gameState == G.STATE_VICTORY then
        RestartGame()
        return
    end

    if G.gameState ~= G.STATE_PLAYING then return end

    -- 教程提示: 必须点击 banner 才能继续；点击别处也消费输入（不触发游戏动作）
    if Tutorial.currentTip then
        if Tutorial.IsPointOnBanner(mx, my) then
            Tutorial.Dismiss()
        end
        return
    end

    -- 奖励选择阶段
    if WM.phase == WM.PHASE_REWARD then
        local wave = WM.GetCurrentWave()
        local isSupply = (wave and wave.rewardType == "supply")
        if isSupply then
            HandleRewardClick()
        else
            local choices = WM.rewardChoices
            local cardCount = #choices
            if cardCount > 0 then
                local cardW = 140
                local cardH = 170
                local gap = 20
                local totalW = cardCount * cardW + (cardCount - 1) * gap
                local startX = (DESIGN_W - totalW) / 2
                local cardY = (DESIGN_H - cardH) / 2 + 10
                for i = 1, cardCount do
                    local cx = startX + (i - 1) * (cardW + gap)
                    if mx >= cx and mx <= cx + cardW and my >= cardY and my <= cardY + cardH then
                        WM.selectedReward = i
                        HandleRewardClick()
                        return
                    end
                end
            end
        end
    end
end

function Stop()
    if G.vg then
        nvgDelete(G.vg)
        G.vg = nil
    end
end

-- ============================================================================
-- 冲刺位置更新（每帧调用，无论 phase 如何，都要把进行中的冲刺推进完毕）
-- ============================================================================
function UpdateDash(dt)
    local player = G.player
    if player.dashTimer <= 0 then return end

    player.dashTimer = player.dashTimer - dt
    local startX, startY = player.x, player.y

    -- 分轴推进：避免对角冲刺撞到墙角时被同时锁死两个轴
    local stepX = player.dashDirX * DASH_SPEED * dt
    if math.abs(stepX) > 0.001 then
        local resX, _ = Map.ResolveWallCollision(player.x + stepX, player.y, player.radius)
        resX = math.max(player.radius, math.min(G.MAP_W - player.radius, resX))
        if math.abs(resX - (player.x + stepX)) > 0.5 then
            player.dashDirX = 0
        end
        player.x = resX
    end
    local stepY = player.dashDirY * DASH_SPEED * dt
    if math.abs(stepY) > 0.001 then
        local _, resY = Map.ResolveWallCollision(player.x, player.y + stepY, player.radius)
        resY = math.max(player.radius, math.min(G.MAP_H - player.radius, resY))
        if math.abs(resY - (player.y + stepY)) > 0.5 then
            player.dashDirY = 0
        end
        player.y = resY
    end

    -- 任何一帧"几乎没移动"就立即终止冲刺，避免卡墙
    local moved = math.abs(player.x - startX) + math.abs(player.y - startY)
    if moved < 0.5 then
        player.dashTimer = 0
        player.dashDirX, player.dashDirY = 0, 0
        player.dashCooldown = DASH_COOLDOWN
    end

    -- 冲刺拖影粒子
    if player.dashTimer > 0 and math.random() < 0.85 then
        table.insert(G.particles, {
            x = player.x + (math.random() - 0.5) * 8,
            y = player.y + (math.random() - 0.5) * 8,
            vx = -player.dashDirX * 40 + (math.random() - 0.5) * 20,
            vy = -player.dashDirY * 40 + (math.random() - 0.5) * 20,
            life = 0.18, maxLife = 0.18,
            r = 200, g = 220, b = 255,
            size = 4 + math.random() * 3,
        })
    end

    if player.dashTimer <= 0 then
        player.dashTimer   = 0
        player.dashCooldown = DASH_COOLDOWN
    end
end

-- ============================================================================
-- 冲刺
-- ============================================================================
function TryDash()
    local player = G.player
    if not player.alive then return end
    if player.dashTimer > 0 then return end      -- 冲刺进行中
    if player.dashCooldown > 0 then return end   -- 冷却中
    if G.gameState ~= G.STATE_PLAYING then return end
    if WM.phase == WM.PHASE_REWARD then return end
    if InvUI.isOpen then return end

    -- 计算冲刺方向
    local ddx, ddy
    if G.isMobile then
        if math.abs(MI.moveDX) > 0.1 or math.abs(MI.moveDY) > 0.1 then
            ddx, ddy = MI.moveDX, MI.moveDY
        else
            ddx = math.cos(player.angle)
            ddy = math.sin(player.angle)
        end
    else
        ddx = math.cos(player.angle)
        ddy = math.sin(player.angle)
    end

    local len = math.sqrt(ddx * ddx + ddy * ddy)
    if len < 0.001 then return end
    ddx = ddx / len
    ddy = ddy / len

    player.dashTimer    = DASH_DURATION
    player.dashDirX     = ddx
    player.dashDirY     = ddy
    -- 冲刺期间无敌（多留0.05s buffer）
    player.invincibleTimer = math.max(player.invincibleTimer, DASH_DURATION + 0.05)

    G.PlaySfx(G.sndMeleeSwing, 0.5)
end

-- ============================================================================
-- 输入处理
-- ============================================================================
function HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    local player = G.player

    -- 漫画阶段: 点击翻页
    if G.gameState == G.STATE_COMIC and Comic.active then
        if button == MOUSEB_LEFT then
            Comic.NextPage()
            if Comic.finished then
                G.gameState = G.STATE_TITLE
                Title.Init(G.vg)
            end
        end
        return
    end

    -- 标题页面: 鼠标点击
    if G.gameState == G.STATE_TITLE and Title.active then
        local mx, my = G.ScreenToDesign(input:GetMousePosition().x, input:GetMousePosition().y)
        Title.HandleMouseDown(mx, my, button)
        if Title.finished then
            G.gameState = G.STATE_PLAYING
            Tutorial.Init()
            BGM.PlayForWave(WM.currentWave, WM.GetWaveCount())
        end
        return
    end

    if G.gameState == G.STATE_GAMEOVER or G.gameState == G.STATE_EXTRACTED or G.gameState == G.STATE_VICTORY then
        RestartGame()
        return
    end

    if G.gameState ~= G.STATE_PLAYING then return end

    -- 教程提示: 必须点击 banner 才能继续；点击别处也消费输入（不触发游戏动作）
    if Tutorial.currentTip then
        local mx, my = G.ScreenToDesign(input:GetMousePosition().x, input:GetMousePosition().y)
        if button == MOUSEB_LEFT and Tutorial.IsPointOnBanner(mx, my) then
            Tutorial.Dismiss()
        end
        return
    end

    -- 奖励选择阶段
    if WM.phase == WM.PHASE_REWARD and button == MOUSEB_LEFT then
        local mx, my = G.ScreenToDesign(input:GetMousePosition().x, input:GetMousePosition().y)
        local wave = WM.GetCurrentWave()
        local isSupply = (wave and wave.rewardType == "supply")
        if isSupply then
            HandleRewardClick()
        else
            local choices = WM.rewardChoices
            local cardCount = #choices
            if cardCount > 0 then
                local cardW = 140
                local cardH = 170
                local gap = 20
                local totalW = cardCount * cardW + (cardCount - 1) * gap
                local startX = (DESIGN_W - totalW) / 2
                local cardY = (DESIGN_H - cardH) / 2 + 10
                for i = 1, cardCount do
                    local cx = startX + (i - 1) * (cardW + gap)
                    if mx >= cx and mx <= cx + cardW and my >= cardY and my <= cardY + cardH then
                        WM.selectedReward = i
                        HandleRewardClick()
                        return
                    end
                end
            end
        end
        return
    end

    if not player.alive then return end

    -- 背包UI优先处理输入（非移动端或移动端也通过此路径处理鼠标）
    if InvUI.isOpen then
        local mx, my = G.ScreenToDesign(input:GetMousePosition().x, input:GetMousePosition().y)
        if InvUI.HandleMouseDown(mx, my, button) then
            return
        end
    end

    -- 移动端射击由摇杆处理，不走鼠标路径
    if not G.isMobile and button == MOUSEB_LEFT then
        if WM.phase ~= WM.PHASE_WALKOUT then
            Combat.TryShoot()
        end
    end

    -- 右键冲刺（PC 端）
    if not G.isMobile and button == MOUSEB_RIGHT then
        TryDash()
    end
end

function HandleMouseUp(eventType, eventData)
    local button = eventData["Button"]:GetInt()

    -- 标题页面: 鼠标释放（滑条拖拽结束）
    if G.gameState == G.STATE_TITLE and Title.active then
        local mx, my = G.ScreenToDesign(input:GetMousePosition().x, input:GetMousePosition().y)
        Title.HandleMouseUp(mx, my, button)
        return
    end

    if InvUI.isOpen then
        local mx, my = G.ScreenToDesign(input:GetMousePosition().x, input:GetMousePosition().y)
        InvUI.HandleMouseUp(mx, my, button)
    end
end

-- 奖励点击处理
function HandleRewardClick()
    local player = G.player
    local wave = WM.GetCurrentWave()
    if not wave then return end

    if wave.rewardType == "supply" then
        WM.ApplyAllSupply(player)
    elseif wave.rewardType == "choice" then
        WM.ApplyReward(WM.selectedReward, player)
    end

    -- 开始过渡动画
    WM.StartTransition()
    G.PlaySfx(G.sndRewardSelect, 0.5)
    WM.transitCallback = function()
        G.camZoom = 1.3
        Map.GenerateMap()
        Enemy.SpawnEnemies()
        local newWave = WM.GetCurrentWave()
        if newWave then
            G.waveAnnounceTimer = 3.0
            G.waveAnnounceText = "Wave " .. WM.currentWave .. " - " .. newWave.name
            if newWave.type == "boss" then
                G.PlaySfx(G.sndBossAppear, 0.6)
            else
                G.PlaySfx(G.sndWaveStart, 0.5)
            end
        end
    end
end

-- ============================================================================
-- 拾取辅助函数
-- ============================================================================
function GetNearbyArtifactLoot(radius)
    local player = G.player
    local result = {}
    for _, item in ipairs(G.lootItems) do
        if item.type == "artifact" then
            local dx = player.x - item.x
            local dy = player.y - item.y
            if dx * dx + dy * dy <= radius * radius then
                table.insert(result, item)
            end
        end
    end
    return result
end

function UI_CollectNearbyPickups()
    local nearby = GetNearbyArtifactLoot(60)
    local pickups = {}
    for _, lootItem in ipairs(nearby) do
        table.insert(pickups, {
            item = lootItem.itemData,
            lootRef = lootItem,
        })
    end
    InvUI.SetPickupItems(pickups)
end

function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    local player = G.player

    -- 漫画阶段: Esc跳过, 空格/回车翻页
    if G.gameState == G.STATE_COMIC and Comic.active then
        if key == KEY_ESCAPE then
            Comic.Skip()
            G.gameState = G.STATE_TITLE
            Title.Init(G.vg)
            return
        end
        if key == KEY_SPACE or key == KEY_RETURN then
            Comic.NextPage()
            if Comic.finished then
                G.gameState = G.STATE_TITLE
                Title.Init(G.vg)
            end
            return
        end
        return
    end

    -- 标题页面: 按键处理
    if G.gameState == G.STATE_TITLE and Title.active then
        Title.HandleKeyDown(key)
        if Title.finished then
            G.gameState = G.STATE_PLAYING
            Tutorial.Init()
            BGM.PlayForWave(WM.currentWave, WM.GetWaveCount())
        end
        return
    end

    -- 教程提示显示中：拦截所有按键（必须点击 banner 才能继续）
    if G.gameState == G.STATE_PLAYING and Tutorial.currentTip then
        return
    end

    -- 奖励选择阶段: 数字键快捷选择
    if WM.phase == WM.PHASE_REWARD and G.gameState == G.STATE_PLAYING then
        local numChoices = #WM.rewardChoices
        if key == KEY_1 and numChoices >= 1 then
            WM.selectedReward = 1; HandleRewardClick(); return
        elseif key == KEY_2 and numChoices >= 2 then
            WM.selectedReward = 2; HandleRewardClick(); return
        elseif key == KEY_3 and numChoices >= 3 then
            WM.selectedReward = 3; HandleRewardClick(); return
        end
    end

    -- Tab 开关背包
    if key == KEY_TAB and G.gameState == G.STATE_PLAYING and player.alive then
        InvUI.Toggle()
        if InvUI.isOpen then
            G.gameTimeScale = 0.15
            UI_CollectNearbyPickups()
            G.PlaySfx(G.sndInventoryOpen, 0.5)
        else
            G.gameTimeScale = 1.0
            G.PlaySfx(G.sndInventoryClose, 0.4)
        end
        return
    end

    -- F键拾取附近配件
    if key == KEY_F and G.gameState == G.STATE_PLAYING and player.alive and not InvUI.isOpen then
        local nearby = GetNearbyArtifactLoot(60)
        if #nearby > 0 then
            InvUI.Open()
            G.gameTimeScale = 0.15
            UI_CollectNearbyPickups()
        end
        return
    end

    -- 背包打开时, 优先处理背包按键
    if InvUI.isOpen then
        if InvUI.HandleKeyDown(key) then
            return
        end
    end

    if key == KEY_R and G.gameState == G.STATE_PLAYING then
        local effectiveMag = WEAPON.magSize + WM.weaponMods.bonusMagSize + math.floor(Inv.GetStat("magSize", 0))
        if not player.reloading and player.ammo < effectiveMag and player.totalAmmo > 0 then
            player.reloading = true
            player.reloadTimer = WEAPON.reloadTime
            G.PlaySfx(G.sndReload, 0.5)
            print("Reloading...")
        end
    end

    if key == KEY_ESCAPE then
        if InvUI.isOpen then
            InvUI.Close()
            G.gameTimeScale = 1.0
            return
        end
        if G.gameState == G.STATE_PLAYING then
            G.gameState = G.STATE_PAUSED
        elseif G.gameState == G.STATE_PAUSED then
            G.gameState = G.STATE_PLAYING
        end
    end
end

-- ============================================================================
-- 搜刮系统
-- ============================================================================
function UpdateSearch(dt)
    local player = G.player
    local pc = math.floor(player.x / TILE_SIZE) + 1
    local pr = math.floor(player.y / TILE_SIZE) + 1

    if G.searchingCrate then
        G.searchingCrate.timer = G.searchingCrate.timer - dt
        if pc ~= G.searchingCrate.col or pr ~= G.searchingCrate.row then
            G.searchingCrate = nil
            return
        end
        if G.searchingCrate.timer <= 0 then
            local cx = (G.searchingCrate.col - 0.5) * TILE_SIZE
            local cy = (G.searchingCrate.row - 0.5) * TILE_SIZE
            G.mapData[G.searchingCrate.row][G.searchingCrate.col] = G.TILE_FLOOR

            local cfg = G.CRATE_CONFIG[G.searchingCrate.crateType] or G.CRATE_CONFIG[G.TILE_CRATE_WOOD]
            local roll = math.random(1, 100)
            if roll <= cfg.ammoChance then
                table.insert(G.lootItems, {x = cx, y = cy, type = "ammo",
                    amount = math.random(cfg.ammoRange[1], cfg.ammoRange[2])})
            elseif roll <= cfg.healthChance then
                table.insert(G.lootItems, {x = cx, y = cy, type = "health",
                    amount = math.random(cfg.healthRange[1], cfg.healthRange[2])})
            else
                local rarityBoost = Inv.GetStat("rarityBoost", 0)
                local maxRarity = cfg.maxRarity
                local artifact = Inv.CreateRandomArtifact(maxRarity, rarityBoost)
                if artifact then
                    table.insert(G.lootItems, {
                        x = cx + math.random(-6, 6),
                        y = cy + math.random(-6, 6),
                        type = "artifact",
                        itemData = artifact,
                    })
                end
            end

            G.PlaySfx(G.sndCrateOpen, 0.5)
            local scoreMap = {[G.TILE_CRATE_WOOD] = 20, [G.TILE_CRATE_IRON] = 40, [G.TILE_CRATE_GOLD] = 80}
            G.score = G.score + (scoreMap[G.searchingCrate.crateType] or 20)
            G.searchingCrate = nil
        end
    else
        if player.alive and pc >= 1 and pc <= G.MAP_COLS and pr >= 1 and pr <= G.MAP_ROWS then
            local tile = G.mapData[pr][pc]
            if G.IsCrateTile(tile) then
                local cfg = G.CRATE_CONFIG[tile] or G.CRATE_CONFIG[G.TILE_CRATE_WOOD]
                G.searchingCrate = {col = pc, row = pr, timer = cfg.searchTime,
                    crateType = tile, searchTime = cfg.searchTime}
                G.PlaySfx(G.sndCrateSearch, 0.4)
            end
        end
    end

    -- 拾取掉落物
    for i = #G.lootItems, 1, -1 do
        local item = G.lootItems[i]
        if item.type == "artifact" then
            -- 跳过, 由F键处理
        elseif Map.CircleCollision(player.x, player.y, player.radius + 10, item.x, item.y, 8) then
            if item.type == "ammo" then
                player.totalAmmo = player.totalAmmo + item.amount
                table.insert(G.damageNumbers, {
                    x = item.x, y = item.y - 10,
                    text = "+" .. item.amount .. " 弹药",
                    life = 1.0, maxLife = 1.0,
                    vy = -30,
                })
            elseif item.type == "health" then
                local effectiveMaxHp = player.maxHp + Inv.GetStat("maxHp", 0)
                player.hp = math.min(effectiveMaxHp, player.hp + item.amount)
                table.insert(G.damageNumbers, {
                    x = item.x, y = item.y - 10,
                    text = "+" .. item.amount .. " HP",
                    life = 1.0, maxLife = 1.0,
                    vy = -30,
                })
            end
            G.PlaySfx(G.sndItemPickup, 0.4)
            table.remove(G.lootItems, i)
        end
    end
end

-- ============================================================================
-- 相机
-- ============================================================================
function UpdateCamera()
    local player = G.player
    local viewW = DESIGN_W / G.camZoom
    local viewH = DESIGN_H / G.camZoom
    G.camX = player.x - viewW / 2
    G.camY = player.y - viewH / 2
    G.camX = math.max(0, math.min(G.MAP_W - viewW, G.camX))
    G.camY = math.max(0, math.min(G.MAP_H - viewH, G.camY))
end

-- ============================================================================
-- 重新开始
-- ============================================================================
function RestartGame()
    local player = G.player
    player.x = 0
    player.y = 0
    player.hp = 100
    player.maxHp = 100
    player.speed = 180
    player.ammo = 12
    player.totalAmmo = 150
    player.alive = true
    player.reloading = false
    player.reloadTimer = 0
    player.fireTimer = 0
    player.invincibleTimer = 0
    player.meleeTimer = 0
    player.meleeSwingTimer = 0
    player.meleeHitDone = false
    player.shield = 0
    player.shieldMax = 0
    player.shieldRegen = 0
    player.shieldRegenDelay = 0
    player.dashTimer    = 0
    player.dashCooldown = 0
    player.dashDirX     = 0
    player.dashDirY     = 0

    G.bullets = {}
    G.enemies = {}
    G.lootItems = {}
    G.particles = {}
    G.damageNumbers = {}
    G.drones = {}
    G.searchingCrate = nil

    G.gameTime = 0
    G.score = 0
    G.killCount = 0
    G.gameState = G.STATE_PLAYING
    G.waveAnnounceTimer = 0

    -- 重置背包
    Inv.Init()
    InvUI.Close()
    G.gameTimeScale = 1.0
    local starterArtifact = Inv.CreateArtifact("a_bullet_core")
    if starterArtifact then
        table.insert(G.lootItems, {
            x = player.x + math.random(-12, 12),
            y = player.y + math.random(-12, 12),
            type = "artifact",
            itemData = starterArtifact,
        })
    end

    -- 重置相机和死亡动画
    G.camZoom = 1.3
    G.deathAnimTimer = 0
    G.deathSlowScale = 1.0

    -- 重置波次管理器
    WM.Init()
    Map.GenerateMap()
    Enemy.SpawnEnemies()

    local w1 = WM.GetCurrentWave()
    G.waveAnnounceTimer = 3.0
    G.waveAnnounceText = "Wave 1 - " .. (w1 and w1.name or "")

    -- 重启游戏：重新按当前波次播放对应 BGM
    BGM.PlayForWave(WM.currentWave, WM.GetWaveCount())
end

-- ============================================================================
-- 更新逻辑
-- ============================================================================
function HandleUpdate(eventType, eventData)
    local rawDt = eventData["TimeStep"]:GetFloat()
    local player = G.player

    -- BGM 循环兜底（每帧检查，确保曲目结束后自动重启）
    BGM.Update()

    -- 漫画开场更新
    if G.gameState == G.STATE_COMIC then
        Comic.Update(rawDt)
        if Comic.finished then
            G.gameState = G.STATE_TITLE
            Title.Init(G.vg)
        end
        return
    end

    -- 标题页面更新
    if G.gameState == G.STATE_TITLE then
        Title.Update(rawDt)
        -- 鼠标移动处理（悬停+滑条拖拽）
        local pmx, pmy = G.ScreenToDesign(input:GetMousePosition().x, input:GetMousePosition().y)
        Title.HandleMouseMove(pmx, pmy)
        if Title.finished then
            G.gameState = G.STATE_PLAYING
            BGM.PlayForWave(WM.currentWave, WM.GetWaveCount())
        end
        return
    end

    -- 死亡电影化效果更新
    if G.gameState == G.STATE_DYING then
        G.deathAnimTimer = G.deathAnimTimer + rawDt
        local progress = math.min(1.0, G.deathAnimTimer / G.DEATH_ANIM_DURATION)
        G.deathSlowScale = math.max(0, 1.0 - progress * 2.5)
        local targetZoom = 2.2
        local zoomProgress = math.min(1.0, progress * 1.5)
        local ease = 1.0 - (1.0 - zoomProgress) * (1.0 - zoomProgress)
        G.camZoom = G.deathZoomStart + (targetZoom - G.deathZoomStart) * ease
        UpdateCamera()
        Fx.UpdateParticles(rawDt * G.deathSlowScale)
        Fx.UpdateDamageNumbers(rawDt * G.deathSlowScale)
        if G.deathAnimTimer >= G.DEATH_ANIM_DURATION then
            G.gameState = G.STATE_GAMEOVER
        end
        return
    end

    if G.gameState ~= G.STATE_PLAYING then return end

    -- 波次变化时同步切换 BGM（最后一波 → boss.ogg；其他 → 2~5.ogg 循环）
    if G.lastBgmWave ~= WM.currentWave then
        BGM.PlayForWave(WM.currentWave, WM.GetWaveCount())
        G.lastBgmWave = WM.currentWave
    end

    -- 情境式教程：检测触发条件 + 更新动画
    Tutorial.CheckTriggers()
    Tutorial.Update(rawDt)

    -- 教程显示中：暂停所有游戏逻辑（仅相机继续更新以保持画面平滑）
    if Tutorial.IsBlocking() then
        UpdateCamera()
        return
    end

    -- 冲刺冷却倒计时（放在所有 phase 分支之前，保证任何阶段都递减）
    if player.dashCooldown > 0 then
        player.dashCooldown = player.dashCooldown - rawDt
        if player.dashCooldown < 0 then player.dashCooldown = 0 end
    end

    -- 近战计时器在所有 phase 分支前递减（避免奖励/出口/走出/清除等阶段卡住玩家挥砍）
    -- 注意：dashTimer 不在此处递减，由后面的"冲刺位置更新"统一处理（包含位置推进 + 计时）
    if player.meleeTimer and player.meleeTimer > 0 then
        player.meleeTimer = player.meleeTimer - rawDt
        if player.meleeTimer < 0 then player.meleeTimer = 0 end
    end
    if player.meleeSwingTimer and player.meleeSwingTimer > 0 then
        player.meleeSwingTimer = player.meleeSwingTimer - rawDt
        if player.meleeSwingTimer < 0 then player.meleeSwingTimer = 0 end
    end

    local dt = rawDt * G.gameTimeScale
    G.gameTimeAcc = G.gameTimeAcc + rawDt
    local g = GetGraphics()
    G.screenW = g:GetWidth()
    G.screenH = g:GetHeight()

    -- 波次管理器更新
    WM.Update(rawDt)

    if G.waveAnnounceTimer > 0 then
        G.waveAnnounceTimer = G.waveAnnounceTimer - rawDt
    end

    -- 过渡中: 只更新粒子和相机（仍要把进行中的冲刺推进完）
    if WM.transitPhase ~= "none" then
        UpdateDash(dt)
        Fx.UpdateParticles(dt)
        Fx.UpdateShake(dt)
        UpdateCamera()
        return
    end

    -- 奖励阶段: 暂停战斗（但仍要把进行中的冲刺推进完）
    if WM.phase == WM.PHASE_REWARD then
        UpdateDash(dt)
        Fx.UpdateParticles(dt)
        UpdateCamera()
        return
    end

    -- 出口开放阶段
    if WM.phase == WM.PHASE_EXIT_OPEN then
        if not WM.exitReady then
            Map.SpawnExit()
        end

        UpdateDash(dt)
        Combat.UpdatePlayer(dt)
        Bullet.UpdateBullets(dt)
        UpdateSearch(dt)
        Fx.UpdateParticles(dt)
        Fx.UpdateDamageNumbers(dt)
        UpdateCamera()

        if player.alive and not InvUI.isOpen then
            if G.isMobile then
                if MI.isShooting then Combat.TryShoot() end
            else
                if input:GetMouseButtonDown(MOUSEB_LEFT) then Combat.TryShoot() end
            end
        end

        -- 拾取掉落物(出口阶段残留)
        for i = #G.lootItems, 1, -1 do
            local item = G.lootItems[i]
            if item.type == "artifact" then
                -- 跳过
            elseif Map.CircleCollision(player.x, player.y, player.radius + 10, item.x, item.y, 8) then
                if item.type == "ammo" then
                    player.totalAmmo = player.totalAmmo + item.amount
                elseif item.type == "health" then
                    local effectiveMaxHp = player.maxHp + Inv.GetStat("maxHp", 0)
                    player.hp = math.min(effectiveMaxHp, player.hp + item.amount)
                end
                G.PlaySfx(G.sndItemPickup, 0.4)
                table.remove(G.lootItems, i)
            end
        end

        -- 检测玩家到达出口
        local exitDist = math.sqrt((player.x - WM.exitX)^2 + (player.y - WM.exitY)^2)
        if exitDist < 40 then
            WM.phase = WM.PHASE_WALKOUT
            WM.walkoutTimer = WM.walkoutDuration
            G.walkoutStartX = player.x
            G.walkoutStartY = player.y
            G.walkoutTargetX = WM.exitX
            G.walkoutTargetY = WM.exitY
            G.walkoutZoomStart = G.camZoom
            G.walkoutZoomEnd = math.min(1.0, G.camZoom + 0.15)
            G.PlaySfx(G.sndPortalEnter, 0.5)
            G.PlaySfx(G.sndLevelClear, 0.6)
        end
        return
    end

    -- 走出动画阶段
    if WM.phase == WM.PHASE_WALKOUT then
        local progress = 1.0 - (WM.walkoutTimer / WM.walkoutDuration)
        progress = math.max(0, math.min(1, progress))
        local ease = progress < 0.5
            and (2 * progress * progress)
            or (1 - (-2 * progress + 2)^2 / 2)

        player.x = G.walkoutStartX + (G.walkoutTargetX - G.walkoutStartX) * ease
        player.y = G.walkoutStartY + (G.walkoutTargetY - G.walkoutStartY) * ease
        player.angle = math.atan(G.walkoutTargetY - G.walkoutStartY, G.walkoutTargetX - G.walkoutStartX)
        G.camZoom = G.walkoutZoomStart + (G.walkoutZoomEnd - G.walkoutZoomStart) * ease

        if math.random() < 0.4 then
            table.insert(G.particles, {
                x = player.x + (math.random() - 0.5) * 16,
                y = player.y + (math.random() - 0.5) * 16,
                vx = (math.random() - 0.5) * 30,
                vy = -20 - math.random() * 20,
                life = 0.6 + math.random() * 0.3,
                maxLife = 0.9,
                r = 80, g = 255, b = 120,
                size = 2 + math.random() * 3,
                drag = 0.95,
            })
        end

        Fx.UpdateParticles(dt)
        UpdateCamera()
        return
    end

    -- 胜利阶段
    if WM.phase == WM.PHASE_VICTORY then
        G.gameState = G.STATE_VICTORY
        return
    end

    -- 清除展示阶段: 不冻结, 继续正常逻辑
    -- (WM.Update 会在 phaseTimer 倒计时结束后自动推进到 EXIT_OPEN)

    -- 命中停顿
    if G.hitstopTimer > 0 then
        G.hitstopTimer = G.hitstopTimer - rawDt
        Fx.UpdateShake(rawDt)
        return
    end

    -- 更新游戏时间
    G.gameTime = G.gameTime + dt

    -- 动态难度调整
    WM.UpdateDifficulty(player.hp / (player.maxHp + Inv.GetStat("maxHp", 0)))

    -- 冲刺位置更新（在 Combat.UpdatePlayer 之前，覆盖普通移动）
    UpdateDash(dt)

    Combat.UpdatePlayer(dt)
    Combat.UpdateDrones(dt)
    Bullet.UpdateBullets(dt)
    Enemy.UpdateEnemies(dt)
    Fx.UpdateParticles(dt)
    Fx.UpdateDamageNumbers(dt)
    UpdateSearch(dt)
    Fx.UpdateShake(dt)
    UpdateCamera()

    -- Boss特殊行为
    if WM.phase == WM.PHASE_BOSS and WM.boss and WM.boss.hp > 0 then
        local summoned, chargeImpact, spinBullets = WM.UpdateBossBehavior(WM.boss, dt, player.x, player.y)
        if summoned then
            Enemy.SpawnBossMinions(summoned.count)
            G.PlaySfx(G.sndBossSummon, 0.5)
        end
        if chargeImpact then
            G.PlaySfx(G.sndBossCharge, 0.5)
            local cdx = player.x - chargeImpact.x
            local cdy = player.y - chargeImpact.y
            local cdist = math.sqrt(cdx * cdx + cdy * cdy)
            if cdist < chargeImpact.radius and player.invincibleTimer <= 0 and not (player.dashTimer > 0) then
                player.hp = player.hp - chargeImpact.damage
                player.invincibleTimer = 0.5
                table.insert(G.damageNumbers, {
                    x = player.x, y = player.y - player.radius - 5,
                    text = tostring(chargeImpact.damage),
                    life = 0.8, maxLife = 0.8, vy = -40,
                    isPlayer = true,
                })
                if player.hp <= 0 then
                    player.hp = 0
                    player.alive = false
                    G.gameState = G.STATE_DYING
                    G.deathAnimTimer = 0
                    G.deathZoomStart = G.camZoom
                    G.deathSlowScale = 1.0
                    G.PlaySfx(G.sndPlayerDeath, 0.6)
                end
            end
            for kp = 1, 20 do
                local pa = (kp / 20) * math.pi * 2
                local spd = chargeImpact.radius * 2.5
                table.insert(G.particles, {
                    x = chargeImpact.x, y = chargeImpact.y,
                    vx = math.cos(pa) * spd, vy = math.sin(pa) * spd,
                    life = 0.3, maxLife = 0.3,
                    r = 255, g = 80, b = 40,
                    size = 3 + math.random() * 2, glow = true,
                })
            end
            Fx.TriggerShake(5, 0.15)
        end
        if spinBullets then
            for _, sb in ipairs(spinBullets) do
                table.insert(G.bullets, {
                    x = sb.x, y = sb.y,
                    vx = sb.vx, vy = sb.vy,
                    damage = sb.damage,
                    radius = 3.5,
                    fromPlayer = false,
                    life = 2.5,
                    trail = {},
                })
            end
        end
    end

    -- 小Boss特殊行为
    for _, e in ipairs(G.enemies) do
        if e.isMiniBoss and e.hp > 0 then
            WM.UpdateMiniBossBehavior(e, dt, player.x, player.y)
        end
    end

    -- 波次清除检测
    local aliveEnemies = #G.enemies
    if WM.CheckWaveCleared(aliveEnemies) then
        WM.OnWaveCleared()
        if WM.phase == WM.PHASE_VICTORY then
            G.gameState = G.STATE_VICTORY
        end
        G.PlaySfx(G.sndLevelClear, 0.6)
        G.PlaySfx(G.sndWaveStart, 0.5)
    end

    -- 持续射击
    if player.alive and not InvUI.isOpen then
        if G.isMobile then
            if MI.isShooting then Combat.TryShoot() end
        else
            if input:GetMouseButtonDown(MOUSEB_LEFT) then Combat.TryShoot() end
        end
    end

    -- 生命回复
    local hpRegen = Inv.GetStat("hpRegen", 0)
    if hpRegen > 0 and player.hp < player.maxHp + Inv.GetStat("maxHp", 0) then
        player.hp = math.min(player.maxHp + Inv.GetStat("maxHp", 0),
            player.hp + hpRegen * dt)
    end

    -- 护盾系统更新
    local shieldMaxStat = Inv.GetStat("shieldMax", 0)
    local shieldRegenStat = Inv.GetStat("shieldRegen", 0)
    player.shieldMax = shieldMaxStat
    if shieldMaxStat > 0 then
        if player.shieldRegenDelay > 0 then
            player.shieldRegenDelay = player.shieldRegenDelay - dt
        else
            if player.shield < shieldMaxStat and shieldRegenStat > 0 then
                player.shield = math.min(shieldMaxStat, player.shield + shieldRegenStat * dt)
            end
        end
    else
        player.shield = 0
    end

    -- 近战系统更新
    if player.meleeTimer > 0 then
        player.meleeTimer = player.meleeTimer - dt
    end
    if player.meleeSwingTimer > 0 then
        player.meleeSwingTimer = player.meleeSwingTimer - dt
        if not player.meleeHitDone and player.meleeSwingTimer <= player.meleeSwingDur * 0.5 then
            player.meleeHitDone = true
            local meleeDmg = WEAPON.damage
            local meleeRange = player.meleeRange + player.radius
            local hitAny = false
            for _, e in ipairs(G.enemies) do
                local dx = e.x - player.x
                local dy = e.y - player.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < meleeRange + e.radius then
                    local angleToEnemy = math.atan(dy, dx)
                    local angleDiff = angleToEnemy - player.angle
                    angleDiff = math.atan(math.sin(angleDiff), math.cos(angleDiff))
                    if math.abs(angleDiff) <= player.meleeArc * 0.5 then
                        e.hp = e.hp - meleeDmg
                        e.hitFlashTimer = 0.15
                        hitAny = true
                        table.insert(G.damageNumbers, {
                            x = e.x, y = e.y - e.radius - 5,
                            text = tostring(meleeDmg),
                            life = 0.8, maxLife = 0.8,
                            vy = -40,
                        })
                        local hitAngle = math.atan(dy, dx)
                        for k = 1, 8 do
                            local pa = hitAngle + (math.random() - 0.5) * 1.0
                            local spd = 80 + math.random() * 120
                            table.insert(G.particles, {
                                x = e.x, y = e.y,
                                vx = math.cos(pa) * spd, vy = math.sin(pa) * spd,
                                life = 0.2 + math.random() * 0.2, maxLife = 0.4,
                                r = 255, g = 220 + math.random(35), b = 80 + math.random(80),
                                size = 2 + math.random() * 2, drag = 0.94,
                            })
                        end
                        local pushAngle = math.atan(dy, dx)
                        local pushForce = 150
                        e.vx = (e.vx or 0) + math.cos(pushAngle) * pushForce
                        e.vy = (e.vy or 0) + math.sin(pushAngle) * pushForce
                        if e.hp <= 0 then
                            G.killCount = G.killCount + 1
                            G.score = G.score + 10
                            for k = 1, 12 do
                                local pa2 = math.random() * math.pi * 2
                                local spd2 = 60 + math.random() * 100
                                table.insert(G.particles, {
                                    x = e.x, y = e.y,
                                    vx = math.cos(pa2) * spd2, vy = math.sin(pa2) * spd2,
                                    life = 0.3 + math.random() * 0.3, maxLife = 0.6,
                                    r = e.color[1], g = e.color[2], b = e.color[3],
                                    size = 2 + math.random() * 2, gravity = 100, drag = 0.96,
                                })
                            end
                            G.PlaySfx(G.sndKill, 0.5)
                            G.PlaySfx(G.sndEnemyDeath, 0.35)
                        else
                            G.PlaySfx(G.sndMeleeHit, 0.4)
                        end
                    end
                end
            end
            if not hitAny then
                G.PlaySfx(G.sndMeleeHit, 0.2)
            end
        end
    end

    -- 链式闪电延迟队列更新（逐跳执行）
    for ci = #G.pendingChainLightning, 1, -1 do
        local chain = G.pendingChainLightning[ci]
        chain.timer = chain.timer - dt
        if chain.timer <= 0 and chain.remainBounces > 0 then
            -- 执行一跳
            local nearest = nil
            local nearestDist = chain.searchRange + 1
            for kk = 1, #G.enemies do
                local et = G.enemies[kk]
                if not chain.hitSet[et] and et.hp > 0 then
                    local dx = et.x - chain.sourceX
                    local dy = et.y - chain.sourceY
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist <= chain.searchRange and dist < nearestDist then
                        nearest = et
                        nearestDist = dist
                    end
                end
            end

            if not nearest then
                -- 没有可跳跃的目标，链断裂
                table.remove(G.pendingChainLightning, ci)
            else
                chain.hitSet[nearest] = true
                local aDmg = math.floor(chain.currentDmg)
                if nearest.armor and nearest.armor > 0 then
                    aDmg = math.max(1, math.floor(aDmg * (1 - nearest.armor)))
                end
                nearest.hp = nearest.hp - aDmg
                nearest.hitFlashTimer = 0.15

                -- 伤害数字
                table.insert(G.damageNumbers, {
                    x = nearest.x, y = nearest.y - nearest.radius - 5,
                    text = tostring(aDmg),
                    life = 0.8, maxLife = 0.8, vy = -35,
                    isShock = true,
                })
                -- 闪电连线视觉
                table.insert(G.lightningEffects, {
                    x1 = chain.sourceX, y1 = chain.sourceY,
                    x2 = nearest.x, y2 = nearest.y,
                    life = 0.3, maxLife = 0.3,
                })
                -- 电弧粒子
                for sp = 1, 4 do
                    local sAngle = math.random() * math.pi * 2
                    table.insert(G.particles, {
                        x = nearest.x, y = nearest.y,
                        vx = math.cos(sAngle) * 40, vy = math.sin(sAngle) * 40,
                        life = 0.15, maxLife = 0.15,
                        r = 100, g = 180, b = 255,
                        size = 2 + math.random() * 2, glow = true,
                    })
                end
                -- 击杀判定
                if nearest.hp <= 0 and not nearest.dead then
                    nearest.dead = true
                    G.killCount = G.killCount + 1
                    WM.OnEnemyKilled()
                    G.score = G.score + 50
                    for sp2 = 1, 10 do
                        local pa2 = math.random() * math.pi * 2
                        local spd2 = 60 + math.random() * 100
                        table.insert(G.particles, {
                            x = nearest.x, y = nearest.y,
                            vx = math.cos(pa2) * spd2, vy = math.sin(pa2) * spd2,
                            life = 0.3 + math.random() * 0.3, maxLife = 0.6,
                            r = 80, g = 160, b = 255,
                            size = 2 + math.random() * 2, glow = true,
                        })
                    end
                end

                -- 准备下一跳
                chain.currentDmg = chain.currentDmg * chain.damageDecay
                chain.sourceX = nearest.x
                chain.sourceY = nearest.y
                chain.remainBounces = chain.remainBounces - 1
                chain.timer = chain.delay

                if chain.remainBounces <= 0 then
                    table.remove(G.pendingChainLightning, ci)
                end
            end
        end
    end

    -- 闪电特效更新
    for i = #G.lightningEffects, 1, -1 do
        G.lightningEffects[i].life = G.lightningEffects[i].life - dt
        if G.lightningEffects[i].life <= 0 then
            table.remove(G.lightningEffects, i)
        end
    end
end

-- ============================================================================
-- NanoVG 渲染
-- ============================================================================
function HandleNanoVGRender(eventType, eventData)
    if G.vg == nil then return end
    local vg = G.vg
    local player = G.player

    local g = GetGraphics()
    G.screenW = g:GetWidth()
    G.screenH = g:GetHeight()

    -- 计算设计分辨率缩放 (SHOW_ALL)
    local scaleX = G.screenW / DESIGN_W
    local scaleY = G.screenH / DESIGN_H
    G.renderScale = math.min(scaleX, scaleY)
    G.renderOffsetX = (G.screenW - DESIGN_W * G.renderScale) / 2
    G.renderOffsetY = (G.screenH - DESIGN_H * G.renderScale) / 2

    nvgBeginFrame(vg, G.screenW, G.screenH, 1.0)

    -- 漫画开场: 独占渲染，跳过游戏画面
    if G.gameState == G.STATE_COMIC and Comic.active then
        Comic.Draw(vg, G.screenW, G.screenH)
        nvgEndFrame(vg)
        return
    end

    -- 标题页面: 独占渲染
    if G.gameState == G.STATE_TITLE and Title.active then
        Title.Draw(vg, G.screenW, G.screenH)
        nvgEndFrame(vg)
        return
    end

    -- 深色森林填充整个屏幕(防止letterbox黑边)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, G.screenW, G.screenH)
    nvgFillColor(vg, nvgRGBA(20, 35, 15, 255))
    nvgFill(vg)

    -- 世界空间 (设计分辨率缩放 + 相机缩放 + 相机偏移 + 震动)
    nvgSave(vg)
    nvgTranslate(vg, G.renderOffsetX, G.renderOffsetY)
    nvgScale(vg, G.renderScale, G.renderScale)
    nvgScale(vg, G.camZoom, G.camZoom)
    nvgTranslate(vg, -G.camX + G.shakeOffsetX, -G.camY + G.shakeOffsetY)

    RW.DrawMap(DESIGN_W, DESIGN_H)
    RW.DrawLootItems()
    RW.DrawEnemies()
    RW.DrawBullets()
    RW.DrawPlayer()
    RW.DrawDrones()
    RW.DrawParticles()

    RW.DrawLightningEffects()
    RW.DrawShield()

    RW.DrawDamageNumbers()
    RW.DrawFogOfWar(DESIGN_W, DESIGN_H)
    RW.DrawSearchProgress()

    -- 出口光柱特效 (世界空间)
    if (WM.phase == WM.PHASE_EXIT_OPEN or WM.phase == WM.PHASE_WALKOUT) and WM.exitReady then
        local t = GetTime():GetElapsedTime()
        local pulse = 0.5 + 0.5 * math.sin(t * 3)
        local beamAlpha = math.floor(40 + 30 * pulse)

        local beamW = TILE_SIZE * 2
        local beamH = TILE_SIZE * 6
        local beamX = WM.exitX - beamW / 2
        local beamY = WM.exitY - beamH

        local beamGrad = nvgLinearGradient(vg,
            beamX + beamW / 2, WM.exitY,
            beamX + beamW / 2, beamY,
            nvgRGBA(80, 255, 120, beamAlpha),
            nvgRGBA(80, 255, 120, 0))
        nvgBeginPath(vg)
        nvgRect(vg, beamX, beamY, beamW, beamH)
        nvgFillPaint(vg, beamGrad)
        nvgFill(vg)

        local ringRadius = TILE_SIZE * 1.5 + 4 * math.sin(t * 2)
        nvgBeginPath(vg)
        nvgCircle(vg, WM.exitX, WM.exitY, ringRadius)
        nvgStrokeColor(vg, nvgRGBA(80, 255, 120, math.floor(100 * pulse)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(80, 255, 120, math.floor(200 * pulse)))
        nvgText(vg, WM.exitX, WM.exitY - TILE_SIZE * 1.8, "出口", nil)
    end

    nvgRestore(vg)

    -- 受伤红色闪屏(暗角)
    if player.invincibleTimer > 0 then
        local flashAlpha = math.floor(player.invincibleTimer / 0.3 * 80)
        flashAlpha = math.max(0, math.min(80, flashAlpha))
        nvgSave(vg)
        nvgTranslate(vg, G.renderOffsetX, G.renderOffsetY)
        nvgScale(vg, G.renderScale, G.renderScale)
        local vignette = nvgRadialGradient(vg, DESIGN_W / 2, DESIGN_H / 2,
            DESIGN_W * 0.25, DESIGN_W * 0.7,
            nvgRGBA(255, 0, 0, 0),
            nvgRGBA(180, 0, 0, flashAlpha))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillPaint(vg, vignette)
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- 低血量持续暗角警告
    local warnMaxHp = player.maxHp + Inv.GetStat("maxHp", 0)
    if player.hp < warnMaxHp * 0.3 and player.alive then
        local pulse = math.sin(GetTime():GetElapsedTime() * 5) * 0.4 + 0.6
        local warnAlpha = math.floor((1 - player.hp / (warnMaxHp * 0.3)) * 50 * pulse)
        nvgSave(vg)
        nvgTranslate(vg, G.renderOffsetX, G.renderOffsetY)
        nvgScale(vg, G.renderScale, G.renderScale)
        local warnGrad = nvgRadialGradient(vg, DESIGN_W / 2, DESIGN_H / 2,
            DESIGN_W * 0.2, DESIGN_W * 0.65,
            nvgRGBA(0, 0, 0, 0),
            nvgRGBA(120, 0, 0, warnAlpha))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillPaint(vg, warnGrad)
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- HUD (设计分辨率空间)
    nvgSave(vg)
    nvgTranslate(vg, G.renderOffsetX, G.renderOffsetY)
    nvgScale(vg, G.renderScale, G.renderScale)
    RH.DrawHUD(DESIGN_W, DESIGN_H, GetNearbyArtifactLoot)
    nvgRestore(vg)

    -- 背包UI
    if InvUI.isOpen then
        local mx, my = G.ScreenToDesign(input:GetMousePosition().x, input:GetMousePosition().y)
        nvgSave(vg)
        nvgTranslate(vg, G.renderOffsetX, G.renderOffsetY)
        nvgScale(vg, G.renderScale, G.renderScale)
        InvUI.Draw(vg, DESIGN_W, DESIGN_H, mx, my)
        nvgRestore(vg)
    end

    -- 波次清除公告
    if WM.phase == WM.PHASE_CLEARED then
        nvgSave(vg)
        nvgTranslate(vg, G.renderOffsetX, G.renderOffsetY)
        nvgScale(vg, G.renderScale, G.renderScale)
        RH.DrawWaveCleared(DESIGN_W, DESIGN_H)
        nvgRestore(vg)
    end

    -- 出口方向指示器
    if WM.phase == WM.PHASE_EXIT_OPEN or WM.phase == WM.PHASE_WALKOUT then
        nvgSave(vg)
        nvgTranslate(vg, G.renderOffsetX, G.renderOffsetY)
        nvgScale(vg, G.renderScale, G.renderScale)
        RH.DrawExitIndicator(DESIGN_W, DESIGN_H)
        nvgRestore(vg)
    end

    -- 奖励选择界面
    if WM.phase == WM.PHASE_REWARD then
        nvgSave(vg)
        nvgTranslate(vg, G.renderOffsetX, G.renderOffsetY)
        nvgScale(vg, G.renderScale, G.renderScale)
        RH.DrawRewardScreen(DESIGN_W, DESIGN_H)
        nvgRestore(vg)
    end

    -- 波次开始公告
    if G.waveAnnounceTimer > 0 and WM.phase ~= WM.PHASE_REWARD and WM.phase ~= WM.PHASE_CLEARED then
        nvgSave(vg)
        nvgTranslate(vg, G.renderOffsetX, G.renderOffsetY)
        nvgScale(vg, G.renderScale, G.renderScale)
        RH.DrawWaveAnnounce(DESIGN_W, DESIGN_H)
        nvgRestore(vg)
    end

    -- Boss血条
    if WM.phase == WM.PHASE_BOSS and WM.boss and WM.boss.hp > 0 then
        nvgSave(vg)
        nvgTranslate(vg, G.renderOffsetX, G.renderOffsetY)
        nvgScale(vg, G.renderScale, G.renderScale)
        RH.DrawBossHPBar(DESIGN_W, DESIGN_H)
        nvgRestore(vg)
    end

    -- 过渡遮罩
    if WM.transitAlpha > 0 then
        nvgSave(vg)
        nvgTranslate(vg, G.renderOffsetX, G.renderOffsetY)
        nvgScale(vg, G.renderScale, G.renderScale)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(math.min(255, WM.transitAlpha))))
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- 死亡电影化效果
    if G.gameState == G.STATE_DYING then
        nvgSave(vg)
        nvgTranslate(vg, G.renderOffsetX, G.renderOffsetY)
        nvgScale(vg, G.renderScale, G.renderScale)
        RH.DrawDeathCinematic(DESIGN_W, DESIGN_H)
        nvgRestore(vg)
    end

    -- 游戏结束/胜利画面
    if G.gameState == G.STATE_GAMEOVER or G.gameState == G.STATE_VICTORY then
        nvgSave(vg)
        nvgTranslate(vg, G.renderOffsetX, G.renderOffsetY)
        nvgScale(vg, G.renderScale, G.renderScale)
        RH.DrawEndScreen(DESIGN_W, DESIGN_H)
        nvgRestore(vg)
    end

    -- 新手教程提示
    if Tutorial.currentTip then
        nvgSave(vg)
        nvgTranslate(vg, G.renderOffsetX, G.renderOffsetY)
        nvgScale(vg, G.renderScale, G.renderScale)
        Tutorial.Draw(vg, DESIGN_W, DESIGN_H)
        nvgRestore(vg)
    end

    -- 移动端触控控件 (摇杆+按钮)
    if G.isMobile and G.gameState == G.STATE_PLAYING then
        nvgSave(vg)
        nvgTranslate(vg, G.renderOffsetX, G.renderOffsetY)
        nvgScale(vg, G.renderScale, G.renderScale)
        MI.DrawControls(DESIGN_W, DESIGN_H)
        nvgRestore(vg)
    end

    nvgEndFrame(vg)
end
