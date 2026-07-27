local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local FireWeaponEvent = Remotes:WaitForChild("FireWeaponEvent")
local ReloadWeaponEvent = Remotes:WaitForChild("ReloadWeaponEvent")

local WeaponEquip = require(script.Parent.WeaponEquip)
local WeaponViewmodel = require(script.Parent.WeaponViewmodel)
local WeaponEffects = require(script.Parent.WeaponEffects)

-- Firing itself: ammo/cooldown bookkeeping, the tracer raycast, the server
-- fire request, and both ways a shot actually gets triggered (held mouse
-- button on desktop, crosshair-over-enemy auto-fire on touch devices).
local WeaponFiring = {}

local canFire = true
local firing = false
local pendingFire = false -- buffers a single "clicked too early" shot to fire the instant the cooldown clears
local autoFiring = false -- mobile aim-assist auto-fire loop flag

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

-- Shared by fireBullet's tracer raycast and the mobile auto-fire target
-- check below, so both always aim from exactly the same place (camera
-- center, where the fixed crosshair sits) and ignore the same instances.
local function buildFireRayParams()
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    local ignore = {Camera}
    local viewmodel = WeaponViewmodel.getViewmodel()
    if viewmodel then table.insert(ignore, viewmodel) end
    if LocalPlayer.Character then table.insert(ignore, LocalPlayer.Character) end
    for _, part in CollectionService:GetTagged("BulletPass") do
        table.insert(ignore, part)
    end
    rayParams.FilterDescendantsInstances = ignore
    return rayParams
end

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

    local currentWeapon = WeaponEquip.getCurrentWeapon()
    local fireRate = WeaponEquip.getStat("FireRate") or 0.12
    local range = WeaponEquip.getStat("BulletRange") or 500

    local viewmodel = WeaponViewmodel.getViewmodel()
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

    local result = Workspace:Raycast(camOrigin, camDir, buildFireRayParams())
    local hitPos = result and result.Position or (camOrigin + camDir)

    WeaponEffects.createTracer(muzzlePos, hitPos, currentWeapon)
    WeaponEffects.createMuzzleFlash(muzzlePos, muzzleCFrame)
    WeaponEffects.playWeaponFireSound(currentWeapon, muzzlePos)

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
    if WeaponEquip.getStat("Type") == "Melee" then return end
    if LocalPlayer:GetAttribute("Reloading") then return end
    local ammoInMag = LocalPlayer:GetAttribute("AmmoInMag")
    if ammoInMag ~= nil and ammoInMag <= 0 then
        WeaponFiring.requestReload()
        return
    end
    fireBullet()
end

-- Ammo/reload state lives on the server (AmmoInMag/AmmoReserve/Reloading
-- attributes on LocalPlayer, same pattern as EquippedWeapon) — this only
-- reads it, to decide locally whether it's even worth asking to fire.
function WeaponFiring.requestReload()
    if WeaponEquip.getStat("Type") == "Melee" then return end
    if LocalPlayer:GetAttribute("Reloading") then return end -- avoid spamming the server every held-trigger tick
    ReloadWeaponEvent:FireServer()
end

-- ============================================================
-- Manual (desktop) fire: mouse button held down.
-- ============================================================

function WeaponFiring.startManualFire()
    if WeaponEquip.getStat("Type") == "Melee" then return end -- knife attack not implemented yet

    firing = true
    attemptFire()
    if WeaponEquip.getStat("Auto") then
        local rate = WeaponEquip.getStat("FireRate") or 0.12
        while firing do
            task.wait(rate)
            if not firing then break end
            attemptFire()
        end
    end
end

function WeaponFiring.stopManualFire()
    firing = false
end

-- Character died/removed: drop everything mid-flight rather than let a
-- buffered or looping shot fire into nothing.
function WeaponFiring.cancel()
    firing = false
    pendingFire = false
    autoFiring = false
end

WeaponEquip.onWeaponChanged(function()
    pendingFire = false -- don't let a shot buffered for the old weapon fire under the new one's stats
end)

-- ============================================================
-- Mobile auto-fire: touch devices have no "hold the trigger" gesture over
-- the crosshair (it's just a fixed screen-center dot, there's nothing to
-- press), so instead the weapon fires on its own whenever the crosshair is
-- resting on a live zombie. Runs at the weapon's own fire rate regardless of
-- its Auto flag — this is aim assist, not a simulated held mouse button.
-- ============================================================

-- Is the (fixed, screen-center) crosshair currently resting on a live
-- zombie? Same "Zombie" CollectionService tag WeaponService trusts
-- server-side for damage, so this stays correct if/when multiple zombies
-- get spawned in later.
local function crosshairOnLiveZombie()
    local range = WeaponEquip.getStat("BulletRange") or 500
    local camOrigin = Camera.CFrame.Position
    local camDir = Camera.CFrame.LookVector * range

    local result = Workspace:Raycast(camOrigin, camDir, buildFireRayParams())
    if not result then return false end

    local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
    if not hitModel or not CollectionService:HasTag(hitModel, "Zombie") then return false end

    local humanoid = hitModel:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0
end

local function stopAutoFire()
    autoFiring = false
    firing = false
end

local function startAutoFire()
    autoFiring = true
    firing = true
    task.spawn(function()
        while autoFiring do
            attemptFire() -- already a no-op while reloading/melee; the check below stops the loop for melee
            local rate = WeaponEquip.getStat("FireRate") or 0.12
            task.wait(rate)
        end
    end)
end

if UserInputService.TouchEnabled then
    local TARGET_CHECK_INTERVAL = 1 / 20 -- raycasting every single frame is overkill and costs more on low-end phones
    local timeSinceLastCheck = 0

    RunService.Heartbeat:Connect(function(dt)
        if WeaponEquip.getStat("Type") == "Melee" then
            if autoFiring then stopAutoFire() end
            return
        end

        timeSinceLastCheck += dt
        if timeSinceLastCheck < TARGET_CHECK_INTERVAL then return end
        timeSinceLastCheck = 0

        local onTarget = crosshairOnLiveZombie()
        if onTarget and not autoFiring then
            startAutoFire()
        elseif not onTarget and autoFiring then
            stopAutoFire()
        end
    end)
end

return WeaponFiring
