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
local WeaponEffectsEvent = ReplicatedStorage:WaitForChild("WeaponEffectsEvent")
local ReloadWeaponEvent = ReplicatedStorage:WaitForChild("ReloadWeaponEvent")
local HitmarkerEvent = ReplicatedStorage:WaitForChild("HitmarkerEvent")
local DamageNumberEvent = ReplicatedStorage:WaitForChild("DamageNumberEvent")

local WEAPON_MODEL_NAME = "EquippedWeaponModel"

-- Single source of truth for "what weapon is equipped": the server-owned
-- EquippedWeapon attribute. This script only reads it; changes are requested
-- via EquipWeaponEvent and applied here once the server confirms them back.
local currentWeapon = LocalPlayer:GetAttribute("EquippedWeapon") or "AK47"

local function getStat(stat)
    local cfg = WeaponConfig[currentWeapon]
    return cfg and cfg[stat]
end

local function requestEquipSlot(slotName)
    EquipWeaponEvent:FireServer(slotName)
end

-- Ammo/reload state lives on the server (AmmoInMag/AmmoReserve/Reloading
-- attributes on LocalPlayer, same pattern as EquippedWeapon) — this script
-- only reads it, to decide locally whether it's even worth asking to fire.
local function requestReload()
    if getStat("Type") == "Melee" then return end
    if LocalPlayer:GetAttribute("Reloading") then return end -- avoid spamming the server every held-trigger tick
    ReloadWeaponEvent:FireServer()
end

-- ============================================================
-- Firing (tracers, muzzle flash, server hit request)
-- ============================================================

local canFire = true
local firing = false
local pendingFire = false -- buffers a single "clicked too early" shot to fire the instant the cooldown clears

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

local function createTracer(startPos, endPos, weaponName)
    local cfg = WeaponConfig[weaponName or currentWeapon]
    local color = (cfg and cfg.TracerColor) or Color3.fromRGB(255, 220, 80)
    local thickness = (cfg and cfg.TracerThickness) or 0.15
    local life = (cfg and cfg.TracerLifetime) or 0.08
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

-- Generic per-weapon gunshot sound: looks up a Sound named "<WeaponName>Shot"
-- in ReplicatedStorage (e.g. "AK47Shot") so adding a new weapon's fire sound
-- is just dropping in a Sound with the matching name — no code changes needed.
-- Silently does nothing if that weapon has no shot sound yet.
-- Played from a throwaway anchored part (rather than the hitmarker's flat
-- ScreenGui) so it's positional 3D audio, consistent for both the shooter and
-- anyone else nearby.
local function playWeaponFireSound(weaponName, position)
    local soundTemplate = ReplicatedStorage:FindFirstChild(weaponName .. "Shot")
    if not soundTemplate then return end

    local anchor = Instance.new("Part")
    anchor.Name = "WeaponSoundEmitter"
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.CanTouch = false
    anchor.Transparency = 1
    anchor.Size = Vector3.new(0.1, 0.1, 0.1)
    anchor.Position = position
    anchor.Parent = Workspace

    local sound = soundTemplate:Clone()
    sound.Parent = anchor
    sound:Play()
    sound.Ended:Connect(function()
        anchor:Destroy()
    end)
end

-- ============================================================
-- Hitmarker: plays a confirmation sound on a confirmed server hit,
-- with a distinct sound (and a screen-centered spark burst) for headshots.
-- ============================================================

local hitmarkerSound = ReplicatedStorage:FindFirstChild("HitmarkerSound")
local hitmarkerHeadshotSound = ReplicatedStorage:FindFirstChild("HitmarkerHeadshotSound")

local hitmarkerGui = Instance.new("ScreenGui")
hitmarkerGui.Name = "HitmarkerGui"
hitmarkerGui.ResetOnSpawn = false
hitmarkerGui.IgnoreGuiInset = true

local function addGui()
    if LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") then
        hitmarkerGui.Parent = LocalPlayer.PlayerGui
    end
end
addGui()
LocalPlayer.PlayerGui.ChildAdded:Connect(function(child)
    if child.Name == "HitmarkerGui" then return end
    addGui()
end)

-- Headshot spark burst: a handful of thin streaks fired outward from screen
-- center, then fade out. Reuses no state between bursts, so overlapping
-- headshots just add more particles instead of interrupting each other.
local SPARK_COUNT = 8
local SPARK_LENGTH = 14
local SPARK_THICKNESS = 2
local SPARK_TRAVEL = 26
local SPARK_DURATION = 0.25

