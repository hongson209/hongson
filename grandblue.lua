-- SON HUB v19 | Nexomia snapshot rebuild | hongson

local VERSION = "20.0.0"
local EXPECTED_PLACE_ID = 118635363908336
local FLUENT_URL =
    "https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"

local ENV = _G
if type(getgenv) == "function" then
    local okEnv, customEnv = pcall(getgenv)
    if okEnv and type(customEnv) == "table" then
        ENV = customEnv
    end
end

if type(ENV.__SON_HUB_UNLOAD) == "function" then
    pcall(ENV.__SON_HUB_UNLOAD)
end

local function envFunction(name)
    local value = rawget(ENV, name)
    if type(value) == "function" then
        return value
    end

    value = rawget(_G, name)
    if type(value) == "function" then
        return value
    end

    return nil
end

local requestFn =
    envFunction("request")
    or envFunction("http_request")

if not requestFn then
    local httpTable = rawget(ENV, "http")
    if type(httpTable) == "table"
        and type(httpTable.request) == "function" then
        requestFn = httpTable.request
    end
end

if not requestFn then
    local synTable = rawget(ENV, "syn")
    if type(synTable) == "table"
        and type(synTable.request) == "function" then
        requestFn = synTable.request
    end
end

local firePromptFn = envFunction("fireproximityprompt")
local fireSignalFn = envFunction("firesignal")
local clipboardFn = envFunction("setclipboard")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local RobloxStats = game:GetService("Stats")

local okVim, VirtualInputManager = pcall(function()
    return game:GetService("VirtualInputManager")
end)
if not okVim then
    VirtualInputManager = nil
end

local okVu, VirtualUser = pcall(function()
    return game:GetService("VirtualUser")
end)
if not okVu then
    VirtualUser = nil
end

local okCore, CoreGui = pcall(function()
    return game:GetService("CoreGui")
end)
if not okCore then
    CoreGui = nil
end

local LocalPlayer = Players.LocalPlayer
local Workspace = workspace

local ExecutorCaps = {
    Http = false,
    Request = type(requestFn) == "function",
    VirtualInput = VirtualInputManager ~= nil,
    FireSignal = type(fireSignalFn) == "function",
    FirePrompt = type(firePromptFn) == "function",
    Clipboard = type(clipboardFn) == "function",
}

local Compat = {}

local function markCap(name, ok)
    if ok == false then
        ExecutorCaps[name] = false
    elseif ExecutorCaps[name] == nil then
        ExecutorCaps[name] = ok == true
    end
    return ok
end

function Compat.Key(held, key)
    if not ExecutorCaps.VirtualInput or not VirtualInputManager or not key then
        return false
    end
    local ok = pcall(function()
        VirtualInputManager:SendKeyEvent(held, key, false, game)
    end)
    markCap("VirtualInput", ok)
    return ok
end

function Compat.Mouse(x, y, held)
    if not ExecutorCaps.VirtualInput or not VirtualInputManager then
        return false
    end
    local ok = pcall(function()
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, held, game, 0)
    end)
    markCap("VirtualInput", ok)
    return ok
end

function Compat.FireSignal(signal)
    if not ExecutorCaps.FireSignal or not fireSignalFn or not signal then
        return false
    end
    local ok = pcall(fireSignalFn, signal)
    markCap("FireSignal", ok)
    return ok
end

function Compat.FirePrompt(prompt, holdDuration)
    if not ExecutorCaps.FirePrompt or not firePromptFn or not prompt then
        return false
    end
    local ok = pcall(
        firePromptFn,
        prompt,
        math.max(0, tonumber(holdDuration) or 0)
    )
    markCap("FirePrompt", ok)
    return ok
end

function Compat.Clipboard(text)
    if not ExecutorCaps.Clipboard or not clipboardFn then
        return false
    end
    local ok = pcall(clipboardFn, tostring(text or ""))
    markCap("Clipboard", ok)
    return ok
end

local function fetchText(url)
    local okHttp, body = pcall(function()
        local method = game.HttpGet
        if type(method) == "function" then
            return game:HttpGet(url)
        end
    end)

    if okHttp
        and type(body) == "string"
        and #body > 500 then
        ExecutorCaps.Http = true
        return body
    end

    if type(requestFn) == "function" then
        local okRequest, response = pcall(requestFn, {
            Url = url,
            Method = "GET",
            Headers = {
                ["User-Agent"] = "SON-HUB-Nexomia",
            },
        })

        if okRequest and type(response) == "table" then
            local responseBody = response.Body or response.body

            if type(responseBody) == "string"
                and #responseBody > 500 then
                return responseBody
            end
        end
    end

    return nil
end

if type(loadstring) ~= "function" then
    error("SON HUB: loadstring is unavailable")
end

local fluentSource = fetchText(FLUENT_URL)
if type(fluentSource) ~= "string" then
    error("SON HUB: unable to fetch Fluent with HttpGet/request")
end

local fluentChunk, fluentCompileError = loadstring(fluentSource)
if type(fluentChunk) ~= "function" then
    error(
        "SON HUB: Fluent compile failed: "
            .. tostring(fluentCompileError)
    )
end

local okFluent, Fluent = pcall(fluentChunk)
if not okFluent or type(Fluent) ~= "table" then
    error(
        "SON HUB: Fluent init failed: "
            .. tostring(Fluent)
    )
end


local Core = {
    Running = true,
    Connections = {},
    Instances = {},
    CollisionBackup = setmetatable({}, {__mode = "k"}),
    HitboxBackup = setmetatable({}, {__mode = "k"}),
}

local Config = {
    -- Full progression
    AutoProgress = false,
    AutoQuest = true,
    AutoAcceptRecommended = true,
    AutoTurnIn = true,
    AutoDialogue = true,
    AutoClaim = true,

    -- Farm
    FarmMode = "Smart Quest",
    SelectedMob = "Nearest Hostile",

    -- Auto Farm combat
    AutoAttack = true,
    AttackRate = 7,
    CombatDistance = 5,
    FarmAnchorHeight = 0.4,

    -- Mob gather uses real aggro/follow behaviour.
    AutoGather = true,
    GatherRadius = 85,
    GatherMax = 4,
    GatherAggroDistance = 5.0,
    GatherStackRadius = 5,
    GatherFollowWait = 0.75,
    GatherFailureLimit = 3,

    -- Single movement owner
    PlatformTransport = true,
    PlatformSpeed = 175,
    TweenSpeed = 175,
    PlatformNpcHeight = 0.25,
    PlatformBackDistance = 5,
    PlatformArrivalDistance = 3.5,
    PlatformRetargetDistance = 4.0,
    FarmHoldCorrectionDistance = 4.5,
    PlatformNoclip = true,

    -- Combat
    AutoBlock = false,
    BlockHealthPercent = 40,
    MobHitbox = false,
    MobHitboxSize = 10,
    MobHitboxTransparency = 0.72,

    -- Stats
    AutoStats = false,
    StatBuild = "Auto",
    StatSpendInterval = 0.25,

    -- Collection / lifeskills
    AutoPickup = false,
    AutoChest = false,
    AutoWorldBossChest = false,
    AutoFruitChest = false,
    AutoChestRoute = true,
    ChestCollectRadius = 65,
    AutoQuestItems = false,

    AutoMining = false,
    AutoMiningQTE = true,
    MiningMode = "Any Available",
    SelectedOre = "Copper Ore",
    MiningCriticalTolerance = 0.035,
    MiningHoldTimeout = 5.0,
    MiningRetryDelay = 0.55,
    MiningStartTimeout = 1.8,
    MiningNoOreRetry = 1.4,
    MiningAutoAim = false,

    AutoFarming = false,

    AutoFishing = false,
    FishingSpotMode = "Anchor Town Pond",
    FishingAutoReturn = true,
    FishingRequireBait = false,
    FishingBiteTimeout = 40,
    FishingEquipSettle = 0.35,
    FishingCooldown = 2.0,
    FishingReelTolerance = 14,
    FishingAutoCalibrate = true,
    FishingHoldMovesRight = true,
    FishingAutoShake = true,
    FishingAutoSpamClick = true,
    FishingAutoTimedRelease = true,
    FishingReleaseThreshold = 0.92,

    -- Movement / player
    SpeedOverride = false,
    WalkSpeed = 24,
    JumpOverride = false,
    JumpPower = 55,
    InfiniteJump = false,
    Noclip = false,
    AntiAFK = true,

    -- ESP
    CurrentTargetESP = true,
    PlayerESP = false,
    MobESP = false,
    BossESP = false,
    LootESP = false,
    ESPDistance = 1200,
    TargetColor = Color3.fromRGB(95, 200, 255),
    PlayerColor = Color3.fromRGB(170, 125, 255),
    MobColor = Color3.fromRGB(255, 205, 80),
    BossColor = Color3.fromRGB(255, 75, 95),
    LootColor = Color3.fromRGB(115, 255, 145),
}

local Runtime = {
    Prompts = setmetatable({}, {__mode = "k"}),
    Entities = setmetatable({}, {__mode = "k"}),
    DialogueNPCs = setmetatable({}, {__mode = "k"}),
    DialogueQuestNames = setmetatable({}, {__mode = "k"}),
    Ores = setmetatable({}, {__mode = "k"}),
    WorldMarkers = setmetatable({}, {__mode = "k"}),

    IndexReady = false,

    ProgressState = "IDLE",
    ProgressDetail = "Waiting",
    ProgressQuestKey = nil,

    FarmFSM = {
        State = "IDLE",
        Since = 0,
        QuestKey = nil,
        TaskKey = nil,
        InteractionAttempts = 0,
        LastInteraction = 0,
        LastResolverRefresh = 0,
        NoMobSince = 0,
        LastAnchorRefresh = 0,
        InteractionNPC = nil,
        InteractionPrompt = nil,
        InteractionGoal = nil,
        InteractionArrivedAt = 0,
        InteractionLockUntil = 0,
        PromptAttemptAt = 0,
        PromptAttemptCount = 0,

        LockedQuestId = nil,
        LockedTaskOrder = nil,
        LockedTaskKind = nil,
        LockedTaskTarget = nil,
        LockedTaskUntil = 0,
    },

    Gather = {
        State = "IDLE",
        Wanted = nil,
        Anchor = nil,
        AnchorSource = nil,
        AnchorMob = nil,
        Target = nil,
        InitialTargetDistance = 0,
        PhaseSince = 0,
        Failures = 0,
        Gathered = 0,
        Total = 0,
        Fallback = false,
        Cooldown = setmetatable({}, {__mode = "k"}),
    },

    LootRouteTarget = nil,
    LootRouteKind = nil,
    PromptUseAt = setmetatable({}, {__mode = "k"}),

    CurrentTarget = nil,
    CurrentWantedMob = nil,
    FarmAnchorCFrame = nil,

    LastInteraction = 0,
    LastQuestChange = 0,
    LastAttack = 0,
    LastStatsSpend = 0,
    StatsSpendFailures = 0,
    StatsSpendStatus = "Idle",

    CharacterCollisionBackup = setmetatable({}, {__mode = "k"}),

    FishingState = "IDLE",
    FishingStateSince = 0,
    FishingSpotCFrame = nil,
    FishingReason = "Disabled",
    FishingHadReel = false,
    FishingMouseHeld = false,
    FishingKeyHeld = nil,
    FishingLastCast = 0,
    FishingEquippedRod = nil,
    FishingEquippedAt = 0,
    FishingRodCache = nil,
    FishingRodCacheAt = 0,
    FishingBaitCache = nil,
    FishingBaitCacheAt = 0,
    FishingLastShakeClick = 0,
    FishingLastShakePosition = nil,
    FishingLastSpamClick = 0,
    FishingTimedReleaseDone = false,
    FishingReelCalibrated = false,
    FishingHoldDirection = 1,
    FishingLastMoveCenter = nil,
    FishingLastMoveVelocity = 0,

    MiningLastQTE = 0,
    MiningState = "IDLE",
    MiningStateSince = 0,
    MiningTarget = nil,
    MiningMouseHeld = false,
    MiningLastAttempt = 0,
    MiningNoOreSince = 0,
    MiningReleaseDone = false,
    MiningEquippedSlot = nil,
    MiningEquipAt = 0,
    MiningTeleportedTarget = nil,
    MiningLastIndexRefresh = 0,
    ProgressLifeSkill = nil,

    IslandLandingCache = {},


    ClaimButtons = setmetatable({}, {__mode = "k"}),

    BlockHeld = false,

    QuestCatalog = {},
    QuestCatalogByName = {},
    QuestToNPCs = {},

    LastLevel = nil,

    WorkerTicks = {
        Progress = 0,
        Fishing = 0,
        Mining = 0,
        Prompts = 0,
        Stats = 0,
        Block = 0,
        Claims = 0,
        ESP = 0,
    },
    WorkerErrors = {},
    WorkerErrorCount = {},
    LastWorkerErrorNotify = {},
}

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(Core.Connections, connection)
    return connection
end

local function track(instance)
    table.insert(Core.Instances, instance)
    return instance
end

local function notify(title, description, duration)
    if not Fluent then
        return
    end

    pcall(function()
        Fluent:Notify({
            Title = tostring(title or "SON HUB"),
            Content = tostring(description or ""),
            Duration = tonumber(duration) or 3,
        })
    end)
end

local function workerTrace(errorValue)
    local message = tostring(errorValue)
    if type(debug) == "table" and type(debug.traceback) == "function" then
        local ok, trace = pcall(debug.traceback, message, 2)
        if ok and type(trace) == "string" then
            return trace
        end
    end
    return message
end

local function safeWorker(name, callback)
    local ok, result = xpcall(callback, workerTrace)

    Runtime.WorkerTicks[name] = (Runtime.WorkerTicks[name] or 0) + 1

    if ok then
        Runtime.WorkerErrors[name] = nil
        Runtime.WorkerErrorCount[name] = 0
        return result
    end

    Runtime.WorkerErrors[name] = result
    Runtime.WorkerErrorCount[name] = (Runtime.WorkerErrorCount[name] or 0) + 1

    local now = os.clock()
    if now - (Runtime.LastWorkerErrorNotify[name] or 0) >= 8 then
        Runtime.LastWorkerErrorNotify[name] = now
        notify(
            name .. " worker error",
            tostring(result):sub(1, 320),
            7
        )
    end

    return nil
end

local function normalize(value)
    local text = tostring(value or "")
    text = text:gsub("<.->", "")
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function lower(value)
    return string.lower(normalize(value))
end

local function stripRuntimeSuffix(name)
    local value = normalize(name)
    value = value:gsub("%s*%[%d+%]%s*$", "")
    value = value:gsub("%s+%d+$", "")
    return normalize(value)
end

local function character()
    return LocalPlayer.Character
end

local function humanoid()
    local char = character()
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function rootPart()
    local char = character()
    return char and (
        char:FindFirstChild("HumanoidRootPart")
        or char.PrimaryPart
        or char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("Torso")
    )
end

local function objectRoot(object)
    if not object then
        return nil
    end

    if object:IsA("BasePart") then
        return object
    end

    if object:IsA("Attachment") then
        return object.Parent and object.Parent:IsA("BasePart") and object.Parent or nil
    end

    if object:IsA("ProximityPrompt") then
        return objectRoot(object.Parent)
    end

    if object:IsA("Model") then
        return object:FindFirstChild("HumanoidRootPart")
            or object.PrimaryPart
            or object:FindFirstChild("UpperTorso")
            or object:FindFirstChild("Torso")
            or object:FindFirstChildWhichIsA("BasePart", true)
    end

    local model = object:FindFirstAncestorWhichIsA("Model")
    return model and objectRoot(model) or nil
end

local function distanceTo(object)
    local ownRoot = rootPart()
    local target = objectRoot(object)

    if not ownRoot or not target then
        return math.huge
    end

    return (ownRoot.Position - target.Position).Magnitude
end

local function isGuiVisible(guiObject)
    if not guiObject or not guiObject:IsA("GuiObject") then
        return false
    end

    local current = guiObject
    while current and current:IsA("GuiObject") do
        if current.Visible == false then
            return false
        end
        current = current.Parent
    end

    local screen = guiObject:FindFirstAncestorWhichIsA("ScreenGui")
    return not screen or screen.Enabled
end

local function isScriptTemplateDescendant(object)
    local current = object and object.Parent
    while current and current ~= game do
        if current:IsA("LocalScript")
            or current:IsA("ModuleScript")
            or current:IsA("Script") then
            return true
        end
        current = current.Parent
    end

    return false
end

local function isOnScreen(guiObject)
    if not guiObject or not guiObject:IsA("GuiObject") or not isGuiVisible(guiObject) then
        return false
    end

    local pos = guiObject.AbsolutePosition
    local size = guiObject.AbsoluteSize
    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)

    return size.X > 0
        and size.Y > 0
        and pos.X + size.X >= 0
        and pos.Y + size.Y >= 0
        and pos.X <= viewport.X
        and pos.Y <= viewport.Y
end

local function textOf(object)
    if not object then
        return ""
    end

    if object:IsA("TextLabel")
        or object:IsA("TextButton")
        or object:IsA("TextBox") then
        return normalize(object.Text)
    end

    local label = object:FindFirstChildWhichIsA("TextLabel", true)
    return label and normalize(label.Text) or ""
end

local function pressKey(key, holdTime)
    if not VirtualInputManager
        or not key
        or key == Enum.KeyCode.Unknown then
        return false
    end

    holdTime = holdTime or 0.035

    if not Compat.Key(true, key) then
        return false
    end
    task.wait(holdTime)
    return Compat.Key(false, key)
end

local function mouseClickAt(x, y)
    if not VirtualInputManager then
        return false
    end

    if not Compat.Mouse(x, y, true) then
        return false
    end
    task.wait(0.025)
    return Compat.Mouse(x, y, false)
end

local function mouseClickCenter()
    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)
    return mouseClickAt(viewport.X / 2, viewport.Y / 2)
end

local function mouseButtonAt(x, y, held)
    if not VirtualInputManager then
        return false
    end

    return Compat.Mouse(x, y, held)
end

local function screenPointOf(object)
    local camera = Workspace.CurrentCamera
    local part = objectRoot(object)
    if not camera or not part then
        return nil
    end

    local point, visible = camera:WorldToViewportPoint(part.Position)
    if not visible or point.Z <= 0 then
        return nil
    end

    return Vector2.new(point.X, point.Y)
end

local function clickButton(button, allowHiddenSignal)
    if not button or not button:IsA("GuiButton") then
        return false
    end

    if Compat.FireSignal(button.Activated) then
        return true
    end

    if allowHiddenSignal ~= true and not isGuiVisible(button) then
        return false
    end

    if not isOnScreen(button) then
        return false
    end

    local pos = button.AbsolutePosition
    local size = button.AbsoluteSize
    return mouseClickAt(pos.X + size.X / 2, pos.Y + size.Y / 2)
end

local function clickButtonReliable(button)
    if not button or not button:IsA("GuiButton") then
        return false
    end

    if type(fireSignalFn) == "function" then
        return clickButton(button, true)
    end

    local screen = button:FindFirstAncestorWhichIsA("ScreenGui")
    local wasEnabled = screen and screen.Enabled

    if screen and not wasEnabled then
        screen.Enabled = true
        RunService.RenderStepped:Wait()
    end

    local ok = clickButton(button, false)

    if screen and not wasEnabled then
        task.defer(function()
            if screen and screen.Parent then
                screen.Enabled = false
            end
        end)
    end

    return ok
end

-- ============================================================
-- Runtime index
-- ============================================================

local RuntimeIndex = {}

local function entitiesFolder()
    return Workspace:FindFirstChild("Entities")
end

local function dialogueRoot()
    local important = Workspace:FindFirstChild("AA IMPORTANT")
    return important and important:FindFirstChild("DialogueNPCs")
end

function RuntimeIndex.Register(instance)
    if not instance then
        return
    end

    if instance:IsA("ProximityPrompt") then
        Runtime.Prompts[instance] = true
        return
    end

    if instance:IsA("BillboardGui") then
        Runtime.WorldMarkers[instance] = true
        return
    end

    if instance:IsA("BasePart") then
        return
    end

    if not instance:IsA("Model") then
        return
    end

    if instance:GetAttribute("ObjectType") == "Ore"
        or instance:GetAttribute("Ore") ~= nil then
        Runtime.Ores[instance] = true
    end

    local entities = entitiesFolder()
    if entities and instance:IsDescendantOf(entities) then
        local hasHumanoid =
            instance:FindFirstChildOfClass("Humanoid") ~= nil

        local combatTagged =
            instance:GetAttribute("Combat") == true
            or instance:GetAttribute("NPCCombat") == true
            or instance:GetAttribute("BossCombat") == true
            or instance:GetAttribute("NPCName") ~= nil
            or instance:GetAttribute("NPCType") ~= nil

        if instance.Parent == entities
            or hasHumanoid
            or combatTagged then
            Runtime.Entities[instance] = true
        end
    end

    local dialogues = dialogueRoot()
    if dialogues and instance:IsDescendantOf(dialogues) then
        local parent = instance.Parent
        if parent and parent.Parent == dialogues then
            Runtime.DialogueNPCs[instance] = true
        end
    end
end

function RuntimeIndex.Unregister(instance)
    Runtime.Prompts[instance] = nil
    Runtime.Entities[instance] = nil
    Runtime.DialogueNPCs[instance] = nil
    Runtime.DialogueQuestNames[instance] = nil
    Runtime.Ores[instance] = nil
    Runtime.WorldMarkers[instance] = nil
end

function RuntimeIndex.Rebuild()
    Runtime.IndexReady = false

    table.clear(Runtime.Prompts)
    table.clear(Runtime.Entities)
    table.clear(Runtime.DialogueNPCs)
    table.clear(Runtime.DialogueQuestNames)
    table.clear(Runtime.Ores)
    table.clear(Runtime.WorldMarkers)

    local descendants = Workspace:GetDescendants()

    for index, instance in ipairs(descendants) do
        RuntimeIndex.Register(instance)

        if index % 5000 == 0 then
            task.wait()
        end
    end

    Runtime.IndexReady = true
end

connect(Workspace.DescendantAdded, RuntimeIndex.Register)
connect(Workspace.DescendantRemoving, RuntimeIndex.Unregister)

task.spawn(RuntimeIndex.Rebuild)

-- ============================================================
-- Player state
-- ============================================================

local PlayerState = {}

function PlayerState.GetLevel()
    local direct = tonumber(LocalPlayer:GetAttribute("Level"))
    if direct then
        return direct
    end

    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    local value = leaderstats and (
        leaderstats:FindFirstChild("Level")
        or leaderstats:FindFirstChild("Lvl")
    )

    if value and (value:IsA("IntValue") or value:IsA("NumberValue")) then
        return tonumber(value.Value) or 0
    end

    return 0
end

function PlayerState.GetWorld()
    return tostring(
        LocalPlayer:GetAttribute("WorldType")
        or Workspace:GetAttribute("WorldType")
        or "Unknown"
    )
end

function PlayerState.GetFruit()
    return tostring(LocalPlayer:GetAttribute("Fruit") or "None")
end

function PlayerState.GetFruitLevel()
    return tonumber(LocalPlayer:GetAttribute("FruitLevel")) or 0
end

function PlayerState.GetEntity()
    local entities = entitiesFolder()
    return entities and entities:FindFirstChild(LocalPlayer.Name)
end

function PlayerState.GetWeaponTypes()
    local entity = PlayerState.GetEntity()
    if not entity then
        return {}
    end

    local result = {}
    for index = 1, 3 do
        local value = entity:GetAttribute("WeaponType" .. index)
        if value and tostring(value) ~= "" then
            table.insert(result, tostring(value))
        end
    end

    return result
end

function PlayerState.GetHealthPercent()
    local hum = humanoid()
    if not hum or hum.MaxHealth <= 0 then
        return 100
    end

    return math.clamp((hum.Health / hum.MaxHealth) * 100, 0, 100)
end

function PlayerState.GetLeaderValue(name)
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    local value = leaderstats and leaderstats:FindFirstChild(name)
    return value and value.Value or nil
end

function PlayerState.IsReady()
    local loaded = LocalPlayer:GetAttribute("Loaded")
    local playerLoaded = LocalPlayer:GetAttribute("PlayerLoaded")

    if loaded == nil and playerLoaded == nil then
        return humanoid() ~= nil and rootPart() ~= nil
    end

    return loaded ~= false
        and playerLoaded ~= false
        and humanoid() ~= nil
        and rootPart() ~= nil
end

-- ============================================================
-- Quest service
-- ============================================================

QuestService = {}

local function questScreen()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    return playerGui and playerGui:FindFirstChild("Quests")
end

local function questScrollingFrame()
    local gui = questScreen()
    local quest = gui and gui:FindFirstChild("Quest")
    return quest and quest:FindFirstChild("ScrollingFrame")
end

local function questStorage()
    local gui = questScreen()
    local quest = gui and gui:FindFirstChild("Quest")
    local localScript = quest and quest:FindFirstChild("QuestLocal")
    return localScript and localScript:FindFirstChild("Storage")
end

local function taskIsComplete(frame, rawText)
    if rawText:find("<s>", 1, true) then
        return true
    end

    local checkbox = frame:FindFirstChild("Checkbox")
    if checkbox and checkbox:IsA("GuiObject") and checkbox.Visible then
        return true
    end

    local current, required = rawText:match("%((%d+)%s*/%s*(%d+)%)")
    if current and required and tonumber(current) >= tonumber(required) then
        return true
    end

    return false
end

