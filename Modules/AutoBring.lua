local AutoBring = {}
local Dependencies = nil
local BringLoops = {}

function AutoBring:Init(deps)
    Dependencies = deps
end

local NormalFruitNames = {
    apple = true, banana = true, greenapple = true,
    melon = true, pumpkin = true,
    cantaloupe = true, coconut = true, ["prickly pear"] = true
}

local FruitNames = {
    "Barrier Fruit", "Swim Fruit", "Spring Fruit", "String Fruit",
    "Spin Fruit", "Smelt Fruit", "Snow Fruit", "Slip Fruit",
    "Slow Fruit", "Quake Fruit", "Sand Fruit", "Rumble Fruit",
    "Plasma Fruit", "Phoenix Fruit", "Paw Fruit", "Order Fruit",
    "Magma Fruit", "Ope Fruit", "Luck Fruit", "Love Fruit",
    "Light Fruit", "Hot Fruit", "Gum Fruit", "Gravity Fruit",
    "Gas Fruit", "Float Fruit", "Flare Fruit", "Diamond Fruit",
    "Dark Fruit", "Clone Fruit", "Clear Fruit", "Chop Fruit",
    "Chilly Fruit", "Candy Fruit", "Bomb Fruit", "Buddha Fruit"
}

function AutoBring:StartLoop(name, func)
    -- Dừng loop cũ nếu có
    if BringLoops[name] then
        BringLoops[name] = false
    end
    
    local Config = Dependencies.Config
    local loopVar = true
    BringLoops[name] = loopVar
    
    task.spawn(function()
        while loopVar and Config[name] do
            pcall(func)
            task.wait(0.7)
        end
    end)
end

function AutoBring:StopLoop(name)
    if BringLoops[name] then
        BringLoops[name] = false
    end
end

function AutoBring:BringNormalFruit()
    local Utils = Dependencies.Utils
    local Workspace = Dependencies.Workspace
    local hrp = Utils.getRoot()
    if not hrp then return end
    for _, v in pairs(Workspace:GetDescendants()) do
        if not v then continue end
        local name = v.Name
        if type(name) ~= "string" then continue end
        if NormalFruitNames[string.lower(name)] then
            local part = v:FindFirstChildWhichIsA("BasePart")
            if not part and v:IsA("BasePart") then
                part = v
            end
            if part then
                pcall(function()
                    part.CFrame = hrp.CFrame * CFrame.new(0, -2.5, 0)
                end)
            end
        end
    end
end

function AutoBring:BringDemonFruit()
    local Utils = Dependencies.Utils
    local Workspace = Dependencies.Workspace
    local hrp = Utils.getRoot()
    if not hrp then return end
    for _, obj in pairs(Workspace:GetChildren()) do
        if not obj or not obj:IsA("Tool") then continue end
        local name = obj.Name
        if type(name) ~= "string" then continue end
        for _, fn in ipairs(FruitNames) do
            if name == fn then
                local part = obj:FindFirstChildWhichIsA("BasePart")
                if not part and obj:IsA("BasePart") then
                    part = obj
                end
                if part then
                    pcall(function()
                        part.CFrame = hrp.CFrame * CFrame.new(0, -2.5, 0)
                    end)
                end
                break
            end
        end
    end
end

function AutoBring:BringCompass()
    local Utils = Dependencies.Utils
    local Workspace = Dependencies.Workspace
    local hrp = Utils.getRoot()
    if not hrp then return end
    for _, obj in pairs(Workspace:GetDescendants()) do
        if not obj then continue end
        local name = obj.Name
        if type(name) ~= "string" then continue end
        local lowerName = string.lower(name)
        if lowerName == "compass" or string.find(lowerName, "compass") then
            local part = obj:FindFirstChildWhichIsA("BasePart")
            if not part and obj:IsA("BasePart") then
                part = obj
            end
            if part then
                pcall(function()
                    part.CFrame = hrp.CFrame * CFrame.new(0, -2.5, 0)
                end)
            end
        end
    end
end

function AutoBring:BringOldBook()
    local Utils = Dependencies.Utils
    local Workspace = Dependencies.Workspace
    local hrp = Utils.getRoot()
    if not hrp then return end
    for _, obj in pairs(Workspace:GetDescendants()) do
        if not obj then continue end
        local name = obj.Name
        if type(name) ~= "string" then continue end
        local lowerName = string.lower(name)
        if lowerName == "oldbook" or lowerName == "old book" or string.find(lowerName, "oldbook") then
            local part = obj:FindFirstChildWhichIsA("BasePart")
            if not part and obj:IsA("BasePart") then
                part = obj
            end
            if part then
                pcall(function()
                    part.CFrame = hrp.CFrame * CFrame.new(0, -2.5, 0)
                end)
            end
        end
    end
end

return AutoBring