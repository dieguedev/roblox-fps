local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SlideEvent = ReplicatedStorage:WaitForChild("SlideEvent")
local SlideAnimationR15 = ReplicatedStorage:WaitForChild("SlideAnimationR15")
local SlideAnimationR6 = ReplicatedStorage:WaitForChild("SlideAnimationR6")

-- Started as a port of the "SlideClient" toolbox script (by SnowCHC), which
-- used a raw BodyVelocity + PlatformStand impulse. That bypassed the
-- Humanoid's own ground-collision handling and tunneled through floors/ramps
-- at speed, so the slide is now driven through WalkSpeed/Humanoid:Move()
-- instead — the same system normal walking/sprinting already uses safely.
local SLIDE_SPEED = 70 -- studs/s at the start of the slide
local MIN_SLIDE_SPEED = 8 -- floor it decays to by the end (~crouch speed)
local SLIDE_DURATION = 0.6
local SLIDE_COOLDOWN = 1 -- seconds; the original script's debounce (`DB`) was declared but never actually set, so it did nothing

local WEAPON_MODEL_NAME = "EquippedWeaponModel"

local lastSlideTime = {}

-- Hides the held weapon model while sliding (it's welded flat to
-- HumanoidRootPart, so it'd otherwise float above the character during the
-- crouched slide pose) and restores each part's original transparency after.
local function setWeaponHidden(character, hidden)
	local model = character:FindFirstChild(WEAPON_MODEL_NAME)
	if not model then return end

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			if hidden then
				part:SetAttribute("PreSlideTransparency", part.Transparency)
				part.Transparency = 1
			else
				local original = part:GetAttribute("PreSlideTransparency")
				if original ~= nil then
					part.Transparency = original
					part:SetAttribute("PreSlideTransparency", nil)
				end
			end
		end
	end
end

SlideEvent.OnServerEvent:Connect(function(player)
	local now = os.clock()
	local last = lastSlideTime[player]
	if last and (now - last) < SLIDE_COOLDOWN then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end

	lastSlideTime[player] = now

	-- Slide in whatever direction the player was actually moving (falls back
	-- to facing direction if MoveDirection is ~0).
	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.05 then
		local look = root.CFrame.LookVector
		direction = Vector3.new(look.X, 0, look.Z)
	end
	if direction.Magnitude > 0 then
		direction = direction.Unit
	else
		direction = Vector3.zero
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end

	local anim = (humanoid.RigType == Enum.HumanoidRigType.R15) and SlideAnimationR15 or SlideAnimationR6
	local slideTrack = animator:LoadAnimation(anim)
	-- Force Action priority regardless of what the animation asset was published
	-- with: the R15 slide clip is authored at Movement priority, the same tier
	-- the default run animation uses, so without this they'd blend together
	-- instead of the slide cleanly overriding it (visible as arms still doing
	-- the run-swing mid-slide).
	slideTrack.Priority = Enum.AnimationPriority.Action
	slideTrack:Play()
	setWeaponHidden(character, true)

	local endTime = os.clock() + SLIDE_DURATION
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not humanoid.Parent or humanoid.Health <= 0 then
			connection:Disconnect()
			setWeaponHidden(character, false)
			return
		end

		local remaining = endTime - os.clock()
		if remaining <= 0 then
			connection:Disconnect()
			setWeaponHidden(character, false)
			SlideEvent:FireClient(player) -- tell the client it can reassert its own WalkSpeed now
			return
		end

		if direction.Magnitude > 0 then
			humanoid:Move(direction, false)
		end
		-- sqrt easing: holds most of the burst speed for the first half and
		-- only sheds it sharply near the end.
		local alpha = math.sqrt(remaining / SLIDE_DURATION)
		humanoid.WalkSpeed = MIN_SLIDE_SPEED + (SLIDE_SPEED - MIN_SLIDE_SPEED) * alpha
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	lastSlideTime[player] = nil
end)
