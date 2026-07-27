local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local WeaponConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("WeaponConfig"))
local WeaponEquip = require(LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("WeaponController"):WaitForChild("WeaponEquip"))

-- ============================================================
-- STYLE: only runtime-only knobs live here -- layout, colors, the square's
-- background/corner/aspect-ratio and the icon's bleed-over-the-edge size are
-- set on the actual instances in WeaponSlots (built in Studio, not generated
-- here), same convention as the rest of the HUD.
-- ============================================================
local CONFIG = {
    RestingScale = 1,
    ActiveScale = 1.15, -- how much wider/taller the equipped slot's square grows
    TweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

-- ============================================================
-- UI references: WeaponSlots/<Slot>Slot/<Slot>Icon already exist in AmmoHud --
-- built in Studio, not generated here. <Slot>Slot (the Frame) is the black
-- square with the corner radius and the 1:1 aspect ratio -- that's what
-- grows on equip. <Slot>Icon (the ImageLabel inside) is Scale-sized relative
-- to its own square, bigger than 100% so the weapon art bleeds past the
-- square's edges -- growing the square automatically grows the icon with it,
-- no separate tween needed for the icon. Both are anchored bottom-center
-- (AnchorPoint 0.5, 1), so growing only expands sideways/upward and never
-- shifts the baseline or the neighboring slots.
-- ============================================================
local GUI = script.Parent
local weaponSlots = GUI:WaitForChild("WeaponSlots")

local SLOT_BOXES = {
    Primary = weaponSlots:WaitForChild("PrimarySlot"),
    Secondary = weaponSlots:WaitForChild("SecondarySlot"),
    Knife = weaponSlots:WaitForChild("KnifeSlot"),
}

local SLOT_ICONS = {
    Primary = SLOT_BOXES.Primary:WaitForChild("PrimaryIcon"),
    Secondary = SLOT_BOXES.Secondary:WaitForChild("SecondaryIcon"),
    Knife = SLOT_BOXES.Knife:WaitForChild("KnifeIcon"),
}

local activeTweens = {}

local function setBoxScale(box, scale)
    if activeTweens[box] then
        activeTweens[box]:Cancel()
    end
    local tween = TweenService:Create(box, CONFIG.TweenInfo, {
        Size = UDim2.new(scale, 0, scale, 0),
    })
    activeTweens[box] = tween
    tween:Play()
end

-- ============================================================
-- Icons: driven by the Loadout_<Slot> attributes (which weapon sits in each
-- slot), set once by the server when the player's loadout loads. Set once on
-- attribute-changed, not every frame -- the loadout doesn't change mid-game
-- right now (no in-game weapon-swap UI yet).
-- ============================================================
local function refreshIcon(slotName)
    local icon = SLOT_ICONS[slotName]
    local weaponName = LocalPlayer:GetAttribute("Loadout_" .. slotName)
    local cfg = weaponName and WeaponConfig[weaponName]
    icon.Image = (cfg and cfg.Icon) or ""
end

for slotName in SLOT_ICONS do
    LocalPlayer:GetAttributeChangedSignal("Loadout_" .. slotName):Connect(function()
        refreshIcon(slotName)
    end)
    refreshIcon(slotName)
end

-- ============================================================
-- Highlight: the currently equipped weapon's slot grows a bit, the other two
-- stay at resting size. EquippedWeapon is the weapon name, not the slot name,
-- so map it back to a slot via WeaponConfig[name].Slot.
-- ============================================================
local function refreshActiveSlot()
    local equippedWeapon = LocalPlayer:GetAttribute("EquippedWeapon")
    local cfg = equippedWeapon and WeaponConfig[equippedWeapon]
    local activeSlot = cfg and cfg.Slot

    for slotName, box in SLOT_BOXES do
        setBoxScale(box, (slotName == activeSlot) and CONFIG.ActiveScale or CONFIG.RestingScale)
    end
end

LocalPlayer:GetAttributeChangedSignal("EquippedWeapon"):Connect(refreshActiveSlot)
refreshActiveSlot()

-- ============================================================
-- Tap-to-equip: mobile only. On desktop the cursor is locked to the
-- crosshair (see HideCursorAndShowCrosshair), so there's no free pointer to
-- click these with -- touch doesn't need one, so it's gated explicitly here
-- instead of relying on that.
-- ============================================================
if UserInputService.TouchEnabled then
    for slotName, box in SLOT_BOXES do
        box.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch then
                WeaponEquip.requestEquipSlot(slotName)
            end
        end)
    end
end
