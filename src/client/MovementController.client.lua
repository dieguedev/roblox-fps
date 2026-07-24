local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local SlideEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SlideEvent")

local WALK_SPEED = 16
local SPRINT_SPEED = 26
local CROUCH_SPEED = 8
local CROUCH_HIP_HEIGHT_OFFSET = 1.6 -- studs subtracted from the character's own HipHeight while crouched
local SLIDE_COOLDOWN = 1 -- client-side mirror of the server's cooldown, just to keep the button/key from spamming the remote

-- Stamina: draining/regen numbers are the usual shooter defaults (drain over a
-- few seconds, regen slower than drain so you can't tap-spam it back), plus a
-- fixed "gassed out" cooldown once it hits zero so sprint doesn't just
-- toggle back on the instant a sliver of stamina regenerates.
local MAX_STAMINA = 100
local STAMINA_DRAIN_RATE = MAX_STAMINA / 3 -- fully drains after 3s of continuous sprint
local STAMINA_REGEN_RATE = MAX_STAMINA / 8 -- fully refills over 8s once regenerating
local STAMINA_REGEN_DELAY = 1 -- seconds after releasing sprint before regen starts
local EXHAUSTED_COOLDOWN = 5 -- seconds you can't sprint again after fully draining

local humanoid = nil
local normalHipHeight = 2

local isSprinting = false
local isCrouching = false
local isCHeld = false
local canSlide = true

local stamina = MAX_STAMINA
local isExhausted = false
local exhaustedUntil = 0
local lastSprintStopTime = 0

local function canSprint()
	return not isExhausted and stamina > 0
end

local function currentSpeed()
	if isCrouching then return CROUCH_SPEED end
	if isSprinting and canSprint() then return SPRINT_SPEED end
	return WALK_SPEED
end

local function currentHipHeight()
	if isCrouching then
		return math.max(normalHipHeight - CROUCH_HIP_HEIGHT_OFFSET, 0)
	end
	return normalHipHeight
end

local function refreshMovementState()
	if not humanoid then return end
	humanoid.HipHeight = currentHipHeight()
	humanoid.WalkSpeed = currentSpeed()
end

-- The actual slide (velocity burst + animation) is entirely server-authoritative
-- now (see MovementService.server.lua) — the client only ever requests it and
-- keeps a local cooldown so mashing the key/button doesn't spam the remote.
local function requestSlide()
	if not humanoid or not canSlide then return end
	if not (isSprinting and humanoid.MoveDirection.Magnitude > 0.05) then return end

	canSlide = false
	task.delay(SLIDE_COOLDOWN, function()
		canSlide = true
	end)

	SlideEvent:FireServer()
end

-- The server drives WalkSpeed directly for the duration of the slide, then
-- signals back here (no args) so we can reassert whatever speed our own
-- sprint/crouch state actually wants, instead of guessing at a restore value.
SlideEvent.OnClientEvent:Connect(function()
	refreshMovementState()
end)

local function onCPressed()
	isCHeld = true
	if isSprinting then
		requestSlide()
	else
		isCrouching = true
		refreshMovementState()
	end
end

local function onCReleased()
	isCHeld = false
	isCrouching = false
	refreshMovementState()
end

local function setSprinting(active)
	isSprinting = active
	refreshMovementState()
end

-- Drains while actually sprinting (moving, not crouched), regenerates after a
-- short delay once you stop, and locks sprinting out for EXHAUSTED_COOLDOWN
-- once it hits zero.
RunService.Heartbeat:Connect(function(dt)
	local activelySprinting = isSprinting and not isCrouching and canSprint()
		and humanoid and humanoid.MoveDirection.Magnitude > 0.05

	if activelySprinting then
		stamina = math.max(stamina - STAMINA_DRAIN_RATE * dt, 0)
		lastSprintStopTime = os.clock()
		if stamina <= 0 and not isExhausted then
			isExhausted = true
			exhaustedUntil = os.clock() + EXHAUSTED_COOLDOWN
			refreshMovementState()
		end
	else
		if isExhausted and os.clock() >= exhaustedUntil then
			isExhausted = false
		end
		if os.clock() - lastSprintStopTime >= STAMINA_REGEN_DELAY then
			local wasDepleted = stamina <= 0
			stamina = math.min(stamina + STAMINA_REGEN_RATE * dt, MAX_STAMINA)
			if wasDepleted and stamina > 0 then
				refreshMovementState() -- speed can pick back up mid-regen if the cooldown already ended
			end
		end
	end

	LocalPlayer:SetAttribute("Stamina", stamina / MAX_STAMINA)
end)

local function onCharacterAdded(character)
	humanoid = character:WaitForChild("Humanoid")
	normalHipHeight = humanoid.HipHeight

	isSprinting = false
	isCrouching = false
	isCHeld = false
	canSlide = true

	stamina = MAX_STAMINA
	isExhausted = false
	exhaustedUntil = 0
	lastSprintStopTime = 0

	refreshMovementState()
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
if LocalPlayer.Character then
	onCharacterAdded(LocalPlayer.Character)
end

LocalPlayer.CharacterRemoving:Connect(function()
	humanoid = nil
end)

-- ============================================================
-- Input: Shift = sprint (held), C = crouch (held) / slide (if C is pressed while
-- sprinting). Mobile has its own touch button below (same gating as C+sprint).
-- Jump is left entirely to the default Humanoid/StarterPlayer jump behavior.
-- ============================================================

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.KeyCode == Enum.KeyCode.LeftShift then
		setSprinting(true)
	elseif input.KeyCode == Enum.KeyCode.C then
		onCPressed()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		setSprinting(false)
	elseif input.KeyCode == Enum.KeyCode.C then
		onCReleased()
	end
end)

-- ============================================================
-- Mobile: a touch button that requests the same slide, ported as-is from the
-- original SlideClient toolbox script (same GUI properties/asset).
-- ============================================================

if UserInputService.TouchEnabled then
	local SlideHud = Instance.new("ScreenGui")
	local Slide = Instance.new("ImageButton")
	local UIAspectRatioConstraint = Instance.new("UIAspectRatioConstraint")
	local UICorner = Instance.new("UICorner")

	SlideHud.Name = "SlideHud"
	SlideHud.Parent = LocalPlayer:WaitForChild("PlayerGui")
	SlideHud.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	Slide.Name = "Slide"
	Slide.Parent = SlideHud
	Slide.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Slide.BackgroundTransparency = 1.000
	Slide.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Slide.BorderSizePixel = 0
	Slide.Position = UDim2.new(0.739247322, 0, 0.469973892, 0)
	Slide.Size = UDim2.new(0.121681474, 0, 0.235294446, 0)
	Slide.Image = "rbxassetid://121380519093487"

	UIAspectRatioConstraint.Parent = Slide

	UICorner.CornerRadius = UDim.new(110, 32131)
	UICorner.Parent = Slide

	Slide.MouseButton1Click:Connect(requestSlide)
end
