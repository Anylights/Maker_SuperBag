-- ============================================================================
-- 背包数据定义模块
-- 圣物模板、石板模板、Combo规则、稀有度定义
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
-- 石板模板类型
-- ============================================================================
M.TABLET_MASKS = {
    -- 十字: 上下左右4格 (相对偏移)
    cross = {
        name = "邻接十字",
        offsets = {{0, -1}, {0, 1}, {-1, 0}, {1, 0}},
    },
    -- 九宫格: 3x3 周围8格
    square3 = {
        name = "九宫格",
        offsets = {
            {-1, -1}, {0, -1}, {1, -1},
            {-1, 0},           {1, 0},
            {-1, 1},  {0, 1},  {1, 1},
        },
    },
    -- 横条: 同行左右各2格
    row = {
        name = "横条",
        offsets = {{-2, 0}, {-1, 0}, {1, 0}, {2, 0}},
    },
    -- 竖条: 同列上下各2格
    col = {
        name = "竖条",
        offsets = {{0, -2}, {0, -1}, {0, 1}, {0, 2}},
    },
    -- 对角: 四个对角格
    diagonal = {
        name = "角扇区",
        offsets = {{-1, -1}, {1, -1}, {-1, 1}, {1, 1}},
    },
}

-- ============================================================================
-- 圣物模板 (MVP: 24个)
-- ============================================================================
M.ARTIFACT_TEMPLATES = {
    -- ========== 1x1 小型数值圣物 ==========
    {
        id = "a_bullet_core",
        name = "弹芯强化",
        rarity = 1, sizeW = 1, sizeH = 1,
        tags = {"Projectile"},
        baseStats = {damage = 5},
        growthStats = {damage = 2},
        desc = "子弹伤害+5",
        icon = "bullet",
    },
    {
        id = "a_quick_hands",
        name = "快手",
        rarity = 1, sizeW = 1, sizeH = 1,
        tags = {"Projectile"},
        baseStats = {fireRate = 0.03},
        growthStats = {fireRate = 0.01},
        desc = "射速提升",
        icon = "hands",
    },
    {
        id = "a_thick_skin",
        name = "厚皮",
        rarity = 1, sizeW = 1, sizeH = 1,
        tags = {"Survival"},
        baseStats = {maxHp = 15},
        growthStats = {maxHp = 5},
        desc = "最大生命+15",
        icon = "shield",
    },
    {
        id = "a_sprint_boots",
        name = "疾行靴",
        rarity = 1, sizeW = 1, sizeH = 1,
        tags = {"Mobility"},
        baseStats = {moveSpeed = 20},
        growthStats = {moveSpeed = 8},
        desc = "移速+20",
        icon = "boots",
    },
    {
        id = "a_lucky_coin",
        name = "幸运币",
        rarity = 1, sizeW = 1, sizeH = 1,
        tags = {"Economy"},
        baseStats = {lootBonus = 10},
        growthStats = {lootBonus = 5},
        desc = "掉落率+10%",
        icon = "coin",
    },
    {
        id = "a_crit_lens",
        name = "暴击镜",
        rarity = 1, sizeW = 1, sizeH = 1,
        tags = {"Crit"},
        baseStats = {critChance = 5},
        growthStats = {critChance = 2},
        desc = "暴击率+5%",
        icon = "lens",
    },

    -- ========== 1x2 常规圣物 ==========
    {
        id = "a_fire_rounds",
        name = "燃烧弹",
        rarity = 2, sizeW = 1, sizeH = 2,
        tags = {"Burn", "Projectile"},
        baseStats = {damage = 3, burnDamage = 8},
        growthStats = {damage = 1, burnDamage = 3},
        desc = "子弹附带燃烧,每秒造成8点伤害",
        icon = "fire",
    },
    {
        id = "a_frost_rounds",
        name = "冰冻弹",
        rarity = 2, sizeW = 1, sizeH = 2,
        tags = {"Frost", "Projectile"},
        baseStats = {damage = 2, slowAmount = 30},
        growthStats = {damage = 1, slowAmount = 5},
        desc = "子弹附带减速30%",
        icon = "frost",
    },
    {
        id = "a_shock_coil",
        name = "感电线圈",
        rarity = 2, sizeW = 1, sizeH = 2,
        tags = {"Shock"},
        baseStats = {shockChance = 20, shockDamage = 15},
        growthStats = {shockChance = 5, shockDamage = 5},
        desc = "20%概率感电,造成15伤害",
        icon = "coil",
    },
    {
        id = "a_mag_extend",
        name = "扩容弹匣",
        rarity = 2, sizeW = 1, sizeH = 2,
        tags = {"Projectile"},
        baseStats = {magSize = 6, reloadSpeed = 0.2},
        growthStats = {magSize = 2, reloadSpeed = 0.05},
        desc = "弹匣+6, 换弹加速",
        icon = "mag",
    },
    {
        id = "a_med_kit",
        name = "急救包",
        rarity = 2, sizeW = 1, sizeH = 2,
        tags = {"Survival"},
        baseStats = {hpRegen = 2, maxHp = 10},
        growthStats = {hpRegen = 0.5, maxHp = 5},
        desc = "每秒回复2HP,最大生命+10",
        icon = "medkit",
    },

    -- ========== 2x2 核心机制圣物 ==========
    {
        id = "a_explosive_rounds",
        name = "爆裂弹",
        rarity = 3, sizeW = 2, sizeH = 2,
        tags = {"Blast", "Projectile"},
        baseStats = {damage = 8, explosionRadius = 40, explosionDamage = 20},
        growthStats = {damage = 3, explosionDamage = 8},
        desc = "子弹命中后爆炸,对范围内敌人造成20伤害",
        icon = "bomb",
    },
    {
        id = "a_chain_lightning",
        name = "连锁闪电",
        rarity = 3, sizeW = 2, sizeH = 2,
        tags = {"Shock", "Shock"},
        baseStats = {chainCount = 2, chainDamage = 12},
        growthStats = {chainDamage = 4},
        desc = "感电弹射2个目标,每次12伤害",
        icon = "lightning",
    },
    {
        id = "a_blood_pact",
        name = "鲜血契约",
        rarity = 3, sizeW = 2, sizeH = 2,
        tags = {"Crit", "Survival"},
        baseStats = {critChance = 10, critDamage = 25, maxHp = -20},
        growthStats = {critChance = 3, critDamage = 10},
        desc = "暴击率+10%,暴伤+25%,但最大生命-20",
        icon = "blood",
    },
    {
        id = "a_drone",
        name = "攻击无人机",
        rarity = 3, sizeW = 2, sizeH = 2,
        tags = {"Companion"},
        baseStats = {droneDamage = 8, droneRate = 1.0},
        growthStats = {droneDamage = 3, droneRate = -0.1},
        desc = "召唤无人机自动攻击附近敌人",
        icon = "drone",
    },
    {
        id = "a_piercing_rail",
        name = "穿甲弹",
        rarity = 3, sizeW = 2, sizeH = 2,
        tags = {"Projectile", "Projectile"},
        baseStats = {damage = 10, pierce = 2},
        growthStats = {damage = 4},
        desc = "子弹可穿透2个敌人",
        icon = "rail",
    },

    -- ========== 2x3 大型机制件 ==========
    {
        id = "a_inferno_core",
        name = "炼狱核心",
        rarity = 4, sizeW = 2, sizeH = 3,
        tags = {"Burn", "Burn", "Blast"},
        baseStats = {burnDamage = 15, burnDuration = 1.0, explosionOnBurn = true},
        growthStats = {burnDamage = 5},
        desc = "燃烧持续+1秒,燃烧结束时爆炸",
        icon = "inferno",
    },
    {
        id = "a_frost_nova",
        name = "极寒脉冲",
        rarity = 4, sizeW = 2, sizeH = 3,
        tags = {"Frost", "Frost", "Blast"},
        baseStats = {frostNovaRadius = 60, frostNovaDamage = 25, slowAmount = 50},
        growthStats = {frostNovaDamage = 10},
        desc = "每10秒释放冰霜脉冲,冻结周围敌人",
        icon = "nova",
    },
    {
        id = "a_turret",
        name = "自动炮台",
        rarity = 4, sizeW = 2, sizeH = 3,
        tags = {"Companion", "Companion"},
        baseStats = {turretDamage = 12, turretRange = 200, turretRate = 0.5},
        growthStats = {turretDamage = 4},
        desc = "部署自动炮台,攻击范围内敌人",
        icon = "turret",
    },

    -- ========== 3x3 传奇核心件 ==========
    {
        id = "a_storm_caller",
        name = "风暴召唤者",
        rarity = 5, sizeW = 3, sizeH = 3,
        tags = {"Shock", "Shock", "Blast", "Blast"},
        baseStats = {stormInterval = 8, stormDamage = 50, stormRadius = 100},
        growthStats = {stormDamage = 20},
        desc = "每8秒召唤闪电风暴,对范围内敌人造成50伤害",
        icon = "storm",
    },
    {
        id = "a_phoenix",
        name = "不死鸟之羽",
        rarity = 5, sizeW = 3, sizeH = 3,
        tags = {"Burn", "Survival", "Survival"},
        baseStats = {revive = 1, burnAura = 10, maxHp = 30},
        growthStats = {burnAura = 5, maxHp = 10},
        desc = "死亡时原地复活(1次),身边持续燃烧敌人",
        icon = "phoenix",
    },

    -- ========== 额外补充 (达到24个) ==========
    {
        id = "a_ammo_belt",
        name = "弹药带",
        rarity = 1, sizeW = 1, sizeH = 1,
        tags = {"Projectile"},
        baseStats = {totalAmmo = 20},
        growthStats = {totalAmmo = 10},
        desc = "总弹药+20",
        icon = "belt",
    },
    {
        id = "a_scope",
        name = "瞄准镜",
        rarity = 2, sizeW = 1, sizeH = 2,
        tags = {"Crit", "Projectile"},
        baseStats = {critChance = 8, spread = -1},
        growthStats = {critChance = 3},
        desc = "暴击率+8%,散布减少",
        icon = "scope",
    },
    {
        id = "a_dash_unit",
        name = "冲刺模组",
        rarity = 3, sizeW = 2, sizeH = 2,
        tags = {"Mobility", "Mobility"},
        baseStats = {dashCooldown = -1.0, moveSpeed = 15},
        growthStats = {moveSpeed = 5},
        desc = "冲刺CD-1秒,移速+15",
        icon = "dash",
    },
}

