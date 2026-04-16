-- ============================================================================
-- 背包数据定义模块
-- 圣物模板、Combo规则、稀有度定义、俄罗斯方块形状
-- ============================================================================

local M = {}

-- ============================================================================
-- 稀有度定义
-- ============================================================================
M.RARITY = {
    COMMON   = 1,  -- 白
    UNCOMMON = 2,  -- 绿
    RARE     = 3,  -- 蓝
    EPIC     = 4,  -- 紫
    LEGENDARY = 5, -- 金
}

M.RARITY_NAMES = {
    [1] = "普通", [2] = "优秀", [3] = "稀有", [4] = "史诗", [5] = "传奇",
}

M.RARITY_COLORS = {
    [1] = {200, 200, 200},  -- 白
    [2] = {80, 200, 80},    -- 绿
    [3] = {80, 140, 255},   -- 蓝
    [4] = {180, 80, 255},   -- 紫
    [5] = {255, 200, 40},   -- 金
}

--- 等级颜色(LV.1~LV.8+)
M.LEVEL_COLORS = {
    [1] = {180, 180, 180},  -- 灰白
    [2] = {120, 220, 120},  -- 浅绿
    [3] = {80, 180, 255},   -- 天蓝
    [4] = {160, 120, 255},  -- 紫蓝
    [5] = {255, 160, 40},   -- 橙色
    [6] = {255, 80, 80},    -- 红色
    [7] = {255, 50, 200},   -- 品红
    [8] = {255, 220, 60},   -- 金色
}

M.RARITY_BG_COLORS = {
    [1] = {60, 60, 60},
    [2] = {30, 60, 30},
    [3] = {30, 40, 70},
    [4] = {50, 25, 70},
    [5] = {60, 50, 20},
}

-- ============================================================================
-- 标签定义 (Combo 基础)
-- ============================================================================
M.TAGS = {
    Burn = "燃烧",
    Frost = "冰冻",
    Shock = "感电",
    Blast = "爆炸",
    Projectile = "弹道",
    Companion = "召唤",
    Crit = "暴击",
    Survival = "生存",
    Mobility = "机动",
    Economy = "资源",
}

M.TAG_COLORS = {
    Burn = {255, 120, 40},
    Frost = {80, 180, 255},
    Shock = {200, 200, 60},
    Blast = {255, 80, 60},
    Projectile = {180, 220, 255},
    Companion = {120, 220, 120},
    Crit = {255, 60, 100},
    Survival = {80, 220, 160},
    Mobility = {100, 200, 255},
    Economy = {255, 220, 80},
}

