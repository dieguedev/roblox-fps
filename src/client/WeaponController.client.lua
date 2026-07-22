local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local WeaponConfig = require(ReplicatedStorage:WaitForChild("WeaponConfig"))
local EquipWeaponEvent = ReplicatedStorage:WaitForChild("EquipWeaponEvent")
local FireWeaponEvent = ReplicatedStorage:WaitForChild("FireWeaponEvent")

-- Single source of truth for "what weapon is equipped": the server-owned
-- EquippedWeapon attribute. This script only reads it; changes are requested
-- via EquipWeaponEvent and applied here once the server confirms them back.
local currentWeapon = LocalPlayer:GetAttribute("EquippedWeapon") or "AK47"

local function getStat(stat)
    local cfg = WeaponConfig[currentWeapon]
    return cfg and cfg[stat]
end

local function requestEquip(weaponName)
    EquipWeaponEvent:FireServer(weaponName)
end

-- ============================================================
-- Firing (tracers, muzzle flash, server hit request)
-- ============================================================

local canFire = true
local firing = false

local function getViewmodel()
    for _, child in Camera:GetChildren() do
        if child:IsA("Model") then return child end
    end
    return nil
end

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

    local muzzlePos, muzzleCFrame
    if muzzlePart then
        muzzleCFrame = muzzlePart.CFrame * CFrame.new(0, 0, -1)
        muzzlePos = muzzleCFrame.Position
    else
        muzzleCFrame = Camera.CFrame * CFrame.new(0, 0, -2)
        muzzlePos = muzzleCFrame.Position
    end

    -- Raycast EXACTLY from camera center (where the crosshair is), purely for
    -- local visual effects. The server never trusts this and redoes its own raycast.
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

    createTracer(muzzlePos, hitPos)
    createMuzzleFlash(muzzlePos, muzzleCFrame)

    FireWeaponEvent:FireServer(camOrigin, camDir)

    task.delay(fireRate, function()
        canFire = true
    end)
end

-- ============================================================
-- First-person viewmodel (arms + weapon model)
-- ============================================================

local function setRealArmsInvisible(character)
    if not character then return end
    -- R15
    local leftUpper = character:FindFirstChild("LeftUpperArm")
    local leftLower = character:FindFirstChild("LeftLowerArm")
    local rightUpper = character:FindFirstChild("RightUpperArm")
    local rightLower = character:FindFirstChild("RightLowerArm")
    -- R6
    local leftArm = character:FindFirstChild("Left Arm")
    local rightArm = character:FindFirstChild("Right Arm")

    if leftUpper then leftUpper.Transparency = 1 end
    if leftLower then leftLower.Transparency = 1 end
    if rightUpper then rightUpper.Transparency = 1 end
    if rightLower then rightLower.Transparency = 1 end
    if leftArm then leftArm.Transparency = 1 end
    if rightArm then rightArm.Transparency = 1 end
end

local function copyArmAppearance(character, viewmodel)
    if not character or not viewmodel then return end

    local playerLeft = character:FindFirstChild("LeftUpperArm") or character:FindFirstChild("Left Arm")
    local playerRight = character:FindFirstChild("RightUpperArm") or character:FindFirstChild("Right Arm")

    local vmLeft = viewmodel:FindFirstChild("LeftArm")
    local vmRight = viewmodel:FindFirstChild("RightArm")

    if playerLeft and vmLeft and playerLeft:IsA("MeshPart") and vmLeft:IsA("MeshPart") then
        vmLeft.TextureID = playerLeft.TextureID
        vmLeft.Color = playerLeft.Color
        vmLeft.Material = playerLeft.Material
    end
    if playerRight and vmRight and playerRight:IsA("MeshPart") and vmRight:IsA("MeshPart") then
        vmRight.TextureID = playerRight.TextureID
        vmRight.Color = playerRight.Color
        vmRight.Material = playerRight.Material
    end

    local shirt = character:FindFirstChildOfClass("Shirt")
    if shirt and shirt.ShirtTemplate and shirt.ShirtTemplate ~= "" then
        local function applyShirtTexture(arm)
            if arm and arm:IsA("MeshPart") then
                local decal = arm:FindFirstChild("ShirtDecal")
                if not decal then
                    decal = Instance.new("Decal")
                    decal.Name = "ShirtDecal"
                    decal.Face = Enum.NormalId.Front
                    decal.Parent = arm
                end
                decal.Texture = shirt.ShirtTemplate
                decal.Transparency = 0
            end
        end
        applyShirtTexture(vmLeft)
        applyShirtTexture(vmRight)
    else
        local function removeShirtDecal(arm)
            if arm and arm:IsA("MeshPart") then
                local decal = arm:FindFirstChild("ShirtDecal")
                if decal then
                    decal:Destroy()
                end
            end
        end
        removeShirtDecal(vmLeft)
        removeShirtDecal(vmRight)
    end
end

local viewmodel = nil
local renderConn = nil

local function removeViewmodel()
    if renderConn then
        renderConn:Disconnect()
        renderConn = nil
    end
    if viewmodel then
        viewmodel:Destroy()
        viewmodel = nil
    end
end

