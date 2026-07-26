local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local WeaponConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("WeaponConfig"))

-- ============================================================
-- STYLE: only runtime-only knobs live here -- layout, colors, fonts and
-- text sizes are set on the actual instances in AmmoHud (built in Studio,
-- not generated here), same convention as VitalsGUI/HealthBarClient.
-- ============================================================
local CONFIG = {
    IconFitPadding = 1.2, -- extra margin so the model doesn't touch the viewport edges
    -- Fallback "side view" orientation for any weapon that hasn't had
    -- WeaponConfig[weapon].IconRotation tuned yet. Tune per weapon the same
    -- way HeldOffset is tuned: visually, in Studio (this is mesh-dependent,
    -- since not every gun's "forward" axis is built the same way).
    DefaultIconRotation = CFrame.Angles(0, math.rad(90), 0),
    -- Applied on top of IconRotation, in world/camera space (not the mesh's
    -- local space), so this is a pure on-screen roll: the same value tilts
    -- every weapon's icon by the same visual amount regardless of its mesh.
    -- Positive = counter-clockwise. This is the "muzzle up-left" tilt knob.
    IconScreenTilt = math.rad(-30),

    NormalColor = Color3.fromRGB(255, 255, 255),
    LowAmmoColor = Color3.fromRGB(230, 70, 70),
    LowAmmoThreshold = 0.25, -- fraction of magazine size at/below which the count turns red
    ReloadingColor = Color3.fromRGB(230, 190, 60),
}

-- ============================================================
-- UI references: AmmoFrame/WeaponIcon/TextColumn/labels already exist in
-- AmmoHud -- built in Studio, not generated here.
-- ============================================================
local GUI = script.Parent
local frame = GUI:WaitForChild("AmmoFrame")
local iconViewport = frame:WaitForChild("WeaponIcon")
local iconCamera = iconViewport:WaitForChild("Camera")
iconViewport.CurrentCamera = iconCamera

local textColumn = frame:WaitForChild("TextColumn")
local weaponNameLabel = textColumn:WaitForChild("WeaponName")
local ammoLabel = textColumn:WaitForChild("AmmoCount")
local reloadLabel = textColumn:WaitForChild("ReloadStatus")

-- ============================================================
-- Weapon icon: clones the same gun-only mesh WeaponAttachment uses for
-- third person (the nested Model inside ReplicatedStorage.Weapons[name] --
-- the viewmodel template also bundles fake first-person arms alongside it,
-- which we don't want here), rotates it per WeaponConfig[name].IconRotation,
-- and frames a camera around its bounding box so it fits the viewport
-- regardless of the weapon's actual size.
-- ============================================================
local function getIconModelSource(weaponName)
    local weaponsFolder = ReplicatedStorage:FindFirstChild("Weapons")
    local template = weaponsFolder and weaponsFolder:FindFirstChild(weaponName)
    if not template then return nil end
    for _, child in template:GetChildren() do
        if child:IsA("Model") then
            return child
        end
    end
    return nil
end

-- Model:GetBoundingBox() returns a box aligned to the MODEL's own pivot
-- orientation, not world space -- once the model is rotated for the icon,
-- that box no longer tells us how wide/tall it looks on screen (a tilted
-- local-aligned box under-reports its world-space footprint, which is what
-- was clipping the gun against the viewport edges). This instead walks
-- every part's 8 corners in world space, so the box is always aligned to
-- the camera's axes.
local CORNER_SIGNS = {
    Vector3.new(1, 1, 1), Vector3.new(1, 1, -1), Vector3.new(1, -1, 1), Vector3.new(1, -1, -1),
    Vector3.new(-1, 1, 1), Vector3.new(-1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, -1, -1),
}
local function computeWorldAABB(model)
    local min, max
    for _, part in model:GetDescendants() do
        if part:IsA("BasePart") then
            local halfSize = part.Size / 2
            for _, sign in CORNER_SIGNS do
                local corner = part.CFrame:PointToWorldSpace(halfSize * sign)
                min = min and Vector3.new(math.min(min.X, corner.X), math.min(min.Y, corner.Y), math.min(min.Z, corner.Z)) or corner
                max = max and Vector3.new(math.max(max.X, corner.X), math.max(max.Y, corner.Y), math.max(max.Z, corner.Z)) or corner
            end
        end
    end
    if not min then return Vector3.new(), Vector3.new() end
    return (min + max) / 2, (max - min)
end

local currentIconModel = nil
local currentIconWeapon = nil

local function updateIcon(weaponName)
    if weaponName == currentIconWeapon then return end
    currentIconWeapon = weaponName

    if currentIconModel then
        currentIconModel:Destroy()
        currentIconModel = nil
    end

    local source = weaponName and getIconModelSource(weaponName)
    if not source then return end

    local model = source:Clone()
    for _, part in model:GetDescendants() do
        if part:IsA("BasePart") then
            part.Anchored = true
            part.CanCollide = false
            part.CanQuery = false
            part.CastShadow = false
        end
    end

    local cfg = WeaponConfig[weaponName]
    local baseOrientation = (cfg and cfg.IconRotation) or CONFIG.DefaultIconRotation
    local rotation = CFrame.Angles(0, 0, CONFIG.IconScreenTilt) * baseOrientation
    model:PivotTo(rotation)

    local center, size = computeWorldAABB(model)
    -- Re-center on the origin (pure world-space translation, orientation
    -- unchanged) so the camera framing below doesn't need to know the
    -- mesh's own offsets.
    model:PivotTo(CFrame.new(-center) * rotation)
    model.Parent = iconViewport
    currentIconModel = model

    local vFov = math.rad(iconCamera.FieldOfView)
    -- Viewport is always square (AspectRatioConstraint locks it), so
    -- horizontal FOV = vertical FOV.
    local distance = (math.max(size.X, size.Y) / 2 / math.tan(vFov / 2) + size.Z / 2)
        * CONFIG.IconFitPadding

    iconCamera.CFrame = CFrame.new(Vector3.new(0, 0, distance), Vector3.new(0, 0, 0))
end

-- ============================================================
-- Refresh: driven entirely by server-owned attributes on LocalPlayer
-- (EquippedWeapon / AmmoInMag / AmmoReserve / Reloading), same pattern
-- as the rest of the weapon system -- this script never guesses ammo.
-- ============================================================
local function refresh()
    local weaponName = LocalPlayer:GetAttribute("EquippedWeapon")
    local cfg = weaponName and WeaponConfig[weaponName]
    if not cfg or cfg.Type ~= "Ranged" then
        frame.Visible = false
        return
    end
    frame.Visible = true
    updateIcon(weaponName)

    weaponNameLabel.Text = weaponName

    local mag = LocalPlayer:GetAttribute("AmmoInMag") or 0
    local reserve = LocalPlayer:GetAttribute("AmmoReserve") or 0
    -- Reserve is infinite (math.huge) by design -- %d can't format that (no
    -- integer representation), so it gets its own symbol instead of a number.
    local reserveText = (reserve == math.huge) and "∞" or string.format("%d", reserve)
    ammoLabel.Text = string.format("%d / %s", mag, reserveText)

    local reloading = LocalPlayer:GetAttribute("Reloading") == true
    reloadLabel.Visible = reloading

    if reloading then
        ammoLabel.TextColor3 = CONFIG.ReloadingColor
    elseif mag <= math.floor((cfg.MagazineSize or 1) * CONFIG.LowAmmoThreshold) then
        ammoLabel.TextColor3 = CONFIG.LowAmmoColor
    else
        ammoLabel.TextColor3 = CONFIG.NormalColor
    end
end

for _, attribute in {"EquippedWeapon", "AmmoInMag", "AmmoReserve", "Reloading"} do
    LocalPlayer:GetAttributeChangedSignal(attribute):Connect(refresh)
end

refresh()