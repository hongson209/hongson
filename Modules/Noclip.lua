local Noclip = {}
local Dependencies = nil

function Noclip:Init(deps)
    Dependencies = deps
end

local NoclipConnection = nil

function Noclip:Start()
    local Config = Dependencies.Config
    local Utils = Dependencies.Utils
    local RunService = Dependencies.RunService
    
    if Config.NoclipEnabled then return end
    Config.NoclipEnabled = true
    
    if NoclipConnection then NoclipConnection:Disconnect() end
    NoclipConnection = RunService.Stepped:Connect(function()
        if not Config.NoclipEnabled then return end
        local char = Utils.getCharacter()
        if not char then return end
        for _, v in pairs(char:GetDescendants()) do
            if v:IsA("BasePart") and v.CanCollide then
                pcall(function() v.CanCollide = false end)
            end
        end
    end)
end

function Noclip:Stop()
    local Config = Dependencies.Config
    local Utils = Dependencies.Utils
    
    Config.NoclipEnabled = false
    if NoclipConnection then
        NoclipConnection:Disconnect()
        NoclipConnection = nil
    end
    local char = Utils.getCharacter()
    if char then
        for _, v in pairs(char:GetDescendants()) do
            if v:IsA("BasePart") then
                pcall(function() v.CanCollide = true end)
            end
        end
    end
end

function Noclip:Toggle()
    if Dependencies.Config.NoclipEnabled then
        self:Stop()
    else
        self:Start()
    end
end

return Noclip