-- ============================================================================
-- 石板模板 (MVP: 12个)
-- ============================================================================
M.TABLET_TEMPLATES = {
    {
        id = "t_atk_cross",
        name = "攻击十字",
        rarity = 2, sizeW = 1, sizeH = 1,
        maskType = "cross",
        bonusStats = {damage = 3},
        penaltyStats = nil,
        desc = "十字范围内圣物: 伤害+3",
        color = {255, 100, 80},
    },
    {
        id = "t_def_cross",
        name = "防御十字",
        rarity = 2, sizeW = 1, sizeH = 1,
        maskType = "cross",
        bonusStats = {maxHp = 8},
        penaltyStats = nil,
        desc = "十字范围内圣物: 最大生命+8",
        color = {80, 200, 120},
    },
    {
        id = "t_crit_cross",
        name = "暴击十字",
        rarity = 3, sizeW = 1, sizeH = 1,
        maskType = "cross",
        bonusStats = {critChance = 4},
        penaltyStats = {moveSpeed = -5},
        desc = "十字内暴击+4%, 但移速-5",
        color = {255, 80, 120},
    },
    {
        id = "t_burn_square",
        name = "灼烧方阵",
        rarity = 3, sizeW = 1, sizeH = 1,
        maskType = "square3",
        bonusStats = {burnDamage = 5},
        penaltyStats = nil,
        desc = "九宫格范围: 燃烧伤害+5",
        color = {255, 140, 40},
    },
    {
        id = "t_frost_square",
        name = "冰封方阵",
        rarity = 3, sizeW = 1, sizeH = 1,
        maskType = "square3",
        bonusStats = {slowAmount = 10},
        penaltyStats = nil,
        desc = "九宫格范围: 减速+10%",
        color = {80, 180, 255},
    },
    {
        id = "t_speed_row",
        name = "疾风横带",
        rarity = 2, sizeW = 1, sizeH = 1,
        maskType = "row",
        bonusStats = {fireRate = 0.02, moveSpeed = 10},
        penaltyStats = nil,
        desc = "同行圣物: 射速+, 移速+10",
        color = {120, 220, 255},
    },
    {
        id = "t_power_col",
        name = "力量纵带",
        rarity = 2, sizeW = 1, sizeH = 1,
        maskType = "col",
        bonusStats = {damage = 4},
        penaltyStats = nil,
        desc = "同列圣物: 伤害+4",
        color = {255, 180, 80},
    },
    {
        id = "t_glass_cannon",
        name = "玻璃大炮",
        rarity = 4, sizeW = 1, sizeH = 1,
        maskType = "square3",
        bonusStats = {damage = 8, critDamage = 15},
        penaltyStats = {maxHp = -10},
        desc = "九宫格: 伤害+8,暴伤+15%,但生命-10",
        color = {255, 60, 200},
    },
    {
        id = "t_regen_diagonal",
        name = "回生角石",
        rarity = 3, sizeW = 1, sizeH = 1,
        maskType = "diagonal",
        bonusStats = {hpRegen = 1.5},
        penaltyStats = nil,
        desc = "对角圣物: 每秒回复1.5HP",
        color = {80, 255, 160},
    },
    {
        id = "t_ammo_cross",
        name = "弹药十字",
        rarity = 2, sizeW = 1, sizeH = 1,
        maskType = "cross",
        bonusStats = {magSize = 3, reloadSpeed = 0.1},
        penaltyStats = nil,
        desc = "十字范围: 弹匣+3, 换弹加速",
        color = {220, 200, 80},
    },
    {
        id = "t_shock_row",
        name = "雷电横带",
        rarity = 3, sizeW = 1, sizeH = 1,
        maskType = "row",
        bonusStats = {shockChance = 8, shockDamage = 6},
        penaltyStats = {maxHp = -5},
        desc = "同行: 感电率+8%,感电伤害+6, 生命-5",
        color = {220, 220, 80},
    },
    {
        id = "t_blast_col",
        name = "爆破纵带",
        rarity = 3, sizeW = 1, sizeH = 1,
        maskType = "col",
        bonusStats = {explosionDamage = 10, explosionRadius = 10},
        penaltyStats = nil,
        desc = "同列: 爆炸伤害+10, 爆炸范围+10",
        color = {255, 100, 60},
    },
}