local function parseQuestTask(raw, questName)
    local clean = normalize(raw)
    clean = clean:gsub("^[-•]%s*", "")
    clean = clean:gsub("%s*%(%d+%s*/%s*%d+%)%.?$", "")
    clean = normalize(clean)

    local eventGated =
        lower(clean):find("when it opens", 1, true) ~= nil
        or lower(clean):find("when it appears", 1, true) ~= nil
        or lower(clean):find("when available", 1, true) ~= nil

    local patterns = {
        {"Defeat", "^Defeat%s+(.+)$"},
        {"Defeat", "^Kill%s+(.+)$"},
        {"Talk", "^Talk%s+[Tt]o%s+(.+)$"},
        {"Talk", "^Speak%s+[Tt]o%s+(.+)$"},
        {"Collect", "^Collect%s+(.+)$"},
        {"Collect", "^Gather%s+(.+)$"},
        {"Collect", "^Get%s+(.+)$"},
        {"Deliver", "^Deliver%s+(.+)$"},
        {"Return", "^Return%s+[Tt]o%s+(.+)$"},
        {"Find", "^Find%s+(.+)$"},
        {"Reach", "^Reach%s+(.+)$"},
        {"Reach", "^Go%s+[Tt]o%s+(.+)$"},
        {"Reach", "^Visit%s+(.+)$"},
        {"Reach", "^Travel%s+[Tt]o%s+(.+)$"},
        {"Reach", "^Enter%s+(.+)$"},
        {"Reach", "^Wait%s+[Aa]t%s+(.+)$"},
        {"Reach", "^Be%s+[Aa]t%s+(.+)%s+[Ww]hen%s+.+$"},
        {"Interact", "^Interact%s+[Ww]ith%s+(.+)$"},
        {"Interact", "^Open%s+(.+)$"},
        {"Interact", "^Activate%s+(.+)$"},
        {"Use", "^Use%s+(.+)$"},
        {"Equip", "^Equip%s+(.+)$"},
        {"Craft", "^Craft%s+(.+)$"},
        {"Craft", "^Forge%s+(.+)$"},
        {"Craft", "^Smelt%s+(.+)$"},
        {"Fish", "^Catch%s+(.+)$"},
        {"Fish", "^Fish%s+(.+)$"},
        {"Mine", "^Mine%s+(.+)$"},
        {"Farm", "^Harvest%s+(.+)$"},
        {"Farm", "^Grow%s+(.+)$"},
        {"Farm", "^Plant%s+(.+)$"},
        {"Treasure", "^Dig%s+(.+)$"},
        {"Treasure", "^Excavate%s+(.+)$"},
        {"Cook", "^Cook%s+(.+)$"},
        {"Upgrade", "^Upgrade%s+(.+)$"},
        {"Learn", "^Learn%s+(.+)$"},
        {"Buy", "^Buy%s+(.+)$"},
        {"Sell", "^Sell%s+(.+)$"},
        {"Claim", "^Claim%s+(.+)$"},
        {"Destroy", "^Destroy%s+(.+)$"},
        {"Collect", "^Pick%s+[Uu]p%s+(.+)$"},
    }

    for _, pattern in ipairs(patterns) do
        local target = clean:match(pattern[2])
        if target then
            return pattern[1], normalize(target), eventGated
        end
    end

    local value = lower(clean)
    if value:find("be there", 1, true)
        or value:find("wait there", 1, true) then
        return "Reach", normalize(questName or clean), true
    end

    return "Unknown", clean, eventGated
end

function QuestService.GetActiveQuests()
    local scrolling = questScrollingFrame()
    if not scrolling then
        return {}
    end

    local byId = {}

    for _, child in ipairs(scrolling:GetChildren()) do
        if child.Name == "QuestTitle" then
            local questId = child:GetAttribute("QuestId")

            if questId ~= nil then
                local questName = child:GetAttribute("QuestName")
                local nameLabel = child:FindFirstChild("QuestName", true)

                byId[questId] = {
                    Id = questId,
                    Name = normalize(
                        questName
                        or (nameLabel and textOf(nameLabel))
                        or ""
                    ),
                    Tasks = {},
                    Complete = false,
                    LayoutOrder = child.LayoutOrder,
                }
            end
        end
    end

    for _, child in ipairs(scrolling:GetChildren()) do
        if child.Name == "Task" then
            local questId = child:GetAttribute("QuestId")
            local quest = questId ~= nil and byId[questId]

            if quest then
                local info = child:FindFirstChild("Info1", true)
                local raw = info and tostring(info.Text) or ""
                local kind, target, eventGated =
                    parseQuestTask(raw, quest.Name)

                table.insert(quest.Tasks, {
                    Frame = child,
                    Text = normalize(raw),
                    RawText = raw,
                    Kind = kind,
                    Target = target,
                    EventGated = eventGated == true,
                    Complete = taskIsComplete(child, raw),
                    LayoutOrder = child.LayoutOrder,
                })
            end
        end
    end

    local result = {}

    for _, quest in pairs(byId) do
        table.sort(quest.Tasks, function(a, b)
            return a.LayoutOrder < b.LayoutOrder
        end)

        local complete = #quest.Tasks > 0
        for _, taskData in ipairs(quest.Tasks) do
            if not taskData.Complete then
                complete = false
                break
            end
        end

        quest.Complete = complete
        table.insert(result, quest)
    end

    table.sort(result, function(a, b)
        local aOrder = tonumber(a.LayoutOrder) or math.huge
        local bOrder = tonumber(b.LayoutOrder) or math.huge

        if aOrder ~= bOrder then
            return aOrder < bOrder
        end

        return tostring(a.Id) < tostring(b.Id)
    end)

    return result
end

local TASK_PRIORITY = {
    Talk = 130,
    Return = 125,
    Deliver = 122,
    Defeat = 118,
    Collect = 112,
    Interact = 110,
    Equip = 108,
    Use = 106,
    Find = 102,
    Reach = 96,
    Mine = 90,
    Fish = 90,
    Farm = 90,
    Treasure = 88,
    Craft = 82,
    Cook = 82,
    Upgrade = 82,
    Learn = 80,
    Claim = 78,
    Destroy = 76,
    Buy = 40,
    Sell = 40,
    Unknown = 10,
}

function QuestService.GetNextTask()
    local bestQuest
    local bestTask
    local bestScore = -math.huge
    local bestOrder = math.huge

    for _, quest in ipairs(QuestService.GetActiveQuests()) do
        for _, taskData in ipairs(quest.Tasks) do
            if not taskData.Complete then
                local score =
                    TASK_PRIORITY[taskData.Kind]
                    or TASK_PRIORITY.Unknown

                if taskData.EventGated then
                    score -= 85
                end

                local order =
                    (tonumber(quest.LayoutOrder) or 9999) * 1000
                    + (tonumber(taskData.LayoutOrder) or 999)

                if score > bestScore
                    or (
                        score == bestScore
                        and order < bestOrder
                    ) then

                    bestQuest = quest
                    bestTask = taskData
                    bestScore = score
                    bestOrder = order
                end
            end
        end
    end

    return bestQuest, bestTask
end


local function sameQuestId(a, b)
    return tostring(a) == tostring(b)
end

function QuestService.ClearTaskLock()
    local fsm = Runtime.FarmFSM
    fsm.LockedQuestId = nil
    fsm.LockedTaskOrder = nil
    fsm.LockedTaskKind = nil
    fsm.LockedTaskTarget = nil
    fsm.LockedTaskUntil = 0
end

local function lockQuestTask(quest, taskData)
    local fsm = Runtime.FarmFSM
    fsm.LockedQuestId = quest and quest.Id or nil
    fsm.LockedTaskOrder = taskData and taskData.LayoutOrder or nil
    fsm.LockedTaskKind = taskData and taskData.Kind or nil
    fsm.LockedTaskTarget = taskData and taskData.Target or nil

    if taskData and taskData.EventGated then
        fsm.LockedTaskUntil = os.clock() + 1.6
    else
        fsm.LockedTaskUntil = math.huge
    end
end

local function findLockedTask()
    local fsm = Runtime.FarmFSM

    if fsm.LockedQuestId == nil then
        return nil, nil
    end

    if os.clock() > (fsm.LockedTaskUntil or 0) then
        QuestService.ClearTaskLock()
        return nil, nil
    end

    for _, quest in ipairs(QuestService.GetActiveQuests()) do
        if sameQuestId(quest.Id, fsm.LockedQuestId) then
            for _, taskData in ipairs(quest.Tasks) do
                if not taskData.Complete
                    and taskData.LayoutOrder == fsm.LockedTaskOrder
                    and taskData.Kind == fsm.LockedTaskKind
                    and taskData.Target == fsm.LockedTaskTarget then
                    return quest, taskData
                end
            end
        end
    end

    QuestService.ClearTaskLock()
    return nil, nil
end

function QuestService.GetStableTask()
    local quest, taskData = findLockedTask()
    if quest and taskData then
        return quest, taskData
    end

    quest, taskData = QuestService.GetNextTask()

    if quest and taskData then
        lockQuestTask(quest, taskData)
    end

    return quest, taskData
end

function QuestService.GetCompletedQuest()
    for _, quest in ipairs(QuestService.GetActiveQuests()) do
        if quest.Complete then
            return quest
        end
    end

    return nil
end

function QuestService.GetRecommended()
    local storage = questStorage()
    local recommended = storage and storage:FindFirstChild("RecommendedQuest")

    if not recommended then
        return nil
    end

    local info = recommended:FindFirstChild("Info1", true)
    local text = info and normalize(info.Text) or ""
    local name = text:match("[Rr]ecommended:%s*(.+)$")

    if not name or name == "" then
        return nil
    end

    return {
        Id = recommended:GetAttribute("QuestId"),
        Name = normalize(name),
    }
end

function QuestService.StateKey()
    local completed = QuestService.GetCompletedQuest()
    if completed then
        return "complete|" .. tostring(completed.Id) .. "|" .. completed.Name
    end

    local quest, taskData = QuestService.GetStableTask()
    if quest and taskData then
        return "task|"
            .. tostring(quest.Id)
            .. "|"
            .. tostring(taskData.LayoutOrder)
            .. "|"
            .. taskData.Kind
            .. "|"
            .. taskData.Target
    end

    local recommended = QuestService.GetRecommended()
    if recommended then
        return "recommended|" .. tostring(recommended.Id) .. "|" .. recommended.Name
    end

    return "idle"
end

-- ============================================================
-- Integrated Quest Planner
-- ============================================================

QuestPlannerService = {}

function QuestPlannerService.GetPlan()
    local level = PlayerState.GetLevel()
    local active = QuestService.GetActiveQuests()

    if #active > 0 then
        local completed = QuestService.GetCompletedQuest()
        if completed then
            return {
                Mode = "TURN_IN",
                Level = level,
                ActiveCount = #active,
                Quest = completed,
                Task = nil,
            }
        end

        local quest, taskData = QuestService.GetStableTask()

        return {
            Mode = quest and taskData and "ACTIVE_TASK" or "ACTIVE_WAIT",
            Level = level,
            ActiveCount = #active,
            Quest = quest,
            Task = taskData,
        }
    end

    -- The game's RecommendedQuest object is preferred over a guessed
    -- hard-coded level table. It is the client-visible recommendation
    -- produced by the game for the current player state/level.
    QuestService.ClearTaskLock()

    local recommended = QuestService.GetRecommended()

    if recommended then
        return {
            Mode = "ACCEPT_RECOMMENDED",
            Level = level,
            ActiveCount = 0,
            Recommended = recommended,
        }
    end

    return {
        Mode = "NO_QUEST",
        Level = level,
        ActiveCount = 0,
    }
end

function QuestPlannerService.GetSummary()
    local plan = QuestPlannerService.GetPlan()

    if plan.Mode == "TURN_IN" then
        return string.format(
            "Lv.%s • Turn-in • %s",
            tostring(plan.Level),
            tostring(plan.Quest and plan.Quest.Name or "Unknown")
        )
    elseif plan.Mode == "ACTIVE_TASK" then
        return string.format(
            "Lv.%s • %s • %s",
            tostring(plan.Level),
            tostring(plan.Quest and plan.Quest.Name or "Quest"),
            tostring(plan.Task and plan.Task.Text or "Task")
        )
    elseif plan.Mode == "ACCEPT_RECOMMENDED" then
        return string.format(
            "Lv.%s • No active quest • Recommended: %s",
            tostring(plan.Level),
            tostring(
                plan.Recommended
                and plan.Recommended.Name
                or "Unknown"
            )
        )
    end

    return string.format(
        "Lv.%s • %s",
        tostring(plan.Level),
        plan.Mode
    )
end

-- ============================================================
-- Quest catalog + quest NPC mapping
-- ============================================================

QuestCatalogService = {}

local function questModulesRoot()
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local questInfo = modules and modules:FindFirstChild("QuestInfo")
    return questInfo and questInfo:FindFirstChild("Quests")
end

local function relativePath(root, object)
    local names = {}
    local current = object

    while current and current ~= root do
        table.insert(names, 1, current.Name)
        current = current.Parent
    end

    return table.concat(names, "/")
end

local function findDialogueNpcRoot(descendant)
    local root = dialogueRoot()
    if not root then
        return nil
    end

    local current = descendant
    while current and current.Parent do
        if current:IsA("Model")
            and current.Parent.Parent == root then
            return current
        end

        current = current.Parent
    end

    return descendant:FindFirstAncestorWhichIsA("Model")
end

function QuestCatalogService.Build()
    table.clear(Runtime.QuestCatalog)
    table.clear(Runtime.QuestCatalogByName)
    table.clear(Runtime.QuestToNPCs)

    local questsRoot = questModulesRoot()
    if questsRoot then
        for _, object in ipairs(questsRoot:GetDescendants()) do
            if object:IsA("ModuleScript") then
                local entry = {
                    Name = object.Name,
                    Path = relativePath(questsRoot, object),
                    Module = object,
                }

                table.insert(Runtime.QuestCatalog, entry)

                local key = lower(object.Name)
                Runtime.QuestCatalogByName[key] = Runtime.QuestCatalogByName[key] or {}
                table.insert(Runtime.QuestCatalogByName[key], entry)
            end
        end

        table.sort(Runtime.QuestCatalog, function(a, b)
            return lower(a.Path) < lower(b.Path)
        end)
    end

    local root = dialogueRoot()
    if root then
        for _, object in ipairs(root:GetDescendants()) do
            local questName

            if object:IsA("StringValue")
                and object.Name == "QuestName"
                and object.Value ~= "" then
                questName = object.Value
            end

            local questNode = object:GetAttribute("QuestNode")
            if type(questNode) == "string" and questNode ~= "" then
                questName = questName or questNode
            end

            if object:IsA("TextLabel") and object.Name == "QuestLabel" then
                local text = normalize(object.Text)
                if text ~= "" then
                    questName = questName or text
                end
            end

            if questName then
                local npc = findDialogueNpcRoot(object)

                if npc then
                    local key = lower(questName)
                    Runtime.QuestToNPCs[key] = Runtime.QuestToNPCs[key] or {}

                    local exists = false
                    for _, current in ipairs(Runtime.QuestToNPCs[key]) do
                        if current == npc then
                            exists = true
                            break
                        end
                    end

                    if not exists then
                        table.insert(Runtime.QuestToNPCs[key], npc)
                    end
                end
            end
        end
    end
end

function QuestCatalogService.GetNames()
    local names = {}

    for _, entry in ipairs(Runtime.QuestCatalog) do
        table.insert(names, entry.Path)
    end

    if #names == 0 then
        table.insert(names, "Quest catalog unavailable")
    end

    return names
end

local function liveDialogueNpcs()
    local result, seen = {}, {}
    for npc in pairs(Runtime.DialogueNPCs) do
        if npc and npc.Parent and not seen[npc] then
            seen[npc] = true
            table.insert(result, npc)
        end
    end
    if #result == 0 then
        local root = dialogueRoot()
        if root then
            for _, island in ipairs(root:GetChildren()) do
                for _, object in ipairs(island:GetChildren()) do
                    if object:IsA("Model") and not seen[object] then
                        seen[object] = true
                        table.insert(result, object)
                    end
                end
            end
        end
    end
    return result
end

local function dialogueNpcQuestScore(npc, questName)
    if not npc or not npc.Parent then return 0 end
    local wanted = lower(questName)
    if wanted == "" then return 0 end
    local score = 0
    for _, object in ipairs(npc:GetDescendants()) do
        if object:IsA("TextLabel") and object.Name == "QuestLabel" then
            local value = lower(object.Text)
            if value == wanted then score = math.max(score, 140)
            elseif value:find(wanted, 1, true) or wanted:find(value, 1, true) then score = math.max(score, 100) end
        elseif object:IsA("StringValue") and object.Name == "QuestName" then
            local value = lower(object.Value)
            if value == wanted then score = math.max(score, 95)
            elseif value:find(wanted, 1, true) or wanted:find(value, 1, true) then score = math.max(score, 70) end
        end
    end
    return score
end

function QuestCatalogService.FindQuestGiver(questName, preferredNpc)
    local ownRoot = rootPart()

    if preferredNpc and preferredNpc ~= "" and TargetService then
        local direct = TargetService.FindNamedDialogueNPC(preferredNpc)
            or TargetService.FindNamedNPC(preferredNpc)
        if direct then return direct end
    end

    local best, bestScore, bestDistance = nil, -math.huge, math.huge
    for _, npc in ipairs(Runtime.QuestToNPCs[lower(questName)] or {}) do
        if npc and npc.Parent then
            local part = objectRoot(npc)
            if part then
                local score = dialogueNpcQuestScore(npc, questName)
                local distance = ownRoot and (ownRoot.Position - part.Position).Magnitude or 0
                if score > bestScore or (score == bestScore and distance < bestDistance) then
                    best, bestScore, bestDistance = npc, score, distance
                end
            end
        end
    end
    if best then return best end

    for _, npc in ipairs(liveDialogueNpcs()) do
        local part = objectRoot(npc)
        local score = dialogueNpcQuestScore(npc, questName)
        if part and score > 0 then
            local distance = ownRoot and (ownRoot.Position - part.Position).Magnitude or 0
            if score > bestScore or (score == bestScore and distance < bestDistance) then
                best, bestScore, bestDistance = npc, score, distance
            end
        end
    end
    return best
end

QuestCatalogService.Build()

task.delay(1.5, function()
    if Core.Running then QuestCatalogService.Build() end
end)

task.delay(4.0, function()
    if Core.Running then QuestCatalogService.Build() end
end)

-- ============================================================
-- Hotbar service
-- ============================================================

HotbarService = {
    Slots = {},
    TitleToSlot = {},
    Hotbar = nil,
}

local KEY_BY_SLOT = {
    ["1"] = Enum.KeyCode.One,
    ["2"] = Enum.KeyCode.Two,
    ["3"] = Enum.KeyCode.Three,
    ["4"] = Enum.KeyCode.Four,
    ["5"] = Enum.KeyCode.Five,
    ["6"] = Enum.KeyCode.Six,
    ["7"] = Enum.KeyCode.Seven,
    ["8"] = Enum.KeyCode.Eight,
    ["9"] = Enum.KeyCode.Nine,
    ["0"] = Enum.KeyCode.Zero,
}

local UTILITY_WORDS = {
    "key",
    "fragment",
    "rock",
    "ink",
    "pickaxe",
    "bait",
    "food",
    "map",
    "pouch",
    "shovel",
    "watering",
    "fertilizer",
    "seed",
    "ore",
}

local COMBAT_WORDS = {
    "sword",
    "slash",
    "punch",
    "gun",
    "shot",
    "cannon",
    "fist",
    "claw",
    "axe",
    "kick",
    "sulong",
    "bomb",
    "flame",
    "dark",
}

local function findHotbar()
    if HotbarService.Hotbar and HotbarService.Hotbar.Parent then
        return HotbarService.Hotbar
    end

    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local backpack = playerGui and playerGui:FindFirstChild("Backpack")
    if not backpack then
        return nil
    end

    for _, object in ipairs(backpack:GetDescendants()) do
        if object.Name == "Hotbar" and object:IsA("GuiObject") then
            HotbarService.Hotbar = object
            return object
        end
    end

    return nil
end

local function isUtilityTitle(title)
    local value = lower(title)

    for _, word in ipairs(UTILITY_WORDS) do
        if value:find(word, 1, true) then
            return true
        end
    end

    return false
end

function HotbarService.Refresh()
    table.clear(HotbarService.Slots)
    table.clear(HotbarService.TitleToSlot)

    local hotbar = findHotbar()
    if not hotbar then
        return
    end

    for _, slot in ipairs(hotbar:GetChildren()) do
        local key = KEY_BY_SLOT[slot.Name]

        if key then
            local toolFrame = slot:FindFirstChild("ToolFrame")
            local title = toolFrame and toolFrame:FindFirstChild("Title", true)

            if title and title:IsA("TextLabel") then
                local name = normalize(title.Text)

                if name ~= "" then
                    local data = {
                        Slot = slot.Name,
                        Key = key,
                        Title = name,
                        Frame = slot,
                        ToolFrame = toolFrame,
                        Cooldown = toolFrame and toolFrame:FindFirstChild("Cooldown", true),
                        EXP = toolFrame and toolFrame:FindFirstChild("EXP", true),
                        Upgradable = toolFrame and toolFrame:FindFirstChild("Upgradable", true),
                    }

                    HotbarService.Slots[slot.Name] = data
                    HotbarService.TitleToSlot[name] = data
                end
            end
        end
    end
end

function HotbarService.IsCombat(data)
    if not data or isUtilityTitle(data.Title) then
        return false
    end

    local value = lower(data.Title)

    for _, word in ipairs(COMBAT_WORDS) do
        if value:find(word, 1, true) then
            return true
        end
    end

    -- Unknown non-utility hotbar slots can still be skills.
    return true
end

function HotbarService.IsReady(data)
    if not data then
        return false
    end

    local cooldown = data.Cooldown
    if cooldown and cooldown:IsA("GuiObject") then
        return cooldown.Visible == false
    end

    return true
end

function HotbarService.Press(data)
    return data and pressKey(data.Key, 0.03) or false
end

function HotbarService.RequiresHold(data)
    if not data or not data.ToolFrame then
        return false
    end

    for _, object in ipairs(data.ToolFrame:GetDescendants()) do
        if object:IsA("TextLabel") then
            local value = lower(object.Text)
            if value == "hold" or value:find("hold", 1, true) then
                return true
            end
        end
    end

    return false
end


function HotbarService.AutoCombatSlot()
    local best
    local bestScore = -math.huge

    for _, data in pairs(HotbarService.Slots) do
        if HotbarService.IsCombat(data) then
            local score = 10
            local value = lower(data.Title)

            for index, word in ipairs(COMBAT_WORDS) do
                if value:find(word, 1, true) then
                    score = score + 100 - index
                    break
                end
            end

            local slotNumber = tonumber(data.Slot)
            if slotNumber then
                score = score - slotNumber * 0.01
            end

            if score > bestScore then
                best = data
                bestScore = score
            end
        end
    end

    return best
end

function HotbarService.ResolveConfigured()
    HotbarService.Refresh()
    return HotbarService.AutoCombatSlot()
end

function HotbarService.GetWeaponOptions()
    HotbarService.Refresh()

    local result = {"Auto"}
    local rows = {}

    for _, data in pairs(HotbarService.Slots) do
        if HotbarService.IsCombat(data) then
            table.insert(rows, data)
        end
    end

    table.sort(rows, function(a, b)
        return (tonumber(a.Slot) or 99) < (tonumber(b.Slot) or 99)
    end)

    for _, data in ipairs(rows) do
        table.insert(result, data.Title)
    end

    return result
end

function HotbarService.FindByText(text)
    local wanted = lower(text)
    if wanted == "" then
        return nil
    end

    HotbarService.Refresh()

    local best
    local bestScore = -math.huge

    for _, data in pairs(HotbarService.Slots) do
        local value = lower(data.Title)
        local score = 0

        if value == wanted then
            score = 160
        elseif value:find(wanted, 1, true)
            or wanted:find(value, 1, true) then
            score = 110
        end

        if score > bestScore then
            best = data
            bestScore = score
        end
    end

    return best
end

function HotbarService.GetSnapshot()
    HotbarService.Refresh()

    local rows = {}
    for slot, data in pairs(HotbarService.Slots) do
        table.insert(rows, slot .. ": " .. data.Title)
    end

    table.sort(rows)
    return #rows > 0 and table.concat(rows, " | ") or "Hotbar unavailable"
end

-- ============================================================
-- Target service
-- ============================================================

TargetService = {}

local function isPlayerEntity(model)
    return model and (
        model:GetAttribute("PlayerCharacter") == true
        or Players:FindFirstChild(model.Name) ~= nil
    )
end

function TargetService.GetLifeState(model)
    if not model or not model.Parent or not model:IsA("Model") or isPlayerEntity(model) then
        return "INVALID"
    end

    for _, name in ipairs({"Dead", "Died", "IsDead", "Death", "Respawning"}) do
        if model:GetAttribute(name) == true then
            return "DEAD"
        end
    end

    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum then
        return "INVALID"
    end

    if hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead then
        return "DEAD"
    end

    if model:GetAttribute("Ragdolled") == true
        and model:GetAttribute("Dead") == true then
        return "CORPSE"
    end

    return objectRoot(model) and "ALIVE" or "INVALID"
end

function TargetService.IsAliveNPC(model)
    return TargetService.GetLifeState(model) == "ALIVE"
end