local function spawnHeadshotSpark()
    for i = 1, SPARK_COUNT do
        local angle = (i / SPARK_COUNT) * math.pi * 2 + math.random() * 0.3

        local spark = Instance.new("Frame")
        spark.AnchorPoint = Vector2.new(0.5, 0.5)
        spark.Position = UDim2.new(0.5, 0, 0.5, 0)
        spark.Size = UDim2.new(0, SPARK_LENGTH, 0, SPARK_THICKNESS)
        spark.Rotation = math.deg(angle)
        spark.BackgroundColor3 = Color3.fromRGB(255, 200, 80)
        spark.BorderSizePixel = 0
        spark.Parent = hitmarkerGui

        local startTime = os.clock()
        local dx, dy = math.cos(angle), math.sin(angle)
        local conn
        conn = RunService.Heartbeat:Connect(function()
            local alpha = math.clamp((os.clock() - startTime) / SPARK_DURATION, 0, 1)
            local dist = SPARK_TRAVEL * alpha
            spark.Position = UDim2.new(0.5, dx * dist, 0.5, dy * dist)
            spark.BackgroundTransparency = alpha
            if alpha >= 1 then
                conn:Disconnect()
                spark:Destroy()
            end
        end)
    end
end

local function showHitmarker(isHeadshot)
    if isHeadshot then
        spawnHeadshotSpark()
    end

    local soundTemplate = (isHeadshot and hitmarkerHeadshotSound) or hitmarkerSound
    if soundTemplate then
        local sound = soundTemplate:Clone()
        sound.Parent = hitmarkerGui
        sound.Ended:Connect(function() sound:Destroy() end)
        sound:Play()
    end
end

HitmarkerEvent.OnClientEvent:Connect(function(isHeadshot)
    showHitmarker(isHeadshot)
end)

-- ============================================================
-- Damage numbers: accumulates repeated hits on the same target into one
-- floating number above its head. Pops in with a slight sideways arc
-- (rather than shooting straight up), then once hits stop landing it
-- falls away and fades out.
-- ============================================================

local DAMAGE_NUMBER_HOLD_TIME = 0.6 -- seconds without a new hit before it starts falling
local DAMAGE_NUMBER_ENTRY_TIME = 0.18
local DAMAGE_NUMBER_FALL_TIME = 0.6
local DAMAGE_NUMBER_RISE_HEIGHT = 2.2 -- studs, how high it settles above its base offset
local DAMAGE_NUMBER_FALL_DISTANCE = 3 -- studs, how far it drops while fading out

local activeDamageNumbers = {} -- [targetModel] = state

local function getTargetHead(targetModel)
    return targetModel:FindFirstChild("Head") or targetModel:FindFirstChildWhichIsA("BasePart")
end

local function animateDamageNumberFall(state, myToken)
    state.falling = true
    local startTime = os.clock()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if state.token ~= myToken then
            conn:Disconnect()
            return
        end
        local alpha = math.clamp((os.clock() - startTime) / DAMAGE_NUMBER_FALL_TIME, 0, 1)
        local eased = alpha * alpha -- accelerating fall, like gravity
        state.billboard.StudsOffset = state.restOffset + Vector3.new(state.sideDrift * alpha * 0.6, -DAMAGE_NUMBER_FALL_DISTANCE * eased, 0)
        state.label.TextTransparency = alpha
        state.stroke.Transparency = alpha
        if alpha >= 1 then
            conn:Disconnect()
            state.billboard:Destroy()
            if activeDamageNumbers[state.target] == state then
                activeDamageNumbers[state.target] = nil
            end
        end
    end)
end

-- Rises with an ease-out curve while drifting sideways at a steady rate:
-- the two combined trace an arc instead of a straight vertical line.
local function animateDamageNumberEntry(state)
    local startTime = os.clock()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if not state.billboard.Parent then
            conn:Disconnect()
            return
        end
        local alpha = math.clamp((os.clock() - startTime) / DAMAGE_NUMBER_ENTRY_TIME, 0, 1)
        local rise = DAMAGE_NUMBER_RISE_HEIGHT * (1 - (1 - alpha) * (1 - alpha))
        state.billboard.StudsOffset = state.baseOffset + Vector3.new(state.sideDrift * alpha, rise, 0)
        if alpha >= 1 then
            conn:Disconnect()
            state.restOffset = state.baseOffset + Vector3.new(state.sideDrift, DAMAGE_NUMBER_RISE_HEIGHT, 0)
        end
    end)
end

local function scheduleDamageNumberFall(state)
    state.token += 1
    local myToken = state.token
    task.delay(DAMAGE_NUMBER_HOLD_TIME, function()
        if state.token ~= myToken then return end -- another hit landed since this was scheduled
        animateDamageNumberFall(state, myToken)
    end)
end

