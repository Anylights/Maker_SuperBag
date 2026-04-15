-- ============================================================================
-- 《小狼救红帽》 Little Wolf's Rescue
-- 2D俯视角PVE射击游戏 - 小狼深入森林拯救小红帽
-- 玩家移动(WASD) + 鼠标瞄准射击 + 子弹系统 + 3种敌人 + 地图 + 战争迷雾 + HUD
-- ============================================================================

require "LuaScripts/Utilities/Sample"

-- 背包系统模块
local InvData = require("inventory_data")
local Inv = require("inventory")
local InvUI = require("inventory_ui")

-- 波次管理器
local WM = require("wave_manager")

-- ============================================================================
-- 全局常量
-- ============================================================================
local TILE_SIZE = 32         -- 瓦片像素尺寸
local MAP_COLS = 40          -- 地图列数
local MAP_ROWS = 30          -- 地图行数
local MAP_W = MAP_COLS * TILE_SIZE
local MAP_H = MAP_ROWS * TILE_SIZE

-- 瓦片类型
local TILE_FLOOR = 0
local TILE_WALL = 1
local TILE_CRATE = 2         -- 可搜刮箱子
local TILE_EXIT = 3           -- 撤离点

-- 游戏状态
local STATE_PLAYING = "playing"
local STATE_PAUSED = "paused"
local STATE_GAMEOVER = "gameover"
local STATE_EXTRACTED = "extracted"  -- 保留兼容(不再用撤离, 用波次通关)
local STATE_VICTORY = "victory"      -- 全部通关

-- 武器数据
local WEAPON = {
    name = "弹弓",
    damage = 25,
    fireRate = 0.2,          -- 射击间隔(秒) — 稍快连射
    bulletSpeed = 1000,      -- 子弹速度(像素/秒) — 大幅提升
    magSize = 12,            -- 弹匣容量
    totalAmmo = 60,          -- 总弹药
    reloadTime = 1.5,        -- 换弹时间
    spread = 3,              -- 散布角度
    bulletRadius = 3,
}

-- 子弹拖尾最大记录长度
local TRAIL_MAX = 6

-- 敌人类型数据
local ENEMY_TYPES = {
    patrol = {
        name = "灰狼巡逻",
        hp = 50, speed = 60, damage = 10, radius = 12,
        color = {200, 80, 80},
        sightRange = 200, attackRange = 180, attackRate = 0.8,
        bulletSpeed = 350,
        attackPattern = "single",  -- 单发
    },
    sentry = {
        name = "灰狼哨兵",
        hp = 40, speed = 0, damage = 12, radius = 14,
        color = {80, 80, 200},
        sightRange = 280, attackRange = 260, attackRate = 1.8,
        bulletSpeed = 400,
        attackPattern = "burst",   -- 三连发
        burstCount = 3,            -- 每次连发3颗
        burstInterval = 0.1,       -- 连发间隔(秒)
    },
    rusher = {
        name = "灰狼突击",
        hp = 60, speed = 140, damage = 20, radius = 10,
        color = {200, 160, 40},
        sightRange = 160, attackRange = 30, attackRate = 0.5,
        bulletSpeed = 0,  -- 近战
        attackPattern = "melee",
    },
    heavy = {
        name = "灰狼重装",
        hp = 120, speed = 35, damage = 8, radius = 16,
        color = {100, 100, 120},
        sightRange = 220, attackRange = 160, attackRate = 2.2,
        bulletSpeed = 280,
        attackPattern = "shotgun",  -- 散弹(4发扇形)
        shotgunPellets = 4,         -- 弹丸数
        shotgunSpread = 0.35,       -- 扇形半角(弧度, ±20°)
        armor = 0.3,                -- 30%伤害减免
    },
}

-- ============================================================================
-- 全局变量
-- ============================================================================
local vg = nil               -- NanoVG 上下文
local fontNormal = -1

-- 角色图片句柄
local imgPlayer = -1
local imgEnemies = {}        -- typeKey → NanoVG image handle
local gameTimeAcc = 0        -- 累计时间(用于摇摆动画)

-- 音效
local sndShoot = nil
local sndReload = nil
local sndHit = nil
local sndKill = nil
local sndSplat = nil       -- 击杀溅血
local sndReloadDone = nil   -- 换弹完毕
local sndFootstep = nil     -- 脚步声
local sndLevelClear = nil   -- 过关成功
local footstepTimer = 0     -- 脚步声计时器
local audioScene = nil  -- 音频专用场景

local gameState = STATE_PLAYING
local gameTime = 0            -- 已用时间(秒, 正计时)
local score = 0
local killCount = 0

-- 波次系统
local waveAnnounceTimer = 0   -- 波次开始公告倒计时
local waveAnnounceText = ""   -- 公告文本

-- 相机偏移(世界坐标 → 屏幕坐标)
local camX = 0
local camY = 0
local camZoom = 0.75          -- 相机缩放(< 1 = 缩小看到更多, 1 = 原始比例)

-- 屏幕尺寸
local screenW = 0
local screenH = 0
local dpr = 1

-- 玩家
local player = {
    x = 0, y = 0,
    radius = 14,
    speed = 180,
    hp = 100, maxHp = 100,
    angle = 0,              -- 朝向角度(弧度)
    ammo = 12,              -- 当前弹匣
    totalAmmo = 60,
    reloading = false,
    reloadTimer = 0,
    fireTimer = 0,
    alive = true,
    invincibleTimer = 0,     -- 受伤无敌帧
}

-- 子弹列表
local bullets = {}           -- {x,y,vx,vy,damage,radius,fromPlayer,life}
-- 敌人列表
local enemies = {}           -- {x,y,type,hp,maxHp,radius,state,angle,fireTimer,...}
-- 掉落物列表
local lootItems = {}         -- {x,y,type,amount}
-- 粒子列表
local particles = {}
-- 伤害数字
local damageNumbers = {}

-- 地图数据
local mapData = {}           -- mapData[row][col] = tileType
local mapRooms = {}          -- 房间列表(GenerateMap保存, 供SpawnExit使用)

-- 搜刮状态
local searchingCrate = nil   -- 正在搜刮的箱子 {col,row,timer}
local SEARCH_TIME = 1.5

-- (撤离系统已移除, 改用波次通关)

-- 屏幕震动
local shakeIntensity = 0     -- 当前震动强度(像素)
local shakeTimer = 0         -- 震动剩余时间
local shakeOffsetX = 0       -- 当前帧偏移
local shakeOffsetY = 0

-- 命中停顿(Hitstop)
local hitstopTimer = 0       -- 停顿剩余时间(秒)
local HITSTOP_HIT = 0.03     -- 命中敌人停顿
local HITSTOP_KILL = 0.08    -- 击杀停顿

-- 走出动画状态
local walkoutStartX = 0      -- 走出动画起始位置
local walkoutStartY = 0
local walkoutTargetX = 0     -- 走出动画目标位置(出口中心)
local walkoutTargetY = 0
local walkoutZoomStart = 0.75  -- 走出动画起始缩放
local walkoutZoomEnd = 0.9     -- 走出动画结束缩放(微拉近)

-- 背包时间缩放(替代scene_:SetTimeScale)
local gameTimeScale = 1.0

-- 设计分辨率 (SHOW_ALL 策略, 所有设备看到相同画面)
local DESIGN_W = 1152
local DESIGN_H = 648
local renderScale = 1.0       -- 设计→物理的统一缩放比
local renderOffsetX = 0       -- 居中偏移(letterbox)
local renderOffsetY = 0

--- 物理屏幕坐标 → 设计坐标
local function ScreenToDesign(px, py)
    return (px - renderOffsetX) / renderScale, (py - renderOffsetY) / renderScale
end

-- ============================================================================
-- 音效播放辅助
-- ============================================================================
function PlaySfx(sound, gain)
    if not sound then return end
    if not audioScene then return end
    local node = audioScene:CreateChild("SfxNode")
    local src = node:CreateComponent("SoundSource")
    src.soundType = "Effect"
    src.gain = gain or 0.5
    src.autoRemoveMode = REMOVE_NODE
    src:Play(sound)
end