function TargetService.IsBoss(model)
    if not TargetService.IsAliveNPC(model) then
        return false
    end

    if model:GetAttribute("BossCombat") == true
        or model:GetAttribute("WorldBoss") == true
        or model:GetAttribute("Boss") == true then
        return true
    end

    local value = lower(
        model.Name
        .. " "
        .. tostring(model:GetAttribute("NPCType") or "")
        .. " "
        .. tostring(model:GetAttribute("NPCName") or "")
    )

    return value:find("boss", 1, true) ~= nil
end

function TargetService.IsDialogueNPC(model)
    if not model then
        return false
    end

    local interaction = lower(model:GetAttribute("Interaction") or "")
    local npcType = lower(model:GetAttribute("NPCType") or "")

    if interaction:find("dialogue", 1, true) then
        return true
    end

    if npcType == "civilian" and model:GetAttribute("Combat") ~= true then
        return true
    end

    local root = dialogueRoot()
    return root and model:IsDescendantOf(root) or false
end

function TargetService.IsHostile(model)
    if not TargetService.IsAliveNPC(model)
        or TargetService.IsDialogueNPC(model) then
        return false
    end

    if TargetService.IsBoss(model) then
        return true
    end

    if model:GetAttribute("Combat") == true
        or model:GetAttribute("NPCCombat") == true then
        return true
    end

    local party = lower(
        model:GetAttribute("Party")
        or model:GetAttribute("DefaultParty")
        or ""
    )

    return party:find("enemy", 1, true) ~= nil
        or party:find("corrupt", 1, true) ~= nil
        or party:find("hostile", 1, true) ~= nil
end

local function npcMatches(model, targetName)
    if not model or not targetName or targetName == "" then
        return false
    end

    local wanted = lower(targetName)
    local candidates = {
        model.Name,
        stripRuntimeSuffix(model.Name),
        model:GetAttribute("NPCName"),
        model:GetAttribute("NPCType"),
        model:GetAttribute("OriginalName"),
    }

    for _, candidate in ipairs(candidates) do
        if candidate then
            local value = lower(candidate)

            if value == wanted
                or value:find(wanted, 1, true)
                or wanted:find(value, 1, true) then
                return true
            end
        end
    end

    return false
end

function TargetService.IsFarmMob(model, wanted)
    if not TargetService.IsAliveNPC(model)
        or TargetService.IsDialogueNPC(model) then
        return false
    end

    if wanted == "Boss Only" then
        return TargetService.IsBoss(model)
    elseif wanted == "Nearest Hostile" then
        return TargetService.IsHostile(model)
    elseif wanted == "Any Hostile" then
        return TargetService.IsHostile(model)
    elseif wanted and wanted ~= "" then
        if not npcMatches(model, wanted) then
            return false
        end

        -- Exact quest-name target can be accepted even if party metadata is incomplete,
        -- but never a dialogue-only NPC.
        return TargetService.IsHostile(model)
            or model:FindFirstChildOfClass("Humanoid") ~= nil
    end

    return false
end

function TargetService.Find(wanted)
    local best
    local bestDistance

    for model in pairs(Runtime.Entities) do
        if model
            and model.Parent
            and TargetService.IsFarmMob(model, wanted) then

            local distance = distanceTo(model)
            if not bestDistance or distance < bestDistance then
                best = model
                bestDistance = distance
            end
        end
    end

    return best
end

function TargetService.FindNamedNPC(name)
    local best
    local bestDistance

    for model in pairs(Runtime.Entities) do
        if model and model.Parent and npcMatches(model, name) then
            local distance = distanceTo(model)
            if not bestDistance or distance < bestDistance then
                best = model
                bestDistance = distance
            end
        end
    end

    return best
end

function TargetService.FindNamedDialogueNPC(name)
    if not name or normalize(name) == "" then return nil end
    local wanted = lower(stripRuntimeSuffix(name))
    local ownRoot = rootPart()
    local best, bestScore, bestDistance = nil, -math.huge, math.huge

    for _, model in ipairs(liveDialogueNpcs()) do
        if model and model.Parent then
            local cleanName = lower(stripRuntimeSuffix(model.Name))
            local rawName = lower(model.Name)
            local npcName = lower(model:GetAttribute("NPCName") or "")
            local score = 0
            if cleanName == wanted or npcName == wanted then score = 160
            elseif rawName:find(wanted,1,true) or cleanName:find(wanted,1,true) or npcName:find(wanted,1,true) then score = 120 end
            if score > 0 then
                local part = objectRoot(model)
                local distance = part and ownRoot and (ownRoot.Position - part.Position).Magnitude or math.huge
                if score > bestScore or (score == bestScore and distance < bestDistance) then
                    best, bestScore, bestDistance = model, score, distance
                end
            end
        end
    end
    return best
end

function TargetService.GetMobOptions()
    local set = {
        ["Nearest Hostile"] = true,
        ["Boss Only"] = true,
    }

    local folder = entitiesFolder()
    if folder then
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model")
                and not isPlayerEntity(model)
                and not TargetService.IsDialogueNPC(model) then

                local name = tostring(
                    model:GetAttribute("NPCType")
                    or model:GetAttribute("NPCName")
                    or stripRuntimeSuffix(model.Name)
                )

                if name ~= "" then
                    set[name] = true
                end
            end
        end
    end

    local result = {}
    for name in pairs(set) do
        table.insert(result, name)
    end

    table.sort(result)
    return result
end

-- ============================================================
-- Platform transport
-- ============================================================

MotionController = {}

local MOTION_PRIORITY = {
    Manual = 120,
    Dialogue = 110,
    Mining = 100,
    Fishing = 95,
    Farming = 90,
    Quest = 80,
    Combat = 70,
    Loot = 40,
    Legacy = 20,
}

Runtime.Motion = {
    Owner = nil,
    Priority = -math.huge,
    Goal = nil,
    FacePosition = nil,
    Active = false,
    Hold = false,
    HoldGoal = nil,
    Speed = Config.PlatformSpeed,
    ArrivalDistance = Config.PlatformArrivalDistance,
    UpdatedAt = 0,
    AutoRotate = nil,
    Kind = nil,
    Tween = nil,
}

local function motionYawCFrame(position, facePosition)
    if facePosition then
        local flat = Vector3.new(
            facePosition.X - position.X,
            0,
            facePosition.Z - position.Z
        )

        if flat.Magnitude > 0.01 then
            return CFrame.lookAt(
                position,
                position + flat.Unit
            )
        end
    end

    return CFrame.new(position)
end

local function restoreMotionHumanoid()
    local hum = humanoid()

    if hum and Runtime.Motion.AutoRotate ~= nil then
        pcall(function()
            hum.AutoRotate = Runtime.Motion.AutoRotate
        end)
    end

    Runtime.Motion.AutoRotate = nil
end

function MotionController.Release(owner, force)
    local motion = Runtime.Motion

    if not motion.Owner then
        return true
    end

    if not force
        and owner
        and motion.Owner ~= owner then
        return false
    end

    if motion.Tween then
        pcall(function()
            motion.Tween:Cancel()
        end)
        motion.Tween = nil
    end

    local root = rootPart()
    if root then
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
    end

    restoreMotionHumanoid()

    motion.Owner = nil
    motion.Priority = -math.huge
    motion.Goal = nil
    motion.FacePosition = nil
    motion.Active = false
    motion.Hold = false
    motion.HoldGoal = nil
    motion.UpdatedAt = 0
    motion.Kind = nil

    return true
end

function MotionController.Request(owner, goal, options)
    if not goal then
        return false, "missing goal"
    end

    owner = owner or "Legacy"
    options = options or {}

    local motion = Runtime.Motion
    local priority = options.Priority
        or MOTION_PRIORITY[owner]
        or MOTION_PRIORITY.Legacy

    if motion.Owner
        and motion.Owner ~= owner
        and priority < motion.Priority then
        return false, "busy:" .. tostring(motion.Owner)
    end

    if motion.Owner and motion.Owner ~= owner then
        MotionController.Release(motion.Owner, true)
    end

    local root = rootPart()
    if not root then
        return false, "missing root"
    end

    if motion.Owner ~= owner then
        local hum = humanoid()
        if hum and motion.AutoRotate == nil then
            motion.AutoRotate = hum.AutoRotate
            hum.AutoRotate = false
        end
    end

    local retargetDistance = tonumber(options.RetargetDistance)
        or Config.PlatformRetargetDistance

    if motion.Owner == owner
        and motion.Goal
        and motion.Active
        and (
            motion.Goal.Position
            - goal.Position
        ).Magnitude < retargetDistance then

        motion.UpdatedAt = os.clock()
        motion.FacePosition = options.FacePosition or motion.FacePosition
        motion.Hold = options.Hold == true
        motion.Kind = options.Kind or motion.Kind
        return true, "tracking"
    end

    motion.Owner = owner
    motion.Priority = priority
    motion.Goal = goal
    motion.FacePosition = options.FacePosition or goal.Position
    motion.Active = true
    motion.Hold = options.Hold == true
    motion.HoldGoal = nil
    motion.Speed = tonumber(options.Speed) or Config.TweenSpeed or Config.PlatformSpeed
    motion.ArrivalDistance = tonumber(options.ArrivalDistance)
        or Config.PlatformArrivalDistance
    motion.UpdatedAt = os.clock()
    motion.Kind = options.Kind or owner

    if motion.Tween then
        pcall(function()
            motion.Tween:Cancel()
        end)
        motion.Tween = nil
    end

    local targetCFrame = motionYawCFrame(
        goal.Position,
        motion.FacePosition or goal.Position
    )
    local distance = (root.Position - goal.Position).Magnitude
    local duration = math.max(0.05, distance / math.max(30, motion.Speed))

    local okTween, tween = pcall(function()
        return TweenService:Create(
            root,
            TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
            {CFrame = targetCFrame}
        )
    end)

    if okTween and tween then
        motion.Tween = tween
        tween:Play()
    end

    return true, "started"
end

function MotionController.IsOwnedBy(owner)
    return Runtime.Motion.Owner == owner
end

function MotionController.IsActive()
    return Runtime.Motion.Active == true
end

function MotionController.IsHolding()
    return Runtime.Motion.Hold == true
        and Runtime.Motion.HoldGoal ~= nil
end

function MotionController.Step(deltaTime)
    local motion = Runtime.Motion

    if not motion.Owner then
        return
    end

    local root = rootPart()
    if not root then
        MotionController.Release(motion.Owner, true)
        return
    end

    if motion.Active and motion.Goal then
        local goal = motion.Goal
        local distance = (goal.Position - root.Position).Magnitude

        if distance <= motion.ArrivalDistance then
            if motion.Tween then
                pcall(function()
                    motion.Tween:Cancel()
                end)
                motion.Tween = nil
            end

            pcall(function()
                root.CFrame = motionYawCFrame(
                    goal.Position,
                    motion.FacePosition or goal.Position
                )
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end)

            motion.Active = false

            if motion.Hold then
                motion.HoldGoal = goal
                        return
            end

            local owner = motion.Owner
            MotionController.Release(owner, true)
            return
        end

        if not motion.Tween then
            local duration = math.max(0.05, distance / math.max(30, motion.Speed))
            local targetCFrame = motionYawCFrame(
                goal.Position,
                motion.FacePosition or goal.Position
            )
            local okTween, tween = pcall(function()
                return TweenService:Create(
                    root,
                    TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
                    {CFrame = targetCFrame}
                )
            end)
            if okTween and tween then
                motion.Tween = tween
                tween:Play()
            end
        end

        return
    end

    if motion.Hold and motion.HoldGoal then
        local drift = (
            root.Position
            - motion.HoldGoal.Position
        ).Magnitude

        -- Standing still should not mean CFrame spam every Heartbeat.
        -- Correct only meaningful drift.
        if drift > Config.FarmHoldCorrectionDistance then
            local delta = motion.HoldGoal.Position - root.Position
            local stepDistance = math.max(25, motion.Speed * 0.45)
                * math.max(0.001, deltaTime)

            local nextPosition = root.Position
                + delta.Unit * math.min(delta.Magnitude, stepDistance)

            local corrected = motionYawCFrame(
                nextPosition,
                motion.HoldGoal.Position
                    + motion.HoldGoal.LookVector
            )

            pcall(function()
                root.CFrame = corrected
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end)
        end
    end

end

connect(RunService.Heartbeat, function(deltaTime)
    if Core.Running then
        MotionController.Step(deltaTime)
    end
end)

-- Legacy movement API now delegates to the one motion owner.
PlatformTransport = {}

local function legacyMotionOwner()
    if Config.AutoMining
        or Runtime.ProgressLifeSkill == "Mining" then
        return "Mining"
    elseif Config.AutoFishing
        or Runtime.ProgressLifeSkill == "Fishing" then
        return "Fishing"
    elseif Config.AutoFarming
        or Runtime.ProgressLifeSkill == "Farming" then
        return "Farming"
    end

    return "Legacy"
end

function PlatformTransport.Ensure()
    return nil
end

function PlatformTransport.DestroyWeld()
    return
end

function PlatformTransport.Attach()
    return true
end

function PlatformTransport.Cancel(keepPlatform)
    local owner = legacyMotionOwner()
    MotionController.Release(owner, false)
end

function PlatformTransport.MoveToRootCFrame(rootGoal)
    return MotionController.Request(
        legacyMotionOwner(),
        rootGoal,
        {
            Kind = "legacy",
            FacePosition = rootGoal and rootGoal.Position,
        }
    )
end

function PlatformTransport.Step(deltaTime)
    return
end

function PlatformTransport.MoveAbove(object)
    local target = objectRoot(object)
    if not target then
        return false, "missing target"
    end

    local goal = motionYawCFrame(
        target.Position + Vector3.new(0, 6, 0),
        target.Position
    )

    return MotionController.Request(
        legacyMotionOwner(),
        goal,
        {
            Kind = "legacy",
            FacePosition = target.Position,
        }
    )
end

function PlatformTransport.MoveNear(object)
    local target = objectRoot(object)
    local root = rootPart()

    if not target or not root then
        return false, "missing target"
    end

    local away = Vector3.new(
        root.Position.X - target.Position.X,
        0,
        root.Position.Z - target.Position.Z
    )

    if away.Magnitude <= 0.05 then
        away = Vector3.new(0, 0, 1)
    else
        away = away.Unit
    end

    local position = target.Position
        + away * Config.PlatformBackDistance
        + Vector3.new(0, 0.4, 0)

    return MotionController.Request(
        legacyMotionOwner(),
        motionYawCFrame(position, target.Position),
        {
            Kind = "legacy",
            FacePosition = target.Position,
        }
    )
end

function PlatformTransport.SetFarmAnchorFrom(object)
    local target = objectRoot(object)
    if not target then
        return nil
    end

    Runtime.FarmAnchorCFrame = CFrame.new(
        target.Position + Vector3.new(0, 0.4, 0)
    )

    return Runtime.FarmAnchorCFrame
end

function PlatformTransport.MoveToFarmAnchor()
    if not Runtime.FarmAnchorCFrame then
        return false, "no anchor"
    end

    return MotionController.Request(
        "Combat",
        Runtime.FarmAnchorCFrame,
        {
            Kind = "combat",
            Hold = true,
        }
    )
end

-- ============================================================
-- Fixed mob-zone registry
-- ============================================================

MobZoneService = {
    ByMob = {},
    LastBuild = 0,
}

local function mobZoneRoot()
    local important = Workspace:FindFirstChild("AA IMPORTANT")
    return important and important:FindFirstChild("MobZones")
end

local function mobIdentity(model)
    if not model then
        return ""
    end

    return normalize(
        model:GetAttribute("NPCName")
        or model:GetAttribute("NPCType")
        or stripRuntimeSuffix(model.Name)
    )
end

function MobZoneService.Rebuild(force)
    local now = os.clock()
    if not force and now - MobZoneService.LastBuild < 4 then
        return
    end

    MobZoneService.LastBuild = now
    table.clear(MobZoneService.ByMob)

    local root = mobZoneRoot()
    if not root then
        return
    end

    for _, object in ipairs(root:GetDescendants()) do
        if object:IsA("BasePart") then
            local mob = object:GetAttribute("Mob")
            if type(mob) == "string" and normalize(mob) ~= "" then
                local key = lower(stripRuntimeSuffix(mob))
                MobZoneService.ByMob[key] = MobZoneService.ByMob[key] or {}
                table.insert(MobZoneService.ByMob[key], object)
            end
        end
    end
end

function MobZoneService.Find(mobName, hintPosition)
    if not mobName or normalize(mobName) == "" then
        return nil
    end

    MobZoneService.Rebuild(false)

    local rows = MobZoneService.ByMob[lower(stripRuntimeSuffix(mobName))]
    if not rows then
        MobZoneService.Rebuild(true)
        rows = MobZoneService.ByMob[lower(stripRuntimeSuffix(mobName))]
    end

    local best, bestDistance
    for _, part in ipairs(rows or {}) do
        if part and part.Parent
            and part:GetAttribute("Active") ~= false
            and part:GetAttribute("Spawned") ~= false then

            local distance = hintPosition and (part.Position - hintPosition).Magnitude or 0
            if not bestDistance or distance < bestDistance then
                best = part
                bestDistance = distance
            end
        end
    end

    return best
end

function MobZoneService.ResolveAnchor(wanted, rows)
    if not rows or #rows == 0 then
        return nil, nil, nil
    end

    local first = rows[1]
    local generic = wanted == "Nearest Hostile"
        or wanted == "Any Hostile"
        or wanted == "Boss Only"

    local mobName = generic and mobIdentity(first.Model) or normalize(wanted)
    local marker = MobZoneService.Find(mobName, first.Part.Position)

    if marker then
        local position = marker.Position + Vector3.new(0, Config.FarmAnchorHeight, 0)
        local face = marker.Position + marker.CFrame.LookVector
        local zone = marker:GetAttribute("Zone")
        local source = "MobZone" .. (zone and (":" .. tostring(zone)) or "")
        return motionYawCFrame(position, face), source, mobName
    end

    local position = first.Part.Position + Vector3.new(0, math.max(0.2, Config.FarmAnchorHeight), 0)
    return motionYawCFrame(position, first.Part.Position + first.Part.CFrame.LookVector), "CapturedSpawn", mobName
end

-- ============================================================
-- Mob gather
-- ============================================================

MobGatherService = {}

local function gatherRows(wanted)
    local root = rootPart()
    local rows = {}

    for model in pairs(Runtime.Entities) do
        if model
            and model.Parent
            and TargetService.IsFarmMob(model, wanted) then

            local part = objectRoot(model)
            if part then
                table.insert(rows, {
                    Model = model,
                    Part = part,
                    Distance = root
                        and (root.Position - part.Position).Magnitude
                        or 0,
                })
            end
        end
    end

    table.sort(rows, function(a, b)
        return a.Distance < b.Distance
    end)

    return rows
end

local function gatherAnchorFromRows(wanted, rows)
    return MobZoneService.ResolveAnchor(wanted, rows)
end

local function countGathered(wanted, anchor)
    if not anchor then
        return 0, 0
    end

    local total = 0
    local gathered = 0

    for model in pairs(Runtime.Entities) do
        if model
            and model.Parent
            and TargetService.IsFarmMob(model, wanted) then

            local part = objectRoot(model)
            if part then
                local distance = (
                    part.Position
                    - anchor.Position
                ).Magnitude

                if distance <= Config.GatherRadius then
                    total += 1

                    if distance <= Config.GatherStackRadius then
                        gathered += 1
                    end
                end
            end
        end
    end

    return gathered, total
end

function MobGatherService.Reset(reason)
    local gather = Runtime.Gather

    if MotionController.IsOwnedBy("Combat") then
        MotionController.Release("Combat", true)
    end

    gather.State = "IDLE"
    gather.Wanted = nil
    gather.Anchor = nil
    gather.AnchorSource = nil
    gather.AnchorMob = nil
    gather.Target = nil
    gather.InitialTargetDistance = 0
    gather.PhaseSince = 0
    gather.Failures = 0
    gather.Gathered = 0
    gather.Total = 0
    gather.Fallback = false
    gather.Cooldown = setmetatable({}, {__mode = "k"})

    if reason then
        Runtime.ProgressDetail = reason
    end
end

local function pickLureTarget(wanted, anchor)
    local root = rootPart()
    if not root or not anchor then
        return nil
    end

    local best
    local bestDistance
    local now = os.clock()

    for model in pairs(Runtime.Entities) do
        if model
            and model.Parent
            and TargetService.IsFarmMob(model, wanted)
            and (Runtime.Gather.Cooldown[model] or 0) <= now then

            local part = objectRoot(model)
            if part then
                local anchorDistance = (
                    part.Position
                    - anchor.Position
                ).Magnitude

                if anchorDistance > Config.GatherStackRadius
                    and anchorDistance <= Config.GatherRadius then

                    local playerDistance = (
                        root.Position
                        - part.Position
                    ).Magnitude

                    if not bestDistance
                        or playerDistance < bestDistance then
                        best = model
                        bestDistance = playerDistance
                    end
                end
            end
        end
    end

    return best
end

local function lureGoal(target, anchor)
    local part = objectRoot(target)
    if not part or not anchor then
        return nil
    end

    -- Stand on the anchor-facing side of the mob, tag with M1,
    -- then run back to the anchor so normal AI can follow.
    local towardAnchor = Vector3.new(
        anchor.Position.X - part.Position.X,
        0,
        anchor.Position.Z - part.Position.Z
    )

    if towardAnchor.Magnitude <= 0.05 then
        towardAnchor = Vector3.new(0, 0, 1)
    else
        towardAnchor = towardAnchor.Unit
    end

    local position = part.Position
        + towardAnchor * Config.GatherAggroDistance
        + Vector3.new(0, 0.25, 0)

    return motionYawCFrame(position, part.Position)
end

function MobGatherService.Step(wanted)
    local gather = Runtime.Gather

    if not Config.AutoGather
        or wanted == "Boss Only" then
        return true, "disabled"
    end

    if gather.Wanted ~= wanted then
        MobGatherService.Reset()
        gather = Runtime.Gather
        gather.Wanted = wanted
    end

    if gather.Fallback then
        return true, "fallback"
    end

    local rows = gatherRows(wanted)
    if #rows <= 1 then
        gather.State = "READY"
        gather.Gathered = #rows
        gather.Total = #rows
        return true, "single"
    end

    if not gather.Anchor then
        local anchor, source, anchorMob = gatherAnchorFromRows(wanted, rows)
        gather.Anchor = anchor
        gather.AnchorSource = source
        gather.AnchorMob = anchorMob
        gather.State = "PICK"
        gather.PhaseSince = os.clock()
    end

    if not gather.Anchor then
        gather.State = "WAIT_ZONE"
        return false, "anchor unavailable"
    end

    local gathered, total = countGathered(wanted, gather.Anchor)
    gather.Gathered = gathered
    gather.Total = total

    local desired = math.min(Config.GatherMax, total)

    if desired <= 1 or gathered >= desired then
        gather.State = "READY"
        return true, "ready"
    end

    if gather.Failures >= Config.GatherFailureLimit then
        gather.Fallback = true
        gather.State = "FALLBACK"
        MotionController.Release("Combat", true)
        return true, "follow not detected"
    end

    local now = os.clock()

    if gather.State == "IDLE"
        or gather.State == "PICK"
        or not gather.Target
        or not gather.Target.Parent then

        gather.Target = pickLureTarget(wanted, gather.Anchor)

        if not gather.Target then
            gather.State = "READY"
            return true, "no outside mob"
        end

        local targetPart = objectRoot(gather.Target)
        gather.InitialTargetDistance = targetPart
            and (targetPart.Position - gather.Anchor.Position).Magnitude
            or 0
        gather.State = "TAG_TRAVEL"
        gather.PhaseSince = now
    end

    local target = gather.Target

    if not TargetService.IsAliveNPC(target) then
        if target then
            gather.Cooldown[target] = now + 1.0
        end
        gather.Target = nil
        gather.State = "PICK"
        gather.PhaseSince = now
        return false, "target dead"
    end

    local targetPart = objectRoot(target)

    if not targetPart then
        gather.Target = nil
        gather.State = "PICK"
        return false, "lost target"
    end

    if gather.State == "TAG_TRAVEL" then
        local goal = lureGoal(target, gather.Anchor)
        if not goal then
            gather.Target = nil
            gather.State = "PICK"
            return false, "missing goal"
        end

        MotionController.Request(
            "Combat",
            goal,
            {
                Kind = "gather-tag",
                FacePosition = targetPart.Position,
                ArrivalDistance = 1.2,
            }
        )

        if distanceTo(target) <= Config.GatherAggroDistance + 1.4
            and TargetService.IsAliveNPC(target) then
            MotionController.Release("Combat", true)
            mouseClickCenter()
            gather.State = "TAGGED"
            gather.PhaseSince = now
        end

        return false, "tagging"
    end

    if gather.State == "TAGGED" then
        if now - gather.PhaseSince < 0.22 then
            return false, "tag settle"
        end

        gather.State = "RETURN"
        gather.PhaseSince = now
    end

    if gather.State == "RETURN" then
        MotionController.Request(
            "Combat",
            gather.Anchor,
            {
                Kind = "gather-return",
                FacePosition = targetPart.Position,
                ArrivalDistance = 1.5,
                Hold = true,
            }
        )

        local root = rootPart()
        if root
            and (
                root.Position
                - gather.Anchor.Position
            ).Magnitude <= 2.2 then

            gather.State = "WAIT_FOLLOW"
            gather.PhaseSince = now
        end

        return false, "returning"
    end

    if gather.State == "WAIT_FOLLOW" then
        if now - gather.PhaseSince < Config.GatherFollowWait then
            return false, "waiting follow"
        end

        local currentDistance = (
            targetPart.Position
            - gather.Anchor.Position
        ).Magnitude

        local progressed = currentDistance <= Config.GatherStackRadius
            or currentDistance <= math.max(
                0,
                gather.InitialTargetDistance - 3.0
            )

        if progressed then
            gather.Cooldown[target] = now + 1.2
        else
            gather.Failures += 1
            gather.Cooldown[target] = now + 2.0
        end

        gather.Target = nil
        gather.State = "PICK"
        gather.PhaseSince = now
        return false, progressed and "followed" or "no follow"
    end

    return false, gather.State
