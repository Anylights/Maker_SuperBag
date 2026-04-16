local G = require("game_context")
local WM = require("wave_manager")
local Inv = require("inventory")

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

local Bullet = {}

function Bullet.UpdateBullets(dt)
    for i = #G.bullets, 1, -1 do
        local b = G.bullets[i]

        -- 记录拖尾位置(移动前)
        if b.trail then
            table.insert(b.trail, 1, {x = b.x, y = b.y})
            if #b.trail > G.TRAIL_MAX then
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
        if getMap().IsWall(b.x, b.y) then
            -- 弹跳判定: bounceCount > 0 则反射, 否则销毁
            if b.bounceCount and b.bounceCount > 0 then
                -- 计算反射方向: 检测哪个轴穿墙
                local prevX = b.x - b.vx * dt
                local prevY = b.y - b.vy * dt
                local hitHorizontal = getMap().IsWall(prevX, b.y)
                local hitVertical = getMap().IsWall(b.x, prevY)
                if hitHorizontal and hitVertical then
                    b.vx = -b.vx
                    b.vy = -b.vy
                elseif hitHorizontal then
                    b.vy = -b.vy
                else
                    b.vx = -b.vx
                end
                -- 回退到墙外
                b.x = prevX
                b.y = prevY
                b.bounceCount = b.bounceCount - 1
                b.life = math.max(b.life, 1.0)  -- 延长寿命
                G.PlaySfx(G.sndBulletBounce, 0.3)
                -- 清空已击中列表(弹跳后可再次击中)
                if b.hitEnemies then b.hitEnemies = {} end

                -- 弹跳火花(配件染色)
                local bfxc = G.BULLET_FX_COLORS[b.bulletFx or "bounce"] or G.BULLET_FX_COLORS.bounce
                local bsc = bfxc.core
                for j = 1, 8 do
                    local pa = math.random() * math.pi * 2
                    local spd = 80 + math.random() * 100
                    table.insert(G.particles, {
                        x = b.x, y = b.y,
                        vx = math.cos(pa) * spd, vy = math.sin(pa) * spd,
                        life = 0.15 + math.random() * 0.12, maxLife = 0.27,
                        r = bsc[1], g = bsc[2], b = bsc[3],
                        size = 1.5 + math.random() * 2.5, glow = true,
                    })
                end
                -- 弹跳闪光(白绿色环)
                table.insert(G.particles, {
                    x = b.x, y = b.y, vx = 0, vy = 0,
                    life = 0.08, maxLife = 0.08,
                    r = math.min(255, bsc[1] + 60), g = math.min(255, bsc[2] + 40), b = math.min(255, bsc[3] + 60),
                    size = 12, glow = true, drag = 1.0,
                })
            else
                remove = true
                -- 墙壁火花(散射)
                for j = 1, 8 do
                    local pa = math.random() * math.pi * 2
                    local spd = 40 + math.random() * 80
                    table.insert(G.particles, {
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
                table.insert(G.particles, {
                    x = b.x, y = b.y, vx = 0, vy = 0,
                    life = 0.05, maxLife = 0.05,
                    r = 255, g = 255, b = 220,
                    size = 8, glow = true, drag = 1.0,
                })
                -- 碎屑(重力下落)
                for j = 1, 3 do
                    local pa = math.random() * math.pi * 2
                    table.insert(G.particles, {
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
        end

        -- 玩家子弹 → 敌人
        if not remove and b.fromPlayer then
            for j = #G.enemies, 1, -1 do
                local e = G.enemies[j]
                -- 穿透子弹: 跳过已击中过的敌人
                local alreadyHit = false
                if b.hitEnemies then
                    for _, he in ipairs(b.hitEnemies) do
                        if he == e then alreadyHit = true; break end
                    end
                end
                if not alreadyHit and not e.dead and getMap().CircleCollision(b.x, b.y, b.radius, e.x, e.y, e.radius) then
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
                        G.PlaySfx(G.sndBurnHit, 0.25)
                    end
                    -- 减速: 降低移动速度
                    if b.slowAmount and b.slowAmount > 0 then
                        e.slowTimer = b.slowDuration or 2.0
                        e.slowPercent = math.min(0.8, (b.slowAmount / 100))  -- 最多减速80%
                        G.PlaySfx(G.sndFrostHit, 0.25)
                    end
                    -- 爆炸: 对周围敌人造成AOE伤害
                    if b.explosionRadius and b.explosionRadius > 0 and b.explosionDamage and b.explosionDamage > 0 then
                        G.PlaySfx(G.sndExplosion, 0.5)
                        for k2 = #G.enemies, 1, -1 do
                            local e2 = G.enemies[k2]
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
                                    table.insert(G.damageNumbers, {
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
                                        G.killCount = G.killCount + 1
                                        WM.OnEnemyKilled()
                                        G.score = G.score + 50
                                        -- AOE击杀粒子
                                        for kp = 1, 10 do
                                            local pa2 = math.random() * math.pi * 2
                                            local spd2 = 60 + math.random() * 100
                                            table.insert(G.particles, {
                                                x = e2.x, y = e2.y,
                                                vx = math.cos(pa2) * spd2, vy = math.sin(pa2) * spd2,
                                                life = 0.3 + math.random() * 0.3, maxLife = 0.6,
                                                r = 255, g = 160 + math.random(60), b = 40 + math.random(60),
                                                size = 2 + math.random() * 2, glow = true,
                                            })
                                        end
                                        table.remove(G.enemies, k2)
                                    end
                                end
                            end
                        end
                        -- 爆炸冲击波视觉: 外圈快速扩散环
                        for kp = 1, 20 do
                            local pa = (kp / 20) * math.pi * 2 + (math.random() - 0.5) * 0.15
                            local spd = b.explosionRadius * 2.5
                            table.insert(G.particles, {
                                x = e.x, y = e.y,
                                vx = math.cos(pa) * spd, vy = math.sin(pa) * spd,
                                life = 0.3, maxLife = 0.3,
                                r = 255, g = 180, b = 60,
                                size = 3 + math.random() * 2.5, glow = true, drag = 0.95,
                            })
                        end
                        -- 内圈慢速烈焰碎片(向上飘)
                        for kp = 1, 10 do
                            local pa = math.random() * math.pi * 2
                            local spd = 30 + math.random() * 60
                            table.insert(G.particles, {
                                x = e.x + (math.random() - 0.5) * 8,
                                y = e.y + (math.random() - 0.5) * 8,
                                vx = math.cos(pa) * spd,
                                vy = math.sin(pa) * spd - 30,
                                life = 0.35 + math.random() * 0.25,
                                maxLife = 0.6,
                                r = 255, g = 100 + math.random(80), b = 20 + math.random(30),
                                size = 2 + math.random() * 3, glow = true, drag = 0.94,
                            })
                        end
                        -- 爆炸中心白色闪光(更大更亮)
                        table.insert(G.particles, {
                            x = e.x, y = e.y, vx = 0, vy = 0,
                            life = 0.1, maxLife = 0.1,
                            r = 255, g = 255, b = 220,
                            size = b.explosionRadius * 0.8, glow = true, drag = 1.0,
                        })
                        -- 橙色次级光晕
                        table.insert(G.particles, {
                            x = e.x, y = e.y, vx = 0, vy = 0,
                            life = 0.15, maxLife = 0.15,
                            r = 255, g = 160, b = 40,
                            size = b.explosionRadius * 0.5, glow = true, drag = 1.0,
                        })
                    end

                    -- === 感电链式闪电(延迟队列，逐跳传递) ===
                    if b.shockChance and b.shockChance > 0 then
                        if math.random(1, 100) <= b.shockChance then
                            G.PlaySfx(G.sndChainLightning, 0.4)
                            local sDmg = b.shockDamage or 8
                            local maxBounces = b.chainCount or 2
                            local searchRange = b.chainRange or 120
                            local damageDecay = 0.8

                            -- 将整条链加入延迟队列，由 main.lua 逐跳执行
                            table.insert(G.pendingChainLightning, {
                                sourceX = e.x, sourceY = e.y,
                                hitSet = {[e] = true},
                                remainBounces = maxBounces,
                                currentDmg = sDmg,
                                searchRange = searchRange,
                                damageDecay = damageDecay,
                                timer = 0,           -- 第一跳立即执行
                                delay = 0.08,        -- 每跳间隔
                            })

                            -- 起始点电弧闪光
                            table.insert(G.particles, {
                                x = e.x, y = e.y, vx = 0, vy = 0,
                                life = 0.15, maxLife = 0.15,
                                r = 150, g = 200, b = 255,
                                size = 20, glow = true, drag = 1.0,
                            })
                        end
                    end

                    -- 穿透判定: pierce > 0 则不消除子弹
                    if b.pierce and b.pierce > 0 then
                        b.pierce = b.pierce - 1
                        if b.hitEnemies then table.insert(b.hitEnemies, e) end
                    else
                        remove = true
                    end

                    -- 弹药回收: 击中敌人概率恢复1发弹药
                    local recycleChance = Inv.GetStat("ammoRecycleChance", 0)
                    if recycleChance > 0 and math.random(1, 100) <= recycleChance then
                        G.player.ammo = math.min(G.player.ammo + 1,
                            G.WEAPON.magSize + math.floor(Inv.GetStat("magSize", 0)))
                    end

                    -- 伤害数字(暴击显示红色大字, 护甲显示灰色)
                    local dmgText = (b.isCrit and "暴击 " or "") .. tostring(actualDmg)
                    table.insert(G.damageNumbers, {
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
                        table.insert(G.particles, {
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

                    -- 配件特化击中粒子
                    local hfx = b.bulletFx or "normal"
                    if hfx == "burn" then
                        -- 燃烧: 向上飘升火焰粒子
                        for k = 1, 5 do
                            table.insert(G.particles, {
                                x = e.x + (math.random() - 0.5) * 10,
                                y = e.y,
                                vx = (math.random() - 0.5) * 30,
                                vy = -(40 + math.random() * 60),
                                life = 0.3 + math.random() * 0.3,
                                maxLife = 0.6,
                                r = 255, g = 100 + math.random(80), b = 20,
                                size = 2 + math.random() * 2.5, glow = true, drag = 0.97,
                            })
                        end
                    elseif hfx == "frost" then
                        -- 冰冻: 冰晶碎片(慢速扩散)
                        for k = 1, 5 do
                            local pa = math.random() * math.pi * 2
                            local spd = 20 + math.random() * 40
                            table.insert(G.particles, {
                                x = e.x, y = e.y,
                                vx = math.cos(pa) * spd, vy = math.sin(pa) * spd,
                                life = 0.3 + math.random() * 0.3,
                                maxLife = 0.6,
                                r = 180, g = 230, b = 255,
                                size = 1.5 + math.random() * 2, glow = true, drag = 0.92,
                            })
                        end
                    elseif hfx == "shock" then
                        -- 感电: 微型电弧碎片
                        for k = 1, 4 do
                            local pa = math.random() * math.pi * 2
                            local spd = 50 + math.random() * 80
                            table.insert(G.particles, {
                                x = e.x, y = e.y,
                                vx = math.cos(pa) * spd, vy = math.sin(pa) * spd,
                                life = 0.15 + math.random() * 0.1,
                                maxLife = 0.25,
                                r = 180, g = 150, b = 255,
                                size = 1 + math.random() * 2, glow = true,
                            })
                        end
                    elseif hfx == "pierce" then
                        -- 穿透: 贯穿方向箭头状粒子
                        for k = 1, 4 do
                            local pa = bulletDir + (math.random() - 0.5) * 0.4
                            local spd = 120 + math.random() * 100
                            table.insert(G.particles, {
                                x = e.x, y = e.y,
                                vx = math.cos(pa) * spd, vy = math.sin(pa) * spd,
                                life = 0.12 + math.random() * 0.08,
                                maxLife = 0.2,
                                r = 100, g = 200, b = 255,
                                size = 1 + math.random() * 1.5, glow = true,
                            })
                        end
                    end

                    -- 命中闪光(配件染色)
                    local hitFlashCol = G.BULLET_FX_COLORS[hfx] or G.BULLET_FX_COLORS.normal
                    local hfc = hitFlashCol.core
                    table.insert(G.particles, {
                        x = b.x, y = b.y, vx = 0, vy = 0,
                        life = 0.05, maxLife = 0.05,
                        r = hfc[1], g = hfc[2], b = hfc[3],
                        size = 11, glow = true, drag = 1.0,
                    })

                    -- 命中震动 + 停顿 + 音效
                    getFx().TriggerShake(3, 0.1)
                    getFx().TriggerHitstop(G.HITSTOP_HIT)
                    G.PlaySfx(G.sndHit, 0.3)

                    if e.hp <= 0 and not e.dead then
                        e.dead = true
                        -- 敌人死亡 -- 更强震动 + 更长停顿 + 音效
                        getFx().TriggerShake(6, 0.15)
                        getFx().TriggerHitstop(G.HITSTOP_KILL)
                        G.PlaySfx(G.sndKill, 0.5)
                        G.PlaySfx(G.sndSplat, 0.4)
                        G.PlaySfx(G.sndEnemyDeath, 0.35)
                        G.killCount = G.killCount + 1
                        WM.OnEnemyKilled()
                        G.score = G.score + 50
                        -- 掉落物(弹药/血包)
                        local lootRoll = math.random(1, 100)
                        if lootRoll <= 40 then
                            table.insert(G.lootItems, {
                                x = e.x, y = e.y,
                                type = "ammo", amount = math.random(3, 8),
                            })
                        elseif lootRoll <= 60 then
                            table.insert(G.lootItems, {
                                x = e.x, y = e.y,
                                type = "health", amount = math.random(15, 30),
                            })
                        end

                        -- 掉落圣物(背包系统)
                        local invLootRoll = math.random(1, 100)
                        local dropRarityMax = 3  -- 默认最高掉蓝色
                        if e.typeKey == "rusher" then dropRarityMax = 4 end  -- 冲锋者可掉紫
                        if e.typeKey == "sentry" then dropRarityMax = 4 end  -- 哨兵可掉紫
                        if WM.currentWave >= 5 then dropRarityMax = math.max(dropRarityMax, 4) end  -- 后期全员可掉紫

                        -- 掉落率固定18%, 幸运币提升高稀有度概率(不影响掉落率)
                        local artifactChance = 18
                        local rarityBoost = Inv.GetStat("rarityBoost", 0)

                        if invLootRoll <= artifactChance then
                            -- 掉落圣物(掉到地面, 需要玩家走过去拾取)
                            local artifact = Inv.CreateRandomArtifact(dropRarityMax, rarityBoost)
                            if artifact then
                                table.insert(G.lootItems, {
                                    x = e.x + math.random(-8, 8),
                                    y = e.y + math.random(-8, 8),
                                    type = "artifact",
                                    itemData = artifact,
                                })
                            end
                        end
                        -- 击杀爆炸: 核心冲击波闪光
                        table.insert(G.particles, {
                            x = e.x, y = e.y, vx = 0, vy = 0,
                            life = 0.1, maxLife = 0.1,
                            r = 255, g = 255, b = 255,
                            size = 25, glow = true, drag = 1.0,
                        })
                        -- 击杀爆炸: 碎片喷射(带重力)
                        for k = 1, 16 do
                            local pa = math.random() * math.pi * 2
                            local spd = 80 + math.random() * 140
                            table.insert(G.particles, {
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
                            table.insert(G.particles, {
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
                    end
                    break
                end
            end
        end

        -- 敌人子弹 → 玩家
        if not remove and not b.fromPlayer and G.player.alive then
            if getMap().CircleCollision(b.x, b.y, b.radius, G.player.x, G.player.y, G.player.radius) then
                if G.player.invincibleTimer <= 0 then
                    local incomingDmg = b.damage
                    -- 护盾吸收
                    if G.player.shield > 0 then
                        if G.player.shield >= incomingDmg then
                            G.player.shield = G.player.shield - incomingDmg
                            incomingDmg = 0
                            G.PlaySfx(G.sndShieldAbsorb, 0.4)
                            -- 护盾吸收伤害数字(蓝色)
                            table.insert(G.damageNumbers, {
                                x = G.player.x, y = G.player.y - G.player.radius - 5,
                                text = tostring(b.damage),
                                life = 0.8, maxLife = 0.8, vy = -40,
                                isShield = true,
                            })
                            -- 护盾碎片粒子
                            for sp = 1, 6 do
                                local sa = math.random() * math.pi * 2
                                table.insert(G.particles, {
                                    x = G.player.x, y = G.player.y,
                                    vx = math.cos(sa) * 60, vy = math.sin(sa) * 60,
                                    life = 0.2, maxLife = 0.2,
                                    r = 80, g = 160, b = 255,
                                    size = 2 + math.random() * 2, glow = true,
                                })
                            end
                        else
                            incomingDmg = incomingDmg - G.player.shield
                            -- 护盾被击穿数字
                            table.insert(G.damageNumbers, {
                                x = G.player.x + 15, y = G.player.y - G.player.radius - 15,
                                text = tostring(math.floor(G.player.shield)),
                                life = 0.6, maxLife = 0.6, vy = -30,
                                isShield = true,
                            })
                            G.player.shield = 0
                            G.PlaySfx(G.sndShieldBreak, 0.5)
                        end
                        G.player.shieldRegenDelay = 3.0  -- 被击后3秒才恢复护盾
                    end
                    if incomingDmg > 0 then
                        G.player.hp = G.player.hp - incomingDmg
                        G.PlaySfx(G.sndPlayerHurt, 0.5)
                        -- 受伤闪红
                        table.insert(G.damageNumbers, {
                            x = G.player.x, y = G.player.y - G.player.radius - 5,
                            text = tostring(incomingDmg),
                            life = 0.8, maxLife = 0.8,
                            vy = -40,
                            isPlayer = true,
                        })
                    end
                    G.player.invincibleTimer = 0.3
                    if G.player.hp <= 0 then
                        G.player.hp = 0
                        G.player.alive = false
                        G.gameState = G.STATE_DYING
                        G.deathAnimTimer = 0
                        G.deathZoomStart = G.camZoom
                        G.deathSlowScale = 1.0
                        G.PlaySfx(G.sndPlayerDeath, 0.6)
                    end
                end
                remove = true
            end
        end

        if remove then
            table.remove(G.bullets, i)
        end
    end

    -- 统一清理已标记 dead 的敌人（延迟删除，避免遍历中索引错乱）
    for i = #G.enemies, 1, -1 do
        if G.enemies[i].dead then
            table.remove(G.enemies, i)
        end
    end
end

return Bullet