-- ============================================================================
-- Combo (组合技) 模板 (MVP: 10条)
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
            {desc = "移速+15%", moveSpeedPercent = 15},
            {desc = "移速+25%, 冲刺后2秒+20%伤害", moveSpeedPercent = 25, dashDamageBonus = 20},
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
-- 背包初始配置
-- ============================================================================
M.GRID_COLS = 6
M.GRID_ROWS = 6
M.MAX_COLS = 8
M.MAX_ROWS = 8
M.CELL_SIZE = 48      -- UI 绘制时每格的像素大小

-- ============================================================================
-- 工具: 根据ID查找模板
-- ============================================================================
function M.FindArtifactTemplate(id)
    for _, t in ipairs(M.ARTIFACT_TEMPLATES) do
        if t.id == id then return t end
    end
    return nil
end

function M.FindTabletTemplate(id)
    for _, t in ipairs(M.TABLET_TEMPLATES) do
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

--- 随机选择一个圣物模板
function M.RandomArtifactTemplate(maxRarity)
    local pool = M.GetArtifactsByRarity(maxRarity or 5)
    if #pool == 0 then return nil end
    return pool[math.random(1, #pool)]
end

--- 随机选择一个石板模板
function M.RandomTabletTemplate()
    if #M.TABLET_TEMPLATES == 0 then return nil end
    return M.TABLET_TEMPLATES[math.random(1, #M.TABLET_TEMPLATES)]
end

return M
