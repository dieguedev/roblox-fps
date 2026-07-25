local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZombieConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ZombieConfig"))

-- ============================================================
-- Studio-side prerequisites (not synced by Rojo, must exist before this
-- script can spawn anything):
--   ServerStorage.ZombieTemplates.Normal   (Model, same shape as the
--                                            manually-placed Workspace zombies)
--   ServerStorage.ZombieTemplates.Corredor (Model)
--   Workspace.ZombieSpawns                 (Folder of BaseParts, one per spawn point)
-- ============================================================
local zombieTemplates = ServerStorage:WaitForChild("ZombieTemplates")
local templatesByType = {
    Normal = zombieTemplates:WaitForChild("Normal"),
    Corredor = zombieTemplates:WaitForChild("Corredor"),
}

local zombieSpawnsFolder = Workspace:WaitForChild("ZombieSpawns")

local SPAWN_INTERVAL = 3 -- seconds between staggered spawns while zombies are still alive
local REST_DURATION = 15 -- fixed downtime between rounds, cannot be skipped
-- Chance that any given spawn is a Corredor instead of Normal. No mix ratio
-- is specified by the design doc for this step; tune freely.
local CORREDOR_CHANCE = 0.25

-- CoD Zombies base-count curve: grows with round, capped so the remaining
-- difficulty past that point comes only from HP scaling, not more zombies.
local function baseCountForRound(round)
    return math.min(math.floor(6 + round * 1.5 + 0.5), 40)
end

-- Scales zombie count with players present, not per-zombie HP (HP depends
-- only on round). Minimum of 1 so a lone player never sees an empty queue.
local function zombiesForRound(round, playerCount)
    return math.max(1, math.ceil(baseCountForRound(round) * playerCount / 4))
end

-- Real CoD Zombies HP curve, computed off the Normal baseline and then
-- scaled by the type's own ratio to Normal (e.g. Corredor stays ~66.7%
-- of Normal at every round, not just at round 1).
local NORMAL_BASE_HEALTH = ZombieConfig.Normal.MaxHealth
local function healthForRound(typeBaseHealth, round)
    local normalHealthAtRound
    if round <= 9 then
        normalHealthAtRound = NORMAL_BASE_HEALTH + 100 * (round - 1)
    else
        local normalHealthAtRound9 = NORMAL_BASE_HEALTH + 100 * 8
        normalHealthAtRound = normalHealthAtRound9 * 1.1 ^ (round - 9)
    end
    local ratioToNormal = typeBaseHealth / NORMAL_BASE_HEALTH
    return normalHealthAtRound * ratioToNormal
end

local function pickZombieType()
    return (math.random() < CORREDOR_CHANCE) and "Corredor" or "Normal"
end

-- "Elegidos al azar evitando el más cercano a cualquier jugador": finds
-- whichever single spawn point is nearest to ANY player right now and
-- excludes just that one, then picks randomly among the rest.
local function pickSpawnPoint()
    local spawnPoints = zombieSpawnsFolder:GetChildren()
    local players = Players:GetPlayers()

    local nearestPoint, nearestDistance = nil, math.huge
    for _, point in spawnPoints do
        if point:IsA("BasePart") then
            for _, player in players do
                local character = player.Character
                local root = character and character:FindFirstChild("HumanoidRootPart")
                if root then
                    local distance = (root.Position - point.Position).Magnitude
                    if distance < nearestDistance then
                        nearestPoint, nearestDistance = point, distance
                    end
                end
            end
        end
    end

    local eligible = {}
    for _, point in spawnPoints do
        if point:IsA("BasePart") and point ~= nearestPoint then
            table.insert(eligible, point)
        end
    end
    if #eligible == 0 then
        -- Only one spawn point total (or no players yet to exclude one against).
        eligible = spawnPoints
    end
    return eligible[math.random(1, #eligible)]
end

-- Spawns immediately and returns once the zombie is parented; the caller
-- tracks liveness via the Died connection made here (connected before
-- Parent is set, so a same-frame death can't be missed).
local function spawnZombie(round, onDied)
    local zombieType = pickZombieType()
    local template = templatesByType[zombieType]
    local clone = template:Clone()

    -- Set before Parent so ZombieAI.server.lua (which starts running the
    -- instant it's parented) reads the round-scaled HP on its very first
    -- line instead of racing against this script to set it afterward.
    clone:SetAttribute("ZombieType", zombieType)
    clone:SetAttribute("RoundMaxHealth", healthForRound(ZombieConfig[zombieType].MaxHealth, round))

    local humanoid = clone:FindFirstChildOfClass("Humanoid")
    humanoid.Died:Once(onDied)

    local spawnPoint = pickSpawnPoint()
    clone:PivotTo(spawnPoint.CFrame + Vector3.new(0, 3, 0))
    clone.Parent = Workspace
end

local function runRound(round)
    Workspace:SetAttribute("Round", round)

    local queueRemaining = zombiesForRound(round, #Players:GetPlayers())
    local aliveCount = 0
    local lastSpawnTime = -math.huge

    while queueRemaining > 0 or aliveCount > 0 do
        if queueRemaining > 0 and (aliveCount == 0 or os.clock() - lastSpawnTime >= SPAWN_INTERVAL) then
            queueRemaining -= 1
            aliveCount += 1
            lastSpawnTime = os.clock()
            spawnZombie(round, function()
                aliveCount -= 1
            end)
        end
        task.wait(0.25)
    end
end

local currentRound = 0
while true do
    currentRound += 1
    runRound(currentRound)
    task.wait(REST_DURATION)
end
