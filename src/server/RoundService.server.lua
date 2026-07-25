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

local REST_DURATION = 15 -- fixed downtime between rounds, cannot be skipped
-- Chance that any given spawn is a Corredor instead of Normal. No mix ratio
-- is specified by the design doc for this step; tune freely.
local CORREDOR_CHANCE = 0.25

-- CoD Zombies base-count curve: grows with round, capped so the remaining
-- difficulty past that point comes only from HP scaling, not more zombies.
local function baseCountForRound(round)
    return math.min(math.floor(6 + round * 1.5 + 0.5), 40)
end

-- Solo gets the FULL base curve (not divided down to a quarter of it) so
-- round 1 already feels like a horde coming at you, not 1-2 stragglers.
-- Extra players add on top instead of the count being split between them --
-- +50% of the base count per extra player, same spirit as real CoD Zombies
-- (more players = noticeably more zombies, not the same total shared out).
local EXTRA_PER_PLAYER_FRACTION = 0.5
local function zombiesForRound(round, playerCount)
    local base = baseCountForRound(round)
    return math.max(1, math.ceil(base * (1 + EXTRA_PER_PLAYER_FRACTION * (playerCount - 1))))
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

-- Dedicated RNG instance instead of the global math.random: a whole round's
-- worth of zombies spawns back-to-back in the same frame (see runRound's
-- burst loop below), and independent math.random() calls with no yield in
-- between it turned out to streak hard -- 15 zombies could land on the same
-- point while 12 others sat empty. The shuffled-bag approach below removes
-- the streaking risk entirely: it guarantees every point is used once before
-- any point repeats, rather than trusting per-call randomness for spread.
local rng = Random.new()

local function pickZombieType()
    return (rng:NextNumber() < CORREDOR_CHANCE) and "Corredor" or "Normal"
end

-- Shuffled queue of spawn points; refilled (and reshuffled) whenever it runs
-- dry, so within any run of N spawns (N = number of eligible points) every
-- point gets used exactly once before any of them repeats.
local spawnQueue = {}

-- "Elegidos al azar evitando el más cercano a cualquier jugador": whichever
-- single spawn point is nearest to ANY player right now is excluded from
-- this batch, then the rest are shuffled into the queue.
local function refillSpawnQueue()
    local spawnPoints = {}
    for _, point in zombieSpawnsFolder:GetChildren() do
        if point:IsA("BasePart") then
            table.insert(spawnPoints, point)
        end
    end

    local nearestPoint, nearestDistance = nil, math.huge
    for _, point in spawnPoints do
        for _, player in Players:GetPlayers() do
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

    local eligible = {}
    for _, point in spawnPoints do
        if point ~= nearestPoint then
            table.insert(eligible, point)
        end
    end
    if #eligible == 0 then
        -- Only one spawn point total (or no players yet to exclude one against).
        eligible = spawnPoints
    end

    -- Fisher-Yates shuffle.
    for i = #eligible, 2, -1 do
        local j = rng:NextInteger(1, i)
        eligible[i], eligible[j] = eligible[j], eligible[i]
    end
    spawnQueue = eligible
end

local function pickSpawnPoint()
    if #spawnQueue == 0 then
        refillSpawnQueue()
    end
    return table.remove(spawnQueue)
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

    local total = zombiesForRound(round, #Players:GetPlayers())
    local aliveCount = 0

    for _ = 1, total do
        aliveCount += 1
        spawnZombie(round, function()
            aliveCount -= 1
        end)
    end

    while aliveCount > 0 do
        task.wait(0.25)
    end
end

local currentRound = 0
while true do
    currentRound += 1
    runRound(currentRound)
    task.wait(REST_DURATION)
end