end

function MobGatherService.GetStatus()
    local gather = Runtime.Gather
    return string.format(
        "%s • %d/%d • %s • fail=%d%s",
        tostring(gather.State),
        tonumber(gather.Gathered) or 0,
        tonumber(gather.Total) or 0,
        tostring(gather.AnchorSource or "no-anchor"),
        tonumber(gather.Failures) or 0,
        gather.Fallback and " • fallback" or ""
    )
end

-- ============================================================
-- Small GUI caches
-- ============================================================

local function cacheClaimButton(object)
    if object
        and object:IsA("GuiButton")
        and lower(object.Name .. " " .. textOf(object)):find("claim", 1, true) then
        Runtime.ClaimButtons[object] = true
    end
end

local function cacheWorldMarker(object)
    if object
        and object:IsA("BillboardGui")
        and not isScriptTemplateDescendant(object) then
        Runtime.WorldMarkers[object] = true
    end
end

local function cacheGuiObject(object)
    cacheClaimButton(object)
    cacheWorldMarker(object)
end

local function initGuiCaches()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        return
    end

    local descendants = playerGui:GetDescendants()

    for index, object in ipairs(descendants) do
        cacheGuiObject(object)

        if index % 4000 == 0 then
            task.wait()
        end
    end

    connect(playerGui.DescendantAdded, cacheGuiObject)
    connect(playerGui.DescendantRemoving, function(object)
        Runtime.ClaimButtons[object] = nil
        Runtime.WorldMarkers[object] = nil
    end)
end

task.spawn(initGuiCaches)

-- ============================================================
-- Interaction service
-- ============================================================

InteractionService = {}

-- firePromptFn is resolved in the Nexomia compatibility bootstrap.

local function promptKind(prompt)
    local name = lower(prompt.Name)
    local path = lower(prompt:GetFullName())

    if name:find("fruit chest", 1, true) then
        return "FruitChest"
    elseif name:find("world boss chest", 1, true) then
        return "WorldBossChest"
    elseif name:find("chest", 1, true) then
        return "Chest"
    elseif name:find("dialogue", 1, true) then
        return "Dialogue"
    elseif name:find("ore", 1, true)
        or path:find(".ores.", 1, true) then
        return "Ore"
    elseif path:find(".crops.", 1, true)
        or path:find(".farmgear.", 1, true)
        or path:find(".pests.", 1, true) then
        return "Farm"
    elseif name:find("quest", 1, true)
        or name:find("mission", 1, true)
        or name == "trash bag" then
        return "QuestItem"
    elseif name == "pickup"
        or name == "money bag"
        or name == "steal"
        or name == "grab" then
        return "Pickup"
    end

    return "Other"
end

function InteractionService.FirePrompt(prompt)
    if not prompt
        or not prompt.Parent
        or not prompt:IsA("ProximityPrompt")
        or not prompt.Enabled then
        return false
    end

    if Compat.FirePrompt(prompt, prompt.HoldDuration) then
        return true
    end

    return pressKey(
        prompt.KeyboardKeyCode,
        math.max(0.06, (prompt.HoldDuration or 0) + 0.03)
    )
end

function InteractionService.FindPromptNear(object, desiredKind)
    local target = objectRoot(object)
    if not target then
        return nil
    end

    if object and object:IsA("Model") then
        for _, candidate in ipairs(object:GetDescendants()) do
            if candidate:IsA("ProximityPrompt")
                and candidate.Enabled
                and (
                    not desiredKind
                    or promptKind(candidate) == desiredKind
                ) then
                return candidate
            end
        end
    end

    local best
    local bestDistance

    for prompt in pairs(Runtime.Prompts) do
        if prompt and prompt.Parent and prompt.Enabled then
            local part = objectRoot(prompt)

            if part then
                local distance = (part.Position - target.Position).Magnitude
                local correctKind = not desiredKind
                    or promptKind(prompt) == desiredKind

                if correctKind
                    and distance <= 35
                    and (not bestDistance or distance < bestDistance) then

                    best = prompt
                    bestDistance = distance
                end
            end
        end
    end

    return best
end

function InteractionService.FindPromptByText(text, allowedKinds)
    local wanted = lower(text)
    local best
    local bestDistance

    for prompt in pairs(Runtime.Prompts) do
        if prompt and prompt.Parent and prompt.Enabled then
            local kind = promptKind(prompt)
            local kindAllowed = not allowedKinds or allowedKinds[kind]

            if kindAllowed then
                local model = prompt:FindFirstAncestorWhichIsA("Model")

                local blob = lower(table.concat({
                    prompt.Name,
                    tostring(prompt.ActionText or ""),
                    tostring(prompt.ObjectText or ""),
                    model and model.Name or "",
                }, " "))

                if blob:find(wanted, 1, true) then
                    local distance = distanceTo(prompt)

                    if not bestDistance or distance < bestDistance then
                        best = prompt
                        bestDistance = distance
                    end
                end
            end
        end
    end

    return best
end

local function dialogueUI()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    return playerGui and playerGui:FindFirstChild("DialogueUI")
end

local function dialogueHasVisibleResponse()
    local ui = dialogueUI()
    if not ui then
        return false
    end

    if ui:IsA("ScreenGui") and not ui.Enabled then
        return false
    end

    for _, object in ipairs(ui:GetDescendants()) do
        if object:IsA("ImageButton")
            and not isScriptTemplateDescendant(object)
            and isOnScreen(object) then
            return true
        end
    end

    return false
end

local function dialogueIsOpen(npc)
    if npc
        and npc.Parent
        and npc:GetAttribute("InConversation") == true then
        return true
    end

    return dialogueHasVisibleResponse()
end

local function scoreDialogueButton(button, questName)
    if not button
        or not button:IsA("ImageButton")
        or isScriptTemplateDescendant(button)
        or not isOnScreen(button) then
        return nil
    end

    local wanted = lower(questName)
    local parent = button.Parent
    local text = parent and textOf(parent) or ""
    local blob = lower((parent and parent.Name or "") .. " " .. text)

    local score = 1

    if wanted ~= "" and blob:find(wanted, 1, true) then
        score = score + 120
    end

    local questGlow = parent and parent:FindFirstChild("Quest Glow", true)
    if questGlow and questGlow:IsA("GuiObject") and questGlow.Visible then
        score = score + 90
    end

    for _, word in ipairs({
        "quest",
        "help",
        "training",
        "accept",
        "continue",
        "yes",
        "finish",
        "complete",
    }) do
        if blob:find(word, 1, true) then
            score = score + 20
        end
    end

    return score
end

function InteractionService.ProcessDialogue(questName, npc)
    if not Config.AutoDialogue or not dialogueIsOpen(npc) then
        return false
    end

    local ui = dialogueUI()
    local best
    local bestScore = -math.huge

    for _, object in ipairs(ui:GetDescendants()) do
        if object:IsA("ImageButton") then
            local score = scoreDialogueButton(object, questName or "")

            if score and score > bestScore then
                best = object
                bestScore = score
            end
        end
    end

    if best then
        return clickButton(best, false)
    end

    -- Fallback for games that temporarily reuse/reparent the NodeFrame template.
    for _, object in ipairs(ui:GetDescendants()) do
        if object:IsA("ImageButton") and isOnScreen(object) then
            local parent = object.Parent
            local blob = lower(
                (parent and parent.Name or "")
                .. " "
                .. (parent and textOf(parent) or "")
            )

            if blob:find("quest", 1, true)
                or blob:find("accept", 1, true)
                or (
                    questName
                    and questName ~= ""
                    and blob:find(lower(questName), 1, true)
                ) then
                return clickButton(object, false)
            end
        end
    end

    return false
end

function InteractionService.ProcessClaimButtons()
    if not Config.AutoClaim then
        return
    end

    for object in pairs(Runtime.ClaimButtons) do
        if object and object.Parent then
            if isGuiVisible(object) then
                clickButton(object, false)
                return
            end
        else
            Runtime.ClaimButtons[object] = nil
        end
    end
end

function InteractionService.InteractWithQuestNPC(object, questName)
    if not object then
        return false
    end

    local npc = object:IsA("Model")
        and object
        or object:FindFirstAncestorWhichIsA("Model")

    if dialogueIsOpen(npc) then
        return InteractionService.ProcessDialogue(questName, npc)
    end

    local prompt = object:IsA("ProximityPrompt")
        and object
        or InteractionService.FindPromptNear(object, "Dialogue")

    Runtime.FarmFSM.InteractionPrompt = prompt

    if not prompt then
        return false
    end

    local ownRoot = rootPart()
    local promptPart = objectRoot(prompt)
    if not ownRoot or not promptPart then
        return false
    end

    local maxDistance = tonumber(prompt.MaxActivationDistance) or 16
    if (ownRoot.Position - promptPart.Position).Magnitude > math.max(3, maxDistance - 1.5) then
        return false
    end

    local now = os.clock()
    if now - Runtime.FarmFSM.PromptAttemptAt < 0.80 then
        return false
    end

    Runtime.FarmFSM.PromptAttemptAt = now
    Runtime.FarmFSM.PromptAttemptCount += 1
    Runtime.LastInteraction = now

    -- Manual E is confirmed working in this game. Use the prompt's real key first.
    local inputOk = pressKey(
        prompt.KeyboardKeyCode,
        math.max(0.07, (prompt.HoldDuration or 0) + 0.04)
    )

    task.wait(0.10)
    if dialogueIsOpen(npc) then
        return true
    end

    -- Executor helper is only fallback because some custom prompts ignore it.
    if Compat.FirePrompt(prompt, prompt.HoldDuration) then
        task.wait(0.08)
    end

    return inputOk == true or dialogueIsOpen(npc)
end

-- ============================================================
-- Mastery / combat
-- ============================================================

CombatService = {}

local function setBlock(held)
    if Runtime.BlockHeld == held then
        return
    end

    Runtime.BlockHeld = held

    pcall(function()
        Compat.Key(held, Enum.KeyCode.F)
    end)
end

function CombatService.AimAt(model)
    -- Auto Farm v14 deliberately avoids rotating the character every
    -- scheduler tick because that caused stationary jitter.
    return false
end

function CombatService.AttackStep()
    if not Config.AutoAttack then
        return false
    end

    local now = os.clock()
    local minimumDelay =
        1 / math.max(1, Config.AttackRate)

    if now - Runtime.LastAttack < minimumDelay then
        return false
    end

    Runtime.LastAttack = now

    -- Generic normal attack only.
    -- No 1/2/3/4/5/6/7 hotbar skill input in this route.
    return mouseClickCenter()
end

function CombatService.BlockStep()
    setBlock(false)
    return false
end

-- ============================================================
-- Stats service
-- ============================================================

StatsService = {}

local STAT_NAMES = {
    "Health",
    "Strength",
    "Energy",
    "Willpower",
    "Agility",
    "Precision",
}

local STAT_WEIGHTS = {
    ["Balanced"] = {
        Health = 1,
        Strength = 1,
        Energy = 1,
        Willpower = 1,
        Agility = 1,
        Precision = 1,
    },
    ["Strength"] = {
        Health = 1.4,
        Strength = 4.5,
        Energy = 1.3,
        Willpower = 1.0,
        Agility = 1.0,
        Precision = 0.1,
    },
    ["Precision"] = {
        Health = 1.4,
        Strength = 0.1,
        Energy = 1.3,
        Willpower = 1.0,
        Agility = 1.0,
        Precision = 4.5,
    },
    ["Tank"] = {
        Health = 5.0,
        Strength = 0.8,
        Energy = 1.3,
        Willpower = 2.3,
        Agility = 0.8,
        Precision = 0.8,
    },
    ["Mobility"] = {
        Health = 1.4,
        Strength = 1.0,
        Energy = 2.0,
        Willpower = 1.0,
        Agility = 4.0,
        Precision = 1.0,
    },
    ["Haki"] = {
        Health = 1.5,
        Strength = 1.0,
        Energy = 1.4,
        Willpower = 4.5,
        Agility = 1.0,
        Precision = 1.0,
    },
}

local function radarFrame()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local menu = playerGui and playerGui:FindFirstChild("Menu")
    local container = menu and menu:FindFirstChild("ContainerFrame")
    local right = container and container:FindFirstChild("Right")
    return right and right:FindFirstChild("Radar")
end

function StatsService.GetStatPoints()
    local radar = radarFrame()
    local statpoint = radar and radar:FindFirstChild("StatpointText")
    local label = statpoint and statpoint:FindFirstChild("StatpointText")

    if label and label:IsA("TextLabel") then
        return tonumber(label.Text:match("(%d+)")) or 0
    end

    return 0
end

function StatsService.GetValues()
    local radar = radarFrame()
    local statsFolder = radar and radar:FindFirstChild("Stats")
    local values = {}

    for _, name in ipairs(STAT_NAMES) do
        local value = statsFolder and statsFolder:FindFirstChild(name)

        if value and (value:IsA("IntValue") or value:IsA("NumberValue")) then
            values[name] = tonumber(value.Value) or 0
        else
            local label = radar
                and radar:FindFirstChild(name)
                and radar[name]:FindFirstChild("Number")

            values[name] = label
                and tonumber((label.Text or ""):match("(%d+)"))
                or 0
        end
    end

    return values
end

local function autoWeaponBuild()
    local selected = HotbarService.ResolveConfigured()

    local blob = lower(
        tostring(selected and selected.Title or "")
        .. " "
        .. table.concat(PlayerState.GetWeaponTypes(), " ")
        .. " "
        .. PlayerState.GetFruit()
    )

    if blob:find("gun", 1, true)
        or blob:find("cannon", 1, true)
        or blob:find("precision", 1, true)
        or blob:find("rifle", 1, true)
        or blob:find("shot", 1, true) then
        return "Precision"
    end

    return "Strength"
end

function StatsService.GetBuild()
    local build = Config.StatBuild

    if build == "Auto" then
        return autoWeaponBuild()
    end

    if STAT_WEIGHTS[build] then
        return build
    end

    return "Balanced"
end

function StatsService.ChooseStat()
    local build = StatsService.GetBuild()
    local weights = STAT_WEIGHTS[build] or STAT_WEIGHTS.Balanced
    local values = StatsService.GetValues()

    local totalWeight = 0
    local totalValue = 0

    for _, name in ipairs(STAT_NAMES) do
        totalWeight = totalWeight + weights[name] or 0
        totalValue = totalValue + values[name] or 0
    end

    local best
    local bestDeficit = -math.huge

    for _, name in ipairs(STAT_NAMES) do
        local weight = weights[name] or 0
        local target = totalWeight > 0
            and ((totalValue + 1) * weight / totalWeight)
            or 0

        local deficit = target - (values[name] or 0)

        if deficit > bestDeficit then
            best = name
            bestDeficit = deficit
        end
    end

    return best
end

function StatsService.SpendOne()
    if not Config.AutoStats then
        Runtime.StatsSpendStatus = "Disabled"
        return false
    end

    local now = os.clock()
    local backoff = math.min(1.5, (Runtime.StatsSpendFailures or 0) * 0.2)
    if now - Runtime.LastStatsSpend < Config.StatSpendInterval + backoff then
        return false
    end

    local before = StatsService.GetStatPoints()
    if before <= 0 then
        Runtime.StatsSpendStatus = "No points"
        return false
    end

    local stat = StatsService.ChooseStat()
    local radar = radarFrame()
    local frame = radar and radar:FindFirstChild(stat or "")
    local button = frame and frame:FindFirstChild("ImageButton")

    if not button or not button:IsA("ImageButton") then
        Runtime.StatsSpendFailures += 1
        Runtime.StatsSpendStatus = "Radar button unavailable"
        Runtime.LastStatsSpend = now
        return false
    end

    Runtime.LastStatsSpend = now
    local clicked = clickButtonReliable(button)
    if not clicked then
        Runtime.StatsSpendFailures += 1
        Runtime.StatsSpendStatus = "Input failed: " .. tostring(stat)
        return false
    end

    Runtime.StatsSpendStatus = "Pending: " .. tostring(stat)
    task.delay(0.22, function()
        if not Core.Running then
            return
        end

        local after = StatsService.GetStatPoints()
        if after < before then
            Runtime.StatsSpendFailures = 0
            Runtime.StatsSpendStatus = "Spent: " .. tostring(stat)
        else
            Runtime.StatsSpendFailures += 1
            Runtime.StatsSpendStatus = "No server confirmation: " .. tostring(stat)
        end
    end)

    return true
end

function StatsService.GetSnapshot()
    local values = StatsService.GetValues()
    local rows = {
        "Points: " .. StatsService.GetStatPoints(),
        "Build: " .. StatsService.GetBuild(),
        "Status: " .. tostring(Runtime.StatsSpendStatus),
    }

    for _, name in ipairs(STAT_NAMES) do
        table.insert(rows, name .. ": " .. tostring(values[name] or 0))
    end

    return table.concat(rows, "\n")
end

-- ============================================================
-- Fishing service + QTE
-- ============================================================

FishingService = {}

local ROD_NAMES = {
    "Wooden Rod",
    "Carbon Rod",
    "Fiberglass Rod",
    "Silverline Rod",
    "Deep-Sea Rod",
    "Terry's Trusted Rod",
    "Celestial Rod",
}

local function fishInventory()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    return playerGui and playerGui:FindFirstChild("FishInventory")
end

local function fishingGui()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    return playerGui and playerGui:FindFirstChild("Fishing")
end

local function qteScreen()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    return playerGui and playerGui:FindFirstChild("QuickTimeEvents")
end

local function setFishingState(state, reason)
    if Runtime.FishingState ~= state then
        Runtime.FishingState = state
        Runtime.FishingStateSince = os.clock()
    end

    Runtime.FishingReason = reason or Runtime.FishingReason
end

local function setFishingMouseHeld(held)
    if Runtime.FishingMouseHeld == held then
        return
    end

    Runtime.FishingMouseHeld = held

    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)

    pcall(function()
        Compat.Mouse(viewport.X / 2, viewport.Y / 2, held)
    end)
end

local function releaseFishingKey()
    if not Runtime.FishingKeyHeld then
        return
    end

    local key = Runtime.FishingKeyHeld
    Runtime.FishingKeyHeld = nil

    pcall(function()
        Compat.Key(false, key)
    end)
end

local function holdFishingKey(key)
    if Runtime.FishingKeyHeld == key then
        return
    end

    releaseFishingKey()
    Runtime.FishingKeyHeld = key

    pcall(function()
        Compat.Key(true, key)
    end)
end

local function findHotbarRod()
    HotbarService.Refresh()

    for _, data in pairs(HotbarService.Slots) do
        local value = lower(data.Title)

        if value:find("rod", 1, true) then
            return {
                Name = data.Title,
                Source = "Hotbar",
                Hotbar = data,
            }
        end
    end

    return nil
end

local function findInventoryRod()
    local inventory = fishInventory()
    local root = inventory
        and inventory:FindFirstChild("Inventory")
        and inventory.Inventory:FindFirstChild("Inventory")

    local rodFrame = root and root:FindFirstChild("RodFrame")
    local inner = rodFrame and rodFrame:FindFirstChild("Frame")
    local itemName = inner and inner:FindFirstChild("ItemName")
    local equip = inner and inner:FindFirstChild("Equip")

    if itemName and itemName:IsA("TextLabel") then
        local name = normalize(itemName.Text):gsub("^%[", ""):gsub("%]$", "")

        return {
            Name = name,
            Source = "FishInventory",
            EquipButton = equip,
        }
    end

    return nil
end

function FishingService.FindRod()
    local now = os.clock()

    if Runtime.FishingRodCache
        and now - Runtime.FishingRodCacheAt < 1.0 then
        return Runtime.FishingRodCache
    end

    Runtime.FishingRodCacheAt = now
    Runtime.FishingRodCache = findHotbarRod() or findInventoryRod()
    return Runtime.FishingRodCache
end

function FishingService.GetBait()
    local now = os.clock()

    if Runtime.FishingBaitCache
        and now - Runtime.FishingBaitCacheAt < 1.5 then
        return Runtime.FishingBaitCache
    end

    Runtime.FishingBaitCacheAt = now

    local inventory = fishInventory()
    local root = inventory
        and inventory:FindFirstChild("Inventory")
        and inventory.Inventory:FindFirstChild("Inventory")

    local baitFrame = root and root:FindFirstChild("BaitFrame")
    local inner = baitFrame and baitFrame:FindFirstChild("Frame")
    local itemName = inner and inner:FindFirstChild("ItemName")
    local amount = inner and inner:FindFirstChild("Amount")

    if itemName and itemName:IsA("TextLabel") then
        local count = amount
            and amount:IsA("TextLabel")
            and tonumber((amount.Text or ""):match("(%d+)"))
            or 0

        Runtime.FishingBaitCache = {
            Name = normalize(itemName.Text):gsub("^%[", ""):gsub("%]$", ""),
            Amount = count or 0,
        }

        return Runtime.FishingBaitCache
    end

    Runtime.FishingBaitCache = nil
    return nil
end

local function largestAnchorTownWater()
    local islands = Workspace:FindFirstChild("Islands")
    local anchor = islands and islands:FindFirstChild("Anchor Town")
    if not anchor then
        return nil
    end

    local best
    local bestArea = 0

    for _, object in ipairs(anchor:GetDescendants()) do
        if object:IsA("BasePart") and object.Name == "Water" then
            local area = object.Size.X * object.Size.Z
            if area > bestArea then
                best = object
                bestArea = area
            end
        end
    end

    return best
end

local function shorePosition(water)
    local root = rootPart()
    if not water or not root then
        return nil
    end

    local localPos = water.CFrame:PointToObjectSpace(root.Position)
    local halfX = water.Size.X / 2
    local halfZ = water.Size.Z / 2
    local margin = 7

    local edges = {
        {math.abs(localPos.X + halfX), "left"},
        {math.abs(halfX - localPos.X), "right"},
        {math.abs(localPos.Z + halfZ), "back"},
        {math.abs(halfZ - localPos.Z), "front"},
    }

    table.sort(edges, function(a, b)
        return a[1] < b[1]
    end)

    local x = math.clamp(localPos.X, -halfX, halfX)
    local z = math.clamp(localPos.Z, -halfZ, halfZ)

    if edges[1][2] == "left" then
        x = -halfX - margin
    elseif edges[1][2] == "right" then
        x = halfX + margin
    elseif edges[1][2] == "back" then
        z = -halfZ - margin
    else
        z = halfZ + margin
    end

    local world = water.CFrame:PointToWorldSpace(Vector3.new(
        x,
        water.Size.Y / 2 + 3,
        z
    ))

    return CFrame.lookAt(world, water.Position)
end

function FishingService.ResolveSpot()
    if Config.FishingSpotMode == "Saved Position" then
        return Runtime.FishingSpotCFrame,
            Runtime.FishingSpotCFrame and "Saved position" or "No saved spot"
    elseif Config.FishingSpotMode == "Current Position" then
        local root = rootPart()
        return root and root.CFrame or nil,
            root and "Current position" or "Character unavailable"
    elseif Config.FishingSpotMode == "Anchor Town Pond" then
        local water = largestAnchorTownWater()
        return water and shorePosition(water) or nil,
            water and "Detected Anchor Town water edge" or "Anchor Town water not found"
    end

    return nil, "Unknown spot mode"
end

local function fishingReelActive()
    local gui = fishingGui()
    local main = gui and gui:FindFirstChild("Main")

    return gui
        and (not gui:IsA("ScreenGui") or gui.Enabled)
        and main
        and main.Visible,
        main
end

local function qteButtonByText(text)
    local screen = qteScreen()
    if not screen or not screen.Enabled then
        return nil
    end

    local client = screen:FindFirstChild("QTEClient")
    local events = client and client:FindFirstChild("Events")
    if not events then
        return nil
    end

    local wanted = lower(text)
    local button

    if wanted == "shake" then
        local gridshot = events:FindFirstChild("Gridshot")
        button = gridshot and gridshot:FindFirstChild("Button")
    elseif wanted == "click" then
        local spam = events:FindFirstChild("Spam Click")
        local frame = spam and spam:FindFirstChild("Frame")
        button = frame and frame:FindFirstChild("ImageButton")
    end

    if button and button:IsA("ImageButton") and isOnScreen(button) then
        return button
    end

    return nil
end

local function findEnabledBillboard(name)
    local screen = qteScreen()
    local client = screen and screen:FindFirstChild("QTEClient")
    local events = client and client:FindFirstChild("Events")
    local timed = events and events:FindFirstChild("Timed Release")
    local billboard = timed and timed:FindFirstChild(name)

    if billboard and billboard:IsA("BillboardGui") and billboard.Enabled then
        return billboard
    end

    return nil
end

