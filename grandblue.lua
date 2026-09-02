--[[
    SON HUB v10 - Nexomia Full
    Target snapshot: PlaceId 118635363908336
    UI: Fluent direct API
    make by hongson

    Design:
      - Nexomia-safe bootstrap: no WebSocket/getscriptclosure/filesystem addons.
      - Every worker runs behind xpcall and exposes its last error.
      - One progression owner; no competing movement loops.
      - Movement uses a heartbeat-driven local platform under the player.
      - Quest/NPC/task logic comes from client-visible game structures.
      - No guessed RemoteEvent/RemoteFunction contracts.
      - Large Workspace scan occurs once; caches update incrementally.
]]

local VERSION = "14.0.0"
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
}

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
    AttackRate = 8,
    SelectedWeapon = "Auto",
    AutoMastery = false,
    MasteryMode = "All Combat",
    MasteryReadyOnly = true,
    MasteryInterval = 0.75,
    MasteryHoldTime = 0.20,

    -- Moving platform
    PlatformTransport = true,
    PlatformKinematicAssist = true,
    PlatformSpeed = 175,
    PlatformSize = 10,
    PlatformTransparency = 0.72,
    PlatformFarmHeight = 18,
    PlatformNpcHeight = 0.25,
    PlatformBackDistance = 5,
    PlatformArrivalDistance = 4,
    PlatformRetargetDistance = 12,
    TravelClearance = 11,
    TravelMaxAboveTarget = 30,
    TravelHorizontalThreshold = 22,
    FarmAnchorRecenterDistance = 55,
    FarmHoldCorrectionDistance = 5.0,
    PlatformNoclip = true,

    -- Bring + hitbox
    BringMobs = true,
    BringRadius = 165,
    BringLimit = 12,
    MobBelowFeet = 9,
    BringSpread = 1.5,

    MobHitbox = true,
    HitboxSize = 28,
    HitboxTransparency = 0.72,
    HitboxRange = 220,

    -- Combat
    AutoAim = false,
    AutoBlock = false,
    BlockHealthPercent = 40,

    -- Stats
    AutoStats = false,
    StatBuild = "Balanced",
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
    MiningMode = "Quest Required",
    SelectedOre = "Copper Ore",
    MiningCriticalTolerance = 0.035,
    MiningHoldTimeout = 5.0,
    MiningRetryDelay = 0.55,
    MiningAutoAim = true,

    AutoFarming = false,

    AutoTreasure = false,
    TreasureSearchRadius = 3500,
    TreasureDigInterval = 0.45,

    AutoFishing = false,
    FishingSpotMode = "Saved Position",
    FishingAutoReturn = true,
    FishingRequireBait = false,
    FishingBiteTimeout = 40,
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
    MobESP = false,
    BossESP = false,
    LootESP = false,
    ESPDistance = 1200,
    TargetColor = Color3.fromRGB(95, 200, 255),
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
    DigSpots = setmetatable({}, {__mode = "k"}),
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
        InteractionArrivedAt = 0,
        PromptAttemptAt = 0,
        PromptAttemptCount = 0,

        LockedQuestId = nil,
        LockedTaskOrder = nil,
        LockedTaskKind = nil,
        LockedTaskTarget = nil,
        LockedTaskUntil = 0,
    },

    FarmMovePart = nil,
    FarmMoveGoal = nil,
    FarmMoveActive = false,
    FarmMoveHold = false,
    FarmMoveHoldCFrame = nil,
    FarmMoveRoute = nil,
    FarmMoveRouteIndex = 0,
    FarmMoveFinalGoal = nil,
    FarmMoveFacePosition = nil,
    FarmMoveKind = nil,

    LootRouteTarget = nil,
    LootRouteKind = nil,
    PromptUseAt = setmetatable({}, {__mode = "k"}),

    CurrentTarget = nil,
    CurrentWantedMob = nil,
    FarmAnchorCFrame = nil,

    LastInteraction = 0,
    LastQuestChange = 0,
    LastAttack = 0,
    LastBring = 0,
    LastHitbox = 0,
    LastBringCount = 0,
    LastHitboxCount = 0,
    LastMastery = 0,
    LastStatsSpend = 0,

    TransportPart = nil,
    TransportTween = nil,
    TransportWeld = nil,
    TransportGoal = nil,
    TransportRootGoal = nil,
    TransportMoving = false,
    TransportAutoRotate = nil,
    TransportLastDistance = nil,
    TransportLastProgressAt = 0,
    TransportStartedAt = 0,

    ExpandedHitboxes = setmetatable({}, {__mode = "k"}),
    CharacterCollisionBackup = setmetatable({}, {__mode = "k"}),

    FishingState = "IDLE",
    FishingStateSince = 0,
    FishingSpotCFrame = nil,
    FishingReason = "Disabled",
    FishingHadReel = false,
    FishingMouseHeld = false,
    FishingKeyHeld = nil,
    FishingLastCast = 0,
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
    MiningReleaseDone = false,
    ProgressLifeSkill = nil,

    TreasureState = "IDLE",
    TreasureTarget = nil,
    TreasureLastDig = 0,

    ClaimButtons = setmetatable({}, {__mode = "k"}),

    MasteryCursor = 0,

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
        Treasure = 0,
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

    return pcall(function()
        VirtualInputManager:SendKeyEvent(true, key, false, game)
        task.wait(holdTime)
        VirtualInputManager:SendKeyEvent(false, key, false, game)
    end)
end

local function mouseClickAt(x, y)
    if not VirtualInputManager then
        return false
    end

    return pcall(function()
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.025)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)
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

    return pcall(function()
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, held, game, 0)
    end)
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

    if type(fireSignalFn) == "function" then
        local ok = pcall(function()
            fireSignalFn(button.Activated)
        end)

        if ok then
            return true
        end
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
        local parent = instance.Parent
        if parent and lower(parent.Name):find("digspots", 1, true) then
            Runtime.DigSpots[instance] = true
        end
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
    Runtime.DigSpots[instance] = nil
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

    if Config.SelectedWeapon == "Auto" then
        return HotbarService.AutoCombatSlot()
    end

    return HotbarService.TitleToSlot[Config.SelectedWeapon]
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

function TargetService.IsAliveNPC(model)
    if not model
        or not model.Parent
        or not model:IsA("Model")
        or isPlayerEntity(model) then
        return false
    end

    local hum = model:FindFirstChildOfClass("Humanoid")
    return objectRoot(model) ~= nil and (not hum or hum.Health > 0)
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

PlatformTransport = {}

local PLATFORM_NAME = "SON_TransportPlatform"

local function transportPlatformCFrameForRoot(rootGoal)
    return rootGoal * CFrame.new(0, -3.25, 0)
end

local function restoreTransportHumanoid()
    local hum = humanoid()

    if hum and Runtime.TransportAutoRotate ~= nil then
        hum.AutoRotate = Runtime.TransportAutoRotate
    end

    Runtime.TransportAutoRotate = nil
end

function PlatformTransport.Ensure()
    local part = Runtime.TransportPart

    if part and part.Parent then
        part.Size = Vector3.new(
            Config.PlatformSize,
            1,
            Config.PlatformSize
        )
        part.Transparency = Config.PlatformTransparency
        return part
    end

    local root = rootPart()
    if not root then
        return nil
    end

    part = Instance.new("Part")
    part.Name = PLATFORM_NAME
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    part.Material = Enum.Material.SmoothPlastic
    part.Size = Vector3.new(
        Config.PlatformSize,
        1,
        Config.PlatformSize
    )
    part.Transparency = Config.PlatformTransparency
    part.CFrame = root.CFrame * CFrame.new(0, -3.25, 0)
    part.Parent = Workspace

    Runtime.TransportPart = part
    track(part)

    return part
end

function PlatformTransport.DestroyWeld()
    if Runtime.TransportWeld then
        pcall(function()
            Runtime.TransportWeld:Destroy()
        end)
    end

    Runtime.TransportWeld = nil
end

function PlatformTransport.Attach()
    local root = rootPart()
    local part = PlatformTransport.Ensure()

    if not root or not part then
        return false
    end

    if Runtime.TransportWeld and Runtime.TransportWeld.Parent then
        return true
    end

    part.CFrame = root.CFrame * CFrame.new(0, -3.25, 0)

    pcall(function()
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)

    local hum = humanoid()
    if hum and Runtime.TransportAutoRotate == nil then
        Runtime.TransportAutoRotate = hum.AutoRotate
        hum.AutoRotate = false
    end

    local weld = Instance.new("WeldConstraint")
    weld.Name = "SON_TransportWeld"
    weld.Part0 = part
    weld.Part1 = root
    weld.Parent = part

    Runtime.TransportWeld = weld
    return true
end

function PlatformTransport.Cancel(keepPlatform)
    Runtime.TransportTween = nil
    Runtime.TransportGoal = nil
    Runtime.TransportRootGoal = nil
    Runtime.TransportMoving = false
    Runtime.TransportLastDistance = nil
    Runtime.TransportLastProgressAt = 0
    Runtime.TransportStartedAt = 0

    PlatformTransport.DestroyWeld()
    restoreTransportHumanoid()

    local root = rootPart()
    local part = Runtime.TransportPart

    if keepPlatform ~= false and root and part and part.Parent then
        pcall(function()
            part.CFrame = root.CFrame * CFrame.new(0, -3.25, 0)
        end)
    elseif keepPlatform == false and part then
        pcall(function()
            part:Destroy()
        end)
        Runtime.TransportPart = nil
    end
end

function PlatformTransport.MoveToRootCFrame(rootGoal)
    local root = rootPart()
    local part = PlatformTransport.Ensure()

    if not root or not part or not rootGoal then
        return false, "missing"
    end

    local distance = (root.Position - rootGoal.Position).Magnitude

    if distance <= Config.PlatformArrivalDistance then
        PlatformTransport.Cancel(true)
        return true, "arrived"
    end

    if not Config.PlatformTransport then
        return false, "disabled"
    end

    local platformGoal = transportPlatformCFrameForRoot(rootGoal)

    if Runtime.TransportMoving and Runtime.TransportGoal then
        local moved = (
            Runtime.TransportGoal.Position
            - platformGoal.Position
        ).Magnitude

        -- Retarget without cancelling/recreating movement. This is the key
        -- difference from the old Tween loop that caused visible jitter.
        if moved >= Config.PlatformRetargetDistance then
            Runtime.TransportGoal = platformGoal
            Runtime.TransportRootGoal = rootGoal
        end

        return false, "moving"
    end

    if not PlatformTransport.Attach() then
        return false, "attach failed"
    end

    Runtime.TransportGoal = platformGoal
    Runtime.TransportRootGoal = rootGoal
    Runtime.TransportMoving = true
    Runtime.TransportLastDistance =
        (part.Position - platformGoal.Position).Magnitude
    Runtime.TransportLastProgressAt = os.clock()
    Runtime.TransportStartedAt = os.clock()

    return false, "started"
end

