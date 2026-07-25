local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SimplePath = require(script.SimplePath)
local ZombieConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ZombieConfig"))

local zombie = script.Parent
local humanoid = zombie:WaitForChild("Humanoid")
local rootPart = zombie:WaitForChild("HumanoidRootPart")

-- Tags WeaponService's raycast damage check so gunfire only hurts zombies,
-- never other players (no friendly fire).
CollectionService:AddTag(zombie, "Zombie")

-- Type is set via a Studio attribute on the model so placing a Corredor is
-- just duplicating the zombie and changing one attribute, no script edits.
local zombieType = zombie:GetAttribute("ZombieType") or "Normal"
local stats = ZombieConfig[zombieType]
if not stats then
    warn(("ZombieAI: unknown ZombieType %q on %s, falling back to Normal"):format(zombieType, zombie:GetFullName()))
    stats = ZombieConfig.Normal
end

humanoid.MaxHealth = stats.MaxHealth
humanoid.Health = stats.MaxHealth
humanoid.WalkSpeed = stats.WalkSpeed

-- Checked frequently (not recomputed frequently -- see the idle/moved gate
-- below); checking only once a second meant the zombie chased a snapshot of
-- the player's position that was up to a full second stale, so it never
-- actually closed the distance on a moving target.
local REPATH_INTERVAL = 0.1 -- seconds between recompute *checks*
local REPATH_DISTANCE = 5 -- studs the target must move since the last computed path before it's worth recomputing
local CORPSE_CLEANUP_DELAY = 5 -- seconds the corpse stays before being removed, so kills don't pile up on the map

local ATTACK_RANGE = stats.AttackRange
-- Wider than ATTACK_RANGE on purpose: the swing already started at ATTACK_RANGE,
-- so a player backing away mid-animation shouldn't fully void a hit that was
-- already committed. Only used for the impact check below, not for deciding
-- whether to start swinging in the first place.
local HIT_CONNECT_RANGE = ATTACK_RANGE + 2.5
local ATTACK_DAMAGE = stats.AttackDamage
local ATTACK_COOLDOWN = stats.AttackCooldown -- seconds after a landed hit before the zombie can swing again

-- AgentCanJump/AgentCanClimb let the zombie get over the map's obstacles instead
-- of getting stuck at the base of them, which would let a player standing on
-- something elevated kill zombies with zero risk.
local path = SimplePath.new(zombie, {
    AgentCanJump = true,
    AgentCanClimb = true,
})
path.Visualize = false

local losRayParams = RaycastParams.new()
losRayParams.FilterType = Enum.RaycastFilterType.Exclude
losRayParams.FilterDescendantsInstances = {zombie}

-- Used by the "Hit" marker callback below to know who's actually in front of
-- the zombie at the exact instant the swing connects, not when it started.
local currentTargetRoot = nil
local isSwinging = false
local lastHitTime = -math.huge

local function hasLineOfSight(targetRoot)
    local origin = rootPart.Position
    local toTarget = targetRoot.Position - origin
    local result = Workspace:Raycast(origin, toTarget, losRayParams)
    -- No hit at all, or the first thing hit belongs to the target's own
    -- character, both count as a clean line of sight.
    return not result or result.Instance:IsDescendantOf(targetRoot.Parent)
end

-- The Attack animation is a hand-placed Studio asset (ReplicatedStorage.Animations.Zombie.Attack),
-- not something Rojo syncs in. WaitForChild-ing on it would block this whole
-- script -- including the chase loop and the "Zombie" CollectionService tag
-- gunfire relies on -- until it exists, so it's loaded defensively instead:
-- if it's missing, the zombie still chases/dies normally, just without melee.
local attackTrack = nil
local animationsFolder = ReplicatedStorage:FindFirstChild("Animations")
local zombieAnimFolder = animationsFolder and animationsFolder:FindFirstChild("Zombie")
local attackAnimation = zombieAnimFolder and zombieAnimFolder:FindFirstChild("Attack")
if attackAnimation then
    -- Custom NPC rigs don't always come with an Animator pre-inserted the way
    -- player characters do, so it's created here if missing.
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    attackTrack = animator:LoadAnimation(attackAnimation)
    attackTrack.Priority = Enum.AnimationPriority.Action

    attackTrack:GetMarkerReachedSignal("Hit"):Connect(function()
        local targetRoot = currentTargetRoot
        local targetCharacter = targetRoot and targetRoot.Parent
        local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
        if not targetHumanoid or targetHumanoid.Health <= 0 then
            return
        end
        -- Re-check range at the moment of impact, not when the swing started --
        -- but with a bit of slack (HIT_CONNECT_RANGE), so backing away mid-swing
        -- doesn't automatically void a hit that already started.
        local distance = (targetRoot.Position - rootPart.Position).Magnitude
        if distance <= HIT_CONNECT_RANGE then
            targetHumanoid:TakeDamage(ATTACK_DAMAGE)
            lastHitTime = os.clock()
        end
    end)

    attackTrack.Stopped:Connect(function()
        isSwinging = false
    end)