-- ============================================================================
-- 入口
-- ============================================================================
function Start()
    SampleStart()

    local g = GetGraphics()
    screenW = g:GetWidth()
    screenH = g:GetHeight()
    dpr = g:GetDPR()

    vg = nvgCreate(1)
    if vg == nil then
        print("ERROR: Failed to create NanoVG context")
        return
    end

    fontNormal = nvgCreateFont(vg, "sans", "fonts/KNMaiyuan/KNMaiyuan-Regular.ttf")
    if fontNormal == -1 then
        print("ERROR: Failed to load font")
    end

    -- 加载角色图片(绿幕抠图后的透明PNG)
    imgPlayer = nvgCreateImage(vg, "image/wolf_player.png", 0)
    imgPlayerWhite = nvgCreateImage(vg, "image/wolf_player_white.png", 0)
    imgEnemies = {
        patrol = nvgCreateImage(vg, "image/wolf_patrol.png", 0),
        sentry = nvgCreateImage(vg, "image/wolf_sentry.png", 0),
        rusher = nvgCreateImage(vg, "image/wolf_rusher.png", 0),
        heavy  = nvgCreateImage(vg, "image/wolf_heavy.png", 0),
        elite  = nvgCreateImage(vg, "image/wolf_elite.png", 0),
        boss   = nvgCreateImage(vg, "image/wolf_boss.png", 0),
    }
    imgEnemiesWhite = {
        patrol = nvgCreateImage(vg, "image/wolf_patrol_white.png", 0),
        sentry = nvgCreateImage(vg, "image/wolf_sentry_white.png", 0),
        rusher = nvgCreateImage(vg, "image/wolf_rusher_white.png", 0),
        heavy  = nvgCreateImage(vg, "image/wolf_heavy_white.png", 0),
        elite  = nvgCreateImage(vg, "image/wolf_elite_white.png", 0),
        boss   = nvgCreateImage(vg, "image/wolf_boss_white.png", 0),
    }
    -- 加载地形瓦片图片
    imgFloorTiles = {
        nvgCreateImage(vg, "image/tiles32/floor_0.png", 0),
        nvgCreateImage(vg, "image/tiles32/floor_1.png", 0),
        nvgCreateImage(vg, "image/tiles32/floor_2.png", 0),
        nvgCreateImage(vg, "image/tiles32/floor_3.png", 0),
    }
    imgForestTiles = {
        nvgCreateImage(vg, "image/tiles32/forest_0.png", 0),
        nvgCreateImage(vg, "image/tiles32/forest_1.png", 0),
        nvgCreateImage(vg, "image/tiles32/forest_2.png", 0),
        nvgCreateImage(vg, "image/tiles32/forest_3.png", 0),
    }
    imgDarkTiles = {
        nvgCreateImage(vg, "image/tiles32/dark_0.png", 0),
        nvgCreateImage(vg, "image/tiles32/dark_1.png", 0),
        nvgCreateImage(vg, "image/tiles32/dark_2.png", 0),
        nvgCreateImage(vg, "image/tiles32/dark_3.png", 0),
    }
    imgEdgeTiles = {
        nvgCreateImage(vg, "image/tiles32/edge_0.png", 0),
        nvgCreateImage(vg, "image/tiles32/edge_1.png", 0),
        nvgCreateImage(vg, "image/tiles32/edge_2.png", 0),
        nvgCreateImage(vg, "image/tiles32/edge_3.png", 0),
        nvgCreateImage(vg, "image/tiles32/edge_4.png", 0),
        nvgCreateImage(vg, "image/tiles32/edge_5.png", 0),
        nvgCreateImage(vg, "image/tiles32/edge_6.png", 0),
        nvgCreateImage(vg, "image/tiles32/edge_7.png", 0),
    }

    print("Player image: " .. tostring(imgPlayer))
    for k, v in pairs(imgEnemies) do
        print("Enemy image [" .. k .. "]: " .. tostring(v))
    end
    print("Tile images loaded: floor=" .. #imgFloorTiles .. " forest=" .. #imgForestTiles .. " dark=" .. #imgDarkTiles .. " edge=" .. #imgEdgeTiles)

    SampleInitMouseMode(MM_FREE)

    -- 加载音效
    -- 创建音频专用场景（纯NanoVG游戏无3D场景，需独立Scene播放音效）
    audioScene = Scene()
    audioScene:CreateComponent("Octree")

    sndShoot = cache:GetResource("Sound", "audio/sfx/sfx_shoot.ogg")
    sndReload = cache:GetResource("Sound", "audio/sfx/sfx_reload.ogg")
    sndHit = cache:GetResource("Sound", "audio/sfx/sfx_hit.ogg")
    sndKill = cache:GetResource("Sound", "audio/sfx/sfx_kill.ogg")
    sndSplat = cache:GetResource("Sound", "audio/sfx/sfx_splat.ogg")
    sndReloadDone = cache:GetResource("Sound", "audio/sfx/sfx_reload_done.ogg")
    sndFootstep = cache:GetResource("Sound", "audio/sfx/sfx_footstep.ogg")
    sndLevelClear = cache:GetResource("Sound", "audio/sfx/sfx_level_clear.ogg")

    -- 初始化背包系统
    Inv.Init()
    -- 给玩家初始圣物(教学引导)
    local starterArtifact = Inv.CreateArtifact("a_bullet_core", 1)
    if starterArtifact then
        Inv.AddPendingItem(starterArtifact)
    end

    -- 设置背包丢弃回调: 将物品丢到玩家脚下
    InvUI.onDiscardItem = function(item)
        table.insert(lootItems, {
            x = player.x + math.random(-16, 16),
            y = player.y + math.random(-16, 16),
            type = item.type,  -- "artifact" 或 "tablet"
            itemData = item,
        })
    end

    -- 初始化波次管理器
    WM.Init()
    -- 首波地图(直接构建, fade_in从黑屏渐亮)
    GenerateMap()
    SpawnEnemies()
    -- 波次公告
    local w1 = WM.GetCurrentWave()
    waveAnnounceTimer = 3.0
    waveAnnounceText = "Wave " .. WM.currentWave .. " - " .. (w1 and w1.name or "")

    print("=== 小狼救红帽 - 森林冒险模式 ===")
    print("WASD移动, 鼠标瞄准, 左键射击, R换弹")
    print("消灭所有敌人进入下一波!")

    SubscribeToEvent(vg, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
end

function Stop()
    if vg then
        nvgDelete(vg)
        vg = nil
    end
end

-- ============================================================================
-- 地图生成
-- ============================================================================
function GenerateMap()
    -- 根据波次调整地图大小
    local wave = WM.GetCurrentWave()
    if wave then
        MAP_COLS = wave.mapSize.cols
        MAP_ROWS = wave.mapSize.rows
    else
        MAP_COLS = 40
        MAP_ROWS = 30
    end
    MAP_W = MAP_COLS * TILE_SIZE
    MAP_H = MAP_ROWS * TILE_SIZE

    -- 初始化全部为墙
    for r = 1, MAP_ROWS do
        mapData[r] = {}
        for c = 1, MAP_COLS do
            mapData[r][c] = TILE_WALL
        end
    end

    -- 用房间+走廊算法挖出空间
    local rooms = {}
    local NUM_ROOMS = wave and wave.rooms or 12
    local MIN_ROOM = 4
    local MAX_ROOM = 8

    for i = 1, NUM_ROOMS do
        local rw = math.random(MIN_ROOM, MAX_ROOM)
        local rh = math.random(MIN_ROOM, MAX_ROOM)
        local rx = math.random(2, MAP_COLS - rw - 1)
        local ry = math.random(2, MAP_ROWS - rh - 1)

        -- 检查是否重叠(允许少量重叠)
        local ok = true
        for _, room in ipairs(rooms) do
            if rx < room.x + room.w + 1 and rx + rw + 1 > room.x and
               ry < room.y + room.h + 1 and ry + rh + 1 > room.y then
                ok = false
                break
            end
        end

        if ok then
            -- 挖出房间
            for r = ry, ry + rh - 1 do
                for c = rx, rx + rw - 1 do
                    mapData[r][c] = TILE_FLOOR
                end
            end
            table.insert(rooms, {x = rx, y = ry, w = rw, h = rh})
        end
    end

    -- 用走廊连接相邻房间
    for i = 2, #rooms do
        local r1 = rooms[i - 1]
        local r2 = rooms[i]
        local cx1 = math.floor(r1.x + r1.w / 2)
        local cy1 = math.floor(r1.y + r1.h / 2)
        local cx2 = math.floor(r2.x + r2.w / 2)
        local cy2 = math.floor(r2.y + r2.h / 2)

        -- 先水平再垂直
        local x = cx1
        while x ~= cx2 do
            if mapData[cy1] and mapData[cy1][x] then
                mapData[cy1][x] = TILE_FLOOR
                -- 走廊宽度2
                if cy1 + 1 <= MAP_ROWS then
                    mapData[cy1 + 1][x] = TILE_FLOOR
                end
            end
            x = x + (cx2 > cx1 and 1 or -1)
        end
        local y = cy1
        while y ~= cy2 do
            if mapData[y] and mapData[y][cx2] then
                mapData[y][cx2] = TILE_FLOOR
                if cx2 + 1 <= MAP_COLS then
                    mapData[y][cx2 + 1] = TILE_FLOOR
                end
            end
            y = y + (cy2 > cy1 and 1 or -1)
        end
    end

    -- 在随机房间放置箱子
    local crateCount = 0
    for _, room in ipairs(rooms) do
        local numCrates = math.random(1, 3)
        for j = 1, numCrates do
            local cx = math.random(room.x + 1, room.x + room.w - 2)
            local cy = math.random(room.y + 1, room.y + room.h - 2)
            if mapData[cy][cx] == TILE_FLOOR then
                mapData[cy][cx] = TILE_CRATE
                crateCount = crateCount + 1
            end
        end
    end

    -- 保存房间列表(供 SpawnExit 使用)
    mapRooms = rooms

    -- 玩家出生在第一个房间中心
    if #rooms >= 1 then
        local firstRoom = rooms[1]
        player.x = (firstRoom.x + firstRoom.w / 2) * TILE_SIZE
        player.y = (firstRoom.y + firstRoom.h / 2) * TILE_SIZE
    else
        player.x = MAP_W / 2
        player.y = MAP_H / 2
    end

    print("Map generated: " .. #rooms .. " rooms, " .. crateCount .. " crates")
end

-- ============================================================================
-- 出口生成 (波次清除后调用)
-- ============================================================================
function SpawnExit()
    if #mapRooms < 2 then
        -- 只有一个房间: 在房间边缘放出口
        local room = mapRooms[1] or {x = MAP_COLS / 2 - 2, y = MAP_ROWS / 2 - 2, w = 4, h = 4}
        local ec = room.x + room.w - 1
        local er = room.y + room.h - 1
        mapData[er][ec] = TILE_EXIT
        WM.exitX = (ec - 0.5) * TILE_SIZE
        WM.exitY = (er - 0.5) * TILE_SIZE
        WM.exitReady = true
        return
    end

    -- 找距离玩家最远的房间
    local bestDist = -1
    local bestRoom = nil
    for _, room in ipairs(mapRooms) do
        local rcx = (room.x + room.w / 2) * TILE_SIZE
        local rcy = (room.y + room.h / 2) * TILE_SIZE
        local dist = math.sqrt((rcx - player.x)^2 + (rcy - player.y)^2)
        if dist > bestDist then
            bestDist = dist
            bestRoom = room
        end
    end

    if not bestRoom then
        bestRoom = mapRooms[#mapRooms]
    end

    -- 在该房间中心放置 3×3 出口区域
    local centerC = math.floor(bestRoom.x + bestRoom.w / 2)
    local centerR = math.floor(bestRoom.y + bestRoom.h / 2)
    for dr = -1, 1 do
        for dc = -1, 1 do
            local rr = centerR + dr
            local cc = centerC + dc
            if rr >= 1 and rr <= MAP_ROWS and cc >= 1 and cc <= MAP_COLS then
                if mapData[rr][cc] == TILE_FLOOR or mapData[rr][cc] == TILE_CRATE then
                    mapData[rr][cc] = TILE_EXIT
                end
            end
        end
    end

    WM.exitX = (centerC - 0.5) * TILE_SIZE
    WM.exitY = (centerR - 0.5) * TILE_SIZE
    WM.exitReady = true
    print("Exit spawned at room center: col=" .. centerC .. " row=" .. centerR)
end

-- ============================================================================
-- 敌人生成
-- ============================================================================
function SpawnEnemies()
    enemies = {}
    WM.boss = nil

    -- 收集可用地板格(远离玩家出生点)
    local floorTiles = {}
    for r = 1, MAP_ROWS do
        for c = 1, MAP_COLS do
            if mapData[r][c] == TILE_FLOOR then
                local wx = (c - 0.5) * TILE_SIZE
                local wy = (r - 0.5) * TILE_SIZE
                local dist = math.sqrt((wx - player.x)^2 + (wy - player.y)^2)
                if dist > 250 then
                    table.insert(floorTiles, {c = c, r = r})
                end
            end
        end
    end

    -- 打乱顺序
    for i = #floorTiles, 2, -1 do
        local j = math.random(1, i)
        floorTiles[i], floorTiles[j] = floorTiles[j], floorTiles[i]
    end

    -- 波次参数决定敌人数量
    local wave = WM.GetCurrentWave()
    local numEnemies = WM.GetEnemyCount()
    local hpMult = WM.GetHpMult()
    local dmgMult = WM.GetDmgMult()
    local MIN_ENEMY_DIST = 100

    -- Boss波: 先生成Boss
    if wave and wave.type == "boss" and #floorTiles > 0 then
        -- 选择离玩家最远的位置给Boss
        local bestTile = floorTiles[1]
        local bestDist = 0
        for _, tile in ipairs(floorTiles) do
            local wx = (tile.c - 0.5) * TILE_SIZE
            local wy = (tile.r - 0.5) * TILE_SIZE
            local d = math.sqrt((wx - player.x)^2 + (wy - player.y)^2)
            if d > bestDist then
                bestDist = d
                bestTile = tile
            end
        end
        local bx = (bestTile.c - 0.5) * TILE_SIZE
        local by = (bestTile.r - 0.5) * TILE_SIZE
        local boss = WM.CreateBoss(bx, by)
        table.insert(enemies, boss)
    end

    local placed = {}

    for _, tile in ipairs(floorTiles) do
        if #placed >= numEnemies then break end

        local wx = (tile.c - 0.5) * TILE_SIZE
        local wy = (tile.r - 0.5) * TILE_SIZE

        -- 检查与已有敌人的间距
        local tooClose = false
        for _, pos in ipairs(placed) do
            local dx = wx - pos.x
            local dy = wy - pos.y
            if math.sqrt(dx * dx + dy * dy) < MIN_ENEMY_DIST then
                tooClose = true
                break
            end
        end

        -- 也不要离Boss太近
        if not tooClose and WM.boss then
            local dx = wx - WM.boss.x
            local dy = wy - WM.boss.y
            if math.sqrt(dx * dx + dy * dy) < 80 then
                tooClose = true
            end
        end

        if not tooClose then
            local typeKey = WM.RollEnemyType()
            local t = ENEMY_TYPES[typeKey]
            local enemy = {
                x = wx, y = wy,
                typeKey = typeKey,
                hp = math.floor(t.hp * hpMult),
                maxHp = math.floor(t.hp * hpMult),
                radius = t.radius,
                speed = t.speed,
                damage = math.floor(t.damage * dmgMult),
                sightRange = t.sightRange,
                attackRange = t.attackRange,
                attackRate = t.attackRate,
                bulletSpeed = t.bulletSpeed,
                color = {t.color[1], t.color[2], t.color[3]},
                state = "idle",
                angle = math.random() * math.pi * 2,
                fireTimer = 0,
                alertTimer = 0,
                patrolOriginX = wx,
                patrolOriginY = wy,
                patrolAngle = math.random() * math.pi * 2,
                patrolTimer = 0,
                hitFlashTimer = 0,
                -- 攻击模式相关
                attackPattern = t.attackPattern or "single",
                burstRemaining = 0,       -- burst: 剩余连发数
                burstTimer = 0,           -- burst: 连发间隔计时
                burstAngle = 0,           -- burst: 锁定的发射角度
                burstCount = t.burstCount or 3,
                burstInterval = t.burstInterval or 0.1,
                shotgunPellets = t.shotgunPellets or 4,
                shotgunSpread = t.shotgunSpread or 0.35,
                armor = t.armor or 0,     -- 伤害减免比例(0~1)
            }
            table.insert(enemies, enemy)
            table.insert(placed, {x = wx, y = wy})
        end
    end

    print("Wave " .. WM.currentWave .. ": Spawned " .. #enemies .. " enemies (hp×" .. hpMult .. " dmg×" .. dmgMult .. ")")
end

-- ============================================================================
-- 碰撞检测工具
-- ============================================================================
--- 点是否在墙内
local function IsWall(wx, wy)
    local c = math.floor(wx / TILE_SIZE) + 1
    local r = math.floor(wy / TILE_SIZE) + 1
    if r < 1 or r > MAP_ROWS or c < 1 or c > MAP_COLS then return true end
    return mapData[r][c] == TILE_WALL
end

--- 获取指定位置的瓦片类型
local function GetTile(wx, wy)
    local c = math.floor(wx / TILE_SIZE) + 1
    local r = math.floor(wy / TILE_SIZE) + 1
    if r < 1 or r > MAP_ROWS or c < 1 or c > MAP_COLS then return TILE_WALL end
    return mapData[r][c]
end

--- 圆与墙的碰撞修正
local function ResolveWallCollision(x, y, radius)
    local newX, newY = x, y

    -- 检查四个方向
    -- 左
    if IsWall(x - radius, y) then
        local wallRight = (math.floor((x - radius) / TILE_SIZE) + 1) * TILE_SIZE
        newX = math.max(newX, wallRight + radius)
    end
    -- 右
    if IsWall(x + radius, y) then
        local wallLeft = math.floor((x + radius) / TILE_SIZE) * TILE_SIZE
        newX = math.min(newX, wallLeft - radius)
    end
    -- 上
    if IsWall(x, y - radius) then
        local wallBottom = (math.floor((y - radius) / TILE_SIZE) + 1) * TILE_SIZE
        newY = math.max(newY, wallBottom + radius)
    end
    -- 下
    if IsWall(x, y + radius) then
        local wallTop = math.floor((y + radius) / TILE_SIZE) * TILE_SIZE
        newY = math.min(newY, wallTop - radius)
    end

    return newX, newY
end

--- 两圆碰撞
local function CircleCollision(x1, y1, r1, x2, y2, r2)
    local dx = x2 - x1
    local dy = y2 - y1
    local dist = math.sqrt(dx * dx + dy * dy)
    return dist < (r1 + r2)
end

--- 简单的线段与墙碰撞(Bresenham式采样)
local function LineHitsWall(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    local dist = math.sqrt(dx * dx + dy * dy)
    local steps = math.max(1, math.floor(dist / (TILE_SIZE * 0.5)))
    for i = 0, steps do
        local t = i / steps
        local px = x1 + dx * t
        local py = y1 + dy * t
        if IsWall(px, py) then return true end
    end
    return false
end

-- ============================================================================
-- 屏幕震动 / 命中停顿 工具
-- ============================================================================
local function TriggerShake(intensity, duration)
    shakeIntensity = math.max(shakeIntensity, intensity)
    shakeTimer = math.max(shakeTimer, duration)
end

local function TriggerHitstop(duration)
    hitstopTimer = math.max(hitstopTimer, duration)
end

local function UpdateShake(dt)
    if shakeTimer > 0 then
        shakeTimer = shakeTimer - dt
        local t = shakeTimer / 0.2  -- 归一化衰减
        local amp = shakeIntensity * math.max(0, t)
        shakeOffsetX = (math.random() * 2 - 1) * amp
        shakeOffsetY = (math.random() * 2 - 1) * amp
        if shakeTimer <= 0 then
            shakeIntensity = 0
            shakeOffsetX = 0
            shakeOffsetY = 0
        end
    end
end

-- ============================================================================
-- 输入处理
-- ============================================================================
function HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()

    if gameState == STATE_GAMEOVER or gameState == STATE_EXTRACTED or gameState == STATE_VICTORY then
        -- 点击重新开始
        RestartGame()
        return
    end

    if gameState ~= STATE_PLAYING then return end

    -- 奖励选择阶段: 点击确认
    if WM.phase == WM.PHASE_REWARD and button == MOUSEB_LEFT then
        HandleRewardClick()
        return
    end

    if not player.alive then return end

    -- 背包UI优先处理输入
    if InvUI.isOpen then
        local mx, my = ScreenToDesign(input:GetMousePosition().x, input:GetMousePosition().y)
        if InvUI.HandleMouseDown(mx, my, button) then
            return  -- 事件被背包UI消费
        end
    end

    if button == MOUSEB_LEFT then
        -- 出口/走出阶段禁止射击
        if WM.phase ~= WM.PHASE_EXIT_OPEN and WM.phase ~= WM.PHASE_WALKOUT then
            TryShoot()
        end
    end
end

function HandleMouseUp(eventType, eventData)
    local button = eventData["Button"]:GetInt()

    if InvUI.isOpen then
        local mx, my = ScreenToDesign(input:GetMousePosition().x, input:GetMousePosition().y)
        InvUI.HandleMouseUp(mx, my, button)
    end
end

-- 奖励点击处理
function HandleRewardClick()
    local wave = WM.GetCurrentWave()
    if not wave then return end

    if wave.rewardType == "supply" then
        -- 补给型: 自动全选
        WM.ApplyAllSupply(player)
    elseif wave.rewardType == "choice" then
        -- 三选一: 应用选中的奖励
        WM.ApplyReward(WM.selectedReward, player)
    end

    -- 开始过渡动画(fade_out → AdvanceWave → callback → fade_in)
    WM.StartTransition()
    WM.transitCallback = function()
        -- 此时 AdvanceWave 已执行, currentWave 已是新波次
        camZoom = 0.75  -- 恢复默认缩放
        GenerateMap()
        SpawnEnemies()
        local newWave = WM.GetCurrentWave()
        if newWave then
            waveAnnounceTimer = 3.0
            waveAnnounceText = "Wave " .. WM.currentWave .. " - " .. newWave.name
        end
    end
end

function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    -- 奖励选择阶段: 左右键/1-3数字选择
    if WM.phase == WM.PHASE_REWARD and gameState == STATE_PLAYING then
        local numChoices = #WM.rewardChoices
        if key == KEY_A or key == KEY_LEFT then
            WM.selectedReward = math.max(1, WM.selectedReward - 1)
            return
        elseif key == KEY_D or key == KEY_RIGHT then
            WM.selectedReward = math.min(numChoices, WM.selectedReward + 1)
            return
        elseif key == KEY_RETURN or key == KEY_SPACE then
            HandleRewardClick()
            return
        elseif key == KEY_1 and numChoices >= 1 then
            WM.selectedReward = 1; HandleRewardClick(); return
        elseif key == KEY_2 and numChoices >= 2 then
            WM.selectedReward = 2; HandleRewardClick(); return
        elseif key == KEY_3 and numChoices >= 3 then
            WM.selectedReward = 3; HandleRewardClick(); return
        end
    end

    -- Tab 开关背包
    if key == KEY_TAB and gameState == STATE_PLAYING and player.alive then
        InvUI.Toggle()
        if InvUI.isOpen then
            gameTimeScale = 0.15  -- 慢速不暂停
        else
            gameTimeScale = 1.0
        end
        return
    end

    -- 背包打开时, 优先处理背包按键
    if InvUI.isOpen then
        if InvUI.HandleKeyDown(key) then
            return
        end
    end

    if key == KEY_R and gameState == STATE_PLAYING then
        if not player.reloading and player.ammo < WEAPON.magSize and player.totalAmmo > 0 then
            player.reloading = true
            player.reloadTimer = WEAPON.reloadTime
            PlaySfx(sndReload, 0.5)
            print("Reloading...")
        end
    end

    if key == KEY_ESCAPE then
        -- 如果背包打开, 先关闭背包
        if InvUI.isOpen then
            InvUI.Close()
            gameTimeScale = 1.0
            return
        end
        if gameState == STATE_PLAYING then
            gameState = STATE_PAUSED
        elseif gameState == STATE_PAUSED then
            gameState = STATE_PLAYING
        end
    end
end

function TryShoot()
    if InvUI.isOpen then return end  -- 背包打开时禁止射击
    if player.reloading then return end
    if player.fireTimer > 0 then return end
    if player.ammo <= 0 then
        -- 自动换弹
        if player.totalAmmo > 0 then
            player.reloading = true
            local reloadSpeedBonus = Inv.GetStat("reloadSpeed", 0)
            player.reloadTimer = math.max(0.3, WEAPON.reloadTime - reloadSpeedBonus)
            PlaySfx(sndReload, 0.5)
        end
        return
    end

    -- 应用背包散布加成(负值=更精准)
    local spreadBonus = Inv.GetStat("spread", 0)
    local effectiveSpread = math.max(0, WEAPON.spread + spreadBonus)
    local spreadRad = math.rad(effectiveSpread) * (math.random() - 0.5)
    local angle = player.angle + spreadRad
    local bx = player.x + math.cos(angle) * (player.radius + 5)
    local by = player.y + math.sin(angle) * (player.radius + 5)

    -- 应用背包加成 + 波次奖励modifier
    local bonusDamage = Inv.GetStat("damage", 0) + WM.weaponMods.bonusDamage
    local bonusFireRate = Inv.GetStat("fireRate", 0) + WM.weaponMods.fireRateReduction

    -- 暴击判定
    local critChance = Inv.GetStat("critChance", 0)
    local isCrit = math.random(1, 100) <= critChance
    local finalDamage = WEAPON.damage + bonusDamage
    if isCrit then finalDamage = math.floor(finalDamage * 2) end

    -- 穿透次数(0=普通子弹击中即消失, >0=可穿透多个敌人)
    local pierceCount = math.floor(Inv.GetStat("pierce", 0))

    -- 状态效果属性(从背包汇总)
    local burnDmg = Inv.GetStat("burnDamage", 0)
    local burnComboMult = 1.0 + (Inv.GetStat("combo_burnDamagePercent", 0) / 100)
    burnDmg = math.floor(burnDmg * burnComboMult)
    local burnDur = 2.0 + Inv.GetStat("combo_burnDurationBonus", 0)

    local slowAmt = Inv.GetStat("slowAmount", 0) + Inv.GetStat("combo_slowAmountBonus", 0)

    local explRadius = Inv.GetStat("explosionRadius", 0)
    local explDamage = Inv.GetStat("explosionDamage", 0)
    local comboRadiusMult = 1.0 + (Inv.GetStat("combo_explosionRadiusPercent", 0) / 100)
    explRadius = math.floor(explRadius * comboRadiusMult)

    table.insert(bullets, {
        x = bx, y = by,
        vx = math.cos(angle) * WEAPON.bulletSpeed,
        vy = math.sin(angle) * WEAPON.bulletSpeed,
        damage = finalDamage,
        radius = WEAPON.bulletRadius,
        fromPlayer = true,
        life = 2.0,
        trail = {},
        isCrit = isCrit,
        pierce = pierceCount,
        hitEnemies = {},  -- 已穿透过的敌人(避免重复伤害)
        -- 状态效果
        burnDamage = burnDmg > 0 and burnDmg or nil,
        burnDuration = burnDmg > 0 and burnDur or nil,
        slowAmount = slowAmt > 0 and slowAmt or nil,
        slowDuration = slowAmt > 0 and 2.0 or nil,
        explosionRadius = explRadius > 0 and explRadius or nil,
        explosionDamage = explDamage > 0 and explDamage or nil,
    })

    player.ammo = player.ammo - 1
    player.fireTimer = math.max(0.05, WEAPON.fireRate - bonusFireRate)

    PlaySfx(sndShoot, 0.35)

    -- 射击后坐力震动(轻微)
    TriggerShake(1.5, 0.06)

    -- 枪口闪光粒子(火花)
    for j = 1, 8 do
        local pa = angle + (math.random() - 0.5) * 0.8
        local spd = 150 + math.random() * 200
        table.insert(particles, {
            x = bx, y = by,
            vx = math.cos(pa) * spd,
            vy = math.sin(pa) * spd,
            life = 0.1 + math.random() * 0.1,
            maxLife = 0.2,
            r = 255, g = 200 + math.random(55), b = 50 + math.random(100),
            size = 1.5 + math.random() * 3,
            glow = true,
        })
    end

    -- 枪口闪光圆(短暂亮光)
    table.insert(particles, {
        x = bx, y = by, vx = 0, vy = 0,
        life = 0.06, maxLife = 0.06,
        r = 255, g = 240, b = 200,
        size = 12, glow = true, drag = 1.0,
    })

    -- 弹壳抛出(向枪口侧方弹出, 带重力)
    local shellAngle = angle + math.pi * 0.5 + (math.random() - 0.5) * 0.4
    local shellSpd = 60 + math.random() * 40
    table.insert(particles, {
        x = player.x + math.cos(angle) * 6,
        y = player.y + math.sin(angle) * 6,
        vx = math.cos(shellAngle) * shellSpd,
        vy = math.sin(shellAngle) * shellSpd,
        life = 0.5, maxLife = 0.5,
        r = 200, g = 180, b = 80,
        size = 2.5, gravity = 200, drag = 0.98,
        isShell = true,
        rot = math.random() * math.pi * 2,
        rotSpeed = 10 + math.random() * 15,
    })
end

-- ============================================================================
-- 更新逻辑
-- ============================================================================
function HandleUpdate(eventType, eventData)
    if gameState ~= STATE_PLAYING then return end

    local rawDt = eventData["TimeStep"]:GetFloat()
    local dt = rawDt * gameTimeScale  -- 应用背包慢速
    gameTimeAcc = gameTimeAcc + rawDt  -- 累计时间(摇摆动画)
    local g = GetGraphics()
    screenW = g:GetWidth()
    screenH = g:GetHeight()

    -- 波次管理器更新(过渡动画等, 不受慢速影响)
    WM.Update(rawDt)

    -- 波次公告计时
    if waveAnnounceTimer > 0 then
        waveAnnounceTimer = waveAnnounceTimer - rawDt
    end

    -- 过渡中/奖励选择中: 只更新粒子和相机, 不更新战斗
    if WM.transitPhase ~= "none" then
        UpdateParticles(dt)
        UpdateShake(dt)
        UpdateCamera()
        return
    end

    -- 奖励阶段: 暂停战斗
    if WM.phase == WM.PHASE_REWARD then
        UpdateParticles(dt)
        UpdateCamera()
        return
    end

    -- 出口开放阶段: 允许玩家移动, 检测到达出口
    if WM.phase == WM.PHASE_EXIT_OPEN then
        -- 首次进入: 生成出口
        if not WM.exitReady then
            SpawnExit()
        end

        -- 玩家仍可移动和拾取
        UpdatePlayer(dt)
        UpdateParticles(dt)
        UpdateDamageNumbers(dt)
        UpdateCamera()

        -- 拾取掉落物(复用战斗中的逻辑)
        for i = #lootItems, 1, -1 do
            local item = lootItems[i]
            local pickupRadius = 10
            if item.type == "artifact" or item.type == "tablet" then
                pickupRadius = 20
            end
            if CircleCollision(player.x, player.y, player.radius + pickupRadius, item.x, item.y, 8) then
                if item.type == "ammo" then
                    player.totalAmmo = player.totalAmmo + item.amount
                elseif item.type == "health" then
                    local effectiveMaxHp = player.maxHp + Inv.GetStat("maxHp", 0)
                    player.hp = math.min(effectiveMaxHp, player.hp + item.amount)
                elseif item.type == "artifact" or item.type == "tablet" then
                    Inv.AddPendingItem(item.itemData)
                end
                table.remove(lootItems, i)
            end
        end

        -- 检测玩家到达出口(距离出口中心 < 40像素)
        local exitDist = math.sqrt((player.x - WM.exitX)^2 + (player.y - WM.exitY)^2)
        if exitDist < 40 then
            -- 开始走出动画
            WM.phase = WM.PHASE_WALKOUT
            WM.walkoutTimer = WM.walkoutDuration
            walkoutStartX = player.x
            walkoutStartY = player.y
            walkoutTargetX = WM.exitX
            walkoutTargetY = WM.exitY
            walkoutZoomStart = camZoom
            walkoutZoomEnd = math.min(1.0, camZoom + 0.15)
            PlaySfx(sndLevelClear, 0.6)
        end
        return
    end

    -- 走出动画阶段: 自动移动玩家, 禁止输入
    if WM.phase == WM.PHASE_WALKOUT then
        local progress = 1.0 - (WM.walkoutTimer / WM.walkoutDuration)
        progress = math.max(0, math.min(1, progress))
        -- ease-in-out
        local ease = progress < 0.5
            and (2 * progress * progress)
            or (1 - (-2 * progress + 2)^2 / 2)

        -- 插值玩家位置
        player.x = walkoutStartX + (walkoutTargetX - walkoutStartX) * ease
        player.y = walkoutStartY + (walkoutTargetY - walkoutStartY) * ease
        -- 玩家朝向出口
        player.angle = math.atan(walkoutTargetY - walkoutStartY, walkoutTargetX - walkoutStartX)
        -- 镜头微拉近
        camZoom = walkoutZoomStart + (walkoutZoomEnd - walkoutZoomStart) * ease

        -- 走出粒子特效
        if math.random() < 0.4 then
            table.insert(particles, {
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

        UpdateParticles(dt)
        UpdateCamera()
        return
    end

    -- 胜利阶段
    if WM.phase == WM.PHASE_VICTORY then
        gameState = STATE_VICTORY
        return
    end

    -- 清除展示阶段: 只更新粒子
    if WM.phase == WM.PHASE_CLEARED then
        UpdateParticles(dt)
        UpdateDamageNumbers(dt)
        UpdateCamera()
        return
    end

    -- 命中停顿: 冻结游戏逻辑(用真实dt计时)
    if hitstopTimer > 0 then
        hitstopTimer = hitstopTimer - rawDt
        UpdateShake(rawDt)
        return
    end

    -- 更新游戏时间(正计时)
    gameTime = gameTime + dt

    -- 动态难度调整
    WM.UpdateDifficulty(player.hp / (player.maxHp + Inv.GetStat("maxHp", 0)))

    UpdatePlayer(dt)
    UpdateBullets(dt)
    UpdateEnemies(dt)
    UpdateParticles(dt)
    UpdateDamageNumbers(dt)
    UpdateSearch(dt)
    UpdateShake(dt)
    UpdateCamera()

    -- Boss特殊行为
    if WM.phase == WM.PHASE_BOSS and WM.boss and WM.boss.hp > 0 then
        local summoned, chargeImpact, spinBullets = WM.UpdateBossBehavior(WM.boss, dt, player.x, player.y)
        if summoned then
            SpawnBossMinions(summoned.count)
        end
        -- 冲锋冲击波: 对玩家造成AOE伤害+击退
        if chargeImpact then
            local cdx = player.x - chargeImpact.x
            local cdy = player.y - chargeImpact.y
            local cdist = math.sqrt(cdx * cdx + cdy * cdy)
            if cdist < chargeImpact.radius and player.invincibleTimer <= 0 then
                player.hp = player.hp - chargeImpact.damage
                player.invincibleTimer = 0.5
                table.insert(damageNumbers, {
                    x = player.x, y = player.y - player.radius - 5,
                    text = tostring(chargeImpact.damage),
                    life = 0.8, maxLife = 0.8, vy = -40,
                    isPlayer = true,
                })
                if player.hp <= 0 then
                    player.hp = 0
                    player.alive = false
                    gameState = STATE_GAMEOVER
                end
            end
            -- 冲击波视觉(扩散环)
            for kp = 1, 20 do
                local pa = (kp / 20) * math.pi * 2
                local spd = chargeImpact.radius * 2.5
                table.insert(particles, {
                    x = chargeImpact.x, y = chargeImpact.y,
                    vx = math.cos(pa) * spd, vy = math.sin(pa) * spd,
                    life = 0.3, maxLife = 0.3,
                    r = 255, g = 80, b = 40,
                    size = 3 + math.random() * 2, glow = true,
                })
            end
            TriggerShake(5, 0.15)
        end
        -- 旋转弹幕: 生成子弹
        if spinBullets then
            for _, sb in ipairs(spinBullets) do
                table.insert(bullets, {
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

    -- 波次清除检测
    local aliveEnemies = #enemies
    if WM.CheckWaveCleared(aliveEnemies) then
        WM.OnWaveCleared()
        -- Boss波清除 → 全胜
        if WM.phase == WM.PHASE_VICTORY then
            gameState = STATE_VICTORY
        end
        PlaySfx(sndLevelClear, 0.6)
    end

    -- 持续射击(按住左键, 背包打开时禁止射击)
    if input:GetMouseButtonDown(MOUSEB_LEFT) and player.alive and not InvUI.isOpen then
        TryShoot()
    end

    -- 应用背包属性: 生命回复
    local hpRegen = Inv.GetStat("hpRegen", 0)
    if hpRegen > 0 and player.hp < player.maxHp + Inv.GetStat("maxHp", 0) then
        player.hp = math.min(player.maxHp + Inv.GetStat("maxHp", 0),
            player.hp + hpRegen * dt)
    end
end

-- Boss召唤小兵
function SpawnBossMinions(count)
    if not WM.boss then return end
    for i = 1, count do
        local angle = math.random() * math.pi * 2
        local dist = 60 + math.random() * 40
        local mx = WM.boss.x + math.cos(angle) * dist
        local my = WM.boss.y + math.sin(angle) * dist
        -- 确保不在墙里
        if not IsWall(mx, my) then
            local typeKey = math.random() > 0.5 and "rusher" or "patrol"
            local t = ENEMY_TYPES[typeKey]
            local enemy = {
                x = mx, y = my,
                typeKey = typeKey,
                hp = math.floor(t.hp * 0.6),  -- 召唤的小兵稍弱
                maxHp = math.floor(t.hp * 0.6),
                radius = t.radius,
                speed = t.speed,
                damage = t.damage,
                sightRange = t.sightRange,
                attackRange = t.attackRange,
                attackRate = t.attackRate,
                bulletSpeed = t.bulletSpeed,
                color = {t.color[1], t.color[2], t.color[3]},
                state = "chase",  -- 直接追击
                angle = math.atan(player.y - my, player.x - mx),
                fireTimer = 0,
                alertTimer = 5,
                patrolOriginX = mx,
                patrolOriginY = my,
                patrolAngle = 0,
                patrolTimer = 0,
                hitFlashTimer = 0,
            }
            table.insert(enemies, enemy)
            -- 召唤特效
            for k = 1, 8 do
                local pa = math.random() * math.pi * 2
                local spd = 40 + math.random() * 60
                table.insert(particles, {
                    x = mx, y = my,
                    vx = math.cos(pa) * spd,
                    vy = math.sin(pa) * spd,
                    life = 0.3 + math.random() * 0.2,
                    maxLife = 0.5,
                    r = 180, g = 40, b = 40,
                    size = 2 + math.random() * 2,
                    glow = true,
                })
            end
        end
    end
end

function UpdatePlayer(dt)
    if not player.alive then return end

    -- WASD 移动
    local dx, dy = 0, 0
    if input:GetKeyDown(KEY_W) then dy = dy - 1 end
    if input:GetKeyDown(KEY_S) then dy = dy + 1 end
    if input:GetKeyDown(KEY_A) then dx = dx - 1 end
    if input:GetKeyDown(KEY_D) then dx = dx + 1 end

    -- 归一化
    if dx ~= 0 or dy ~= 0 then
        local len = math.sqrt(dx * dx + dy * dy)
        dx = dx / len
        dy = dy / len
    end

    local effectiveSpeed = player.speed + Inv.GetStat("moveSpeed", 0)
    local newX = player.x + dx * effectiveSpeed * dt
    local newY = player.y + dy * effectiveSpeed * dt

    -- 墙碰撞修正
    newX, newY = ResolveWallCollision(newX, newY, player.radius)

    -- 边界限制
    newX = math.max(player.radius, math.min(MAP_W - player.radius, newX))
    newY = math.max(player.radius, math.min(MAP_H - player.radius, newY))

    -- 移动脚步声
    if dx ~= 0 or dy ~= 0 then
        footstepTimer = footstepTimer - dt
        if footstepTimer <= 0 then
            PlaySfx(sndFootstep, 0.25)
            footstepTimer = 0.3  -- 每0.3秒一步
        end
    else
        footstepTimer = 0  -- 停下时重置，起步立刻有声
    end

    -- 移动脚步尘土
    if dx ~= 0 or dy ~= 0 then
        if math.random() < 0.3 then  -- 30%概率每帧产生
            local dustAngle = math.random() * math.pi * 2
            table.insert(particles, {
                x = player.x + (math.random() - 0.5) * 8,
                y = player.y + (math.random() - 0.5) * 8,
                vx = -dx * 15 + math.cos(dustAngle) * 8,
                vy = -dy * 15 + math.sin(dustAngle) * 8,
                life = 0.3 + math.random() * 0.2,
                maxLife = 0.5,
                r = 140, g = 135, b = 120,
                size = 2 + math.random() * 2,
                drag = 0.92,
            })
        end
    end

    player.x = newX
    player.y = newY

    -- 鼠标方向 → 玩家朝向 (物理屏幕坐标 → 设计坐标 → 世界坐标)
    local mx = input:GetMousePosition().x
    local my = input:GetMousePosition().y
    local designMX, designMY = ScreenToDesign(mx, my)
    local worldMX = designMX / camZoom + camX
    local worldMY = designMY / camZoom + camY
    player.angle = math.atan(worldMY - player.y, worldMX - player.x)

    -- 射击冷却
    if player.fireTimer > 0 then
        player.fireTimer = player.fireTimer - dt
    end

    -- 换弹
    if player.reloading then
        player.reloadTimer = player.reloadTimer - dt
        if player.reloadTimer <= 0 then
            player.reloading = false
            PlaySfx(sndReloadDone, 0.5)
            local effectiveMag = WEAPON.magSize + WM.weaponMods.bonusMagSize + math.floor(Inv.GetStat("magSize", 0))
            local need = effectiveMag - player.ammo
            local give = math.min(need, player.totalAmmo)
            player.ammo = player.ammo + give
            player.totalAmmo = player.totalAmmo - give
        end
    end

    -- 无敌帧
    if player.invincibleTimer > 0 then
        player.invincibleTimer = player.invincibleTimer - dt
    end
end

function UpdateBullets(dt)
    for i = #bullets, 1, -1 do
        local b = bullets[i]

        -- 记录拖尾位置(移动前)
        if b.trail then
            table.insert(b.trail, 1, {x = b.x, y = b.y})
            if #b.trail > TRAIL_MAX then
                table.remove(b.trail, #b.trail)
            end
        end

        b.x = b.x + b.vx * dt
        b.y = b.y + b.vy * dt
        b.life = b.life - dt

        local remove = false

        -- 超出寿命
        if b.life <= 0 then
            remove = true
        end

        -- 撞墙
        if IsWall(b.x, b.y) then
            remove = true
            -- 墙壁火花(散射)
            for j = 1, 8 do
                local pa = math.random() * math.pi * 2
                local spd = 40 + math.random() * 80
                table.insert(particles, {
                    x = b.x, y = b.y,
                    vx = math.cos(pa) * spd,
                    vy = math.sin(pa) * spd,
                    life = 0.15 + math.random() * 0.15,
                    maxLife = 0.3,
                    r = 220, g = 200 + math.random(55), b = 120 + math.random(80),
                    size = 1 + math.random() * 2,
                    glow = true,
                })
            end
            -- 撞击闪光
            table.insert(particles, {
                x = b.x, y = b.y, vx = 0, vy = 0,
                life = 0.05, maxLife = 0.05,
                r = 255, g = 255, b = 220,
                size = 8, glow = true, drag = 1.0,
            })
            -- 碎屑(重力下落)
            for j = 1, 3 do
                local pa = math.random() * math.pi * 2
                table.insert(particles, {
                    x = b.x, y = b.y,
                    vx = math.cos(pa) * (20 + math.random() * 30),
                    vy = math.sin(pa) * (20 + math.random() * 30),
                    life = 0.4 + math.random() * 0.3,
                    maxLife = 0.7,
                    r = 100, g = 100, b = 90,
                    size = 1.5 + math.random(),
                    gravity = 150, drag = 0.97,
                })
            end
        end

        -- 玩家子弹 → 敌人
        if not remove and b.fromPlayer then
            for j = #enemies, 1, -1 do
                local e = enemies[j]
                -- 穿透子弹: 跳过已击中过的敌人
                local alreadyHit = false
                if b.hitEnemies then
                    for _, he in ipairs(b.hitEnemies) do
                        if he == e then alreadyHit = true; break end
                    end
                end
                if not alreadyHit and CircleCollision(b.x, b.y, b.radius, e.x, e.y, e.radius) then
                    -- 护甲减伤
                    local actualDmg = b.damage
                    if e.armor and e.armor > 0 then
                        actualDmg = math.max(1, math.floor(b.damage * (1 - e.armor)))
                    end
                    e.hp = e.hp - actualDmg
                    e.hitFlashTimer = 0.1
                    e.state = "chase"  -- 被攻击后追击

                    -- === 状态效果应用 ===
                    -- 燃烧: 持续伤害(DoT)
                    if b.burnDamage and b.burnDamage > 0 then
                        e.burnTimer = b.burnDuration or 2.0
                        e.burnDamage = b.burnDamage
                        e.burnTickTimer = e.burnTickTimer or 0
                    end
                    -- 减速: 降低移动速度
                    if b.slowAmount and b.slowAmount > 0 then
                        e.slowTimer = b.slowDuration or 2.0
                        e.slowPercent = math.min(0.8, (b.slowAmount / 100))  -- 最多减速80%
                    end
                    -- 爆炸: 对周围敌人造成AOE伤害
                    if b.explosionRadius and b.explosionRadius > 0 and b.explosionDamage and b.explosionDamage > 0 then
                        for k2 = #enemies, 1, -1 do
                            local e2 = enemies[k2]
                            if e2 ~= e then
                                local edx = e2.x - e.x
                                local edy = e2.y - e.y
                                local edist = math.sqrt(edx * edx + edy * edy)
                                if edist < b.explosionRadius then
                                    local aoeDmg = math.floor(b.explosionDamage * (1 - edist / b.explosionRadius))
                                    if e2.armor and e2.armor > 0 then
                                        aoeDmg = math.max(1, math.floor(aoeDmg * (1 - e2.armor)))
                                    end
                                    e2.hp = e2.hp - aoeDmg
                                    e2.hitFlashTimer = 0.1
                                    -- AOE伤害数字
                                    table.insert(damageNumbers, {
                                        x = e2.x, y = e2.y - e2.radius - 5,
                                        text = tostring(aoeDmg),
                                        life = 0.6, maxLife = 0.6, vy = -30,
                                        isAoe = true,
                                    })
                                    -- 燃烧传播(如有combo_burnSpread)
                                    if b.burnDamage and b.burnDamage > 0 and Inv.GetStat("combo_burnSpread", false) then
                                        e2.burnTimer = (b.burnDuration or 2.0) * 0.5
                                        e2.burnDamage = math.floor(b.burnDamage * 0.5)
                                        e2.burnTickTimer = e2.burnTickTimer or 0
                                    end
                                    -- AOE击杀判定
                                    if e2.hp <= 0 then
                                        killCount = killCount + 1
                                        WM.OnEnemyKilled()
                                        score = score + 50
                                        -- AOE击杀粒子
                                        for kp = 1, 10 do
                                            local pa2 = math.random() * math.pi * 2
                                            local spd2 = 60 + math.random() * 100
                                            table.insert(particles, {
                                                x = e2.x, y = e2.y,
                                                vx = math.cos(pa2) * spd2, vy = math.sin(pa2) * spd2,
                                                life = 0.3 + math.random() * 0.3, maxLife = 0.6,
                                                r = 255, g = 160 + math.random(60), b = 40 + math.random(60),
                                                size = 2 + math.random() * 2, glow = true,
                                            })
                                        end
                                        table.remove(enemies, k2)
                                    end
                                end
                            end
                        end
                        -- 爆炸冲击波视觉(用粒子环)
                        for kp = 1, 16 do
                            local pa = (kp / 16) * math.pi * 2
                            local spd = b.explosionRadius * 2
                            table.insert(particles, {
                                x = e.x, y = e.y,
                                vx = math.cos(pa) * spd, vy = math.sin(pa) * spd,
                                life = 0.25, maxLife = 0.25,
                                r = 255, g = 180, b = 60,
                                size = 3 + math.random() * 2, glow = true,
                            })
                        end
                        -- 爆炸中心闪光
                        table.insert(particles, {
                            x = e.x, y = e.y, vx = 0, vy = 0,
                            life = 0.12, maxLife = 0.12,
                            r = 255, g = 220, b = 100,
                            size = b.explosionRadius * 0.6, glow = true, drag = 1.0,
                        })
                    end

                    -- 穿透判定: pierce > 0 则不消除子弹
                    if b.pierce and b.pierce > 0 then
                        b.pierce = b.pierce - 1
                        if b.hitEnemies then table.insert(b.hitEnemies, e) end
                    else
                        remove = true
                    end

                    -- 伤害数字(暴击显示金色大字, 护甲显示灰色)
                    local dmgText = (b.isCrit and "暴击 " or "") .. tostring(actualDmg)
                    table.insert(damageNumbers, {
                        x = e.x, y = e.y - e.radius - 5,
                        text = dmgText,
                        life = b.isCrit and 1.2 or 0.8,
                        maxLife = b.isCrit and 1.2 or 0.8,
                        vy = -40,
                        isCrit = b.isCrit,
                        isArmored = (e.armor and e.armor > 0),
                    })

                    -- 血花粒子(沿弹道方向喷射)
                    local bulletDir = math.atan(b.vy, b.vx)
                    for k = 1, 8 do
                        local pa = bulletDir + (math.random() - 0.5) * 1.2
                        local spd = 60 + math.random() * 100
                        table.insert(particles, {
                            x = e.x, y = e.y,
                            vx = math.cos(pa) * spd,
                            vy = math.sin(pa) * spd,
                            life = 0.2 + math.random() * 0.2,
                            maxLife = 0.4,
                            r = 200 + math.random(55), g = 20 + math.random(40), b = 20 + math.random(30),
                            size = 1.5 + math.random() * 2.5,
                            gravity = 80, drag = 0.96,
                        })
                    end
                    -- 命中闪光
                    table.insert(particles, {
                        x = b.x, y = b.y, vx = 0, vy = 0,
                        life = 0.04, maxLife = 0.04,
                        r = 255, g = 200, b = 150,
                        size = 10, glow = true, drag = 1.0,
                    })

                    -- 命中震动 + 停顿 + 音效
                    TriggerShake(3, 0.1)
                    TriggerHitstop(HITSTOP_HIT)
                    PlaySfx(sndHit, 0.3)

                    if e.hp <= 0 then
                        -- 敌人死亡 — 更强震动 + 更长停顿 + 音效
                        TriggerShake(6, 0.15)
                        TriggerHitstop(HITSTOP_KILL)
                        PlaySfx(sndKill, 0.5)
                        PlaySfx(sndSplat, 0.4)
                        killCount = killCount + 1
                        WM.OnEnemyKilled()
                        score = score + 50
                        -- 掉落物(弹药/血包)
                        local lootRoll = math.random(1, 100)
                        if lootRoll <= 40 then
                            table.insert(lootItems, {
                                x = e.x, y = e.y,
                                type = "ammo", amount = math.random(3, 8),
                            })
                        elseif lootRoll <= 60 then
                            table.insert(lootItems, {
                                x = e.x, y = e.y,
                                type = "health", amount = math.random(15, 30),
                            })
                        end

                        -- 掉落圣物/石板(背包系统)
                        local invLootRoll = math.random(1, 100)
                        local dropRarityMax = 2  -- 默认最高掉绿色
                        if e.typeKey == "rusher" then dropRarityMax = 3 end  -- 冲锋者可掉蓝
                        if e.typeKey == "sentry" then dropRarityMax = 3 end  -- 哨兵可掉蓝

                        -- 掉落率受背包加成影响
                        local lootBonusPct = Inv.GetStat("lootBonus", 0)
                        local artifactChance = 8 + lootBonusPct * 0.3   -- 基础8%
                        local tabletChance = artifactChance + 5          -- 额外5%掉石板

                        if invLootRoll <= artifactChance then
                            -- 掉落圣物(掉到地面, 需要玩家走过去拾取)
                            local level = 1
                            if killCount > 10 then level = math.random(1, 2) end
                            if killCount > 25 then level = math.random(1, 3) end
                            local artifact = Inv.CreateRandomArtifact(dropRarityMax, level)
                            if artifact then
                                table.insert(lootItems, {
                                    x = e.x + math.random(-8, 8),
                                    y = e.y + math.random(-8, 8),
                                    type = "artifact",
                                    itemData = artifact,
                                })
                            end
                        elseif invLootRoll <= tabletChance then
                            -- 掉落石板(掉到地面)
                            local tablet = Inv.CreateRandomTablet()
                            if tablet then
                                table.insert(lootItems, {
                                    x = e.x + math.random(-8, 8),
                                    y = e.y + math.random(-8, 8),
                                    type = "tablet",
                                    itemData = tablet,
                                })
                            end
                        end
                        -- 击杀爆炸: 核心冲击波闪光
                        table.insert(particles, {
                            x = e.x, y = e.y, vx = 0, vy = 0,
                            life = 0.1, maxLife = 0.1,
                            r = 255, g = 255, b = 255,
                            size = 25, glow = true, drag = 1.0,
                        })
                        -- 击杀爆炸: 碎片喷射(带重力)
                        for k = 1, 16 do
                            local pa = math.random() * math.pi * 2
                            local spd = 80 + math.random() * 140
                            table.insert(particles, {
                                x = e.x, y = e.y,
                                vx = math.cos(pa) * spd,
                                vy = math.sin(pa) * spd,
                                life = 0.4 + math.random() * 0.4,
                                maxLife = 0.8,
                                r = e.color[1], g = e.color[2], b = e.color[3],
                                size = 2 + math.random() * 3,
                                gravity = 120, drag = 0.96,
                            })
                        end
                        -- 击杀爆炸: 火星(发光小粒子)
                        for k = 1, 10 do
                            local pa = math.random() * math.pi * 2
                            local spd = 100 + math.random() * 160
                            table.insert(particles, {
                                x = e.x, y = e.y,
                                vx = math.cos(pa) * spd,
                                vy = math.sin(pa) * spd,
                                life = 0.2 + math.random() * 0.3,
                                maxLife = 0.5,
                                r = 255, g = 180 + math.random(75), b = 50 + math.random(80),
                                size = 1 + math.random() * 1.5,
                                glow = true,
                            })
                        end
                        table.remove(enemies, j)
                    end
                    break
                end
            end
        end

        -- 敌人子弹 → 玩家
        if not remove and not b.fromPlayer and player.alive then
            if CircleCollision(b.x, b.y, b.radius, player.x, player.y, player.radius) then
                if player.invincibleTimer <= 0 then
                    player.hp = player.hp - b.damage
                    player.invincibleTimer = 0.3
                    -- 受伤闪红
                    table.insert(damageNumbers, {
                        x = player.x, y = player.y - player.radius - 5,
                        text = tostring(b.damage),
                        life = 0.8, maxLife = 0.8,
                        vy = -40,
                        isPlayer = true,
                    })
                    if player.hp <= 0 then
                        player.hp = 0
                        player.alive = false
                        gameState = STATE_GAMEOVER
                    end
                end
                remove = true
            end
        end

        if remove then
            table.remove(bullets, i)
        end
    end
end

function UpdateEnemies(dt)
    for _, e in ipairs(enemies) do
        local dx = player.x - e.x
        local dy = player.y - e.y
        local dist = math.sqrt(dx * dx + dy * dy)
        local canSee = dist < e.sightRange and not LineHitsWall(e.x, e.y, player.x, player.y)

        -- 状态机
        if not player.alive then
            e.state = "idle"
        elseif canSee then
            e.alertTimer = 3.0
            if dist < e.attackRange then
                e.state = "attack"
            else
                e.state = "chase"
            end
        else
            if e.alertTimer > 0 then
                e.alertTimer = e.alertTimer - dt
                e.state = "chase"
            else
                e.state = "idle"
            end
        end

        -- 朝向玩家(追击和攻击状态)
        if e.state == "chase" or e.state == "attack" then
            e.angle = math.atan(dy, dx)
        end

        -- === 状态效果 tick 处理 ===
        -- 减速效果
        local speedMult = 1.0
        if e.slowTimer and e.slowTimer > 0 then
            e.slowTimer = e.slowTimer - dt
            speedMult = 1.0 - (e.slowPercent or 0)
            if e.slowTimer <= 0 then
                e.slowTimer = nil
                e.slowPercent = nil
            end
        end
        -- 燃烧效果(DoT)
        if e.burnTimer and e.burnTimer > 0 then
            e.burnTimer = e.burnTimer - dt
            e.burnTickTimer = (e.burnTickTimer or 0) - dt
            if e.burnTickTimer <= 0 then
                e.burnTickTimer = 0.5  -- 每0.5秒跳一次伤害
                local bDmg = e.burnDamage or 0
                if bDmg > 0 then
                    e.hp = e.hp - bDmg
                    -- 燃烧伤害数字(橙色小字)
                    table.insert(damageNumbers, {
                        x = e.x + (math.random() - 0.5) * 10,
                        y = e.y - e.radius - 3,
                        text = tostring(bDmg),
                        life = 0.5, maxLife = 0.5, vy = -25,
                        isBurn = true,
                    })
                    -- 燃烧火星粒子
                    for kp = 1, 3 do
                        local pa = math.random() * math.pi * 2
                        table.insert(particles, {
                            x = e.x + (math.random() - 0.5) * e.radius,
                            y = e.y + (math.random() - 0.5) * e.radius,
                            vx = math.cos(pa) * (15 + math.random() * 20),
                            vy = -30 - math.random() * 40,
                            life = 0.3 + math.random() * 0.2, maxLife = 0.5,
                            r = 255, g = 120 + math.random(80), b = 20 + math.random(40),
                            size = 1.5 + math.random(), glow = true,
                        })
                    end
                    -- 燃烧致死
                    if e.hp <= 0 then
                        killCount = killCount + 1
                        WM.OnEnemyKilled()
                        score = score + 50
                    end
                end
            end
            if e.burnTimer <= 0 then
                e.burnTimer = nil
                e.burnDamage = nil
                e.burnTickTimer = nil
            end
        end

        -- 移动(Boss冲锋时跳过,由WM.UpdateBossBehavior控制)
        if e.state == "chase" and e.speed > 0 and not e.isCharging then
            local mx = math.cos(e.angle) * e.speed * speedMult * dt
            local my = math.sin(e.angle) * e.speed * speedMult * dt
            local nx = e.x + mx
            local ny = e.y + my
            nx, ny = ResolveWallCollision(nx, ny, e.radius)
            e.x = nx
            e.y = ny
        elseif e.state == "idle" and (e.typeKey == "patrol" or e.typeKey == "heavy") then
            -- 巡逻: 在出生点附近来回
            e.patrolTimer = e.patrolTimer + dt
            if e.patrolTimer > 3 then
                e.patrolAngle = e.patrolAngle + math.pi * (0.5 + math.random())
                e.patrolTimer = 0
            end
            local mx = math.cos(e.patrolAngle) * e.speed * 0.4 * speedMult * dt
            local my = math.sin(e.patrolAngle) * e.speed * 0.4 * speedMult * dt
            local nx = e.x + mx
            local ny = e.y + my
            -- 不离出生点太远
            local pdx = nx - e.patrolOriginX
            local pdy = ny - e.patrolOriginY
            if math.sqrt(pdx * pdx + pdy * pdy) < 100 then
                nx, ny = ResolveWallCollision(nx, ny, e.radius)
                e.x = nx
                e.y = ny
                e.angle = e.patrolAngle
            else
                e.patrolAngle = e.patrolAngle + math.pi
            end
        end

        -- burst 连发处理(已触发的连发必须完成,独立于攻击状态)
        if e.burstRemaining and e.burstRemaining > 0 then
            e.burstTimer = e.burstTimer - dt
            if e.burstTimer <= 0 then
                e.burstTimer = e.burstInterval
                e.burstRemaining = e.burstRemaining - 1
                -- 使用锁定角度发射(带微小抖动)
                local bAngle = e.burstAngle + (math.random() - 0.5) * 0.06
                local bx = e.x + math.cos(bAngle) * (e.radius + 4)
                local by = e.y + math.sin(bAngle) * (e.radius + 4)
                table.insert(bullets, {
                    x = bx, y = by,
                    vx = math.cos(bAngle) * e.bulletSpeed,
                    vy = math.sin(bAngle) * e.bulletSpeed,
                    damage = e.damage,
                    radius = 3,
                    fromPlayer = false,
                    life = 2.0,
                    trail = {},
                })
            end
        end

        -- 攻击
        if e.state == "attack" then
            e.fireTimer = e.fireTimer - dt
            if e.fireTimer <= 0 and (not e.burstRemaining or e.burstRemaining <= 0) then
                e.fireTimer = e.attackRate

                local pattern = e.attackPattern or "single"

                if pattern == "single" then
                    -- 单发: 一颗子弹+轻微散布
                    local bAngle = e.angle + (math.random() - 0.5) * 0.15
                    local bx = e.x + math.cos(bAngle) * (e.radius + 4)
                    local by = e.y + math.sin(bAngle) * (e.radius + 4)
                    table.insert(bullets, {
                        x = bx, y = by,
                        vx = math.cos(bAngle) * e.bulletSpeed,
                        vy = math.sin(bAngle) * e.bulletSpeed,
                        damage = e.damage,
                        radius = 3,
                        fromPlayer = false,
                        life = 2.0,
                        trail = {},
                    })

                elseif pattern == "burst" then
                    -- 三连发: 立即发射第一颗,后续通过 burstRemaining 计时
                    e.burstAngle = e.angle
                    e.burstRemaining = e.burstCount - 1
                    e.burstTimer = e.burstInterval
                    -- 第一颗立即发射
                    local bAngle = e.burstAngle + (math.random() - 0.5) * 0.06
                    local bx = e.x + math.cos(bAngle) * (e.radius + 4)
                    local by = e.y + math.sin(bAngle) * (e.radius + 4)
                    table.insert(bullets, {
                        x = bx, y = by,
                        vx = math.cos(bAngle) * e.bulletSpeed,
                        vy = math.sin(bAngle) * e.bulletSpeed,
                        damage = e.damage,
                        radius = 3,
                        fromPlayer = false,
                        life = 2.0,
                        trail = {},
                    })

                elseif pattern == "shotgun" then
                    -- 散弹: 多颗弹丸扇形展开
                    local pellets = e.shotgunPellets
                    local spread = e.shotgunSpread
                    for p = 1, pellets do
                        local frac = (p - 1) / math.max(1, pellets - 1) -- 0~1
                        local bAngle = e.angle - spread + frac * spread * 2
                        bAngle = bAngle + (math.random() - 0.5) * 0.08
                        local bx = e.x + math.cos(bAngle) * (e.radius + 4)
                        local by = e.y + math.sin(bAngle) * (e.radius + 4)
                        table.insert(bullets, {
                            x = bx, y = by,
                            vx = math.cos(bAngle) * e.bulletSpeed,
                            vy = math.sin(bAngle) * e.bulletSpeed,
                            damage = e.damage,
                            radius = 2.5,
                            fromPlayer = false,
                            life = 1.2,  -- 散弹射程较短
                            trail = {},
                        })
                    end

                elseif pattern == "melee" then
                    -- 近战攻击
                    if dist < e.attackRange + player.radius and player.invincibleTimer <= 0 then
                        player.hp = player.hp - e.damage
                        player.invincibleTimer = 0.5
                        table.insert(damageNumbers, {
                            x = player.x, y = player.y - player.radius - 5,
                            text = tostring(e.damage),
                            life = 0.8, maxLife = 0.8,
                            vy = -40,
                            isPlayer = true,
                        })
                        if player.hp <= 0 then
                            player.hp = 0
                            player.alive = false
                            gameState = STATE_GAMEOVER
                        end
                    end
                end
            end
        end

        -- 受击闪烁
        if e.hitFlashTimer > 0 then
            e.hitFlashTimer = e.hitFlashTimer - dt
        end
    end

    -- 清除燃烧致死的敌人(反向遍历安全删除)
    for i = #enemies, 1, -1 do
        if enemies[i].hp <= 0 then
            local ed = enemies[i]
            -- 死亡粒子
            for kp = 1, 12 do
                local pa = math.random() * math.pi * 2
                local spd = 60 + math.random() * 100
                table.insert(particles, {
                    x = ed.x, y = ed.y,
                    vx = math.cos(pa) * spd, vy = math.sin(pa) * spd,
                    life = 0.3 + math.random() * 0.3, maxLife = 0.6,
                    r = ed.color[1], g = ed.color[2], b = ed.color[3],
                    size = 2 + math.random() * 2, gravity = 100, drag = 0.96,
                })
            end
            table.remove(enemies, i)
        end
    end
end

function UpdateParticles(dt)
    for i = #particles, 1, -1 do
        local p = particles[i]
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        -- 可选重力
        if p.gravity then
            p.vy = p.vy + p.gravity * dt
        end
        -- 阻力
        local drag = p.drag or 0.95
        p.vx = p.vx * drag
        p.vy = p.vy * drag
        -- 可选旋转
        if p.rot then
            p.rot = p.rot + (p.rotSpeed or 0) * dt
        end
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(particles, i)
        end
    end
end

function UpdateDamageNumbers(dt)
    for i = #damageNumbers, 1, -1 do
        local d = damageNumbers[i]
        d.y = d.y + d.vy * dt
        d.life = d.life - dt
        if d.life <= 0 then
            table.remove(damageNumbers, i)
        end
    end
end

function UpdateSearch(dt)
    -- 检测玩家是否在箱子附近且按E
    if searchingCrate then
        searchingCrate.timer = searchingCrate.timer - dt
        -- 检查是否还在范围内
        local cx = (searchingCrate.col - 0.5) * TILE_SIZE
        local cy = (searchingCrate.row - 0.5) * TILE_SIZE
        local dist = math.sqrt((player.x - cx)^2 + (player.y - cy)^2)
        if dist > TILE_SIZE * 1.5 or not input:GetKeyDown(KEY_E) then
            searchingCrate = nil
            return
        end
        if searchingCrate.timer <= 0 then
            -- 搜刮完成
            mapData[searchingCrate.row][searchingCrate.col] = TILE_FLOOR
            -- 随机掉落
            local roll = math.random(1, 100)
            if roll <= 50 then
                table.insert(lootItems, {x = cx, y = cy, type = "ammo", amount = math.random(5, 15)})
            else
                table.insert(lootItems, {x = cx, y = cy, type = "health", amount = math.random(20, 40)})
            end
            score = score + 20
            searchingCrate = nil
        end
    else
        -- 检测是否按E开始搜刮
        if input:GetKeyDown(KEY_E) and player.alive then
            local pc = math.floor(player.x / TILE_SIZE) + 1
            local pr = math.floor(player.y / TILE_SIZE) + 1
            -- 检查周围格子
            for dr = -1, 1 do
                for dc = -1, 1 do
                    local rr = pr + dr
                    local cc = pc + dc
                    if rr >= 1 and rr <= MAP_ROWS and cc >= 1 and cc <= MAP_COLS then
                        if mapData[rr][cc] == TILE_CRATE then
                            searchingCrate = {col = cc, row = rr, timer = SEARCH_TIME}
                            break
                        end
                    end
                end
                if searchingCrate then break end
            end
        end
    end

    -- 拾取掉落物(自动)
    for i = #lootItems, 1, -1 do
        local item = lootItems[i]
        local pickupRadius = 10
        if item.type == "artifact" or item.type == "tablet" then
            pickupRadius = 20  -- 圣物/石板拾取范围更大
        end
        if CircleCollision(player.x, player.y, player.radius + pickupRadius, item.x, item.y, 8) then
            if item.type == "ammo" then
                player.totalAmmo = player.totalAmmo + item.amount
                table.insert(damageNumbers, {
                    x = item.x, y = item.y - 10,
                    text = "+" .. item.amount .. " 弹药",
                    life = 1.0, maxLife = 1.0,
                    vy = -30,
                })
            elseif item.type == "health" then
                local effectiveMaxHp = player.maxHp + Inv.GetStat("maxHp", 0)
                player.hp = math.min(effectiveMaxHp, player.hp + item.amount)
                table.insert(damageNumbers, {
                    x = item.x, y = item.y - 10,
                    text = "+" .. item.amount .. " HP",
                    life = 1.0, maxLife = 1.0,
                    vy = -30,
                })
            elseif item.type == "artifact" or item.type == "tablet" then
                -- 圣物/石板拾取 → 进入背包待放入列表
                Inv.AddPendingItem(item.itemData)
                local rarity = item.itemData.rarity or 1
                local rarityCol = InvData.RARITY_COLORS[rarity] or {200, 200, 200}
                table.insert(damageNumbers, {
                    x = item.x, y = item.y - 10,
                    text = "拾取: " .. item.itemData.name,
                    life = 1.5, maxLife = 1.5,
                    vy = -25,
                    r = rarityCol[1], g = rarityCol[2], b = rarityCol[3],
                })
            end
            table.remove(lootItems, i)
        end
    end
end

function UpdateCamera()
    -- 缩放后的可见区域(世界坐标尺寸)
    local viewW = DESIGN_W / camZoom
    local viewH = DESIGN_H / camZoom
    -- 相机跟随玩家(居中)
    camX = player.x - viewW / 2
    camY = player.y - viewH / 2
    -- 限制在地图范围内
    camX = math.max(0, math.min(MAP_W - viewW, camX))
    camY = math.max(0, math.min(MAP_H - viewH, camY))
end

function RestartGame()
    player.x = 0
    player.y = 0
    player.hp = 100
    player.maxHp = 100
    player.ammo = 12
    player.totalAmmo = 60
    player.alive = true
    player.reloading = false
    player.reloadTimer = 0
    player.fireTimer = 0
    player.invincibleTimer = 0

    bullets = {}
    enemies = {}
    lootItems = {}
    particles = {}
    damageNumbers = {}
    searchingCrate = nil

    gameTime = 0
    score = 0
    killCount = 0
    gameState = STATE_PLAYING
    waveAnnounceTimer = 0

    -- 重置背包
    Inv.Init()
    InvUI.Close()
    gameTimeScale = 1.0
    -- 给初始圣物
    local starterArtifact = Inv.CreateArtifact("a_bullet_core", 1)
    if starterArtifact then
        Inv.AddPendingItem(starterArtifact)
    end

    -- 重置波次管理器
    WM.Init()
    GenerateMap()
    SpawnEnemies()

    -- 首波公告
    local w1 = WM.GetCurrentWave()
    waveAnnounceTimer = 3.0
    waveAnnounceText = "Wave 1 - " .. (w1 and w1.name or "")
end

-- ============================================================================
-- NanoVG 渲染
-- ============================================================================
function HandleNanoVGRender(eventType, eventData)
    if vg == nil then return end

    local g = GetGraphics()
    screenW = g:GetWidth()
    screenH = g:GetHeight()

    -- 计算设计分辨率缩放 (SHOW_ALL: 等比缩放, 完整显示)
    local scaleX = screenW / DESIGN_W
    local scaleY = screenH / DESIGN_H
    renderScale = math.min(scaleX, scaleY)
    renderOffsetX = (screenW - DESIGN_W * renderScale) / 2
    renderOffsetY = (screenH - DESIGN_H * renderScale) / 2

    nvgBeginFrame(vg, screenW, screenH, 1.0)

    -- 用深色森林填充整个屏幕，防止非16:9屏幕出现黑边
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, screenH)
    nvgFillColor(vg, nvgRGBA(20, 35, 15, 255))
    nvgFill(vg)

    -- 世界空间 (设计分辨率缩放 + 相机缩放 + 相机偏移 + 震动)
    nvgSave(vg)
    nvgTranslate(vg, renderOffsetX, renderOffsetY)
    nvgScale(vg, renderScale, renderScale)
    nvgScale(vg, camZoom, camZoom)
    nvgTranslate(vg, -camX + shakeOffsetX, -camY + shakeOffsetY)

    -- 绘制地图
    DrawMap(DESIGN_W, DESIGN_H)

    -- 绘制掉落物
    DrawLootItems()

    -- 绘制敌人
    DrawEnemies()

    -- 绘制子弹
    DrawBullets()

    -- 绘制玩家
    DrawPlayer()

    -- 绘制粒子
    DrawParticles()

    -- 绘制伤害数字
    DrawDamageNumbers()

    -- 绘制战争迷雾
    DrawFogOfWar(DESIGN_W, DESIGN_H)

    -- 绘制搜刮进度
    DrawSearchProgress()

    -- 出口光柱特效 (世界空间)
    if (WM.phase == WM.PHASE_EXIT_OPEN or WM.phase == WM.PHASE_WALKOUT) and WM.exitReady then
        local t = GetTime():GetElapsedTime()
        local pulse = 0.5 + 0.5 * math.sin(t * 3)
        local beamAlpha = math.floor(40 + 30 * pulse)

        -- 向上的光柱(渐变消失)
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

        -- 出口中心光环
        local ringRadius = TILE_SIZE * 1.5 + 4 * math.sin(t * 2)
        nvgBeginPath(vg)
        nvgCircle(vg, WM.exitX, WM.exitY, ringRadius)
        nvgStrokeColor(vg, nvgRGBA(80, 255, 120, math.floor(100 * pulse)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        -- "出口"文字(世界空间)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(80, 255, 120, math.floor(200 * pulse)))
        nvgText(vg, WM.exitX, WM.exitY - TILE_SIZE * 1.8, "出口", nil)
    end

    nvgRestore(vg)

    -- 受伤红色闪屏(无敌帧期间)
    if player.invincibleTimer > 0 then
        local flashAlpha = math.floor(player.invincibleTimer / 0.3 * 80)
        flashAlpha = math.max(0, math.min(80, flashAlpha))
        nvgSave(vg)
        nvgTranslate(vg, renderOffsetX, renderOffsetY)
        nvgScale(vg, renderScale, renderScale)
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
        nvgTranslate(vg, renderOffsetX, renderOffsetY)
        nvgScale(vg, renderScale, renderScale)
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
    nvgTranslate(vg, renderOffsetX, renderOffsetY)
    nvgScale(vg, renderScale, renderScale)
    DrawHUD(DESIGN_W, DESIGN_H)
    nvgRestore(vg)

    -- 背包UI (设计分辨率空间)
    if InvUI.isOpen then
        local mx, my = ScreenToDesign(input:GetMousePosition().x, input:GetMousePosition().y)
        nvgSave(vg)
        nvgTranslate(vg, renderOffsetX, renderOffsetY)
        nvgScale(vg, renderScale, renderScale)
        InvUI.Draw(vg, DESIGN_W, DESIGN_H, mx, my)
        nvgRestore(vg)
    end

    -- 波次清除公告
    if WM.phase == WM.PHASE_CLEARED then
        nvgSave(vg)
        nvgTranslate(vg, renderOffsetX, renderOffsetY)
        nvgScale(vg, renderScale, renderScale)
        DrawWaveCleared(DESIGN_W, DESIGN_H)
        nvgRestore(vg)
    end

    -- 出口方向指示器 (出口阶段 + 走出动画)
    if WM.phase == WM.PHASE_EXIT_OPEN or WM.phase == WM.PHASE_WALKOUT then
        nvgSave(vg)
        nvgTranslate(vg, renderOffsetX, renderOffsetY)
        nvgScale(vg, renderScale, renderScale)
        DrawExitIndicator(DESIGN_W, DESIGN_H)
        nvgRestore(vg)
    end

    -- 奖励选择界面
    if WM.phase == WM.PHASE_REWARD then
        nvgSave(vg)
        nvgTranslate(vg, renderOffsetX, renderOffsetY)
        nvgScale(vg, renderScale, renderScale)
        DrawRewardScreen(DESIGN_W, DESIGN_H)
        nvgRestore(vg)
    end

    -- 波次开始公告
    if waveAnnounceTimer > 0 and WM.phase ~= WM.PHASE_REWARD and WM.phase ~= WM.PHASE_CLEARED then
        nvgSave(vg)
        nvgTranslate(vg, renderOffsetX, renderOffsetY)
        nvgScale(vg, renderScale, renderScale)
        DrawWaveAnnounce(DESIGN_W, DESIGN_H)
        nvgRestore(vg)
    end

    -- Boss血条(屏幕顶部)
    if WM.phase == WM.PHASE_BOSS and WM.boss and WM.boss.hp > 0 then
        nvgSave(vg)
        nvgTranslate(vg, renderOffsetX, renderOffsetY)
        nvgScale(vg, renderScale, renderScale)
        DrawBossHPBar(DESIGN_W, DESIGN_H)
        nvgRestore(vg)
    end

    -- 过渡遮罩(淡入淡出)
    if WM.transitAlpha > 0 then
        nvgSave(vg)
        nvgTranslate(vg, renderOffsetX, renderOffsetY)
        nvgScale(vg, renderScale, renderScale)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DESIGN_W, DESIGN_H)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(math.min(255, WM.transitAlpha))))
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- 游戏结束/胜利画面
    if gameState == STATE_GAMEOVER or gameState == STATE_VICTORY then
        nvgSave(vg)
        nvgTranslate(vg, renderOffsetX, renderOffsetY)
        nvgScale(vg, renderScale, renderScale)
        DrawEndScreen(DESIGN_W, DESIGN_H)
        nvgRestore(vg)
    end

    nvgEndFrame(vg)
end

-- ============================================================================
-- 绘制函数
-- ============================================================================
--- 辅助: 用瓦片图片填充一个格子
local function DrawTileImage(tileImg, x, y)
    local paint = nvgImagePattern(vg, x, y, TILE_SIZE, TILE_SIZE, 0, tileImg, 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, TILE_SIZE, TILE_SIZE)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

function DrawMap(viewW, viewH)
    -- 缩放后的世界可见区域
    local zoomViewW = viewW / camZoom
    local zoomViewH = viewH / camZoom
    -- 计算 SHOW_ALL 额外可见区域（非16:9屏幕会露出设计分辨率之外的内容）
    local extraW = (renderOffsetX or 0) / ((renderScale or 1) * camZoom)
    local extraH = (renderOffsetY or 0) / ((renderScale or 1) * camZoom)

    -- 先用深色森林背景填充整个可见区域，防止黑边
    nvgBeginPath(vg)
    nvgRect(vg, camX - extraW - 1, camY - extraH - 1, zoomViewW + extraW * 2 + 2, zoomViewH + extraH * 2 + 2)
    nvgFillColor(vg, nvgRGBA(20, 35, 15, 255))
    nvgFill(vg)

    -- 扩展绘制范围覆盖额外可见区域(使用缩放后的世界尺寸)
    local startCol = math.max(1, math.floor((camX - extraW) / TILE_SIZE))
    local endCol = math.min(MAP_COLS, math.ceil((camX + zoomViewW + extraW) / TILE_SIZE) + 1)
    local startRow = math.max(1, math.floor((camY - extraH) / TILE_SIZE))
    local endRow = math.min(MAP_ROWS, math.ceil((camY + zoomViewH + extraH) / TILE_SIZE) + 1)

    for r = startRow, endRow do
        for c = startCol, endCol do
            local tile = mapData[r][c]
            local x = (c - 1) * TILE_SIZE
            local y = (r - 1) * TILE_SIZE

            if tile == TILE_WALL then
                -- 墙壁/森林: 三层渐变 edge(紧邻道路) -> forest(间隔一格) -> dark(深处)
                local hash4 = ((r * 7 + c * 13) % 4) + 1
                local hash8 = ((r * 7 + c * 13) % 8) + 1
                -- 检查是否直接相邻道路(上下左右)
                local adjacentFloor = false
                local dirs4 = {{-1,0},{1,0},{0,-1},{0,1}}
                for _, d in ipairs(dirs4) do
                    local nr, nc = r + d[1], c + d[2]
                    if nr >= 1 and nr <= MAP_ROWS and nc >= 1 and nc <= MAP_COLS then
                        if mapData[nr][nc] == TILE_FLOOR or mapData[nr][nc] == TILE_CRATE or mapData[nr][nc] == TILE_EXIT then
                            adjacentFloor = true
                            break
                        end
                    end
                end
                if adjacentFloor then
                    -- 紧邻道路: 使用edge过渡tile
                    DrawTileImage(imgEdgeTiles[hash8], x, y)
                else
                    -- 检查8方向是否靠近道路(对角线也算)
                    local nearFloor = false
                    for dr = -1, 1 do
                        for dc = -1, 1 do
                            local nr, nc = r + dr, c + dc
                            if nr >= 1 and nr <= MAP_ROWS and nc >= 1 and nc <= MAP_COLS then
                                if mapData[nr][nc] == TILE_FLOOR or mapData[nr][nc] == TILE_CRATE or mapData[nr][nc] == TILE_EXIT then
                                    nearFloor = true
                                end
                            end
                        end
                    end
                    if nearFloor then
                        -- 对角相邻道路: 使用forest浅森林
                        DrawTileImage(imgForestTiles[hash4], x, y)
                    else
                        -- 远离道路: 使用dark深森林
                        DrawTileImage(imgDarkTiles[hash4], x, y)
                    end
                end
            elseif tile == TILE_FLOOR then
                -- 地板: 用棕黄色土路瓦片, 交替使用不同变体
                local hash = ((r * 7 + c * 13) % 4) + 1
                DrawTileImage(imgFloorTiles[hash], x, y)
            elseif tile == TILE_CRATE then
                -- 箱子: 先画地板底色, 再画箱子图标
                local hash = ((r * 7 + c * 13) % 4) + 1
                DrawTileImage(imgFloorTiles[hash], x, y)
                -- 箱子图标
                nvgBeginPath(vg)
                local cx = x + TILE_SIZE * 0.15
                local cy = y + TILE_SIZE * 0.15
                local cw = TILE_SIZE * 0.7
                local ch = TILE_SIZE * 0.7
                nvgRoundedRect(vg, cx, cy, cw, ch, 3)
                nvgFillColor(vg, nvgRGBA(160, 120, 60, 255))
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(120, 90, 40, 255))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)
            elseif tile == TILE_EXIT then
                -- 撤离点: 先画地板, 再叠加闪烁绿色半透明层
                local hash = ((r * 7 + c * 13) % 4) + 1
                DrawTileImage(imgFloorTiles[hash], x, y)
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

--- 绘制纯白描边(用白色剪影图片在8个方向偏移绘制, 形成贴合轮廓的白色描边)
local function DrawWhiteOutline(whiteImg, halfSize, imgSize)
    local offDist = 1.5  -- 描边宽度(像素)
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

function DrawPlayer()
    if not player.alive then return end

    local px, py = player.x, player.y
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
        wobble = math.sin(gameTimeAcc * 8) * 0.15  -- 左右摇摆 ±0.15 弧度(约8.6度)
    end

    -- 绘制角色图片
    local imgSize = r * 2.8  -- 图片绘制尺寸(略大于碰撞圆)
    local halfSize = imgSize / 2

    nvgSave(vg)
    nvgTranslate(vg, px, py)
    nvgRotate(vg, wobble)
    nvgGlobalAlpha(vg, alpha / 255)

    if imgPlayer >= 0 then
        -- 根据朝向水平翻转(角色面朝鼠标方向)
        local facingRight = (math.cos(player.angle) >= 0)
        if facingRight then
            nvgScale(vg, -1, 1)
        end

        -- 先绘制纯白描边
        DrawWhiteOutline(imgPlayerWhite, halfSize, imgSize)

        -- 再绘制角色本体
        local paint = nvgImagePattern(vg, -halfSize, -halfSize, imgSize, imgSize, 0, imgPlayer, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, -halfSize, -halfSize, imgSize, imgSize)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    else
        -- 备用：纯色圆形
        nvgBeginPath(vg)
        nvgCircle(vg, 0, 0, r)
        nvgFillColor(vg, nvgRGBA(60, 180, 80, 255))
        nvgFill(vg)
    end

    nvgRestore(vg)

    -- 换弹环形进度条（世界坐标，不受角色旋转影响）
    if player.reloading then
        local progress = 1.0 - (player.reloadTimer / WEAPON.reloadTime)
        progress = math.max(0, math.min(1, progress))

        local ringRadius = 6
        local ringY = py - r - 10  -- 头顶上方
        local lineWidth = 3
        local startAngle = -math.pi / 2  -- 从12点方向开始
        local endAngle = startAngle + progress * math.pi * 2

        -- 底圈（暗色）
        nvgBeginPath(vg)
        nvgArc(vg, px, ringY, ringRadius, 0, math.pi * 2, NVG_CW)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 40))
        nvgStrokeWidth(vg, lineWidth)
        nvgStroke(vg)

        -- 进度弧（亮色）
        if progress > 0.01 then
            nvgBeginPath(vg)
            nvgArc(vg, px, ringY, ringRadius, startAngle, endAngle, NVG_CW)
            nvgStrokeColor(vg, nvgRGBA(100, 220, 255, 230))
            nvgStrokeWidth(vg, lineWidth)
            nvgLineCap(vg, NVG_ROUND)
            nvgStroke(vg)
        end
    end
end

function DrawEnemies()
    for i, e in ipairs(enemies) do
        local alpha = 255
        local isBoss = (e.typeKey == "boss")

        if e.hitFlashTimer > 0 then
            alpha = 255
            -- 受击闪白光晕
            nvgBeginPath(vg)
            nvgCircle(vg, e.x, e.y, e.radius + 2)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 120))
            nvgFill(vg)
        end

        -- Boss专属: 外圈光环
        if isBoss then
            local glowPulse = math.sin(gameTimeAcc * 3) * 0.3 + 0.7
            local glowR = e.radius + 6 + math.sin(gameTimeAcc * 5) * 2
            nvgBeginPath(vg)
            nvgCircle(vg, e.x, e.y, glowR)
            nvgStrokeColor(vg, nvgRGBA(255, 60, 30, math.floor(120 * glowPulse)))
            nvgStrokeWidth(vg, 3)
            nvgStroke(vg)

            -- Boss冲刺时的拖影
            if e.isCharging then
                nvgBeginPath(vg)
                nvgCircle(vg, e.x, e.y, e.radius + 4)
                nvgFillColor(vg, nvgRGBA(255, 100, 40, 80))
                nvgFill(vg)
            end

            -- Boss护盾(金色六边形闪烁)
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

            -- Boss旋转弹幕蓄力(紫色旋涡)
            if e.isSpinning then
                local spinVis = math.sin(gameTimeAcc * 10) * 0.3 + 0.7
                nvgBeginPath(vg)
                nvgCircle(vg, e.x, e.y, e.radius + 8)
                nvgStrokeColor(vg, nvgRGBA(180, 60, 255, math.floor(100 * spinVis)))
                nvgStrokeWidth(vg, 2)
                nvgStroke(vg)
            end
        end

        -- 重装兵专属: 护甲光环(灰蓝色金属质感)
        if e.typeKey == "heavy" then
            local armorPulse = math.sin(gameTimeAcc * 2 + i * 0.5) * 0.2 + 0.8
            -- 外圈护甲环
            nvgBeginPath(vg)
            nvgCircle(vg, e.x, e.y, e.radius + 3)
            nvgStrokeColor(vg, nvgRGBA(140, 160, 200, math.floor(100 * armorPulse)))
            nvgStrokeWidth(vg, 2.5)
            nvgStroke(vg)
            -- 内部金属光泽
            nvgBeginPath(vg)
            nvgCircle(vg, e.x, e.y, e.radius + 1)
            nvgFillColor(vg, nvgRGBA(100, 120, 160, math.floor(30 * armorPulse)))
            nvgFill(vg)
        end

        -- 敌人摇摆动画: 移动中的敌人左右轻摇, 每个敌人相位不同
        local eMoving = (e.state == "chase" or e.state == "alert" or (e.state == "idle" and e.speed > 0))
        local eWobble = 0
        if eMoving then
            local phase = i * 1.7  -- 每个敌人相位偏移, 避免整齐划一
            eWobble = math.sin(gameTimeAcc * 7 + phase) * 0.12
        end

        -- 选择敌人图片
        local eImg = imgEnemies[e.typeKey] or imgEnemies["patrol"] or -1
        local imgSize = e.radius * 2.8
        local halfSize = imgSize / 2

        nvgSave(vg)
        nvgTranslate(vg, e.x, e.y)
        nvgRotate(vg, eWobble)
        nvgGlobalAlpha(vg, alpha / 255)

        if eImg >= 0 then
            -- 根据朝向翻转
            local facingRight = (math.cos(e.angle) >= 0)
            if facingRight then
                nvgScale(vg, -1, 1)
            end

            -- 先绘制纯白描边
            local eWhiteImg = imgEnemiesWhite[e.typeKey] or imgEnemiesWhite["patrol"] or -1
            DrawWhiteOutline(eWhiteImg, halfSize, imgSize)

            -- 再绘制敌人本体
            local paint = nvgImagePattern(vg, -halfSize, -halfSize, imgSize, imgSize, 0, eImg, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, -halfSize, -halfSize, imgSize, imgSize)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        else
            -- 备用: 纯色圆形
            nvgBeginPath(vg)
            nvgCircle(vg, 0, 0, e.radius)
            nvgFillColor(vg, nvgRGBA(e.color[1], e.color[2], e.color[3], 255))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(
                math.floor(e.color[1] * 0.7),
                math.floor(e.color[2] * 0.7),
                math.floor(e.color[3] * 0.7), 255))
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

        -- === 状态效果视觉 ===
        -- 燃烧: 橙红色火焰光环
        if e.burnTimer and e.burnTimer > 0 then
            local flicker = math.sin(gameTimeAcc * 12 + i * 2.3) * 0.3 + 0.7
            -- 外圈火焰光晕
            nvgBeginPath(vg)
            nvgCircle(vg, e.x, e.y, e.radius + 4)
            nvgStrokeColor(vg, nvgRGBA(255, 120, 30, math.floor(140 * flicker)))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
            -- 内圈橙色叠加
            nvgBeginPath(vg)
            nvgCircle(vg, e.x, e.y, e.radius)
            nvgFillColor(vg, nvgRGBA(255, 80, 20, math.floor(40 * flicker)))
            nvgFill(vg)
        end
        -- 减速: 蓝色冰霜覆盖
        if e.slowTimer and e.slowTimer > 0 then
            local frostPulse = math.sin(gameTimeAcc * 4 + i * 1.7) * 0.2 + 0.8
            -- 冰霜外圈
            nvgBeginPath(vg)
            nvgCircle(vg, e.x, e.y, e.radius + 2)
            nvgStrokeColor(vg, nvgRGBA(100, 180, 255, math.floor(120 * frostPulse)))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
            -- 冰霜内部覆盖
            nvgBeginPath(vg)
            nvgCircle(vg, e.x, e.y, e.radius - 1)
            nvgFillColor(vg, nvgRGBA(80, 160, 255, math.floor(35 * frostPulse)))
            nvgFill(vg)
        end

        -- 血条(受伤时显示) - 不受摇摆影响
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

            -- 重装兵: 血条下方额外显示护甲标记
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

function DrawBullets()
    for _, b in ipairs(bullets) do
        -- 拖尾轨迹(渐隐线段)
        if b.trail and #b.trail > 0 then
            local cr, cg, cb
            if b.fromPlayer then
                cr, cg, cb = 255, 255, 100
            else
                cr, cg, cb = 255, 100, 80
            end

            local prevX, prevY = b.x, b.y
            for ti = 1, #b.trail do
                local t = b.trail[ti]
                local alpha = math.floor(180 * (1 - ti / (#b.trail + 1)))
                local width = b.radius * 2 * (1 - ti / (#b.trail + 1)) + 0.5

                nvgBeginPath(vg)
                nvgMoveTo(vg, prevX, prevY)
                nvgLineTo(vg, t.x, t.y)
                nvgStrokeColor(vg, nvgRGBA(cr, cg, cb, alpha))
                nvgStrokeWidth(vg, width)
                nvgLineCap(vg, NVG_ROUND)
                nvgStroke(vg)

                prevX, prevY = t.x, t.y
            end
        end

        -- 子弹本体(发光效果)
        if b.fromPlayer then
            -- 外层光晕
            nvgBeginPath(vg)
            nvgCircle(vg, b.x, b.y, b.radius + 4)
            nvgFillColor(vg, nvgRGBA(255, 255, 150, 60))
            nvgFill(vg)
            -- 内核
            nvgBeginPath(vg)
            nvgCircle(vg, b.x, b.y, b.radius)
            nvgFillColor(vg, nvgRGBA(255, 255, 100, 255))
            nvgFill(vg)
        else
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

function DrawLootItems()
    local t = GetTime():GetElapsedTime()
    for _, item in ipairs(lootItems) do
        local bounce = math.sin(t * 4 + item.x) * 2

        if item.type == "artifact" or item.type == "tablet" then
            -- 圣物/石板: 稀有度颜色发光宝珠 + 名称标签
            local rarity = item.itemData.rarity or 1
            local col = InvData.RARITY_COLORS[rarity] or {200, 200, 200}
            local pulse = 0.7 + 0.3 * math.sin(t * 5 + item.y)  -- 脉冲发光

            -- 外层光晕
            nvgBeginPath(vg)
            nvgCircle(vg, item.x, item.y + bounce, 14)
            nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], math.floor(35 * pulse)))
            nvgFill(vg)

            -- 中层光晕
            nvgBeginPath(vg)
            nvgCircle(vg, item.x, item.y + bounce, 9)
            nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], math.floor(70 * pulse)))
            nvgFill(vg)

            -- 内核宝珠
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

            -- 物品名称(头顶)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 9)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], 200))
            nvgText(vg, item.x, item.y + bounce - 12, item.itemData.name, nil)
        else
            -- 弹药/血包: 原有样式
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