-- ============================================================================
-- 圣物模板 (俄罗斯方块形状)
-- cells: 格子偏移数组 {{col_off, row_off}, ...}，基准点(0,0)
-- boundW/boundH: 形状包围盒尺寸(用于旋转计算)
-- ============================================================================
M.ARTIFACT_TEMPLATES = {
    -- ========== 稀有度1: 单格 (monomino) ==========
    {
        id = "a_bullet_core",
        name = "弹芯强化",
        rarity = 1,
        cells = {{0,0}}, boundW = 1, boundH = 1,
        tags = {"Projectile"},
        baseStats = {damage = 7},
        growthStats = {damage = 3},
        desc = "子弹伤害+7",
        icon = "bullet",
    },
    {
        id = "a_quick_hands",
        name = "快手",
        rarity = 1,
        cells = {{0,0}}, boundW = 1, boundH = 1,
        tags = {"Projectile"},
        baseStats = {fireRate = 0.06},
        growthStats = {fireRate = 0.02},
        desc = "射速提升",
        icon = "hands",
    },
    {
        id = "a_thick_skin",
        name = "厚皮",
        rarity = 1,
        cells = {{0,0}}, boundW = 1, boundH = 1,
        tags = {"Survival"},
        baseStats = {maxHp = 25},
        growthStats = {maxHp = 8},
        desc = "最大生命+25",
        icon = "shield",
    },
    {
        id = "a_sprint_boots",
        name = "疾行靴",
        rarity = 1,
        cells = {{0,0}}, boundW = 1, boundH = 1,
        tags = {"Mobility"},
        baseStats = {moveSpeed = 12},
        growthStats = {moveSpeed = 4},
        desc = "移速+12",
        icon = "boots",
    },
    {
        id = "a_lucky_coin",
        name = "幸运币",
        rarity = 1,
        cells = {{0,0}}, boundW = 1, boundH = 1,
        tags = {"Economy"},
        baseStats = {rarityBoost = 5},
        growthStats = {rarityBoost = 2},
        desc = "掉落圣物时,更容易获得高稀有度",
        icon = "coin",
    },
    {
        id = "a_crit_lens",
        name = "暴击镜",
        rarity = 1,
        cells = {{0,0}}, boundW = 1, boundH = 1,
        tags = {"Crit"},
        baseStats = {critChance = 5},
        growthStats = {critChance = 2},
        desc = "暴击率+5%",
        icon = "lens",
    },
    {
        id = "a_ammo_belt",
        name = "弹药带",
        rarity = 1,
        cells = {{0,0}}, boundW = 1, boundH = 1,
        tags = {"Projectile"},
        baseStats = {totalAmmo = 20},
        growthStats = {totalAmmo = 10},
        desc = "总弹药+20",
        icon = "belt",
    },
    {
        id = "a_ammo_recycle",
        name = "回收弹头",
        rarity = 1,
        cells = {{0,0}}, boundW = 1, boundH = 1,
        tags = {"Projectile"},
        baseStats = {ammoRecycleChance = 15},
        growthStats = {ammoRecycleChance = 5},
        desc = "击中敌人15%概率回收1发弹药",
        icon = "recycle",
    },

    -- ========== 稀有度2(优秀): 2格 — 升级上限Lv4 ==========
    {
        id = "a_fire_rounds",
        name = "燃烧弹",
        rarity = 2,
        cells = {{0,0},{1,0}}, boundW = 2, boundH = 1,
        tags = {"Burn", "Projectile"},
        baseStats = {damage = 3, burnDamage = 12},
        growthStats = {damage = 2, burnDamage = 5},
        desc = "子弹附带燃烧,每秒造成12点伤害",
        icon = "fire",
    },
    {
        id = "a_frost_rounds",
        name = "冰冻弹",
        rarity = 2,
        cells = {{0,0},{0,1}}, boundW = 1, boundH = 2,
        tags = {"Frost", "Projectile"},
        baseStats = {damage = 4, slowAmount = 25},
        growthStats = {damage = 3, slowAmount = 8},
        desc = "子弹附带减速25%",
        icon = "frost",
    },
    {
        id = "a_shock_coil",
        name = "感电线圈",
        rarity = 2,
        cells = {{0,0},{1,0}}, boundW = 2, boundH = 1,
        tags = {"Shock"},
        baseStats = {shockChance = 25, shockDamage = 8},
        growthStats = {shockChance = 6, shockDamage = 3},
        desc = "25%概率触发链式闪电,弹射攻击附近敌人",
        icon = "coil",
    },
    {
        id = "a_mag_extend",
        name = "扩容弹匣",
        rarity = 2,
        cells = {{0,0},{0,1}}, boundW = 1, boundH = 2,
        tags = {"Projectile"},
        baseStats = {magSize = 10, reloadSpeed = 0.3},
        growthStats = {magSize = 5, reloadSpeed = 0.1},
        desc = "弹匣+10, 换弹加速",
        icon = "mag",
    },
    {
        id = "a_med_kit",
        name = "急救包",
        rarity = 2,
        cells = {{0,0},{1,0}}, boundW = 2, boundH = 1,
        tags = {"Survival"},
        baseStats = {hpRegen = 1, maxHp = 10},
        growthStats = {hpRegen = 0.5, maxHp = 5},
        desc = "每秒回复1HP,最大生命+10",
        icon = "medkit",
    },
    {
        id = "a_bounce_round",
        name = "弹跳弹",
        rarity = 2,
        cells = {{0,0},{0,1}}, boundW = 1, boundH = 2,
        tags = {"Projectile"},
        baseStats = {bounceCount = 2, damage = 4},
        growthStats = {bounceCount = 1, damage = 3},
        desc = "子弹撞墙反弹2次,继续追杀敌人",
        icon = "bounce",
    },
    {
        id = "a_scope",
        name = "瞄准镜",
        rarity = 2,
        cells = {{0,0},{1,0}}, boundW = 2, boundH = 1,
        tags = {"Crit", "Projectile"},
        baseStats = {critChance = 8, spread = -1},
        growthStats = {critChance = 4},
        desc = "暴击率+8%,散布减少",
        icon = "scope",
    },

    -- ========== 稀有度3(稀有): 3格 — 升级上限Lv6 ==========
    {
        id = "a_explosive_rounds",
        name = "爆裂弹",
        rarity = 3,
        cells = {{0,0},{1,0},{2,0}}, boundW = 3, boundH = 1,  -- 横三格
        tags = {"Blast", "Projectile"},
        baseStats = {damage = 10, explosionRadius = 55, explosionDamage = 30},
        growthStats = {damage = 4, explosionDamage = 12},
        desc = "子弹命中后爆炸,对范围内敌人造成30伤害",
        icon = "bomb",
    },
    {
        id = "a_chain_lightning",
        name = "连锁闪电",
        rarity = 3,
        cells = {{0,0},{1,0},{0,1}}, boundW = 2, boundH = 2,  -- L形
        tags = {"Shock", "Shock"},
        baseStats = {chainCount = 3, chainDamage = 10},
        growthStats = {chainDamage = 4},
        desc = "闪电链+3跳,每跳+10伤害",
        icon = "lightning",
    },
    {
        id = "a_blood_pact",
        name = "鲜血契约",
        rarity = 3,
        cells = {{0,0},{1,0},{1,1}}, boundW = 2, boundH = 2,  -- 反L形
        tags = {"Crit", "Survival"},
        baseStats = {critChance = 10, critDamage = 20, maxHp = -20},
        growthStats = {critChance = 3, critDamage = 8},
        desc = "暴击率+10%,暴伤+20%,但最大生命-20",
        icon = "blood",
    },
    {
        id = "a_drone",
        name = "攻击无人机",
        rarity = 3,
        cells = {{0,0},{0,1},{1,1}}, boundW = 2, boundH = 2,  -- 反L形
        tags = {"Companion"},
        baseStats = {droneDamage = 14, droneRate = 0.8},
        growthStats = {droneDamage = 5, droneRate = -0.08},
        desc = "召唤无人机自动攻击附近敌人",
        icon = "drone",
    },
    {
        id = "a_piercing_rail",
        name = "穿甲弹",
        rarity = 3,
        cells = {{0,0},{0,1},{0,2}}, boundW = 1, boundH = 3,  -- 竖三格
        tags = {"Projectile", "Projectile"},
        baseStats = {damage = 14, pierce = 3},
        growthStats = {damage = 5},
        desc = "子弹可穿透3个敌人",
        icon = "rail",
    },
    {
        id = "a_shotgun_mod",
        name = "散弹模组",
        rarity = 3,
        cells = {{0,0},{1,0},{2,0}}, boundW = 3, boundH = 1,  -- 横三格
        tags = {"Projectile", "Blast"},
        baseStats = {shotgunPellets = 3, damage = 4},
        growthStats = {shotgunPellets = 1, damage = 2},
        desc = "额外发射3颗散弹,火力覆盖更广",
        icon = "shotgun",
    },
    {
        id = "a_shield_gen",
        name = "能量护盾",
        rarity = 3,
        cells = {{0,0},{1,0},{0,1}}, boundW = 2, boundH = 2,  -- L形
        tags = {"Survival", "Survival"},
        baseStats = {shieldMax = 45, shieldRegen = 6},
        growthStats = {shieldMax = 18, shieldRegen = 3},
        desc = "生成45点能量护盾,每秒恢复6点",
        icon = "shield_gen",
    },
    {
        id = "a_dash_unit",
        name = "冲刺模组",
        rarity = 3,
        cells = {{1,0},{0,1},{1,1}}, boundW = 2, boundH = 2,  -- 反L形
        tags = {"Mobility", "Mobility"},
        baseStats = {dashCooldown = -1.0, moveSpeed = 8},
        growthStats = {moveSpeed = 3},
        desc = "冲刺CD-1秒,移速+8",
        icon = "dash",
    },

    -- ========== 稀有度4(史诗): 4格 — 升级上限Lv8 ==========
    {
        id = "a_inferno_core",
        name = "炼狱核心",
        rarity = 4,
        cells = {{0,0},{1,0},{2,0},{1,1}}, boundW = 3, boundH = 2,  -- T形
        tags = {"Burn", "Burn", "Blast"},
        baseStats = {burnDamage = 20, burnDuration = 1.0, explosionOnBurn = true},
        growthStats = {burnDamage = 8},
        desc = "燃烧持续+1秒,燃烧结束时爆炸",
        icon = "inferno",
    },
    {
        id = "a_frost_nova",
        name = "极寒脉冲",
        rarity = 4,
        cells = {{0,0},{1,0},{2,0},{3,0}}, boundW = 4, boundH = 1,  -- I形
        tags = {"Frost", "Frost", "Blast"},
        baseStats = {frostNovaRadius = 75, frostNovaDamage = 35, slowAmount = 35},
        growthStats = {frostNovaDamage = 12},
        desc = "每10秒释放冰霜脉冲,冻结周围敌人",
        icon = "nova",
    },
    {
        id = "a_turret",
        name = "自动炮台",
        rarity = 4,
        cells = {{0,0},{1,0},{0,1},{1,1}}, boundW = 2, boundH = 2,  -- O形
        tags = {"Companion", "Companion"},
        baseStats = {turretDamage = 10, turretRange = 190, turretRate = 0.6},
        growthStats = {turretDamage = 4},
        desc = "部署自动炮台,攻击范围内敌人",
        icon = "turret",
    },

    -- ========== 稀有度5(传奇): 5格 — 升级上限Lv10 ==========
    {
        id = "a_storm_caller",
        name = "风暴召唤者",
        rarity = 5,
        cells = {{0,0},{1,0},{2,0},{1,1},{1,2}}, boundW = 3, boundH = 3,  -- +形(十字)
        tags = {"Shock", "Shock", "Blast", "Blast"},
        baseStats = {stormInterval = 8, stormDamage = 35, stormRadius = 120},
        growthStats = {stormDamage = 12},
        desc = "每8秒召唤闪电风暴,对范围内敌人造成35伤害",
        icon = "storm",
    },
    {
        id = "a_phoenix",
        name = "不死鸟之羽",
        rarity = 5,
        cells = {{0,0},{1,0},{2,0},{0,1},{2,1}}, boundW = 3, boundH = 2,  -- U形
        tags = {"Burn", "Survival", "Survival"},
        baseStats = {revive = 1, burnAura = 15, maxHp = 40},
        growthStats = {burnAura = 6, maxHp = 12},
        desc = "死亡时原地复活(1次),身边持续燃烧敌人",
        icon = "phoenix",
    },
}

