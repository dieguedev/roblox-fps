local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local WeaponConfig = require(ReplicatedStorage:WaitForChild("WeaponConfig"))
local EquipWeaponEvent = ReplicatedStorage:WaitForChild("EquipWeaponEvent")
local FireWeaponEvent = ReplicatedStorage:WaitForChild("FireWeaponEvent")

-- Server-owned source of truth: what weapon each player actually has equipped,
-- and when they last fired a valid shot (for rate limiting).
local equippedWeapon = {}
local lastFireTime = {}

local MAX_ORIGIN_DISTANCE = 10 -- studs; how far camOrigin may be from the player's head before we distrust it
local FIRE_RATE_TOLERANCE = 0.85 -- allow shots slightly faster than FireRate to absorb network jitter

Players.PlayerRemoving:Connect(function(player)
    equippedWeapon[player] = nil
    lastFireTime[player] = nil
end)

EquipWeaponEvent.OnServerEvent:Connect(function(player, weaponName)
    if typeof(weaponName) ~= "string" or not WeaponConfig[weaponName] then
        return
    end
    equippedWeapon[player] = weaponName
    player:SetAttribute("EquippedWeapon", weaponName)
end)

FireWeaponEvent.OnServerEvent:Connect(function(player, camOrigin, camDir)
    local weaponName = equippedWeapon[player]
    local cfg = weaponName and WeaponConfig[weaponName]
    if not cfg then
        return
    end

    if typeof(camOrigin) ~= "Vector3" or typeof(camDir) ~= "Vector3" then
        return
    end

    local character = player.Character
    if not character then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or humanoid.Health <= 0 then
        return
    end

    -- Rate limit: ignore shots that arrive faster than the weapon's fire rate allows.
    local now = os.clock()
    local last = lastFireTime[player]
    if last and (now - last) < (cfg.FireRate * FIRE_RATE_TOLERANCE) then
        return
    end

    -- Sanity-check the reported camera origin against the player's actual position,
    -- since the client can otherwise claim to be shooting from anywhere.
    local head = character:FindFirstChild("Head")
    local originReference = (head and head.Position) or root.Position
    if (camOrigin - originReference).Magnitude > MAX_ORIGIN_DISTANCE then
        return
    end

    lastFireTime[player] = now

    -- Never trust the client's reported hit Instance/Position: redo the raycast on the server.
    local range = cfg.BulletRange or 500
    local direction = camDir
    if direction.Magnitude > 0 then
        direction = direction.Unit * range
    else
        return
    end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {character}

    local result = Workspace:Raycast(camOrigin, direction, rayParams)
    if not result then
        return
    end

    local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
    local hitHumanoid = hitModel and hitModel:FindFirstChildOfClass("Humanoid")
    if hitHumanoid and hitHumanoid ~= humanoid and hitHumanoid.Health > 0 then
        hitHumanoid:TakeDamage(cfg.Damage or 0)
    end
end)
