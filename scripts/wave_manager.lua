-- ============================================================================
-- 波次管理器 (Wave Manager)
-- 管理游戏的多波次渐进流程: 战斗→奖励→战斗→精英→...→Boss
-- ============================================================================

local WM = {}

-- ============================================================================
-- 波次状态常量
-- ============================================================================
WM.PHASE_COMBAT    = "combat"     -- 战斗中(清除所有敌人)
WM.PHASE_CLEARED   = "cleared"    -- 波次刚清完(短暂展示)
WM.PHASE_EXIT_OPEN = "exit_open"  -- 出口已开放(玩家需走到出口)
WM.PHASE_WALKOUT   = "walkout"    -- 走出动画(玩家自动移向出口)
WM.PHASE_REWARD    = "reward"     -- 选择奖励
WM.PHASE_TRANSIT   = "transit"    -- 过渡到下一波(地图重生中)
WM.PHASE_BOSS      = "boss"       -- Boss战
WM.PHASE_VICTORY   = "victory"    -- 全部通关

-- ============================================================================
-- 波次定义 (7波 + Boss)
-- ============================================================================
-- 每波包含: 类型、敌人数量系数、敌人类型权重、地图参数、奖励类型
WM.WAVES = {
    -- Wave 1: 新手引导 (只有巡逻兵, 少量, HP较低让玩家熟悉)
    {
        name = "森林入口",
        desc = "小狼踏入黑暗森林",
        type = "combat",
        enemyCount = 16,
        rooms = 10,
        mapSize = {cols = 50, rows = 36},
        weights = { patrol = 100, sentry = 0, rusher = 0 },
        hpMult = 0.8,
        dmgMult = 0.6,
        rewardType = "choice",  -- 三选一奖励
    },
    -- Wave 2: 引入哨兵, 数量渐增
    {
        name = "密林小径",
        desc = "穿越大灰狼的巡逻区",
        type = "combat",
        enemyCount = 22,
        rooms = 12,
        mapSize = {cols = 55, rows = 40},
        weights = { patrol = 60, sentry = 40, rusher = 0 },
        hpMult = 1.0,
        dmgMult = 0.8,
        rewardType = "supply",  -- 补给(弹药+血)
    },
    -- Wave 3: 引入冲锋者, HP开始攀升(幂次曲线起点)
    {
        name = "灰狼哨站",
        desc = "攻破灰狼集团的前哨",
        type = "combat",
        enemyCount = 28,
        rooms = 14,
        mapSize = {cols = 60, rows = 42},
        weights = { patrol = 40, sentry = 30, rusher = 30 },
        hpMult = 1.3,
        dmgMult = 1.0,
        rewardType = "choice",
    },
    -- Wave 4: 引入重装兵+头狼精锐(精英波, HP跳跃)
    {
        name = "狼群伏击",
        desc = "遭遇灰狼精锐!",
        type = "elite",
        enemyCount = 32,
        rooms = 12,
        mapSize = {cols = 55, rows = 40},
        weights = { patrol = 15, sentry = 25, rusher = 30, heavy = 20, alpha = 10 },
        hpMult = 1.8,
        dmgMult = 1.2,
        rewardType = "choice",
    },
    -- Wave 5: 大规模战斗, HP继续攀升
    {
        name = "外婆家附近",
        desc = "深入灰狼集团腹地",
        type = "combat",
        enemyCount = 40,
        rooms = 16,
        mapSize = {cols = 65, rows = 48},
        weights = { patrol = 20, sentry = 25, rusher = 25, heavy = 20, alpha = 10 },
        hpMult = 2.4,
        dmgMult = 1.4,
        rewardType = "supply",
    },
    -- Wave 6: 高难度混合, 头狼增多
    {
        name = "灰狼营地",
        desc = "捣毁灰狼集团的巢穴",
        type = "combat",
        enemyCount = 48,
        rooms = 16,
        mapSize = {cols = 65, rows = 48},
        weights = { patrol = 10, sentry = 20, rusher = 30, heavy = 25, alpha = 15 },
        hpMult = 3.2,
        dmgMult = 1.6,
        rewardType = "choice",
    },
    -- Wave 7: Boss前哨(精英波, HP峰值)
    {
        name = "囚禁之地",
        desc = "小红帽就在前方...",
        type = "elite",
        enemyCount = 44,
        rooms = 14,
        mapSize = {cols = 60, rows = 42},
        weights = { patrol = 5, sentry = 20, rusher = 30, heavy = 25, alpha = 20 },
        hpMult = 4.0,
        dmgMult = 1.8,
        rewardType = "choice",
    },
    -- Wave 8: Boss战
    {
        name = "大灰狼首领",
        desc = "击败大灰狼, 救出小红帽!",
        type = "boss",
        enemyCount = 20,  -- 小兵 + Boss
        rooms = 8,
        mapSize = {cols = 45, rows = 35},
        weights = { patrol = 30, sentry = 30, rusher = 20, alpha = 20 },
        hpMult = 1.5,
        dmgMult = 1.2,
        rewardType = "none",
    },
}

