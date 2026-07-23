-- Service Variables
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

-- UI Variables
local GUI = script.Parent
local HEALTHBAR = GUI:WaitForChild("Healthbar")
local PROGRESSBAR = HEALTHBAR:WaitForChild("Healthbar")
local PERCENTAGE = HEALTHBAR:WaitForChild("percentage")

-- Character Variables
local PLR = Players.LocalPlayer -- LocalPlayer Variable
local CHARACTER = PLR.Character or PLR.CharacterAdded:Wait() -- Character Variable
local HUMANOID = CHARACTER:WaitForChild("Humanoid") -- Humanoid Variable

-- Our own HUD already shows health; the built-in overhead bar would just
-- duplicate it for other players looking at us.
HUMANOID.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

-- Other Variables
local TweenColourInfo = TweenInfo.new(.1, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0)
local Colours = {
	LowHealth = Color3.new(1,.25,.25),
	MidHealth = Color3.new(1,.75,0),
	FullHealth = PROGRESSBAR.BackgroundColor3,
}
local Tweens = {
	LowHealth = {
		TweenService:Create(PROGRESSBAR, TweenColourInfo, {BackgroundColor3=Colours.LowHealth}),
		TweenService:Create(HEALTHBAR.UIStroke, TweenColourInfo, {Color=Colours.LowHealth:Lerp(Color3.new(0,0,0),.75)})
	},
	MidHealth = {
		TweenService:Create(PROGRESSBAR, TweenColourInfo, {BackgroundColor3=Colours.MidHealth}),
		TweenService:Create(HEALTHBAR.UIStroke, TweenColourInfo, {Color=Colours.MidHealth:Lerp(Color3.new(0,0,0),.75)})
	},
	FullHealth = {
		TweenService:Create(PROGRESSBAR, TweenColourInfo, {BackgroundColor3=Colours.FullHealth}),
		TweenService:Create(HEALTHBAR.UIStroke, TweenColourInfo, {Color=Colours.FullHealth:Lerp(Color3.new(0,0,0),.75)})
	},
}
local Connections = {}

-- Functions
local function RunTween(TweenName : string)
	if not Tweens[TweenName] then return error(("Invalid Tween Name %s"):format(TweenName)) end
	if Tweens[TweenName][1].PlaybackState == Enum.PlaybackState.Playing then return end -- Tween already playing.
	for _,Tween in pairs(Tweens[TweenName]) do
		Tween:Cancel()
		Tween:Play()
	end
end

local function UpdateHP(ForceHP : number?)
	local HealthScale = 1/(HUMANOID.MaxHealth/math.floor(ForceHP or (HUMANOID.Health + .5)))
	PROGRESSBAR:TweenSize(UDim2.new(HealthScale,0,1,0), Enum.EasingDirection.Out, Enum.EasingStyle.Linear, .25)
	PERCENTAGE.Text = math.ceil(math.max(ForceHP or HUMANOID.Health, 0)) .. " HP"

	-- I could have made this A LOT better and less hard-coded.
	if HealthScale > .85 then
		RunTween("FullHealth")
	elseif HealthScale >= .35 then
		RunTween("MidHealth")
	else
		RunTween("LowHealth")
	end
end

local function Cleanup()
	for i,v in pairs(Connections) do
		v:Disconnect()
		Connections[i] = nil
	end
end

-- Events
table.insert(Connections, HUMANOID:GetPropertyChangedSignal("Health"):Connect(UpdateHP))
table.insert(Connections, HUMANOID:GetPropertyChangedSignal("MaxHealth"):Connect(UpdateHP))
table.insert(Connections, HUMANOID.Died:Once(function()
	UpdateHP(0)
	Cleanup()
end))

-- Init
UpdateHP()
