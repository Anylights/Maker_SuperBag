-- ============================================================================
-- game_context.lua — 全局共享状态（所有模块 require 同一实例）
-- ============================================================================

local G = {}

-- ============================================================================
-- 常量
-- ============================================================================
G.TILE_SIZE   = 32
G.MAP_COLS    = 40
G.MAP_ROWS    = 30
G.MAP_W       = G.MAP_COLS * G.TILE_SIZE
G.MAP_H       = G.MAP_ROWS * G.TILE_SIZE

-- 瓦片类型
G.TILE_FLOOR      = 0
G.TILE_WALL       = 1
G.TILE_CRATE_WOOD = 2
G.TILE_EXIT       = 3
G.TILE_CRATE_IRON = 4
G.TILE_CRATE_GOLD = 5

--- 箱子辅助
function G.IsCrateTile(tile)
    return tile == G.TILE_CRATE_WOOD or tile == G.TILE_CRATE_IRON or tile == G.TILE_CRATE_GOLD
end

-- 箱子配置表
G.CRATE_CONFIG = {
    [G.TILE_CRATE_WOOD] = {
        name = "木箱",
        searchTime = 1.0,
        ammoChance   = 90,
        healthChance = 85,
        maxRarity = 2,
        ammoRange = {15, 25},
        healthRange = {15, 30},
    },
    [G.TILE_CRATE_IRON] = {
        name = "铁箱",
        searchTime = 2.0,
        ammoChance   = 80,
        healthChance = 55,
        maxRarity = 3,
        ammoRange = {25, 40},
        healthRange = {25, 45},
    },
    [G.TILE_CRATE_GOLD] = {
        name = "金箱",
        searchTime = 3.5,
        ammoChance   = 70,
        healthChance = 30,
        maxRarity = 5,
        ammoRange = {35, 60},
        healthRange = {35, 60},
    },
}

function G.GetCrateSpawnWeights(wave)
    if wave >= 7 then
        return { {G.TILE_CRATE_WOOD, 30}, {G.TILE_CRATE_IRON, 40}, {G.TILE_CRATE_GOLD, 30} }
    elseif wave >= 5 then
        return { {G.TILE_CRATE_WOOD, 45}, {G.TILE_CRATE_IRON, 40}, {G.TILE_CRATE_GOLD, 15} }
    elseif wave >= 3 then
        return { {G.TILE_CRATE_WOOD, 70}, {G.TILE_CRATE_IRON, 30}, {G.TILE_CRATE_GOLD, 0} }
    else
        return { {G.TILE_CRATE_WOOD, 100}, {G.TILE_CRATE_IRON, 0}, {G.TILE_CRATE_GOLD, 0} }
    end
end

function G.PickWeightedCrate(wave)
    local weights = G.GetCrateSpawnWeights(wave)
    local total = 0
    for _, w in ipairs(weights) do total = total + w[2] end
    local roll = math.random(1, total)
    local acc = 0
    for _, w in ipairs(weights) do
        acc = acc + w[2]
        if roll <= acc then return w[1] end
    end
    return G.TILE_CRATE_WOOD
end

-- 游戏状态枚举
G.STATE_COMIC     = "comic"
G.STATE_TITLE     = "title"
G.STATE_PLAYING   = "playing"
G.STATE_PAUSED    = "paused"
G.STATE_DYING     = "dying"
G.STATE_GAMEOVER  = "gameover"
G.STATE_EXTRACTED = "extracted"
G.STATE_VICTORY   = "victory"

-- 武器数据
G.WEAPON = {
    name = "弹弓",
    damage = 25,
    fireRate = 0.2,
    bulletSpeed = 1000,
    magSize = 12,
    totalAmmo = 150,
    reloadTime = 1.5,
    spread = 3,
    bulletRadius = 3,
}

-- 子弹拖尾最大长度
G.TRAIL_MAX = 6

-- 敌人类型数据
G.ENEMY_TYPES = {
    patrol = {
        name = "灰狼巡逻",
        hp = 100, speed = 60, damage = 10, radius = 12,
        color = {200, 80, 80},
        sightRange = 200, attackRange = 180, attackRate = 0.8,
        bulletSpeed = 280,
        attackPattern = "single",
    },
    sentry = {
        name = "灰狼哨兵",
        hp = 85, speed = 0, damage = 12, radius = 14,
        color = {80, 80, 200},
        sightRange = 280, attackRange = 260, attackRate = 1.8,
        bulletSpeed = 330,
        attackPattern = "burst",
        burstCount = 3,
        burstInterval = 0.1,
    },
    rusher = {
        name = "灰狼突击",
        hp = 130, speed = 140, damage = 20, radius = 10,
        color = {200, 160, 40},
        sightRange = 160, attackRange = 30, attackRate = 0.5,
        bulletSpeed = 0,
        attackPattern = "melee",
    },
    heavy = {
        name = "灰狼重装",
        hp = 260, speed = 35, damage = 8, radius = 16,
        color = {100, 100, 120},
        sightRange = 220, attackRange = 160, attackRate = 2.2,
        bulletSpeed = 240,
        attackPattern = "shotgun",
        shotgunPellets = 4,
        shotgunSpread = 0.35,
        armor = 0.3,
    },
    alpha = {
        name = "头狼精锐",
        hp = 400, speed = 50, damage = 15, radius = 18,
        color = {180, 50, 50},
        sightRange = 240, attackRange = 200, attackRate = 1.5,
        bulletSpeed = 320,
        attackPattern = "burst",
        burstCount = 3,
        burstInterval = 0.08,
        armor = 0.15,
    },
}