-- ============================================================================
-- 奖励定义
-- ============================================================================
WM.REWARD_POOL = {
    -- 每个奖励: {id, name, desc, apply}
    { id = "ammo_pack",   name = "石弹补给",   desc = "+30 弹药",
      icon = "ammo", apply = function(p) p.totalAmmo = p.totalAmmo + 30 end },
    { id = "heal_kit",    name = "草药包",     desc = "回复 40 HP",
      icon = "health", apply = function(p) p.hp = math.min(p.maxHp, p.hp + 40) end },
    { id = "max_hp_up",   name = "狼族血脉",   desc = "最大HP +15",
      icon = "shield", apply = function(p) p.maxHp = p.maxHp + 15; p.hp = p.hp + 15 end },
    { id = "dmg_up",      name = "利爪强化",   desc = "伤害 +8",
      icon = "damage", apply = function(p) end },  -- 通过weapon modifier实现
    { id = "speed_up",    name = "疾风步法",   desc = "移速 +8",
      icon = "speed", apply = function(p) p.speed = p.speed + 8 end },
    { id = "mag_up",      name = "大容量弹袋",   desc = "弹匣 +4",
      icon = "mag", apply = function(p) end },  -- 通过weapon modifier实现
    { id = "fire_rate",   name = "连射技巧",   desc = "射速提升",
      icon = "rate", apply = function(p) end },
    { id = "full_ammo",   name = "弹药宝箱",   desc = "弹药全满",
      icon = "ammo", apply = function(p) p.totalAmmo = p.totalAmmo + 60 end },
    { id = "full_heal",   name = "长老秘药",   desc = "HP全满",
      icon = "health", apply = function(p) p.hp = p.maxHp end },
}

-- 武器modifier(在main里应用)
WM.weaponMods = {
    bonusDamage = 0,
    bonusMagSize = 0,
    fireRateReduction = 0,
}

-- ============================================================================
-- 状态
-- ============================================================================
WM.currentWave = 1           -- 当前波次 (1-8)
WM.phase = WM.PHASE_COMBAT   -- 当前阶段
WM.phaseTimer = 0             -- 阶段计时器
WM.totalTime = 0              -- 总游戏时间
WM.waveStartTime = 0          -- 当前波次开始时间
WM.waveKills = 0              -- 当前波次击杀数
WM.totalKills = 0             -- 总击杀数

-- 过渡动画
WM.transitAlpha = 0           -- 渐变遮罩透明度 (0→255→0)
WM.transitPhase = "none"      -- "fade_out" | "fade_in" | "none"
WM.transitCallback = nil      -- 渐变完成回调

-- 奖励选择
WM.rewardChoices = {}         -- 当前可选奖励 (3个)
WM.selectedReward = 0         -- 高亮的奖励索引
WM.rewardConfirmed = false    -- 是否已确认选择

-- Boss状态
WM.boss = nil                 -- Boss实例引用
WM.bossSpawnTimer = 0         -- Boss召唤小兵冷却

-- 出口系统
WM.exitX = 0                  -- 出口中心世界坐标X
WM.exitY = 0                  -- 出口中心世界坐标Y
WM.exitReady = false          -- 出口是否已生成
WM.walkoutTimer = 0           -- 走出动画计时器
WM.walkoutDuration = 1.2      -- 走出动画持续时间(秒)

-- 动态难度
WM.difficultyMod = 1.0        -- 难度修正系数

-- ============================================================================
-- 初始化
-- ============================================================================
function WM.Init()
    WM.currentWave = 1
    WM.phase = WM.PHASE_TRANSIT
    WM.phaseTimer = 0
    WM.totalTime = 0
    WM.waveStartTime = 0
    WM.waveKills = 0
    WM.totalKills = 0
    WM.transitAlpha = 255  -- 开始时全黑渐入
    WM.transitPhase = "fade_in"
    WM.transitCallback = nil
    WM.rewardChoices = {}
    WM.selectedReward = 1
    WM.rewardConfirmed = false
    WM.boss = nil
    WM.bossSpawnTimer = 0
    WM.exitX = 0
    WM.exitY = 0
    WM.exitReady = false
    WM.walkoutTimer = 0
    WM.difficultyMod = 1.0
    WM.weaponMods = {
        bonusDamage = 0,
        bonusMagSize = 0,
        fireRateReduction = 0,
    }
