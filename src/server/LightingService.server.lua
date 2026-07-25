local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LightingConfig = require(ReplicatedStorage.Modules.LightingConfig)

local function applyProperties(instance, properties)
    for property, value in pairs(properties) do
        instance[property] = value
    end
end

applyProperties(Lighting, LightingConfig.Lighting)

local colorCorrection = Lighting:FindFirstChild("ZombieMapColorCorrection")
if not colorCorrection then
    colorCorrection = Instance.new("ColorCorrectionEffect")
    colorCorrection.Name = "ZombieMapColorCorrection"
    colorCorrection.Parent = Lighting
end
applyProperties(colorCorrection, LightingConfig.ColorCorrection)

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if not atmosphere then
    atmosphere = Instance.new("Atmosphere")
    atmosphere.Parent = Lighting
end
applyProperties(atmosphere, LightingConfig.Atmosphere)
