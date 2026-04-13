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
WM.PHASE_REWARD    = "reward"     -- 选择奖励
WM.PHASE_TRANSIT   = "transit"    -- 过渡到下一波(地图重生中)
WM.PHASE_BOSS      = "boss"       -- Boss战
WM.PHASE_VICTORY   = "victory"    -- 全部通关

-- ============================================================================
-- 波次定义 (7波 + Boss)
-- ============================================================================
-- 每波包含: 类型、敌人数量系数、敌人类型权重、地图参数、奖励类型
WM.WAVES = {
    -- Wave 1: 新手引导 (只有巡逻兵, 少量)
    {
        name = "鸭巢外围",
        desc = "清除外围哨所的敌人",
        type = "combat",
        enemyCount = 6,
        rooms = 8,
        mapSize = {cols = 30, rows = 22},
        weights = { patrol = 100, sentry = 0, rusher = 0 },
        hpMult = 0.8,
        dmgMult = 0.7,
        rewardType = "choice",  -- 三选一奖励
    },
    -- Wave 2: 引入哨兵
    {
        name = "地下通道",
        desc = "穿越地下防御通道",
        type = "combat",
        enemyCount = 9,
        rooms = 10,
        mapSize = {cols = 35, rows = 25},
        weights = { patrol = 60, sentry = 40, rusher = 0 },
        hpMult = 1.0,
        dmgMult = 0.8,
        rewardType = "supply",  -- 补给(弹药+血)
    },
    -- Wave 3: 引入冲锋者
    {
        name = "补给仓库",
        desc = "攻占敌方补给点",
        type = "combat",
        enemyCount = 11,
        rooms = 10,
        mapSize = {cols = 35, rows = 25},
        weights = { patrol = 40, sentry = 30, rusher = 30 },
        hpMult = 1.0,
        dmgMult = 1.0,
        rewardType = "choice",
    },
    -- Wave 4: 精英波 (强化敌人, 少量)
    {
        name = "精英防线",
        desc = "遭遇精锐守卫!",
        type = "elite",
        enemyCount = 7,
        rooms = 8,
        mapSize = {cols = 30, rows = 22},
        weights = { patrol = 20, sentry = 40, rusher = 40 },
        hpMult = 1.8,
        dmgMult = 1.4,
        rewardType = "choice",
    },
    -- Wave 5: 大规模战斗
    {
        name = "核心区域",
        desc = "深入鸭巢核心",
        type = "combat",
        enemyCount = 14,
        rooms = 12,
        mapSize = {cols = 40, rows = 30},
        weights = { patrol = 35, sentry = 35, rusher = 30 },
        hpMult = 1.2,
        dmgMult = 1.1,
        rewardType = "supply",
    },
    -- Wave 6: 高难度混合
    {
        name = "指挥中心",
        desc = "摧毁敌军指挥系统",
        type = "combat",
        enemyCount = 16,
        rooms = 12,
        mapSize = {cols = 40, rows = 30},
        weights = { patrol = 30, sentry = 30, rusher = 40 },
        hpMult = 1.4,
        dmgMult = 1.3,
        rewardType = "choice",
    },
    -- Wave 7: Boss前哨
    {
        name = "机密实验室",
        desc = "最后的防线...",
        type = "elite",
        enemyCount = 10,
        rooms = 10,
        mapSize = {cols = 35, rows = 25},
        weights = { patrol = 20, sentry = 30, rusher = 50 },
        hpMult = 1.6,
        dmgMult = 1.5,
        rewardType = "supply",
    },
    -- Wave 8: Boss战
    {
        name = "鸭巢之主",
        desc = "击败最终Boss!",
        type = "boss",
        enemyCount = 4,  -- 少量小兵 + Boss
        rooms = 6,
        mapSize = {cols = 25, rows = 20},
        weights = { patrol = 50, sentry = 50, rusher = 0 },
        hpMult = 1.0,
        dmgMult = 1.0,
        rewardType = "none",
    },
}