-- 子弹视觉配色表
G.BULLET_FX_COLORS = {
    normal   = { core = {255, 255, 100}, glow = {255, 255, 150}, trail = {255, 255, 100} },
    shotgun  = { core = {255, 200, 60},  glow = {255, 220, 100}, trail = {255, 180, 40} },
    pierce   = { core = {100, 220, 255}, glow = {120, 200, 255}, trail = {80, 180, 255} },
    bounce   = { core = {100, 255, 120}, glow = {140, 255, 160}, trail = {80, 255, 100} },
    frost    = { core = {140, 220, 255}, glow = {180, 240, 255}, trail = {100, 200, 255} },
    burn     = { core = {255, 140, 40},  glow = {255, 100, 20},  trail = {255, 80, 20} },
    shock    = { core = {180, 140, 255}, glow = {200, 160, 255}, trail = {160, 120, 255} },
    explosive= { core = {255, 180, 40},  glow = {255, 200, 60},  trail = {255, 160, 20} },
}

-- 闪电链延迟队列
G.pendingChainLightning = {}

-- 命中停顿常量
G.HITSTOP_HIT  = 0.03
G.HITSTOP_KILL = 0.08

-- 死亡动画常量
G.DEATH_ANIM_DURATION = 3.0

-- 近战刀光序列帧数
G.SLASH_FRAME_COUNT = 6

-- 设计分辨率
G.DESIGN_W = 1152
G.DESIGN_H = 648

-- ============================================================================
-- 可变状态（运行时修改）
-- ============================================================================

-- NanoVG 上下文 & 资源
G.vg = nil
G.fontNormal = -1
G.imgPlayer = -1
G.imgPlayerWhite = -1
G.imgSlashFrames = {}
G.imgEnemies = {}
G.imgEnemiesWhite = {}
G.imgEnemiesRed = {}
G.imgFloorTiles = {}
G.imgForestTiles = {}
G.imgDarkTiles = {}
G.imgEdgeTiles = {}
G.imgCrateTiles = {}
G.imgCrateByType = {}
G.gameTimeAcc = 0

-- 音效
G.sndShoot      = nil
G.sndReload     = nil
G.sndHit        = nil
G.sndKill       = nil
G.sndSplat      = nil
G.sndReloadDone = nil
G.sndFootstep   = nil
G.sndLevelClear = nil
G.footstepTimer = 0
G.audioScene    = nil

-- 平台检测（默认PC；第一个TouchBegin事件触发时自动切换为true）
G.isMobile = false

-- 游戏运行时
G.gameState    = G.STATE_PLAYING
G.gameTime     = 0
G.score        = 0
G.killCount    = 0
G.gameTimeScale = 1.0

-- 波次公告
G.waveAnnounceTimer = 0
G.waveAnnounceText  = ""

-- 相机
G.camX    = 0
G.camY    = 0
G.camZoom = 1.3

-- 屏幕
G.screenW = 0
G.screenH = 0
G.dpr     = 1
G.renderScale   = 1.0
G.renderOffsetX = 0
G.renderOffsetY = 0

-- 玩家
G.player = {
    x = 0, y = 0,
    radius = 14,
    speed = 180,
    hp = 100, maxHp = 100,
    angle = 0,
    ammo = 12,
    totalAmmo = 150,
    reloading = false,
    reloadTimer = 0,
    fireTimer = 0,
    alive = true,
    invincibleTimer = 0,
    shield = 0,
    shieldMax = 0,
    shieldRegen = 0,
    shieldRegenDelay = 0,
    -- 近战
    meleeTimer = 0,
    meleeSwingTimer = 0,
    meleeSwingDur = 0.25,
    meleeCooldown = 0.4,
    meleeRange = 35,
    meleeArc = math.pi * 0.8,
    meleeHitDone = false,
    -- 视觉后坐力
    recoilX = 0,
    recoilY = 0,
    -- 冲刺系统
    dashTimer = 0,      -- 冲刺剩余时间 (>0 = 正在冲刺)
    dashCooldown = 0,   -- 冷却倒计时
    dashDirX = 0,       -- 冲刺方向
    dashDirY = 0,
}

-- 实体列表
G.bullets          = {}
G.enemies          = {}
G.lootItems        = {}
G.particles        = {}
G.damageNumbers    = {}
G.lightningEffects = {}
G.drones           = {}

-- 地图
G.mapData  = {}
G.mapRooms = {}

-- 搜刮状态
G.searchingCrate = nil

-- 屏幕震动
G.shakeIntensity = 0
G.shakeTimer     = 0
G.shakeOffsetX   = 0
G.shakeOffsetY   = 0

-- 命中停顿
G.hitstopTimer = 0

-- 死亡电影化
G.deathAnimTimer  = 0
G.deathZoomStart  = 1.3
G.deathSlowScale  = 1.0

-- 走出动画
G.walkoutStartX   = 0
G.walkoutStartY   = 0
G.walkoutTargetX  = 0
G.walkoutTargetY  = 0
G.walkoutZoomStart = 0.75
G.walkoutZoomEnd   = 0.9

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 物理屏幕坐标 → 设计坐标
function G.ScreenToDesign(px, py)
    return (px - G.renderOffsetX) / G.renderScale,
           (py - G.renderOffsetY) / G.renderScale
end

--- 音效播放辅助
function G.PlaySfx(sound, gain)
    if not sound then return end
    if not G.audioScene then return end
    local node = G.audioScene:CreateChild("SfxNode")
    local src = node:CreateComponent("SoundSource")
    src.soundType = "Effect"
    src.gain = gain or 0.5
    src.autoRemoveMode = REMOVE_NODE
    src:Play(sound)
end

return G
