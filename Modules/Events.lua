local Events = {}
local Dependencies = nil

function Events:Init(deps)
    Dependencies = deps
end

local afkConnection = nil

function Events:SetupAntiAFK()
    local Config = Dependencies.Config
    local Player = Dependencies.Players.LocalPlayer
    local VirtualUser = Dependencies.VirtualUser
    
    if afkConnection then afkConnection:Disconnect() end
    if Config.AntiAFKEnabled then
        afkConnection = Player.Idled:Connect(function()
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end)
    end
end

function Events:SetupPlayerEvents(callback)
    local Players = Dependencies.Players
    Players.PlayerAdded:Connect(function(player)
        task.wait(0.5)
        if callback then callback(player) end
    end)
    
    Players.PlayerRemoving:Connect(function(player)
        task.wait(0.5)
        if callback then callback(player) end
    end)
end

return Events