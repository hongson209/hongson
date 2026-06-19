-- SON HUB V3.5 - Main Loader
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Player = Players.LocalPlayer

local GITHUB_RAW = "local GITHUB_RAW = "https://raw.githubusercontent.com/hongson209/hongson/main/Modules/"

local function LoadModule(path)
    local url = GITHUB_RAW .. path
    local success, result = pcall(function()
        return game:HttpGet(url)
    end)
    if not success then
        warn("Failed to load: " .. path)
        return nil
    end
    local fn, err = loadstring(result)
    if not fn then
        warn("Failed to compile: " .. path .. " - " .. err)
        return nil
    end
    return fn()
end

local function Init()
    print("Loading SON HUB V3.5...")
    
    local Config = LoadModule("Config.lua")
    
    local Dependencies = {
        Config = Config,
        Fluent = nil,
        Players = game:GetService("Players"),
        Workspace = game:GetService("Workspace"),
        ReplicatedStorage = game:GetService("ReplicatedStorage"),
        VirtualInput = game:GetService("VirtualInputManager"),
        VirtualUser = game:GetService("VirtualUser"),
        TweenService = game:GetService("TweenService"),
        RunService = game:GetService("RunService"),
        UserInputService = game:GetService("UserInputService"),
        PlayerGui = Player:WaitForChild("PlayerGui"),
    }
    
    local Utils = LoadModule("Utils.lua")
    Utils:Init(Dependencies)
    Dependencies.Utils = Utils
    
    local Remote = LoadModule("Remote.lua")
    Remote:Init(Dependencies)
    Dependencies.Remote = Remote
    
    local MobManager = LoadModule("MobManager.lua")
    MobManager:Init(Dependencies)
    Dependencies.MobManager = MobManager
    
    local AutoFarm = LoadModule("AutoFarm.lua")
    AutoFarm:Init(Dependencies)
    Dependencies.AutoFarm = AutoFarm
    
    local AutoChest = LoadModule("AutoChest.lua")
    AutoChest:Init(Dependencies)
    Dependencies.AutoChest = AutoChest
    
    local Kill = LoadModule("Kill.lua")
    Kill:Init(Dependencies)
    Dependencies.Kill = Kill
    
    local Spectate = LoadModule("Spectate.lua")
    Spectate:Init(Dependencies)
    Dependencies.Spectate = Spectate
    
    local TeleportToPlayer = LoadModule("TeleportToPlayer.lua")
    TeleportToPlayer:Init(Dependencies)
    Dependencies.TeleportToPlayer = TeleportToPlayer
    
    local Teleport = LoadModule("Teleport.lua")
    Teleport:Init(Dependencies)
    Dependencies.Teleport = Teleport
    
    local AutoBring = LoadModule("AutoBring.lua")
    AutoBring:Init(Dependencies)
    Dependencies.AutoBring = AutoBring
    
    local IslandData = LoadModule("IslandData.lua")
    IslandData:Init(Dependencies)
    Dependencies.IslandData = IslandData
    
    local HakiQuest = LoadModule("HakiQuest.lua")
    HakiQuest:Init(Dependencies)
    Dependencies.HakiQuest = HakiQuest
    
    local Fishing = LoadModule("Fishing.lua")
    Fishing:Init(Dependencies)
    Dependencies.Fishing = Fishing
    
    local Fly = LoadModule("Fly.lua")
    Fly:Init(Dependencies)
    Dependencies.Fly = Fly
    
    local Noclip = LoadModule("Noclip.lua")
    Noclip:Init(Dependencies)
    Dependencies.Noclip = Noclip
    
    local ESP = LoadModule("ESP.lua")
    ESP:Init(Dependencies)
    Dependencies.ESP = ESP
    
    local Events = LoadModule("Events.lua")
    Events:Init(Dependencies)
    Dependencies.Events = Events
    
    local Fluent = loadstring(game:HttpGet("https://github.com/StyearX/Fluent-Modded/releases/download/Fluent/FluentPro"))()
    Dependencies.Fluent = Fluent
    
    local Interface = LoadModule("Interface.lua")
    Interface:Init(Dependencies)
    Interface:Create()
    
    print("SON HUB V3.5 Loaded!")
end

Init()
