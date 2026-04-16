-- ============================================================================
-- map.lua  --  地图生成与碰撞检测模块
-- ============================================================================
local G  = require("game_context")
local WM = require("wave_manager")

local Map = {}

-- ============================================================================
-- 地图生成
-- ============================================================================
function Map.GenerateMap()
    -- 根据波次调整地图大小
    local wave = WM.GetCurrentWave()
    if wave then
        G.MAP_COLS = wave.mapSize.cols
        G.MAP_ROWS = wave.mapSize.rows
    else
        G.MAP_COLS = 40
        G.MAP_ROWS = 30
    end
    G.MAP_W = G.MAP_COLS * G.TILE_SIZE
    G.MAP_H = G.MAP_ROWS * G.TILE_SIZE

    -- 初始化全部为墙
    for r = 1, G.MAP_ROWS do
        G.mapData[r] = {}
        for c = 1, G.MAP_COLS do
            G.mapData[r][c] = G.TILE_WALL
        end
    end

    -- 用房间+走廊算法挖出空间
    local rooms = {}
    local NUM_ROOMS = wave and wave.rooms or 12
    local MIN_ROOM = 4
    local MAX_ROOM = 8

    for i = 1, NUM_ROOMS do
        local rw = math.random(MIN_ROOM, MAX_ROOM)
        local rh = math.random(MIN_ROOM, MAX_ROOM)
        local rx = math.random(2, G.MAP_COLS - rw - 1)
        local ry = math.random(2, G.MAP_ROWS - rh - 1)

        -- 检查是否重叠(允许少量重叠)
        local ok = true
        for _, room in ipairs(rooms) do
            if rx < room.x + room.w + 1 and rx + rw + 1 > room.x and
               ry < room.y + room.h + 1 and ry + rh + 1 > room.y then
                ok = false
                break
            end
        end

        if ok then
            -- 挖出房间
            for r = ry, ry + rh - 1 do
                for c = rx, rx + rw - 1 do
                    G.mapData[r][c] = G.TILE_FLOOR
                end
            end
            table.insert(rooms, {x = rx, y = ry, w = rw, h = rh})
        end
    end

    -- 用走廊连接相邻房间
    for i = 2, #rooms do
        local r1 = rooms[i - 1]
        local r2 = rooms[i]
        local cx1 = math.floor(r1.x + r1.w / 2)
        local cy1 = math.floor(r1.y + r1.h / 2)
        local cx2 = math.floor(r2.x + r2.w / 2)
        local cy2 = math.floor(r2.y + r2.h / 2)

        -- 先水平再垂直
        local x = cx1
        while x ~= cx2 do
            if G.mapData[cy1] and G.mapData[cy1][x] then
                G.mapData[cy1][x] = G.TILE_FLOOR
                -- 走廊宽度2
                if cy1 + 1 <= G.MAP_ROWS then
                    G.mapData[cy1 + 1][x] = G.TILE_FLOOR
                end
            end
            x = x + (cx2 > cx1 and 1 or -1)
        end
        local y = cy1
        while y ~= cy2 do
            if G.mapData[y] and G.mapData[y][cx2] then
                G.mapData[y][cx2] = G.TILE_FLOOR
                if cx2 + 1 <= G.MAP_COLS then
                    G.mapData[y][cx2 + 1] = G.TILE_FLOOR
                end
            end
            y = y + (cy2 > cy1 and 1 or -1)
        end
    end

    -- 在随机房间放置箱子(按波次权重选择稀有度, 数量下调)
    local crateCount = 0
    for _, room in ipairs(rooms) do
        -- 60%的房间有箱子, 每房间0-1个(大幅下调)
        if math.random(1, 100) <= 60 then
            local cx = math.random(room.x + 1, room.x + room.w - 2)
            local cy = math.random(room.y + 1, room.y + room.h - 2)
            if G.mapData[cy][cx] == G.TILE_FLOOR then
                local crateType = G.PickWeightedCrate(WM.currentWave or 1)
                G.mapData[cy][cx] = crateType
                crateCount = crateCount + 1
            end
        end
    end

    -- 保存房间列表(供 SpawnExit 使用)
    G.mapRooms = rooms

    -- 玩家出生在第一个房间中心
    if #rooms >= 1 then
        local firstRoom = rooms[1]
        G.player.x = (firstRoom.x + firstRoom.w / 2) * G.TILE_SIZE
        G.player.y = (firstRoom.y + firstRoom.h / 2) * G.TILE_SIZE
    else
        G.player.x = G.MAP_W / 2
        G.player.y = G.MAP_H / 2
    end

    print("Map generated: " .. #rooms .. " rooms, " .. crateCount .. " crates")
end

-- ============================================================================
-- 出口生成 (波次清除后调用)
-- ============================================================================
function Map.SpawnExit()
    if #G.mapRooms < 2 then
        -- 只有一个房间: 在房间边缘放出口
        local room = G.mapRooms[1] or {x = G.MAP_COLS / 2 - 2, y = G.MAP_ROWS / 2 - 2, w = 4, h = 4}
        local ec = room.x + room.w - 1
        local er = room.y + room.h - 1
        G.mapData[er][ec] = G.TILE_EXIT
        WM.exitX = (ec - 0.5) * G.TILE_SIZE
        WM.exitY = (er - 0.5) * G.TILE_SIZE
        WM.exitReady = true
        return
    end

    -- 找距离玩家最远的房间
    local bestDist = -1
    local bestRoom = nil
    for _, room in ipairs(G.mapRooms) do
        local rcx = (room.x + room.w / 2) * G.TILE_SIZE
        local rcy = (room.y + room.h / 2) * G.TILE_SIZE
        local dist = math.sqrt((rcx - G.player.x)^2 + (rcy - G.player.y)^2)
        if dist > bestDist then
            bestDist = dist
            bestRoom = room
        end
    end

    if not bestRoom then
        bestRoom = G.mapRooms[#G.mapRooms]
    end

    -- 在该房间中心放置 3x3 出口区域
    local centerC = math.floor(bestRoom.x + bestRoom.w / 2)
    local centerR = math.floor(bestRoom.y + bestRoom.h / 2)
    for dr = -1, 1 do
        for dc = -1, 1 do
            local rr = centerR + dr
            local cc = centerC + dc
            if rr >= 1 and rr <= G.MAP_ROWS and cc >= 1 and cc <= G.MAP_COLS then
                if G.mapData[rr][cc] == G.TILE_FLOOR or G.IsCrateTile(G.mapData[rr][cc]) then
                    G.mapData[rr][cc] = G.TILE_EXIT
                end
            end
        end
    end

    WM.exitX = (centerC - 0.5) * G.TILE_SIZE
    WM.exitY = (centerR - 0.5) * G.TILE_SIZE
    WM.exitReady = true
    print("Exit spawned at room center: col=" .. centerC .. " row=" .. centerR)
end

-- ============================================================================
-- 碰撞检测工具
-- ============================================================================

--- 点是否在墙内
function Map.IsWall(wx, wy)
    local c = math.floor(wx / G.TILE_SIZE) + 1
    local r = math.floor(wy / G.TILE_SIZE) + 1
    if r < 1 or r > G.MAP_ROWS or c < 1 or c > G.MAP_COLS then return true end
    return G.mapData[r][c] == G.TILE_WALL
end

--- 获取指定位置的瓦片类型
function Map.GetTile(wx, wy)
    local c = math.floor(wx / G.TILE_SIZE) + 1
    local r = math.floor(wy / G.TILE_SIZE) + 1
    if r < 1 or r > G.MAP_ROWS or c < 1 or c > G.MAP_COLS then return G.TILE_WALL end
    return G.mapData[r][c]
end

--- 圆与墙的碰撞修正
function Map.ResolveWallCollision(x, y, radius)
    local newX, newY = x, y

    -- 检查四个方向
    -- 左
    if Map.IsWall(x - radius, y) then
        local wallRight = (math.floor((x - radius) / G.TILE_SIZE) + 1) * G.TILE_SIZE
        newX = math.max(newX, wallRight + radius)
    end
    -- 右
    if Map.IsWall(x + radius, y) then
        local wallLeft = math.floor((x + radius) / G.TILE_SIZE) * G.TILE_SIZE
        newX = math.min(newX, wallLeft - radius)
    end
    -- 上
    if Map.IsWall(x, y - radius) then
        local wallBottom = (math.floor((y - radius) / G.TILE_SIZE) + 1) * G.TILE_SIZE
        newY = math.max(newY, wallBottom + radius)
    end
    -- 下
    if Map.IsWall(x, y + radius) then
        local wallTop = math.floor((y + radius) / G.TILE_SIZE) * G.TILE_SIZE
        newY = math.min(newY, wallTop - radius)
    end

    return newX, newY
end

--- 两圆碰撞
function Map.CircleCollision(x1, y1, r1, x2, y2, r2)
    local dx = x2 - x1
    local dy = y2 - y1
    local dist = math.sqrt(dx * dx + dy * dy)
    return dist < (r1 + r2)
end

--- 简单的线段与墙碰撞(Bresenham式采样)
function Map.LineHitsWall(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    local dist = math.sqrt(dx * dx + dy * dy)
    local steps = math.max(1, math.floor(dist / (G.TILE_SIZE * 0.5)))
    for i = 0, steps do
        local t = i / steps
        local px = x1 + dx * t
        local py = y1 + dy * t
        if Map.IsWall(px, py) then return true end
    end
    return false
end

return Map