end

-- ============================================================================
-- 获取当前波次数据
-- ============================================================================
function WM.GetCurrentWave()
    return WM.WAVES[WM.currentWave]
end

function WM.GetWaveCount()
    return #WM.WAVES
end

function WM.IsLastWave()
    return WM.currentWave >= #WM.WAVES
end

-- ============================================================================
-- 动态难度调整(根据玩家血量)
-- ============================================================================
function WM.UpdateDifficulty(playerHpRatio)
    if playerHpRatio > 0.7 then
        WM.difficultyMod = 1.1  -- 血量充足, 略增难度
    elseif playerHpRatio > 0.4 then
        WM.difficultyMod = 1.0  -- 正常
    elseif playerHpRatio > 0.2 then
        WM.difficultyMod = 0.85 -- 血量低, 降低难度
    else
        WM.difficultyMod = 0.7  -- 快死了, 大幅降低
    end
end

-- ============================================================================
-- 获取当前波次的敌人数量(含动态调整)
-- ============================================================================
function WM.GetEnemyCount()
    local wave = WM.GetCurrentWave()
    if not wave then return 8 end
    return math.max(3, math.floor(wave.enemyCount * WM.difficultyMod))
end

-- ============================================================================
-- 根据权重随机选择敌人类型
-- ============================================================================
function WM.RollEnemyType()
    local wave = WM.GetCurrentWave()
    if not wave then return "patrol" end

    local w = wave.weights
    local total = (w.patrol or 0) + (w.sentry or 0) + (w.rusher or 0) + (w.heavy or 0)
    if total <= 0 then return "patrol" end

    local roll = math.random(1, total)
    if roll <= (w.patrol or 0) then return "patrol" end
    roll = roll - (w.patrol or 0)
    if roll <= (w.sentry or 0) then return "sentry" end
    roll = roll - (w.sentry or 0)
    if roll <= (w.rusher or 0) then return "rusher" end
    return "heavy"
end

-- ============================================================================
-- HP/伤害倍率
-- ============================================================================
function WM.GetHpMult()
    local wave = WM.GetCurrentWave()
    return wave and wave.hpMult or 1.0
end

function WM.GetDmgMult()
    local wave = WM.GetCurrentWave()
    return wave and wave.dmgMult or 1.0
end

-- ============================================================================
-- 波次清除通知
-- ============================================================================
function WM.OnEnemyKilled()
    WM.waveKills = WM.waveKills + 1
    WM.totalKills = WM.totalKills + 1
end

function WM.CheckWaveCleared(enemyCount)
    if WM.phase ~= WM.PHASE_COMBAT and WM.phase ~= WM.PHASE_BOSS then
        return false
    end

    -- Boss波: Boss死了才算清除
    if WM.phase == WM.PHASE_BOSS then
        if WM.boss and WM.boss.hp <= 0 then
            return true
        end
        return enemyCount <= 0 and (WM.boss == nil or WM.boss.hp <= 0)
    end

    return enemyCount <= 0
end

-- ============================================================================
-- 进入下一阶段
-- ============================================================================
function WM.OnWaveCleared()
    if WM.phase == WM.PHASE_BOSS then
        -- Boss被击败 → 胜利
        WM.phase = WM.PHASE_VICTORY
        WM.phaseTimer = 0
        return
    end

    WM.phase = WM.PHASE_CLEARED
    WM.phaseTimer = 2.0  -- 展示"波次清除"2秒
end

function WM.AdvanceToReward()
    local wave = WM.GetCurrentWave()
    if not wave then return end

    if wave.rewardType == "choice" then
        WM.phase = WM.PHASE_REWARD
        WM.GenerateRewardChoices()
        WM.selectedReward = 1
        WM.rewardConfirmed = false
    elseif wave.rewardType == "supply" then
        WM.phase = WM.PHASE_REWARD
        WM.GenerateSupplyReward()
        WM.selectedReward = 1
        WM.rewardConfirmed = false
    else
        -- 无奖励, 直接过渡
        WM.StartTransition()
    end
