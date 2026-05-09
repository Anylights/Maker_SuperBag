local G = require("game_context")
local WM = require("wave_manager")
local Inv = require("inventory")
local InvUI = require("inventory_ui")

local Map = nil
local function getMap()
    if not Map then Map = require("map") end
    return Map
end
local Fx = nil
local function getFx()
    if not Fx then Fx = require("fx") end
    return Fx
end

local MI = nil  -- 延迟加载移动端输入模块
local function getMI()
    if not MI then MI = require("mobile_input") end
    return MI
end

local Combat = {}

function Combat.TryMelee()
    if G.player.meleeTimer > 0 then return end       -- 冷却中
    if G.player.meleeSwingTimer > 0 then return end   -- 正在挥击

    G.player.meleeSwingTimer = G.player.meleeSwingDur
    G.player.meleeTimer = G.player.meleeCooldown
    G.player.meleeHitDone = false
    G.PlaySfx(G.sndMeleeSwing, 0.4)
end

function Combat.TryShoot()
    if InvUI.isOpen then return end  -- 背包打开时禁止射击
    if G.player.reloading then return end
    if G.player.fireTimer > 0 then return end
    if G.player.ammo <= 0 then
        -- 自动换弹
        if G.player.totalAmmo > 0 then
            G.player.reloading = true
            local reloadSpeedBonus = Inv.GetStat("reloadSpeed", 0)
            G.player.reloadTimer = math.max(0.3, G.WEAPON.reloadTime - reloadSpeedBonus)
            G.PlaySfx(G.sndReload, 0.5)
        else
            -- 弹药全空 → 近战攻击
            Combat.TryMelee()
        end
        return
    end

    -- 应用背包散布加成(负值=更精准)
    local spreadBonus = Inv.GetStat("spread", 0)
    local effectiveSpread = math.max(0, G.WEAPON.spread + spreadBonus)

    -- 应用背包加成 + 波次奖励modifier
    local bonusDamage = Inv.GetStat("damage", 0) + WM.weaponMods.bonusDamage
    local bonusFireRate = Inv.GetStat("fireRate", 0) + WM.weaponMods.fireRateReduction

    -- 暴击判定
    local critChance = Inv.GetStat("critChance", 0)
    local isCrit = math.random(1, 100) <= critChance
    local finalDamage = G.WEAPON.damage + bonusDamage
    if isCrit then finalDamage = math.floor(finalDamage * 2) end

    -- 穿透次数(0=普通子弹击中即消失, >0=可穿透多个敌人)
    local pierceCount = math.floor(Inv.GetStat("pierce", 0))

    -- 弹跳次数(撞墙反弹)
    local bounceCount = math.floor(Inv.GetStat("bounceCount", 0))

    -- 感电属性(链式闪电)
    local shockChance = Inv.GetStat("shockChance", 0)
    local shockDamage = Inv.GetStat("shockDamage", 0)
    -- 链式闪电: 基础2跳 + 圣物chainCount + combo_chainBounce
    local chainCount = 2 + math.floor(Inv.GetStat("chainCount", 0)) + math.floor(Inv.GetStat("combo_chainBounce", 0))
    local chainRange = 120  -- 链式闪电搜索范围(像素)
    -- chainDamage 圣物加成(叠加到 shockDamage)
    local chainDmgBonus = Inv.GetStat("chainDamage", 0)
    shockDamage = shockDamage + chainDmgBonus
    -- combo 感电伤害百分比加成
    local shockDmgPercent = Inv.GetStat("combo_shockDamagePercent", 0)
    shockDamage = math.floor(shockDamage * (1.0 + shockDmgPercent / 100))

    -- 状态效果属性(从背包汇总)
    local burnDmg = Inv.GetStat("burnDamage", 0)
    local burnComboMult = 1.0 + (Inv.GetStat("combo_burnDamagePercent", 0) / 100)
    burnDmg = math.floor(burnDmg * burnComboMult)
    local burnDur = 2.0 + Inv.GetStat("combo_burnDurationBonus", 0)

    local slowAmt = Inv.GetStat("slowAmount", 0) + Inv.GetStat("combo_slowPercent", 0)
    local freezeChance = Inv.GetStat("combo_freezeChance", 0)  -- 来自combo_polar Lv2/Lv3

    local explRadius = Inv.GetStat("explosionRadius", 0)
    local explDamage = Inv.GetStat("explosionDamage", 0)
    local comboRadiusMult = 1.0 + (Inv.GetStat("combo_explosionRadiusPercent", 0) / 100)
    explRadius = math.floor(explRadius * comboRadiusMult)

    -- 散弹枪: 计算总弹丸数(1 + 额外散弹)
    local shotgunPellets = math.floor(Inv.GetStat("shotgunPellets", 0))
    local totalPellets = 1 + shotgunPellets
    local shotgunSpreadAngle = 0.5  -- 散弹扇形总角度(弧度, 约±28度)

    for pelletIdx = 1, totalPellets do
        -- 计算每颗弹丸的角度
        local pelletAngle
        if totalPellets == 1 then
            -- 单发: 原始散布
            local spreadRad = math.rad(effectiveSpread) * (math.random() - 0.5)
            pelletAngle = G.player.angle + spreadRad
        else
            -- 散弹: 均匀分布在扇形内 + 微小随机偏移
            local t = (pelletIdx - 1) / (totalPellets - 1)  -- 0~1
            local baseOffset = (t - 0.5) * shotgunSpreadAngle
            local jitter = (math.random() - 0.5) * 0.08  -- 微小抖动
            pelletAngle = G.player.angle + baseOffset + jitter
        end

        local bx = G.player.x + math.cos(pelletAngle) * (G.player.radius + 5)
        local by = G.player.y + math.sin(pelletAngle) * (G.player.radius + 5)

        -- 散弹伤害略低(防止过于imba)
        local pelletDamage = finalDamage
        if shotgunPellets > 0 then
            pelletDamage = math.max(1, math.floor(finalDamage * 0.7))
        end

        -- 计算子弹视觉类型 + 多层特效叠加
        -- bulletFx 保留为"主特效"用于命中粒子等回退路径；fxLayers 用于渲染叠加
        local bfx = "normal"
        local fxLayers = {}
        if shotgunPellets > 0 then bfx = "shotgun"; table.insert(fxLayers, "shotgun") end
        if bounceCount > 0 then bfx = "bounce"; table.insert(fxLayers, "bounce") end
        if pierceCount > 0 then bfx = "pierce"; table.insert(fxLayers, "pierce") end
        if slowAmt > 0 then bfx = "frost"; table.insert(fxLayers, "frost") end
        if burnDmg > 0 then bfx = "burn"; table.insert(fxLayers, "burn") end
        if shockChance > 0 then bfx = "shock"; table.insert(fxLayers, "shock") end
        if explRadius > 0 then bfx = "explosive"; table.insert(fxLayers, "explosive") end
        if #fxLayers == 0 then table.insert(fxLayers, "normal") end

        table.insert(G.bullets, {
            x = bx, y = by,
            vx = math.cos(pelletAngle) * G.WEAPON.bulletSpeed,
            vy = math.sin(pelletAngle) * G.WEAPON.bulletSpeed,
            damage = pelletDamage,
            radius = G.WEAPON.bulletRadius,
            fromPlayer = true,
            life = 2.0,
            trail = {},
            isCrit = isCrit,
            pierce = pierceCount,
            bounceCount = bounceCount,
            hitEnemies = {},
            bulletFx = bfx,
            fxLayers = fxLayers,
            -- 感电属性(链式闪电)
            shockChance = shockChance > 0 and shockChance or nil,
            shockDamage = shockDamage > 0 and shockDamage or nil,
            chainCount = shockChance > 0 and chainCount or nil,
            chainRange = shockChance > 0 and chainRange or nil,
            -- 状态效果
            burnDamage = burnDmg > 0 and burnDmg or nil,
            burnDuration = burnDmg > 0 and burnDur or nil,
            slowAmount = slowAmt > 0 and slowAmt or nil,
            slowDuration = slowAmt > 0 and 2.0 or nil,
            freezeChance = freezeChance > 0 and freezeChance or nil,
            explosionRadius = explRadius > 0 and explRadius or nil,
            explosionDamage = explDamage > 0 and explDamage or nil,
        })
    end

    G.player.ammo = G.player.ammo - 1
    G.player.fireTimer = math.max(0.05, G.WEAPON.fireRate - bonusFireRate)

    G.PlaySfx(G.sndShoot, 0.35)

    -- 射击后坐力震动(散弹更强)
    local shakeStr = shotgunPellets > 0 and 3.0 or 1.5
    getFx().TriggerShake(shakeStr, 0.08)

    -- 视觉后坐力(角色渲染偏移, 方向为射击反方向)
    local recoilStr = shotgunPellets > 0 and 5.0 or 2.5
    G.player.recoilX = -math.cos(G.player.angle) * recoilStr
    G.player.recoilY = -math.sin(G.player.angle) * recoilStr

    -- 枪口主视觉类型(与子弹 bulletFx 同优先级)
    local muzzleFx = "normal"
    if shotgunPellets > 0 then muzzleFx = "shotgun" end
    if bounceCount > 0 then muzzleFx = "bounce" end
    if pierceCount > 0 then muzzleFx = "pierce" end
    if slowAmt > 0 then muzzleFx = "frost" end
    if burnDmg > 0 then muzzleFx = "burn" end
    if shockChance > 0 then muzzleFx = "shock" end
    if explRadius > 0 then muzzleFx = "explosive" end

    -- 枪口闪光配色
    local mfxColors = {
        normal    = { {255,220,100}, {255,240,200} },
        shotgun   = { {255,200,60},  {255,230,150} },
        pierce    = { {100,200,255}, {180,230,255} },
        bounce    = { {100,255,120}, {200,255,200} },
        frost     = { {140,220,255}, {220,240,255} },
        burn      = { {255,120,30},  {255,200,100} },
        shock     = { {180,140,255}, {220,200,255} },
        explosive = { {255,140,40},  {255,220,140} },
    }
    local mfxc = mfxColors[muzzleFx] or mfxColors.normal
    local sparkCol = mfxc[1]
    local flashCol = mfxc[2]

    -- 枪口闪光粒子(配件染色火花)
    local muzzleX = G.player.x + math.cos(G.player.angle) * (G.player.radius + 5)
    local muzzleY = G.player.y + math.sin(G.player.angle) * (G.player.radius + 5)
    local sparkCount = shotgunPellets > 0 and 14 or 8
    for j = 1, sparkCount do
        local pa = G.player.angle + (math.random() - 0.5) * (shotgunPellets > 0 and 1.2 or 0.8)
        local spd = 150 + math.random() * 200
        table.insert(G.particles, {
            x = muzzleX, y = muzzleY,
            vx = math.cos(pa) * spd,
            vy = math.sin(pa) * spd,
            life = 0.1 + math.random() * 0.12,
            maxLife = 0.22,
            r = sparkCol[1], g = math.min(255, sparkCol[2] + math.random(30)), b = sparkCol[3] + math.random(40),
            size = 1.5 + math.random() * 3,
            glow = true,
        })
    end

    -- 枪口闪光圆(短暂亮光, 散弹更大)
    local flashSize = shotgunPellets > 0 and 18 or 12
    table.insert(G.particles, {
        x = muzzleX, y = muzzleY, vx = 0, vy = 0,
        life = 0.07, maxLife = 0.07,
        r = flashCol[1], g = flashCol[2], b = flashCol[3],
        size = flashSize, glow = true, drag = 1.0,
    })

    -- 暴击额外: 白色核心闪光
    if isCrit then
        table.insert(G.particles, {
            x = muzzleX, y = muzzleY, vx = 0, vy = 0,
            life = 0.05, maxLife = 0.05,
            r = 255, g = 255, b = 255,
            size = 8, glow = true, drag = 1.0,
        })
    end

    -- 弹壳抛出(向枪口侧方弹出, 带重力)
    local shellAngle = G.player.angle + math.pi * 0.5 + (math.random() - 0.5) * 0.4
    local shellSpd = 60 + math.random() * 40
    table.insert(G.particles, {
        x = G.player.x + math.cos(G.player.angle) * 6,
        y = G.player.y + math.sin(G.player.angle) * 6,
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

function Combat.UpdatePlayer(dt)
    if not G.player.alive then return end

    -- 冲刺中跳过普通移动（位置已由 HandleUpdate 更新）
    if not (G.player.dashTimer > 0) then
        -- 移动输入
        local dx, dy = 0, 0
        if G.isMobile then
            local mi = getMI()
            dx, dy = mi.moveDX, mi.moveDY
        else
            -- WASD 移动
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
        end

        local effectiveSpeed = G.player.speed + Inv.GetStat("moveSpeed", 0)
        local newX = G.player.x + dx * effectiveSpeed * dt
        local newY = G.player.y + dy * effectiveSpeed * dt

        -- 墙碰撞修正
        newX, newY = getMap().ResolveWallCollision(newX, newY, G.player.radius)

        -- 边界限制
        newX = math.max(G.player.radius, math.min(G.MAP_W - G.player.radius, newX))
        newY = math.max(G.player.radius, math.min(G.MAP_H - G.player.radius, newY))

        -- 移动脚步声
        if dx ~= 0 or dy ~= 0 then
            G.footstepTimer = G.footstepTimer - dt
            if G.footstepTimer <= 0 then
                G.PlaySfx(G.sndFootstep, 0.25)
                G.footstepTimer = 0.3
            end
        else
            G.footstepTimer = 0
        end

        -- 移动脚步尘土
        if dx ~= 0 or dy ~= 0 then
            if math.random() < 0.3 then
                local dustAngle = math.random() * math.pi * 2
                table.insert(G.particles, {
                    x = G.player.x + (math.random() - 0.5) * 8,
                    y = G.player.y + (math.random() - 0.5) * 8,
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

        G.player.x = newX
        G.player.y = newY
    end

    -- 玩家朝向
    if G.isMobile then
        -- 移动端: 右摇杆激活时使用摇杆角度，否则保持上次角度
        local mi = getMI()
        if mi.isShooting then
            G.player.angle = mi.aimAngle
        end
    else
        -- 桌面端: 鼠标方向 → 玩家朝向 (物理屏幕坐标 → 设计坐标 → 世界坐标)
        local mx = input:GetMousePosition().x
        local my = input:GetMousePosition().y
        local designMX, designMY = G.ScreenToDesign(mx, my)
        local worldMX = designMX / G.camZoom + G.camX
        local worldMY = designMY / G.camZoom + G.camY
        G.player.angle = math.atan(worldMY - G.player.y, worldMX - G.player.x)
    end

    -- 射击冷却
    if G.player.fireTimer > 0 then
        G.player.fireTimer = G.player.fireTimer - dt
    end

    -- 视觉后坐力衰减(快速弹性回复)
    local recoilDecay = 1.0 - math.min(1.0, dt * 18)
    G.player.recoilX = G.player.recoilX * recoilDecay
    G.player.recoilY = G.player.recoilY * recoilDecay
    if math.abs(G.player.recoilX) < 0.1 then G.player.recoilX = 0 end
    if math.abs(G.player.recoilY) < 0.1 then G.player.recoilY = 0 end

    -- 换弹
    if G.player.reloading then
        G.player.reloadTimer = G.player.reloadTimer - dt
        if G.player.reloadTimer <= 0 then
            G.player.reloading = false
            G.PlaySfx(G.sndReloadDone, 0.5)
            local effectiveMag = G.WEAPON.magSize + WM.weaponMods.bonusMagSize + math.floor(Inv.GetStat("magSize", 0))
            local need = effectiveMag - G.player.ammo
            local give = math.min(need, G.player.totalAmmo)
            G.player.ammo = G.player.ammo + give
            G.player.totalAmmo = G.player.totalAmmo - give
        end
    end

    -- 无敌帧
    if G.player.invincibleTimer > 0 then
        G.player.invincibleTimer = G.player.invincibleTimer - dt
    end
end

function Combat.UpdateDrones(dt)
    local droneDmg = Inv.GetStat("droneDamage", 0)
    local droneRate = Inv.GetStat("droneRate", 0)
    if droneDmg <= 0 then
        G.drones = {}
        return
    end

    -- 确保有一架无人机
    if #G.drones == 0 then
        table.insert(G.drones, {
            x = G.player.x, y = G.player.y - 30,
            angle = 0, fireTimer = 0, orbitAngle = 0,
        })
    end

    local DRONE_ORBIT_RADIUS = 35
    local DRONE_ORBIT_SPEED = 2.5    -- 环绕速度(弧度/秒)
    local DRONE_RANGE = 200          -- 索敌范围(像素)
    local DRONE_BULLET_SPEED = 350
    local fireInterval = math.max(0.15, droneRate)

    for _, d in ipairs(G.drones) do
        -- 环绕玩家
        d.orbitAngle = d.orbitAngle + DRONE_ORBIT_SPEED * dt
        local targetX = G.player.x + math.cos(d.orbitAngle) * DRONE_ORBIT_RADIUS
        local targetY = G.player.y + math.sin(d.orbitAngle) * DRONE_ORBIT_RADIUS - 20
        -- 平滑跟随
        local followSpeed = 8.0
        d.x = d.x + (targetX - d.x) * math.min(1.0, followSpeed * dt)
        d.y = d.y + (targetY - d.y) * math.min(1.0, followSpeed * dt)

        -- 索敌: 找最近敌人
        local bestDist = DRONE_RANGE
        local bestEnemy = nil
        for _, e in ipairs(G.enemies) do
            if not e.dead then
                local ex = e.x - d.x
                local ey = e.y - d.y
                local dist = math.sqrt(ex * ex + ey * ey)
                if dist < bestDist then
                    bestDist = dist
                    bestEnemy = e
                end
            end
        end

        -- 瞄准
        if bestEnemy then
            d.angle = math.atan(bestEnemy.y - d.y, bestEnemy.x - d.x)
        end

        -- 射击
        d.fireTimer = d.fireTimer - dt
        if d.fireTimer <= 0 and bestEnemy then
            d.fireTimer = fireInterval
            G.PlaySfx(G.sndDroneShoot, 0.25)
            local bx = d.x + math.cos(d.angle) * 8
            local by = d.y + math.sin(d.angle) * 8
            table.insert(G.bullets, {
                x = bx, y = by,
                vx = math.cos(d.angle) * DRONE_BULLET_SPEED,
                vy = math.sin(d.angle) * DRONE_BULLET_SPEED,
                damage = droneDmg,
                radius = 2.5,
                fromPlayer = true,
                life = 1.2,
                trail = {},
                isCrit = false,
                pierce = 0,
                bounceCount = 0,
                hitEnemies = {},
                bulletFx = "shock",  -- 无人机子弹使用电弧视觉
                fxLayers = {"shock"},
                isDrone = true,
            })
            -- 微型枪口闪光
            table.insert(G.particles, {
                x = bx, y = by,
                vx = math.cos(d.angle) * 40, vy = math.sin(d.angle) * 40,
                life = 0.08, maxLife = 0.08,
                r = 180, g = 140, b = 255,
                size = 4, glow = true,
            })
        end
    end
end

-- ============================================================================
-- 高级圣物运行时逻辑
-- ============================================================================

-- 状态计时器（首次访问时初始化）
local function initRelicState()
    if not G.frostNovaTimer then G.frostNovaTimer = 0 end
    if not G.frostNovaPulses then G.frostNovaPulses = {} end
    if not G.stormTimer then G.stormTimer = 0 end
    if not G.stormBolts then G.stormBolts = {} end
    if not G.turretEntities then G.turretEntities = {} end
    if not G.turretSpawned then G.turretSpawned = false end
    if not G.phoenixUsed then G.phoenixUsed = false end
    if not G.phoenixAuraTimer then G.phoenixAuraTimer = 0 end
end

-- ===== 极寒脉冲 =====
function Combat.UpdateFrostNova(dt)
    initRelicState()
    local radius = Inv.GetStat("frostNovaRadius", 0)
    local damage = Inv.GetStat("frostNovaDamage", 0)
    local slowAmt = Inv.GetStat("slowAmount", 0)
    if radius <= 0 or damage <= 0 then
        G.frostNovaTimer = 0
        return
    end
    if not G.player.alive then return end

    G.frostNovaTimer = G.frostNovaTimer + dt
    local interval = 10.0
    if G.frostNovaTimer >= interval then
        G.frostNovaTimer = 0
        -- 触发脉冲：扩张冰环
        table.insert(G.frostNovaPulses, {
            x = G.player.x, y = G.player.y,
            currentR = 0, maxR = radius,
            duration = 0.6, life = 0.6,
            damage = damage, slow = slowAmt,
            hitSet = {},
        })
        G.PlaySfx(G.sndFrostHit, 0.7)
        -- 中心闪光
        table.insert(G.particles, {
            x = G.player.x, y = G.player.y, vx = 0, vy = 0,
            life = 0.18, maxLife = 0.18,
            r = 220, g = 240, b = 255,
            size = 30, glow = true, drag = 1.0,
        })
    end

    -- 推进每个脉冲
    for i = #G.frostNovaPulses, 1, -1 do
        local p = G.frostNovaPulses[i]
        local prevR = p.currentR
        p.life = p.life - dt
        local progress = 1 - p.life / p.duration
        p.currentR = p.maxR * progress

        -- 击中扇区：环上的敌人（在 prevR..currentR 之间且未命中过）
        for _, e in ipairs(G.enemies) do
            if not e.dead and not p.hitSet[e] then
                local dx = e.x - p.x
                local dy = e.y - p.y
                local d = math.sqrt(dx*dx + dy*dy)
                if d >= prevR and d <= p.currentR then
                    p.hitSet[e] = true
                    local dmg = p.damage
                    if e.armor and e.armor > 0 then
                        dmg = math.max(1, math.floor(dmg * (1 - e.armor)))
                    end
                    e.hp = e.hp - dmg
                    e.hitFlashTimer = 0.1
                    -- 减速/冰冻
                    e.slowTimer = 2.5
                    e.slowPercent = math.min(0.9, p.slow / 100)
                    table.insert(G.damageNumbers, {
                        x = e.x, y = e.y - e.radius - 5,
                        text = tostring(dmg),
                        life = 0.7, maxLife = 0.7, vy = -35,
                        isFrost = true,
                    })
                    -- 冰晶碎片
                    for k = 1, 4 do
                        local pa = math.random() * math.pi * 2
                        table.insert(G.particles, {
                            x = e.x, y = e.y,
                            vx = math.cos(pa) * 50, vy = math.sin(pa) * 50,
                            life = 0.4, maxLife = 0.4,
                            r = 200, g = 230, b = 255,
                            size = 2, glow = true,
                        })
                    end
                    if e.hp <= 0 then
                        e.dead = true
                        G.killCount = G.killCount + 1
                        WM.OnEnemyKilled()
                        G.score = G.score + 50
                    end
                end
            end
        end

        if p.life <= 0 then table.remove(G.frostNovaPulses, i) end
    end
end

-- ===== 风暴召唤者 =====
function Combat.UpdateStorm(dt)
    initRelicState()
    local interval = Inv.GetStat("stormInterval", 0)
    local stormDmg = Inv.GetStat("stormDamage", 0)
    local stormR = Inv.GetStat("stormRadius", 0)
    if interval <= 0 or stormDmg <= 0 then
        G.stormTimer = 0
        return
    end
    if not G.player.alive then return end

    G.stormTimer = G.stormTimer + dt
    if G.stormTimer >= interval then
        G.stormTimer = 0
        -- 选择 5 个随机敌人作为雷击目标
        local targets = {}
        for _, e in ipairs(G.enemies) do
            if not e.dead then
                local dx = e.x - G.player.x
                local dy = e.y - G.player.y
                if math.sqrt(dx*dx + dy*dy) < 600 then
                    table.insert(targets, e)
                end
            end
        end
        local boltCount = math.min(5, #targets)
        for i = 1, boltCount do
            -- 随机抽取
            local idx = math.random(1, #targets)
            local e = targets[idx]
            table.remove(targets, idx)
            table.insert(G.stormBolts, {
                target = e, x = e.x, y = e.y,
                delay = (i - 1) * 0.08,
                life = 0.35, maxLife = 0.35,
                damage = stormDmg, radius = stormR,
                detonated = false,
            })
        end
        G.PlaySfx(G.sndChainLightning, 0.8)
    end

    -- 推进雷击
    for i = #G.stormBolts, 1, -1 do
        local b = G.stormBolts[i]
        b.delay = b.delay - dt
        if b.delay <= 0 then
            if not b.detonated then
                b.detonated = true
                -- AOE 伤害
                for _, e in ipairs(G.enemies) do
                    if not e.dead then
                        local dx = e.x - b.x
                        local dy = e.y - b.y
                        local d = math.sqrt(dx*dx + dy*dy)
                        if d < b.radius then
                            local dmg = b.damage
                            if e.armor and e.armor > 0 then
                                dmg = math.max(1, math.floor(dmg * (1 - e.armor)))
                            end
                            e.hp = e.hp - dmg
                            e.hitFlashTimer = 0.1
                            table.insert(G.damageNumbers, {
                                x = e.x, y = e.y - e.radius - 5,
                                text = tostring(dmg),
                                life = 0.8, maxLife = 0.8, vy = -40,
                                isShock = true,
                            })
                            if e.hp <= 0 then
                                e.dead = true
                                G.killCount = G.killCount + 1
                                WM.OnEnemyKilled()
                                G.score = G.score + 50
                            end
                        end
                    end
                end
                -- 雷击中心爆裂
                for k = 1, 16 do
                    local pa = math.random() * math.pi * 2
                    local spd = 80 + math.random() * 120
                    table.insert(G.particles, {
                        x = b.x, y = b.y,
                        vx = math.cos(pa) * spd, vy = math.sin(pa) * spd,
                        life = 0.3, maxLife = 0.3,
                        r = 180 + math.random(70), g = 180, b = 255,
                        size = 3, glow = true, drag = 0.92,
                    })
                end
                table.insert(G.particles, {
                    x = b.x, y = b.y, vx = 0, vy = 0,
                    life = 0.25, maxLife = 0.25,
                    r = 255, g = 255, b = 255,
                    size = b.radius * 0.6, glow = true, drag = 1.0,
                })
                G.PlaySfx(G.sndChainLightning, 0.4)
            end
            b.life = b.life - dt
            if b.life <= 0 then table.remove(G.stormBolts, i) end
        end
    end
end

-- ===== 自动炮台 =====
function Combat.UpdateTurret(dt)
    initRelicState()
    local tDmg = Inv.GetStat("turretDamage", 0)
    local tRange = Inv.GetStat("turretRange", 0)
    local tRate = Inv.GetStat("turretRate", 0)
    if tDmg <= 0 or tRange <= 0 then
        G.turretEntities = {}
        G.turretSpawned = false
        return
    end
    if not G.player.alive then return end

    -- 首次出现：在玩家附近部署
    if not G.turretSpawned then
        G.turretSpawned = true
        G.turretEntities = {{
            x = G.player.x + 30, y = G.player.y + 10,
            angle = 0, fireTimer = 0,
        }}
    end

    for _, t in ipairs(G.turretEntities) do
        -- 平滑跟随玩家（保持距离 40）
        local dx = G.player.x + 30 - t.x
        local dy = G.player.y + 10 - t.y
        t.x = t.x + dx * dt * 3
        t.y = t.y + dy * dt * 3

        -- 寻找最近敌人
        local best, bestD = nil, tRange
        for _, e in ipairs(G.enemies) do
            if not e.dead then
                local edx = e.x - t.x
                local edy = e.y - t.y
                local d = math.sqrt(edx*edx + edy*edy)
                if d < bestD then
                    bestD = d
                    best = e
                end
            end
        end

        t.fireTimer = t.fireTimer - dt
        if best and t.fireTimer <= 0 then
            t.fireTimer = tRate
            t.angle = math.atan(best.y - t.y, best.x - t.x)
            local TURRET_BSPD = 460
            table.insert(G.bullets, {
                x = t.x + math.cos(t.angle) * 8,
                y = t.y + math.sin(t.angle) * 8,
                vx = math.cos(t.angle) * TURRET_BSPD,
                vy = math.sin(t.angle) * TURRET_BSPD,
                damage = tDmg, radius = 3,
                fromPlayer = true, life = 1.0,
                trail = {}, isCrit = false,
                pierce = 0, bounceCount = 0,
                hitEnemies = {},
                bulletFx = "normal",
                fxLayers = {"normal"},
                isTurret = true,
            })
            G.PlaySfx(G.sndDroneShoot, 0.2)
        end
    end
end

-- ===== 不死鸟之羽：燃烧光环 =====
function Combat.UpdatePhoenix(dt)
    initRelicState()
    local burnAura = Inv.GetStat("burnAura", 0)
    if burnAura <= 0 then return end
    if not G.player.alive then return end

    G.phoenixAuraTimer = G.phoenixAuraTimer + dt
    -- 每 0.5 秒对周围敌人施加燃烧
    if G.phoenixAuraTimer >= 0.5 then
        G.phoenixAuraTimer = 0
        local AURA_R = 90
        for _, e in ipairs(G.enemies) do
            if not e.dead then
                local dx = e.x - G.player.x
                local dy = e.y - G.player.y
                if math.sqrt(dx*dx + dy*dy) < AURA_R then
                    e.burnTimer = math.max(e.burnTimer or 0, 1.5)
                    e.burnDamage = math.max(e.burnDamage or 0, burnAura)
                    e.burnTickTimer = e.burnTickTimer or 0
                end
            end
        end
        -- 视觉：火星粒子绕玩家
        for k = 1, 6 do
            local pa = math.random() * math.pi * 2
            table.insert(G.particles, {
                x = G.player.x + math.cos(pa) * 80,
                y = G.player.y + math.sin(pa) * 80,
                vx = -math.cos(pa) * 30, vy = -math.sin(pa) * 30 - 20,
                life = 0.5, maxLife = 0.5,
                r = 255, g = 140 + math.random(60), b = 30,
                size = 2 + math.random() * 1.5, glow = true,
            })
        end
    end
end

-- ===== 不死鸟之羽：复活检测（由玩家死亡逻辑调用）=====
function Combat.TryPhoenixRevive()
    initRelicState()
    if G.phoenixUsed then return false end
    local revive = Inv.GetStat("revive", 0)
    if revive <= 0 then return false end
    G.phoenixUsed = true
    G.player.alive = true
    G.player.hp = math.floor((G.player.maxHp or 100) * 0.6)
    G.player.invincibleTimer = 2.0
    G.PlaySfx(G.sndShieldAbsorb, 0.8)
    G.PlaySfx(G.sndLevelClear, 0.6)
    -- 复活爆发：金色火羽爆裂
    for k = 1, 60 do
        local pa = (k / 60) * math.pi * 2
        local spd = 120 + math.random() * 180
        table.insert(G.particles, {
            x = G.player.x, y = G.player.y,
            vx = math.cos(pa) * spd, vy = math.sin(pa) * spd,
            life = 0.6 + math.random() * 0.4, maxLife = 1.0,
            r = 255, g = 180 + math.random(75), b = 50,
            size = 3 + math.random() * 2, glow = true, drag = 0.94,
        })
    end
    table.insert(G.particles, {
        x = G.player.x, y = G.player.y, vx = 0, vy = 0,
        life = 0.4, maxLife = 0.4,
        r = 255, g = 220, b = 100, size = 80,
        glow = true, drag = 1.0,
    })
    return true
end

-- ===== 炼狱核心：燃烧结束爆炸（由 enemy 燃烧伤害逻辑调用）=====
function Combat.TryInfernoExplosion(e)
    if not Inv.GetStat("explosionOnBurn", false) then return end
    if not e or e.dead then return end
    local burnDmg = e.burnDamage or 10
    local R = 90
    local explDmg = math.floor(burnDmg * 2.2)
    -- 推入华丽爆炸动画队列（render_world 渲染）
    if not G.infernoBlasts then G.infernoBlasts = {} end
    table.insert(G.infernoBlasts, {
        x = e.x, y = e.y,
        radius = R,
        life = 0.55, maxLife = 0.55,
        ringPhase = 0,
    })
    -- 镜头震动 + 命中停顿
    G.shakeAmount = math.max(G.shakeAmount or 0, 8)
    G.shakeTimer = math.max(G.shakeTimer or 0, 0.25)
    G.hitstopTimer = math.max(G.hitstopTimer or 0, 0.05)
    -- AOE 伤害
    for _, e2 in ipairs(G.enemies) do
        if e2 ~= e and not e2.dead then
            local dx = e2.x - e.x
            local dy = e2.y - e.y
            local d = math.sqrt(dx*dx + dy*dy)
            if d < R then
                local dmg = math.floor(explDmg * (1 - d / R))
                if e2.armor and e2.armor > 0 then
                    dmg = math.max(1, math.floor(dmg * (1 - e2.armor)))
                end
                if dmg > 0 then
                    e2.hp = e2.hp - dmg
                    e2.hitFlashTimer = 0.1
                    -- 传播燃烧
                    e2.burnTimer = math.max(e2.burnTimer or 0, 1.0)
                    e2.burnDamage = math.max(e2.burnDamage or 0, math.floor(burnDmg * 0.6))
                    e2.burnTickTimer = e2.burnTickTimer or 0
                    table.insert(G.damageNumbers, {
                        x = e2.x, y = e2.y - e2.radius - 5,
                        text = tostring(dmg),
                        life = 0.7, maxLife = 0.7, vy = -35,
                        isAoe = true,
                    })
                    if e2.hp <= 0 then
                        e2.dead = true
                        G.killCount = G.killCount + 1
                        WM.OnEnemyKilled()
                        G.score = G.score + 50
                    end
                end
            end
        end
    end
    -- 视觉：华丽炼狱爆炸
    G.PlaySfx(G.sndExplosion, 0.6)
    -- 中心强光
    table.insert(G.particles, {
        x = e.x, y = e.y, vx = 0, vy = 0,
        life = 0.25, maxLife = 0.25,
        r = 255, g = 240, b = 180, size = R * 1.1,
        glow = true, drag = 1.0,
    })
    -- 内核（白热）
    table.insert(G.particles, {
        x = e.x, y = e.y, vx = 0, vy = 0,
        life = 0.18, maxLife = 0.18,
        r = 255, g = 255, b = 220, size = R * 0.55,
        glow = true, drag = 1.0,
    })
    -- 火焰花瓣（多层环）
    for ring = 1, 3 do
        local count = 14 + ring * 6
        local baseSpd = 120 + ring * 80
        for k = 1, count do
            local pa = (k / count) * math.pi * 2 + math.random() * 0.2
            local spd = baseSpd + math.random() * 100
            table.insert(G.particles, {
                x = e.x, y = e.y,
                vx = math.cos(pa) * spd, vy = math.sin(pa) * spd,
                life = 0.45 + math.random() * 0.35, maxLife = 0.8,
                r = 255,
                g = 80 + math.random(140),
                b = 10 + math.random(60),
                size = 4 + math.random() * 4,
                glow = true, drag = 0.88,
            })
        end
    end
    -- 飞溅余烬（高速亮黄）
    for k = 1, 24 do
        local pa = math.random() * math.pi * 2
        local spd = 280 + math.random() * 220
        table.insert(G.particles, {
            x = e.x, y = e.y,
            vx = math.cos(pa) * spd, vy = math.sin(pa) * spd,
            life = 0.6 + math.random() * 0.4, maxLife = 1.0,
            r = 255, g = 220 + math.random(35), b = 80 + math.random(100),
            size = 1.5 + math.random() * 1.5, glow = true, drag = 0.93,
        })
    end
    -- 上升黑红浓烟
    for k = 1, 16 do
        local pa = math.random() * math.pi * 2
        local spd = 30 + math.random() * 60
        table.insert(G.particles, {
            x = e.x + math.cos(pa) * 8,
            y = e.y + math.sin(pa) * 8,
            vx = math.cos(pa) * spd * 0.4,
            vy = -50 - math.random() * 60,
            life = 0.8 + math.random() * 0.5, maxLife = 1.3,
            r = 80 + math.random(60), g = 40 + math.random(40), b = 30,
            size = 8 + math.random() * 6, glow = false, drag = 0.95,
        })
    end
    -- 地面焦痕（短促闪光块）
    for k = 1, 8 do
        local pa = math.random() * math.pi * 2
        local d = math.random() * R * 0.7
        table.insert(G.particles, {
            x = e.x + math.cos(pa) * d,
            y = e.y + math.sin(pa) * d,
            vx = 0, vy = 0,
            life = 0.5, maxLife = 0.5,
            r = 200, g = 60, b = 20,
            size = 6, glow = true, drag = 1.0,
        })
    end
end

-- ===== 推进炼狱爆炸动画 =====
function Combat.UpdateInfernoBlasts(dt)
    if not G.infernoBlasts then return end
    for i = #G.infernoBlasts, 1, -1 do
        local b = G.infernoBlasts[i]
        b.life = b.life - dt
        b.ringPhase = b.ringPhase + dt
        if b.life <= 0 then table.remove(G.infernoBlasts, i) end
    end
end

-- ===== 关卡切换时重置炮台/不死鸟使用状态（在 wave 开始时调用）=====
function Combat.ResetRelicsOnNewWave()
    initRelicState()
    G.turretSpawned = false
    G.turretEntities = {}
    G.frostNovaTimer = 0
    G.frostNovaPulses = {}
    G.stormTimer = 0
    G.stormBolts = {}
    -- phoenixUsed 跨关卡保留（一周目只能用一次）
end

return Combat
