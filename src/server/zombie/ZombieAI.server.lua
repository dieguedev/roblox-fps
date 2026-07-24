local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local SimplePath = require(script.SimplePath)

local zombie = script.Parent
local humanoid = zombie:WaitForChild("Humanoid")
local rootPart = zombie:WaitForChild("HumanoidRootPart")

-- Tags WeaponService's raycast damage check so gunfire only hurts zombies,
-- never other players (no friendly fire).
CollectionService:AddTag(zombie, "Zombie")

-- Hardcoded for now (ZombieConfig with per-type stats comes in Paso 3); 150 HP
-- matches the "Normal" zombie baseline from Juego_Completo.md.
humanoid.MaxHealth = 150
humanoid.Health = 150

local REPATH_INTERVAL = 1 -- seconds between recompute checks
local REPATH_DISTANCE = 6 -- studs the target must move since the last computed path before it's worth recomputing
local CORPSE_CLEANUP_DELAY = 5 -- seconds the corpse stays before being removed, so kills don't pile up on the map

-- AgentCanJump/AgentCanClimb let the zombie get over the map's obstacles instead
-- of getting stuck at the base of them, which would let a player standing on
-- something elevated kill zombies with zero risk.
local path = SimplePath.new(zombie, {
    AgentCanJump = true,
    AgentCanClimb = true,
})
path.Visualize = false

-- Same treatment WeaponService gives player accessories: hats/hair sit in front
-- of the real Head part and would otherwise absorb the weapon's headshot raycast.
local function disableAccessoryRaycasts()
    for _, accessory in zombie:GetChildren() do
        if accessory:IsA("Accessory") then
            local handle = accessory:FindFirstChild("Handle")
            if handle then
                handle.CanQuery = false
            end
        end
    end
end
disableAccessoryRaycasts()
zombie.ChildAdded:Connect(function(child)
    if child:IsA("Accessory") then
        disableAccessoryRaycasts()
    end
end)

local function getNearestStandingPlayer()
    local nearestRoot, nearestDistance = nil, math.huge
    for _, player in Players:GetPlayers() do
        local character = player.Character
        local targetHumanoid = character and character:FindFirstChildOfClass("Humanoid")
        local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
        if targetHumanoid and targetHumanoid.Health > 0 and targetRoot then
            local distance = (targetRoot.Position - rootPart.Position).Magnitude
            if distance < nearestDistance then
                nearestRoot, nearestDistance = targetRoot, distance
            end
        end
    end
    return nearestRoot
end

-- Corpses shouldn't pile up once rounds are spawning many zombies (Paso 4).
humanoid.Died:Once(function()
    Debris:AddItem(zombie, CORPSE_CLEANUP_DELAY)
end)

local lastTargetPosition = nil

while humanoid.Health > 0 do
    local targetRoot = getNearestStandingPlayer()
    if targetRoot then
        local targetPosition = targetRoot.Position
        -- Only recompute when idle or the target has moved far enough to
        -- matter; recomputing every tick regardless of progress was what made
        -- the chase look choppy (it kept restarting MoveTo mid-stride).
        local targetMoved = not lastTargetPosition or (targetPosition - lastTargetPosition).Magnitude > REPATH_DISTANCE
        if path.Status == SimplePath.StatusType.Idle or targetMoved then
            lastTargetPosition = targetPosition
            path:Run(targetPosition)
        end
    elseif path.Status ~= SimplePath.StatusType.Idle then
        path:Stop()
        lastTargetPosition = nil
    end
    task.wait(REPATH_INTERVAL)
end