else
    warn("ZombieAI: ReplicatedStorage.Animations.Zombie.Attack not found -- melee attack disabled until it's set up in Studio (chase/gunfire still work).")
end

-- Same treatment WeaponService gives player accessories: hats/hair sit in front
-- of the real Head part and would otherwise absorb the weapon's headshot raycast.
local function disableAccessoryRaycasts()
    for _, accessory in zombie:GetChildren() do
        if accessory:IsA("Accessory") then
            local handle = accessory:FindFirstChild("Handle")
            if handle then
                handle.CanQuery = false
            end
        end
    end
end
disableAccessoryRaycasts()
zombie.ChildAdded:Connect(function(child)
    if child:IsA("Accessory") then
        disableAccessoryRaycasts()
    end
end)

local function getNearestStandingPlayer()
    local nearestRoot, nearestDistance = nil, math.huge
    for _, player in Players:GetPlayers() do
        local character = player.Character
        local targetHumanoid = character and character:FindFirstChildOfClass("Humanoid")
        local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
        if targetHumanoid and targetHumanoid.Health > 0 and targetRoot then
            local distance = (targetRoot.Position - rootPart.Position).Magnitude
            if distance < nearestDistance then
                nearestRoot, nearestDistance = targetRoot, distance
            end
        end
    end
    return nearestRoot
end

-- Corpses shouldn't pile up once rounds are spawning many zombies (Paso 4).
humanoid.Died:Once(function()
    Debris:AddItem(zombie, CORPSE_CLEANUP_DELAY)
end)

local lastTargetPosition = nil

while humanoid.Health > 0 do
    local targetRoot = getNearestStandingPlayer()
    currentTargetRoot = targetRoot

    local inMeleeRange = attackTrack and targetRoot and (targetRoot.Position - rootPart.Position).Magnitude <= ATTACK_RANGE
    -- The line-of-sight check only runs once range is already close, since
    -- it's the more expensive of the two conditions.
    local canAttack = inMeleeRange and hasLineOfSight(targetRoot)

    if isSwinging and not canAttack then
        -- Target stepped out of melee range (or broke line of sight) mid-swing;
        -- cancel the animation instead of letting it play out, so the zombie
        -- can resume chasing at full speed right away instead of eating the
        -- rest of the attack in place.
        attackTrack:Stop()
    end

    if canAttack then
        -- Stop chasing and turn to face the target; a wall/pillar in the way
        -- falls through to the chase branch below instead, so the zombie
        -- paths around it rather than attacking through it.
        if path.Status ~= SimplePath.StatusType.Idle then
            path:Stop()
            lastTargetPosition = nil
        end
        local facePosition = Vector3.new(targetRoot.Position.X, rootPart.Position.Y, targetRoot.Position.Z)
        if (facePosition - rootPart.Position).Magnitude > 0.05 then
            rootPart.CFrame = CFrame.lookAt(rootPart.Position, facePosition)
        end

        if not isSwinging and (os.clock() - lastHitTime) >= ATTACK_COOLDOWN then
            isSwinging = true
            attackTrack:Play()
        end
    elseif targetRoot then
        local targetPosition = targetRoot.Position
        -- Only recompute when idle or the target has moved far enough to
        -- matter; recomputing every tick regardless of progress was what made
        -- the chase look choppy (it kept restarting MoveTo mid-stride).
        local targetMoved = not lastTargetPosition or (targetPosition - lastTargetPosition).Magnitude > REPATH_DISTANCE
        if path.Status == SimplePath.StatusType.Idle or targetMoved then
            lastTargetPosition = targetPosition
            path:Run(targetPosition)
        end
    elseif path.Status ~= SimplePath.StatusType.Idle then
        path:Stop()
        lastTargetPosition = nil
    end
    task.wait(REPATH_INTERVAL)
end
