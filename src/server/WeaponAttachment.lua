local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("WeaponConfig"))

local WeaponAttachment = {}

local WEAPON_MODEL_NAME = "EquippedWeaponModel"

-- Viewmodel templates in ReplicatedStorage.Weapons bundle fake first-person arms
-- (LeftArm/RightArm/HumanoidRootPart/FakeCamera) alongside the actual gun mesh;
-- third person only wants the gun mesh itself, which is the nested Model.
local function getHeldModelSource(weaponName)
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

function WeaponAttachment.clear(character)
    local existing = character:FindFirstChild(WEAPON_MODEL_NAME)
    if existing then
        existing:Destroy()
    end
end

-- Attaches (or replaces) the visible, third-person weapon model on `character`,
-- anchored and positioned relative to HumanoidRootPart. Clients reposition it
-- every frame to track HumanoidRootPart (same technique already used for the
-- first-person viewmodel) instead of a Motor6D/WeldConstraint rig, since the
-- source gun meshes are a pile of loose parts, not welded to each other.
function WeaponAttachment.equip(character, weaponName)
    WeaponAttachment.clear(character)
    if not weaponName then return end

    local cfg = WeaponConfig[weaponName]
    if not cfg or not cfg.HeldOffset then return end -- no tuned hold pose yet for this weapon

    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local source = getHeldModelSource(weaponName)
    if not source then return end -- no model uploaded for this weapon yet

    local model = source:Clone()
    model.Name = WEAPON_MODEL_NAME

    local parts = {}
    for _, part in model:GetDescendants() do
        if part:IsA("BasePart") then
            part.Anchored = false
            part.CanCollide = false
            part.CanQuery = false
            table.insert(parts, part)
        end
    end
    if #parts == 0 then
        model:Destroy()
        return
    end

    model.Parent = character
    model:PivotTo(hrp.CFrame * cfg.HeldOffset)

    -- The gun mesh is a pile of loose, unwelded parts, so each one needs its own
    -- weld to HumanoidRootPart rather than one weld on a "root" part. WeldConstraint
    -- locks in whatever relative CFrame exists at creation time (set via PivotTo
    -- above) and keeps it rigid from then on — no per-frame reposition script needed,
    -- so this follows anything with a HumanoidRootPart: players and NPCs alike.
    for _, part in parts do
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = hrp
        weld.Part1 = part
        weld.Parent = part
    end
end

return WeaponAttachment