function DrawParticles()
    for _, p in ipairs(particles) do
        local t = p.life / p.maxLife  -- 0→1 归一化剩余生命
        local alpha = math.floor(t * 255)
        local sz = p.size * t

        if p.isShell then
            -- 弹壳: 小矩形
            nvgSave(vg)
            nvgTranslate(vg, p.x, p.y)
            nvgRotate(vg, p.rot or 0)
            nvgBeginPath(vg)
            nvgRect(vg, -sz, -sz * 0.5, sz * 2, sz)
            nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, alpha))
            nvgFill(vg)
            nvgRestore(vg)
        elseif p.glow then
            -- 发光粒子: 外层光晕 + 内核
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
            -- 普通粒子
            nvgBeginPath(vg)
            nvgCircle(vg, p.x, p.y, sz)
            nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, alpha))
            nvgFill(vg)
        end
    end
end

function DrawDamageNumbers()
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    for _, d in ipairs(damageNumbers) do
        local alpha = math.floor((d.life / d.maxLife) * 255)
        if d.isCrit then
            -- 暴击: 金色大字
            nvgFontSize(vg, 18)
            nvgFillColor(vg, nvgRGBA(255, 210, 50, alpha))
        elseif d.isBurn then
            -- 燃烧DoT: 橙色小字
            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBA(255, 150, 40, alpha))
        elseif d.isAoe then
            -- 爆炸AOE: 黄橙色
            nvgFontSize(vg, 12)
            nvgFillColor(vg, nvgRGBA(255, 180, 60, alpha))
        elseif d.isPlayer then
            nvgFontSize(vg, 13)
            nvgFillColor(vg, nvgRGBA(255, 80, 80, alpha))
        elseif d.r and d.g and d.b then
            -- 自定义颜色(如拾取物品)
            nvgFontSize(vg, 12)
            nvgFillColor(vg, nvgRGBA(d.r, d.g, d.b, alpha))
        else
            nvgFontSize(vg, 13)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
        end
        nvgText(vg, d.x, d.y, d.text, nil)
    end
