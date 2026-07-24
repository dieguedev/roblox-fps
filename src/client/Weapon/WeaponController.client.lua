local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local WeaponEquip = require(script.WeaponEquip)
local WeaponViewmodel = require(script.WeaponViewmodel)
-- WeaponFiring pulls in WeaponEffects itself (tracers/flash/sound on every
-- shot), which also wires up its own remote listeners as a side effect.
local WeaponFiring = require(script.WeaponFiring)

-- ============================================================
-- Character lifecycle
-- ============================================================

local function onCharacterAdded(character)
    WeaponViewmodel.forceFirstPerson()
    WeaponViewmodel.setRealArmsInvisible(character)
    WeaponViewmodel.setup()
    WeaponViewmodel.watchOwnWeaponModel(character)

    local humanoid = character:WaitForChild("Humanoid")
    humanoid.Died:Connect(function()
        WeaponFiring.cancel()
    end)
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

if LocalPlayer.Character then
    onCharacterAdded(LocalPlayer.Character)
else
    WeaponViewmodel.forceFirstPerson()
end

LocalPlayer.CharacterRemoving:Connect(function()
    WeaponFiring.cancel()
    WeaponViewmodel.remove()
end)

-- ============================================================
-- Input: equip slots (1 = Primary, 2 = Secondary, 3 = Knife), reload (R),
-- and fire (mouse1). Mobile auto-fire is entirely self-contained inside
-- WeaponFiring. One listener each for the whole client.
-- ============================================================

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.UserInputType == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.One then
            WeaponEquip.requestEquipSlot("Primary")
        elseif input.KeyCode == Enum.KeyCode.Two then
            WeaponEquip.requestEquipSlot("Secondary")
        elseif input.KeyCode == Enum.KeyCode.Three then
            WeaponEquip.requestEquipSlot("Knife")
        elseif input.KeyCode == Enum.KeyCode.R then
            WeaponFiring.requestReload()
        end
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
        WeaponFiring.startManualFire()
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        WeaponFiring.stopManualFire()
    end
end)
