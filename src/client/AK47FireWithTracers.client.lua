local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- Config
local WeaponConfig = require(ReplicatedStorage:WaitForChild("WeaponConfig"))
local currentWeapon = "AK47"
local FireWeaponEvent = ReplicatedStorage:WaitForChild("FireWeaponEvent")

local function getStat(stat)
    local cfg = WeaponConfig[currentWeapon]
    return cfg and cfg[stat]
end

local canFire = true
local firing = false

-- Find the viewmodel (weapon model under Camera)
local function getViewmodel()
    for _, child in Camera:GetChildren() do
        if child:IsA("Model") then return child end
    end
    return nil
end

-- Find the muzzle part (furthest part from root, or named Muzzle/Barrel/Tip)
local function getMuzzlePart(model)
    if not model then return nil end
    for _, name in {"Muzzle", "Barrel", "Tip"} do
        local p = model:FindFirstChild(name, true)
        if p and p:IsA("BasePart") then return p end
    end
    local parts = {}
    for _, p in model:GetDescendants() do
        if p:IsA("BasePart") then table.insert(parts, p) end
    end
    if #parts == 0 then return nil end
    local root = model:FindFirstChildWhichIsA("BasePart") or parts[1]
    local best, bestDist = parts[1], 0
    for _, p in parts do
        local d = (p.Position - root.Position).Magnitude
        if d > bestDist then best, bestDist = p, d end
    end
    return best
end

-- Yellow tracer from muzzle to hit point
local function createTracer(startPos, endPos)
    local color = getStat("TracerColor") or Color3.fromRGB(255, 220, 80)
    local thickness = getStat("TracerThickness") or 0.15
    local life = getStat("TracerLifetime") or 0.08
    local dist = (endPos - startPos).Magnitude
    if dist < 0.1 then return end

    local tracer = Instance.new("Part")
    tracer.Name = "Tracer"
    tracer.Anchored = true
    tracer.CanCollide = false
    tracer.CanQuery = false
    tracer.CanTouch = false
    tracer.Material = Enum.Material.Neon
    tracer.Color = color
    tracer.Transparency = 0.15
    tracer.Shape = Enum.PartType.Cylinder
    -- Cylinder extends along X axis, so X = length (dist), Y and Z = diameter (thickness)
    tracer.Size = Vector3.new(dist, thickness, thickness)
    local mid = (startPos + endPos) / 2
    -- Orient so the cylinder's X axis points from startPos toward endPos
    tracer.CFrame = CFrame.lookAt(mid, endPos) * CFrame.Angles(0, math.rad(-90), 0)
    tracer.Parent = Workspace

    task.spawn(function()
        for i = 1, 4 do
            tracer.Transparency = 0.15 + (0.85 * (i / 4))
            task.wait(life / 4)
        end
        tracer:Destroy()
    end)
end

-- Muzzle flash at barrel tip
local function createMuzzleFlash(pos, cframe)
    local flashColor = Color3.fromRGB(255, 230, 100)
    local flash = Instance.new("Part")
    flash.Name = "MuzzleFlash"
    flash.Anchored = true
    flash.CanCollide = false
    flash.CanQuery = false
    flash.CanTouch = false
    flash.Material = Enum.Material.Neon
    flash.Color = flashColor
    flash.Shape = Enum.PartType.Ball
    flash.Size = Vector3.new(0.5, 0.5, 0.5)
    flash.CFrame = cframe
    flash.Parent = Workspace

    local light = Instance.new("PointLight")
    light.Color = flashColor
    light.Brightness = 6
    light.Range = 12
    light.Parent = flash

    task.spawn(function()
        for i = 1, 3 do
            flash.Transparency = i / 3
            light.Brightness = 6 * (1 - i / 3)
            task.wait(0.02)
        end
        flash:Destroy()
    end)
end

local function fireBullet()
    if not canFire then return end
    canFire = false

    local fireRate = getStat("FireRate") or 0.12
    local range = getStat("BulletRange") or 500

    local viewmodel = getViewmodel()
    local muzzlePart = getMuzzlePart(viewmodel)

    -- Muzzle position for visual effects
    local muzzlePos, muzzleCFrame
    if muzzlePart then
        muzzleCFrame = muzzlePart.CFrame * CFrame.new(0, 0, -1)
        muzzlePos = muzzleCFrame.Position
    else
        muzzleCFrame = Camera.CFrame * CFrame.new(0, 0, -2)
        muzzlePos = muzzleCFrame.Position
    end

    -- Raycast EXACTLY from camera center (where the crosshair is)
    local camOrigin = Camera.CFrame.Position
    local camDir = Camera.CFrame.LookVector * range

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    local ignore = {Camera}
    if viewmodel then table.insert(ignore, viewmodel) end
    if LocalPlayer.Character then table.insert(ignore, LocalPlayer.Character) end
    rayParams.FilterDescendantsInstances = ignore

    local result = Workspace:Raycast(camOrigin, camDir, rayParams)
    local hitPos = result and result.Position or (camOrigin + camDir)

    -- Tracer from muzzle to the exact point the crosshair is aiming at
    createTracer(muzzlePos, hitPos)
    -- Muzzle flash
    createMuzzleFlash(muzzlePos, muzzleCFrame)

    -- Send to server: use client's hit result for damage
    FireWeaponEvent:FireServer(camOrigin, camDir, currentWeapon, result and result.Instance or nil, result and result.Position or nil)

    task.delay(fireRate, function()
        canFire = true
    end)
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        firing = true
        fireBullet()
        local rate = getStat("FireRate") or 0.12
        while firing do
            task.wait(rate)
            if not firing then break end
            fireBullet()
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, processed)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        firing = false
    end
end)