end

function DrawFogOfWar(viewW, viewH)
    -- 无级渐变战争迷雾: 单个 radialGradient 从透明核心平滑过渡到半透明黑暗
    local fogAlpha = 178  -- ~70% 不透明度, 可以隐约看到视野外的地形
    -- 缩放后视野更大, 需要按比例扩大迷雾半径
    local innerR = 100 / camZoom     -- 渐变起始(完全透明)
    local outerR = 260 / camZoom     -- 渐变结束(完全黑暗)

    -- 微弱呼吸
    local t = GetTime():GetElapsedTime()
    local breathe = math.sin(t * 1.5) * 6

    local px = player.x
    local py = player.y
    local iR = innerR + breathe
    local oR = outerR + breathe

    nvgSave(vg)

    -- 外围纯黑(渐变圆之外的区域), 挖掉渐变覆盖的圆
    local zoomViewW = viewW / camZoom
    local zoomViewH = viewH / camZoom
    local fogExtraW = (renderOffsetX or 0) / ((renderScale or 1) * camZoom)
    local fogExtraH = (renderOffsetY or 0) / ((renderScale or 1) * camZoom)
    nvgBeginPath(vg)
    nvgRect(vg, camX - fogExtraW - 20, camY - fogExtraH - 20, zoomViewW + fogExtraW * 2 + 40, zoomViewH + fogExtraH * 2 + 40)
    nvgPathWinding(vg, NVG_HOLE)
    nvgCircle(vg, px, py, oR)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, fogAlpha))
    nvgFill(vg)

    -- 单一径向渐变: innerR 处完全透明 → outerR 处完全黑暗, 无级过渡
    local grad = nvgRadialGradient(vg, px, py, iR, oR,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, fogAlpha))
    nvgBeginPath(vg)
    nvgCircle(vg, px, py, oR)
    nvgFillPaint(vg, grad)
    nvgFill(vg)

    -- 暖色环境光(极淡, 模拟火把)
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

