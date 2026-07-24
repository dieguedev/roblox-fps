local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Roblox parents a default "Health" Script into every character on spawn that
-- regenerates a % of MaxHealth per second unconditionally — even while the
-- player is actively being shot — which reads as a bug (heal ticks between
-- incoming hits). It's destroyed below and replaced with regen that only
-- kicks in once the player has gone a while without taking damage.
local REGEN_DELAY = 5 -- seconds since last damage before regen starts
local REGEN_RATE = 2 -- HP per second once regen is active

local lastDamageTime = {}

local function onCharacterAdded(character)
    local defaultHealthScript = character:FindFirstChild("Health")
    if defaultHealthScript and defaultHealthScript:IsA("Script") then
        defaultHealthScript:Destroy()
    end

    local humanoid = character:WaitForChild("Humanoid")
    lastDamageTime[humanoid] = os.clock()

    local previousHealth = humanoid.Health
    humanoid.HealthChanged:Connect(function(newHealth)
        if newHealth < previousHealth then
            lastDamageTime[humanoid] = os.clock()
        end
        previousHealth = newHealth
    end)

    humanoid.Died:Connect(function()
        lastDamageTime[humanoid] = nil
    end)
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(onCharacterAdded)
    if player.Character then
        onCharacterAdded(player.Character)
    end
end)

RunService.Heartbeat:Connect(function(dt)
    for humanoid, damageTime in pairs(lastDamageTime) do
        if humanoid.Parent and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
            if os.clock() - damageTime >= REGEN_DELAY then
                humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + REGEN_RATE * dt)
            end
        end
    end
end)
