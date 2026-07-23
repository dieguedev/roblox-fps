local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local WALK_SPEED = 16
local SPRINT_SPEED = 26
local CROUCH_SPEED = 8
local SLIDE_SPEED = 52
local SLIDE_DURATION = 0.75 -- seconds the slide's extra speed takes to decay back to crouch speed
local CROUCH_HIP_HEIGHT_OFFSET = 1.6 -- studs subtracted from the character's own HipHeight while crouched/sliding

local humanoid = nil
local normalHipHeight = 2

local isSprinting = false
local isCrouching = false
local isSliding = false
local isCHeld = false -- tracks the physical key state, separate from isCrouching, so releasing C mid-slide stands up once the slide ends
local slideConnection = nil
local slideEndTime = 0
local slideDirection = Vector3.zero
local stateChangedConnection = nil

local function currentSpeed()
	if isSliding then return SLIDE_SPEED end
	if isCrouching then return CROUCH_SPEED end
	if isSprinting then return SPRINT_SPEED end
	return WALK_SPEED
end

local function currentHipHeight()
	if isCrouching or isSliding then
		return math.max(normalHipHeight - CROUCH_HIP_HEIGHT_OFFSET, 0)
	end
	return normalHipHeight
end

local function refreshMovementState()
	if not humanoid then return end
	humanoid.HipHeight = currentHipHeight()
	if not isSliding then -- while sliding, WalkSpeed is being animated by the slide's own Heartbeat loop
		humanoid.WalkSpeed = currentSpeed()
	end
end

local function endSlide()
	if not isSliding then return end
	isSliding = false
	if slideConnection then
		slideConnection:Disconnect()
		slideConnection = nil
	end
	isCrouching = isCHeld -- stay crouched only if C is still being held
	refreshMovementState()
end

-- Jumping out of a slide (COD-style "omnimovement" cancel): stops forcing the
-- slide direction and stands you back up so you land already sprinting,
-- instead of jumping straight up out of a crouch.
local function cancelSlideForJump()
	if not isSliding then return end
	isSliding = false
	isCrouching = false
	isCHeld = false
	if slideConnection then
		slideConnection:Disconnect()
		slideConnection = nil
	end
	refreshMovementState()
end

local function startSlide()
	if not humanoid or isSliding then return end
	isSliding = true
	isCrouching = true

	-- Slide in whatever direction you were actually moving (falls back to
	-- facing direction if MoveDirection is ~0, e.g. strafe-slide edge cases).
	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude > 0.05 then
		slideDirection = moveDir.Unit
	else
		local rootPart = humanoid.RootPart
		local look = rootPart and Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z) or Vector3.zero
		slideDirection = (look.Magnitude > 0.05) and look.Unit or Vector3.zero
	end

	humanoid.WalkSpeed = SLIDE_SPEED
	humanoid.HipHeight = currentHipHeight()

	slideEndTime = os.clock() + SLIDE_DURATION
	slideConnection = RunService.Heartbeat:Connect(function()
		-- Force the movement regardless of held input: this is what actually
		-- carries you forward, rather than just being a WalkSpeed number that
		-- only matters while you keep holding a direction key.
		if slideDirection.Magnitude > 0 then
			humanoid:Move(slideDirection, false)
		end

		local remaining = slideEndTime - os.clock()
		if remaining <= 0 then
			endSlide()
			return
		end
		-- sqrt easing instead of a straight line: holds most of the burst speed
		-- for the first half of the slide and only sheds it sharply near the
		-- very end, so the slide actually out-paces sprinting over the same time.
		local alpha = math.sqrt(remaining / SLIDE_DURATION)
		humanoid.WalkSpeed = CROUCH_SPEED + (SLIDE_SPEED - CROUCH_SPEED) * alpha
	end)
end

local function onCPressed()
	isCHeld = true
	if isSliding then return end
	if isSprinting and humanoid and humanoid.MoveDirection.Magnitude > 0 then
		startSlide()
	else
		isCrouching = true
		refreshMovementState()
	end
end

local function onCReleased()
	isCHeld = false
	if isSliding then return end -- let the slide play out; endSlide() checks isCHeld once it finishes
	isCrouching = false
	refreshMovementState()
end

local function setSprinting(active)
	isSprinting = active
	refreshMovementState()
end

local function onCharacterAdded(character)
	humanoid = character:WaitForChild("Humanoid")
	normalHipHeight = humanoid.HipHeight

	isSprinting = false
	isCrouching = false
	isSliding = false
	isCHeld = false
	if slideConnection then
		slideConnection:Disconnect()
		slideConnection = nil
	end
	if stateChangedConnection then
		stateChangedConnection:Disconnect()
	end
	stateChangedConnection = humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping or new == Enum.HumanoidStateType.Freefall then
			cancelSlideForJump()
		end
	end)

	refreshMovementState()
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
if LocalPlayer.Character then
	onCharacterAdded(LocalPlayer.Character)
end

LocalPlayer.CharacterRemoving:Connect(function()
	if slideConnection then
		slideConnection:Disconnect()
		slideConnection = nil
	end
	if stateChangedConnection then
		stateChangedConnection:Disconnect()
		stateChangedConnection = nil
	end
	humanoid = nil
end)

-- ============================================================
-- Input: Shift = sprint (held), C = crouch (held) / slide (if C is pressed while sprinting).
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