-- ============================================================================
-- Combo (组合技) 模板 (MVP: 10条) - 保持不变
-- ============================================================================
M.COMBO_TEMPLATES = {
    {
        id = "combo_ember",
        name = "余烬核心",
        tag = "Burn",
        thresholds = {2, 4, 6},
        effects = {
            {desc = "燃烧伤害+20%", burnDamagePercent = 20},
            {desc = "燃烧伤害+45%, 持续+1.5s", burnDamagePercent = 45, burnDuration = 1.5},
            {desc = "燃烧伤害+70%, 燃烧可传染", burnDamagePercent = 70, burnSpread = true},
        },
    },
    {
        id = "combo_polar",
        name = "极地锁链",
        tag = "Frost",
        thresholds = {2, 4, 6},
        effects = {
            {desc = "减速效果+15%", slowPercent = 15},
            {desc = "减速+30%, 冰冻几率10%", slowPercent = 30, freezeChance = 10},
            {desc = "减速+50%, 冰冻几率25%", slowPercent = 50, freezeChance = 25},
        },
    },
    {
        id = "combo_chain",
        name = "链式风暴",
        tag = "Shock",
        thresholds = {2, 4, 6},
        effects = {
            {desc = "感电弹射+1", chainBounce = 1},
            {desc = "感电弹射+2, 感电伤害+30%", chainBounce = 2, shockDamagePercent = 30},
            {desc = "感电弹射+3, 伤害+60%", chainBounce = 3, shockDamagePercent = 60},
        },
    },
    {
        id = "combo_iron_bloom",
        name = "铁焰绽放",
        tag = "Blast",
        thresholds = {2, 4},
        effects = {
            {desc = "爆炸半径+20%", blastRadiusPercent = 20},
            {desc = "爆炸半径+40%, 爆炸附带燃烧", blastRadiusPercent = 40, blastBurn = true},
        },
    },
    {
        id = "combo_sniper",
        name = "狙击律动",
        tag = "Crit",
        thresholds = {2, 4},
        effects = {
            {desc = "暴击伤害+20%", critDamageBonus = 20},
            {desc = "暴击伤害+40%, 暴击回弹药", critDamageBonus = 40, critRefundAmmo = true},
        },
    },
    {
        id = "combo_fortress",
        name = "堡垒意志",
        tag = "Survival",
        thresholds = {2, 4},
        effects = {
            {desc = "受伤减免10%", damageReduction = 10},
            {desc = "受伤减免20%, 低血量时+10%", damageReduction = 20, lowHpBonus = 10},
        },
    },
    {
        id = "combo_bullet_storm",
        name = "弹幕风暴",
        tag = "Projectile",
        thresholds = {2, 4, 6, 8},
        effects = {
            {desc = "射速+10%", fireRatePercent = 10},
            {desc = "射速+20%, 弹匣+15%", fireRatePercent = 20, magSizePercent = 15},
            {desc = "射速+30%, 弹匣+25%, 穿透+1", fireRatePercent = 30, magSizePercent = 25, pierce = 1},
            {desc = "射速+40%, 双发射击", fireRatePercent = 40, doubleFire = true},
        },
    },
    {
        id = "combo_wind_runner",
        name = "风行者",
        tag = "Mobility",
        thresholds = {2, 4},
        effects = {
            {desc = "移速+8%", moveSpeedPercent = 8},
            {desc = "移速+15%, 冲刺后2秒+15%伤害", moveSpeedPercent = 15, dashDamageBonus = 15},
        },
    },
    {
        id = "combo_companion",
        name = "战争机器",
        tag = "Companion",
        thresholds = {2, 4},
        effects = {
            {desc = "召唤物伤害+25%", companionDamagePercent = 25},
            {desc = "召唤物伤害+50%, 攻速+30%", companionDamagePercent = 50, companionRatePercent = 30},
        },
    },
    {
        id = "combo_fortune",
        name = "财运亨通",
        tag = "Economy",
        thresholds = {2, 4},
        effects = {
            {desc = "金币掉落+20%", goldDropPercent = 20},
            {desc = "金币+40%, 偶尔掉高稀有", goldDropPercent = 40, rareDropChance = true},
        },
    },
}

