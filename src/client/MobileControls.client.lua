local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ============================================================
-- UI references: MobileControlsGui/JumpButton and MobileControlsGui/MoveJoystick
-- already exist in StarterGui -- built in Studio, not generated here, same
-- convention as AmmoHud/WeaponSlots. Move them there with the device
-- emulator to change the layout; this script only wires up behavior.
-- ============================================================
local GUI = script.Parent

-- Desktop/console players still get this GUI cloned into their PlayerGui
-- (StarterGui always clones to everyone) -- without this it would just sit
-- there doing nothing on non-touch platforms, so hide the whole thing.
if not UserInputService.TouchEnabled then
    GUI.Enabled = false
    return
end

local jumpButton = GUI:WaitForChild("JumpButton")
local joystick = GUI:WaitForChild("MoveJoystick")
local joystickBase = joystick:WaitForChild("JoystickBase")
local joystickThumb = joystickBase:WaitForChild("JoystickThumb")

-- Roblox's default touch controls (JumpButton/DynamicThumbstickFrame under
-- PlayerGui.TouchGui) are disabled entirely via
-- StarterPlayer.DevTouchMovementMode = Scriptable, so they never get created
-- in the first place -- no need to hide/fight them here.

-- ============================================================
-- Jump: the default Humanoid jump handling already reacts to Humanoid.Jump,
-- same as the native button.
-- ============================================================
jumpButton.Activated:Connect(function()
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.Jump = true
    end
end)

-- ============================================================
-- Movement joystick: drag from JoystickBase's center, clamp the visual thumb
-- to MAX_RADIUS pixels, and drive the humanoid with a camera-relative
-- direction every frame (same convention as WASD -- forward is wherever the
-- camera is looking, flattened to the ground plane).
-- ============================================================
local MAX_RADIUS = 50

local activeInput = nil
local moveDirection = Vector3.zero

local function updateFromInputPosition(inputPosition)
    local center = joystickBase.AbsolutePosition + joystickBase.AbsoluteSize / 2
    local delta = Vector2.new(inputPosition.X, inputPosition.Y) - center
    local distance = delta.Magnitude
    local clamped = (distance > MAX_RADIUS and distance > 0) and delta.Unit * MAX_RADIUS or delta
    joystickThumb.Position = UDim2.new(0.5, clamped.X, 0.5, clamped.Y)

    local normalized = distance > 0 and delta.Unit or Vector2.zero

    local camCFrame = camera.CFrame
    local forward = Vector3.new(camCFrame.LookVector.X, 0, camCFrame.LookVector.Z)
    local right = Vector3.new(camCFrame.RightVector.X, 0, camCFrame.RightVector.Z)
    if forward.Magnitude > 0 then forward = forward.Unit end
    if right.Magnitude > 0 then right = right.Unit end

    moveDirection = (right * normalized.X) + (forward * -normalized.Y)
    if moveDirection.Magnitude > 1 then
        moveDirection = moveDirection.Unit
    end
end

local function releaseJoystick()
    activeInput = nil
    moveDirection = Vector3.zero
    joystickThumb.Position = UDim2.new(0.5, 0, 0.5, 0)
end

joystickBase.InputBegan:Connect(function(input)
    if activeInput then return end
    if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
        return
    end
    activeInput = input
    updateFromInputPosition(input.Position)
end)

UserInputService.InputChanged:Connect(function(input)
    if input ~= activeInput then return end
    updateFromInputPosition(input.Position)
end)

UserInputService.InputEnded:Connect(function(input)
    if input == activeInput then
        releaseJoystick()
    end
end)

RunService.Heartbeat:Connect(function()
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid:Move(moveDirection, false)
    end
end)
