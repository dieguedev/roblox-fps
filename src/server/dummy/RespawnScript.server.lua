local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local WeaponAttachment = require(ServerScriptService:WaitForChild("WeaponAttachment"))

local RESPAWN_DELAY = 2
local WEAPON_NAME = "AK47"

local dummy = script.Parent
local humanoid = dummy:WaitForChild("Humanoid")

-- Captured once, before any damage, so every future respawn comes back
-- healthy and in the original spot -- same idea as a player's CharacterAdded.
local spawnCFrame = dummy:GetPivot()
local template = dummy:Clone()

humanoid.Died:Connect(function()
    task.wait(RESPAWN_DELAY)

    local clone = template:Clone()
    clone:PivotTo(spawnCFrame)
    clone.Parent = dummy.Parent
    WeaponAttachment.equip(clone, WEAPON_NAME)

    dummy:Destroy()
end)
