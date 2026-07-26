local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer

local WeaponEquip = require(script.Parent.WeaponEquip)
local WeaponViewmodel = require(script.Parent.WeaponViewmodel)

-- Plays the reload animation on the first-person viewmodel and fires
-- matching sounds off animation markers. Purely presentational: the server
-- is still the sole authority on ammo/reload timing (see WeaponService's
-- Reloading attribute) — this just visualizes it.
local WeaponReload = {}

-- Same "look up by name, do nothing if missing" convention as
-- WeaponEffects.playWeaponFireSound, so adding/tweaking a weapon's reload
-- animation or sounds never requires a code change.
local reloadAnimations = ReplicatedStorage:WaitForChild("Animations"):WaitForChild("Weapons")
local weaponSounds = ReplicatedStorage:WaitForChild("Sounds"):WaitForChild("Weapons")

-- Marker names the reload animations are expected to place on their timeline;
-- matching sounds are looked up as "<WeaponName><MarkerName>" (e.g. "AK47MagOut").
local RELOAD_MARKERS = {"MagOut", "MagIn", "BoltRack"}

local currentTrack = nil
local markerConnections = {}

local function disconnectMarkers()
    for _, conn in markerConnections do
        conn:Disconnect()
    end
    markerConnections = {}
end

local function playMarkerSound(weaponName, markerName)
    local soundTemplate = weaponSounds:FindFirstChild(weaponName .. markerName)
    if not soundTemplate then return end

    local sound = soundTemplate:Clone()
    sound.Parent = SoundService
    sound:Play()
    sound.Ended:Connect(function()
        sound:Destroy()
    end)
end

local function stopReload()
    if currentTrack then
        currentTrack:Stop(0.15)
        currentTrack = nil
    end
    disconnectMarkers()
end

local function playReloadAnimation()
    local weaponName = WeaponEquip.getCurrentWeapon()
    local animTemplate = reloadAnimations:FindFirstChild(weaponName .. "Reload")
    if not animTemplate or animTemplate.AnimationId == "" then return end

    local viewmodel = WeaponViewmodel.getViewmodel()
    if not viewmodel then return end
    -- Recursive lookups: AK47 keeps its AnimationController directly under
    -- the viewmodel root, but P2000's ended up nested inside its gun
    -- submodel — this works regardless of where it lives.
    local controller = viewmodel:FindFirstChild("AnimationController", true)
    local animator = controller and controller:FindFirstChildOfClass("Animator")
    if not animator then return end

    stopReload()

    local track = animator:LoadAnimation(animTemplate)
    -- Stretch/compress the clip to match the server's authoritative
    -- ReloadTime so the visuals never drift out of sync with when the
    -- server actually lets you fire again.
    local reloadTime = WeaponEquip.getStat("ReloadTime")
    if reloadTime and track.Length > 0 then
        track:AdjustSpeed(track.Length / reloadTime)
    end
    track:Play(0.1)
    currentTrack = track

    for _, markerName in RELOAD_MARKERS do
        local ok, signal = pcall(function()
            return track:GetMarkerReachedSignal(markerName)
        end)
        if ok and signal then
            local conn = signal:Connect(function()
                playMarkerSound(weaponName, markerName)
            end)
            table.insert(markerConnections, conn)
        end
    end
end

LocalPlayer:GetAttributeChangedSignal("Reloading"):Connect(function()
    if LocalPlayer:GetAttribute("Reloading") then
        playReloadAnimation()
    else
        stopReload()
    end
end)

return WeaponReload
