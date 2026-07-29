local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- UI references: GoldFrame/GoldAmount already exist in GoldHud -- built
-- in Studio, not generated here (same convention as RoundHud/AmmoHud).
-- ============================================================
local GUI = script.Parent
local frame = GUI:WaitForChild("GoldFrame")
local goldLabel = frame:WaitForChild("GoldNumber")
local goldLabelBackdrop = frame:WaitForChild("GoldNumberBackdrop")

-- ============================================================
-- Refresh: driven by the server-owned "Gold" attribute on LocalPlayer
-- (set by GoldService.lua via WeaponService.server.lua), same zero-RemoteEvent
-- attribute pattern as AmmoUI/RoundUI.
-- ============================================================
local function refresh()
    local gold = LocalPlayer:GetAttribute("Gold") or 0
    goldLabel.Text = string.format("%d", gold)
    goldLabelBackdrop.Text = string.format("%d", gold)
end

LocalPlayer:GetAttributeChangedSignal("Gold"):Connect(refresh)
refresh()
