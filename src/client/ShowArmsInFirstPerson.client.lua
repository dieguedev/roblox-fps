local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- Force first person
local function forceFirstPerson()
    LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
    LocalPlayer.CameraMinZoomDistance = 0.5
    LocalPlayer.CameraMaxZoomDistance = 0.5
end

-- Hide real arms
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

-- Copy arm appearance from player to viewmodel, including Shirt texture if present
local function copyArmAppearance(character, viewmodel)
    if not character or not viewmodel then return end

    -- Find player's arm MeshParts
    local playerLeft = character:FindFirstChild("LeftUpperArm") or character:FindFirstChild("Left Arm")
    local playerRight = character:FindFirstChild("RightUpperArm") or character:FindFirstChild("Right Arm")

    -- Find viewmodel's arm MeshParts
    local vmLeft = viewmodel:FindFirstChild("LeftArm")
    local vmRight = viewmodel:FindFirstChild("RightArm")

    -- Copy TextureID and Color if possible
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

    -- If player has a Shirt, apply its texture to the arms
    local shirt = character:FindFirstChildOfClass("Shirt")
    if shirt and shirt.ShirtTemplate and shirt.ShirtTemplate ~= "" then
        -- Create/Update Decals on arms
        local function applyShirtTexture(arm)
            if arm and arm:IsA("MeshPart") then
                -- Try to find existing Decal
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
        -- Remove ShirtDecal if no shirt
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

-- Viewmodel logic (use equipped weapon)
local viewmodel = nil
local renderConn = nil
local equippedWeapon = "AK47"

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
    if not character then return Vector3.new(0,0,0) end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return Vector3.new(0,0,0) end
    return hrp.Velocity
end

-- Camera sway state
local lastCameraCFrame = nil
local swayOffset = CFrame.new()
local swaySmooth = 0.15 -- how quickly sway interpolates (lower = smoother)
local swayAmount = 0.5 -- max sway in degrees

local function setupViewmodel()
    removeViewmodel()
    local weaponsFolder = ReplicatedStorage:FindFirstChild("Weapons")
    if not weaponsFolder then return end
    local weaponTemplate = weaponsFolder:FindFirstChild(equippedWeapon)
    if not weaponTemplate then return end
    viewmodel = weaponTemplate:Clone()
    viewmodel.Parent = Camera

    -- Copy arm appearance from player
    copyArmAppearance(LocalPlayer.Character, viewmodel)

    -- Make sure all parts are non-collidable and only visible to local player
    for i, part in viewmodel:GetDescendants() do
        if part:IsA("BasePart") then
            part.CanCollide = false
            part.Anchored = true
            part.CastShadow = false
        end
    end

    -- Shooter-style viewmodel bob (cl_bob) + camera sway
    lastCameraCFrame = Camera.CFrame
    swayOffset = CFrame.new()
    renderConn = RunService.RenderStepped:Connect(function(dt)
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head") then
            -- Offset the viewmodel closer to the camera
            local baseOffset = CFrame.new(0, -0.5, -0.25) -- arms closer to camera

            -- Get movement speed and direction
            local speed = getMovementSpeed()
            local velocity = getMovementDirection()
            local moveThreshold = 0.5 -- minimum speed to start bobbing

            -- Bobbing parameters
            local bobIntensity = math.clamp(speed / 16, 0, 1) -- scale bob with speed
            local bobFrequency = 8 -- how fast the bob cycles
            local bobAmplitudeY = 0.08 * bobIntensity -- up/down
            local bobAmplitudeX = 0.04 * bobIntensity -- left/right
            local bobAmplitudeRot = 0.03 * bobIntensity -- rotation

            local t = tick()
            local bobY = math.sin(t * bobFrequency) * bobAmplitudeY
            local bobX = math.cos(t * bobFrequency * 0.5) * bobAmplitudeX
            local bobRot = math.sin(t * bobFrequency * 0.5) * bobAmplitudeRot

            local animatedOffset = baseOffset

            if speed > moveThreshold then
                -- Apply bobbing only when moving
                animatedOffset = animatedOffset * CFrame.new(bobX, bobY, 0) * CFrame.Angles(0, bobRot, 0)
            end

            -- Camera sway logic
            if lastCameraCFrame then
                local lastLook = lastCameraCFrame.LookVector
                local currentLook = Camera.CFrame.LookVector
                local delta = currentLook - lastLook

                -- Calculate yaw and pitch change
                local lastRight = lastCameraCFrame.RightVector
                local currentRight = Camera.CFrame.RightVector
                local lastUp = lastCameraCFrame.UpVector
                local currentUp = Camera.CFrame.UpVector

                -- Use dot product to estimate angle change
                local yawChange = math.acos(math.clamp(lastRight:Dot(currentRight), -1, 1))
                local pitchChange = math.acos(math.clamp(lastUp:Dot(currentUp), -1, 1))

                -- Direction sign
                local yawSign = (currentLook:Dot(lastRight) > 0) and 1 or -1
                local pitchSign = (currentLook:Dot(lastUp) > 0) and 1 or -1

                -- Sway amount (degrees to radians)
                local swayYaw = math.clamp(yawChange * yawSign, -math.rad(swayAmount), math.rad(swayAmount))
                local swayPitch = math.clamp(pitchChange * pitchSign, -math.rad(swayAmount), math.rad(swayAmount))

                -- Smoothly interpolate swayOffset
                local targetSway = CFrame.Angles(swayPitch, swayYaw, 0)
                swayOffset = swayOffset:Lerp(targetSway, swaySmooth)
            end
            lastCameraCFrame = Camera.CFrame

            -- Combine bobbing and sway
            viewmodel:PivotTo(Camera.CFrame * animatedOffset * swayOffset)
            -- Arms always hold weapon: don't modify Motor6Ds, just move the whole viewmodel
        end
    end)
end

local function onCharacterAdded(character)
    forceFirstPerson()
    setRealArmsInvisible(character)
    setupViewmodel()
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

if LocalPlayer.Character then
    onCharacterAdded(LocalPlayer.Character)
else
    forceFirstPerson()
end

-- Clean up viewmodel on respawn
LocalPlayer.CharacterRemoving:Connect(function()
    removeViewmodel()
end)

-- Listen for weapon equip changes (from attribute)
LocalPlayer:GetAttributeChangedSignal("EquippedWeapon"):Connect(function()
    local newWeapon = LocalPlayer:GetAttribute("EquippedWeapon")
    if typeof(newWeapon) == "string" and newWeapon ~= equippedWeapon then
        equippedWeapon = newWeapon
        setupViewmodel()
    end
end)

-- Listen for weapon equip requests (keyboard, for local preview)
local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.One then
            equippedWeapon = "AK47"
            LocalPlayer:SetAttribute("EquippedWeapon", "AK47")
            setupViewmodel()
        elseif input.KeyCode == Enum.KeyCode.Two then
            equippedWeapon = "OtherWeapon"
            LocalPlayer:SetAttribute("EquippedWeapon", "OtherWeapon")
            setupViewmodel()
        end
    end
end)
