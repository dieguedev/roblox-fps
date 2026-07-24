local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local SlideEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SlideEvent")

local WALK_SPEED = 16
local SPRINT_SPEED = 26
local CROUCH_SPEED = 8
local CROUCH_HIP_HEIGHT_OFFSET = 1.6 -- studs subtracted from the character's own HipHeight while crouched
local SLIDE_COOLDOWN = 1 -- client-side mirror of the server's cooldown, just to keep the button/key from spamming the remote

local humanoid = nil
local normalHipHeight = 2

local isSprinting = false
local isCrouching = false
local isCHeld = false
local canSlide = true

local function currentSpeed()
	if isCrouching then return CROUCH_SPEED end
	if isSprinting then return SPRINT_SPEED end
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

local function onCharacterAdded(character)
	humanoid = character:WaitForChild("Humanoid")
	normalHipHeight = humanoid.HipHeight

	isSprinting = false
	isCrouching = false
	isCHeld = false
	canSlide = true

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