local function showDamageNumber(targetModel, damage, isHeadshot)
    local head = getTargetHead(targetModel)
    if not head then return end

    local state = activeDamageNumbers[targetModel]
    if not state then
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "DamageNumber"
        billboard.Adornee = head
        billboard.AlwaysOnTop = true
        billboard.LightInfluence = 0
        billboard.Size = UDim2.new(0, 140, 0, 60)
        billboard.StudsOffset = Vector3.new(0, 1, 0)

        local label = Instance.new("TextLabel")
        label.Name = "DamageLabel"
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(1, 0, 1, 0)
        label.Font = Enum.Font.SourceSansBold
        label.TextScaled = true
        label.Text = ""
        label.Parent = billboard

        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 4
        stroke.LineJoinMode = Enum.LineJoinMode.Round
        stroke.Parent = label

        billboard.Parent = head

        state = {
            target = targetModel,
            billboard = billboard,
            label = label,
            stroke = stroke,
            accumulated = 0,
            token = 0,
            falling = false,
            baseOffset = Vector3.new(0, 1, 0),
            sideDrift = (math.random() * 2 - 1) * 1.2,
        }
        activeDamageNumbers[targetModel] = state
        animateDamageNumberEntry(state)

        targetModel.Destroying:Connect(function()
            if activeDamageNumbers[targetModel] == state then
                activeDamageNumbers[targetModel] = nil
            end
        end)
    elseif state.falling then
        -- A new hit landed mid fall-away: snap back to resting height and reset the fade.
        state.falling = false
        state.label.TextTransparency = 0
        state.stroke.Transparency = 0
        state.billboard.StudsOffset = state.restOffset or state.baseOffset
    end

    state.accumulated += damage
    state.label.Text = tostring(math.floor(state.accumulated + 0.5))

    if isHeadshot then
        state.label.TextColor3 = Color3.fromRGB(255, 60, 60)
        state.stroke.Color = Color3.fromRGB(90, 0, 0)
    else
        state.label.TextColor3 = Color3.new(1, 1, 1)
        state.stroke.Color = Color3.new(0, 0, 0)
    end

    scheduleDamageNumberFall(state)
end

DamageNumberEvent.OnClientEvent:Connect(function(targetModel, damage, isHeadshot)
    if typeof(targetModel) ~= "Instance" or not targetModel:IsDescendantOf(Workspace) then return end
    showDamageNumber(targetModel, damage, isHeadshot)
end)

local attemptFire -- forward declaration: fireBullet's cooldown callback re-triggers a buffered shot through this

local function fireBullet()
    if not canFire then
        pendingFire = true -- click landed mid-cooldown; fire it as soon as we can instead of dropping it
        return
    end
    if LocalPlayer:GetAttribute("Reloading") then return end
    local ammoInMag = LocalPlayer:GetAttribute("AmmoInMag")
    if ammoInMag ~= nil and ammoInMag <= 0 then return end -- server enforces this too; this just avoids a wasted trip
    canFire = false
    pendingFire = false

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
    playWeaponFireSound(currentWeapon, muzzlePos)

    FireWeaponEvent:FireServer(camOrigin, camDir)

    task.delay(fireRate, function()
        canFire = true
        if pendingFire then
            pendingFire = false
            attemptFire()
        end
    end)
end

-- Wraps fireBullet with the "trigger pulled on an empty mag" case: rather than
-- doing nothing, auto-request a reload (standard shooter QoL).
attemptFire = function()
    if getStat("Type") == "Melee" then return end
    if LocalPlayer:GetAttribute("Reloading") then return end
    local ammoInMag = LocalPlayer:GetAttribute("AmmoInMag")
    if ammoInMag ~= nil and ammoInMag <= 0 then
        requestReload()
        return
    end
    fireBullet()
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

local function watchOwnWeaponModel(character)
    local existing = character:FindFirstChild(WEAPON_MODEL_NAME)
    if existing then
        hideWeaponModel(existing)
    end
    character.ChildAdded:Connect(function(child)
        if child.Name == WEAPON_MODEL_NAME then
            hideWeaponModel(child)
        end
    end)
end

-- Other players' shots: the shooter already drew their own tracer/flash locally.
WeaponEffectsEvent.OnClientEvent:Connect(function(shooter, origin, hitPos)
    if shooter == LocalPlayer then return end
    local weaponName = shooter:GetAttribute("EquippedWeapon")
    local muzzlePos = origin
    local character = shooter.Character
    local model = character and character:FindFirstChild(WEAPON_MODEL_NAME)
    if model then
        muzzlePos = model:GetPivot().Position
    end
    createTracer(muzzlePos, hitPos, weaponName)
    createMuzzleFlash(muzzlePos, CFrame.lookAt(muzzlePos, hitPos))
    if weaponName then
        playWeaponFireSound(weaponName, muzzlePos)
    end
end)

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
    watchOwnWeaponModel(character)

    local humanoid = character:WaitForChild("Humanoid")
    humanoid.Died:Connect(function()
        firing = false
        pendingFire = false
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
    pendingFire = false
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
        pendingFire = false -- don't let a shot buffered for the old weapon fire under the new one's stats
        setupViewmodel()
    end
end)

-- ============================================================
-- Input: equip slots (1 = Primary, 2 = Secondary, 3 = Knife) and fire (mouse1).
-- One listener each for the whole client.
-- ============================================================

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.UserInputType == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.One then
            requestEquipSlot("Primary")
        elseif input.KeyCode == Enum.KeyCode.Two then
            requestEquipSlot("Secondary")
        elseif input.KeyCode == Enum.KeyCode.Three then
            requestEquipSlot("Knife")
        elseif input.KeyCode == Enum.KeyCode.R then
            requestReload()
        end
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
        if getStat("Type") == "Melee" then return end -- knife attack not implemented yet

        firing = true
        attemptFire()
        if getStat("Auto") then
            local rate = getStat("FireRate") or 0.12
            while firing do
                task.wait(rate)
                if not firing then break end
                attemptFire()
            end
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        firing = false
    end
end)
