local G = require("game_context")

local Fx = {}

function Fx.TriggerShake(intensity, duration)
    G.shakeIntensity = math.max(G.shakeIntensity, intensity)
    G.shakeTimer = math.max(G.shakeTimer, duration)
end

function Fx.TriggerHitstop(duration)
    G.hitstopTimer = math.max(G.hitstopTimer, duration)
end

function Fx.UpdateShake(dt)
    if G.shakeTimer > 0 then
        G.shakeTimer = G.shakeTimer - dt
        local t = G.shakeTimer / 0.2  -- 归一化衰减
        local amp = G.shakeIntensity * math.max(0, t)
        G.shakeOffsetX = (math.random() * 2 - 1) * amp
        G.shakeOffsetY = (math.random() * 2 - 1) * amp
        if G.shakeTimer <= 0 then
            G.shakeIntensity = 0
            G.shakeOffsetX = 0
            G.shakeOffsetY = 0
        end
    end
end

function Fx.UpdateParticles(dt)
    for i = #G.particles, 1, -1 do
        local p = G.particles[i]
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
            table.remove(G.particles, i)
        end
    end
end

function Fx.UpdateDamageNumbers(dt)
    for i = #G.damageNumbers, 1, -1 do
        local d = G.damageNumbers[i]
        d.y = d.y + d.vy * dt
        d.life = d.life - dt
        if d.life <= 0 then
            table.remove(G.damageNumbers, i)
        end
    end
end

return Fx