-- ============================================================================
-- 奖励定义
-- ============================================================================
WM.REWARD_POOL = {
    -- 每个奖励: {id, name, desc, apply}
    { id = "ammo_pack",   name = "弹药补给",   desc = "+30 弹药",
      icon = "ammo", apply = function(p) p.totalAmmo = p.totalAmmo + 30 end },
    { id = "heal_kit",    name = "急救包",     desc = "回复 40 HP",
      icon = "health", apply = function(p) p.hp = math.min(p.maxHp, p.hp + 40) end },
    { id = "max_hp_up",   name = "强化体质",   desc = "最大HP +15",
      icon = "shield", apply = function(p) p.maxHp = p.maxHp + 15; p.hp = p.hp + 15 end },
    { id = "dmg_up",      name = "穿甲弹头",   desc = "伤害 +8",
      icon = "damage", apply = function(p) end },  -- 通过weapon modifier实现
    { id = "speed_up",    name = "轻量装甲",   desc = "移速 +20",
      icon = "speed", apply = function(p) p.speed = p.speed + 20 end },
    { id = "mag_up",      name = "扩容弹匣",   desc = "弹匣 +4",
      icon = "mag", apply = function(p) end },  -- 通过weapon modifier实现
    { id = "fire_rate",   name = "快速扳机",   desc = "射速提升",
      icon = "rate", apply = function(p) end },
    { id = "full_ammo",   name = "弹药箱",     desc = "弹药全满",
      icon = "ammo", apply = function(p) p.totalAmmo = p.totalAmmo + 60 end },
    { id = "full_heal",   name = "医疗箱",     desc = "HP全满",
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
    local total = (w.patrol or 0) + (w.sentry or 0) + (w.rusher or 0)
    if total <= 0 then return "patrol" end

    local roll = math.random(1, total)
    if roll <= (w.patrol or 0) then return "patrol" end
    roll = roll - (w.patrol or 0)
    if roll <= (w.sentry or 0) then return "sentry" end
    return "rusher"
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
        { id = "supply_ammo", name = "弹药补给", desc = "+25 弹药",
          icon = "ammo", apply = function(p) p.totalAmmo = p.totalAmmo + 25 end },
        { id = "supply_heal", name = "战地急救", desc = "回复 30 HP",
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
    name = "鸭巢指挥官",
    hp = 500,
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

    -- 召唤小兵
    boss.summonTimer = boss.summonTimer - dt
    local summonInterval = WM.BOSS_DATA.summonInterval
    if phase >= 2 then summonInterval = summonInterval * 0.7 end
    if phase >= 3 then summonInterval = summonInterval * 0.5 end

    local summoned = nil
    if boss.summonTimer <= 0 then
        boss.summonTimer = summonInterval
        local count = WM.BOSS_DATA.summonCount
        if phase >= 3 then count = count + 1 end
        summoned = { count = count }
    end

    -- 冲锋攻击
    boss.chargeTimer = boss.chargeTimer - dt
    if boss.chargeTimer <= 0 and not boss.isCharging then
        local dx = playerX - boss.x
        local dy = playerY - boss.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < 300 and dist > 60 then
            boss.isCharging = true
            boss.chargeTargetX = playerX
            boss.chargeTargetY = playerY
            boss.chargeDuration = 0.6
            boss.chargeTimer = WM.BOSS_DATA.chargeCooldown
            if phase >= 2 then boss.chargeTimer = boss.chargeTimer * 0.7 end
        end
    end

    -- 执行冲锋
    if boss.isCharging then
        boss.chargeDuration = boss.chargeDuration - dt
        local angle = math.atan(boss.chargeTargetY - boss.y, boss.chargeTargetX - boss.x)
        local spd = WM.BOSS_DATA.chargeSpeed
        if phase >= 3 then spd = spd * 1.3 end
        boss.x = boss.x + math.cos(angle) * spd * dt
        boss.y = boss.y + math.sin(angle) * spd * dt
        if boss.chargeDuration <= 0 then
            boss.isCharging = false
        end
    end

    -- 攻击频率随阶段提高
    if phase >= 2 then
        boss.attackRate = WM.BOSS_DATA.attackRate * 0.7
    end
    if phase >= 3 then
        boss.attackRate = WM.BOSS_DATA.attackRate * 0.5
        -- 狂暴视觉: 颜色变化
        local pulse = math.sin(WM.totalTime * 8) * 0.3 + 0.7
        boss.color[1] = math.floor(220 * pulse)
        boss.color[2] = math.floor(40 * pulse)
        boss.color[3] = math.floor(40 * pulse)
    end

    return summoned
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
            WM.AdvanceToReward()
        end
    end
end

return WM
