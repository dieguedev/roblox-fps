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
-- few seconds, regen slower than drain so you can't tap-spam it back). No
-- fixed cooldown once it hits zero — sprint is just unavailable until you
-- release Shift and press it again (even if stamina has regenerated in the
-- meantime while still holding it down).
local MAX_STAMINA = 100
local STAMINA_DRAIN_RATE = MAX_STAMINA / 3 -- fully drains after 3s of continuous sprint
local STAMINA_REGEN_RATE = MAX_STAMINA / 8 -- fully refills over 8s once regenerating
local STAMINA_REGEN_DELAY = 1 -- seconds after releasing sprint before regen starts
local SLIDE_STAMINA_COST = 20 -- flat stamina charge per slide, on top of any sprint drain

local humanoid = nil
local normalHipHeight = 2

local isSprinting = false
local isCrouching = false
local isCHeld = false
local canSlide = true

local stamina = MAX_STAMINA
local sprintLocked = false -- set once stamina hits 0; cleared only when Shift is released
local lastSprintStopTime = 0

local function canSprint()
	return not sprintLocked and stamina > 0
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

-- Shared by the sprint drain (Heartbeat) and the slide's flat charge. Hitting
-- zero locks sprinting out until Shift is released (see setSprinting) rather
-- than on a fixed timer.
local function spendStamina(amount)
	stamina = math.max(stamina - amount, 0)
	lastSprintStopTime = os.clock()
	if stamina <= 0 and not sprintLocked then
		sprintLocked = true
		refreshMovementState()
	end
end

-- The actual slide (velocity burst + animation) is entirely server-authoritative
-- now (see MovementService.server.lua) — the client only ever requests it and
-- keeps a local cooldown so mashing the key/button doesn't spam the remote.
-- Requires stamina up front (same gate as sprint) so you can't keep sliding
-- once you're gassed out.
local function requestSlide()
	if not humanoid or not canSlide then return end
	if not (isSprinting and canSprint() and humanoid.MoveDirection.Magnitude > 0.05) then return end

	canSlide = false
	task.delay(SLIDE_COOLDOWN, function()
		canSlide = true
	end)

	spendStamina(SLIDE_STAMINA_COST)
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
	if not active then
		-- Releasing Shift is the only way to clear the lockout, even if
		-- stamina has already regenerated while it was still held down.
		sprintLocked = false
	end
	refreshMovementState()
end

-- Drains while actually sprinting (moving, not crouched), regenerates after a
-- short delay once you stop. No fixed lockout timer — once stamina hits 0,
-- sprint stays unavailable until Shift is released and pressed again.
RunService.Heartbeat:Connect(function(dt)
	local activelySprinting = isSprinting and not isCrouching and canSprint()
		and humanoid and humanoid.MoveDirection.Magnitude > 0.05

	if activelySprinting then
		spendStamina(STAMINA_DRAIN_RATE * dt)
	else
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
	sprintLocked = false
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
-- sprinting). Mobile has its own touch buttons below (SprintButton toggles
-- the same isSprinting state Shift does; SlideButton requests the same
-- slide C does). Jump is left entirely to the default Humanoid/StarterPlayer
-- jump behavior.
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
-- Mobile: SprintButton (toggle) and SlideButton -- built in Studio inside
-- StarterGui.MobileControlsGui, not generated here (same convention as
-- JumpButton/MoveJoystick in MobileControls.client.lua). Wired here instead
-- of there because isSprinting/setSprinting/requestSlide are private to this
-- script.
--
-- SprintButton is a toggle (tap to start, tap again to stop) rather than
-- hold-to-sprint like Shift -- holding a screen button down is uncomfortable,
-- and toggling frees that thumb to tap SlideButton without needing a second
-- hand.
-- ============================================================

if UserInputService.TouchEnabled then
	local mobileGui = LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("MobileControlsGui")
	local actionButtons = mobileGui:WaitForChild("ActionButtonsCluster")
	local sprintButton = actionButtons:WaitForChild("SprintButton")
	local slideButton = actionButtons:WaitForChild("SlideButton")

	local SPRINT_BUTTON_OFF_TRANSPARENCY = 0.5
	local SPRINT_BUTTON_ON_TRANSPARENCY = 0.1 -- less transparent while toggled on, as the "active" indicator
	local sprintToggled = false

	local function setSprintButtonToggled(toggled)
		sprintToggled = toggled
		sprintButton.BackgroundTransparency = toggled and SPRINT_BUTTON_ON_TRANSPARENCY or SPRINT_BUTTON_OFF_TRANSPARENCY
		setSprinting(toggled)
	end

	sprintButton.Activated:Connect(function()
		setSprintButtonToggled(not sprintToggled)
	end)

	slideButton.Activated:Connect(requestSlide)

	-- Respawning shouldn't carry the toggle over -- match onCharacterAdded's
	-- own isSprinting reset above.
	LocalPlayer.CharacterAdded:Connect(function()
		setSprintButtonToggled(false)
	end)
end