local function getMovementSpeed()
    local character = LocalPlayer.Character
    if not character then return 0 end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return 0 end
    return hrp.Velocity.Magnitude
end

local function getMovementDirection()
    local character = LocalPlayer.Character
    if not character then return Vector3.new(0, 0, 0) end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return Vector3.new(0, 0, 0) end
    return hrp.Velocity
end

-- Camera sway state
local lastCameraCFrame = nil
local swayOffset = CFrame.new()
local swaySmooth = 0.15
local swayAmount = 0.5

local function setupViewmodel()
    removeViewmodel()
    local weaponsFolder = ReplicatedStorage:FindFirstChild("Weapons")
    if not weaponsFolder then return end
    local weaponTemplate = weaponsFolder:FindFirstChild(currentWeapon)
    if not weaponTemplate then return end
    viewmodel = weaponTemplate:Clone()
    viewmodel.Parent = Camera

    copyArmAppearance(LocalPlayer.Character, viewmodel)

    for _, part in viewmodel:GetDescendants() do
        if part:IsA("BasePart") then
            part.CanCollide = false
            part.Anchored = true
            part.CastShadow = false
        end
    end

    lastCameraCFrame = Camera.CFrame
    swayOffset = CFrame.new()
    renderConn = RunService.RenderStepped:Connect(function(dt)
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head") then
            local baseOffset = CFrame.new(0, -0.5, -0.25)

            local speed = getMovementSpeed()
            local moveThreshold = 0.5

            local bobIntensity = math.clamp(speed / 16, 0, 1)
            local bobFrequency = 8
            local bobAmplitudeY = 0.08 * bobIntensity
            local bobAmplitudeX = 0.04 * bobIntensity
            local bobAmplitudeRot = 0.03 * bobIntensity

            local t = tick()
            local bobY = math.sin(t * bobFrequency) * bobAmplitudeY
            local bobX = math.cos(t * bobFrequency * 0.5) * bobAmplitudeX
            local bobRot = math.sin(t * bobFrequency * 0.5) * bobAmplitudeRot

            local animatedOffset = baseOffset

            if speed > moveThreshold then
                animatedOffset = animatedOffset * CFrame.new(bobX, bobY, 0) * CFrame.Angles(0, bobRot, 0)
            end

            if lastCameraCFrame then
                local lastRight = lastCameraCFrame.RightVector
                local currentRight = Camera.CFrame.RightVector
                local lastUp = lastCameraCFrame.UpVector
                local currentUp = Camera.CFrame.UpVector
                local currentLook = Camera.CFrame.LookVector

                local yawChange = math.acos(math.clamp(lastRight:Dot(currentRight), -1, 1))
                local pitchChange = math.acos(math.clamp(lastUp:Dot(currentUp), -1, 1))

                local yawSign = (currentLook:Dot(lastRight) > 0) and 1 or -1
                local pitchSign = (currentLook:Dot(lastUp) > 0) and 1 or -1

                local swayYaw = math.clamp(yawChange * yawSign, -math.rad(swayAmount), math.rad(swayAmount))
                local swayPitch = math.clamp(pitchChange * pitchSign, -math.rad(swayAmount), math.rad(swayAmount))

                local targetSway = CFrame.Angles(swayPitch, swayYaw, 0)
                swayOffset = swayOffset:Lerp(targetSway, swaySmooth)
            end
            lastCameraCFrame = Camera.CFrame

            viewmodel:PivotTo(Camera.CFrame * animatedOffset * swayOffset)
        end
    end)
end

-- ============================================================
-- Character lifecycle
-- ============================================================

local function forceFirstPerson()
    LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
    LocalPlayer.CameraMinZoomDistance = 0.5
    LocalPlayer.CameraMaxZoomDistance = 0.5
end

local function onCharacterAdded(character)
    forceFirstPerson()
    setRealArmsInvisible(character)
    setupViewmodel()

    local humanoid = character:WaitForChild("Humanoid")
    humanoid.Died:Connect(function()
        firing = false
    end)
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

if LocalPlayer.Character then
    onCharacterAdded(LocalPlayer.Character)
else
    forceFirstPerson()
end

LocalPlayer.CharacterRemoving:Connect(function()
    firing = false
    removeViewmodel()
end)

-- ============================================================
-- Equip state: the server is the only writer of EquippedWeapon.
-- We request changes and react once the attribute actually updates.
-- ============================================================

LocalPlayer:GetAttributeChangedSignal("EquippedWeapon"):Connect(function()
    local newWeapon = LocalPlayer:GetAttribute("EquippedWeapon")
    if typeof(newWeapon) == "string" and newWeapon ~= currentWeapon then
        currentWeapon = newWeapon
        setupViewmodel()
    end
end)

if LocalPlayer:GetAttribute("EquippedWeapon") == nil then
    requestEquip("AK47")
end

-- ============================================================
-- Input: equip (1/2) and fire (mouse1), one listener each for the whole client.
-- ============================================================

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.UserInputType == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.One then
            requestEquip("AK47")
        elseif input.KeyCode == Enum.KeyCode.Two then
            requestEquip("OtherWeapon")
        end
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
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

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        firing = false
    end
end)
