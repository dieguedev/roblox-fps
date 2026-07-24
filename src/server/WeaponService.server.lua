local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local DataStoreService = game:GetService("DataStoreService")
local CollectionService = game:GetService("CollectionService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local WeaponConfig = require(Modules:WaitForChild("WeaponConfig"))
local WeaponAttachment = require(script.Parent:WaitForChild("WeaponAttachment"))
local EquipWeaponEvent = Remotes:WaitForChild("EquipWeaponEvent")
local FireWeaponEvent = Remotes:WaitForChild("FireWeaponEvent")
local WeaponEffectsEvent = Remotes:WaitForChild("WeaponEffectsEvent")
local ReloadWeaponEvent = Remotes:WaitForChild("ReloadWeaponEvent")
local HitmarkerEvent = Remotes:WaitForChild("HitmarkerEvent")
local DamageNumberEvent = Remotes:WaitForChild("DamageNumberEvent")

local loadoutStore = DataStoreService:GetDataStore("PlayerLoadout_v1")

local SLOTS = {"Primary", "Secondary", "Knife"}
-- Every player starts owning these three; a future shop grants better weapons
-- per slot (e.g. Primary = "SCAR-L") and that assignment gets persisted the same way.
local DEFAULT_LOADOUT = {Primary = "AK47", Secondary = "P2000", Knife = "Knife"}
local DEFAULT_ACTIVE_SLOT = "Primary"

-- Server-owned source of truth: which weapon each player has assigned to each
-- slot, which slot they're currently holding, and when they last fired a valid
-- shot (for rate limiting).
local loadouts = {}
local activeSlot = {}
local equippedWeapon = {}
local lastFireTime = {}

-- Ammo, like the loadout, is server-owned: ammoState[player][weaponName] = {mag=, reserve=}.
-- Keyed by weapon (not by slot) so ammo persists correctly if a slot's weapon
-- ever changes. Not saved to DataStore on purpose — full ammo on next session
-- is the expected behavior, same as most shooters.
local ammoState = {}
local isReloading = {}
local reloadToken = {} -- bumped on every equip/respawn/new reload so stale task.delay callbacks no-op

local MAX_ORIGIN_DISTANCE = 10 -- studs; how far camOrigin may be from the player's head before we distrust it
local FIRE_RATE_TOLERANCE = 0.85 -- allow shots slightly faster than FireRate to absorb network jitter

local function isValidForSlot(weaponName, slotName)
    local cfg = weaponName and WeaponConfig[weaponName]
    return cfg ~= nil and cfg.Slot == slotName
end

-- Never trust saved data blindly: a weapon could've been renamed/removed since
-- it was saved, so fall back to the default for any slot that doesn't check out.
local function sanitizeLoadout(rawLoadout)
    local loadout = {}
    for _, slotName in SLOTS do
        local weaponName = nil
        if typeof(rawLoadout) == "table" then
            weaponName = rawLoadout[slotName]
        end
        if isValidForSlot(weaponName, slotName) then
            loadout[slotName] = weaponName
        else
            loadout[slotName] = DEFAULT_LOADOUT[slotName]
        end
    end
    return loadout
end

local function resetAmmoForWeapon(player, weaponName)
    local cfg = WeaponConfig[weaponName]
    if not cfg or cfg.Type ~= "Ranged" then return end
    ammoState[player] = ammoState[player] or {}
    ammoState[player][weaponName] = {mag = cfg.MagazineSize, reserve = cfg.ReserveAmmo}
end

local function getAmmo(player, weaponName)
    local cfg = WeaponConfig[weaponName]
    if not cfg or cfg.Type ~= "Ranged" then return nil end
    ammoState[player] = ammoState[player] or {}
    if not ammoState[player][weaponName] then
        resetAmmoForWeapon(player, weaponName)
    end
    return ammoState[player][weaponName]
end

-- Attributes are how the client (HUD + fire-gating) reads ammo: cheap, and it
-- automatically only ever reflects what the server decided, same pattern as
-- EquippedWeapon.
local function updateAmmoAttributes(player)
    local weaponName = equippedWeapon[player]
    local ammo = weaponName and getAmmo(player, weaponName)
    if ammo then
        player:SetAttribute("AmmoInMag", ammo.mag)
        player:SetAttribute("AmmoReserve", ammo.reserve)
    else
        player:SetAttribute("AmmoInMag", nil)
        player:SetAttribute("AmmoReserve", nil)
    end
end

local function cancelReload(player)
    reloadToken[player] = (reloadToken[player] or 0) + 1
    isReloading[player] = false
    player:SetAttribute("Reloading", false)
end

local function startReload(player)
    if isReloading[player] then return end
    local weaponName = equippedWeapon[player]
    local cfg = weaponName and WeaponConfig[weaponName]
    if not cfg or cfg.Type ~= "Ranged" then return end

    local ammo = getAmmo(player, weaponName)
    if not ammo or ammo.mag >= cfg.MagazineSize or ammo.reserve <= 0 then return end

    isReloading[player] = true
    reloadToken[player] = (reloadToken[player] or 0) + 1
    local myToken = reloadToken[player]
    player:SetAttribute("Reloading", true)

    task.delay(cfg.ReloadTime, function()
        -- Bail out if the player left, switched weapons, or started another
        -- reload while this one was in flight (token no longer matches).
        if reloadToken[player] ~= myToken then return end
        if not ammoState[player] or equippedWeapon[player] ~= weaponName then return end

        local needed = cfg.MagazineSize - ammo.mag
        local take = math.min(needed, ammo.reserve)
        ammo.mag += take
        ammo.reserve -= take

        isReloading[player] = false
        player:SetAttribute("Reloading", false)
        updateAmmoAttributes(player)
    end)
end

local function equipSlot(player, slotName)
    local loadout = loadouts[player]
    if not loadout then return end
    local weaponName = loadout[slotName]
    if not weaponName then return end -- slot locked/empty for this player
    cancelReload(player)
    activeSlot[player] = slotName
    equippedWeapon[player] = weaponName
    player:SetAttribute("EquippedWeapon", weaponName)
    updateAmmoAttributes(player)
    if player.Character then
        WeaponAttachment.equip(player.Character, weaponName)
    end
end

local function loadPlayerData(player)
    local key = "Player_" .. player.UserId
    local ok, saved = pcall(function()
        return loadoutStore:GetAsync(key)
    end)

    local rawLoadout, savedActiveSlot
    if ok and typeof(saved) == "table" then
        rawLoadout = saved.loadout
        savedActiveSlot = saved.activeSlot
    end

    loadouts[player] = sanitizeLoadout(rawLoadout)
    if typeof(savedActiveSlot) ~= "string" or not table.find(SLOTS, savedActiveSlot) then
        savedActiveSlot = DEFAULT_ACTIVE_SLOT
    end
    equipSlot(player, savedActiveSlot)

    -- Re-attach the visible weapon model on every respawn (a fresh character
    -- has no weapon welded to it yet), and refill ammo for every ranged weapon
    -- in the loadout — a fresh life starts with full mags, same as most shooters.
    player.CharacterAdded:Connect(function(character)
        cancelReload(player)
        for _, weaponName in loadouts[player] do
            resetAmmoForWeapon(player, weaponName)
        end
        updateAmmoAttributes(player)
        WeaponAttachment.equip(character, equippedWeapon[player])
    end)
    for _, weaponName in loadouts[player] do
        resetAmmoForWeapon(player, weaponName)
    end
    updateAmmoAttributes(player)
    if player.Character then
        WeaponAttachment.equip(player.Character, equippedWeapon[player])
    end
end

local function savePlayerData(player)
    local loadout = loadouts[player]
    if not loadout then return end
    local key = "Player_" .. player.UserId
    local data = {
        loadout = loadout,
        activeSlot = activeSlot[player] or DEFAULT_ACTIVE_SLOT,
    }
    pcall(function()
        loadoutStore:SetAsync(key, data)
    end)
end

-- Hats/hair sit in front of the real Head part and are raycastable by default,
-- so a headshot ray hits the accessory's Handle first and never reports "Head".
-- CharacterAppearanceLoaded (not CharacterAdded) guarantees accessories have
-- actually finished loading before we touch them.
local function disableAccessoryRaycasts(character)
    for _, accessory in character:GetChildren() do
        if accessory:IsA("Accessory") then
            local handle = accessory:FindFirstChild("Handle")
            if handle then
                handle.CanQuery = false
            end
        end
    end
end

Players.PlayerAdded:Connect(loadPlayerData)
Players.PlayerAdded:Connect(function(player)
    player.CharacterAppearanceLoaded:Connect(disableAccessoryRaycasts)
end)

Players.PlayerRemoving:Connect(function(player)
    savePlayerData(player)
    loadouts[player] = nil
    activeSlot[player] = nil
    equippedWeapon[player] = nil
    lastFireTime[player] = nil
    ammoState[player] = nil
    isReloading[player] = nil
    reloadToken[player] = nil
end)

game:BindToClose(function()
    for _, player in Players:GetPlayers() do
        savePlayerData(player)
    end
end)

-- Client requests a slot switch (which weapon to use is decided here, from the
-- player's own loadout — the client never gets to name an arbitrary weapon).
EquipWeaponEvent.OnServerEvent:Connect(function(player, slotName)
    if typeof(slotName) ~= "string" or not table.find(SLOTS, slotName) then
        return
    end
    equipSlot(player, slotName)
end)

ReloadWeaponEvent.OnServerEvent:Connect(function(player)
    startReload(player)
end)

FireWeaponEvent.OnServerEvent:Connect(function(player, camOrigin, camDir)
    local weaponName = equippedWeapon[player]
    local cfg = weaponName and WeaponConfig[weaponName]
    if not cfg or cfg.Type == "Melee" then
        return
    end

    if isReloading[player] then
        return
    end

    if typeof(camOrigin) ~= "Vector3" or typeof(camDir) ~= "Vector3" then
        return
    end

    local character = player.Character
    if not character then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or humanoid.Health <= 0 then
        return
    end

    -- Rate limit: ignore shots that arrive faster than the weapon's fire rate allows.
    local now = os.clock()
    local last = lastFireTime[player]
    if last and (now - last) < (cfg.FireRate * FIRE_RATE_TOLERANCE) then
        return
    end

    -- Sanity-check the reported camera origin against the player's actual position,
    -- since the client can otherwise claim to be shooting from anywhere.
    local head = character:FindFirstChild("Head")
    local originReference = (head and head.Position) or root.Position
    if (camOrigin - originReference).Magnitude > MAX_ORIGIN_DISTANCE then
        return
    end

    -- No ammo, no shot. Consumes a bullet regardless of hit/miss, same as the
    -- rate limit above only applies to shots that get this far (a rejected
    -- shot shouldn't cost ammo).
    local ammo = getAmmo(player, weaponName)
    if not ammo or ammo.mag <= 0 then
        return
    end

    lastFireTime[player] = now
    ammo.mag -= 1
    updateAmmoAttributes(player)

    -- Never trust the client's reported hit Instance/Position: redo the raycast on the server.
    local range = cfg.BulletRange or 500
    local direction = camDir
    if direction.Magnitude > 0 then
        direction = direction.Unit * range
    else
        return
    end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {character}

    local result = Workspace:Raycast(camOrigin, direction, rayParams)
    local hitPos = result and result.Position or (camOrigin + direction)

    -- Broadcast so every other client can draw a tracer/muzzle flash for this shot —
    -- the shooter already drew their own locally, for zero-latency feedback.
    WeaponEffectsEvent:FireAllClients(player, camOrigin, hitPos)

    if not result then
        return
    end

    -- Only zombies (tagged by their AI script) take damage from gunfire, so
    -- hitting another player never applies damage (no friendly fire).
    local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
    local hitHumanoid = hitModel and hitModel:FindFirstChildOfClass("Humanoid")
    if hitHumanoid and hitHumanoid.Health > 0 and CollectionService:HasTag(hitModel, "Zombie") then
        local isHeadshot = result.Instance.Name == "Head"
        local damage = cfg.Damage or 0
        if isHeadshot then
            damage *= cfg.HeadshotMultiplier or 1
        end
        hitHumanoid:TakeDamage(damage)
        HitmarkerEvent:FireClient(player, isHeadshot)
        DamageNumberEvent:FireClient(player, hitModel, damage, isHeadshot)
    end
end)
