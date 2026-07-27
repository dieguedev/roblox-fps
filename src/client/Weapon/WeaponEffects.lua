local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local WeaponEffectsEvent = Remotes:WaitForChild("WeaponEffectsEvent")
local HitmarkerEvent = Remotes:WaitForChild("HitmarkerEvent")
local DamageNumberEvent = Remotes:WaitForChild("DamageNumberEvent")

local WeaponConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("WeaponConfig"))
local WeaponEquip = require(script.Parent.WeaponEquip)

-- Purely presentational: tracers, muzzle flash, gunshot sound, hitmarkers and
-- floating damage numbers. Takes weaponName as an explicit argument wherever
-- it needs one instead of tracking "current weapon" itself.
local WeaponEffects = {}

-- ============================================================
-- Tracer / muzzle flash / gunshot sound
-- ============================================================

function WeaponEffects.createTracer(startPos, endPos, weaponName)
    local cfg = WeaponConfig[weaponName]
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

-- Layered particle burst (core flash + directional sparks + light smoke) fired
-- from an Attachment, rather than a single flat sprite/part. Particles inherit
-- the attachment's 3D orientation automatically, so unlike a billboarded
-- sprite there's no manual rotation to get wrong. Uses Roblox's built-in
-- particle textures so no asset uploads are needed.
local MUZZLE_FLASH_CORE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local MUZZLE_FLASH_SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local MUZZLE_FLASH_SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

function WeaponEffects.createMuzzleFlash(pos, cframe)
    local flashColor = Color3.fromRGB(255, 230, 100)

    local anchor = Instance.new("Part")
    anchor.Name = "MuzzleFlashAnchor"
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.CanTouch = false
    anchor.Transparency = 1
    anchor.Size = Vector3.new(0.1, 0.1, 0.1)
    anchor.CFrame = cframe
    anchor.Parent = Workspace

    local attachment = Instance.new("Attachment")
    attachment.Parent = anchor

    local light = Instance.new("PointLight")
    light.Color = flashColor
    light.Brightness = 6
    light.Range = 12
    light.Parent = anchor

    local core = Instance.new("ParticleEmitter")
    core.Texture = MUZZLE_FLASH_CORE_TEXTURE
    core.Color = ColorSequence.new(flashColor)
    core.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1.2),
        NumberSequenceKeypoint.new(1, 0),
    })
    core.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    core.Lifetime = NumberRange.new(0.04, 0.06)
    core.Speed = NumberRange.new(0)
    core.Rate = 0
    core.LightEmission = 1
    core.LightInfluence = 0
    core.EmissionDirection = Enum.NormalId.Front
    core.Rotation = NumberRange.new(0, 360)
    core.Parent = attachment

    local sparks = Instance.new("ParticleEmitter")
    sparks.Texture = MUZZLE_FLASH_SPARK_TEXTURE
    sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 120))
    sparks.Size = NumberSequence.new(0.15)
    sparks.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 1),
    })
    sparks.Lifetime = NumberRange.new(0.05, 0.1)
    sparks.Speed = NumberRange.new(15, 25)
    sparks.SpreadAngle = Vector2.new(8, 8)
    sparks.Rate = 0
    sparks.LightEmission = 1
    sparks.EmissionDirection = Enum.NormalId.Front
    sparks.Parent = attachment

    local smoke = Instance.new("ParticleEmitter")
    smoke.Texture = MUZZLE_FLASH_SMOKE_TEXTURE
    smoke.Color = ColorSequence.new(Color3.fromRGB(120, 120, 120))
    smoke.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.4),
        NumberSequenceKeypoint.new(1, 1.4),
    })
    smoke.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.6),
        NumberSequenceKeypoint.new(1, 1),
    })
    smoke.Lifetime = NumberRange.new(0.3, 0.5)
    smoke.Speed = NumberRange.new(2, 4)
    smoke.SpreadAngle = Vector2.new(15, 15)
    smoke.Rate = 0
    smoke.EmissionDirection = Enum.NormalId.Front
    smoke.Parent = attachment

    core:Emit(2)
    sparks:Emit(6)
    smoke:Emit(2)

    task.spawn(function()
        for i = 1, 3 do
            light.Brightness = 6 * (1 - i / 3)
            task.wait(0.02)
        end
    end)

    task.delay(0.6, function()
        anchor:Destroy()
    end)
end

-- Generic per-weapon gunshot sound: looks up a Sound named "<WeaponName>Shot"
-- in ReplicatedStorage.Sounds.Weapons (e.g. "AK47Shot") so adding a new
-- weapon's fire sound is just dropping in a Sound with the matching name —
-- no code changes needed.
-- Silently does nothing if that weapon has no shot sound yet.
-- Played from a throwaway anchored part (rather than the hitmarker's flat
-- ScreenGui) so it's positional 3D audio, consistent for both the shooter and
-- anyone else nearby.
local weaponSounds = ReplicatedStorage:WaitForChild("Sounds"):WaitForChild("Weapons")

function WeaponEffects.playWeaponFireSound(weaponName, position)
    local soundTemplate = weaponSounds:FindFirstChild(weaponName .. "Shot")
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

local hitmarkerSounds = ReplicatedStorage:WaitForChild("Sounds"):WaitForChild("Hitmarker")
local hitmarkerSound = hitmarkerSounds:FindFirstChild("HitmarkerSound")
local hitmarkerHeadshotSound = hitmarkerSounds:FindFirstChild("HitmarkerHeadshotSound")

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
        -- Scale (studs), not Offset (pixels) -- same convention as the zombie
        -- HP billboard, so the number keeps a consistent world-space size
        -- across devices instead of a fixed pixel box that reads oversized
        -- on a small mobile screen.
        billboard.Size = UDim2.new(3.3, 0, 1.35, 0)
        billboard.StudsOffset = Vector3.new(0, 1, 0)

        local label = Instance.new("TextLabel")
        label.Name = "DamageLabel"
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(1, 0, 1, 0)
        label.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold, Enum.FontStyle.Normal)
        label.TextScaled = true
        label.Text = ""
        label.Parent = billboard

        local stroke = Instance.new("UIStroke")
        stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
        stroke.Thickness = 0.15
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

-- ============================================================
-- Other players' shots: the shooter already drew their own tracer/flash
-- locally, this replays the same effects for everyone else watching.
-- ============================================================

WeaponEffectsEvent.OnClientEvent:Connect(function(shooter, origin, hitPos)
    if shooter == LocalPlayer then return end
    local weaponName = shooter:GetAttribute("EquippedWeapon")
    local muzzlePos = origin
    local character = shooter.Character
    local model = character and character:FindFirstChild(WeaponEquip.WEAPON_MODEL_NAME)
    if model then
        muzzlePos = model:GetPivot().Position
    end
    WeaponEffects.createTracer(muzzlePos, hitPos, weaponName)
    WeaponEffects.createMuzzleFlash(muzzlePos, CFrame.lookAt(muzzlePos, hitPos))
    if weaponName then
        WeaponEffects.playWeaponFireSound(weaponName, muzzlePos)
    end
end)

return WeaponEffects
