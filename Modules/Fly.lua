local Fly = {}
local Dependencies = nil

function Fly:Init(deps)
    Dependencies = deps
end

local FlyAttachment = nil
local FlyLinearVelocity = nil
local FlyAlignOrientation = nil
local FlyConnection = nil
local isMobile = false

function Fly:Start()
    local Config = Dependencies.Config
    local Utils = Dependencies.Utils
    local UserInputService = Dependencies.UserInputService
    local RunService = Dependencies.RunService
    
    if Config.FlyEnabled then return end
    Config.FlyEnabled = true
    isMobile = UserInputService.TouchEnabled
    
    local char = Utils.getCharacter()
    if not char then return end
    local root = Utils.getRoot()
    if not root then return end
    
    local animate = char:FindFirstChild("Animate")
    if animate then pcall(function() animate.Disabled = true end) end
    
    pcall(function()
        char.Humanoid.PlatformStand = true
        char.Humanoid.AutoRotate = false
        char.Humanoid.WalkSpeed = 0
        char.Humanoid.JumpPower = 0
    end)
    
    if FlyLinearVelocity then pcall(function() FlyLinearVelocity:Destroy() end) end
    if FlyAlignOrientation then pcall(function() FlyAlignOrientation:Destroy() end) end
    if FlyAttachment then pcall(function() FlyAttachment:Destroy() end) end
    
    FlyAttachment = Instance.new("Attachment")
    FlyAttachment.Parent = root
    
    FlyLinearVelocity = Instance.new("LinearVelocity")
    FlyLinearVelocity.Parent = root
    FlyLinearVelocity.Attachment0 = FlyAttachment
    FlyLinearVelocity.MaxForce = math.huge
    FlyLinearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
    FlyLinearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
    FlyLinearVelocity.VectorVelocity = Vector3.new(0, 0, 0)
    
    -- Dùng AlignOrientation thay BodyGyro (mới hơn, tương thích tốt hơn)
    FlyAlignOrientation = Instance.new("AlignOrientation")
    FlyAlignOrientation.Parent = root
    FlyAlignOrientation.Attachment0 = FlyAttachment
    FlyAlignOrientation.MaxAngularVelocity = 9e9
    FlyAlignOrientation.MaxTorque = math.huge
    FlyAlignOrientation.RigidityEnabled = true
    FlyAlignOrientation.Responsiveness = 1000
    FlyAlignOrientation.CFrame = CFrame.new(root.Position, root.Position + Vector3.new(0, 1, 0))
    
    if FlyConnection then FlyConnection:Disconnect() end
    FlyConnection = RunService.Heartbeat:Connect(function()
        if not Config.FlyEnabled then return end
        local currentRoot = Utils.getRoot()
        if not currentRoot then return end
        
        local moveX = 0
        local moveZ = 0
        local moveY = 0
        local cam = workspace.CurrentCamera
        
        if isMobile then
            local hum = Utils.getHumanoid()
            if hum then
                local dir = hum.MoveDirection
                if dir.Magnitude > 0.1 then
                    local flatLook = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z).Unit
                    local flatRight = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z).Unit
                    moveX = dir:Dot(flatRight)
                    moveZ = dir:Dot(flatLook)
                end
                if hum.Jump then moveY = 1 end
            end
        else
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveZ = moveZ + 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveZ = moveZ - 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveX = moveX - 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveX = moveX + 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveY = moveY + 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveY = moveY - 1 end
        end
        
        local look = cam.CFrame.LookVector
        local right = cam.CFrame.RightVector
        local up = cam.CFrame.UpVector
        
        local velocity = (right * moveX + look * moveZ + up * moveY) * Config.FlySpeed
        FlyLinearVelocity.VectorVelocity = velocity
        
        FlyAlignOrientation.CFrame = CFrame.new(currentRoot.Position, currentRoot.Position + Vector3.new(0, 1, 0))
    end)
end

function Fly:Stop()
    local Config = Dependencies.Config
    local Utils = Dependencies.Utils
    
    Config.FlyEnabled = false
    if FlyConnection then FlyConnection:Disconnect(); FlyConnection = nil end
    if FlyLinearVelocity then pcall(function() FlyLinearVelocity:Destroy() end) end
    if FlyAlignOrientation then pcall(function() FlyAlignOrientation:Destroy() end) end
    if FlyAttachment then pcall(function() FlyAttachment:Destroy() end) end
    
    local char = Utils.getCharacter()
    if char then
        local animate = char:FindFirstChild("Animate")
        if animate then pcall(function() animate.Disabled = false end) end
        pcall(function()
            char.Humanoid.PlatformStand = false
            char.Humanoid.AutoRotate = true
            char.Humanoid.WalkSpeed = 16
            char.Humanoid.JumpPower = 50
        end)
    end
end

function Fly:Toggle()
    if Dependencies.Config.FlyEnabled then
        self:Stop()
    else
        self:Start()
    end
end

return Fly