function DrawSearchProgress()
    if not searchingCrate then return end

    local cx = (searchingCrate.col - 0.5) * TILE_SIZE
    local cy = (searchingCrate.row - 0.5) * TILE_SIZE
    local progress = 1.0 - (searchingCrate.timer / SEARCH_TIME)

    -- 进度条背景
    local barW = 40
    local barH = 5
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - barW/2, cy - 20, barW, barH, 2)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    -- 进度条
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - barW/2, cy - 20, barW * progress, barH, 2)
    nvgFillColor(vg, nvgRGBA(255, 200, 60, 255))
    nvgFill(vg)

    -- 文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
    nvgText(vg, cx, cy - 28, "搜索中...", nil)
end

-- ============================================================================
-- 波次UI绘制函数 (屏幕空间/设计分辨率坐标)
-- ============================================================================

--- 波次清除公告 (PHASE_CLEARED 时显示)
function DrawWaveCleared(w, h)
    -- 半透明暗色遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 100))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 主标题: "波次清除!"
    local pulse = math.sin(GetTime():GetElapsedTime() * 5) * 0.2 + 0.8
    nvgFontSize(vg, 32)
    nvgFillColor(vg, nvgRGBA(80, 255, 120, math.floor(255 * pulse)))
    nvgText(vg, w / 2, h / 2 - 20, "敌人已清除!", nil)

    -- 副标题
    local wave = WM.GetCurrentWave()
    local desc = wave and wave.name or ""
    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(200, 220, 200, 200))
    nvgText(vg, w / 2, h / 2 + 16,
        "Wave " .. WM.currentWave .. " 「" .. desc .. "」 完成", nil)

    -- 倒计时提示
    local remaining = math.max(0, math.ceil(WM.phaseTimer))
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(180, 180, 180, 180))
    nvgText(vg, w / 2, h / 2 + 44,
        remaining .. " 秒后开放出口...", nil)