function PlatformTransport.Step(deltaTime)
    if not Runtime.TransportMoving then
        return
    end

    local root = rootPart()
    local part = Runtime.TransportPart
    local goal = Runtime.TransportGoal

    if not root or not part or not part.Parent or not goal then
        PlatformTransport.Cancel(true)
        return
    end

    local offset = goal.Position - part.Position
    local distance = offset.Magnitude
    local stepDistance =
        math.max(20, Config.PlatformSpeed)
        * math.max(0.001, deltaTime)

    if distance <= math.max(stepDistance, 0.3) then
        part.CFrame = goal
        Runtime.TransportMoving = false
        Runtime.TransportGoal = nil
        Runtime.TransportRootGoal = nil
        Runtime.TransportLastDistance = nil

        PlatformTransport.DestroyWeld()
        restoreTransportHumanoid()

        pcall(function()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)

        return
    end

    local alpha = math.clamp(stepDistance / distance, 0, 1)

    -- Lerp moves by a distance-derived alpha, therefore speed is approximately
    -- studs/second while orientation changes smoothly with the platform.
    local nextPlatformCFrame = part.CFrame:Lerp(goal, alpha)
    part.CFrame = nextPlatformCFrame

    if Config.PlatformKinematicAssist then
        pcall(function()
            root.CFrame = nextPlatformCFrame * CFrame.new(0, 3.25, 0)
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
    end

    local now = os.clock()
    local previous = Runtime.TransportLastDistance

    if previous == nil or distance < previous - 0.05 then
        Runtime.TransportLastDistance = distance
        Runtime.TransportLastProgressAt = now
    elseif now - Runtime.TransportLastProgressAt > 2.0 then
        -- Re-seat only the local platform/weld, never snap the player directly.
        PlatformTransport.DestroyWeld()
        restoreTransportHumanoid()
        PlatformTransport.Attach()

        Runtime.TransportLastDistance = distance
        Runtime.TransportLastProgressAt = now
    end
end

connect(RunService.Heartbeat, function(deltaTime)
    if Core.Running then
        PlatformTransport.Step(deltaTime)
    end
end)

function PlatformTransport.MoveAbove(object)
    local target = objectRoot(object)
    if not target then
        return false, "missing target"
    end

    local position = target.Position + Vector3.new(
        0,
        Config.PlatformFarmHeight,
        0
    )

    local goal = CFrame.lookAt(
        position,
        Vector3.new(
            target.Position.X,
            position.Y,
            target.Position.Z
        )
    )

    return PlatformTransport.MoveToRootCFrame(goal)
end

function PlatformTransport.MoveNear(object)
    local target = objectRoot(object)
    local root = rootPart()

    if not target or not root then
        return false, "missing target"
    end

    local humanoidModel =
        object:IsA("Model")
        and object:FindFirstChildOfClass("Humanoid") ~= nil

    local height =
        humanoidModel
        and Config.PlatformNpcHeight
        or 3

    local away = Vector3.new(
        root.Position.X - target.Position.X,
        0,
        root.Position.Z - target.Position.Z
    )

    if away.Magnitude <= 0.05 then
        away = Vector3.new(
            -target.CFrame.LookVector.X,
            0,
            -target.CFrame.LookVector.Z
        )
    end

    if away.Magnitude <= 0.05 then
        away = Vector3.new(0, 0, 1)
    end

    away = away.Unit

    local position =
        target.Position
        + away * Config.PlatformBackDistance
        + Vector3.new(0, height, 0)

    local face = Vector3.new(
        target.Position.X,
        position.Y,
        target.Position.Z
    )

    local goal = CFrame.lookAt(
        position,
        face
    )

    return PlatformTransport.MoveToRootCFrame(
        goal
    )
end

function PlatformTransport.SetFarmAnchorFrom(object)
    local target = objectRoot(object)
    if not target then
        return nil
    end

    local position = target.Position + Vector3.new(
        0,
        Config.PlatformFarmHeight,
        0
    )

    Runtime.FarmAnchorCFrame = CFrame.lookAt(
        position,
        Vector3.new(
            target.Position.X,
            position.Y,
            target.Position.Z
        )
    )

    return Runtime.FarmAnchorCFrame
end

function PlatformTransport.MoveToFarmAnchor()
    if not Runtime.FarmAnchorCFrame then
        return false, "no anchor"
    end

    return PlatformTransport.MoveToRootCFrame(
        Runtime.FarmAnchorCFrame
    )
end

-- ============================================================
-- Bring / hitbox
-- ============================================================

BringService = {}

local function farmTargetAllowsBoss(wanted)
    return wanted == "Boss Only"
        or (
            wanted
            and wanted ~= ""
            and wanted ~= "Nearest Hostile"
            and wanted ~= "Any Hostile"
        )
end

local function farmAnchorGround(anchor)
    if not anchor then
        return nil
    end

    return anchor.Position - Vector3.new(
        0,
        Config.PlatformFarmHeight,
        0
    )
end

function BringService.Step(wanted, anchor)
    if not Config.BringMobs or not anchor then
        Runtime.LastBringCount = 0
        return 0
    end

    local now = os.clock()
    if now - Runtime.LastBring < 0.12 then
        return Runtime.LastBringCount or 0
    end
    Runtime.LastBring = now

    local ground = farmAnchorGround(anchor)
    if not ground then
        Runtime.LastBringCount = 0
        return 0
    end

    local candidates = {}
    local bossAllowed = farmTargetAllowsBoss(wanted)

    for model in pairs(Runtime.Entities) do
        if model
            and model.Parent
            and TargetService.IsFarmMob(model, wanted)
            and (
                not TargetService.IsBoss(model)
                or bossAllowed
            ) then

            local part =
                model:FindFirstChild("HumanoidRootPart")
                or objectRoot(model)

            if part and not part.Anchored then
                local distance =
                    (part.Position - ground).Magnitude

                if distance <= Config.BringRadius then
                    table.insert(candidates, {
                        Model = model,
                        Part = part,
                        Distance = distance,
                    })
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        return a.Distance < b.Distance
    end)

    local count =
        math.min(#candidates, Config.BringLimit)

    for index = 1, count do
        local data = candidates[index]
        local column = ((index - 1) % 3) - 1
        local row = math.floor((index - 1) / 3)

        local position =
            anchor.Position
            + Vector3.new(
                column * Config.BringSpread,
                -Config.MobBelowFeet,
                row * Config.BringSpread
            )

        local destination = CFrame.new(position)

        pcall(function()
            data.Part.AssemblyLinearVelocity = Vector3.zero
            data.Part.AssemblyAngularVelocity = Vector3.zero
            data.Model:PivotTo(destination)
            data.Part.CFrame = destination
        end)
    end

    Runtime.LastBringCount = count
    return count
end

HitboxService = {}

function HitboxService.Restore(model)
    local data = Runtime.ExpandedHitboxes[model]
    if not data then
        return
    end

    local part = data.Part
    if part and part.Parent then
        pcall(function()
            part.Size = data.Size
            part.Transparency = data.Transparency
            part.CanCollide = data.CanCollide
            part.CanQuery = data.CanQuery
            part.Massless = data.Massless
        end)
    end

    Runtime.ExpandedHitboxes[model] = nil
end

function HitboxService.Clear()
    for model in pairs(Runtime.ExpandedHitboxes) do
        HitboxService.Restore(model)
    end
end

function HitboxService.Apply(model, wanted)
    if not Config.MobHitbox
        or not TargetService.IsFarmMob(model, wanted) then

        HitboxService.Restore(model)
        return
    end

    if TargetService.IsBoss(model)
        and not farmTargetAllowsBoss(wanted) then

        HitboxService.Restore(model)
        return
    end

    local part = model:FindFirstChild("HumanoidRootPart")

    if not part then
        return
    end

    if not Runtime.ExpandedHitboxes[model] then
        Runtime.ExpandedHitboxes[model] = {
            Part = part,
            Size = part.Size,
            Transparency = part.Transparency,
            CanCollide = part.CanCollide,
            CanQuery = part.CanQuery,
            Massless = part.Massless,
        }
    end

    pcall(function()
        part.Size = Vector3.new(
            Config.HitboxSize,
            Config.HitboxSize,
            Config.HitboxSize
        )
        part.Transparency = Config.HitboxTransparency
        part.CanCollide = false
        part.CanQuery = true
        part.Massless = true
    end)
end

function HitboxService.Step(wanted, anchor)
    local now = os.clock()

    if now - Runtime.LastHitbox < 0.12 then
        return Runtime.LastHitboxCount or 0
    end
    Runtime.LastHitbox = now

    local keep = {}
    local count = 0
    local ground = farmAnchorGround(anchor)
    local bossAllowed = farmTargetAllowsBoss(wanted)

    if Config.MobHitbox then
        for model in pairs(Runtime.Entities) do
            if model
                and model.Parent
                and TargetService.IsFarmMob(model, wanted)
                and (
                    not TargetService.IsBoss(model)
                    or bossAllowed
                ) then

                local part =
                    model:FindFirstChild("HumanoidRootPart")

                local inRange =
                    not ground
                    or (
                        part
                        and (
                            part.Position - ground
                        ).Magnitude <= Config.HitboxRange
                    )

                if inRange then
                    keep[model] = true
                    count += 1
                    HitboxService.Apply(model, wanted)
                end
            end
        end
    end

    for model in pairs(Runtime.ExpandedHitboxes) do
        if not keep[model] then
            HitboxService.Restore(model)
        end
    end

    Runtime.LastHitboxCount = count
    return count
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

    if firePromptFn then
        local ok = pcall(function()
            firePromptFn(prompt, math.max(0, prompt.HoldDuration or 0))
        end)

        if ok then
            return true
        end
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
    if firePromptFn then
        pcall(function()
            firePromptFn(prompt, math.max(0, prompt.HoldDuration or 0))
        end)
        task.wait(0.08)
    end

    return inputOk == true or dialogueIsOpen(npc)
end

-- ============================================================
-- Mastery / combat
-- ============================================================

MasteryService = {}

local function currentFruitSkillNames()
    local result = {}
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local skillInfo = modules and modules:FindFirstChild("SkillInformation")
    local skills = skillInfo and skillInfo:FindFirstChild("Skills")
    local fruits = skills and skills:FindFirstChild("Fruits")
    local fruit = fruits and fruits:FindFirstChild(PlayerState.GetFruit())

    if fruit then
        for _, object in ipairs(fruit:GetDescendants()) do
            if object:IsA("ModuleScript") then
                result[lower(object.Name)] = true
            end
        end
    end

    return result
end

function MasteryService.GetCandidates()
    HotbarService.Refresh()

    local candidates = {}
    local fruitSkills = Config.MasteryMode == "Current Fruit"
        and currentFruitSkillNames()
        or nil

    for _, data in pairs(HotbarService.Slots) do
        local accepted = false

        if Config.MasteryMode == "Selected Skill" then
            accepted = Config.SelectedWeapon ~= "Auto"
                and data.Title == Config.SelectedWeapon
        elseif Config.MasteryMode == "Current Fruit" then
            local title = lower(data.Title)

            if fruitSkills then
                for skillName in pairs(fruitSkills) do
                    if title == skillName
                        or title:find(skillName, 1, true)
                        or skillName:find(title, 1, true) then
                        accepted = true
                        break
                    end
                end
            end
        else
            accepted = HotbarService.IsCombat(data)
        end

        if accepted
            and (not Config.MasteryReadyOnly or HotbarService.IsReady(data)) then
            table.insert(candidates, data)
        end
    end

    table.sort(candidates, function(a, b)
        return (tonumber(a.Slot) or 99) < (tonumber(b.Slot) or 99)
    end)

    return candidates
end

function MasteryService.Step()
    if not Config.AutoMastery then
        return false
    end

    local now = os.clock()
    if now - Runtime.LastMastery < Config.MasteryInterval then
        return false
    end

    local candidates = MasteryService.GetCandidates()
    if #candidates == 0 then
        return false
    end

    Runtime.MasteryCursor =
        (Runtime.MasteryCursor % #candidates) + 1

    local data = candidates[Runtime.MasteryCursor]
    if not data then
        return false
    end

    if Config.MasteryReadyOnly and not HotbarService.IsReady(data) then
        return false
    end

    Runtime.LastMastery = now

    if HotbarService.RequiresHold(data) then
        return pressKey(
            data.Key,
            math.clamp(Config.MasteryHoldTime, 0.08, 1.5)
        )
    end

    return HotbarService.Press(data)
end

function MasteryService.GetSnapshot()
    local candidates = MasteryService.GetCandidates()
    local rows = {}

    for _, data in ipairs(candidates) do
        local ready = HotbarService.IsReady(data) and "Ready" or "Cooldown"
        local exp = data.EXP
        local expText = ""

        if exp and exp:IsA("GuiObject") then
            local bar = exp:FindFirstChild("Bar", true)
            if bar and bar:IsA("GuiObject") then
                expText = string.format(
                    " • EXP %.0f%%",
                    math.clamp(bar.Size.X.Scale * 100, 0, 100)
                )
            end
        end

        table.insert(
            rows,
            data.Slot .. ": " .. data.Title .. " [" .. ready .. "]" .. expText
        )
    end

    return #rows > 0 and table.concat(rows, "\n") or "No mastery candidates"
end

CombatService = {}

local function setBlock(held)
    if Runtime.BlockHeld == held then
        return
    end

    Runtime.BlockHeld = held

    pcall(function()
        VirtualInputManager:SendKeyEvent(held, Enum.KeyCode.F, false, game)
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
        Config.SelectedWeapon
        .. " "
        .. tostring(selected and selected.Title or "")
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

    if build == "Balanced"
        or build == "Tank"
        or build == "Mobility"
        or build == "Haki" then
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
        return false
    end

    local now = os.clock()
    if now - Runtime.LastStatsSpend < Config.StatSpendInterval then
        return false
    end

    if StatsService.GetStatPoints() <= 0 then
        return false
    end

    local stat = StatsService.ChooseStat()
    local radar = radarFrame()
    local frame = radar and radar:FindFirstChild(stat or "")
    local button = frame and frame:FindFirstChild("ImageButton")

    if not button or not button:IsA("ImageButton") then
        return false
    end

    Runtime.LastStatsSpend = now
    return clickButton(button, true)
end

function StatsService.GetSnapshot()
    local values = StatsService.GetValues()
    local rows = {
        "Points: " .. StatsService.GetStatPoints(),
        "Build: " .. StatsService.GetBuild(),
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
        VirtualInputManager:SendMouseButtonEvent(
            viewport.X / 2,
            viewport.Y / 2,
            0,
            held,
            game,
            0
        )
    end)
end

local function releaseFishingKey()
    if not Runtime.FishingKeyHeld then
        return
    end

    local key = Runtime.FishingKeyHeld
    Runtime.FishingKeyHeld = nil

    pcall(function()
        VirtualInputManager:SendKeyEvent(false, key, false, game)
    end)
end

local function holdFishingKey(key)
    if Runtime.FishingKeyHeld == key then
        return
    end

    releaseFishingKey()
    Runtime.FishingKeyHeld = key

    pcall(function()
        VirtualInputManager:SendKeyEvent(true, key, false, game)
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

    local wanted = lower(text)

    for _, object in ipairs(screen:GetDescendants()) do
        if object:IsA("ImageButton")
            and not isScriptTemplateDescendant(object)
            and isOnScreen(object) then

            local label = object:FindFirstChildWhichIsA("TextLabel", true)
            if label and lower(label.Text) == wanted then
                return object
            end
        end
    end

    -- Some QTE implementations may reuse the template in place.
    -- In the inactive dump, those template buttons sit at Y=-58;
    -- only accept a template if it has moved into the viewport.
    for _, object in ipairs(screen:GetDescendants()) do
        if object:IsA("ImageButton") and isOnScreen(object) then
            local label = object:FindFirstChildWhichIsA("TextLabel", true)
            if label and lower(label.Text) == wanted then
                return object
            end
        end
    end

    return nil
end

local function findEnabledBillboard(name)
    local screen = qteScreen()
    if not screen then
        return nil
    end

    for _, object in ipairs(screen:GetDescendants()) do
        if object:IsA("BillboardGui")
            and object.Name == name
            and object.Enabled then
            return object
        end
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

    if rod.Source == "Hotbar" then
        return HotbarService.Press(rod.Hotbar)
    end

    if rod.EquipButton and rod.EquipButton:IsA("GuiButton") then
        local ok = clickButton(rod.EquipButton, true)

        if ok then
            Runtime.FishingRodCache = nil
            Runtime.FishingRodCacheAt = 0
        end

        return ok
    end

    return false
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
        FishingService.Reset("No fishing rod detected")
        setFishingState("MISSING_ROD", "No rod in Hotbar/FishInventory")
        return 1.0
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

    if FarmMovement then
        FarmMovement.Stop(false, true)
    else
        PlatformTransport.Cancel(true)
    end

    if Runtime.FishingState == "WAIT_QTE" then
        if os.clock() - Runtime.FishingStateSince >= Config.FishingBiteTimeout then
            Runtime.FishingLastCast = os.clock()
            setFishingState("COOLDOWN", "No bite/QTE; retrying")
        end

        return 0.25
    end

    if os.clock() - Runtime.FishingLastCast < Config.FishingCooldown then
        return 0.25
    end

    FishingService.EquipRod(rod)
    task.wait(0.08)
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

function MiningQTEService.FindOre()
    local wanted = MiningQTEService.GetWantedOre()
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
                    if drop > bestDrop or (drop == bestDrop and (not bestDistance or distance < bestDistance)) then
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
    if not screen then
        return nil
    end

    -- The real Mining QTE in the dump is:
    -- Events/Mining/Mining/Frame/{Critical Zone, Amount}
    for _, object in ipairs(screen:GetDescendants()) do
        if object:IsA("BillboardGui")
            and object.Name == "Mining"
            and object.Enabled
            and object.Parent
            and object.Parent.Name == "Mining" then

            local frame = object:FindFirstChild("Frame")
            local critical = frame and frame:FindFirstChild("Critical Zone")
            local amount = frame and frame:FindFirstChild("Amount")

            if critical and amount
                and critical:IsA("GuiObject")
                and amount:IsA("GuiObject") then
                return object, frame, critical, amount
            end
        end
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
    setMiningState("CHECK", reason or "reset")
end

function MiningQTEService.Step()
    local progressionMining = Config.AutoProgress
        and Runtime.ProgressLifeSkill == "Mining"

    if not Config.AutoMining and not progressionMining then
        MiningQTEService.Reset("Auto Mining disabled")
        return 0.8
    end

    if Config.AutoProgress and Runtime.ProgressLifeSkill ~= "Mining" then
        MiningQTEService.Reset("Progression owns another task")
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
    end

    if not ore then
        miningMouse(false)
        setMiningState("WAIT_ORE", "No matching ore spawned")
        return 0.8
    end

    local wanted = oreName(ore)
    local distance = distanceTo(ore)

    if distance > Config.PlatformArrivalDistance + 1 then
        miningMouse(false, ore)
        setMiningState("MOVE", "Moving to " .. wanted)

        if FarmMovement then
            FarmMovement.GoNear(
                ore,
                2.4,
                3.5
            )
        else
            PlatformTransport.MoveNear(ore)
        end

        return 0.18
    end

    if FarmMovement then
        FarmMovement.Stop(false, true)
    else
        PlatformTransport.Cancel(true)
    end

    local pickaxe = findPickaxe()
    if not pickaxe then
        miningMouse(false, ore)
        setMiningState("MISSING_PICKAXE", "No pickaxe in hotbar")
        return 0.8
    end

    HotbarService.Press(pickaxe)

    if Config.MiningAutoAim then
        local ownRoot = rootPart()
        local targetPart = objectRoot(ore)
        if ownRoot and targetPart then
            pcall(function()
                ownRoot.CFrame = CFrame.lookAt(
                    ownRoot.Position,
                    Vector3.new(targetPart.Position.X, ownRoot.Position.Y, targetPart.Position.Z)
                )
            end)
        end
    end

    if MiningQTEService.HandleQTE(ore) then
        if Runtime.MiningReleaseDone then
            -- Wait for the game to consume the release and either reset the bar
            -- or mark the ore Mined before another swing.
            if os.clock() - Runtime.MiningLastQTE >= Config.MiningRetryDelay then
                Runtime.MiningReleaseDone = false
                Runtime.MiningLastAttempt = os.clock()
            end
        end
        return 0.035
    end

    -- No QTE yet: start/continue one mining swing by holding M1 on the ore.
    local elapsed = os.clock() - Runtime.MiningStateSince
    if Runtime.MiningState ~= "HOLD" then
        setMiningState("HOLD", "Holding M1 on " .. wanted)
        Runtime.MiningStateSince = os.clock()
        miningMouse(true, ore)
    elseif elapsed >= Config.MiningHoldTimeout then
        miningMouse(false, ore)
        Runtime.MiningLastAttempt = os.clock()
        setMiningState("RETRY", "Mining QTE timeout")
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

    local standaloneLifeSkillActive =
        Config.AutoFishing
        or Config.AutoMining
        or Config.AutoTreasure

    local isChest =
        kind == "Chest"
        or kind == "WorldBossChest"
        or kind == "FruitChest"

    if Config.AutoProgress then
        -- Loot never steals movement from the quest controller.
        -- Nexomia exposes fireproximityprompt, so chest prompts around
        -- the farm point can be opened without descending from the platform.
        local allowedDistance

        if isChest then
            allowedDistance =
                type(firePromptFn) == "function"
                and Config.ChestCollectRadius
                or math.max(
                    8,
                    tonumber(prompt.MaxActivationDistance) or 8
                )
        else
            allowedDistance = 14
        end

        if distance <= allowedDistance then
            usePromptWithCooldown(
                prompt,
                isChest and 1.15 or 0.75
            )
        elseif isChest
            and Config.AutoChestRoute
            and (
                Runtime.ProgressState == "QUEST_WAIT"
                or Runtime.ProgressState == "REACH_WAIT_EVENT"
                or Runtime.ProgressState == "MANUAL_COMBAT"
            ) then
            FarmMovement.GoNear(
                prompt,
                2.5,
                2.5
            )
        end

        return
    end

    if standaloneLifeSkillActive then
        if distance <= 10 then
            InteractionService.FirePrompt(prompt)
        end
        return
    end

    if isChest
        and Config.AutoChestRoute
        and not standaloneLifeSkillActive then

        if distance
            > Config.PlatformArrivalDistance + 2 then

            FarmMovement.GoNear(
                prompt,
                3,
                2.5
            )
            return
        end

        FarmMovement.Stop(false, true)
        usePromptWithCooldown(prompt, 1.15)
        return
    end

    if distance
        > Config.PlatformArrivalDistance + 2 then

        FarmMovement.GoNear(
            prompt,
            3,
            2.5
        )
    else
        FarmMovement.Stop(false, true)
        usePromptWithCooldown(prompt, 0.75)
    end
end

-- ============================================================
-- Treasure / world utility
-- ============================================================

TreasureService = {}

local function shovelSlot()
    HotbarService.Refresh()

    for _, data in pairs(HotbarService.Slots) do
        if lower(data.Title):find("shovel", 1, true) then
            return data
        end
    end

    return nil
end

function TreasureService.FindNearestDigSpot()
    local best
    local bestDistance

    for spot in pairs(Runtime.DigSpots) do
        if spot and spot.Parent then
            local distance = distanceTo(spot)

            if distance <= Config.TreasureSearchRadius
                and (not bestDistance or distance < bestDistance) then
                best = spot
                bestDistance = distance
            end
        end
    end

    return best, bestDistance
end

function TreasureService.Reset(reason)
    Runtime.TreasureTarget = nil
    Runtime.TreasureState = "IDLE"

    if reason then
        Runtime.ProgressDetail = reason
    end
end

function TreasureService.Step()
    local progressionTreasure = Config.AutoProgress
        and Runtime.ProgressLifeSkill == "Treasure"

    if not Config.AutoTreasure and not progressionTreasure then
        Runtime.TreasureState = "IDLE"
        Runtime.TreasureTarget = nil
        return 0.8
    end

    if Config.AutoProgress
        and Runtime.ProgressLifeSkill ~= "Treasure" then
        return 0.8
    end

    local target = Runtime.TreasureTarget
    if not target or not target.Parent then
        target = TreasureService.FindNearestDigSpot()
        Runtime.TreasureTarget = target
    end

    if not target then
        Runtime.TreasureState = "WAIT_DIGSPOT"
        return 0.8
    end

    if distanceTo(target) > Config.PlatformArrivalDistance + 1 then
        Runtime.TreasureState = "MOVE"
        PlatformTransport.MoveNear(target)
        return 0.2
    end

    PlatformTransport.Cancel(true)

    local shovel = shovelSlot()
    if not shovel then
        Runtime.TreasureState = "MISSING_SHOVEL"
        return 0.8
    end

    HotbarService.Press(shovel)

    if os.clock() - Runtime.TreasureLastDig >= Config.TreasureDigInterval then
        Runtime.TreasureLastDig = os.clock()

        local point = screenPointOf(target)
        if point then
            mouseClickAt(point.X, point.Y)
        else
            mouseClickCenter()
        end
    end

    Runtime.TreasureState = "DIGGING"
    return 0.12
end

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

local FARM_PLATFORM_NAME = "SON_FarmPlatform"

local function farmSetState(state, detail)
    local fsm = Runtime.FarmFSM

    if fsm.State ~= state then
        fsm.State = state
        fsm.Since = os.clock()
    end

    Runtime.ProgressState = state
    Runtime.ProgressDetail = detail or ""
end

local function farmMovementPlatformCFrame(rootCFrame)
    return CFrame.new(rootCFrame.Position - Vector3.new(0, 3.25, 0))
end

local function yawCFrame(position, facePosition)
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

function FarmMovement.Ensure()
    local part = Runtime.FarmMovePart

    if part and part.Parent then
        part.Size = Vector3.new(
            Config.PlatformSize,
            1,
            Config.PlatformSize
        )
        part.Transparency = Config.PlatformTransparency
        return part
    end

    local root = rootPart()
    if not root then
        return nil
    end

    part = Instance.new("Part")
    part.Name = FARM_PLATFORM_NAME
    part.Anchored = true
    part.CanCollide = true
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    part.Material = Enum.Material.SmoothPlastic
    part.Size = Vector3.new(
        Config.PlatformSize,
        1,
        Config.PlatformSize
    )
    part.Transparency = Config.PlatformTransparency
    part.CFrame =
        farmMovementPlatformCFrame(root.CFrame)
    part.Parent = Workspace

    Runtime.FarmMovePart = part
    track(part)

    return part
end

function FarmMovement.Stop(removePlatform, clearHold)
    Runtime.FarmMoveActive = false
    Runtime.FarmMoveGoal = nil
    Runtime.FarmMoveRoute = nil
    Runtime.FarmMoveRouteIndex = 0
    Runtime.FarmMoveFinalGoal = nil
    Runtime.FarmMoveFacePosition = nil
    Runtime.FarmMoveKind = nil

    if clearHold ~= false then
        Runtime.FarmMoveHold = false
        Runtime.FarmMoveHoldCFrame = nil
    end

    if removePlatform and Runtime.FarmMovePart then
        pcall(function()
            Runtime.FarmMovePart:Destroy()
        end)
        Runtime.FarmMovePart = nil
    elseif Runtime.FarmMovePart
        and Runtime.FarmMovePart.Parent then

        local root = rootPart()
        if root then
            Runtime.FarmMovePart.CFrame =
                farmMovementPlatformCFrame(
                    root.CFrame
                )
        end
    end
end

local function buildFarmRoute(
    finalGoal,
    facePosition,
    kind
)
    local root = rootPart()
    if not root or not finalGoal then
        return nil
    end

    local current = root.Position
    local final = finalGoal.Position
    local horizontal = Vector3.new(
        final.X - current.X,
        0,
        final.Z - current.Z
    )

    local route = {}
    local cruiseY

    if kind == "farm" then
        cruiseY = final.Y
    else
        local minimumY =
            final.Y + Config.TravelClearance

        local maximumY =
            final.Y + Config.TravelMaxAboveTarget

        cruiseY = math.clamp(
            math.max(current.Y, minimumY),
            minimumY,
            maximumY
        )
    end

    local function add(position)
        table.insert(
            route,
            yawCFrame(
                position,
                facePosition or final
            )
        )
    end

    -- Phase 1: move to one ABSOLUTE travel altitude.
    -- It never adds height to the player's current Y each tick.
    if math.abs(current.Y - cruiseY) > 2.5 then
        add(Vector3.new(
            current.X,
            cruiseY,
            current.Z
        ))
    end

    -- Phase 2: horizontal cruise.
    if horizontal.Magnitude
        > Config.TravelHorizontalThreshold then

        add(Vector3.new(
            final.X,
            cruiseY,
            final.Z
        ))
    end

    -- Phase 3: final approach / descent.
    add(final)

    return route
end

function FarmMovement.Go(
    rootGoal,
    holdAtEnd,
    kind,
    facePosition
)
    if not rootGoal then
        return false
    end

    -- Old PlatformTransport is used only by standalone life-skill
    -- workers. It must never compete with Auto Farm navigation.
    PlatformTransport.Cancel(false)

    local root = rootPart()
    if not root then
        return false
    end

    FarmMovement.Ensure()

    local oldFinal = Runtime.FarmMoveFinalGoal
    if oldFinal
        and Runtime.FarmMoveKind == kind
        and (
            oldFinal.Position
            - rootGoal.Position
        ).Magnitude <= 1.5 then

        Runtime.FarmMoveHold =
            holdAtEnd == true

        if Runtime.FarmMoveActive
            or (
                root.Position
                - rootGoal.Position
            ).Magnitude
                <= Config.PlatformArrivalDistance then
            return true
        end
    end

    local route = buildFarmRoute(
        rootGoal,
        facePosition,
        kind
    )

    if not route or #route == 0 then
        return false
    end

    Runtime.FarmMoveRoute = route
    Runtime.FarmMoveRouteIndex = 1
    Runtime.FarmMoveGoal = route[1]
    Runtime.FarmMoveFinalGoal = rootGoal
    Runtime.FarmMoveFacePosition =
        facePosition or rootGoal.Position
    Runtime.FarmMoveKind = kind or "travel"
    Runtime.FarmMoveActive = true
    Runtime.FarmMoveHold =
        holdAtEnd == true

    return true
end

function FarmMovement.IsAt(
    rootGoal,
    tolerance
)
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

function FarmMovement.GoNear(
    object,
    heightOffset,
    backDistance
)
    local target = objectRoot(object)
    local root = rootPart()

    if not target or not root then
        return false
    end

    local humanoidModel =
        object:IsA("Model")
        and object:FindFirstChildOfClass(
            "Humanoid"
        ) ~= nil

    if heightOffset == nil then
        heightOffset =
            humanoidModel
            and Config.PlatformNpcHeight
            or 3
    end

    backDistance =
        backDistance
        or Config.PlatformBackDistance

    local targetPosition = target.Position
    local away = Vector3.new(
        root.Position.X - targetPosition.X,
        0,
        root.Position.Z - targetPosition.Z
    )

    if away.Magnitude <= 0.05 then
        local look = target.CFrame.LookVector
        away = Vector3.new(
            -look.X,
            0,
            -look.Z
        )
    end

    if away.Magnitude <= 0.05 then
        away = Vector3.new(0, 0, 1)
    end

    away = away.Unit

    local finalPosition =
        targetPosition
        + away * backDistance
        + Vector3.new(
            0,
            heightOffset,
            0
        )

    local finalGoal = yawCFrame(
        finalPosition,
        targetPosition
    )

    return FarmMovement.Go(
        finalGoal,
        false,
        "travel",
        targetPosition
    )
end

function FarmMovement.GetInteractionGoal(object, prompt)
    local target = objectRoot(prompt) or objectRoot(object)
    if not target then
        return nil
    end

    local maxDistance = prompt and tonumber(prompt.MaxActivationDistance) or 16
    local desiredDistance = math.clamp(maxDistance * 0.38, 4.5, 6.5)

    local look = target.CFrame.LookVector
    local flatLook = Vector3.new(look.X, 0, look.Z)
    if flatLook.Magnitude <= 0.05 then
        flatLook = Vector3.new(0, 0, -1)
    else
        flatLook = flatLook.Unit
    end

    -- Fixed target-relative point. It does not change as the player approaches.
    local position = target.Position + flatLook * desiredDistance + Vector3.new(0, 0.15, 0)
    return yawCFrame(position, target.Position)
end

function FarmMovement.GoInteract(object, prompt)
    local goal = FarmMovement.GetInteractionGoal(object, prompt)
    if not goal then
        return false
    end

    local target = objectRoot(prompt) or objectRoot(object)
    return FarmMovement.Go(
        goal,
        false,
        "interaction",
        target and target.Position or goal.Position
    )
end

function FarmMovement.GoAnchor(anchor)
    if not anchor then
        return false
    end

    return FarmMovement.Go(
        yawCFrame(
            anchor.Position,
            anchor.Position
                + anchor.LookVector
        ),
        true,
        "farm",
        anchor.Position
            + anchor.LookVector
    )
end

function FarmMovement.Step(deltaTime)
    if not Config.AutoProgress
        and not Runtime.FarmMoveActive then
        return
    end

    local root = rootPart()
    if not root then
        return
    end

    local part = FarmMovement.Ensure()
    if not part then
        return
    end

    if Runtime.FarmMoveActive then
        local route =
            Runtime.FarmMoveRoute

        local index =
            Runtime.FarmMoveRouteIndex

        local goal =
            route
            and route[index]

        if not goal then
            Runtime.FarmMoveActive = false
            Runtime.FarmMoveGoal = nil
            return
        end

        Runtime.FarmMoveGoal = goal

        local current = root.Position
        local target = goal.Position
        local delta = target - current
        local distance = delta.Magnitude

        local stepDistance =
            math.max(
                35,
                Config.PlatformSpeed
            )
            * math.max(
                deltaTime,
                0.001
            )

        if distance <= math.max(
            0.35,
            stepDistance
        ) then
            pcall(function()
                root.CFrame = goal
                root.AssemblyLinearVelocity =
                    Vector3.zero
                root.AssemblyAngularVelocity =
                    Vector3.zero

                part.CFrame =
                    farmMovementPlatformCFrame(
                        root.CFrame
                    )
            end)

            Runtime.FarmMoveRouteIndex =
                index + 1

            local nextGoal =
                route[index + 1]

            if nextGoal then
                Runtime.FarmMoveGoal =
                    nextGoal
                return
            end

            Runtime.FarmMoveActive =
                false
            Runtime.FarmMoveGoal = nil

            if Runtime.FarmMoveHold
                and Runtime.FarmMoveFinalGoal then

                Runtime.FarmMoveHoldCFrame =
                    Runtime.FarmMoveFinalGoal
            end

            return
        end

        local nextPosition =
            current
            + delta.Unit
                * math.min(
                    distance,
                    stepDistance
                )

        local nextRoot = yawCFrame(
            nextPosition,
            Runtime.FarmMoveFacePosition
                or target
        )

        pcall(function()
            root.CFrame = nextRoot
            root.AssemblyLinearVelocity =
                Vector3.zero
            root.AssemblyAngularVelocity =
                Vector3.zero

            part.CFrame =
                farmMovementPlatformCFrame(
                    nextRoot
                )
        end)

        return
    end

    local hold =
        Runtime.FarmMoveHoldCFrame

    if Runtime.FarmMoveHold
        and hold then

        local drift =
            (
                root.Position
                - hold.Position
            ).Magnitude

        -- Do not freeze/snap every frame.
        if drift
            > Config.FarmHoldCorrectionDistance then

            local direction =
                hold.Position
                - root.Position

            local correction =
                math.min(
                    direction.Magnitude,
                    math.max(
                        30,
                        Config.PlatformSpeed * 0.5
                    )
                    * math.max(
                        deltaTime,
                        0.001
                    )
                )

            local correctedPosition =
                root.Position
                + (
                    direction.Magnitude > 0
                    and direction.Unit * correction
                    or Vector3.zero
                )

            local corrected = yawCFrame(
                correctedPosition,
                hold.Position
                    + hold.LookVector
            )

            pcall(function()
                root.CFrame = corrected
                root.AssemblyLinearVelocity =
                    Vector3.zero
            end)
        end

        part.CFrame =
            farmMovementPlatformCFrame(
                CFrame.new(hold.Position)
            )
    else
        part.CFrame =
            farmMovementPlatformCFrame(
                root.CFrame
            )
    end
end

connect(
    RunService.Heartbeat,
    function(deltaTime)
        if Core.Running then
            FarmMovement.Step(deltaTime)
        end
    end
)

local function farmResetRoute(clearAnchor)
    Runtime.CurrentTarget = nil
    Runtime.CurrentWantedMob = nil
    Runtime.ProgressLifeSkill = nil

    if clearAnchor ~= false then
        Runtime.FarmAnchorCFrame = nil
        Runtime.FarmMoveHold = false
        Runtime.FarmMoveHoldCFrame = nil
    end

    HitboxService.Clear()
end

local function matchingFarmMobs(wanted, limit)
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

    if limit and #rows > limit then
        for index = #rows, limit + 1, -1 do
            rows[index] = nil
        end
    end

    return rows
end

local function computeFarmAnchor(mobs)
    if #mobs == 0 then
        return nil
    end

    local sample = math.min(#mobs, 6)
    local x = 0
    local z = 0
    local baseY = mobs[1].Part.Position.Y

    for index = 1, sample do
        x += mobs[index].Part.Position.X
        z += mobs[index].Part.Position.Z
    end

    x /= sample
    z /= sample

    local ground = Vector3.new(x, baseY, z)
    local position = ground + Vector3.new(
        0,
        Config.PlatformFarmHeight,
        0
    )

    return CFrame.lookAt(
        position,
        Vector3.new(
            ground.X,
            position.Y,
            ground.Z
        )
    )
end

local function shouldRecenterAnchor(anchor, mobs)
    if not anchor or #mobs == 0 then
        return true
    end

    local ground = farmAnchorGround(anchor)
    if not ground then
        return true
    end

    return (
        mobs[1].Part.Position
        - ground
    ).Magnitude > Config.FarmAnchorRecenterDistance
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
    local npc = resolveQuestNpc(questName, preferredNpc)

    if not npc then
        FarmMovement.Stop(false, true)
        local now = os.clock()
        if now - fsm.LastResolverRefresh >= 1.5 then
            fsm.LastResolverRefresh = now
            QuestCatalogService.Build()
        end

        fsm.InteractionNPC = nil
        fsm.InteractionPrompt = nil
        farmSetState("NPC_SEARCH", preferredNpc and preferredNpc ~= "" and preferredNpc or questName)
        return
    end

    Runtime.CurrentTarget = npc
    local prompt = InteractionService.FindPromptNear(npc, "Dialogue")
    local targetPart = objectRoot(prompt) or objectRoot(npc)

    if not targetPart then
        FarmMovement.Stop(false, true)
        farmSetState("NPC_NO_ROOT", npc.Name)
        return
    end

    if fsm.InteractionNPC ~= npc or fsm.InteractionPrompt ~= prompt then
        fsm.InteractionNPC = npc
        fsm.InteractionPrompt = prompt
        fsm.InteractionArrivedAt = 0
        fsm.PromptAttemptAt = 0
        fsm.PromptAttemptCount = 0
    end

    if dialogueIsOpen(npc) then
        FarmMovement.Stop(false, true)
        InteractionService.ProcessDialogue(questName, npc)
        farmSetState("NPC_DIALOGUE", npc.Name)
        return
    end

    local maxActivation = prompt and tonumber(prompt.MaxActivationDistance) or 16
    local interactionRange = math.clamp(maxActivation - 3, 7, 12)
    local ownRoot = rootPart()
    local distance = ownRoot and (ownRoot.Position - targetPart.Position).Magnitude or math.huge

    if distance > interactionRange then
        fsm.InteractionArrivedAt = 0
        FarmMovement.GoInteract(npc, prompt)
        farmSetState("NPC_TRAVEL", npc.Name .. " • " .. string.format("%.1f", distance) .. " studs")
        return
    end

    -- Release the movement owner before the game's dialogue/camera logic starts.
    FarmMovement.Stop(false, true)

    if fsm.InteractionArrivedAt == 0 then
        fsm.InteractionArrivedAt = os.clock()
        farmSetState("NPC_SETTLE", npc.Name)
        return
    end

    if os.clock() - fsm.InteractionArrivedAt < 0.18 then
        farmSetState("NPC_SETTLE", npc.Name)
        return
    end

    if not prompt then
        farmSetState("NPC_NO_PROMPT", npc.Name)
        return
    end

    local triggered = InteractionService.InteractWithQuestNPC(npc, questName)
    farmSetState(
        triggered and "NPC_TRIGGER" or "NPC_PRESS_E",
        npc.Name .. " • E attempts=" .. tostring(fsm.PromptAttemptCount)
    )
end

local function stepDefeatTask(wanted)
    Runtime.ProgressLifeSkill = nil
    Runtime.CurrentWantedMob = wanted

    local mobs = matchingFarmMobs(
        wanted,
        math.max(Config.BringLimit, 8)
    )

    if #mobs == 0 then
        HitboxService.Clear()
        Runtime.CurrentTarget = nil

        if Runtime.FarmFSM.NoMobSince == 0 then
            Runtime.FarmFSM.NoMobSince = os.clock()
        end

        farmSetState(
            "MOB_WAIT",
            wanted .. " • waiting for spawn"
        )

        return
    end

    Runtime.FarmFSM.NoMobSince = 0

    if shouldRecenterAnchor(
        Runtime.FarmAnchorCFrame,
        mobs
    ) then

        Runtime.FarmAnchorCFrame =
            computeFarmAnchor(mobs)

        Runtime.FarmFSM.LastAnchorRefresh =
            os.clock()
    end

    local anchor = Runtime.FarmAnchorCFrame

    if not anchor then
        farmSetState(
            "MOB_SEARCH",
            wanted
        )
        return
    end

    -- Hitbox is maintained as soon as the quest mob cluster is known.
    -- It is no longer blocked by travel reaching the farm anchor first.
    HitboxService.Step(
        wanted,
        anchor
    )

    if not FarmMovement.IsAt(
        anchor,
        Config.PlatformArrivalDistance
    ) then

        FarmMovement.GoAnchor(anchor)

        farmSetState(
            "FARM_TRAVEL",
            wanted
        )

        return
    end

    Runtime.FarmMoveHold = true
    Runtime.FarmMoveHoldCFrame = anchor

    local brought = BringService.Step(
        wanted,
        anchor
    )

    local target = mobs[1].Model
    Runtime.CurrentTarget = target

    if target then
        CombatService.AimAt(target)
    end

    CombatService.AttackStep()

    farmSetState(
        "FARM_COMBAT",
        wanted
            .. " • mobs="
            .. tostring(#mobs)
            .. " • brought="
            .. tostring(brought)
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
            Runtime.FarmMoveHold = true
            Runtime.FarmMoveHoldCFrame = goal
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
    HitboxService.Clear()

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
            HitboxService.Clear()
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
            routeLifeSkill("Treasure", taskData.Text)
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
-- Character movement service
-- Makes Movement-tab controls functional.
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
            Config.AutoProgress
            or Runtime.FarmMoveActive
            or Runtime.FarmMoveHold
            or Runtime.TransportMoving
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
        task.wait(Config.AutoProgress and 0.12 or 0.65)
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
        local delay = safeWorker("Treasure", TreasureService.Step)
        task.wait(tonumber(delay) or 0.8)
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
        local active =
            Config.CurrentTargetESP
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
    local npc =
        NPCNavigator.Resolve(displayOrName)

    if not npc then
        notify(
            "NPC Navigation",
            "NPC not found: "
                .. tostring(displayOrName),
            5
        )
        return false
    end

    Runtime.CurrentTarget = npc

    local prompt =
        InteractionService.FindPromptNear(
            npc,
            "Dialogue"
        )

    if FarmMovement then
        FarmMovement.GoInteract(
            npc,
            prompt
        )
    else
        PlatformTransport.MoveNear(npc)
    end

    notify(
        "NPC Navigation",
        "Moving to " .. npc.Name,
        4
    )

    return true
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
        "Farm mover: "
            .. tostring(Runtime.FarmMoveActive)
            .. " • hold="
            .. tostring(Runtime.FarmMoveHold),
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
        "Quest-only Bring + mob-only Hitbox",
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
        "VirtualInputManager: " .. tostring(VirtualInputManager ~= nil),
        "fireproximityprompt: " .. tostring(type(firePromptFn) == "function"),
        "firesignal: " .. tostring(type(fireSignalFn) == "function"),
        "setclipboard: " .. tostring(type(clipboardFn) == "function"),
        "WebSocket: unused",
        "getscriptclosure: unused",
        "filesystem addons: unused",
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
-- Fluent UI - direct API
-- ============================================================

local Window = Fluent:CreateWindow({
    Title = "SON HUB " .. VERSION,
    SubTitle = "Nexomia Full | make by hongson",
    TabWidth = 155,
    Size = UDim2.fromOffset(720, 520),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl,
})

local Tabs = {
    Home = Window:AddTab({Title = "Trang Chu", Icon = "home"}),
    Farm = Window:AddTab({Title = "Farm", Icon = "target"}),
    Combat = Window:AddTab({Title = "Combat", Icon = "shield"}),
    Movement = Window:AddTab({Title = "Movement", Icon = "move"}),
    Player = Window:AddTab({Title = "Player", Icon = "user"}),
    Quest = Window:AddTab({Title = "Quest", Icon = "scroll"}),
    Settings = Window:AddTab({Title = "Settings", Icon = "settings"}),
    Info = Window:AddTab({Title = "Info", Icon = "info"}),
}

local function bindToggle(section, id, title, defaultValue, callback, description)
    local option = section:AddToggle(id, {
        Title = title,
        Description = description or "",
        Default = defaultValue == true,
    })

    option:OnChanged(function()
        callback(option.Value)
    end)

    return option
end

local function bindDropdown(section, id, title, values, defaultIndex, callback, description)
    local option = section:AddDropdown(id, {
        Title = title,
        Description = description or "",
        Values = values,
        Multi = false,
        Default = defaultIndex or 1,
    })

    option:OnChanged(function(value)
        callback(value)
    end)

    return option
end

local function bindSlider(section, id, title, minimum, maximum, defaultValue, callback, description)
    return section:AddSlider(id, {
        Title = title,
        Description = description or "",
        Default = defaultValue,
        Min = minimum,
        Max = maximum,
        Rounding = 0,
        Callback = callback,
    })
end

-- ============================================================
-- Home
-- ============================================================

local HomeAutomation = Tabs.Home:AddSection("Main Automation")

HomeAutomation:AddButton({
    Title = "Runtime Status",
    Description = "Level, quest, progression state and detected game data.",
    Callback = function()
        notify("Runtime Status", runtimeStatus(), 11)
    end,
})

HomeAutomation:AddButton({
    Title = "Self Test",
    Description = "Checks Quest UI, DialogueNPCs, hotbar, Fishing/QTE, Ore and DigSpot caches.",
    Callback = function()
        notify("SON HUB Self Test", selfTest(), 12)
    end,
})

HomeAutomation:AddButton({
    Title = "Worker Health",
    Description = "Shows scheduler ticks and the last isolated worker error.",
    Callback = function()
        notify("Worker Health", workerHealth(), 14)
    end,
})

HomeAutomation:AddButton({
    Title = "Quest Target Probe",
    Description = "Resolve the current dialogue target and start a platform movement test.",
    Callback = function()
        local quest, taskData = QuestService.GetNextTask()
        if not quest or not taskData then
            notify("Quest Probe", "No incomplete live quest task.", 5)
            return
        end

        if taskData.Kind == "Talk" or taskData.Kind == "Return" or taskData.Kind == "Deliver" then
            local npc = TargetService.FindNamedDialogueNPC(taskData.Target)
                or QuestCatalogService.FindQuestGiver(quest.Name, taskData.Target)
            if not npc then
                notify("Quest Probe", "FAILED\nQuest: " .. quest.Name .. "\nTask: " .. taskData.Text .. "\nDialogue NPC not found.", 9)
                return
            end

            local prompt = InteractionService.FindPromptNear(npc, "Dialogue")
            local distance = distanceTo(npc)
            notify("Quest Probe", "OK\nQuest: " .. quest.Name .. "\nTask: " .. taskData.Text .. "\nNPC: " .. npc.Name .. "\nDistance: " .. string.format("%.1f", distance) .. "\nPrompt: " .. tostring(prompt and prompt.Name or "None"), 10)

            if distance > Config.PlatformArrivalDistance + 2 then
                PlatformTransport.MoveNear(npc)
            end
        else
            notify("Quest Probe", "Quest: " .. quest.Name .. "\nKind: " .. taskData.Kind .. "\nTarget: " .. taskData.Target, 7)
        end
    end,
})

local HomeState = Tabs.Home:AddSection("Current State")

HomeState:AddButton({
    Title = "Current Quest",
    Callback = function()
        notify(
            "Quest",
            currentQuestSummary()
                .. "\nProgress: "
                .. tostring(Runtime.ProgressState)
                .. "\nDetail: "
                .. tostring(Runtime.ProgressDetail),
            9
        )
    end,
})

HomeState:AddButton({
    Title = "Refresh Game Index",
    Description = "Rebuilds client-visible entity/prompt/ore/dig caches and the quest-to-NPC map.",
    Callback = function()
        task.spawn(function()
            RuntimeIndex.Rebuild()
            QuestCatalogService.Build()
            HotbarService.Refresh()

            notify(
                "Game Index",
                "Ready | "
                    .. tostring(#Runtime.QuestCatalog)
                    .. " quest modules mapped",
                4
            )
        end)
    end,
})

-- ============================================================
-- Farm
-- ============================================================

local FarmMain = Tabs.Farm:AddSection("Auto Farm")

local FarmMaster = bindToggle(
    FarmMain,
    "AutoFarmV12",
    "AUTO FARM",
    Config.AutoProgress,
    function(value)
        Config.AutoProgress = value

        if value then
            Config.AutoQuest = true
            Config.AutoAcceptRecommended = true
            Config.AutoTurnIn = true
            Config.AutoDialogue = true
            QuestCatalogService.Build()

            Runtime.FarmFSM.QuestKey = nil
            Runtime.FarmFSM.TaskKey = nil

            notify(
                "Auto Farm",
                "Started • active quest first; otherwise accept the game's level-appropriate RecommendedQuest.",
                4
            )
        else
            Runtime.ProgressLifeSkill = nil
            Runtime.FarmAnchorCFrame = nil
            Runtime.CurrentTarget = nil
            Runtime.CurrentWantedMob = nil

            HitboxService.Clear()
            QuestService.ClearTaskLock()
            FarmMovement.Stop(true, true)
            restoreCollision()

            notify(
                "Auto Farm",
                "Stopped and farm state cleared.",
                3
            )
        end
    end,
    "Single owner: Quest -> travel -> farm point -> bring -> hitbox -> combat -> turn-in."
)

bindDropdown(
    FarmMain,
    "FarmModeV12",
    "Mode",
    {"Smart Quest", "Selected Mob", "Boss"},
    1,
    function(value)
        Config.FarmMode = value
        Runtime.FarmFSM.TaskKey = nil
        Runtime.FarmAnchorCFrame = nil
        Runtime.CurrentTarget = nil
        HitboxService.Clear()
        FarmMovement.Stop(false, true)
    end,
    "Smart Quest is the normal full-auto mode. Manual modes ignore Quest routing."
)

local mobValuesV11 = TargetService.GetMobOptions()

bindDropdown(
    FarmMain,
    "SelectedMobV12",
    "Manual Mob",
    mobValuesV11,
    1,
    function(value)
        Config.SelectedMob = value
        Runtime.CurrentTarget = nil
        Runtime.FarmAnchorCFrame = nil
    end,
    "Only used when Mode = Selected Mob."
)

FarmMain:AddButton({
    Title = "Farm Status",
    Description = "Shows the exact state, quest task, target and movement status.",
    Callback = function()
        local statusQuest, statusTask =
            QuestService.GetNextTask()

        notify(
            "Auto Farm Status",
            table.concat({
                "State: " .. tostring(Runtime.ProgressState),
                "Detail: " .. tostring(Runtime.ProgressDetail),
                "Quest: " .. currentQuestSummary(),
                "Next Kind: "
                    .. tostring(statusTask and statusTask.Kind or "None")
                    .. (
                        statusTask and statusTask.EventGated
                        and " • event-gated"
                        or ""
                    ),
                "Wanted Mob: " .. tostring(Runtime.CurrentWantedMob or "None"),
                "Target: "
                    .. tostring(
                        Runtime.CurrentTarget
                        and Runtime.CurrentTarget.Name
                        or "None"
                    ),
                "Moving: " .. tostring(Runtime.FarmMoveActive)
                    .. " • phase="
                    .. tostring(Runtime.FarmMoveKind or "-")
                    .. " #"
                    .. tostring(Runtime.FarmMoveRouteIndex),
                "Anchor: " .. tostring(Runtime.FarmAnchorCFrame ~= nil),
                "Bring count: " .. tostring(Runtime.LastBringCount or 0),
                "Hitbox count: " .. tostring(Runtime.LastHitboxCount or 0)
                    .. " • size="
                    .. tostring(Config.HitboxSize),
                "Planner: " .. QuestPlannerService.GetSummary(),
            }, "\n"),
            11
        )
    end,
})

local PositionSection = Tabs.Farm:AddSection("Farm Position")

bindSlider(
    PositionSection,
    "FarmHeightV12",
    "Height Above Mobs",
    10,
    32,
    Config.PlatformFarmHeight,
    function(value)
        Config.PlatformFarmHeight = value
        Runtime.FarmAnchorCFrame = nil
    end,
    "Player stays above the mob cluster; matching mobs are stacked below the platform."
)

bindSlider(
    PositionSection,
    "FarmMoveSpeedV12",
    "Travel Speed",
    70,
    320,
    Config.PlatformSpeed,
    function(value)
        Config.PlatformSpeed = value
    end,
    "Continuous Heartbeat interpolation; changing a target does not recreate TweenService tweens."
)

bindSlider(
    PositionSection,
    "FarmPlatformSizeV12",
    "Platform Size",
    6,
    18,
    Config.PlatformSize,
    function(value)
        Config.PlatformSize = value
    end
)

local MobSection = Tabs.Farm:AddSection("Mob Farm")

bindToggle(
    MobSection,
    "BringMobsV14",
    "Bring Matching Mobs",
    Config.BringMobs,
    function(value)
        Config.BringMobs = value
    end,
    "Only mobs matching the current Defeat task are moved."
)

bindSlider(
    MobSection,
    "BringRadiusV14",
    "Bring Radius",
    40,
    240,
    Config.BringRadius,
    function(value)
        Config.BringRadius = value
    end
)

bindToggle(
    MobSection,
    "HitboxV14",
    "Large Mob Hitbox",
    Config.MobHitbox,
    function(value)
        Config.MobHitbox = value
        if not value then
            HitboxService.Clear()
        end
    end,
    "HumanoidRootPart only; quest NPCs and players are excluded."
)

bindSlider(
    MobSection,
    "HitboxSizeV14",
    "Hitbox Size",
    10,
    40,
    Config.HitboxSize,
    function(value)
        Config.HitboxSize = value
    end
)

local AttackSection = Tabs.Farm:AddSection("Basic Attack")

bindToggle(
    AttackSection,
    "AutoM1V14",
    "Auto M1",
    Config.AutoAttack,
    function(value)
        Config.AutoAttack = value
    end,
    "Only normal M1. Auto Farm does not press numeric skill keys."
)

bindSlider(
    AttackSection,
    "AttackRateV14",
    "M1 / Second",
    2,
    12,
    Config.AttackRate,
    function(value)
        Config.AttackRate = value
    end
)

local QuestOnlySection = Tabs.Farm:AddSection("Quest Routing")

QuestOnlySection:AddParagraph({
    Title = "Integrated Quest Planner",
    Content = "Existing quests are always processed first. If none are active, SON HUB uses the game's RecommendedQuest for the current player level and routes to its quest giver."
})

QuestOnlySection:AddButton({
    Title = "Quest Planner Status",
    Callback = function()
        notify(
            "Quest Planner",
            QuestPlannerService.GetSummary(),
            8
        )
    end,
})

-- ============================================================
-- Combat
-- ============================================================

Tabs.Combat:AddParagraph({
    Title = "Combat",
    Content = "Combat input is left manual in this build."
})

-- ============================================================
-- Movement
-- ============================================================

Tabs.Movement:AddParagraph({
    Title = "Auto Farm Movement",
    Content = "Farm travel/platform settings live in the Farm tab. This tab only contains manual character movement."
})

local CharacterSection = Tabs.Movement:AddSection("Character")

bindToggle(
    CharacterSection,
    "SpeedOverride",
    "WalkSpeed Override",
    Config.SpeedOverride,
    function(value)
        Config.SpeedOverride = value
    end
)

bindSlider(
    CharacterSection,
    "WalkSpeed",
    "Walk Speed",
    16,
    100,
    Config.WalkSpeed,
    function(value)
        Config.WalkSpeed = value
    end
)

bindToggle(
    CharacterSection,
    "JumpOverride",
    "Jump Override",
    Config.JumpOverride,
    function(value)
        Config.JumpOverride = value
    end
)

bindSlider(
    CharacterSection,
    "JumpPower",
    "Jump Power",
    40,
    120,
    Config.JumpPower,
    function(value)
        Config.JumpPower = value
    end
)

bindToggle(
    CharacterSection,
    "InfiniteJump",
    "Infinite Jump",
    Config.InfiniteJump,
    function(value)
        Config.InfiniteJump = value
    end
)

bindToggle(
    CharacterSection,
    "Noclip",
    "Noclip",
    Config.Noclip,
    function(value)
        Config.Noclip = value
        if not value and not Runtime.TransportMoving then
            restoreCollision()
        end
    end
)

bindToggle(
    CharacterSection,
    "PlatformNoclip",
    "Noclip During Auto Progress",
    Config.PlatformNoclip,
    function(value)
        Config.PlatformNoclip = value
    end
)

-- ============================================================
-- Player
-- ============================================================

local StatsSection = Tabs.Player:AddSection("Auto Stats")

bindToggle(
    StatsSection,
    "AutoStats",
    "Auto Spend Stat Points",
    Config.AutoStats,
    function(value)
        Config.AutoStats = value
    end
)

bindDropdown(
    StatsSection,
    "StatBuild",
    "Stat Build",
    {"Balanced", "Tank", "Mobility", "Haki"},
    1,
    function(value)
        Config.StatBuild = value
    end,
    "Reads StatpointText and uses the client-visible Radar stat buttons."
)

StatsSection:AddButton({
    Title = "Show Stats",
    Callback = function()
        notify("Stats", StatsService.GetSnapshot(), 9)
    end,
})

local LootSection = Tabs.Player:AddSection("Loot / Chests")

bindToggle(
    LootSection,
    "AutoPickup",
    "Auto Pickup",
    Config.AutoPickup,
    function(value)
        Config.AutoPickup = value
    end
)

bindToggle(
    LootSection,
    "AutoChest",
    "Auto Chest",
    Config.AutoChest,
    function(value)
        Config.AutoChest = value
    end
)

bindToggle(
    LootSection,
    "AutoWorldBossChest",
    "Auto World Boss Chest",
    Config.AutoWorldBossChest,
    function(value)
        Config.AutoWorldBossChest = value
    end
)

bindToggle(
    LootSection,
    "AutoFruitChest",
    "Auto Fruit Chest",
    Config.AutoFruitChest,
    function(value)
        Config.AutoFruitChest = value
    end
)

bindToggle(
    LootSection,
    "AutoChestRoute",
    "Route To Chests",
    Config.AutoChestRoute,
    function(value)
        Config.AutoChestRoute = value
    end,
    "When Auto Farm is OFF, travel to enabled chests. During Auto Farm, nearby chest prompts are opened without stealing quest movement."
)

bindSlider(
    LootSection,
    "ChestCollectRadius",
    "Chest Collect Radius",
    15,
    100,
    Config.ChestCollectRadius,
    function(value)
        Config.ChestCollectRadius = value
    end
)

bindToggle(
    LootSection,
    "AutoQuestItems",
    "Auto Quest Items",
    Config.AutoQuestItems,
    function(value)
        Config.AutoQuestItems = value
    end
)

bindToggle(
    LootSection,
    "LootESP",
    "Loot ESP",
    Config.LootESP,
    function(value)
        Config.LootESP = value
    end
)

local FishingSection = Tabs.Player:AddSection("Fishing")

bindToggle(
    FishingSection,
    "AutoFishing",
    "Auto Fishing",
    Config.AutoFishing,
    function(value)
        Config.AutoFishing = value
        FishingService.Reset(value and "Enabled" or "Disabled")
    end,
    "Handles SHAKE, CLICK, Timed Release and the Move/Fish reel controller."
)

bindDropdown(
    FishingSection,
    "FishingSpotMode",
    "Fishing Spot",
    {"Saved Position", "Anchor Town Pond", "Current Position"},
    1,
    function(value)
        Config.FishingSpotMode = value
        FishingService.Reset("Spot changed")
    end
)

FishingSection:AddButton({
    Title = "Save Current Fishing Spot",
    Callback = function()
        local root = rootPart()

        if root then
            Runtime.FishingSpotCFrame = root.CFrame
            Config.FishingSpotMode = "Saved Position"
            FishingService.Reset("Saved current spot")
            notify("Fishing", "Current fishing position saved.", 3)
        end
    end,
})

bindToggle(
    FishingSection,
    "FishingReturn",
    "Auto Return To Fishing Spot",
    Config.FishingAutoReturn,
    function(value)
        Config.FishingAutoReturn = value
    end
)

bindToggle(
    FishingSection,
    "RequireBait",
    "Require Bait",
    Config.FishingRequireBait,
    function(value)
        Config.FishingRequireBait = value
    end
)

bindToggle(
    FishingSection,
    "AutoShake",
    "Auto SHAKE",
    Config.FishingAutoShake,
    function(value)
        Config.FishingAutoShake = value
    end
)

bindToggle(
    FishingSection,
    "AutoSpamClick",
    "Auto CLICK QTE",
    Config.FishingAutoSpamClick,
    function(value)
        Config.FishingAutoSpamClick = value
    end
)

bindToggle(
    FishingSection,
    "AutoTimedRelease",
    "Auto Timed Release",
    Config.FishingAutoTimedRelease,
    function(value)
        Config.FishingAutoTimedRelease = value
    end
)

bindToggle(
    FishingSection,
    "AutoReelCalibrate",
    "Auto Calibrate Reel Direction",
    Config.FishingAutoCalibrate,
    function(value)
        Config.FishingAutoCalibrate = value
        Runtime.FishingReelCalibrated = false
    end
)

bindSlider(
    FishingSection,
    "FishingTolerance",
    "Reel Tolerance",
    5,
    40,
    Config.FishingReelTolerance,
    function(value)
        Config.FishingReelTolerance = value
    end
)

bindSlider(
    FishingSection,
    "FishingBiteTimeout",
    "Bite Timeout",
    15,
    60,
    Config.FishingBiteTimeout,
    function(value)
        Config.FishingBiteTimeout = value
    end
)

FishingSection:AddButton({
    Title = "Fishing Conditions",
    Callback = function()
        local data = FishingService.GetConditions()

        notify(
            "Fishing Conditions",
            table.concat({
                "State: " .. tostring(data.State),
                "Can Start: " .. tostring(data.CanStart),
                "Rod: " .. tostring(data.Rod)
                    .. " [" .. tostring(data.RodSource) .. "]",
                "Bait: " .. tostring(data.Bait)
                    .. " x" .. tostring(data.BaitAmount),
                "Spot: " .. tostring(data.Spot),
                "Reason: " .. tostring(data.Reason),
            }, "\n"),
            11
        )
    end,
})

local MiningSection = Tabs.Player:AddSection("Mining")

bindToggle(
    MiningSection,
    "AutoMining",
    "Auto Mining",
    Config.AutoMining,
    function(value)
        Config.AutoMining = value
        MiningQTEService.Reset(value and "Enabled" or "Disabled")
    end,
    "Targets real Ore models, holds the mining action and releases inside Critical Zone."
)

bindDropdown(
    MiningSection,
    "MiningMode",
    "Mining Mode",
    {"Quest Required", "Selected Ore", "Any Available", "Highest Drop"},
    1,
    function(value)
        Config.MiningMode = value
        MiningQTEService.Reset("Mode changed")
    end
)

local oreValues = MiningQTEService.GetOreOptions()
bindDropdown(
    MiningSection,
    "SelectedOre",
    "Select Ore",
    oreValues,
    1,
    function(value)
        Config.SelectedOre = value
        MiningQTEService.Reset("Ore changed")
    end
)

bindToggle(
    MiningSection,
    "MiningQTE",
    "Auto Mining QTE",
    Config.AutoMiningQTE,
    function(value)
        Config.AutoMiningQTE = value
    end
)

bindToggle(
    MiningSection,
    "MiningAim",
    "Face Ore",
    Config.MiningAutoAim,
    function(value)
        Config.MiningAutoAim = value
    end
)

MiningSection:AddButton({
    Title = "Go To Selected Ore",
    Description = "Finds the selected/quest-required ore and moves to it using the SON HUB mover.",
    Callback = function()
        local ore =
            MiningQTEService.FindOre()

        if not ore then
            notify(
                "Mining",
                "No matching ore is currently client-visible.",
                5
            )
            return
        end

        Runtime.MiningTarget = ore

        if FarmMovement then
            FarmMovement.GoNear(
                ore,
                2.4,
                3.5
            )
        else
            PlatformTransport.MoveNear(ore)
        end

        notify(
            "Mining",
            "Moving to " .. tostring(oreName(ore)),
            4
        )
    end,
})

MiningSection:AddButton({
    Title = "Equip Pickaxe",
    Callback = function()
        local pickaxe = findPickaxe()

        if not pickaxe then
            notify(
                "Mining",
                "No Pickaxe detected in the current hotbar.",
                5
            )
            return
        end

        HotbarService.Press(pickaxe)

        notify(
            "Mining",
            "Equipped: " .. tostring(pickaxe.Title),
            3
        )
    end,
})

MiningSection:AddButton({
    Title = "Mining State",
    Callback = function()
        notify(
            "Mining",
            "State: " .. tostring(Runtime.MiningState)
                .. "\nWanted: "
                .. tostring(MiningQTEService.GetWantedOre() or "Any")
                .. "\nTarget: "
                .. tostring(
                    Runtime.MiningTarget
                    and Runtime.MiningTarget.Name
                    or "None"
                ),
            8
        )
    end,
})

local LifeSection = Tabs.Player:AddSection("Farming / Treasure")

bindToggle(
    LifeSection,
    "AutoFarming",
    "Auto Farming Prompts",
    Config.AutoFarming,
    function(value)
        Config.AutoFarming = value
    end,
    "Uses client-visible Crop, FarmGear and Pest prompts."
)

bindToggle(
    LifeSection,
    "AutoTreasure",
    "Auto Treasure Dig",
    Config.AutoTreasure,
    function(value)
        Config.AutoTreasure = value
        TreasureService.Reset(value and "Enabled" or "Disabled")
    end,
    "Uses visible DigSpots and shovel interaction only; no hidden shovel remote is guessed."
)

bindSlider(
    LifeSection,
    "TreasureRange",
    "Treasure Search Radius",
    500,
    5000,
    Config.TreasureSearchRadius,
    function(value)
        Config.TreasureSearchRadius = value
    end
)

bindSlider(
    LifeSection,
    "TreasureDigInterval",
    "Dig Interval x100",
    20,
    100,
    math.floor(Config.TreasureDigInterval * 100),
    function(value)
        Config.TreasureDigInterval = value / 100
    end
)

LifeSection:AddButton({
    Title = "Treasure State",
    Callback = function()
        notify(
            "Treasure",
            "State: " .. tostring(Runtime.TreasureState)
                .. "\nTarget: "
                .. tostring(
                    Runtime.TreasureTarget
                    and Runtime.TreasureTarget:GetFullName()
                    or "None"
                ),
            8
        )
    end,
})

local UtilitySection = Tabs.Player:AddSection("World Utilities")

UtilitySection:AddButton({
    Title = "Go To Crafting Table",
    Callback = function()
        WorldUtilityService.GoToPrompt("Crafting Table")
    end,
})

UtilitySection:AddButton({
    Title = "Go To Anvil",
    Callback = function()
        WorldUtilityService.GoToPrompt("Anvil")
    end,
})

UtilitySection:AddButton({
    Title = "Go To Furnace",
    Callback = function()
        WorldUtilityService.GoToPrompt("Furnace")
    end,
})

UtilitySection:AddButton({
    Title = "Go To Ship Spawn",
    Callback = function()
        WorldUtilityService.GoToPrompt("Ship Spawn")
    end,
})

bindToggle(
    UtilitySection,
    "AntiAFK",
    "Anti AFK",
    Config.AntiAFK,
    function(value)
        Config.AntiAFK = value
    end
)

local NPCNavigationSection =
    Tabs.Player:AddSection("NPC Navigation")

NPCNavigationSection:AddButton({
    Title = "Fishing NPC — Fisherman Jack",
    Description = "Move to the client-visible fishing NPC.",
    Callback = function()
        NPCNavigator.GoTo(
            "Fishing NPC — Fisherman Jack"
        )
    end,
})

NPCNavigationSection:AddButton({
    Title = "Blacksmith — Shinozaki",
    Callback = function()
        NPCNavigator.GoTo(
            "Blacksmith — Shinozaki"
        )
    end,
})

NPCNavigationSection:AddButton({
    Title = "Merchant",
    Callback = function()
        NPCNavigator.GoTo("Merchant")
    end,
})

NPCNavigationSection:AddButton({
    Title = "Miner — Song Jil Wu",
    Callback = function()
        NPCNavigator.GoTo(
            "Miner — Song Jil Wu"
        )
    end,
})

NPCNavigationSection:AddButton({
    Title = "Miner — Song Kim Wu",
    Callback = function()
        NPCNavigator.GoTo(
            "Miner — Song Kim Wu"
        )
    end,
})

-- ============================================================
-- Quest
-- ============================================================

local QuestAutomation = Tabs.Quest:AddSection("Quest Automation")

bindToggle(
    QuestAutomation,
    "AutoQuest",
    "Auto Quest",
    Config.AutoQuest,
    function(value)
        Config.AutoQuest = value
    end
)

bindToggle(
    QuestAutomation,
    "AutoRecommended",
    "Auto Accept Recommended",
    Config.AutoAcceptRecommended,
    function(value)
        Config.AutoAcceptRecommended = value
    end
)

bindToggle(
    QuestAutomation,
    "AutoTurnIn",
    "Auto Turn-in",
    Config.AutoTurnIn,
    function(value)
        Config.AutoTurnIn = value
    end
)

bindToggle(
    QuestAutomation,
    "AutoDialogue",
    "Auto Dialogue",
    Config.AutoDialogue,
    function(value)
        Config.AutoDialogue = value
    end
)

bindToggle(
    QuestAutomation,
    "AutoClaim",
    "Auto Claim",
    Config.AutoClaim,
    function(value)
        Config.AutoClaim = value
    end
)

QuestAutomation:AddButton({
    Title = "Quest State",
    Callback = function()
        notify(
            "Quest State",
            "Level: " .. tostring(PlayerState.GetLevel())
                .. "\n"
                .. currentQuestSummary()
                .. "\nProgress: "
                .. tostring(Runtime.ProgressState)
                .. "\nDetail: "
                .. tostring(Runtime.ProgressDetail),
            11
        )
    end,
})

local QuestCatalogSection = Tabs.Quest:AddSection("Quest Catalog")

local selectedQuestPath = nil
local questValues = QuestCatalogService.GetNames()

bindDropdown(
    QuestCatalogSection,
    "QuestCatalog",
    "Quest",
    questValues,
    1,
    function(value)
        selectedQuestPath = value
    end,
    "Catalog is built from the client-visible QuestInfo/Quests hierarchy."
)

QuestCatalogSection:AddButton({
    Title = "Find Selected Quest Giver",
    Callback = function()
        if not selectedQuestPath
            or selectedQuestPath == "Quest catalog unavailable" then

            notify("Quest Catalog", "Select a quest first.", 3)
            return
        end

        local questName =
            selectedQuestPath:match("([^/]+)$")
            or selectedQuestPath

        local npc = QuestCatalogService.FindQuestGiver(questName)

        if npc then
            Runtime.CurrentTarget = npc
            PlatformTransport.MoveNear(npc)
            notify(
                "Quest Giver",
                questName .. " -> " .. npc.Name,
                5
            )
        else
            notify(
                "Quest Giver",
                "No client-visible NPC mapping for " .. questName,
                5
            )
        end
    end,
})

-- ============================================================
-- Settings
-- ============================================================

local CompatibilitySection = Tabs.Settings:AddSection("Nexomia Compatibility")

CompatibilitySection:AddButton({
    Title = "Executor Status",
    Description = "SON HUB does not use WebSocket, getscriptclosure or filesystem config addons.",
    Callback = function()
        notify("Executor Status", executorStatus(), 11)
    end,
})

CompatibilitySection:AddButton({
    Title = "Worker Health / Last Errors",
    Callback = function()
        notify("Worker Health", workerHealth(), 14)
    end,
})

CompatibilitySection:AddButton({
    Title = "Self Test",
    Callback = function()
        notify("Self Test", selfTest(), 12)
    end,
})

local ResetSection = Tabs.Settings:AddSection("Runtime")

ResetSection:AddButton({
    Title = "Reset Automation State",
    Callback = function()
        Config.AutoProgress = false
        Config.AutoFishing = false
        Config.AutoMining = false
        Config.AutoTreasure = false
        Config.AutoFarming = false

        Runtime.ProgressLifeSkill = nil
        Runtime.CurrentTarget = nil
        Runtime.CurrentWantedMob = nil
        Runtime.FarmAnchorCFrame = nil

        FishingService.Reset("Manual reset")
        MiningQTEService.Reset("Manual reset")
        TreasureService.Reset("Manual reset")
        HitboxService.Clear()
        PlatformTransport.Cancel(false)
        restoreCollision()

        notify("SON HUB", "Runtime automation state reset.", 3)
    end,
})

ResetSection:AddButton({
    Title = "Unload SON HUB",
    Callback = function()
        if type(ENV.__SON_HUB_UNLOAD) == "function" then
            ENV.__SON_HUB_UNLOAD()
        end
    end,
})

-- ============================================================
-- Info
-- ============================================================

Tabs.Info:AddParagraph({
    Title = "SON HUB",
    Content = VERSION .. " | make by hongson",
})

Tabs.Info:AddParagraph({
    Title = "Architecture",
    Content =
        "Fluent direct API, heartbeat moving platform, isolated workers, "
        .. "live Quest UI and client-visible game state.",
})

local InfoSection = Tabs.Info:AddSection("Game Systems")

InfoSection:AddButton({
    Title = "Detected Systems",
    Callback = function()
        notify("Detected Systems", detectedSystems(), 14)
    end,
})

InfoSection:AddButton({
    Title = "Snapshot Limits",
    Callback = function()
        notify(
            "Snapshot Limits",
            "The supplied snapshot has client-visible Explorer/UI metadata "
                .. "but no readable script source. Server-only state and hidden "
                .. "remote contracts are therefore not guessed.",
            10
        )
    end,
})

InfoSection:AddButton({
    Title = "Copy Version",
    Callback = function()
        if type(clipboardFn) == "function" then
            pcall(clipboardFn, "SON HUB " .. VERSION)
            notify("Copied", "SON HUB " .. VERSION, 2)
        else
            notify("Clipboard", "setclipboard unavailable.", 3)
        end
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
    Config.AutoTreasure = false
    Config.AutoFarming = false
    Config.AutoStats = false
    Config.AutoBlock = false

    pcall(function()
        FishingService.Reset("Unload")
    end)

    pcall(function()
        MiningQTEService.Reset("Unload")
    end)

    pcall(function()
        TreasureService.Reset("Unload")
    end)

    pcall(function()
        HitboxService.Clear()
    end)

    pcall(function()
        FarmMovement.Stop(true, true)
    end)

    pcall(function()
        PlatformTransport.Cancel(false)
    end)

    pcall(function()
        restoreCollision()
    end)

    if Runtime.BlockHeld then
        Runtime.BlockHeld = false
        keyEvent(Enum.KeyCode.F, false)
    end

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