-- ============================================================================
-- 背包配置 (8x8)
-- ============================================================================
M.GRID_COLS = 8
M.GRID_ROWS = 8
M.MAX_COLS = 8
M.MAX_ROWS = 8
M.CELL_SIZE = 40      -- UI 绘制时每格的像素大小(8x8格子稍小些)

-- ============================================================================
-- 工具: 根据ID查找模板
-- ============================================================================
function M.FindArtifactTemplate(id)
    for _, t in ipairs(M.ARTIFACT_TEMPLATES) do
        if t.id == id then return t end
    end
    return nil
end

--- 根据稀有度过滤圣物模板
function M.GetArtifactsByRarity(maxRarity)
    local result = {}
    for _, t in ipairs(M.ARTIFACT_TEMPLATES) do
        if t.rarity <= maxRarity then
            table.insert(result, t)
        end
    end
    return result
end

--- 稀有度掉落权重 (数值越大越容易出)
M.RARITY_DROP_WEIGHTS = {
    [1] = 55,   -- 白色: 大量
    [2] = 30,   -- 绿色: 适量
    [3] = 12,   -- 蓝色: 稀少
    [4] = 2.5,  -- 紫色: 极稀有
    [5] = 0.5,  -- 金色: 传说级
}

--- 随机选择一个圣物模板(加权稀有度)
--- @param maxRarity number 最高可掉落稀有度
--- @param rarityBoost number|nil 稀有度提升值(百分比), 提升高稀有度权重, 随稀有度递减
function M.RandomArtifactTemplate(maxRarity, rarityBoost)
    maxRarity = maxRarity or 5
    rarityBoost = rarityBoost or 0
    -- 第一步: 按稀有度权重选出目标稀有度
    local weightSum = 0
    local tiers = {}
    for r = 1, maxRarity do
        local w = M.RARITY_DROP_WEIGHTS[r] or 0
        if w > 0 then
            -- 确认该稀有度有可用模板
            local hasAny = false
            for _, t in ipairs(M.ARTIFACT_TEMPLATES) do
                if t.rarity == r then hasAny = true; break end
            end
            if hasAny then
                -- rarityBoost: 提升高稀有度权重, 幅度随稀有度递减
                -- 白色不变, 绿色+boost*0.6, 蓝色+boost*0.35, 紫色+boost*0.15, 金色+boost*0.05
                if rarityBoost > 0 and r >= 2 then
                    local boostFactors = {[2] = 0.6, [3] = 0.35, [4] = 0.15, [5] = 0.05}
                    local factor = boostFactors[r] or 0.05
                    -- 按百分比提升原始权重, 最低提升1%的原始权重
                    local boost = w * math.max(0.01, rarityBoost * factor * 0.01)
                    w = w + boost
                end
                table.insert(tiers, { rarity = r, weight = w })
                weightSum = weightSum + w
            end
        end
    end
    if weightSum <= 0 then return nil end

    -- 加权随机选稀有度
    local roll = math.random() * weightSum
    local targetRarity = 1
    local acc = 0
    for _, tier in ipairs(tiers) do
        acc = acc + tier.weight
        if roll <= acc then
            targetRarity = tier.rarity
            break
        end
    end

    -- 第二步: 在该稀有度中均匀随机选模板
    local pool = {}
    for _, t in ipairs(M.ARTIFACT_TEMPLATES) do
        if t.rarity == targetRarity then
            table.insert(pool, t)
        end
    end
    if #pool == 0 then return nil end
    return pool[math.random(1, #pool)]
end

return M
