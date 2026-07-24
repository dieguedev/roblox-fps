local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local WeaponConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("WeaponConfig"))
local WeaponEquip = require(script.Parent.WeaponEquip)

-- Everything about what the local player sees of their own weapon: the
-- first-person viewmodel (arms + gun, with bob/sway) and hiding the real
-- arms/third-person model that only other players should see.
local WeaponViewmodel = {}

function WeaponViewmodel.forceFirstPerson()
    LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
    LocalPlayer.CameraMinZoomDistance = 0.5
    LocalPlayer.CameraMaxZoomDistance = 0.5
end

function WeaponViewmodel.setRealArmsInvisible(character)
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

-- ============================================================
-- First-person viewmodel (arms + weapon model)
-- ============================================================

local viewmodel = nil
local renderConn = nil

function WeaponViewmodel.getViewmodel()
    for _, child in Camera:GetChildren() do
        if child:IsA("Model") then return child end
    end
    return nil
end

function WeaponViewmodel.remove()
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

-- Camera sway state
local lastCameraCFrame = nil
local swayOffset = CFrame.new()
local swaySmooth = 0.15
local swayAmount = 0.5

function WeaponViewmodel.setup()
    WeaponViewmodel.remove()
    local weaponsFolder = ReplicatedStorage:FindFirstChild("Weapons")
    if not weaponsFolder then return end
    local currentWeapon = WeaponEquip.getCurrentWeapon()
    local weaponTemplate = weaponsFolder:FindFirstChild(currentWeapon)
    if not weaponTemplate then return end
    viewmodel = weaponTemplate:Clone()
    viewmodel.Parent = Camera

    for _, part in viewmodel:GetDescendants() do
        if part:IsA("BasePart") then
            part.CanCollide = false
            part.Anchored = true
            part.CastShadow = false
        end
    end

    lastCameraCFrame = Camera.CFrame
    swayOffset = CFrame.new()
    -- Per-weapon nudge on top of the shared base offset: the raw templates in
    -- ReplicatedStorage.Weapons aren't built with the gun at a consistent
    -- distance from the fake arms, so some weapons need pulling forward/back
    -- to match the others (tuned visually, same as HeldOffset/IconRotation).
    local weaponCfg = WeaponConfig[currentWeapon]
    local viewmodelOffset = (weaponCfg and weaponCfg.ViewmodelOffset) or CFrame.new()

    renderConn = RunService.RenderStepped:Connect(function(dt)
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head") then
            local baseOffset = CFrame.new(0, -0.5, -0.25) * viewmodelOffset

            local speed = getMovementSpeed()
            local moveThreshold = 0.5

            local bobIntensity = math.clamp(speed / 16, 0, 1)
            local bobFrequency = 8
            local bobAmplitudeY = 0.08 * bobIntensity
            local bobAmplitudeX = 0.04 * bobIntensity
            local bobAmplitudeRot = 0.03 * bobIntensity

            -- Idle "breathing" sway: same shape as the walk bob but much
            -- slower/subtler, and it fades out as the walk bob fades in so
            -- the two never fight each other.
            local idleFrequency = 1.6
            local idleAmplitudeY = 0.03
            local idleAmplitudeX = 0.016
            local idleAmplitudeRot = 0.016
            local idleIntensity = 1 - bobIntensity

            local t = tick()
            local bobY = math.sin(t * bobFrequency) * bobAmplitudeY
            local bobX = math.cos(t * bobFrequency * 0.5) * bobAmplitudeX
            local bobRot = math.sin(t * bobFrequency * 0.5) * bobAmplitudeRot

            local idleY = math.sin(t * idleFrequency) * idleAmplitudeY * idleIntensity
            local idleX = math.cos(t * idleFrequency * 0.5) * idleAmplitudeX * idleIntensity
            local idleRot = math.sin(t * idleFrequency * 0.5) * idleAmplitudeRot * idleIntensity

            local animatedOffset = baseOffset

            if speed > moveThreshold then
                animatedOffset = animatedOffset * CFrame.new(bobX, bobY, 0) * CFrame.Angles(0, bobRot, 0)
            else
                animatedOffset = animatedOffset * CFrame.new(idleX, idleY, 0) * CFrame.Angles(0, idleRot, 0)
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

WeaponEquip.onWeaponChanged(function()
    WeaponViewmodel.setup()
end)

-- ============================================================
-- Third-person weapon model: the server welds a real "EquippedWeaponModel"
-- onto every character (WeaponAttachment), so it physically follows
-- HumanoidRootPart on its own and is visible to everyone without any
-- per-frame reposition script. We only need to hide our own copy locally
-- (we already see the first-person viewmodel instead) — Transparency
-- changes made from a LocalScript never replicate to other clients, so
-- this only affects what we see.
-- ============================================================

local function hideWeaponModel(model)
    for _, part in model:GetDescendants() do
        if part:IsA("BasePart") then
            part.Transparency = 1
        end
    end
end

function WeaponViewmodel.watchOwnWeaponModel(character)
    local existing = character:FindFirstChild(WeaponEquip.WEAPON_MODEL_NAME)
    if existing then
        hideWeaponModel(existing)
    end
    character.ChildAdded:Connect(function(child)
        if child.Name == WeaponEquip.WEAPON_MODEL_NAME then
            hideWeaponModel(child)
        end
    end)
end

return WeaponViewmodel