end

--- 出口方向指示器 (PHASE_EXIT_OPEN / PHASE_WALKOUT 时显示, 屏幕空间)
function DrawExitIndicator(w, h)
    if not WM.exitReady then return end

    local t = GetTime():GetElapsedTime()

    -- 计算出口在屏幕上的位置
    local exitScreenX = (WM.exitX - camX) * camZoom
    local exitScreenY = (WM.exitY - camY) * camZoom

    -- 判断出口是否在屏幕可见区域内
    local margin = 60
    local onScreen = exitScreenX > margin and exitScreenX < w - margin
                 and exitScreenY > margin and exitScreenY < h - margin

    -- 玩家屏幕中心位置
    local playerScreenX = (player.x - camX) * camZoom
    local playerScreenY = (player.y - camY) * camZoom

    -- 方向角
    local angle = math.atan(exitScreenY - playerScreenY, exitScreenX - playerScreenX)
    local dist = math.sqrt((WM.exitX - player.x)^2 + (WM.exitY - player.y)^2)

    if not onScreen then
        -- 出口不可见: 在屏幕边缘绘制方向箭头
        local arrowDist = math.min(w, h) * 0.4
        local ax = w / 2 + math.cos(angle) * arrowDist
        local ay = h / 2 + math.sin(angle) * arrowDist
        -- 限制在屏幕边缘
        ax = math.max(40, math.min(w - 40, ax))
        ay = math.max(40, math.min(h - 40, ay))

        local pulse = 0.7 + 0.3 * math.sin(t * 4)
        local arrowAlpha = math.floor(220 * pulse)

        -- 箭头背景圆
        nvgBeginPath(vg)
        nvgCircle(vg, ax, ay, 18)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 140))
        nvgFill(vg)

        -- 箭头三角形
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

        -- 距离文字
        local distText = math.floor(dist / TILE_SIZE) .. "m"
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 255, 200, arrowAlpha))
        nvgText(vg, ax, ay + 24, distText, nil)
    end

    -- 顶部提示文字
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

        -- 距离提示(居中, 小字)
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(180, 220, 180, 180))
        nvgText(vg, w / 2, 68, math.floor(dist / TILE_SIZE) .. " 米", nil)
    end
