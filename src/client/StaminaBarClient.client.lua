local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

-- Staminabar (inside the shared HudStack) already exists in VitalsGUI --
-- built in Studio, not generated here.
local GUI = script.Parent
local STAMINABAR = GUI:WaitForChild("HudStack"):WaitForChild("Staminabar")
local FILL = STAMINABAR:WaitForChild("Fill")

local LocalPlayer = Players.LocalPlayer

local TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Linear)

local function refresh()
    local fraction = LocalPlayer:GetAttribute("Stamina")
    if typeof(fraction) ~= "number" then
        return
    end
    TweenService:Create(FILL, TWEEN_INFO, {Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0)}):Play()
end

LocalPlayer:GetAttributeChangedSignal("Stamina"):Connect(refresh)
refresh()
