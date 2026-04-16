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

local Combat = {}

function Combat.TryMelee()
    if G.player.meleeTimer > 0 then return end       -- 冷却中
    if G.player.meleeSwingTimer > 0 then return end   -- 正在挥击

    G.player.meleeSwingTimer = G.player.meleeSwingDur
    G.player.meleeTimer = G.player.meleeCooldown
    G.player.meleeHitDone = false
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

    local slowAmt = Inv.GetStat("slowAmount", 0) + Inv.GetStat("combo_slowAmountBonus", 0)

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

        -- 计算子弹视觉类型(优先级: explosive > shock > burn > frost > pierce > bounce > shotgun > normal)
        local bfx = "normal"
        if shotgunPellets > 0 then bfx = "shotgun" end
        if bounceCount > 0 then bfx = "bounce" end
        if pierceCount > 0 then bfx = "pierce" end
        if slowAmt > 0 then bfx = "frost" end
        if burnDmg > 0 then bfx = "burn" end
        if shockChance > 0 then bfx = "shock" end
        if explRadius > 0 then bfx = "explosive" end

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
            G.footstepTimer = 0.3  -- 每0.3秒一步
        end
    else
        G.footstepTimer = 0  -- 停下时重置，起步立刻有声
    end

    -- 移动脚步尘土
    if dx ~= 0 or dy ~= 0 then
        if math.random() < 0.3 then  -- 30%概率每帧产生
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

    -- 鼠标方向 → 玩家朝向 (物理屏幕坐标 → 设计坐标 → 世界坐标)
    local mx = input:GetMousePosition().x
    local my = input:GetMousePosition().y
    local designMX, designMY = G.ScreenToDesign(mx, my)
    local worldMX = designMX / G.camZoom + G.camX
    local worldMY = designMY / G.camZoom + G.camY
    G.player.angle = math.atan(worldMY - G.player.y, worldMX - G.player.x)

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

return Combat