function FishingService.HandleShake()
    if not Config.FishingAutoShake then
        return false
    end

    local button = qteButtonByText("SHAKE")
    if not button then
        return false
    end

    local now = os.clock()
    local position = button.AbsolutePosition

    local moved = not Runtime.FishingLastShakePosition
        or (Runtime.FishingLastShakePosition - position).Magnitude > 3

    if moved or now - Runtime.FishingLastShakeClick >= 0.12 then
        Runtime.FishingLastShakePosition = position
        Runtime.FishingLastShakeClick = now
        clickButton(button, false)
    end

    setFishingState("SHAKE", "Clicking SHAKE QTE")
    return true
end

function FishingService.HandleSpamClick()
    if not Config.FishingAutoSpamClick then
        return false
    end

    local button = qteButtonByText("CLICK")
    if not button then
        return false
    end

    local now = os.clock()
    if now - Runtime.FishingLastSpamClick >= 0.065 then
        Runtime.FishingLastSpamClick = now
        clickButton(button, false)
    end

    setFishingState("SPAM_CLICK", "Handling CLICK QTE")
    return true
end

function FishingService.HandleTimedRelease()
    if not Config.FishingAutoTimedRelease then
        Runtime.FishingTimedReleaseDone = false
        setFishingMouseHeld(false)
        return false
    end

    local bar = findEnabledBillboard("Fishing Bar")
    if not bar then
        Runtime.FishingTimedReleaseDone = false
        setFishingMouseHeld(false)
        return false
    end

    local frame = bar:FindFirstChild("Frame")
    local amount = frame and frame:FindFirstChild("Amount")

    if not amount or not amount:IsA("GuiObject") then
        return false
    end

    if Runtime.FishingTimedReleaseDone then
        setFishingMouseHeld(false)
        setFishingState("TIMED_RELEASE", "Release completed")
        return true
    end

    local fill = math.clamp(amount.Size.Y.Scale, 0, 1)

    if fill < Config.FishingReleaseThreshold then
        setFishingMouseHeld(true)
        setFishingState(
            "TIMED_RELEASE",
            string.format("Holding %.0f%%", fill * 100)
        )
    else
        setFishingMouseHeld(false)
        Runtime.FishingTimedReleaseDone = true
        setFishingState(
            "TIMED_RELEASE",
            string.format("Released %.0f%%", fill * 100)
        )
    end

    return true
end

function FishingService.HandleReel()
    local active, main = fishingReelActive()
    if not active or not main then
        releaseFishingKey()
        setFishingMouseHeld(false)
        Runtime.FishingReelCalibrated = false
        Runtime.FishingLastMoveCenter = nil
        return false
    end

    local move = main:FindFirstChild("Move")
    local fish = main:FindFirstChild("Fish")

    if not move or not fish
        or not move:IsA("GuiObject")
        or not fish:IsA("GuiObject") then
        return false
    end

    -- Confirmed from the dump:
    -- Move = the wide controllable catcher bar.
    -- Fish = the smaller target block that must stay inside Move.
    local moveLeft = move.AbsolutePosition.X
    local moveRight = moveLeft + move.AbsoluteSize.X
    local moveCenter = moveLeft + move.AbsoluteSize.X / 2

    local fishLeft = fish.AbsolutePosition.X
    local fishRight = fishLeft + fish.AbsoluteSize.X
    local fishCenter = fishLeft + fish.AbsoluteSize.X / 2

    local previousCenter = Runtime.FishingLastMoveCenter
    if previousCenter then
        Runtime.FishingLastMoveVelocity = moveCenter - previousCenter
    end
    Runtime.FishingLastMoveCenter = moveCenter

    -- Optional one-time calibration. We briefly hold and observe whether Move
    -- travels right or left. This avoids hard-coding the input direction.
    if Config.FishingAutoCalibrate and not Runtime.FishingReelCalibrated then
        local before = moveCenter
        setFishingMouseHeld(true)
        task.wait(0.075)

        local after = move.AbsolutePosition.X + move.AbsoluteSize.X / 2
        local delta = after - before

        if math.abs(delta) >= 0.5 then
            Runtime.FishingHoldDirection = delta > 0 and 1 or -1
        else
            Runtime.FishingHoldDirection = Config.FishingHoldMovesRight and 1 or -1
        end

        Runtime.FishingReelCalibrated = true
        Runtime.FishingLastMoveCenter = after
        setFishingMouseHeld(false)
        return true
    end

    local tolerance = Config.FishingReelTolerance
    local innerLeft = moveLeft + tolerance
    local innerRight = moveRight - tolerance

    -- Target control direction:
    -- +1 = Move should travel right, -1 = Move should travel left.
    local wantedDirection = 0

    if fishRight > innerRight then
        wantedDirection = 1
    elseif fishLeft < innerLeft then
        wantedDirection = -1
    else
        -- Fish is already contained. Counter the current bar velocity so it
        -- does not drift out of the target while we wait for the next frame.
        local velocity = Runtime.FishingLastMoveVelocity or 0
        if velocity > 0.6 and fishCenter <= moveCenter + tolerance then
            wantedDirection = -1
        elseif velocity < -0.6 and fishCenter >= moveCenter - tolerance then
            wantedDirection = 1
        else
            wantedDirection = fishCenter > moveCenter and 1 or -1
        end
    end

    local holdDirection = Runtime.FishingHoldDirection or 1
    local shouldHold = wantedDirection == holdDirection
    setFishingMouseHeld(shouldHold)
    releaseFishingKey()

    Runtime.FishingHadReel = true
    setFishingState(
        "REEL",
        string.format(
            "Keeping Fish inside Move | error %.1f | %s",
            fishCenter - moveCenter,
            shouldHold and "HOLD" or "RELEASE"
        )
    )

    return true
end

function FishingService.EquipRod(rod)
    if not rod then
        return false
    end

    if Runtime.FishingEquippedRod == rod.Name
        and os.clock() - (Runtime.FishingEquippedAt or 0) < 120 then
        return true
    end

    local ok = false
    if rod.Source == "Hotbar" then
        ok = HotbarService.Press(rod.Hotbar)
    elseif rod.EquipButton and rod.EquipButton:IsA("GuiButton") then
        ok = clickButtonReliable(rod.EquipButton)
    end

    if ok then
        Runtime.FishingEquippedRod = rod.Name
        Runtime.FishingEquippedAt = os.clock()
        Runtime.FishingRodCache = nil
        Runtime.FishingRodCacheAt = 0
    end

    return ok
end

function FishingService.GetConditions()
    local rod = FishingService.FindRod()
    local bait = FishingService.GetBait()
    local spot, spotReason = FishingService.ResolveSpot()

    return {
        Enabled = Config.AutoFishing,
        PlayerReady = PlayerState.IsReady(),
        ProgressionFree = not Config.AutoProgress
            or Runtime.ProgressLifeSkill == "Fishing",
        Rod = rod and rod.Name or "None",
        RodSource = rod and rod.Source or "None",
        Bait = bait and bait.Name or "None",
        BaitAmount = bait and bait.Amount or 0,
        BaitRequired = Config.FishingRequireBait,
        SpotFound = spot ~= nil,
        Spot = spotReason,
        State = Runtime.FishingState,
        Reason = Runtime.FishingReason,
        CanStart =
            Config.AutoFishing
            and PlayerState.IsReady()
            and (
                not Config.AutoProgress
                or Runtime.ProgressLifeSkill == "Fishing"
            )
            and rod ~= nil
            and spot ~= nil
            and (
                not Config.FishingRequireBait
                or (bait and bait.Amount > 0)
            ),
    }
end

function FishingService.Reset(reason)
    releaseFishingKey()
    setFishingMouseHeld(false)
    Runtime.FishingHadReel = false
    Runtime.FishingTimedReleaseDone = false
    Runtime.FishingLastShakePosition = nil
    setFishingState("CHECK", reason or "reset")
end

function FishingService.Step()
    local progressionFishing = Config.AutoProgress
        and Runtime.ProgressLifeSkill == "Fishing"

    if not Config.AutoFishing and not progressionFishing then
        FishingService.Reset("Auto Fishing disabled")
        setFishingState("IDLE", "Auto Fishing disabled")
        return 0.8
    end

    if Config.AutoProgress
        and Runtime.ProgressLifeSkill ~= "Fishing" then
        FishingService.Reset("Auto Progress owns movement")
        return 0.6
    end

    if not PlayerState.IsReady() then
        FishingService.Reset("Player not ready")
        return 0.8
    end

    -- QTE priority comes before inventory/hotbar checks so a 30-60 Hz QTE
    -- never performs expensive hotbar/inventory discovery every frame.
    if FishingService.HandleShake() then
        return 0.045
    end

    if FishingService.HandleSpamClick() then
        return 0.055
    end

    if FishingService.HandleTimedRelease() then
        return 0.035
    end

    if FishingService.HandleReel() then
        return 0.035
    end

    releaseFishingKey()
    setFishingMouseHeld(false)

    local rod = FishingService.FindRod()
    if not rod then
        setFishingState("WAIT_ROD", "Rod is not visible in Hotbar/FishInventory yet")
        Runtime.FishingRodCache = nil
        Runtime.FishingRodCacheAt = 0
        return 1.2
    end

    local bait = FishingService.GetBait()
    if Config.FishingRequireBait
        and (not bait or bait.Amount <= 0) then

        FishingService.Reset("Required bait missing")
        setFishingState("MISSING_BAIT", "Bait required but unavailable")
        return 1.0
    end

    local spot, spotReason = FishingService.ResolveSpot()
    if not spot then
        FishingService.Reset(spotReason)
        setFishingState("MISSING_SPOT", spotReason)
        return 1.0
    end

    if Runtime.FishingHadReel then
        Runtime.FishingHadReel = false
        Runtime.FishingLastCast = os.clock()
        setFishingState("COOLDOWN", "Reel ended")
    end

    if Runtime.FishingState == "COOLDOWN" then
        if os.clock() - Runtime.FishingStateSince < Config.FishingCooldown then
            return 0.25
        end

        setFishingState("CHECK", "Cooldown complete")
    end

    local root = rootPart()
    local distance = root and (root.Position - spot.Position).Magnitude or math.huge

    if distance > Config.PlatformArrivalDistance then
        if not Config.FishingAutoReturn then
            setFishingState("WAIT_SPOT", "Move to fishing spot manually")
            return 0.8
        end

        setFishingState("MOVE_TO_SPOT", spotReason)

        if FarmMovement then
            FarmMovement.Go(
                spot,
                false,
                "fishing",
                spot.Position
            )
        else
            PlatformTransport.MoveToRootCFrame(spot)
        end

        return 0.20
    end

    MotionController.Release("Fishing", true)

    if Runtime.FishingState == "WAIT_QTE" then
        if os.clock() - Runtime.FishingStateSince >= Config.FishingBiteTimeout then
            Runtime.FishingLastCast = os.clock()
            Runtime.FishingEquippedRod = nil
            Runtime.FishingEquippedAt = 0
            setFishingState("COOLDOWN", "No bite/QTE; retrying")
        end

        return 0.25
    end

    if os.clock() - Runtime.FishingLastCast < Config.FishingCooldown then
        return 0.25
    end

    local equipped = FishingService.EquipRod(rod)
    if not equipped then
        setFishingState("EQUIP_FAILED", "Rod equip input failed")
        return 0.8
    end

    task.wait(Config.FishingEquipSettle)
    mouseClickCenter()

    Runtime.FishingLastCast = os.clock()
    setFishingState("WAIT_QTE", "Cast once; waiting for SHAKE/QTE")

    return 0.20
end

-- ============================================================
-- Mining service
-- Real ore models + verified hold/release QTE
-- ============================================================

MiningQTEService = {}

local ORE_CATALOG = {
    "Copper Ore",
    "Iron Ore",
    "Silver Ore",
    "Gold Ore",
    "Diamond Ore",
}

local function setMiningState(state, reason)
    if Runtime.MiningState ~= state then
        Runtime.MiningState = state
        Runtime.MiningStateSince = os.clock()
    end
    Runtime.ProgressDetail = reason or Runtime.ProgressDetail
end

local function miningMouse(held, ore)
    if Runtime.MiningMouseHeld == held then
        return
    end

    Runtime.MiningMouseHeld = held

    local point = ore and screenPointOf(ore)
    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)
    local x = point and point.X or viewport.X / 2
    local y = point and point.Y or viewport.Y / 2

    mouseButtonAt(x, y, held)
end

local function oreName(model)
    if not model then
        return nil
    end

    return tostring(
        model:GetAttribute("Ore")
        or model:GetAttribute("Name")
        or model.Name
    )
end

local function oreIsAvailable(model)
    if not model or not model.Parent or not model:IsA("Model") then
        return false
    end

    if model:GetAttribute("ObjectType") ~= "Ore"
        and model:GetAttribute("Ore") == nil then
        return false
    end

    return model:GetAttribute("Mined") ~= true
        and objectRoot(model) ~= nil
end

local function questRequiredOre()
    local _, taskData = QuestService.GetStableTask()
    if not taskData or taskData.Kind ~= "Mine" then
        return nil
    end

    local target = normalize(taskData.Target)
    if target == "" then
        return nil
    end

    for _, name in ipairs(ORE_CATALOG) do
        local a = lower(name)
        local b = lower(target)
        if a == b or a:find(b, 1, true) or b:find(a, 1, true) then
            return name
        end
    end

    return target
end

function MiningQTEService.GetWantedOre()
    if Config.MiningMode == "Quest Required" then
        return questRequiredOre() or Config.SelectedOre
    elseif Config.MiningMode == "Selected Ore" then
        return Config.SelectedOre
    end

    return nil
end

function MiningQTEService.GetOreOptions()
    local set = {}
    for _, name in ipairs(ORE_CATALOG) do
        set[name] = true
    end

    for model in pairs(Runtime.Ores) do
        if oreIsAvailable(model) then
            set[oreName(model)] = true
        end
    end

    local result = {}
    for name in pairs(set) do
        table.insert(result, name)
    end
    table.sort(result)
    return result
end

function MiningQTEService.RefreshOreIndex(force)
    local now = os.clock()
    if not force and now - (Runtime.MiningLastIndexRefresh or 0) < 1.5 then
        return
    end
    Runtime.MiningLastIndexRefresh = now

    local islands = Workspace:FindFirstChild("Islands")
    if not islands then
        return
    end

    for _, object in ipairs(islands:GetDescendants()) do
        if object:IsA("Model")
            and (
                object:GetAttribute("ObjectType") == "Ore"
                or object:GetAttribute("Ore") ~= nil
            ) then
            Runtime.Ores[object] = true
        end
    end
end

function MiningQTEService.FindOre()
    local wanted = MiningQTEService.GetWantedOre()

    local function pickBest()
        local best
        local bestDistance
        local bestDrop = -math.huge

        for model in pairs(Runtime.Ores) do
            if oreIsAvailable(model) then
                local name = oreName(model)
                local accepted = Config.MiningMode == "Any Available"
                    or wanted == nil
                    or lower(name) == lower(wanted)

                if accepted then
                    local distance = distanceTo(model)
                    local drop = tonumber(model:GetAttribute("DropAmount")) or 0

                    if Config.MiningMode == "Highest Drop" then
                        if drop > bestDrop
                            or (drop == bestDrop and (not bestDistance or distance < bestDistance)) then
                            best = model
                            bestDrop = drop
                            bestDistance = distance
                        end
                    elseif not bestDistance or distance < bestDistance then
                        best = model
                        bestDistance = distance
                    end
                end
            end
        end

        return best
    end

    local best = pickBest()
    if best then
        return best
    end

    MiningQTEService.RefreshOreIndex(false)
    return pickBest()
end

local function findPickaxe()
    HotbarService.Refresh()

    for _, data in pairs(HotbarService.Slots) do
        if lower(data.Title):find("pickaxe", 1, true) then
            return data
        end
    end

    return nil
end

local function findMiningQTE()
    local screen = qteScreen()
    local client = screen and screen:FindFirstChild("QTEClient")
    local events = client and client:FindFirstChild("Events")
    local module = events and events:FindFirstChild("Mining")
    local billboard = module and module:FindFirstChild("Mining")

    if not billboard
        or not billboard:IsA("BillboardGui")
        or not billboard.Enabled then
        return nil
    end

    local frame = billboard:FindFirstChild("Frame")
    local critical = frame and frame:FindFirstChild("Critical Zone")
    local amount = frame and frame:FindFirstChild("Amount")

    if critical and amount
        and critical:IsA("GuiObject")
        and amount:IsA("GuiObject") then
        return billboard, frame, critical, amount
    end

    return nil
end

local function miningAmountTop(amount)
    -- Amount is anchored at Y=1 and grows upward.
    return 1 - math.clamp(amount.Size.Y.Scale, 0, 1)
end

local function miningCriticalBand(critical)
    local top = critical.Position.Y.Scale
    local bottom = top + critical.Size.Y.Scale
    return math.min(top, bottom), math.max(top, bottom)
end

function MiningQTEService.HandleQTE(ore)
    if not Config.AutoMiningQTE then
        return false
    end

    local _, _, critical, amount = findMiningQTE()
    if not critical or not amount then
        return false
    end

    local amountTop = miningAmountTop(amount)
    local criticalTop, criticalBottom = miningCriticalBand(critical)
    local tolerance = Config.MiningCriticalTolerance

    -- Game tutorial confirms: hold mouse to charge; release at the target/top.
    -- We use the actual green Critical Zone instead of a guessed fixed %.
    local inside = amountTop >= (criticalTop - tolerance)
        and amountTop <= (criticalBottom + tolerance)

    if inside and not Runtime.MiningReleaseDone then
        miningMouse(false, ore)
        Runtime.MiningReleaseDone = true
        Runtime.MiningLastQTE = os.clock()
        setMiningState("RELEASE", string.format("Released on %s critical zone", oreName(ore)))
    elseif not Runtime.MiningReleaseDone then
        miningMouse(true, ore)
        setMiningState("CHARGE", string.format("Charging %s", oreName(ore)))
    end

    return true
end

function MiningQTEService.Reset(reason)
    miningMouse(false, Runtime.MiningTarget)
    Runtime.MiningTarget = nil
    Runtime.MiningReleaseDone = false
    Runtime.MiningEquippedSlot = nil
    Runtime.MiningTeleportedTarget = nil
    setMiningState("CHECK", reason or "reset")
end

function MiningQTEService.TeleportToOre(ore)
    local target = objectRoot(ore)
    if not target then
        return false
    end

    local look = target.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude <= 0.05 then
        flat = Vector3.new(0, 0, -1)
    else
        flat = flat.Unit
    end

    local position = target.Position
        - flat * 4.2
        + Vector3.new(0, 1.0, 0)

    return MotionController.Request(
        "Mining",
        motionYawCFrame(position, target.Position),
        {
            Kind = "mining",
            FacePosition = target.Position,
            ArrivalDistance = 1.0,
            Speed = Config.TweenSpeed,
        }
    )
end

function MiningQTEService.Step()
    local progressionMining =
        Config.AutoProgress
        and Runtime.ProgressLifeSkill == "Mining"

    local manualMining = Config.AutoMining

    if not manualMining and not progressionMining then
        MiningQTEService.Reset("Auto Mining disabled")
        Runtime.MiningEquippedSlot = nil
        Runtime.MiningTeleportedTarget = nil
        return 0.8
    end

    if not PlayerState.IsReady() then
        MiningQTEService.Reset("Player not ready")
        return 0.8
    end

    local ore = Runtime.MiningTarget

    if not oreIsAvailable(ore) then
        ore = MiningQTEService.FindOre()
        Runtime.MiningTarget = ore
        Runtime.MiningReleaseDone = false
        Runtime.MiningTeleportedTarget = nil
        Runtime.MiningEquippedSlot = nil
    end

    if not ore then
        miningMouse(false)
        if Runtime.MiningNoOreSince == 0 then
            Runtime.MiningNoOreSince = os.clock()
        end
        MiningQTEService.RefreshOreIndex(true)
        setMiningState(
            "WAIT_STREAM",
            "No live matching ore in the currently streamed islands"
        )
        return Config.MiningNoOreRetry
    end

    Runtime.MiningNoOreSince = 0

    local wanted = oreName(ore)
    local distance = distanceTo(ore)

    if distance > 7 then
        miningMouse(false, ore)
        setMiningState(
            "TELEPORT",
            "Teleporting to " .. wanted
        )

        MiningQTEService.TeleportToOre(ore)
        Runtime.MiningTeleportedTarget = ore
        return 0.18
    end

    MotionController.Release("Mining", true)

    local pickaxe = findPickaxe()

    if not pickaxe then
        miningMouse(false, ore)
        setMiningState(
            "MISSING_PICKAXE",
            "No Pickaxe detected in live hotbar"
        )
        return 0.8
    end

    if Runtime.MiningEquippedSlot ~= pickaxe.Slot then
        HotbarService.Press(pickaxe)
        Runtime.MiningEquippedSlot = pickaxe.Slot
        Runtime.MiningEquipAt = os.clock()

        setMiningState(
            "EQUIP",
            "Equipping " .. pickaxe.Title
        )

        return 0.22
    end

    if os.clock() - Runtime.MiningEquipAt < 0.35 then
        return 0.06
    end

    if MiningQTEService.HandleQTE(ore) then
        if Runtime.MiningReleaseDone
            and os.clock() - Runtime.MiningLastQTE
                >= Config.MiningRetryDelay then

            Runtime.MiningReleaseDone = false
            Runtime.MiningLastAttempt = os.clock()
        end

        return 0.035
    end

    local elapsed =
        os.clock() - Runtime.MiningStateSince

    if Runtime.MiningState ~= "HOLD" then
        setMiningState(
            "HOLD",
            "Holding M1 on " .. wanted
        )
        Runtime.MiningStateSince = os.clock()
        miningMouse(true, ore)

    elseif elapsed >= Config.MiningHoldTimeout then
        miningMouse(false, ore)
        Runtime.MiningLastAttempt = os.clock()
        Runtime.MiningEquippedSlot = nil

        setMiningState(
            "RETRY",
            "Mining QTE timeout"
        )

        return Config.MiningRetryDelay
    end

    return 0.05
end

-- ============================================================
-- Lifeskill / collection
-- ============================================================

LifeSkillService = {}

local function promptFeatureEnabled(kind)
    return kind == "Pickup" and Config.AutoPickup
        or kind == "Chest" and Config.AutoChest
        or kind == "WorldBossChest" and Config.AutoWorldBossChest
        or kind == "FruitChest" and Config.AutoFruitChest
        or kind == "QuestItem" and Config.AutoQuestItems
        or kind == "Farm" and (
            Config.AutoFarming
            or Runtime.ProgressLifeSkill == "Farming"
        )
end

function LifeSkillService.FindNearestEnabledPrompt()
    local best
    local bestDistance

    for prompt in pairs(Runtime.Prompts) do
        if prompt and prompt.Parent and prompt.Enabled then
            local kind = promptKind(prompt)

            if promptFeatureEnabled(kind) then
                local distance = distanceTo(prompt)

                if not bestDistance or distance < bestDistance then
                    best = prompt
                    bestDistance = distance
                end
            end
        end
    end

    return best, bestDistance
end

local function usePromptWithCooldown(prompt, cooldown)
    if not prompt or not prompt.Parent then
        return false
    end

    local now = os.clock()
    local last = Runtime.PromptUseAt[prompt] or 0

    if now - last < (cooldown or 0.75) then
        return false
    end

    Runtime.PromptUseAt[prompt] = now
    return InteractionService.FirePrompt(prompt)
end

function LifeSkillService.StepPrompts()
    local prompt, distance =
        LifeSkillService.FindNearestEnabledPrompt()

    if not prompt then
        Runtime.LootRouteTarget = nil
        Runtime.LootRouteKind = nil
        return
    end

    local kind = promptKind(prompt)
    Runtime.LootRouteTarget = prompt
    Runtime.LootRouteKind = kind

    local isChest =
        kind == "Chest"
        or kind == "WorldBossChest"
        or kind == "FruitChest"

    local highPriorityOwner =
        Runtime.Motion.Owner == "Dialogue"
        or Runtime.Motion.Owner == "Mining"
        or Runtime.Motion.Owner == "Fishing"
        or Runtime.Motion.Owner == "Farming"
        or Runtime.Motion.Owner == "Combat"
        or Runtime.Motion.Owner == "Manual"

    if Config.AutoProgress or highPriorityOwner then
        -- Background collection may use nearby prompts only. It never
        -- acquires or releases movement while a real task owns motion.
        local allowedDistance = isChest
            and Config.ChestCollectRadius
            or 14

        if distance <= allowedDistance then
            usePromptWithCooldown(
                prompt,
                isChest and 1.15 or 0.75
            )
        end

        return
    end

    if distance <= Config.PlatformArrivalDistance + 2 then
        MotionController.Release("Loot", true)
        usePromptWithCooldown(
            prompt,
            isChest and 1.15 or 0.75
        )
        return
    end

    local target = objectRoot(prompt)
    local root = rootPart()

    if not target or not root then
        return
    end

    local away = Vector3.new(
        root.Position.X - target.Position.X,
        0,
        root.Position.Z - target.Position.Z
    )

    if away.Magnitude <= 0.05 then
        away = Vector3.new(0, 0, 1)
    else
        away = away.Unit
    end

    local goal = motionYawCFrame(
        target.Position
            + away * 3
            + Vector3.new(0, 0.3, 0),
        target.Position
    )

    MotionController.Request(
        "Loot",
        goal,
        {
            Kind = "loot",
            FacePosition = target.Position,
        }
    )
end

-- ============================================================
-- Treasure / world utility
-- ============================================================

WorldUtilityService = {}

