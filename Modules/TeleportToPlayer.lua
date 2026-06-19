local TeleportToPlayer = {}
local Dependencies = nil

function TeleportToPlayer:Init(deps)
    Dependencies = deps
end

function TeleportToPlayer:Teleport(playerName)
    local Utils = Dependencies.Utils
    local Players = Dependencies.Players
    
    local target = Players:FindFirstChild(playerName)
    if not target or not target.Character then
        Utils.notify("Teleport", "Player not found!")
        return
    end
    
    local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        Utils.notify("Teleport", "No root part!")
        return
    end
    
    local myRoot = Utils.getRoot()
    if myRoot then
        pcall(function()
            myRoot.CFrame = targetRoot.CFrame + Vector3.new(0, 1.5, 1.5)
        end)
        Utils.notify("Teleport", "Teleported to " .. target.Name)
    end
end

return TeleportToPlayer