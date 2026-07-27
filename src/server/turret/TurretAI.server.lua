local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local torreta = script.Parent
-- The turret's aim origin/axis: place a Part named "Muzzle" inside the barrel
-- tip in Studio, facing outward (its LookVector is the cone's forward axis).
-- Must be Anchored (or welded once the turret animates) -- otherwise it free-falls
-- under gravity during Play and every distance/cone check goes garbage.
local muzzle = torreta:WaitForChild("Muzzle")

-- Placeholder balance numbers -- not tuned against real playtesting yet, just
-- picked to be "a working turret". Revisit once the battery/build system (see
-- .documentation/TODO.md) is in.
local RANGE = 60 -- studs
local DAMAGE = 30
local FIRE_INTERVAL = 0.1 -- seconds between shots
local TICK_INTERVAL = 0.05 -- seconds between target re-scans

-- "Cono de 180 grados desde la punta": total aperture of 180°, i.e. anything
-- in front of the muzzle's facing plane (half-angle 90° either side of LookVector).
local CONE_TOTAL_ANGLE = 180
local CONE_HALF_ANGLE_COS = math.cos(math.rad(CONE_TOTAL_ANGLE / 2))

-- TEMPORAL: dibuja el cono de detección (radios + borde) en tiempo real para
-- verificar visualmente hacia dónde y cuán ancho apunta. Poner en false o
-- borrar este bloque (y el bloque "visualización" del bucle final) una vez
-- confirmado.
local DEBUG_VISUALIZE = true
local VISUALIZE_SPOKES = 20 -- nº de líneas que forman el borde del cono

local function makeDebugPart(color)
    local part = Instance.new("Part")
    part.Name = "TurretDebugVisual"
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CastShadow = false
    part.Material = Enum.Material.Neon
    part.Color = color
    part.Transparency = 0.4
    part.Parent = torreta
    return part
end

-- Positions `part` as a thin rod between two world points (classic "beam
-- between two points" CFrame trick).
local function pointRodAt(part, from, to, thickness)
    local distance = (to - from).Magnitude
    if distance < 1e-3 then
        part.Size = Vector3.new(thickness, thickness, thickness)
        part.CFrame = CFrame.new(from)
        return
    end
    part.CFrame = CFrame.new(from, to) * CFrame.new(0, 0, -distance / 2)
    part.Size = Vector3.new(thickness, thickness, distance)
end

local debugSpokes, debugRim, debugForward
if DEBUG_VISUALIZE then
    debugSpokes = {}
    debugRim = {}
    for i = 1, VISUALIZE_SPOKES do
        table.insert(debugSpokes, makeDebugPart(Color3.fromRGB(255, 60, 60)))
        table.insert(debugRim, makeDebugPart(Color3.fromRGB(255, 200, 60)))
    end
    -- El borde (rojo/amarillo) es solo el LÍMITE del cono, no las únicas
    -- direcciones válidas -- esta línea verde marca el eje central
    -- (Muzzle.LookVector), que está tan dentro del cono como cualquier punto
    -- entre el eje y el borde.
    debugForward = makeDebugPart(Color3.fromRGB(60, 255, 90))
end

-- Redraws the cone edge: for a half-angle of CONE_TOTAL_ANGLE/2 around the
-- muzzle's LookVector, samples VISUALIZE_SPOKES points on the cone's boundary
-- at RANGE studs out, draws a rod from the muzzle to each (the "spokes") and
-- connects consecutive points (the "rim"). At 180° (half-angle 90°) this
-- traces the flat disc that is the actual boundary of the front hemisphere.
local function updateDebugVisual()
    local origin = muzzle.Position
    local look = muzzle.CFrame.LookVector
    local halfAngle = math.rad(CONE_TOTAL_ANGLE / 2)

    -- Any vector not parallel to `look` works to build a perpendicular basis.
    local upHint = math.abs(look:Dot(Vector3.yAxis)) < 0.99 and Vector3.yAxis or Vector3.xAxis
    local right = look:Cross(upHint).Unit
    local up = right:Cross(look).Unit

    local points = {}
    for i = 1, VISUALIZE_SPOKES do
        local azimuth = (i - 1) / VISUALIZE_SPOKES * math.pi * 2
        local direction = math.cos(halfAngle) * look
            + math.sin(halfAngle) * (math.cos(azimuth) * right + math.sin(azimuth) * up)
        points[i] = origin + direction.Unit * RANGE
        pointRodAt(debugSpokes[i], origin, points[i], 0.05)
    end
    for i = 1, VISUALIZE_SPOKES do
        local nextI = (i % VISUALIZE_SPOKES) + 1
        pointRodAt(debugRim[i], points[i], points[nextI], 0.05)
    end

    pointRodAt(debugForward, origin, origin + look * RANGE, 0.08)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- Rebuilt each shot: BulletPass-tagged parts (see WeaponService) can be tagged
-- or untagged at any time, and the turret should always ignore itself.
local function buildRayFilter()
    local filter = {torreta}
    for _, part in CollectionService:GetTagged("BulletPass") do
        table.insert(filter, part)
    end
    return filter
end

-- Closest zombie inside the 180° cone and RANGE, regardless of obstacles --
-- line of sight is checked separately per-candidate in the fire loop below.
local function findCandidatesInCone()
    local muzzlePosition = muzzle.Position
    local muzzleLook = muzzle.CFrame.LookVector

    local candidates = {}
    for _, zombie in CollectionService:GetTagged("Zombie") do
        local humanoid = zombie:FindFirstChildOfClass("Humanoid")
        local root = zombie:FindFirstChild("HumanoidRootPart")
        if humanoid and humanoid.Health > 0 and root then
            local offset = root.Position - muzzlePosition
            local distance = offset.Magnitude
            if distance > 0 and distance <= RANGE then
                local direction = offset / distance
                if direction:Dot(muzzleLook) >= CONE_HALF_ANGLE_COS then
                    table.insert(candidates, {zombie = zombie, humanoid = humanoid, root = root, distance = distance})
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        return a.distance < b.distance
    end)
    return candidates
end

-- Casts from the muzzle to the candidate's root; a hit that lands on the
-- candidate itself is a clear shot, anything else (wall, other zombie, etc.)
-- blocks it -- same "obstacles block bullets, BulletPass-tagged parts don't"
-- rule WeaponService uses for player gunfire.
local function tryFireAt(candidate)
    local muzzlePosition = muzzle.Position
    local toTarget = candidate.root.Position - muzzlePosition
    local direction = toTarget.Unit * (toTarget.Magnitude + 1)

    rayParams.FilterDescendantsInstances = buildRayFilter()
    local result = Workspace:Raycast(muzzlePosition, direction, rayParams)
    if not result or not result.Instance:IsDescendantOf(candidate.zombie) then
        return false
    end

    candidate.humanoid:TakeDamage(DAMAGE)
    -- TODO (no implementado a propósito, ver .documentation/TODO.md):
    --   - Girar la boquilla/torreta hacia el objetivo antes/mientras dispara.
    --   - Efecto visual de disparo (muzzle flash, tracer).
    --   - Animación de disparo de la torreta.
    --   - Sonido de disparo.
    return true
end

if DEBUG_VISUALIZE then
    RunService.Heartbeat:Connect(updateDebugVisual)
end

local lastFireTime = -math.huge

while torreta.Parent do
    if os.clock() - lastFireTime >= FIRE_INTERVAL then
        local candidates = findCandidatesInCone()
        for _, candidate in candidates do
            if tryFireAt(candidate) then
                lastFireTime = os.clock()
                break
            end
        end
    end
    task.wait(TICK_INTERVAL)
end