function WorldUtilityService.FindPromptByName(name)
    local wanted = lower(name)
    local best
    local bestDistance

    for prompt in pairs(Runtime.Prompts) do
        if prompt and prompt.Parent and prompt.Enabled then
            local blob = lower(
                prompt.Name
                .. " "
                .. tostring(prompt.ActionText or "")
                .. " "
                .. tostring(prompt.ObjectText or "")
            )

            if blob:find(wanted, 1, true) then
                local distance = distanceTo(prompt)
                if not bestDistance or distance < bestDistance then
                    best = prompt
                    bestDistance = distance
                end
            end
        end
    end

    return best
end

function WorldUtilityService.GoToPrompt(name)
    local prompt = WorldUtilityService.FindPromptByName(name)

    if not prompt then
        notify("World Utility", "Prompt not found: " .. tostring(name), 4)
        return
    end

    Runtime.CurrentTarget = prompt

    if distanceTo(prompt) > Config.PlatformArrivalDistance + 1 then
        PlatformTransport.MoveNear(prompt)
    else
        PlatformTransport.Cancel(true)
        InteractionService.FirePrompt(prompt)
    end
end

-- ============================================================
-- World target resolver
-- Used for Reach/Visit/Enter/event-position quests.
-- ============================================================

WorldTargetService = {
    Cache = {},
}

local function worldTargetCandidateScore(object, wanted)
    if not object or not object.Parent then
        return 0
    end

    local name = lower(stripRuntimeSuffix(object.Name))
    local target = lower(stripRuntimeSuffix(wanted))

    if name == target then
        return 160
    end

    if name:find(target, 1, true)
        or target:find(name, 1, true) then
        return 105
    end

    local blob = lower(table.concat({
        tostring(object:GetAttribute("Name") or ""),
        tostring(object:GetAttribute("DisplayName") or ""),
        tostring(object:GetAttribute("Interaction") or ""),
        tostring(object:GetAttribute("ObjectType") or ""),
    }, " "))

    if blob:find(target, 1, true) then
        return 85
    end

    return 0
end

local function worldMarkerText(marker)
    if not marker or not marker.Parent then
        return ""
    end

    local parts = {marker.Name}
    for _, object in ipairs(marker:GetDescendants()) do
        if object:IsA("TextLabel") or object:IsA("TextButton") then
            local value = normalize(object.Text)
            if value ~= "" then
                table.insert(parts, value)
            end
        end
    end

    return normalize(table.concat(parts, " "))
end

local function worldMarkerTarget(marker)
    if not marker or not marker.Parent then
        return nil
    end

    local adornee
    pcall(function()
        adornee = marker.Adornee
    end)

    if adornee then
        if adornee:IsA("Attachment") then
            return adornee.Parent
        end
        if adornee:IsA("BasePart") or adornee:IsA("Model") then
            return adornee
        end
    end

    if marker.Parent:IsA("Attachment") then
        return marker.Parent.Parent
    end
    if marker.Parent:IsA("BasePart") or marker.Parent:IsA("Model") then
        return marker.Parent
    end

    return marker:FindFirstAncestorWhichIsA("Model")
end

local function findTrackedWorldMarker(name)
    local wanted = lower(stripRuntimeSuffix(name))
    if wanted == "" then
        return nil
    end

    local best, bestScore, bestDistance = nil, -math.huge, math.huge
    for marker in pairs(Runtime.WorldMarkers) do
        if marker and marker.Parent and marker.Enabled then
            local blob = lower(worldMarkerText(marker))
            local score = 0
            if blob == wanted then
                score = 180
            elseif blob:find(wanted, 1, true) then
                score = 145
            end

            if score > 0 then
                local target = worldMarkerTarget(marker)
                if target and objectRoot(target) then
                    local distance = distanceTo(target)
                    if score > bestScore or (score == bestScore and distance < bestDistance) then
                        best, bestScore, bestDistance = target, score, distance
                    end
                end
            end
        end
    end

    return best
end

function WorldTargetService.Find(name)
    local wanted = normalize(name)
    if wanted == "" then
        return nil
    end

    local key = lower(wanted)
    local cached = WorldTargetService.Cache[key]

    if cached
        and cached.Object
        and cached.Object.Parent
        and os.clock() - cached.At < 3 then
        return cached.Object
    end

    local trackedMarker = findTrackedWorldMarker(wanted)
    if trackedMarker then
        WorldTargetService.Cache[key] = {
            Object = trackedMarker,
            At = os.clock(),
        }
        return trackedMarker
    end

    local prompt = InteractionService.FindPromptByText(
        wanted
    )
    if prompt then
        WorldTargetService.Cache[key] = {
            Object = prompt,
            At = os.clock(),
        }
        return prompt
    end

    local dialogue =
        TargetService.FindNamedDialogueNPC(
            wanted
        )

    if dialogue then
        WorldTargetService.Cache[key] = {
            Object = dialogue,
            At = os.clock(),
        }
        return dialogue
    end

    local roots = {
        Workspace:FindFirstChild("AA IMPORTANT"),
        Workspace:FindFirstChild("Islands"),
        Workspace:FindFirstChild("Locations"),
        Workspace:FindFirstChild("Map"),
    }

    local best
    local bestScore = -math.huge
    local bestDistance = math.huge

    for _, root in ipairs(roots) do
        if root then
            local exact =
                root:FindFirstChild(
                    wanted,
                    true
                )

            if exact and objectRoot(exact) then
                WorldTargetService.Cache[key] = {
                    Object = exact,
                    At = os.clock(),
                }
                return exact
            end

            local fuzzyAllowed =
                root.Name == "AA IMPORTANT"
                or root.Name == "Locations"

            -- Avoid scanning the enormous Islands tree if an exact
            -- named target was not found. The game snapshot is very large.
            if fuzzyAllowed then
                for _, object in ipairs(
                    root:GetDescendants()
                ) do
                    if object:IsA("Model")
                        or object:IsA("BasePart") then

                        local score =
                            worldTargetCandidateScore(
                                object,
                                wanted
                            )

                        if score > 0
                            and objectRoot(object) then

                            local distance =
                                distanceTo(object)

                            if score > bestScore
                                or (
                                    score == bestScore
                                    and distance < bestDistance
                                ) then

                                best = object
                                bestScore = score
                                bestDistance = distance
                            end
                        end
                    end
                end
            end
        end
    end

    WorldTargetService.Cache[key] = {
        Object = best,
        At = os.clock(),
    }

    return best
end

-- ============================================================
-- Auto Farm v12
-- Single progression owner + smooth farm movement
-- ============================================================

AutoFarmController = {}
FarmMovement = {}

local function farmSetState(state, detail)
    local fsm = Runtime.FarmFSM

    if fsm.State ~= state then
        fsm.State = state
        fsm.Since = os.clock()
    end

    Runtime.ProgressState = state
    Runtime.ProgressDetail = detail or ""
end

local function yawCFrame(position, facePosition)
    return motionYawCFrame(position, facePosition)
end

local function motionOwnerForKind(kind)
    if kind == "interaction" then
        return "Dialogue"
    elseif kind == "combat"
        or kind == "farm"
        or kind == "gather-tag"
        or kind == "gather-return" then
        return "Combat"
    elseif kind == "fishing" then
        return "Fishing"
    elseif kind == "mining" then
        return "Mining"
    elseif kind == "farming" then
        return "Farming"
    elseif kind == "loot" then
        return "Loot"
    elseif kind == "manual" then
        return "Manual"
    end

    return "Quest"
end

function FarmMovement.Ensure()
    return nil
end

function FarmMovement.Stop(removePlatform, clearHold)
    local owner = Runtime.Motion.Owner
    if owner then
        MotionController.Release(owner, true)
    end
end

function FarmMovement.Go(rootGoal, holdAtEnd, kind, facePosition)
    if not rootGoal then
        return false
    end

    local owner = motionOwnerForKind(kind)

    return MotionController.Request(
        owner,
        rootGoal,
        {
            Kind = kind or "travel",
            FacePosition = facePosition or rootGoal.Position,
            Hold = holdAtEnd == true,
        }
    )
end

function FarmMovement.IsAt(rootGoal, tolerance)
    local root = rootPart()
    if not root or not rootGoal then
        return false
    end

    return (
        root.Position
        - rootGoal.Position
    ).Magnitude <= (
        tolerance
        or Config.PlatformArrivalDistance
    )
end

function FarmMovement.GoNear(object, heightOffset, backDistance)
    local target = objectRoot(object)
    local root = rootPart()

    if not target or not root then
        return false
    end

    heightOffset = heightOffset or 0.35
    backDistance = backDistance or Config.PlatformBackDistance

    local away = Vector3.new(
        root.Position.X - target.Position.X,
        0,
        root.Position.Z - target.Position.Z
    )

    if away.Magnitude <= 0.05 then
        local look = target.CFrame.LookVector
        away = Vector3.new(-look.X, 0, -look.Z)
    end

    if away.Magnitude <= 0.05 then
        away = Vector3.new(0, 0, 1)
    else
        away = away.Unit
    end

    local position = target.Position
        + away * backDistance
        + Vector3.new(0, heightOffset, 0)

    local kind = "travel"

    if Config.AutoMining
        or Runtime.ProgressLifeSkill == "Mining" then
        kind = "mining"
    elseif Config.AutoFishing
        or Runtime.ProgressLifeSkill == "Fishing" then
        kind = "fishing"
    elseif Config.AutoFarming
        or Runtime.ProgressLifeSkill == "Farming" then
        kind = "farming"
    end

    return FarmMovement.Go(
        motionYawCFrame(position, target.Position),
        false,
        kind,
        target.Position
    )
end

function FarmMovement.GetInteractionGoal(object, prompt)
    local target = objectRoot(prompt) or objectRoot(object)
    local root = rootPart()

    if not target or not root then
        return nil
    end

    local maxDistance = prompt
        and tonumber(prompt.MaxActivationDistance)
        or 16

    local desiredDistance = math.clamp(
        maxDistance * 0.42,
        5.0,
        6.8
    )

    local look = target.CFrame.LookVector
    local forward = Vector3.new(look.X, 0, look.Z)

    if forward.Magnitude <= 0.05 then
        forward = Vector3.new(0, 0, -1)
    else
        forward = forward.Unit
    end

    local position = target.Position
        + forward * desiredDistance
        + Vector3.new(0, 0.15, 0)

    return motionYawCFrame(position, target.Position)
end

function FarmMovement.GoInteract(object, prompt)
    local goal = FarmMovement.GetInteractionGoal(object, prompt)
    local target = objectRoot(prompt) or objectRoot(object)

    if not goal or not target then
        return false
    end

    return MotionController.Request(
        "Dialogue",
        goal,
        {
            Kind = "interaction",
            FacePosition = target.Position,
            ArrivalDistance = 1.4,
        }
    )
end

function FarmMovement.GoAnchor(anchor)
    if not anchor then
        return false
    end

    return MotionController.Request(
        "Combat",
        anchor,
        {
            Kind = "combat",
            FacePosition = anchor.Position + anchor.LookVector,
            Hold = true,
        }
    )
end

function FarmMovement.Step(deltaTime)
    return
end

local function farmResetRoute(clearAnchor)
    Runtime.CurrentTarget = nil
    Runtime.CurrentWantedMob = nil
    Runtime.ProgressLifeSkill = nil

    if clearAnchor ~= false then
        Runtime.FarmAnchorCFrame = nil
        MobGatherService.Reset()
    end
end

local function resolveQuestNpc(questName, preferredNpc)
    local npc

    if preferredNpc and preferredNpc ~= "" then
        npc = TargetService.FindNamedDialogueNPC(preferredNpc)
    end

    npc = npc
        or QuestCatalogService.FindQuestGiver(
            questName,
            preferredNpc
        )

    if not npc and preferredNpc and preferredNpc ~= "" then
        npc = TargetService.FindNamedNPC(preferredNpc)
    end

    return npc
end

local function stepQuestNpc(questName, preferredNpc, finalState)
    farmResetRoute(false)

    local fsm = Runtime.FarmFSM
    local npc =
        resolveQuestNpc(
            questName,
            preferredNpc
        )

    if not npc then
        FarmMovement.Stop(true, true)

        local now = os.clock()

        if now - fsm.LastResolverRefresh >= 1.5 then
            fsm.LastResolverRefresh = now
            QuestCatalogService.Build()
        end

        fsm.InteractionNPC = nil
        fsm.InteractionPrompt = nil
        fsm.InteractionGoal = nil
        fsm.InteractionArrivedAt = 0
        fsm.InteractionLockUntil = 0

        farmSetState(
            "NPC_SEARCH",
            preferredNpc
                and preferredNpc ~= ""
                and preferredNpc
                or questName
        )
        return
    end

    Runtime.CurrentTarget = npc

    local prompt =
        InteractionService.FindPromptNear(
            npc,
            "Dialogue"
        )

    local targetPart =
        objectRoot(prompt)
        or objectRoot(npc)

    if not targetPart then
        FarmMovement.Stop(true, true)
        farmSetState("NPC_NO_ROOT", npc.Name)
        return
    end

    if fsm.InteractionNPC ~= npc
        or fsm.InteractionPrompt ~= prompt then

        fsm.InteractionNPC = npc
        fsm.InteractionPrompt = prompt
        fsm.InteractionGoal =
            FarmMovement.GetInteractionGoal(
                npc,
                prompt
            )
        fsm.InteractionArrivedAt = 0
        fsm.InteractionLockUntil = 0
        fsm.PromptAttemptAt = 0
        fsm.PromptAttemptCount = 0
    end

    if dialogueIsOpen(npc) then
        FarmMovement.Stop(true, true)

        InteractionService.ProcessDialogue(
            questName,
            npc
        )

        farmSetState(
            "NPC_DIALOGUE",
            npc.Name
        )
        return
    end

    local maxActivation =
        prompt
        and tonumber(prompt.MaxActivationDistance)
        or 16

    local safeTriggerRange =
        math.clamp(
            maxActivation - 2.0,
            7.0,
            14.0
        )

    local root = rootPart()
    if not root then
        return
    end

    local distance =
        (
            root.Position
            - targetPart.Position
        ).Magnitude

    local now = os.clock()

    -- Once we arrive, movement stays locked out while the prompt is
    -- being attempted. Small game/camera nudges cannot restart travel.
    local interactionLocked =
        now < (
            fsm.InteractionLockUntil
            or 0
        )

    if distance > safeTriggerRange
        and not interactionLocked then

        fsm.InteractionArrivedAt = 0

        if not fsm.InteractionGoal then
            fsm.InteractionGoal =
                FarmMovement.GetInteractionGoal(
                    npc,
                    prompt
                )
        end

        if fsm.InteractionGoal then
            FarmMovement.Go(
                fsm.InteractionGoal,
                false,
                "interaction",
                targetPart.Position
            )
        end

        farmSetState(
            "NPC_TRAVEL",
            npc.Name
                .. " • "
                .. string.format(
                    "%.1f",
                    distance
                )
        )
        return
    end

    FarmMovement.Stop(true, true)

    if fsm.InteractionArrivedAt == 0 then
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
        fsm.InteractionArrivedAt = now
        fsm.InteractionLockUntil =
            now + 2.4

        farmSetState(
            "NPC_SETTLE",
            npc.Name
        )
        return
    end

    if now - fsm.InteractionArrivedAt < 0.28 then
        farmSetState(
            "NPC_SETTLE",
            npc.Name
        )
        return
    end

    if not prompt then
        farmSetState(
            "NPC_NO_PROMPT",
            npc.Name
        )
        return
    end

    -- If the game moved us a little after arriving, do not start
    -- another high-frequency navigation loop. Only abandon the lock
    -- if we are actually outside the prompt's real activation range.
    if distance > maxActivation + 1.5 then
        fsm.InteractionLockUntil = 0
        fsm.InteractionGoal = nil
        fsm.InteractionArrivedAt = 0

        farmSetState(
            "NPC_REAPPROACH",
            npc.Name
        )
        return
    end

    local triggered =
        InteractionService.InteractWithQuestNPC(
            npc,
            questName
        )

    if triggered then
        fsm.InteractionLockUntil =
            math.max(
                fsm.InteractionLockUntil,
                now + 1.5
            )
    end

    farmSetState(
        triggered
            and "NPC_TRIGGER"
            or "NPC_PRESS_E",
        npc.Name
            .. " • attempt "
            .. tostring(
                fsm.PromptAttemptCount
            )
    )
end

local function combatTargetValid(model, wanted)
    return model
        and model.Parent
        and TargetService.IsFarmMob(model, wanted)
        and objectRoot(model) ~= nil
end

local function nearestCombatTarget(wanted)
    local root = rootPart()
    local best
    local bestDistance

    for model in pairs(Runtime.Entities) do
        if model
            and model.Parent
            and TargetService.IsFarmMob(model, wanted) then

            local part = objectRoot(model)
            if part then
                local distance = root
                    and (root.Position - part.Position).Magnitude
                    or 0

                if not bestDistance or distance < bestDistance then
                    best = model
                    bestDistance = distance
                end
            end
        end
    end

    return best
end

local function combatGoalFor(model)
    if Config.AutoGather and Runtime.Gather.Anchor then
        return Runtime.Gather.Anchor
    end

    local part = objectRoot(model)
    if not part then
        return nil
    end

    local look = part.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude <= 0.05 then
        flat = Vector3.new(0, 0, -1)
    else
        flat = flat.Unit
    end

    local position = part.Position
        - flat * math.max(5, Config.CombatDistance)
        + Vector3.new(0, 0.25, 0)

    return motionYawCFrame(position, part.Position)
end

local function stepDefeatTask(wanted)
    Runtime.ProgressLifeSkill = nil
    Runtime.CurrentWantedMob = wanted

    if Config.AutoGather and wanted ~= "Boss Only" then
        local ready, gatherReason = MobGatherService.Step(wanted)

        farmSetState(
            ready and "GATHER_READY" or "GATHER_MOBS",
            wanted
                .. " • "
                .. MobGatherService.GetStatus()
                .. " • "
                .. tostring(gatherReason)
        )

        if not ready then
            return
        end
    end

    local target = Runtime.CurrentTarget

    if not combatTargetValid(target, wanted) then
        target = nearestCombatTarget(wanted)
        Runtime.CurrentTarget = target
    end

    if not target then
        MotionController.Release("Combat", true)
        farmSetState(
            "MOB_WAIT",
            wanted .. " • waiting for target"
        )
        return
    end

    local targetPart = objectRoot(target)
    local root = rootPart()

    if not targetPart or not root or not TargetService.IsAliveNPC(target) then
        Runtime.CurrentTarget = nil
        return
    end

    local fixedAnchor = Config.AutoGather and Runtime.Gather.Anchor or nil
    if fixedAnchor then
        local anchorDistance = (root.Position - fixedAnchor.Position).Magnitude
        if anchorDistance > 1.6 or not MotionController.IsHolding() then
            MotionController.Request(
                "Combat",
                fixedAnchor,
                {
                    Kind = "combat-hold",
                    FacePosition = targetPart.Position,
                    ArrivalDistance = 1.2,
                    Hold = true,
                }
            )

            if anchorDistance > 1.6 then
                farmSetState("COMBAT_HOLD", target.Name)
                return
            end
        end
    end

    local distance = (
        root.Position
        - targetPart.Position
    ).Magnitude

    if distance > Config.CombatDistance then
        if fixedAnchor then
            Runtime.CurrentTarget = nil
            farmSetState(
                "COMBAT_WAIT_RANGE",
                target.Name .. " • " .. string.format("%.1f", distance)
            )
            return
        end

        local goal = combatGoalFor(target)
        if goal then
            MotionController.Request(
                "Combat",
                goal,
                {
                    Kind = "combat",
                    FacePosition = targetPart.Position,
                    ArrivalDistance = 1.2,
                }
            )
        end

        farmSetState("COMBAT_TRAVEL", target.Name .. " • " .. string.format("%.1f", distance))
        return
    end

    if not fixedAnchor then
        MotionController.Release("Combat", true)
    end
    CombatService.AttackStep()

    farmSetState(
        "FARM_COMBAT",
        target.Name
            .. " • M1 • "
            .. string.format("%.1f", distance)
    )
end

local function stepPromptTask(taskData)
    farmResetRoute(false)

    local allowed = {
        Pickup = true,
        QuestItem = true,
        Chest = true,
        FruitChest = true,
        Other = true,
        Farm = true,
    }

    local prompt = InteractionService.FindPromptByText(
        taskData.Target,
        allowed
    )

    if not prompt then
        FarmMovement.Stop(false, true)

        farmSetState(
            "OBJECT_SEARCH",
            taskData.Target
        )
        return
    end

    Runtime.CurrentTarget = prompt

    if distanceTo(prompt)
        > Config.PlatformArrivalDistance + 2 then

        FarmMovement.GoNear(
            prompt,
            3,
            2.5
        )

        farmSetState(
            "OBJECT_TRAVEL",
            taskData.Target
        )

        return
    end

    FarmMovement.Stop(false, true)
    InteractionService.FirePrompt(prompt)

    farmSetState(
        "OBJECT_INTERACT",
        taskData.Target
    )
end

local function stableReachGoal(target, standHeight)
    local part = objectRoot(target)
    if not part then
        return nil
    end

    standHeight = standHeight or 3
    local look = part.CFrame.LookVector
    local flatLook = Vector3.new(look.X, 0, look.Z)
    if flatLook.Magnitude <= 0.05 then
        flatLook = Vector3.new(0, 0, -1)
    else
        flatLook = flatLook.Unit
    end

    local position = part.Position + Vector3.new(0, standHeight, 0) - flatLook * 2.5
    return yawCFrame(position, part.Position)
end

local function stepReachTask(quest, taskData)
    farmResetRoute(false)

    local target =
        WorldTargetService.Find(
            taskData.Target
        )

    if not target
        and quest
        and quest.Name ~= taskData.Target then

        target =
            WorldTargetService.Find(
                quest.Name
            )
    end

    if not target then
        FarmMovement.Stop(false, true)

        farmSetState(
            "REACH_SEARCH",
            taskData.Target
        )

        return
    end

    Runtime.CurrentTarget = target

    local requiredDistance =
        math.max(
            7,
            Config.PlatformArrivalDistance + 2
        )

    if distanceTo(target) > requiredDistance then
        local goal = stableReachGoal(
            target,
            target:IsA("Model")
                and target:FindFirstChildOfClass("Humanoid")
                and 0.25
                or 3
        )

        if goal then
            FarmMovement.Go(
                goal,
                taskData.EventGated == true,
                "reach",
                objectRoot(target) and objectRoot(target).Position or goal.Position
            )
        end

        farmSetState(
            "REACH_TRAVEL",
            taskData.Target .. (findTrackedWorldMarker(taskData.Target) and " • tracked marker" or "")
        )

        return
    end

    if taskData.EventGated then
        local goal = stableReachGoal(target, 3)
        if goal then
            FarmMovement.Go(
                goal,
                true,
                "reach",
                objectRoot(target) and objectRoot(target).Position or goal.Position
            )
        end
    else
        FarmMovement.Stop(false, true)
    end

    farmSetState(
        taskData.EventGated
            and "REACH_WAIT_EVENT"
            or "REACH_ARRIVED",
        taskData.Target .. (findTrackedWorldMarker(taskData.Target) and " • marker locked" or "")
    )
end

local function stepEquipOrUseTask(taskData)
    farmResetRoute(false)
    FarmMovement.Stop(false, true)

    local slot =
        HotbarService.FindByText(
            taskData.Target
        )

    if not slot then
        farmSetState(
            "ITEM_WAIT",
            taskData.Target
                .. " not found in hotbar"
        )
        return
    end

    HotbarService.Press(slot)

    farmSetState(
        taskData.Kind == "Equip"
            and "ITEM_EQUIP"
            or "ITEM_USE",
        slot.Title
    )
end

local function stepUtilityTask(quest, taskData)
    farmResetRoute(false)

    if taskData.Kind == "Learn" then
        stepQuestNpc(
            quest.Name,
            taskData.Target,
            "QUEST_LEARN"
        )
        return
    end

    local promptName

    if taskData.Kind == "Craft" then
        promptName = "Crafting Table"
    elseif taskData.Kind == "Cook" then
        promptName = "Furnace"
    elseif taskData.Kind == "Upgrade" then
        promptName = "Anvil"
    end

    local prompt = promptName
        and WorldUtilityService.FindPromptByName(
            promptName
        )
        or InteractionService.FindPromptByText(
            taskData.Target
        )

    if not prompt then
        FarmMovement.Stop(false, true)

        farmSetState(
            "UTILITY_WAIT",
            taskData.Text
        )
        return
    end

    Runtime.CurrentTarget = prompt

    if distanceTo(prompt)
        > Config.PlatformArrivalDistance + 2 then

        FarmMovement.GoNear(
            prompt,
            3,
            2.5
        )

        farmSetState(
            "UTILITY_TRAVEL",
            promptName or taskData.Target
        )

        return
    end

    FarmMovement.Stop(false, true)
    InteractionService.FirePrompt(prompt)

    farmSetState(
        "UTILITY_INTERACT",
        promptName or taskData.Target
    )
end

local function routeLifeSkill(kind, detail)
    FarmMovement.Stop(true, true)
    Runtime.CurrentTarget = nil
    Runtime.CurrentWantedMob = nil

    Runtime.ProgressLifeSkill = kind

    farmSetState(
        "LIFESKILL_" .. string.upper(kind),
        detail
    )
end

