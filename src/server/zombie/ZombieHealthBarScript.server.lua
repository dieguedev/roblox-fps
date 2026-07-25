local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LightingConfig = require(ReplicatedStorage.Modules.LightingConfig)

local zombie = script.Parent
local humanoid = zombie:WaitForChild("Humanoid")
local head = zombie:WaitForChild("Head")
local billboard = head:WaitForChild("HealthBillboard")
local background = billboard.Background
local fill = background.Fill
local hpLabel = background.HPLabel

-- Cap the healthbar's visible range to where the map's fog actually clears,
-- so players can't read zombie HP through fog they can't see the zombie
-- through themselves (would be a de facto wallhack).
billboard.MaxDistance = LightingConfig.Lighting.FogEnd

-- Roblox's built-in overhead healthbar would otherwise show percentage-only
-- and duplicate our custom one, so it's turned off here.
humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
-- NameDisplayDistance = 0 doesn't actually hide it (Roblox falls back to the
-- model's Name); a blank-ish DisplayName is what actually suppresses the text.
humanoid.DisplayName = " "

local COLOURS = {
    Full = Color3.fromRGB(60, 200, 80),
    Mid = Color3.fromRGB(230, 180, 40),
    Low = Color3.fromRGB(220, 60, 60),
}

local TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Linear)

local function updateHealthBar()
    local scale = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
    local colour = COLOURS.Full
    if scale <= 0.35 then
        colour = COLOURS.Low
    elseif scale <= 0.85 then
        colour = COLOURS.Mid
    end
    TweenService:Create(fill, TWEEN_INFO, {Size = UDim2.new(scale, 0, 1, 0), BackgroundColor3 = colour}):Play()
    hpLabel.Text = math.ceil(math.max(humanoid.Health, 0)) .. " HP"
end

humanoid:GetPropertyChangedSignal("Health"):Connect(updateHealthBar)
humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(updateHealthBar)
updateHealthBar()

-- A dead body doesn't need a health bar floating over it.
humanoid.Died:Once(function()
    billboard.Enabled = false
end)
