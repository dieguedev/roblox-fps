local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local WeaponConfig = require(ReplicatedStorage:WaitForChild("WeaponConfig"))

local currentWeapon = "AK47"

-- Equip system: request server to equip weapon
local EquipWeaponEvent = ReplicatedStorage:WaitForChild("EquipWeaponEvent")
local function equipWeapon(weaponName)
    currentWeapon = weaponName
    EquipWeaponEvent:FireServer(weaponName)
end

-- Example: equip AK47 on spawn
if LocalPlayer then
    equipWeapon("AK47")
end

-- NOTE: Firing logic is handled by AK47FireWithTracers LocalScript
-- This script only handles weapon equipping
-- Firing system moved to AK47FireWithTracers to avoid duplicate firing

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.One then
            equipWeapon("AK47")
        elseif input.KeyCode == Enum.KeyCode.Two then
            equipWeapon("OtherWeapon")
        end
    end
end)
