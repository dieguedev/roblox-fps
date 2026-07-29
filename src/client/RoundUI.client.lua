local Workspace = game:GetService("Workspace")

-- ============================================================
-- UI references: RoundFrame/RoundNumber already exist in RoundHud -- built
-- in Studio, not generated here (same convention as VitalsGUI/AmmoHud).
-- ============================================================
local GUI = script.Parent
local frame = GUI:WaitForChild("RoundFrame")
local roundLabel = frame:WaitForChild("RoundNumber")
local roundLabelBackdrop = frame:WaitForChild("RoundNumberBackdrop")

-- ============================================================
-- Refresh: driven by Workspace's own "Round" attribute (set by
-- RoundService.server.lua), same zero-RemoteEvent attribute pattern as
-- AmmoUI/StaminaBar, just on Workspace instead of the player since the
-- round number is shared by everyone in the server, not per-player.
-- ============================================================
local function refresh()
    local round = Workspace:GetAttribute("Round")
    roundLabel.Text = round and string.format("RONDA %d", round) or ""
    roundLabelBackdrop.Text = round and string.format("RONDA %d", round) or ""
end

Workspace:GetAttributeChangedSignal("Round"):Connect(refresh)
refresh()