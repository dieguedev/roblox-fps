local dummy = script.Parent
local humanoid = dummy:WaitForChild("Humanoid")
local pointA = dummy:GetPivot().Position
local pointB = pointA + Vector3.new(12, 0, 0)

task.wait(1)
while true do
    humanoid:MoveTo(pointB)
    humanoid.MoveToFinished:Wait()
    task.wait(1.5)
    humanoid:MoveTo(pointA)
    humanoid.MoveToFinished:Wait()
    task.wait(1.5)
end
