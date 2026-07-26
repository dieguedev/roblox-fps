local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local WeaponConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("WeaponConfig"))

-- ============================================================
-- STYLE: only runtime-only knobs live here -- layout, colors, fonts and
-- text sizes are set on the actual instances in AmmoHud (built in Studio,
-- not generated here), same convention as VitalsGUI/HealthBarClient.
-- ============================================================
local CONFIG = {
    NormalColor = Color3.fromRGB(255, 255, 255),
    LowAmmoColor = Color3.fromRGB(230, 70, 70),
    LowAmmoThreshold = 0.25, -- fraction of magazine size at/below which the count turns red
}

-- ============================================================
-- UI references: AmmoFrame/WeaponName/AmmoRow already exist in AmmoHud --
-- built in Studio, not generated here. AmmoRow holds MagAmmo (big, current
-- magazine) and ReserveAmmo (small, reserve) side by side -- no separator,
-- the size difference alone tells them apart.
-- ============================================================
local GUI = script.Parent
local frame = GUI:WaitForChild("AmmoFrame")
local weaponNameLabel = frame:WaitForChild("WeaponName")
local ammoRow = frame:WaitForChild("AmmoRow")
local magLabel = ammoRow:WaitForChild("MagAmmo")
local reserveLabel = ammoRow:WaitForChild("ReserveAmmo")

-- ============================================================
-- Refresh: driven entirely by server-owned attributes on LocalPlayer
-- (EquippedWeapon / AmmoInMag / AmmoReserve), same pattern as the rest of
-- the weapon system -- this script never guesses ammo.
-- ============================================================
local function refresh()
    local weaponName = LocalPlayer:GetAttribute("EquippedWeapon")
    local cfg = weaponName and WeaponConfig[weaponName]
    if not cfg or cfg.Type ~= "Ranged" then
        frame.Visible = false
        return
    end
    frame.Visible = true

    weaponNameLabel.Text = weaponName

    local mag = LocalPlayer:GetAttribute("AmmoInMag") or 0
    local reserve = LocalPlayer:GetAttribute("AmmoReserve") or 0
    -- Reserve is infinite (math.huge) by design -- %d can't format that (no
    -- integer representation), so it gets its own symbol instead of a number.
    magLabel.Text = string.format("%d", mag)
    reserveLabel.Text = (reserve == math.huge) and "∞" or string.format("%d", reserve)

    if mag <= math.floor((cfg.MagazineSize or 1) * CONFIG.LowAmmoThreshold) then
        magLabel.TextColor3 = CONFIG.LowAmmoColor
    else
        magLabel.TextColor3 = CONFIG.NormalColor
    end
end

for _, attribute in {"EquippedWeapon", "AmmoInMag", "AmmoReserve"} do
    LocalPlayer:GetAttributeChangedSignal(attribute):Connect(refresh)
end

refresh()