end

function WM.StartTransition()
    WM.phase = WM.PHASE_TRANSIT
    WM.transitPhase = "fade_out"
    WM.transitAlpha = 0
end

function WM.AdvanceWave()
    WM.currentWave = WM.currentWave + 1
    WM.waveKills = 0
    WM.waveStartTime = WM.totalTime

    local wave = WM.GetCurrentWave()
    if wave and wave.type == "boss" then
        WM.phase = WM.PHASE_BOSS
    else
        WM.phase = WM.PHASE_COMBAT
    end

    WM.transitPhase = "fade_in"
    WM.transitAlpha = 255
end

-- ============================================================================
-- 奖励生成
-- ============================================================================
function WM.GenerateRewardChoices()
    WM.rewardChoices = {}
    local pool = {}
    for i, r in ipairs(WM.REWARD_POOL) do
        table.insert(pool, i)
    end
    -- 随机选3个不重复
    for i = #pool, 2, -1 do
        local j = math.random(1, i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    for i = 1, math.min(3, #pool) do
        table.insert(WM.rewardChoices, WM.REWARD_POOL[pool[i]])
    end
end

function WM.GenerateSupplyReward()
    -- 补给: 固定给弹药+血
    WM.rewardChoices = {
        { id = "supply_ammo", name = "石弹补给", desc = "+25 弹药",
          icon = "ammo", apply = function(p) p.totalAmmo = p.totalAmmo + 25 end },
        { id = "supply_heal", name = "森林草药", desc = "回复 30 HP",
          icon = "health", apply = function(p) p.hp = math.min(p.maxHp, p.hp + 30) end },
    }
    -- 补给型自动全选(不需要选择)
end

function WM.ApplyReward(index, player)
    if index < 1 or index > #WM.rewardChoices then return end
    local reward = WM.rewardChoices[index]
    if not reward then return end

    reward.apply(player)

    -- 武器modifier特殊处理
    if reward.id == "dmg_up" then
        WM.weaponMods.bonusDamage = WM.weaponMods.bonusDamage + 8
    elseif reward.id == "mag_up" then
        WM.weaponMods.bonusMagSize = WM.weaponMods.bonusMagSize + 4
    elseif reward.id == "fire_rate" then
        WM.weaponMods.fireRateReduction = WM.weaponMods.fireRateReduction + 0.03
    end
end

function WM.ApplyAllSupply(player)
    for _, reward in ipairs(WM.rewardChoices) do
        reward.apply(player)
    end
end

-- ============================================================================
-- 过渡动画更新
-- ============================================================================
function WM.UpdateTransition(dt)
    local speed = 400  -- alpha/秒

    if WM.transitPhase == "fade_out" then
        WM.transitAlpha = WM.transitAlpha + speed * dt
        if WM.transitAlpha >= 255 then
            WM.transitAlpha = 255
            WM.transitPhase = "hold"
            WM.phaseTimer = 0.3  -- 全黑保持0.3秒
        end
    elseif WM.transitPhase == "hold" then
        WM.phaseTimer = WM.phaseTimer - dt
        if WM.phaseTimer <= 0 then
            -- 先推进波次(让新波次数据生效)
            WM.AdvanceWave()
            -- 再执行回调(重建地图、生成敌人等使用新波次数据)
            if WM.transitCallback then
                WM.transitCallback()
                WM.transitCallback = nil
            end
        end
    elseif WM.transitPhase == "fade_in" then
        WM.transitAlpha = WM.transitAlpha - speed * dt
        if WM.transitAlpha <= 0 then
            WM.transitAlpha = 0
            WM.transitPhase = "none"
            -- 如果仍在TRANSIT阶段(初始启动), 进入战斗
            if WM.phase == WM.PHASE_TRANSIT then
                local wave = WM.GetCurrentWave()
                if wave and wave.type == "boss" then
                    WM.phase = WM.PHASE_BOSS
                else
                    WM.phase = WM.PHASE_COMBAT
                end
            end
        end
    end
end

-- ============================================================================
-- Boss 数据
-- ============================================================================
WM.BOSS_DATA = {
    name = "大灰狼首领",
    hp = 600,
    speed = 50,
    damage = 30,
    radius = 24,
    color = {180, 40, 40},
    sightRange = 400,
    attackRange = 350,
    attackRate = 0.6,
    bulletSpeed = 300,
    -- 特殊行为
    summonInterval = 8.0,   -- 每8秒召唤小兵
    summonCount = 2,         -- 每次召唤2个
    chargeSpeed = 280,       -- 冲锋速度
    chargeCooldown = 6.0,    -- 冲锋冷却
    -- 新攻击模式
    shotgunPellets = 5,      -- 散弹弹丸数
    shotgunSpread = 0.5,     -- 散弹扇形角度
    spinBullets = 8,         -- 旋转弹幕每轮弹数
    spinInterval = 0.3,      -- 旋转弹幕发射间隔
    shieldCooldown = 10.0,   -- 护盾冷却
    shieldDuration = 3.0,    -- 护盾持续
}

function WM.CreateBoss(x, y)
    local bd = WM.BOSS_DATA
    WM.boss = {
        x = x, y = y,
        typeKey = "boss",
        hp = bd.hp,
        maxHp = bd.hp,
        radius = bd.radius,
        speed = bd.speed,
        damage = bd.damage,
        sightRange = bd.sightRange,
        attackRange = bd.attackRange,
        attackRate = bd.attackRate,
        bulletSpeed = bd.bulletSpeed,
        color = {bd.color[1], bd.color[2], bd.color[3]},
        state = "idle",
        angle = 0,
        fireTimer = 0,
        alertTimer = 0,
        patrolOriginX = x,
        patrolOriginY = y,
        patrolAngle = 0,
        patrolTimer = 0,
        hitFlashTimer = 0,
        -- Boss专属
        isBoss = true,
        summonTimer = bd.summonInterval,
        chargeTimer = bd.chargeCooldown,
        isCharging = false,
        chargeTargetX = 0,
        chargeTargetY = 0,
        chargeDuration = 0,
        phaseIndex = 1,  -- Boss阶段(根据血量)
        -- 新攻击模式
        attackPattern = "single",  -- 当前攻击模式(会随阶段变化)
        shotgunPellets = bd.shotgunPellets,
        shotgunSpread = bd.shotgunSpread,
        spinTimer = 0,             -- 旋转弹幕计时
        spinAngle = 0,             -- 旋转弹幕当前角度
        isSpinning = false,        -- 是否正在释放旋转弹幕
        spinRounds = 0,            -- 剩余旋转轮数
        shieldTimer = bd.shieldCooldown,
        shieldActive = false,
        shieldDuration = 0,
        armor = 0,
    }
    return WM.boss
end

-- ============================================================================
-- Boss 阶段(根据血量百分比)
-- ============================================================================
function WM.GetBossPhase(boss)
    local ratio = boss.hp / boss.maxHp
    if ratio > 0.6 then return 1 end     -- 阶段1: >60%
    if ratio > 0.3 then return 2 end     -- 阶段2: 30-60% (更激进)
    return 3                              -- 阶段3: <30% (狂暴)
end

function WM.UpdateBossBehavior(boss, dt, playerX, playerY)
    if not boss or boss.hp <= 0 then return nil end

    local phase = WM.GetBossPhase(boss)
    boss.phaseIndex = phase
    local bd = WM.BOSS_DATA

    -- 攻击模式随阶段变化
    if phase == 1 then
        boss.attackPattern = "single"
    elseif phase == 2 then
        boss.attackPattern = "shotgun"  -- 阶段2: 散弹
    else
        boss.attackPattern = "shotgun"  -- 阶段3: 散弹+旋转弹幕
    end

    -- 召唤小兵
    boss.summonTimer = boss.summonTimer - dt
    local summonInterval = bd.summonInterval
    if phase >= 2 then summonInterval = summonInterval * 0.7 end
    if phase >= 3 then summonInterval = summonInterval * 0.5 end

    local summoned = nil
    if boss.summonTimer <= 0 then
        boss.summonTimer = summonInterval
        local count = bd.summonCount
        if phase >= 3 then count = count + 1 end
        summoned = { count = count }
    end

    -- 冲锋攻击
    boss.chargeTimer = boss.chargeTimer - dt
    if boss.chargeTimer <= 0 and not boss.isCharging and not boss.isSpinning then
        local dx = playerX - boss.x
        local dy = playerY - boss.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < 300 and dist > 60 then
            boss.isCharging = true
            boss.chargeTargetX = playerX
            boss.chargeTargetY = playerY
            boss.chargeDuration = 0.6
            boss.chargeTimer = bd.chargeCooldown
            if phase >= 2 then boss.chargeTimer = boss.chargeTimer * 0.7 end
        end
    end

    -- 执行冲锋
    local chargeImpact = nil
    if boss.isCharging then
        boss.chargeDuration = boss.chargeDuration - dt
        local angle = math.atan(boss.chargeTargetY - boss.y, boss.chargeTargetX - boss.x)
        local spd = bd.chargeSpeed
        if phase >= 3 then spd = spd * 1.3 end
        boss.x = boss.x + math.cos(angle) * spd * dt
        boss.y = boss.y + math.sin(angle) * spd * dt
        if boss.chargeDuration <= 0 then
            boss.isCharging = false
            -- 冲锋结束释放冲击波(阶段2+)
            if phase >= 2 then
                chargeImpact = { x = boss.x, y = boss.y, radius = 60, damage = 15 }
            end
        end
    end

    -- 旋转弹幕(阶段3专属)
    local spinBullets = nil
    if phase >= 3 and not boss.isSpinning and not boss.isCharging then
        boss.spinTimer = boss.spinTimer - dt
        if boss.spinTimer <= 0 then
            boss.isSpinning = true
            boss.spinRounds = 5  -- 旋转5轮
            boss.spinTimer = bd.spinInterval
            boss.spinAngle = boss.spinAngle or 0
        end
    end
    if boss.isSpinning then
        boss.spinTimer = boss.spinTimer - dt
        if boss.spinTimer <= 0 then
            boss.spinTimer = bd.spinInterval
            boss.spinRounds = boss.spinRounds - 1
            -- 发射一圈均匀分布的子弹
            local n = bd.spinBullets
            spinBullets = {}
            for p = 1, n do
                local a = boss.spinAngle + (p - 1) * (math.pi * 2 / n)
                table.insert(spinBullets, {
                    x = boss.x + math.cos(a) * (boss.radius + 4),
                    y = boss.y + math.sin(a) * (boss.radius + 4),
                    vx = math.cos(a) * bd.bulletSpeed * 0.8,
                    vy = math.sin(a) * bd.bulletSpeed * 0.8,
                    damage = math.floor(bd.damage * 0.6),
                })
            end
            boss.spinAngle = boss.spinAngle + 0.3  -- 每轮旋转偏移
            if boss.spinRounds <= 0 then
                boss.isSpinning = false
                boss.spinTimer = 5.0  -- 旋转弹幕冷却
            end
        end
    end

    -- 护盾(阶段3: 周期性获得护甲)
    if phase >= 3 then
        if not boss.shieldActive then
            boss.shieldTimer = boss.shieldTimer - dt
            if boss.shieldTimer <= 0 then
                boss.shieldActive = true
                boss.shieldDuration = bd.shieldDuration
                boss.armor = 0.5  -- 50%减伤
            end
        else
            boss.shieldDuration = boss.shieldDuration - dt
            if boss.shieldDuration <= 0 then
                boss.shieldActive = false
                boss.shieldTimer = bd.shieldCooldown
                boss.armor = 0
            end
        end
    end

    -- 攻击频率随阶段提高
    if phase >= 2 then
        boss.attackRate = bd.attackRate * 0.7
    end
    if phase >= 3 then
        boss.attackRate = bd.attackRate * 0.5
        -- 狂暴视觉: 颜色变化
        local pulse = math.sin(WM.totalTime * 8) * 0.3 + 0.7
        boss.color[1] = math.floor(220 * pulse)
        boss.color[2] = math.floor(40 * pulse)
        boss.color[3] = math.floor(40 * pulse)
    end

    return summoned, chargeImpact, spinBullets
end

-- ============================================================================
-- 更新主循环
-- ============================================================================
function WM.Update(dt)
    WM.totalTime = WM.totalTime + dt

    -- 过渡动画
    if WM.transitPhase ~= "none" then
        WM.UpdateTransition(dt)
    end

    -- 清除展示倒计时
    if WM.phase == WM.PHASE_CLEARED then
        WM.phaseTimer = WM.phaseTimer - dt
        if WM.phaseTimer <= 0 then
            -- 进入出口阶段(main.lua 负责生成出口瓦片)
            WM.phase = WM.PHASE_EXIT_OPEN
            WM.exitReady = false  -- 等待 main.lua 调用 SpawnExit 设置
            WM.walkoutTimer = 0
        end
    end

    -- 走出动画倒计时
    if WM.phase == WM.PHASE_WALKOUT then
        WM.walkoutTimer = WM.walkoutTimer - dt
        if WM.walkoutTimer <= 0 then
            -- 走出动画结束 → 进入奖励
            WM.AdvanceToReward()
        end
    end
end

return WM
