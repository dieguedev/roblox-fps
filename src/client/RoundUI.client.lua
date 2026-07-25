local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- STYLE: everything visual lives here, same convention as AmmoUI.client.lua.
-- ============================================================
local CONFIG = {
    -- Scale-based so it stays proportional across resolutions/aspect ratios.
    Position = UDim2.new(0.5, 0, 0.02, 0), -- top-center, 2% inset
    Size = UDim2.new(0.12, 0, 0.05, 0),

    BackgroundColor = Color3.fromRGB(20, 20, 20),
    BackgroundTransparency = 0.35,
    CornerRadius = UDim.new(0, 10),

    TextColor = Color3.fromRGB(255, 255, 255),
    TextSize = 26,
    Font = Enum.Font.GothamBold,

    Text = "RONDA %d",
}

-- ============================================================
-- Build
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RoundHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Name = "RoundFrame"
frame.AnchorPoint = Vector2.new(0.5, 0)
frame.Position = CONFIG.Position
frame.Size = CONFIG.Size
frame.BackgroundColor3 = CONFIG.BackgroundColor
frame.BackgroundTransparency = CONFIG.BackgroundTransparency
frame.BorderSizePixel = 0
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = CONFIG.CornerRadius
corner.Parent = frame

local roundLabel = Instance.new("TextLabel")
roundLabel.Name = "RoundNumber"
roundLabel.BackgroundTransparency = 1
roundLabel.Size = UDim2.new(1, 0, 1, 0)
roundLabel.Font = CONFIG.Font
roundLabel.TextSize = CONFIG.TextSize
roundLabel.TextColor3 = CONFIG.TextColor
roundLabel.Text = ""
roundLabel.Parent = frame

-- ============================================================
-- Refresh: driven by Workspace's own "Round" attribute (set by
-- RoundService.server.lua), same zero-RemoteEvent attribute pattern as
-- AmmoUI/StaminaBar, just on Workspace instead of the player since the
-- round number is shared by everyone in the server, not per-player.
-- ============================================================
local function refresh()
    local round = Workspace:GetAttribute("Round")
    roundLabel.Text = round and string.format(CONFIG.Text, round) or ""
end

Workspace:GetAttributeChangedSignal("Round"):Connect(refresh)
refresh()