function AutoFarmController.Step()
    if not Config.AutoProgress then
        Runtime.ProgressLifeSkill = nil

        farmResetRoute(true)
        QuestService.ClearTaskLock()
        FarmMovement.Stop(true, true)

        farmSetState(
            "IDLE",
            "Auto Farm disabled"
        )

        return
    end

    if not PlayerState.IsReady() then
        farmSetState(
            "PLAYER_WAIT",
            "character / player data"
        )
        return
    end

    if Config.AutoMining then
        Runtime.ProgressLifeSkill = "Mining"
        farmSetState(
            "MANUAL_MINING",
            tostring(
                Runtime.MiningTarget
                and oreName(Runtime.MiningTarget)
                or "searching ore"
            )
        )
        return
    end

    -- Manual modes do not touch Quest state.
    if Config.FarmMode == "Selected Mob" then
        stepDefeatTask(Config.SelectedMob)
        return
    elseif Config.FarmMode == "Boss" then
        stepDefeatTask("Boss Only")
        return
    end

    if not Config.AutoQuest then
        farmSetState(
            "QUEST_DISABLED",
            "Auto Quest is off"
        )
        return
    end

    local plan = QuestPlannerService.GetPlan()

    if plan.Mode == "TURN_IN"
        and plan.Quest
        and Config.AutoTurnIn then

        stepQuestNpc(
            plan.Quest.Name,
            nil,
            "QUEST_TURN_IN"
        )
        return
    end

    if plan.Mode == "ACTIVE_TASK"
        and plan.Quest
        and plan.Task then

        local quest = plan.Quest
        local taskData = plan.Task

        local taskKey =
            tostring(quest.Id)
            .. "|"
            .. taskData.Kind
            .. "|"
            .. taskData.Target
            .. "|"
            .. taskData.Text

        if taskKey ~= Runtime.FarmFSM.TaskKey then
            Runtime.FarmFSM.TaskKey = taskKey
            Runtime.FarmFSM.InteractionAttempts = 0
            Runtime.FarmFSM.LastInteraction = 0
            Runtime.FarmAnchorCFrame = nil
            Runtime.CurrentTarget = nil
            Runtime.CurrentWantedMob = nil
            MobGatherService.Reset()
        end

        if taskData.Kind == "Defeat" then
            stepDefeatTask(taskData.Target)
            return
        elseif taskData.Kind == "Talk"
            or taskData.Kind == "Return"
            or taskData.Kind == "Deliver" then

            stepQuestNpc(
                quest.Name,
                taskData.Target,
                "QUEST_NPC"
            )
            return
        elseif taskData.Kind == "Collect"
            or taskData.Kind == "Find"
            or taskData.Kind == "Interact"
            or taskData.Kind == "Reach"
            or taskData.Kind == "Use"
            or taskData.Kind == "Claim"
            or taskData.Kind == "Destroy" then

            if taskData.Kind == "Reach" then
                stepReachTask(quest, taskData)
            else
                stepPromptTask(taskData)
            end
            return
        elseif taskData.Kind == "Mine" then
            routeLifeSkill("Mining", taskData.Text)
            return
        elseif taskData.Kind == "Fish" then
            routeLifeSkill("Fishing", taskData.Text)
            return
        elseif taskData.Kind == "Farm" then
            routeLifeSkill("Farming", taskData.Text)
            return
        elseif taskData.Kind == "Treasure" then
            FarmMovement.Stop(false, true)
            farmSetState(
                "TASK_UNSUPPORTED",
                "Treasure digging is not verified in the current dump"
            )
            return
        end

        stepUtilityTask(quest, taskData)
        return
    end

    if plan.Mode == "ACCEPT_RECOMMENDED"
        and plan.Recommended
        and Config.AutoAcceptRecommended then

        stepQuestNpc(
            plan.Recommended.Name,
            nil,
            "QUEST_ACCEPT"
        )
        return
    end

    farmResetRoute(true)
    FarmMovement.Stop(false, true)

    farmSetState(
        "QUEST_WAIT",
        "Lv."
            .. tostring(plan.Level)
            .. " • no active/recommended quest"
    )
end

-- ============================================================
-- Mob hitbox (local, reversible)
-- ============================================================

HitboxService = {}

local function hitboxPart(model)
    if not model or not model.Parent then
        return nil
    end
    local part = model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("Torso")
    return part and part:IsA("BasePart") and part or nil
end

function HitboxService.RestorePart(part)
    local backup = Core.HitboxBackup[part]
    if not backup then
        return
    end
    if part and part.Parent then
        pcall(function()
            part.Size = backup.Size
            part.Transparency = backup.Transparency
            part.CanCollide = backup.CanCollide
            part.CanTouch = backup.CanTouch
            part.Massless = backup.Massless
        end)
    end
    Core.HitboxBackup[part] = nil
end

function HitboxService.RestoreAll()
    local parts = {}
    for part in pairs(Core.HitboxBackup) do
        table.insert(parts, part)
    end
    for _, part in ipairs(parts) do
        HitboxService.RestorePart(part)
    end
end

function HitboxService.Apply(model)
    if not Config.MobHitbox or not TargetService.IsAliveNPC(model)
        or TargetService.IsDialogueNPC(model) then
        return false
    end

    local part = hitboxPart(model)
    if not part then
        return false
    end

    if not Core.HitboxBackup[part] then
        Core.HitboxBackup[part] = {
            Size = part.Size,
            Transparency = part.Transparency,
            CanCollide = part.CanCollide,
            CanTouch = part.CanTouch,
            Massless = part.Massless,
        }
    end

    local size = math.clamp(tonumber(Config.MobHitboxSize) or 10, 4, 20)
    pcall(function()
        part.Size = Vector3.new(size, size, size)
        part.Transparency = math.clamp(tonumber(Config.MobHitboxTransparency) or 0.72, 0, 1)
        part.CanCollide = false
        part.CanTouch = false
        part.Massless = true
    end)
    return true
end

function HitboxService.Step()
    if not Config.MobHitbox then
        HitboxService.RestoreAll()
        return
    end

    local active = {}
    for model in pairs(Runtime.Entities) do
        if TargetService.IsHostile(model) then
            local part = hitboxPart(model)
            if part and HitboxService.Apply(model) then
                active[part] = true
            end
        end
    end

    local stale = {}
    for part in pairs(Core.HitboxBackup) do
        if not active[part] or not part.Parent then
            table.insert(stale, part)
        end
    end
    for _, part in ipairs(stale) do
        HitboxService.RestorePart(part)
    end
end

-- ============================================================
-- ESP
-- ============================================================

ESPService = {
    Folder = track(Instance.new("Folder")),
    Map = setmetatable({}, {__mode = "k"}),
}

ESPService.Folder.Name = "SON_HUB_ESP"

pcall(function()
    ESPService.Folder.Parent = CoreGui
end)

if not ESPService.Folder.Parent then
    ESPService.Folder.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

function ESPService.Clear(object)
    local highlight = ESPService.Map[object]
    if highlight then
        pcall(function()
            highlight:Destroy()
        end)
        ESPService.Map[object] = nil
    end
end

function ESPService.Set(object, color)
    if not object
        or not object.Parent
        or distanceTo(object) > Config.ESPDistance then

        ESPService.Clear(object)
        return
    end

    local adornee

    if object:IsA("Model") or object:IsA("BasePart") then
        adornee = object
    else
        adornee = object:FindFirstAncestorWhichIsA("Model")
            or objectRoot(object)
    end

    if not adornee then
        return
    end

    local highlight = ESPService.Map[object]

    if not highlight or not highlight.Parent then
        highlight = Instance.new("Highlight")
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillTransparency = 0.78
        highlight.OutlineTransparency = 0.05
        highlight.Parent = ESPService.Folder
        ESPService.Map[object] = highlight
    end

    highlight.Adornee = adornee
    highlight.FillColor = color
    highlight.OutlineColor = color
end

function ESPService.Step()
    local active = {}

    if Config.CurrentTargetESP and Runtime.CurrentTarget then
        active[Runtime.CurrentTarget] = true
        ESPService.Set(Runtime.CurrentTarget, Config.TargetColor)
    end

    if Config.PlayerESP then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local model = player.Character
                if not model or not model.Parent then
                    local entities = entitiesFolder()
                    model = entities and entities:FindFirstChild(player.Name)
                end
                local hum = model and model:FindFirstChildOfClass("Humanoid")
                if model and model.Parent and (not hum or hum.Health > 0) then
                    active[model] = true
                    ESPService.Set(model, Config.PlayerColor)
                end
            end
        end
    end

    if Config.MobESP or Config.BossESP then
        for model in pairs(Runtime.Entities) do
            if TargetService.IsAliveNPC(model)
                and not TargetService.IsDialogueNPC(model) then

                if Config.BossESP and TargetService.IsBoss(model) then
                    active[model] = true
                    ESPService.Set(model, Config.BossColor)
                elseif Config.MobESP and TargetService.IsHostile(model) then
                    active[model] = true
                    ESPService.Set(model, Config.MobColor)
                end
            end
        end
    end

    if Config.LootESP then
        for prompt in pairs(Runtime.Prompts) do
            if prompt and prompt.Parent then
                local kind = promptKind(prompt)

                if kind == "Pickup"
                    or kind == "Chest"
                    or kind == "WorldBossChest"
                    or kind == "FruitChest"
                    or kind == "QuestItem" then

                    active[prompt] = true
                    ESPService.Set(prompt, Config.LootColor)
                end
            end
        end
    end

    for object in pairs(ESPService.Map) do
        if not active[object] or not object.Parent then
            ESPService.Clear(object)
        end
    end
end

-- ============================================================
-- Player tools
-- ============================================================

PlayerToolsService = {}

local function livePlayerModel(player)
    if not player then
        return nil
    end

    local model = player.Character
    if model and model.Parent then
        return model
    end

    local entities = entitiesFolder()
    model = entities and entities:FindFirstChild(player.Name)
    return model and model:IsA("Model") and model or nil
end

local function livePlayerHumanoid(player)
    local model = livePlayerModel(player)
    return model and model:FindFirstChildOfClass("Humanoid") or nil
end

function PlayerToolsService.GetNames()
    local names = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            table.insert(names, player.Name)
        end
    end
    table.sort(names, function(a, b)
        return string.lower(a) < string.lower(b)
    end)
    if #names == 0 then
        return {"No other players"}
    end
    return names
end

function PlayerToolsService.Resolve(name)
    if not name or name == "" or name == "No other players" then
        return nil
    end
    return Players:FindFirstChild(name)
end

function PlayerToolsService.Spectate(name)
    local player = PlayerToolsService.Resolve(name)
    local hum = livePlayerHumanoid(player)
    local camera = Workspace.CurrentCamera

    if not player or not hum or hum.Health <= 0 or not camera then
        return false, "player unavailable"
    end

    camera.CameraSubject = hum
    return true, player.Name
end

function PlayerToolsService.StopSpectate()
    local camera = Workspace.CurrentCamera
    local hum = humanoid()
    if not camera or not hum then
        return false
    end
    camera.CameraSubject = hum
    return true
end

function PlayerToolsService.TeleportTo(name)
    local player = PlayerToolsService.Resolve(name)
    local model = livePlayerModel(player)
    local target = objectRoot(model)
    if not player or not target or not rootPart() then
        return false, "player unavailable"
    end

    local look = target.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    flat = flat.Magnitude > 0.05 and flat.Unit or Vector3.new(0, 0, -1)

    local position = target.Position - flat * 4 + Vector3.new(0, 0.5, 0)
    local goal = motionYawCFrame(position, target.Position)
    return MotionController.Request(
        "Manual",
        goal,
        {
            Kind = "manual",
            FacePosition = target.Position,
            Speed = Config.TweenSpeed,
            ArrivalDistance = 1.5,
        }
    )
end

-- ============================================================
-- Server tools
-- ============================================================

ServerToolsService = {}

local function requestJson(url)
    local body
    local ok = pcall(function()
        body = game:HttpGet(url)
    end)

    if (not ok or type(body) ~= "string") and type(requestFn) == "function" then
        local okRequest, response = pcall(requestFn, {
            Url = url,
            Method = "GET",
            Headers = { ["User-Agent"] = "SON-HUB-Nexomia" },
        })
        if okRequest and type(response) == "table" then
            body = response.Body or response.body
        end
    end

    if type(body) ~= "string" or body == "" then
        return nil, "http unavailable"
    end

    local okDecode, data = pcall(HttpService.JSONDecode, HttpService, body)
    if not okDecode or type(data) ~= "table" then
        return nil, "invalid server response"
    end

    return data
end

function ServerToolsService.GetInfo()
    local ping = "?"
    pcall(function()
        ping = string.format("%.0f ms", LocalPlayer:GetNetworkPing() * 1000)
    end)

    return table.concat({
        "PlaceId: " .. tostring(game.PlaceId),
        "JobId: " .. tostring(game.JobId ~= "" and game.JobId or "Studio/unknown"),
        "Players: " .. tostring(#Players:GetPlayers()) .. "/" .. tostring(Players.MaxPlayers),
        "Ping: " .. tostring(ping),
        "World: " .. PlayerState.GetWorld(),
    }, "\n")
end

function ServerToolsService.JoinJob(jobId)
    jobId = normalize(jobId)
    if jobId == "" then
        return false, "empty JobId"
    end

    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, jobId, LocalPlayer)
    end)
    return ok, ok and jobId or tostring(err)
end

function ServerToolsService.Rejoin()
    if game.JobId and game.JobId ~= "" then
        return ServerToolsService.JoinJob(game.JobId)
    end

    local ok, err = pcall(function()
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end)
    return ok, ok and "rejoining" or tostring(err)
end

function ServerToolsService.Hop()
    local cursor = nil
    local candidates = {}

    for _ = 1, 3 do
        local url = string.format(
            "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100%s",
            game.PlaceId,
            cursor and ("&cursor=" .. HttpService:UrlEncode(cursor)) or ""
        )

        local data, err = requestJson(url)
        if not data then
            return false, err
        end

        for _, server in ipairs(data.data or {}) do
            if server.id
                and server.id ~= game.JobId
                and tonumber(server.playing or 0) < tonumber(server.maxPlayers or 0) then
                table.insert(candidates, server)
            end
        end

        if #candidates > 0 or not data.nextPageCursor then
            break
        end
        cursor = data.nextPageCursor
    end

    table.sort(candidates, function(a, b)
        local ap = tonumber(a.playing) or math.huge
        local bp = tonumber(b.playing) or math.huge
        if ap ~= bp then
            return ap < bp
        end
        return tostring(a.id) < tostring(b.id)
    end)

    local server = candidates[1]
    if not server then
        return false, "no public server found"
    end

    return ServerToolsService.JoinJob(server.id)
end

-- ============================================================
-- Safe game-structure tests
-- ============================================================

TestService = {}

function TestService.StructureReport()
    local qte = qteScreen()
    local events = qte
        and qte:FindFirstChild("QTEClient")
        and qte.QTEClient:FindFirstChild("Events")

    local rows = {
        "Runtime index: " .. tostring(Runtime.IndexReady),
        "Entities: " .. tostring(entitiesFolder() ~= nil),
        "Quest UI: " .. tostring(questScrollingFrame() ~= nil),
        "Radar stats: " .. tostring(radarFrame() ~= nil),
        "Fishing UI: " .. tostring(fishingGui() ~= nil),
        "Gridshot: " .. tostring(events and events:FindFirstChild("Gridshot") ~= nil),
        "Spam Click: " .. tostring(events and events:FindFirstChild("Spam Click") ~= nil),
        "Timed Release: " .. tostring(events and events:FindFirstChild("Timed Release") ~= nil),
        "Mining QTE: " .. tostring(events and events:FindFirstChild("Mining") ~= nil),
        "Ore cache: " .. tostring(next(Runtime.Ores) ~= nil),
        "MobZones: " .. tostring(mobZoneRoot() ~= nil),
        "MobZone entries: " .. tostring((function()
            MobZoneService.Rebuild(false)
            local count = 0
            for _, list in pairs(MobZoneService.ByMob) do count += #list end
            return count
        end)()),
        "Islands: " .. tostring(Workspace:FindFirstChild("Islands") ~= nil),
    }
    return table.concat(rows, "\n")
end

function TestService.DuplicationRiskReport()
    local roots = {
        ReplicatedStorage:FindFirstChild("Events"),
        ReplicatedStorage:FindFirstChild("Remotes"),
    }
    local categories = {
        Inventory = {"inventory", "item", "equip", "unequip"},
        Economy = {"buy", "sell", "store", "bank"},
        Rewards = {"claim", "reward", "chest"},
        Transfer = {"trade", "give", "transfer", "drop"},
        Persistence = {"save", "load"},
    }
    local counts = {}
    for name in pairs(categories) do counts[name] = 0 end

    for _, root in ipairs(roots) do
        if root then
            for _, object in ipairs(root:GetDescendants()) do
                if object:IsA("RemoteEvent") or object:IsA("RemoteFunction") then
                    local name = lower(object.Name)
                    for category, words in pairs(categories) do
                        for _, word in ipairs(words) do
                            if name:find(word, 1, true) then
                                counts[category] += 1
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    return table.concat({
        "Read-only consistency review; no transaction remote is called.",
        "Inventory surfaces: " .. tostring(counts.Inventory),
        "Economy surfaces: " .. tostring(counts.Economy),
        "Reward surfaces: " .. tostring(counts.Rewards),
        "Transfer surfaces: " .. tostring(counts.Transfer),
        "Persistence surfaces: " .. tostring(counts.Persistence),
        "Use this only to identify areas that need server-side idempotency/validation.",
    }, "\n")
end

-- ============================================================
-- Character movement service
-- ============================================================

MovementService = {}

local function restoreCollision()
    for part, canCollide in pairs(
        Runtime.CharacterCollisionBackup
    ) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = canCollide
            end)
        end

        Runtime.CharacterCollisionBackup[part] = nil
    end
end

local function applyCharacterNoclip()
    local char = character()
    if not char then
        return
    end

    for _, object in ipairs(
        char:GetDescendants()
    ) do
        if object:IsA("BasePart") then
            if Runtime.CharacterCollisionBackup[object]
                == nil then

                Runtime.CharacterCollisionBackup[object] =
                    object.CanCollide
            end

            object.CanCollide = false
        end
    end
end

function MovementService.Step()
    local hum = humanoid()
    if not hum then
        return
    end

    if Config.SpeedOverride then
        pcall(function()
            hum.WalkSpeed = Config.WalkSpeed
        end)
    end

    if Config.JumpOverride then
        pcall(function()
            hum.UseJumpPower = true
            hum.JumpPower = Config.JumpPower
        end)
    end

    local transportNoclip =
        Config.PlatformNoclip
        and (
            Runtime.Motion.Owner ~= nil
            or Runtime.Motion.Active
            or Runtime.Motion.Hold
            or Config.AutoProgress
        )

    if Config.Noclip
        or transportNoclip then

        applyCharacterNoclip()
    elseif next(
        Runtime.CharacterCollisionBackup
    ) ~= nil then
        restoreCollision()
    end
end

connect(
    UserInputService.JumpRequest,
    function()
        if Config.InfiniteJump then
            local hum = humanoid()
            if hum then
                pcall(function()
                    hum:ChangeState(
                        Enum.HumanoidStateType.Jumping
                    )
                end)
            end
        end
    end
)

-- ============================================================
-- Schedulers
-- ============================================================

task.spawn(function()
    while Core.Running do
        safeWorker("Movement", MovementService.Step)
        task.wait(
            (
                Config.SpeedOverride
                or Config.JumpOverride
                or Config.Noclip
                or Config.PlatformNoclip
            )
            and 0.08
            or 0.45
        )
    end
end)


task.spawn(function()
    while Core.Running do
        safeWorker("Progress", AutoFarmController.Step)
        task.wait(Config.AutoProgress and 0.20 or 0.65)
    end
end)

task.spawn(function()
    while Core.Running do
        local delay = safeWorker("Fishing", FishingService.Step)
        task.wait(tonumber(delay) or 0.65)
    end
end)

task.spawn(function()
    while Core.Running do
        local delay = safeWorker("Mining", MiningQTEService.Step)
        task.wait(tonumber(delay) or 0.65)
    end
end)

task.spawn(function()
    while Core.Running do
        local promptActive =
            Config.AutoPickup
            or Config.AutoChest
            or Config.AutoWorldBossChest
            or Config.AutoFruitChest
            or Config.AutoQuestItems
            or Config.AutoFarming
            or (
                Config.AutoProgress
                and Runtime.ProgressLifeSkill == "Farming"
            )

        if promptActive then
            safeWorker("Prompts", LifeSkillService.StepPrompts)
            task.wait(0.30)
        else
            task.wait(0.95)
        end
    end
end)

task.spawn(function()
    while Core.Running do
        if Config.AutoStats then
            safeWorker("Stats", StatsService.SpendOne)
            task.wait(math.max(0.15, Config.StatSpendInterval))
        else
            task.wait(0.95)
        end
    end
end)

task.spawn(function()
    while Core.Running do
        safeWorker("Block", CombatService.BlockStep)
        task.wait(Config.AutoBlock and 0.14 or 0.8)
    end
end)

task.spawn(function()
    while Core.Running do
        if Config.AutoClaim then
            safeWorker(
                "Claims",
                InteractionService.ProcessClaimButtons
            )
        end

        task.wait(Config.AutoClaim and 0.85 or 1.5)
    end
end)

task.spawn(function()
    while Core.Running do
        if Config.MobHitbox then
            safeWorker("Hitbox", HitboxService.Step)
        elseif next(Core.HitboxBackup) ~= nil then
            safeWorker("Hitbox", HitboxService.RestoreAll)
        end
        task.wait(Config.MobHitbox and 0.25 or 1.0)
    end
end)

task.spawn(function()
    while Core.Running do
        local active =
            Config.CurrentTargetESP
            or Config.PlayerESP
            or Config.MobESP
            or Config.BossESP
            or Config.LootESP

        if active then
            safeWorker("ESP", ESPService.Step)
        end

        task.wait(active and 0.9 or 1.8)
    end
end)

task.spawn(function()
    while Core.Running do
        if Config.AntiAFK and VirtualUser then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.zero)
            end)
        end

        task.wait(55)
    end
end)

task.spawn(function()
    while Core.Running do
        local level = PlayerState.GetLevel()

        if Runtime.LastLevel == nil then
            Runtime.LastLevel = level
        elseif Runtime.LastLevel ~= level then
            local previous = Runtime.LastLevel
            Runtime.LastLevel = level

            notify(
                "Level Up",
                string.format(
                    "Lv.%d -> Lv.%d | progression refreshed",
                    previous,
                    level
                ),
                4
            )

            Runtime.FarmAnchorCFrame = nil
            QuestService.ClearTaskLock()
            FarmMovement.Stop(true, true)
        end

        task.wait(0.55)
    end
end)

-- ============================================================
-- NPC Navigator
-- ============================================================

NPCNavigator = {}

local NAV_NPCS = {
    ["Fishing NPC — Fisherman Jack"] = "Fisherman Jack",
    ["Blacksmith — Shinozaki"] = "Blacksmith Shinozaki",
    ["Merchant"] = "Merchant",
    ["Miner — Song Jil Wu"] = "Miner Song Jil Wu",
    ["Miner — Song Kim Wu"] = "Miner Song Kim Wu",
}

function NPCNavigator.GetNames()
    local result = {}

    for display in pairs(NAV_NPCS) do
        table.insert(result, display)
    end

    table.sort(result)
    return result
end

function NPCNavigator.Resolve(displayOrName)
    local targetName =
        NAV_NPCS[displayOrName]
        or displayOrName

    return TargetService.FindNamedDialogueNPC(
        targetName
    )
end

function NPCNavigator.GoTo(displayOrName)
    local npc = NPCNavigator.Resolve(displayOrName)

    if not npc then
        notify(
            "NPC Navigation",
            "NPC not found: " .. tostring(displayOrName),
            4
        )
        return false
    end

    local prompt = InteractionService.FindPromptNear(npc, "Dialogue")
    local goal = FarmMovement.GetInteractionGoal(npc, prompt)
    local target = objectRoot(prompt) or objectRoot(npc)

    if not goal or not target then
        return false
    end

    Runtime.CurrentTarget = npc

    MotionController.Request(
        "Manual",
        goal,
        {
            Kind = "manual",
            FacePosition = target.Position,
            ArrivalDistance = 1.4,
        }
    )

    return true
end

-- ============================================================
-- Island Navigation
-- ============================================================

IslandService = {}

local ISLAND_LANDING_HINTS = {
    ["Maple Village"] = {
        "MapleVillageMissionSite1",
        "MapleVillageMissionSite2",
        "MapleVillageMissionSite3",
    },

    ["Anchor Town"] = {
        "AnchorTownTown1",
        "AnchorMissionSite1",
        "AnchorMissionSite3",
    },

    ["Clown Town"] = {
        "ClownTownMissionSIte1",
        "ClownTownMissionSIte2",
    },
}

local function islandsRoot()
    return Workspace:FindFirstChild("Islands")
end

function IslandService.GetNames()
    local root = islandsRoot()
    local result = {}

    if root then
        for _, child in ipairs(root:GetChildren()) do
            if child:IsA("Folder") or child:IsA("Model") then
                table.insert(result, child.Name)
            end
        end
    end

    table.sort(result)

    if #result == 0 then
        return {"Islands unavailable"}
    end

    return result
end