end

--- 奖励选择界面 (PHASE_REWARD 时显示)
function DrawRewardScreen(w, h)
    -- 暗色遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    local wave = WM.GetCurrentWave()
    local isSupply = (wave and wave.rewardType == "supply")

    if isSupply then
        -- 补给奖励: 自动获得
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
        -- 三选一奖励
        nvgFontSize(vg, 24)
        nvgFillColor(vg, nvgRGBA(255, 220, 80, 255))
        nvgText(vg, w / 2, h * 0.18, "选择装备强化", nil)

        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(180, 180, 180, 200))
        nvgText(vg, w / 2, h * 0.18 + 24, "A/D 或 ←/→ 切换  |  Enter/Space/点击 确认", nil)

        local choices = WM.rewardChoices
        local cardCount = #choices
        if cardCount == 0 then return end

        local cardW = 140
        local cardH = 170
        local gap = 20
        local totalW = cardCount * cardW + (cardCount - 1) * gap
        local startX = (w - totalW) / 2
        local cardY = (h - cardH) / 2 + 10

        for i, reward in ipairs(choices) do
            local cx = startX + (i - 1) * (cardW + gap)
            local selected = (i == WM.selectedReward)

            -- 卡片背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx, cardY, cardW, cardH, 10)
            if selected then
                nvgFillColor(vg, nvgRGBA(50, 55, 80, 240))
            else
                nvgFillColor(vg, nvgRGBA(35, 38, 55, 220))
            end
            nvgFill(vg)

            -- 选中边框(高亮)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx, cardY, cardW, cardH, 10)
            if selected then
                local glow = math.sin(GetTime():GetElapsedTime() * 4) * 0.3 + 0.7
                nvgStrokeColor(vg, nvgRGBA(255, 220, 80, math.floor(220 * glow)))
                nvgStrokeWidth(vg, 2.5)
            else
                nvgStrokeColor(vg, nvgRGBA(80, 85, 100, 160))
                nvgStrokeWidth(vg, 1)
            end
            nvgStroke(vg)

            -- 图标区域 (用简单图形表示)
            local iconY = cardY + 25
            local iconSize = 32
            local iconCX = cx + cardW / 2
            DrawRewardIcon(iconCX, iconY + iconSize / 2, iconSize, reward.icon, selected)

            -- 名称
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            if selected then
                nvgFillColor(vg, nvgRGBA(255, 240, 200, 255))
            else
                nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
            end
            nvgText(vg, cx + cardW / 2, iconY + iconSize + 20, reward.name, nil)

            -- 描述
            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(160, 170, 180, 200))
            nvgText(vg, cx + cardW / 2, iconY + iconSize + 42, reward.desc, nil)

            -- 序号提示
            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBA(120, 120, 130, 160))
            nvgText(vg, cx + cardW / 2, cardY + cardH - 16, "[" .. i .. "]", nil)
        end
    end
