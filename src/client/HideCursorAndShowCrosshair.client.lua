local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Hide the default mouse cursor
UserInputService.MouseIconEnabled = false

-- Create crosshair GUI
local crosshairGui = Instance.new("ScreenGui")
crosshairGui.Name = "CrosshairGui"
crosshairGui.ResetOnSpawn = false
crosshairGui.IgnoreGuiInset = true

local crosshair = Instance.new("Frame")
crosshair.Name = "Crosshair"
crosshair.Size = UDim2.new(0, 24, 0, 24)
crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
crosshair.Position = UDim2.new(0.5, 0, 0.5, 0)
crosshair.BackgroundTransparency = 1

-- Create vertical line
local vertical = Instance.new("Frame")
vertical.Size = UDim2.new(0, 4, 0, 24)
vertical.Position = UDim2.new(0.5, -2, 0, 0)
vertical.BackgroundColor3 = Color3.new(1, 1, 1)
vertical.BorderSizePixel = 0
vertical.Parent = crosshair

-- Create horizontal line
local horizontal = Instance.new("Frame")
horizontal.Size = UDim2.new(0, 24, 0, 4)
horizontal.Position = UDim2.new(0, 0, 0.5, -2)
horizontal.BackgroundColor3 = Color3.new(1, 1, 1)
horizontal.BorderSizePixel = 0
horizontal.Parent = crosshair

crosshair.Parent = crosshairGui

-- Parent to player's PlayerGui
local function addGui()
    if LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") then
        crosshairGui.Parent = LocalPlayer.PlayerGui
    end
end

if LocalPlayer then
    addGui()
end

LocalPlayer.PlayerGui.ChildAdded:Connect(function(child)
    if child.Name == "CrosshairGui" then return end
    addGui()
end)
