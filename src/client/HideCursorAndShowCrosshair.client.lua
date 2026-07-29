local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer

local WeaponEquip = require(script.Parent:WaitForChild("WeaponController"):WaitForChild("WeaponEquip"))

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

--==================================================
-- Crosshair configuration
--==================================================

local CROSSHAIR_LENGTH = 7
local CROSSHAIR_THICKNESS = 4
local CROSSHAIR_GAP = 3
local CROSSHAIR_COLOR = Color3.new(1, 1, 1)

--==================================================

local function createSegment(name, size, position)
	local segment = Instance.new("Frame")
	segment.Name = name
	segment.Size = size
	segment.Position = position
	segment.BackgroundColor3 = CROSSHAIR_COLOR
	segment.BorderSizePixel = 0
	segment.Parent = crosshair

	return segment
end

-- Top
createSegment(
	"Top",
	UDim2.new(0, CROSSHAIR_THICKNESS, 0, CROSSHAIR_LENGTH),
	UDim2.new(0.5, -CROSSHAIR_THICKNESS / 2, 0.5, -(CROSSHAIR_GAP + CROSSHAIR_LENGTH))
)

-- Bottom
createSegment(
	"Bottom",
	UDim2.new(0, CROSSHAIR_THICKNESS, 0, CROSSHAIR_LENGTH),
	UDim2.new(0.5, -CROSSHAIR_THICKNESS / 2, 0.5, CROSSHAIR_GAP)
)

-- Left
createSegment(
	"Left",
	UDim2.new(0, CROSSHAIR_LENGTH, 0, CROSSHAIR_THICKNESS),
	UDim2.new(0.5, -(CROSSHAIR_GAP + CROSSHAIR_LENGTH), 0.5, -CROSSHAIR_THICKNESS / 2)
)

-- Right
createSegment(
	"Right",
	UDim2.new(0, CROSSHAIR_LENGTH, 0, CROSSHAIR_THICKNESS),
	UDim2.new(0.5, CROSSHAIR_GAP, 0.5, -CROSSHAIR_THICKNESS / 2)
)

crosshair.Parent = crosshairGui

-- ============================================================
-- Reload bar: a thin white bar just below the crosshair that empties over
-- exactly WeaponEquip.getStat("ReloadTime") seconds, mirroring the same
-- server-authoritative Reloading attribute WeaponReload uses to drive the
-- viewmodel animation -- this is purely a second visualization of it.
-- ============================================================
local RELOAD_BAR_WIDTH = 40
local RELOAD_BAR_HEIGHT = 4
local RELOAD_BAR_GAP = 10 -- distance below the crosshair's bottom edge
-- Pill-shaped ends, same convention as VitalsGUI's Healthbar UICorner.
local RELOAD_BAR_CORNER_RADIUS = UDim.new(0.5, 0)

local reloadBarBackground = Instance.new("Frame")
reloadBarBackground.Name = "ReloadBar"
reloadBarBackground.Size = UDim2.new(0, RELOAD_BAR_WIDTH, 0, RELOAD_BAR_HEIGHT)
reloadBarBackground.AnchorPoint = Vector2.new(0.5, 0)
reloadBarBackground.Position = UDim2.new(0.5, 0, 0.5, crosshair.Size.Y.Offset / 2 + RELOAD_BAR_GAP)
reloadBarBackground.BackgroundColor3 = Color3.new(1, 1, 1)
reloadBarBackground.BackgroundTransparency = 0.7
reloadBarBackground.BorderSizePixel = 0
reloadBarBackground.Visible = false
reloadBarBackground.Parent = crosshairGui

local reloadBarBackgroundCorner = Instance.new("UICorner")
reloadBarBackgroundCorner.CornerRadius = RELOAD_BAR_CORNER_RADIUS
reloadBarBackgroundCorner.Parent = reloadBarBackground

local reloadBarFill = Instance.new("Frame")
reloadBarFill.Name = "Fill"
reloadBarFill.Size = UDim2.new(1, 0, 1, 0)
reloadBarFill.BackgroundColor3 = Color3.new(1, 1, 1)
reloadBarFill.BorderSizePixel = 0
reloadBarFill.Parent = reloadBarBackground

local reloadBarFillCorner = Instance.new("UICorner")
reloadBarFillCorner.CornerRadius = RELOAD_BAR_CORNER_RADIUS
reloadBarFillCorner.Parent = reloadBarFill

local reloadTween = nil

local function stopReloadBar()
    if reloadTween then
        reloadTween:Cancel()
        reloadTween = nil
    end
    reloadBarBackground.Visible = false
end

local function startReloadBar()
    local reloadTime = WeaponEquip.getStat("ReloadTime")
    if not reloadTime or reloadTime <= 0 then return end

    if reloadTween then
        reloadTween:Cancel()
    end

    reloadBarFill.Size = UDim2.new(1, 0, 1, 0)
    reloadBarBackground.Visible = true

    reloadTween = TweenService:Create(
        reloadBarFill,
        TweenInfo.new(reloadTime, Enum.EasingStyle.Linear),
        {Size = UDim2.new(0, 0, 1, 0)}
    )
    reloadTween:Play()
end

LocalPlayer:GetAttributeChangedSignal("Reloading"):Connect(function()
    if LocalPlayer:GetAttribute("Reloading") then
        startReloadBar()
    else
        stopReloadBar()
    end
end)

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
