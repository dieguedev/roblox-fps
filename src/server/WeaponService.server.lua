local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local DataStoreService = game:GetService("DataStoreService")

local WeaponConfig = require(ReplicatedStorage:WaitForChild("WeaponConfig"))
local WeaponAttachment = require(script.Parent:WaitForChild("WeaponAttachment"))
local EquipWeaponEvent = ReplicatedStorage:WaitForChild("EquipWeaponEvent")
local FireWeaponEvent = ReplicatedStorage:WaitForChild("FireWeaponEvent")
local WeaponEffectsEvent = ReplicatedStorage:WaitForChild("WeaponEffectsEvent")

local loadoutStore = DataStoreService:GetDataStore("PlayerLoadout_v1")

local SLOTS = {"Primary", "Secondary", "Knife"}
-- Every player starts owning these three; a future shop grants better weapons
-- per slot (e.g. Primary = "SCAR-L") and that assignment gets persisted the same way.
local DEFAULT_LOADOUT = {Primary = "AK47", Secondary = "Pistol", Knife = "Knife"}
local DEFAULT_ACTIVE_SLOT = "Secondary"

-- Server-owned source of truth: which weapon each player has assigned to each
-- slot, which slot they're currently holding, and when they last fired a valid
-- shot (for rate limiting).
local loadouts = {}
local activeSlot = {}
local equippedWeapon = {}
local lastFireTime = {}

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

local function equipSlot(player, slotName)
    local loadout = loadouts[player]
    if not loadout then return end
    local weaponName = loadout[slotName]
    if not weaponName then return end -- slot locked/empty for this player
    activeSlot[player] = slotName
    equippedWeapon[player] = weaponName
    player:SetAttribute("EquippedWeapon", weaponName)
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
    -- has no weapon welded to it yet).
    player.CharacterAdded:Connect(function(character)
        WeaponAttachment.equip(character, equippedWeapon[player])
    end)
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

Players.PlayerAdded:Connect(loadPlayerData)

Players.PlayerRemoving:Connect(function(player)
    savePlayerData(player)
    loadouts[player] = nil
    activeSlot[player] = nil
    equippedWeapon[player] = nil
    lastFireTime[player] = nil
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

FireWeaponEvent.OnServerEvent:Connect(function(player, camOrigin, camDir)
    local weaponName = equippedWeapon[player]
    local cfg = weaponName and WeaponConfig[weaponName]
    if not cfg or cfg.Type == "Melee" then
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

    lastFireTime[player] = now

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

    local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
    local hitHumanoid = hitModel and hitModel:FindFirstChildOfClass("Humanoid")
    if hitHumanoid and hitHumanoid ~= humanoid and hitHumanoid.Health > 0 then
        hitHumanoid:TakeDamage(cfg.Damage or 0)
    end
end)
