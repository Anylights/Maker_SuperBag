-- ============================================================================
-- bgm.lua — 背景音乐管理（按游戏状态/波次切换）
-- 1.ogg          → 标题/开始界面
-- 2/3/4/5.ogg    → 中间关卡（循环切换）
-- boss.ogg       → 最终 Boss 战
-- ============================================================================
local G = require("game_context")

local BGM = {}

-- 当前正在播放的曲目 key（防止重复加载/重启同一首）
local currentTrack = nil

-- SoundSource 节点 + 组件
---@type Node
local bgmNode = nil
---@type SoundSource
local bgmSource = nil

-- 各曲目资源（延迟加载）
local sounds = {}

-- 中间关卡曲目顺序（每次进入新中间关卡递进）
local MIDDLE_TRACKS = { "2", "3", "4", "5" }
local middleIndex = 0  -- 上次播放的中间关索引（0 = 还没播过）

-- ============================================================================
-- 资源加载
-- ============================================================================
local function GetSound(key)
    if sounds[key] then return sounds[key] end
    local path = "audio/" .. key .. ".ogg"
    local snd = cache:GetResource("Sound", path)
    if snd then
        -- 压缩音频(OGG)必须用 SetLoop(0, dataSize) 才能真正循环
        -- SetLooped(true) 对未压缩 PCM 才生效
        local dataSize = snd.dataSize or 0
        if dataSize > 0 then
            snd:SetLoop(0, dataSize)
        else
            snd:SetLooped(true)
        end
        sounds[key] = snd
    end
    return snd
end

-- ============================================================================
-- 初始化（创建专用节点 + SoundSource）
-- ============================================================================
function BGM.Init()
    if bgmSource then return end
    if not G.audioScene then return end
    bgmNode = G.audioScene:CreateChild("BGMNode")
    bgmSource = bgmNode:CreateComponent("SoundSource")
    bgmSource.soundType = SOUND_MUSIC  -- 受音乐主音量控制
    bgmSource.gain = 0.6
end

-- ============================================================================
-- 播放指定 key 的曲目（key 即 1/2/3/4/5/boss）
-- ============================================================================
function BGM.Play(key)
    BGM.Init()
    if not bgmSource then return end
    if currentTrack == key then return end  -- 相同曲目，不重启

    local snd = GetSound(key)
    if not snd then return end

    bgmSource:Stop()
    snd:SetLooped(true)  -- 双保险，防止 Sound 资源被其他地方共享改回 false
    bgmSource:Play(snd)
    currentTrack = key
end

function BGM.Stop()
    if bgmSource then bgmSource:Stop() end
    currentTrack = nil
end

-- ============================================================================
-- Update：每帧检查当前曲目是否已停止，若停止则重新播放（循环兜底）
-- 主循环每帧调用一次
-- ============================================================================
function BGM.Update()
    if not bgmSource or not currentTrack then return end
    if not bgmSource:IsPlaying() then
        local snd = sounds[currentTrack]
        if snd then
            bgmSource:Play(snd)
        end
    end
end

-- ============================================================================
-- 播放标题曲（1.ogg）
-- ============================================================================
function BGM.PlayTitle()
    BGM.Play("1")
    middleIndex = 0  -- 重置中间关索引，方便下次新游戏从 2.ogg 开始
end

-- ============================================================================
-- 播放 boss 曲（boss.ogg）
-- ============================================================================
function BGM.PlayBoss()
    BGM.Play("boss")
end

-- ============================================================================
-- 播放中间关曲目（每次调用切到下一首）
-- ============================================================================
function BGM.PlayNextMiddle()
    middleIndex = middleIndex + 1
    local idx = ((middleIndex - 1) % #MIDDLE_TRACKS) + 1
    BGM.Play(MIDDLE_TRACKS[idx])
end

-- ============================================================================
-- 按当前波次智能选曲（推荐入口）
-- waveIndex: 当前波次 (1..N)，最后一波为 boss
-- totalWaves: 总波次数
-- ============================================================================
function BGM.PlayForWave(waveIndex, totalWaves)
    if waveIndex >= totalWaves then
        BGM.PlayBoss()
    else
        -- 中间关：基于波次计算曲目（保证同一波重入不切歌）
        local idx = ((waveIndex - 1) % #MIDDLE_TRACKS) + 1
        BGM.Play(MIDDLE_TRACKS[idx])
    end
end

return BGM