function IslandService.FindLanding(name)
    local cached = Runtime.IslandLandingCache[name]

    if cached and cached.Parent then
        return cached
    end

    local root = islandsRoot()
    local island = root and root:FindFirstChild(name)

    if not island then
        return nil
    end

    for _, hint in ipairs(ISLAND_LANDING_HINTS[name] or {}) do
        local object = island:FindFirstChild(hint, true)
        local part = objectRoot(object)

        if part then
            Runtime.IslandLandingCache[name] = part
            return part
        end
    end

    local spawnLocations =
        island:FindFirstChild("SpawnLocations")

    if spawnLocations then
        local part =
            spawnLocations:FindFirstChildWhichIsA(
                "BasePart",
                true
            )

        if part then
            Runtime.IslandLandingCache[name] = part
            return part
        end
    end

    for _, object in ipairs(island:GetDescendants()) do
        if object:IsA("BasePart")
            and object:GetAttribute("Island") == name
            and object:GetAttribute("Touch") == "QuestZone" then

            Runtime.IslandLandingCache[name] = object
            return object
        end
    end

    return nil
end

function IslandService.Teleport(name)
    local landing = IslandService.FindLanding(name)
    if not landing or not rootPart() then
        notify("Island", "No landing point: " .. tostring(name), 4)
        return false
    end

    local goal = landing.CFrame * CFrame.new(0, 5, 0)
    local ok = MotionController.Request(
        "Manual",
        goal,
        {
            Kind = "manual",
            FacePosition = landing.Position,
            Speed = Config.TweenSpeed,
            ArrivalDistance = 1.6,
        }
    )

    if ok then
        notify("Island", "Moving to " .. name, 3)
    end

    return ok == true
end

-- ============================================================
-- UI helpers
-- ============================================================

local function currentQuestSummary()
    local completed = QuestService.GetCompletedQuest()
    if completed then
        return completed.Name .. " → ready to turn in"
    end

    local quest, taskData = QuestService.GetStableTask()
    if quest and taskData then
        return quest.Name .. " → " .. taskData.Text
    end

    local recommended = QuestService.GetRecommended()
    if recommended then
        return "Recommended → " .. recommended.Name
    end

    return "None"
end

local function runtimeStatus()
    return table.concat({
        "SON HUB v" .. VERSION,
        "Level: " .. tostring(PlayerState.GetLevel()),
        "World: " .. PlayerState.GetWorld(),
        "Fruit: " .. PlayerState.GetFruit()
            .. " (Lv." .. PlayerState.GetFruitLevel() .. ")",
        "Bounty: " .. tostring(PlayerState.GetLeaderValue("Bounty") or 0),
        "Faction: " .. tostring(PlayerState.GetLeaderValue("Faction") or "None"),
        "Crew: " .. tostring(PlayerState.GetLeaderValue("Crew") or "None"),
        "Quest: " .. currentQuestSummary(),
        "Progress: " .. Runtime.ProgressState
            .. " • " .. Runtime.ProgressDetail,
        "Farm FSM: " .. tostring(Runtime.FarmFSM.State),
        "Motion: "
            .. tostring(Runtime.Motion.Owner or "None")
            .. " • active=" .. tostring(Runtime.Motion.Active)
            .. " • hold=" .. tostring(Runtime.Motion.Hold),
        "Wanted mob: "
            .. tostring(Runtime.CurrentWantedMob or "None"),
        "Hotbar: " .. HotbarService.GetSnapshot(),
        "Quest catalog: " .. tostring(#Runtime.QuestCatalog),
    }, "\n")
end

local function detectedSystems()
    return table.concat({
        "151 Quest modules + live RecommendedQuest",
        "DialogueNPC QuestName / QuestNode mapping",
        "Entities / Combat / BossCombat",
        "Fluent UI direct API / Nexomia compatibility",
        "Heartbeat moving platform transport",
        "Fixed MobZone gather + live entity-state filtering",
        "Custom 0-9 Hotbar + Cooldown/EXP",
        "Auto Stats via Radar stat buttons",
        "Skill EXP / hotbar cooldown detection",
        "Fishing: SHAKE / CLICK / Timed Release / Reel",
        "Mining Critical Zone QTE",
        "Fishing / Mining / Farming",
        "Fruit / FruitLevel",
        "Bounty / Faction / Crew",
        "Pickup / Chest / Fruit Chest / World Boss Chest",
        "Treasure / DigSpots",
        "Logbook Claim",
        "Block = F",
    }, "\n")
end


local function workerHealth()
    local rows = {
        "Progress state: " .. tostring(Runtime.ProgressState),
        "Detail: " .. tostring(Runtime.ProgressDetail),
        "Fishing: " .. tostring(Runtime.FishingState),
        "Mining: " .. tostring(Runtime.MiningState),
        "Treasure: " .. tostring(Runtime.TreasureState),
        "",
    }

    local order = {
        "Progress",
        "Fishing",
        "Mining",
        "Treasure",
        "Prompts",
        "Stats",
        "Block",
        "Claims",
        "Hitbox",
        "ESP",
    }

    for _, name in ipairs(order) do
        table.insert(
            rows,
            name
                .. " ticks: "
                .. tostring(Runtime.WorkerTicks[name] or 0)
        )

        local err = Runtime.WorkerErrors[name]
        if err then
            table.insert(
                rows,
                name
                    .. " ERROR: "
                    .. tostring(err):gsub("\n", " "):sub(1, 180)
            )
        end
    end

    return table.concat(rows, "\n")
end

local function executorStatus()
    return table.concat({
        "loadstring: " .. tostring(type(loadstring) == "function"),
        "HTTP: " .. tostring(ExecutorCaps.Http),
        "request fallback: " .. tostring(ExecutorCaps.Request),
        "VirtualInput: " .. tostring(ExecutorCaps.VirtualInput),
        "fireproximityprompt: " .. tostring(ExecutorCaps.FirePrompt),
        "firesignal: " .. tostring(ExecutorCaps.FireSignal),
        "setclipboard: " .. tostring(ExecutorCaps.Clipboard),
        "UNC mode: capability-based (partial support OK)",
        "WebSocket: not required",
        "getscriptclosure: not required",
        "filesystem: not required",
    }, "\n")
end

local function selfTest()
    local rows = {}

    local function add(name, value)
        table.insert(
            rows,
            (value and "[OK] " or "[--] ") .. tostring(name)
        )
    end

    add("Fluent", Fluent ~= nil)
    add("Player ready", PlayerState.IsReady())
    add("Quest UI", questScrollingFrame() ~= nil)
    add("RecommendedQuest storage", questStorage() ~= nil)
    add("Entities", entitiesFolder() ~= nil)
    add("DialogueNPCs", dialogueRoot() ~= nil)
    add("Dialogue E input", VirtualInputManager ~= nil)
    add("World marker cache", Runtime.WorldMarkers ~= nil)
    add("Hotbar", findHotbar() ~= nil)
    add("Quest catalog", #Runtime.QuestCatalog > 0)
    add("Runtime index", Runtime.IndexReady)
    add("Fishing UI", fishingGui() ~= nil)
    add("QTE UI", qteScreen() ~= nil)
    add("Ore cache", next(Runtime.Ores) ~= nil)
    add("DigSpot cache", next(Runtime.DigSpots) ~= nil)

    return table.concat(rows, "\n")
end


-- ============================================================
-- Fluent UI
-- ============================================================

local Window = Fluent:CreateWindow({
    Title = "SON HUB " .. VERSION,
    SubTitle = "Nexomia | hongson",
    TabWidth = 150,
    Size = UDim2.fromOffset(720, 520),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl,
})

local Tabs = {
    Home = Window:AddTab({Title = "Home", Icon = "home"}),
    Minigame = Window:AddTab({Title = "Minigame", Icon = "gamepad-2"}),
    Player = Window:AddTab({Title = "Player", Icon = "user"}),
    Teleport = Window:AddTab({Title = "Teleport", Icon = "map-pin"}),
    Settings = Window:AddTab({Title = "Settings", Icon = "settings"}),
    Test = Window:AddTab({Title = "Test", Icon = "flask-conical"}),
}

local function bindToggle(section, id, title, defaultValue, callback)
    local option = section:AddToggle(id, {
        Title = title,
        Default = defaultValue == true,
    })
    option:OnChanged(function()
        callback(option.Value)
    end)
    return option
end

local function bindDropdown(section, id, title, values, defaultIndex, callback)
    local option = section:AddDropdown(id, {
        Title = title,
        Values = values,
        Multi = false,
        Default = defaultIndex or 1,
    })
    option:OnChanged(function(value)
        callback(value)
    end)
    return option
end

local function bindSlider(section, id, title, minimum, maximum, defaultValue, callback)
    return section:AddSlider(id, {
        Title = title,
        Default = defaultValue,
        Min = minimum,
        Max = maximum,
        Rounding = 0,
        Callback = callback,
    })
end

local function setDropdownValues(dropdown, values)
    if dropdown and type(dropdown.SetValues) == "function" then
        pcall(function()
            dropdown:SetValues(values)
        end)
    end
end

-- Home
local FarmSection = Tabs.Home:AddSection("Auto Farm")

bindToggle(FarmSection, "AutoFarm", "Auto Farm", Config.AutoProgress, function(value)
    Config.AutoProgress = value
    Runtime.ProgressLifeSkill = nil
    Runtime.CurrentTarget = nil
    Runtime.CurrentWantedMob = nil
    Runtime.FarmFSM.TaskKey = nil
    QuestService.ClearTaskLock()
    MobGatherService.Reset()

    if value then
        Config.AutoQuest = true
        Config.AutoAcceptRecommended = true
        Config.AutoTurnIn = true
        Config.AutoDialogue = true
        QuestCatalogService.Build()
    else
        MotionController.Release(Runtime.Motion.Owner, true)
        restoreCollision()
    end
end)

bindDropdown(
    FarmSection,
    "FarmMode",
    "Farm Mode",
    {"Smart Quest", "Selected Mob", "Boss"},
    1,
    function(value)
        Config.FarmMode = value
        Runtime.CurrentTarget = nil
        Runtime.FarmFSM.TaskKey = nil
        MobGatherService.Reset()
    end
)

local mobDropdown = bindDropdown(
    FarmSection,
    "SelectedMob",
    "Target Mob",
    TargetService.GetMobOptions(),
    1,
    function(value)
        Config.SelectedMob = value
        Runtime.CurrentTarget = nil
        MobGatherService.Reset()
    end
)

FarmSection:AddButton({
    Title = "Refresh Mobs",
    Callback = function()
        setDropdownValues(mobDropdown, TargetService.GetMobOptions())
    end,
})

bindToggle(FarmSection, "AutoGather", "M1 Lure", Config.AutoGather, function(value)
    Config.AutoGather = value
    MobGatherService.Reset()
end)

bindToggle(FarmSection, "AutoAttack", "Auto M1", Config.AutoAttack, function(value)
    Config.AutoAttack = value
end)

bindSlider(FarmSection, "AttackRate", "M1 / sec", 1, 15, Config.AttackRate, function(value)
    Config.AttackRate = value
end)

local CombatSection = Tabs.Home:AddSection("Combat Position")

bindSlider(CombatSection, "CombatDistance", "M1 Distance", 3, 7, Config.CombatDistance, function(value)
    Config.CombatDistance = value
end)

bindSlider(CombatSection, "FarmAnchorHeight", "Anchor Y Offset", 0, 3, Config.FarmAnchorHeight, function(value)
    Config.FarmAnchorHeight = value
    MobGatherService.Reset()
end)

bindToggle(CombatSection, "MobHitbox", "Mob Hitbox", Config.MobHitbox, function(value)
    Config.MobHitbox = value
    if not value then
        HitboxService.RestoreAll()
    else
        HitboxService.Step()
    end
end)

bindSlider(CombatSection, "MobHitboxSize", "Hitbox Size", 4, 20, Config.MobHitboxSize, function(value)
    Config.MobHitboxSize = value
end)

local HomeState = Tabs.Home:AddSection("State")
HomeState:AddButton({
    Title = "Current State",
    Callback = function()
        notify(
            "SON HUB",
            currentQuestSummary()
                .. "\nState: " .. tostring(Runtime.ProgressState)
                .. "\nDetail: " .. tostring(Runtime.ProgressDetail),
            9
        )
    end,
})

-- Minigame
local MiningSection = Tabs.Minigame:AddSection("Mining")

bindToggle(MiningSection, "AutoMining", "Auto Mining", Config.AutoMining, function(value)
    Config.AutoMining = value
    MiningQTEService.Reset(value and "Enabled" or "Disabled")
    if value then
        MiningQTEService.RefreshOreIndex(true)
    end
end)

bindDropdown(
    MiningSection,
    "MiningMode",
    "Ore Mode",
    {"Any Available", "Highest Drop", "Selected Ore", "Quest Required"},
    1,
    function(value)
        Config.MiningMode = value
        MiningQTEService.Reset("Mode changed")
    end
)

local oreDropdown = bindDropdown(
    MiningSection,
    "SelectedOre",
    "Selected Ore",
    MiningQTEService.GetOreOptions(),
    1,
    function(value)
        Config.SelectedOre = value
        MiningQTEService.Reset("Ore changed")
    end
)

MiningSection:AddButton({
    Title = "Refresh Ores",
    Callback = function()
        MiningQTEService.RefreshOreIndex(true)
        setDropdownValues(oreDropdown, MiningQTEService.GetOreOptions())
        notify("Mining", "Ore index refreshed", 3)
    end,
})

MiningSection:AddButton({
    Title = "Mining Status",
    Callback = function()
        local target = Runtime.MiningTarget
        notify(
            "Mining",
            "State: " .. tostring(Runtime.MiningState)
                .. "\nTarget: " .. tostring(target and oreName(target) or "None")
                .. "\nDetail: " .. tostring(Runtime.ProgressDetail),
            8
        )
    end,
})

local FishingSection = Tabs.Minigame:AddSection("Fishing")

bindToggle(FishingSection, "AutoFishing", "Auto Fishing", Config.AutoFishing, function(value)
    Config.AutoFishing = value
    FishingService.Reset(value and "Enabled" or "Disabled")
end)

bindDropdown(
    FishingSection,
    "FishingSpotMode",
    "Fishing Spot",
    {"Anchor Town Pond", "Saved Position", "Current Position"},
    1,
    function(value)
        Config.FishingSpotMode = value
        FishingService.Reset("Spot changed")
    end
)

FishingSection:AddButton({
    Title = "Save Current Spot",
    Callback = function()
        local root = rootPart()
        if root then
            Runtime.FishingSpotCFrame = root.CFrame
            Config.FishingSpotMode = "Saved Position"
            FishingService.Reset("Spot saved")
            notify("Fishing", "Saved current position", 3)
        end
    end,
})

FishingSection:AddButton({
    Title = "Fishing Status",
    Callback = function()
        local data = FishingService.GetConditions()
        notify(
            "Fishing",
            "State: " .. tostring(data.State)
                .. "\nRod: " .. tostring(data.Rod) .. " [" .. tostring(data.RodSource) .. "]"
                .. "\nBait: " .. tostring(data.Bait) .. " x" .. tostring(data.BaitAmount)
                .. "\nSpot: " .. tostring(data.Spot)
                .. "\nReady: " .. tostring(data.CanStart),
            9
        )
    end,
})

-- Player
local StatsSection = Tabs.Player:AddSection("Auto Stats")

bindToggle(StatsSection, "AutoStats", "Auto Stats", Config.AutoStats, function(value)
    Config.AutoStats = value
end)

bindDropdown(
    StatsSection,
    "StatBuild",
    "Build",
    {"Auto", "Balanced", "Strength", "Precision", "Tank", "Mobility", "Haki"},
    1,
    function(value)
        Config.StatBuild = value
    end
)

StatsSection:AddButton({
    Title = "Stats Status",
    Callback = function()
        notify("Stats", StatsService.GetSnapshot(), 8)
    end,
})

local ESPSection = Tabs.Player:AddSection("ESP")
bindToggle(ESPSection, "PlayerESP", "Player ESP", Config.PlayerESP, function(value)
    Config.PlayerESP = value
end)
bindToggle(ESPSection, "MobESP", "Mob ESP", Config.MobESP, function(value)
    Config.MobESP = value
end)
bindToggle(ESPSection, "BossESP", "Boss ESP", Config.BossESP, function(value)
    Config.BossESP = value
end)
bindToggle(ESPSection, "TargetESP", "Current Target ESP", Config.CurrentTargetESP, function(value)
    Config.CurrentTargetESP = value
end)
bindToggle(ESPSection, "LootESP", "Loot ESP", Config.LootESP, function(value)
    Config.LootESP = value
end)

local CameraSection = Tabs.Player:AddSection("Player Camera")
local cameraPlayerNames = PlayerToolsService.GetNames()
local selectedCameraPlayer = cameraPlayerNames[1]
local cameraDropdown = bindDropdown(
    CameraSection,
    "CameraPlayer",
    "Player",
    cameraPlayerNames,
    1,
    function(value)
        selectedCameraPlayer = value
    end
)

CameraSection:AddButton({
    Title = "Refresh Players",
    Callback = function()
        setDropdownValues(cameraDropdown, PlayerToolsService.GetNames())
    end,
})

CameraSection:AddButton({
    Title = "Spectate",
    Callback = function()
        local ok, reason = PlayerToolsService.Spectate(selectedCameraPlayer)
        notify("Camera", ok and ("Spectating " .. tostring(reason)) or tostring(reason), 3)
    end,
})

CameraSection:AddButton({
    Title = "Stop Spectate",
    Callback = function()
        PlayerToolsService.StopSpectate()
    end,
})

-- Teleport
local IslandSection = Tabs.Teleport:AddSection("Islands")
local islandNames = IslandService.GetNames()
local selectedIsland = islandNames[1]
local islandDropdown = bindDropdown(
    IslandSection,
    "Island",
    "Island",
    islandNames,
    1,
    function(value)
        selectedIsland = value
    end
)

IslandSection:AddButton({
    Title = "Refresh Islands",
    Callback = function()
        setDropdownValues(islandDropdown, IslandService.GetNames())
    end,
})

IslandSection:AddButton({
    Title = "Tween To Island",
    Callback = function()
        if selectedIsland then
            IslandService.Teleport(selectedIsland)
        end
    end,
})

local PlayerTeleportSection = Tabs.Teleport:AddSection("Players")
local teleportPlayerNames = PlayerToolsService.GetNames()
local selectedTeleportPlayer = teleportPlayerNames[1]
local playerTeleportDropdown = bindDropdown(
    PlayerTeleportSection,
    "TeleportPlayer",
    "Player",
    teleportPlayerNames,
    1,
    function(value)
        selectedTeleportPlayer = value
    end
)

PlayerTeleportSection:AddButton({
    Title = "Refresh Players",
    Callback = function()
        setDropdownValues(playerTeleportDropdown, PlayerToolsService.GetNames())
    end,
})

PlayerTeleportSection:AddButton({
    Title = "Tween To Player",
    Callback = function()
        local ok, reason = PlayerToolsService.TeleportTo(selectedTeleportPlayer)
        if not ok then
            notify("Teleport", tostring(reason), 4)
        end
    end,
})

-- Settings
local MovementSection = Tabs.Settings:AddSection("Movement")

bindSlider(MovementSection, "TweenSpeed", "Tween Speed", 50, 450, Config.TweenSpeed, function(value)
    Config.TweenSpeed = value
    Config.PlatformSpeed = value
end)

bindToggle(MovementSection, "SpeedOverride", "WalkSpeed Override", Config.SpeedOverride, function(value)
    Config.SpeedOverride = value
end)
bindSlider(MovementSection, "WalkSpeed", "WalkSpeed", 16, 100, Config.WalkSpeed, function(value)
    Config.WalkSpeed = value
end)
bindToggle(MovementSection, "JumpOverride", "JumpPower Override", Config.JumpOverride, function(value)
    Config.JumpOverride = value
end)
bindSlider(MovementSection, "JumpPower", "JumpPower", 50, 140, Config.JumpPower, function(value)
    Config.JumpPower = value
end)
bindToggle(MovementSection, "InfiniteJump", "Infinite Jump", Config.InfiniteJump, function(value)
    Config.InfiniteJump = value
end)
bindToggle(MovementSection, "Noclip", "Noclip", Config.Noclip, function(value)
    Config.Noclip = value
    if not value and not Runtime.Motion.Owner then
        restoreCollision()
    end
end)
bindToggle(MovementSection, "AntiAFK", "Anti AFK", Config.AntiAFK, function(value)
    Config.AntiAFK = value
end)

local ServerSection = Tabs.Settings:AddSection("Server")
ServerSection:AddButton({
    Title = "Server Info",
    Callback = function()
        notify("Server", ServerToolsService.GetInfo(), 10)
    end,
})
ServerSection:AddButton({
    Title = "Rejoin Server",
    Callback = function()
        local ok, reason = ServerToolsService.Rejoin()
        if not ok then
            notify("Rejoin", tostring(reason), 5)
        end
    end,
})
ServerSection:AddButton({
    Title = "Server Hop",
    Callback = function()
        task.spawn(function()
            local ok, reason = ServerToolsService.Hop()
            if not ok then
                notify("Server Hop", tostring(reason), 5)
            end
        end)
    end,
})

local joinJobId = ""
ServerSection:AddInput("JoinServerJobId", {
    Title = "Server UID / JobId",
    Default = "",
    Placeholder = "Paste JobId",
    Numeric = false,
    Finished = true,
    Callback = function(value)
        joinJobId = tostring(value or "")
    end,
})
ServerSection:AddButton({
    Title = "Join Server UID",
    Callback = function()
        local ok, reason = ServerToolsService.JoinJob(joinJobId)
        if not ok then
            notify("Join Server", tostring(reason), 5)
        end
    end,
})

local ScriptSection = Tabs.Settings:AddSection("Script")
ScriptSection:AddButton({
    Title = "Unload SON HUB",
    Callback = function()
        if type(ENV.__SON_HUB_UNLOAD) == "function" then
            ENV.__SON_HUB_UNLOAD()
        end
    end,
})

-- Test
local TestSection = Tabs.Test:AddSection("Diagnostics")
TestSection:AddButton({
    Title = "Game Structure",
    Callback = function()
        notify("Game Structure", TestService.StructureReport(), 12)
    end,
})
TestSection:AddButton({
    Title = "Runtime Self Test",
    Callback = function()
        notify("Self Test", selfTest(), 12)
    end,
})
TestSection:AddButton({
    Title = "Worker Health",
    Callback = function()
        notify("Worker Health", workerHealth(), 14)
    end,
})
TestSection:AddButton({
    Title = "Refresh Index",
    Callback = function()
        task.spawn(function()
            RuntimeIndex.Rebuild()
            QuestCatalogService.Build()
            MobZoneService.Rebuild(true)
            MiningQTEService.RefreshOreIndex(true)
            HotbarService.Refresh()
            notify("Index", "Refreshed", 3)
        end)
    end,
})

local CleanSection = Tabs.Settings:AddSection("Clean / Compatibility")
CleanSection:AddButton({
    Title = "Clean Runtime State",
    Callback = function()
        HitboxService.RestoreAll()
        restoreCollision()
        MotionController.Release(Runtime.Motion.Owner, true)
        FishingService.Reset("Manual clean")
        MiningQTEService.Reset("Manual clean")
        Runtime.CurrentTarget = nil
        Runtime.CurrentWantedMob = nil
        MobGatherService.Reset("Manual clean")
        notify("Clean", "Runtime state restored", 4)
    end,
})

CleanSection:AddButton({
    Title = "Executor Compatibility",
    Callback = function()
        notify("Compatibility", executorStatus(), 10)
    end,
})

local RiskSection = Tabs.Test:AddSection("Duplicate Risk")
RiskSection:AddButton({
    Title = "Scan Duplicate-Risk Surfaces",
    Callback = function()
        notify("Duplicate Risk", TestService.DuplicationRiskReport(), 16)
    end,
})

Window:SelectTab(1)


-- ============================================================
-- Startup / cleanup
-- ============================================================

local function unload()
    if not Core.Running then
        return
    end

    Core.Running = false

    Config.AutoProgress = false
    Config.AutoFishing = false
    Config.AutoMining = false
    Config.AutoFarming = false
    Config.AutoStats = false
    Config.AutoBlock = false
    Config.MobHitbox = false

    pcall(function()
        FishingService.Reset("Unload")
    end)

    pcall(function()
        MiningQTEService.Reset("Unload")
    end)

    pcall(function()
        PlayerToolsService.StopSpectate()
    end)

    pcall(function()
        MotionController.Release(Runtime.Motion.Owner, true)
    end)

    pcall(function()
        restoreCollision()
    end)

    pcall(function()
        HitboxService.RestoreAll()
    end)

    Runtime.BlockHeld = false

    for object in pairs(ESPService.Map) do
        ESPService.Clear(object)
    end

    for _, connection in ipairs(Core.Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(Core.Connections)

    for _, instance in ipairs(Core.Instances) do
        pcall(function()
            instance:Destroy()
        end)
    end
    table.clear(Core.Instances)

    pcall(function()
        if Fluent and type(Fluent.Destroy) == "function" then
            Fluent:Destroy()
        end
    end)

    ENV.__SON_HUB_UNLOAD = nil
end

ENV.__SON_HUB_UNLOAD = unload

task.defer(function()
    HotbarService.Refresh()

    notify(
        "SON HUB Ready",
        "Lv."
            .. tostring(PlayerState.GetLevel())
            .. " | Quest: "
            .. currentQuestSummary()
            .. "\nRun Self Test before enabling AUTO QUEST / FARM.",
        7
    )
end)
