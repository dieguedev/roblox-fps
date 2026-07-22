local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local WeaponConfig = require(ReplicatedStorage:WaitForChild("WeaponConfig"))

-- ============================================================
-- STYLE: everything visual lives here. Change freely, nothing
-- below this block needs to change to reflect it.
-- ============================================================
local CONFIG = {
    AnchorCorner = Vector2.new(1, 1), -- bottom-right
    Offset = UDim2.new(1, -24, 1, -24), -- distance from that corner
    Size = UDim2.new(0, 220, 0, 68),

    BackgroundColor = Color3.fromRGB(20, 20, 20),
    BackgroundTransparency = 0.35,
    CornerRadius = UDim.new(0, 10),

    WeaponNameColor = Color3.fromRGB(190, 190, 190),
    WeaponNameTextSize = 16,

    AmmoTextSize = 30,
    NormalColor = Color3.fromRGB(255, 255, 255),
    LowAmmoColor = Color3.fromRGB(230, 70, 70),
    LowAmmoThreshold = 0.25, -- fraction of magazine size at/below which the count turns red
    ReloadingColor = Color3.fromRGB(230, 190, 60),

    ReloadLabelText = "RECARGANDO...",
    ReloadLabelTextSize = 14,
    ReloadLabelColor = Color3.fromRGB(230, 190, 60),

    Font = Enum.Font.GothamBold,
    WeaponNameFont = Enum.Font.Gotham,
}

-- ============================================================
-- Build
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AmmoHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Name = "AmmoFrame"
frame.AnchorPoint = CONFIG.AnchorCorner
frame.Position = CONFIG.Offset
frame.Size = CONFIG.Size
frame.BackgroundColor3 = CONFIG.BackgroundColor
frame.BackgroundTransparency = CONFIG.BackgroundTransparency
frame.BorderSizePixel = 0
frame.Visible = false
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = CONFIG.CornerRadius
corner.Parent = frame

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 14)
padding.PaddingRight = UDim.new(0, 14)
padding.PaddingTop = UDim.new(0, 6)
padding.PaddingBottom = UDim.new(0, 6)
padding.Parent = frame

local weaponNameLabel = Instance.new("TextLabel")
weaponNameLabel.Name = "WeaponName"
weaponNameLabel.BackgroundTransparency = 1
weaponNameLabel.Size = UDim2.new(1, 0, 0, 18)
weaponNameLabel.Position = UDim2.new(0, 0, 0, 0)
weaponNameLabel.Font = CONFIG.WeaponNameFont
weaponNameLabel.TextSize = CONFIG.WeaponNameTextSize
weaponNameLabel.TextColor3 = CONFIG.WeaponNameColor
weaponNameLabel.TextXAlignment = Enum.TextXAlignment.Right
weaponNameLabel.Text = ""
weaponNameLabel.Parent = frame

local ammoLabel = Instance.new("TextLabel")
ammoLabel.Name = "AmmoCount"
ammoLabel.BackgroundTransparency = 1
ammoLabel.Size = UDim2.new(1, 0, 0, 36)
ammoLabel.Position = UDim2.new(0, 0, 0, 20)
ammoLabel.Font = CONFIG.Font
ammoLabel.TextSize = CONFIG.AmmoTextSize
ammoLabel.TextColor3 = CONFIG.NormalColor
ammoLabel.TextXAlignment = Enum.TextXAlignment.Right
ammoLabel.Text = "-- / --"
ammoLabel.Parent = frame

local reloadLabel = Instance.new("TextLabel")
reloadLabel.Name = "ReloadStatus"
reloadLabel.BackgroundTransparency = 1
reloadLabel.Size = UDim2.new(1, 0, 0, 16)
reloadLabel.Position = UDim2.new(0, 0, 1, -16)
reloadLabel.Font = CONFIG.Font
reloadLabel.TextSize = CONFIG.ReloadLabelTextSize
reloadLabel.TextColor3 = CONFIG.ReloadLabelColor
reloadLabel.TextXAlignment = Enum.TextXAlignment.Right
reloadLabel.Text = CONFIG.ReloadLabelText
reloadLabel.Visible = false
reloadLabel.Parent = frame

-- ============================================================
-- Refresh: driven entirely by server-owned attributes on LocalPlayer
-- (EquippedWeapon / AmmoInMag / AmmoReserve / Reloading), same pattern
-- as the rest of the weapon system — this script never guesses ammo.
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
    ammoLabel.Text = string.format("%d / %d", mag, reserve)

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
