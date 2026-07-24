local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local EquipWeaponEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("EquipWeaponEvent")
local WeaponConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("WeaponConfig"))

-- Owns "what weapon is equipped" so every other Weapon module reads it from
-- one place instead of each tracking its own copy.
local WeaponEquip = {}

WeaponEquip.WEAPON_MODEL_NAME = "EquippedWeaponModel"

-- Single source of truth for "what weapon is equipped": the server-owned
-- EquippedWeapon attribute. This module only reads it; changes are requested
-- via EquipWeaponEvent and applied here once the server confirms them back.
local currentWeapon = LocalPlayer:GetAttribute("EquippedWeapon") or "AK47"
local changedCallbacks = {}

function WeaponEquip.getCurrentWeapon()
    return currentWeapon
end

function WeaponEquip.getStat(stat)
    local cfg = WeaponConfig[currentWeapon]
    return cfg and cfg[stat]
end

function WeaponEquip.requestEquipSlot(slotName)
    EquipWeaponEvent:FireServer(slotName)
end

-- Lets WeaponViewmodel/WeaponFiring react when the equipped weapon actually
-- changes (server-confirmed) without requiring each other directly.
function WeaponEquip.onWeaponChanged(callback)
    table.insert(changedCallbacks, callback)
end

LocalPlayer:GetAttributeChangedSignal("EquippedWeapon"):Connect(function()
    local newWeapon = LocalPlayer:GetAttribute("EquippedWeapon")
    if typeof(newWeapon) == "string" and newWeapon ~= currentWeapon then
        currentWeapon = newWeapon
        for _, callback in changedCallbacks do
            callback(newWeapon)
        end
    end
end)

return WeaponEquip
