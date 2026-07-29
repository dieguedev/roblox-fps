-- Per-match gold, server-owned. Same attribute-driven pattern as ammo/loadout
-- in WeaponService.server.lua: this module is the only writer of the "Gold"
-- attribute, clients (HUD, future shop) only ever read it.
local GoldService = {}

local gold = {}

function GoldService.init(player)
    gold[player] = 0
    player:SetAttribute("Gold", 0)
end

function GoldService.cleanup(player)
    gold[player] = nil
end

-- Resets to 0 -- called on wipe/new match once Paso 9 exists; no caller yet.
function GoldService.reset(player)
    if gold[player] == nil then return end
    gold[player] = 0
    player:SetAttribute("Gold", 0)
end

function GoldService.award(player, amount)
    if gold[player] == nil then return end
    gold[player] += amount
    player:SetAttribute("Gold", gold[player])
end

-- Spend is exposed now (even with no caller yet) so the future shop (Paso 7)
-- has a single server-authoritative gate instead of every buy handler
-- reimplementing the "enough gold?" check separately.
function GoldService.trySpend(player, amount)
    if gold[player] == nil or gold[player] < amount then
        return false
    end
    gold[player] -= amount
    player:SetAttribute("Gold", gold[player])
    return true
end

return GoldService