end

--- 奖励图标 (简单几何图形)
function DrawRewardIcon(cx, cy, size, iconType, selected)
    local r = size / 2
    local alpha = selected and 255 or 180

    if iconType == "ammo" then
        -- 子弹图标
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - 4, cy - r, 8, size, 3)
        nvgFillColor(vg, nvgRGBA(220, 180, 60, alpha))
        nvgFill(vg)
    elseif iconType == "health" then
        -- 十字图标
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
        -- 盾牌(圆)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, r)
        nvgFillColor(vg, nvgRGBA(80, 160, 255, alpha))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, r * 0.5)
        nvgFillColor(vg, nvgRGBA(40, 80, 180, alpha))
        nvgFill(vg)
    elseif iconType == "damage" then
        -- 闪电/菱形
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx, cy - r)
        nvgLineTo(vg, cx + r * 0.6, cy)
        nvgLineTo(vg, cx, cy + r)
        nvgLineTo(vg, cx - r * 0.6, cy)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(255, 100, 60, alpha))
        nvgFill(vg)
    elseif iconType == "speed" then
        -- 箭头
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - r, cy + r * 0.5)
        nvgLineTo(vg, cx + r * 0.5, cy)
        nvgLineTo(vg, cx - r, cy - r * 0.5)
        nvgStrokeColor(vg, nvgRGBA(100, 255, 200, alpha))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
    elseif iconType == "mag" then
        -- 弹匣(方块)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - r * 0.5, cy - r, r, size, 2)
        nvgFillColor(vg, nvgRGBA(180, 140, 80, alpha))
        nvgFill(vg)
        -- 小横线表示扩容
        nvgBeginPath(vg)
        nvgRect(vg, cx - r * 0.7, cy - 2, r * 1.4, 4)
        nvgFillColor(vg, nvgRGBA(255, 220, 80, alpha))
        nvgFill(vg)
    elseif iconType == "rate" then
        -- 快速(双箭头)
        for i = -1, 1, 2 do
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx - r * 0.5 + i * 3, cy + r * 0.5)
            nvgLineTo(vg, cx + r * 0.3 + i * 3, cy)
            nvgLineTo(vg, cx - r * 0.5 + i * 3, cy - r * 0.5)
            nvgStrokeColor(vg, nvgRGBA(255, 200, 100, alpha))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end
    else
        -- 默认圆形
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, r * 0.7)
        nvgFillColor(vg, nvgRGBA(180, 180, 180, alpha))
        nvgFill(vg)
    end
end

--- 波次开始公告 (waveAnnounceTimer > 0 时显示)
function DrawWaveAnnounce(w, h)
    local alpha = math.min(1.0, waveAnnounceTimer / 0.5)  -- 前0.5秒淡入
    if waveAnnounceTimer < 0.5 then
        alpha = waveAnnounceTimer / 0.5  -- 后0.5秒淡出
    end
    local a = math.floor(255 * alpha)

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 半透明带状背景
    local bandH = 70
    local bandY = h / 2 - bandH / 2
    nvgBeginPath(vg)
    nvgRect(vg, 0, bandY, w, bandH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(140 * alpha)))
    nvgFill(vg)

    -- 波次标题
    local wave = WM.GetCurrentWave()
    local waveName = wave and wave.name or ""
    nvgFontSize(vg, 25)
    nvgFillColor(vg, nvgRGBA(255, 220, 80, a))
    nvgText(vg, w / 2, h / 2 - 12,
        "Wave " .. WM.currentWave .. " — " .. waveName, nil)

    -- 描述
    if wave and wave.desc then
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(200, 210, 220, math.floor(a * 0.8)))
        nvgText(vg, w / 2, h / 2 + 16, wave.desc, nil)
    end
end

--- Boss血条 (屏幕顶部)
function DrawBossHPBar(w, h)
    if not WM.boss then return end

    local boss = WM.boss
    local barW = math.min(400, w * 0.5)
    local barH = 14
    local barX = (w - barW) / 2
    local barY = 8

    -- 名称
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(255, 100, 80, 240))
    nvgText(vg, w / 2, barY - 2, boss.name or "BOSS", nil)

    -- 血条背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 4)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgFill(vg)

    -- 血条
    local hpRatio = math.max(0, boss.hp / boss.maxHp)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW * hpRatio, barH, 4)
    -- 根据阶段变色
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

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 4)
    nvgStrokeColor(vg, nvgRGBA(200, 80, 60, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- HP 文字
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
    nvgText(vg, w / 2, barY + barH / 2,
        math.floor(boss.hp) .. " / " .. boss.maxHp, nil)
end

-- ============================================================================
-- HUD (屏幕空间坐标)
-- ============================================================================
function DrawHUD(w, h)
    nvgFontFace(vg, "sans")

    -- === 左上: 血条 ===
    local hpBarX = 16
    local hpBarY = 16
    local hpBarW = 160
    local hpBarH = 16
    local effectiveMaxHp = player.maxHp + Inv.GetStat("maxHp", 0)
    local hpRatio = player.hp / effectiveMaxHp

    -- 血条背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, hpBarX, hpBarY, hpBarW, hpBarH, 4)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    -- 血条
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

    -- 血量文字
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, hpBarX + hpBarW / 2, hpBarY + hpBarH / 2,
        math.floor(player.hp) .. " / " .. math.floor(effectiveMaxHp), nil)

    -- === 左上第二行: 弹药 ===
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
    nvgFillColor(vg, ammoColor)
    local ammoText
    if player.reloading then
        ammoText = WEAPON.name .. "  换弹中..."
    else
        ammoText = WEAPON.name .. "  " .. player.ammo .. " / " .. player.totalAmmo
    end
    nvgText(vg, hpBarX, hpBarY + hpBarH + 6, ammoText, nil)

    -- === 右上: 波次信息 ===
    local wave = WM.GetCurrentWave()
    local waveName = wave and wave.name or ("第" .. WM.currentWave .. "波")
    local waveLabel = "Wave " .. WM.currentWave .. "/" .. #WM.WAVES .. "  " .. waveName
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 220, 80, 240))
    nvgText(vg, w - 16, 16, waveLabel, nil)

    -- === 右上第二行: 时间 + 击杀 ===
    local timeMin = math.floor(gameTime / 60)
    local timeSec = math.floor(gameTime % 60)
    local timeStr = string.format("%d:%02d", timeMin, timeSec)
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
    nvgText(vg, w - 16, 36, timeStr .. "  击杀:" .. killCount .. "  分数:" .. score, nil)

    -- === 右上第三行: 剩余敌人 ===
    local enemyAlive = #enemies
    if enemyAlive > 0 then
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(255, 120, 120, 200))
        nvgText(vg, w - 16, 54, "敌人剩余: " .. enemyAlive, nil)
    end

    -- === 待放入物品提示 ===
    local pendingCount = Inv.GetPendingCount()
    if pendingCount > 0 then
        local pulse = math.sin(GetTime():GetElapsedTime() * 4) * 0.3 + 0.7
        local notifyAlpha = math.floor(255 * pulse)

        -- 背景条
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
            "Tab 打开背包 (" .. pendingCount .. "个新物品)", nil)
    end

    -- === 底部: 操作提示 ===
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 160))
    nvgText(vg, w / 2, h - 12, "WASD移动 | 鼠标瞄准 | 左键射击 | R换弹 | Tab背包", nil)

    -- === 小地图 (右下角) ===
    DrawMinimap(w, h)
end

function DrawMinimap(sw, sh)
    local mmSize = 100
    local mmX = sw - mmSize - 12
    local mmY = sh - mmSize - 30
    local scale = mmSize / math.max(MAP_W, MAP_H)

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, mmX - 2, mmY - 2, mmSize + 4, mmSize + 4, 4)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgFill(vg)

    -- 瓦片(简化版: 只画墙)
    for r = 1, MAP_ROWS do
        for c = 1, MAP_COLS do
            local tile = mapData[r][c]
            if tile ~= TILE_WALL then
                local tx = mmX + (c - 1) * TILE_SIZE * scale
                local ty = mmY + (r - 1) * TILE_SIZE * scale
                local tw = math.max(1, TILE_SIZE * scale)

                nvgBeginPath(vg)
                nvgRect(vg, tx, ty, tw, tw)

                if tile == TILE_CRATE then
                    nvgFillColor(vg, nvgRGBA(180, 140, 60, 200))
                elseif tile == TILE_EXIT then
                    nvgFillColor(vg, nvgRGBA(80, 255, 80, 200))
                else
                    nvgFillColor(vg, nvgRGBA(80, 85, 90, 200))
                end
                nvgFill(vg)
            end
        end
    end

    -- 敌人点
    for _, e in ipairs(enemies) do
        nvgBeginPath(vg)
        nvgCircle(vg, mmX + e.x * scale, mmY + e.y * scale, 1.5)
        nvgFillColor(vg, nvgRGBA(255, 80, 80, 220))
        nvgFill(vg)
    end

    -- 玩家点
    nvgBeginPath(vg)
    nvgCircle(vg, mmX + player.x * scale, mmY + player.y * scale, 2.5)
    nvgFillColor(vg, nvgRGBA(60, 255, 60, 255))
    nvgFill(vg)
end

function DrawEndScreen(w, h)
    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgFill(vg)

    local isVictory = (gameState == STATE_VICTORY)

    -- 面板
    local panelW = math.min(340, w - 40)
    local panelH = isVictory and 260 or 220
    local panelX = (w - panelW) / 2
    local panelY = (h - panelH) / 2

    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 12)
    nvgFillColor(vg, nvgRGBA(30, 35, 50, 240))
    nvgFill(vg)

    -- 边框颜色
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

    -- 标题
    nvgFontSize(vg, 28)
    if isVictory then
        local pulse = math.sin(GetTime():GetElapsedTime() * 3) * 0.15 + 0.85
        nvgFillColor(vg, nvgRGBA(255, 220, 60, math.floor(255 * pulse)))
        nvgText(vg, w / 2, panelY + 42, "小红帽获救!", nil)
        -- 副标题
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(180, 220, 255, 220))
        nvgText(vg, w / 2, panelY + 68, "大灰狼集团已被击溃!", nil)
    else
        nvgFillColor(vg, nvgRGBA(255, 80, 80, 255))
        nvgText(vg, w / 2, panelY + 45, "小狼倒下了...", nil)
        -- 失败时显示波次进度
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(180, 180, 180, 200))
        nvgText(vg, w / 2, panelY + 72,
            "进度: Wave " .. WM.currentWave .. "/" .. #WM.WAVES, nil)
    end

    -- 统计
    local statY = isVictory and (panelY + 100) or (panelY + 100)
    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
    nvgText(vg, w / 2, statY, "击退灰狼: " .. killCount, nil)
    nvgText(vg, w / 2, statY + 25, "分数: " .. score, nil)

    local survMin = math.floor(gameTime / 60)
    local survSec = math.floor(gameTime % 60)
    nvgText(vg, w / 2, statY + 50,
        string.format("冒险用时: %d:%02d", survMin, survSec), nil)

    if isVictory then
        -- 额外显示获得的强化
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

    -- 重新开始提示
    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(160, 160, 160, 200))
    local bottomY = panelY + panelH - 30
    nvgText(vg, w / 2, bottomY, "点击任意处再次出发", nil)
end
