local G = require("game_context")
local WM = require("wave_manager")

local Map = nil
local function getMap()
    if not Map then Map = require("map") end
    return Map
end

local Enemy = {}

function Enemy.SpawnEnemies()
    G.enemies = {}
    WM.boss = nil

    -- 收集可用地板格(远离玩家出生点)
    local floorTiles = {}
    for r = 1, G.MAP_ROWS do
        for c = 1, G.MAP_COLS do
            if G.mapData[r][c] == G.TILE_FLOOR then
                local wx = (c - 0.5) * G.TILE_SIZE
                local wy = (r - 0.5) * G.TILE_SIZE
                local dist = math.sqrt((wx - G.player.x)^2 + (wy - G.player.y)^2)
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

    -- 小Boss波: 生成小Boss(第3/6关)
    if wave and wave.hasMiniBoss and #floorTiles > 0 then
        -- 选择离玩家较远的位置给小Boss
        local bestTile = floorTiles[1]
        local bestDist = 0
        for _, tile in ipairs(floorTiles) do
            local wx = (tile.c - 0.5) * G.TILE_SIZE
            local wy = (tile.r - 0.5) * G.TILE_SIZE
            local d = math.sqrt((wx - G.player.x)^2 + (wy - G.player.y)^2)
            if d > bestDist then
                bestDist = d
                bestTile = tile
            end
        end
        local mbx = (bestTile.c - 0.5) * G.TILE_SIZE
        local mby = (bestTile.r - 0.5) * G.TILE_SIZE
        local miniBoss = WM.CreateMiniBoss(mbx, mby, wave.miniBossHpMult or 1.0)
        table.insert(G.enemies, miniBoss)
        print("Wave " .. WM.currentWave .. ": Spawned Mini-Boss at (" .. math.floor(mbx) .. "," .. math.floor(mby) .. ")")
    end

    -- Boss波: 先生成Boss
    if wave and wave.type == "boss" and #floorTiles > 0 then
        -- 选择离玩家最远的位置给Boss
        local bestTile = floorTiles[1]
        local bestDist = 0
        for _, tile in ipairs(floorTiles) do
            local wx = (tile.c - 0.5) * G.TILE_SIZE
            local wy = (tile.r - 0.5) * G.TILE_SIZE
            local d = math.sqrt((wx - G.player.x)^2 + (wy - G.player.y)^2)
            if d > bestDist then
                bestDist = d
                bestTile = tile
            end
        end
        local bx = (bestTile.c - 0.5) * G.TILE_SIZE
        local by = (bestTile.r - 0.5) * G.TILE_SIZE
        local boss = WM.CreateBoss(bx, by)
        table.insert(G.enemies, boss)
    end

    local placed = {}

    for _, tile in ipairs(floorTiles) do
        if #placed >= numEnemies then break end

        local wx = (tile.c - 0.5) * G.TILE_SIZE
        local wy = (tile.r - 0.5) * G.TILE_SIZE

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
            local t = G.ENEMY_TYPES[typeKey]
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
            table.insert(G.enemies, enemy)
            table.insert(placed, {x = wx, y = wy})
        end
    end

    print("Wave " .. WM.currentWave .. ": Spawned " .. #G.enemies .. " enemies (hp×" .. hpMult .. " dmg×" .. dmgMult .. ")")
end

function Enemy.SpawnBossMinions(count)
    if not WM.boss then return end
    for i = 1, count do
        local angle = math.random() * math.pi * 2
        local dist = 60 + math.random() * 40
        local mx = WM.boss.x + math.cos(angle) * dist
        local my = WM.boss.y + math.sin(angle) * dist
        -- 确保不在墙里
        if not getMap().IsWall(mx, my) then
            local typeKey = math.random() > 0.5 and "rusher" or "patrol"
            local t = G.ENEMY_TYPES[typeKey]
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
                angle = math.atan(G.player.y - my, G.player.x - mx),
                fireTimer = 0,
                alertTimer = 5,
                patrolOriginX = mx,
                patrolOriginY = my,
                patrolAngle = 0,
                patrolTimer = 0,
                hitFlashTimer = 0,
            }
            table.insert(G.enemies, enemy)
            -- 召唤特效
            for k = 1, 8 do
                local pa = math.random() * math.pi * 2
                local spd = 40 + math.random() * 60
                table.insert(G.particles, {
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

function Enemy.UpdateEnemies(dt)
    for _, e in ipairs(G.enemies) do
        local dx = G.player.x - e.x
        local dy = G.player.y - e.y
        local dist = math.sqrt(dx * dx + dy * dy)
        local canSee = dist < e.sightRange and not getMap().LineHitsWall(e.x, e.y, G.player.x, G.player.y)

        -- 状态机
        if not G.player.alive then
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
        -- 冰冻效果(完全静止 + 无法攻击)
        local isFrozen = false
        local speedMult = 1.0
        if e.frozenTimer and e.frozenTimer > 0 then
            e.frozenTimer = e.frozenTimer - dt
            isFrozen = true
            speedMult = 0.0
            -- 冰晶粒子特效(每帧小几率产生)
            if math.random() < 0.25 then
                local pa = math.random() * math.pi * 2
                local pr = e.radius * (0.6 + math.random() * 0.6)
                table.insert(G.particles, {
                    x = e.x + math.cos(pa) * pr,
                    y = e.y + math.sin(pa) * pr,
                    vx = math.cos(pa) * (5 + math.random() * 8),
                    vy = math.sin(pa) * (5 + math.random() * 8) - 8,
                    life = 0.4 + math.random() * 0.3, maxLife = 0.7,
                    r = 160, g = 220, b = 255,
                    size = 1.5 + math.random() * 1.5, glow = true,
                })
            end
            if e.frozenTimer <= 0 then
                e.frozenTimer = nil
                isFrozen = false
            end
        end
        -- 减速效果(未冰冻时生效)
        if not isFrozen and e.slowTimer and e.slowTimer > 0 then
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
                    table.insert(G.damageNumbers, {
                        x = e.x + (math.random() - 0.5) * 10,
                        y = e.y - e.radius - 3,
                        text = tostring(bDmg),
                        life = 0.5, maxLife = 0.5, vy = -25,
                        isBurn = true,
                    })
                    -- 燃烧火星粒子
                    for kp = 1, 3 do
                        local pa = math.random() * math.pi * 2
                        table.insert(G.particles, {
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
                        G.killCount = G.killCount + 1
                        WM.OnEnemyKilled()
                        G.score = G.score + 50
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
            nx, ny = getMap().ResolveWallCollision(nx, ny, e.radius)
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
                nx, ny = getMap().ResolveWallCollision(nx, ny, e.radius)
                e.x = nx
                e.y = ny
                e.angle = e.patrolAngle
            else
                e.patrolAngle = e.patrolAngle + math.pi
            end
        end

        -- burst 连发处理(冰冻时暂停)
        if not isFrozen and e.burstRemaining and e.burstRemaining > 0 then
            e.burstTimer = e.burstTimer - dt
            if e.burstTimer <= 0 then
                e.burstTimer = e.burstInterval
                e.burstRemaining = e.burstRemaining - 1
                -- 使用锁定角度发射(带微小抖动)
                local bAngle = e.burstAngle + (math.random() - 0.5) * 0.06
                local bx = e.x + math.cos(bAngle) * (e.radius + 4)
                local by = e.y + math.sin(bAngle) * (e.radius + 4)
                table.insert(G.bullets, {
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

        -- 攻击(冰冻时完全禁止攻击，火力计时器也暂停)
        if e.state == "attack" and not isFrozen then
            e.fireTimer = e.fireTimer - dt
            if e.fireTimer <= 0 and (not e.burstRemaining or e.burstRemaining <= 0) then
                e.fireTimer = e.attackRate

                local pattern = e.attackPattern or "single"

                if pattern == "single" then
                    -- 单发: 一颗子弹+轻微散布
                    local bAngle = e.angle + (math.random() - 0.5) * 0.15
                    local bx = e.x + math.cos(bAngle) * (e.radius + 4)
                    local by = e.y + math.sin(bAngle) * (e.radius + 4)
                    table.insert(G.bullets, {
                        x = bx, y = by,
                        vx = math.cos(bAngle) * e.bulletSpeed,
                        vy = math.sin(bAngle) * e.bulletSpeed,
                        damage = e.damage,
                        radius = 3,
                        fromPlayer = false,
                        life = 2.0,
                        trail = {},
                    })
                    G.PlaySfx(G.sndEnemyShoot, 0.3)

                elseif pattern == "burst" then
                    -- 三连发: 立即发射第一颗,后续通过 burstRemaining 计时
                    e.burstAngle = e.angle
                    e.burstRemaining = e.burstCount - 1
                    e.burstTimer = e.burstInterval
                    -- 第一颗立即发射
                    local bAngle = e.burstAngle + (math.random() - 0.5) * 0.06
                    local bx = e.x + math.cos(bAngle) * (e.radius + 4)
                    local by = e.y + math.sin(bAngle) * (e.radius + 4)
                    table.insert(G.bullets, {
                        x = bx, y = by,
                        vx = math.cos(bAngle) * e.bulletSpeed,
                        vy = math.sin(bAngle) * e.bulletSpeed,
                        damage = e.damage,
                        radius = 3,
                        fromPlayer = false,
                        life = 2.0,
                        trail = {},
                    })
                    G.PlaySfx(G.sndEnemyBurst, 0.3)

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
                        table.insert(G.bullets, {
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
                    G.PlaySfx(G.sndEnemyShotgun, 0.3)

                elseif pattern == "melee" then
                    -- 近战攻击
                    if dist < e.attackRange + G.player.radius and G.player.invincibleTimer <= 0 and not (G.player.dashTimer > 0) then
                        G.player.hp = G.player.hp - e.damage
                        G.player.invincibleTimer = 0.5
                        G.PlaySfx(G.sndPlayerHurt, 0.5)
                        table.insert(G.damageNumbers, {
                            x = G.player.x, y = G.player.y - G.player.radius - 5,
                            text = tostring(e.damage),
                            life = 0.8, maxLife = 0.8,
                            vy = -40,
                            isPlayer = true,
                        })
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
                end
            end
        end

        -- 受击闪烁
        if e.hitFlashTimer > 0 then
            e.hitFlashTimer = e.hitFlashTimer - dt
        end
    end

    -- 清除燃烧致死的敌人(反向遍历安全删除)
    for i = #G.enemies, 1, -1 do
        if G.enemies[i].hp <= 0 then
            local ed = G.enemies[i]
            -- 死亡粒子
            for kp = 1, 12 do
                local pa = math.random() * math.pi * 2
                local spd = 60 + math.random() * 100
                table.insert(G.particles, {
                    x = ed.x, y = ed.y,
                    vx = math.cos(pa) * spd, vy = math.sin(pa) * spd,
                    life = 0.3 + math.random() * 0.3, maxLife = 0.6,
                    r = ed.color[1], g = ed.color[2], b = ed.color[3],
                    size = 2 + math.random() * 2, gravity = 100, drag = 0.96,
                })
            end
            table.remove(G.enemies, i)
        end
    end
end

return Enemy
