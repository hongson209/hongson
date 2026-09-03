-- SON HUB v27 | Info + stats rebuild | hongson

local VERSION = "27.0.0"
local EXPECTED_PLACE_ID = 118635363908336
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
local hookMetamethodFn = envFunction("hookmetamethod")
local getNamecallMethodFn = envFunction("getnamecallmethod")
local newCClosureFn = envFunction("newcclosure")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
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

local BOOT_STAGE = "services"
local function bootMark(stage)
    BOOT_STAGE = tostring(stage)
    pcall(function()
        print("[SON HUB][BOOT] " .. BOOT_STAGE)
    end)
end

bootMark("services-ready")

-- Snapshot diagnostics only. Do not mutate replicated game data merely to
-- suppress warnings: doing so can break dialogue or asset state and is not clean.
local NoiseGuard = {
    ArchivedSoundIds = {
        ["rbxassetid://105775129468752"] = true,
    },
    MalformedDialogue = 0,
    ArchivedSounds = 0,
    SeenDialogue = setmetatable({}, {__mode = "k"}),
    SeenSounds = setmetatable({}, {__mode = "k"}),
}

local function sanitizeGenderText(text)
    if type(text) ~= "string" or not text:find("{Gender:", 1, true) then
        return text, false
    end

    local changed = false
    local result = text:gsub("%{Gender:%s*([^|}]+)%s*|%s*([^}]+)%}", function(first)
        changed = true
        local value = tostring(first or ""):gsub("^%s+", ""):gsub("%s+$", "")
        return value ~= "" and value or "friend"
    end)

    return result, changed
end

function NoiseGuard.PatchDialogueObject(object)
    if not object or not object.Parent or not object:IsA("StringValue") then
        return false
    end
    if NoiseGuard.SeenDialogue[object] then
        return false
    end

    local _, malformed = sanitizeGenderText(object.Value)
    if malformed then
        NoiseGuard.SeenDialogue[object] = true
        NoiseGuard.MalformedDialogue += 1
    end
    return malformed
end

function NoiseGuard.PatchSound(object)
    if not object or not object.Parent or not object:IsA("Sound") then
        return false
    end
    if NoiseGuard.SeenSounds[object] then
        return false
    end
    if NoiseGuard.ArchivedSoundIds[tostring(object.SoundId)] then
        NoiseGuard.SeenSounds[object] = true
        NoiseGuard.ArchivedSounds += 1
        return true
    end
    return false
end

function NoiseGuard.ScanNow()
    local important = Workspace:FindFirstChild("AA IMPORTANT")
    local liveDialogue = important and important:FindFirstChild("DialogueNPCs")
    if liveDialogue then
        for _, object in ipairs(liveDialogue:GetDescendants()) do
            NoiseGuard.PatchDialogueObject(object)
        end
    end

    local assets = ReplicatedStorage:FindFirstChild("Assets")
    local sounds = assets and assets:FindFirstChild("Sounds")
    if sounds then
        for _, object in ipairs(sounds:GetDescendants()) do
            NoiseGuard.PatchSound(object)
        end
    end
end

pcall(NoiseGuard.ScanNow)
bootMark("snapshot-noise-guard")

local Runtime

local ExecutorCaps = {
    Http = false,
    Request = type(requestFn) == "function",
    VirtualKey = VirtualInputManager ~= nil,
    VirtualMouse = VirtualInputManager ~= nil or VirtualUser ~= nil,
    FireSignal = type(fireSignalFn) == "function",
    FirePrompt = type(firePromptFn) == "function",
    Clipboard = type(clipboardFn) == "function",
    HookMetamethod = type(hookMetamethodFn) == "function"
        and type(getNamecallMethodFn) == "function",
}

local Compat = {}

local function safeCall(fn, ...)
    if type(fn) ~= "function" then
        return false, "not callable"
    end

    local args = table.pack(...)
    return xpcall(function()
        return fn(table.unpack(args, 1, args.n))
    end, function(err)
        local message = tostring(err)
        if type(debug) == "table" and type(debug.traceback) == "function" then
            local okTrace, trace = pcall(debug.traceback, message, 2)
            if okTrace and type(trace) == "string" then
                return trace
            end
        end
        return message
    end)
end

local function callMethod(object, methodName, ...)
    local method = object and object[methodName]
    if type(method) ~= "function" then
        return false, "missing method: " .. tostring(methodName)
    end
    return safeCall(method, object, ...)
end

local function dummyOption(defaultValue)
    return {
        Value = defaultValue,
        OnChanged = function()
            return nil
        end,
        SetValues = function()
            return nil
        end,
        SetValue = function()
            return nil
        end,
    }
end

local function markSoftError(bucket, err)
    if not bucket then
        bucket = "General"
    end
    Runtime = Runtime or {}
    Runtime.WorkerErrors = Runtime.WorkerErrors or {}
    Runtime.WorkerErrorCount = Runtime.WorkerErrorCount or {}
    Runtime.LastWorkerErrorNotify = Runtime.LastWorkerErrorNotify or {}
    Runtime.WorkerErrors[bucket] = tostring(err)
    Runtime.WorkerErrorCount[bucket] = (Runtime.WorkerErrorCount[bucket] or 0) + 1
end

local CapabilityFailures = {}
local CapabilityRetryAt = {}

local function canTryCap(name)
    return ExecutorCaps[name] ~= false
        or os.clock() >= (CapabilityRetryAt[name] or 0)
end

local function markCap(name, ok)
    if ok then
        ExecutorCaps[name] = true
        CapabilityFailures[name] = 0
        CapabilityRetryAt[name] = 0
    else
        local failures = (CapabilityFailures[name] or 0) + 1
        CapabilityFailures[name] = failures
        ExecutorCaps[name] = false
        CapabilityRetryAt[name] = os.clock() + math.min(2.0, 0.15 * (2 ^ math.min(4, failures - 1)))
    end
    return ok
end

function Compat.Key(held, key)
    if not VirtualInputManager or not key or not canTryCap("VirtualKey") then
        return false
    end

    local ok = pcall(function()
        VirtualInputManager:SendKeyEvent(held, key, false, game)
    end)
    markCap("VirtualKey", ok)
    return ok
end

function Compat.ReleaseKey(key)
    if not key then
        return false
    end

    local ok = false
    if VirtualInputManager then
        ok = pcall(function()
            VirtualInputManager:SendKeyEvent(false, key, false, game)
        end)
    end
    return ok
end

function Compat.Mouse(x, y, held)
    local vimOk = false

    if VirtualInputManager and canTryCap("VirtualMouse") then
        vimOk = pcall(function()
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, held, game, 0)
        end)
        markCap("VirtualMouse", vimOk)
        if vimOk then
            return true
        end
    end

    -- Some partial-UNC executors expose VirtualInputManager but its mouse
    -- methods are incomplete. VirtualUser is a safe client-input fallback.
    if VirtualUser then
        local point = Vector2.new(tonumber(x) or 0, tonumber(y) or 0)
        local camera = Workspace.CurrentCamera
        local cameraCFrame = camera and camera.CFrame or CFrame.new()
        local vuOk = pcall(function()
            if held then
                VirtualUser:Button1Down(point, cameraCFrame)
            else
                VirtualUser:Button1Up(point, cameraCFrame)
            end
        end)
        if vuOk then
            markCap("VirtualMouse", true)
            return true
        end
    end

    markCap("VirtualMouse", false)
    return false
end

function Compat.ReleaseMouse(x, y)
    local released = false
    x = tonumber(x) or 0
    y = tonumber(y) or 0

    if VirtualInputManager then
        released = pcall(function()
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end) or released
    end

    if VirtualUser then
        local camera = Workspace.CurrentCamera
        local cameraCFrame = camera and camera.CFrame or CFrame.new()
        released = pcall(function()
            VirtualUser:Button1Up(Vector2.new(x, y), cameraCFrame)
        end) or released
    end

    return released
end

function Compat.FireSignal(signal)
    if not fireSignalFn or not signal or not canTryCap("FireSignal") then
        return false
    end
    local ok = pcall(fireSignalFn, signal)
    markCap("FireSignal", ok)
    return ok
end

function Compat.FirePrompt(prompt, holdDuration)
    if not firePromptFn or not prompt or not canTryCap("FirePrompt") then
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
    if not clipboardFn or not canTryCap("Clipboard") then
        return false
    end
    local ok = pcall(clipboardFn, tostring(text or ""))
    markCap("Clipboard", ok)
    return ok
end

bootMark("native-ui-build")

local connect, track

local NativeUI = {}
NativeUI.__index = NativeUI
NativeUI.RootGui = nil
NativeUI.Window = nil
NativeUI.Toasts = {}

local function uiNew(className, props, parent)
    local object = Instance.new(className)
    if props then
        for key, value in pairs(props) do
            pcall(function()
                object[key] = value
            end)
        end
    end
    if parent then
        object.Parent = parent
    end
    return object
end

local function uiCorner(parent, radius)
    return uiNew("UICorner", {
        CornerRadius = UDim.new(0, radius or 8),
    }, parent)
end

local function uiStroke(parent, transparency)
    return uiNew("UIStroke", {
        Thickness = 1,
        Transparency = transparency or 0.72,
    }, parent)
end

local function uiPadding(parent, left, right, top, bottom)
    return uiNew("UIPadding", {
        PaddingLeft = UDim.new(0, left or 8),
        PaddingRight = UDim.new(0, right or 8),
        PaddingTop = UDim.new(0, top or 8),
        PaddingBottom = UDim.new(0, bottom or 8),
    }, parent)
end

local function uiList(parent, padding)
    return uiNew("UIListLayout", {
        Padding = UDim.new(0, padding or 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, parent)
end

local function attachCanvas(scroller, layout)
    local function refresh()
        pcall(function()
            scroller.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 20)
        end)
    end
    connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"), refresh)
    refresh()
end

local function nativeParent()
    local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        return playerGui
    end
    return CoreGui
end

local function createOption(defaultValue)
    local option = {
        Value = defaultValue,
        _callbacks = {},
    }

    function option:OnChanged(callback)
        if type(callback) == "function" then
            table.insert(self._callbacks, callback)
        end
        return self
    end

    function option:_emit(value)
        self.Value = value
        for _, callback in ipairs(self._callbacks) do
            local ok, err = safeCall(callback, value)
            if not ok then
                markSoftError("UI", err)
            end
        end
    end

    function option:SetValue(value)
        self:_emit(value)
    end

    function option:SetValues(values)
        self.Values = values or {}
    end

    return option
end

local function labelText(parent, text, size, transparency)
    return uiNew("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, size or 22),
        Font = Enum.Font.Gotham,
        Text = tostring(text or ""),
        TextSize = 13,
        TextColor3 = Color3.fromRGB(225, 229, 238),
        TextTransparency = transparency or 0,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, parent)
end

local function createRow(parent, height)
    local row = uiNew("Frame", {
        BackgroundColor3 = Color3.fromRGB(28, 31, 39),
        BackgroundTransparency = 0.08,
        Size = UDim2.new(1, -4, 0, height or 42),
        BorderSizePixel = 0,
    }, parent)
    uiCorner(row, 7)
    uiStroke(row, 0.82)
    return row
end

local NativeSection = {}
NativeSection.__index = NativeSection

function NativeSection:AddToggle(id, data)
    data = data or {}
    local option = createOption(data.Default == true)
    local row = createRow(self.Container, 42)
    local title = labelText(row, data.Title or id, 42)
    title.Size = UDim2.new(1, -58, 1, 0)
    title.Position = UDim2.fromOffset(12, 0)

    local button = uiNew("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = Color3.fromRGB(57, 62, 74),
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(38, 22),
        Position = UDim2.new(1, -50, 0.5, -11),
        Text = "",
    }, row)
    uiCorner(button, 11)

    local knob = uiNew("Frame", {
        BackgroundColor3 = Color3.fromRGB(235, 238, 245),
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(18, 18),
        Position = UDim2.fromOffset(2, 2),
    }, button)
    uiCorner(knob, 9)

    local function render(value)
        button.BackgroundColor3 = value and Color3.fromRGB(76, 130, 255) or Color3.fromRGB(57, 62, 74)
        knob.Position = value and UDim2.fromOffset(18, 2) or UDim2.fromOffset(2, 2)
    end
    render(option.Value)

    connect(button.Activated, function()
        option:_emit(not option.Value)
        render(option.Value)
    end)

    local baseSet = option.SetValue
    function option:SetValue(value)
        baseSet(self, value == true)
        render(self.Value)
    end

    return option
end

function NativeSection:AddButton(spec)
    spec = spec or {}
    local row = createRow(self.Container, 40)
    local button = uiNew("TextButton", {
        AutoButtonColor = true,
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Font = Enum.Font.GothamMedium,
        Text = tostring(spec.Title or "Button"),
        TextSize = 13,
        TextColor3 = Color3.fromRGB(220, 226, 239),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    uiPadding(button, 12, 12, 0, 0)

    local lastActivatedAt = 0
    connect(button.Activated, function()
        local now = os.clock()
        if now - lastActivatedAt < 0.18 then
            return
        end
        lastActivatedAt = now

        if type(spec.Callback) == "function" then
            local ok, err = safeCall(spec.Callback)
            if not ok then
                markSoftError("UI", err)
            end
        end
    end)

    return createOption(false)
end

function NativeSection:AddInput(id, spec)
    spec = spec or {}
    local option = createOption(spec.Default or "")
    local row = createRow(self.Container, 58)
    local title = labelText(row, spec.Title or id, 20)
    title.Position = UDim2.fromOffset(12, 5)
    title.Size = UDim2.new(1, -24, 0, 18)

    local box = uiNew("TextBox", {
        BackgroundColor3 = Color3.fromRGB(20, 23, 30),
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(10, 27),
        Size = UDim2.new(1, -20, 0, 25),
        ClearTextOnFocus = false,
        Font = Enum.Font.Gotham,
        PlaceholderText = tostring(spec.Placeholder or ""),
        Text = tostring(spec.Default or ""),
        TextSize = 12,
        TextColor3 = Color3.fromRGB(230, 233, 240),
        PlaceholderColor3 = Color3.fromRGB(120, 126, 140),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    uiCorner(box, 6)
    uiPadding(box, 8, 8, 0, 0)

    connect(box.FocusLost, function(enterPressed)
        if spec.Finished == false or enterPressed or spec.Finished == true then
            option:_emit(box.Text)
            if type(spec.Callback) == "function" then
                local ok, err = safeCall(spec.Callback, box.Text)
                if not ok then markSoftError("UI", err) end
            end
        end
    end)

    function option:SetValue(value)
        value = tostring(value or "")
        self:_emit(value)
        box.Text = value
    end

    return option
end

function NativeSection:AddSlider(id, data)
    data = data or {}
    local minValue = tonumber(data.Min) or 0
    local maxValue = tonumber(data.Max) or 100
    local option = createOption(math.clamp(tonumber(data.Default) or minValue, minValue, maxValue))
    local row = createRow(self.Container, 56)
    local title = labelText(row, data.Title or id, 22)
    title.Position = UDim2.fromOffset(12, 3)
    title.Size = UDim2.new(1, -70, 0, 20)

    local valueLabel = labelText(row, tostring(option.Value), 20)
    valueLabel.Position = UDim2.new(1, -58, 0, 3)
    valueLabel.Size = UDim2.fromOffset(46, 20)
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right

    local bar = uiNew("Frame", {
        BackgroundColor3 = Color3.fromRGB(52, 56, 68),
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(12, 34),
        Size = UDim2.new(1, -24, 0, 6),
    }, row)
    uiCorner(bar, 3)
    local fill = uiNew("Frame", {
        BackgroundColor3 = Color3.fromRGB(76, 130, 255),
        BorderSizePixel = 0,
        Size = UDim2.fromScale(0, 1),
    }, bar)
    uiCorner(fill, 3)

    local dragging = false
    local function setFromX(x, emit)
        local width = math.max(1, bar.AbsoluteSize.X)
        local alpha = math.clamp((x - bar.AbsolutePosition.X) / width, 0, 1)
        local value = minValue + (maxValue - minValue) * alpha
        local rounding = tonumber(data.Rounding)
        if rounding == nil or rounding == 0 then
            value = math.floor(value + 0.5)
        else
            local scale = 10 ^ rounding
            value = math.floor(value * scale + 0.5) / scale
        end
        option.Value = value
        fill.Size = UDim2.fromScale((value - minValue) / math.max(1e-6, maxValue - minValue), 1)
        valueLabel.Text = tostring(value)
        if emit and type(data.Callback) == "function" then
            local ok, err = safeCall(data.Callback, value)
            if not ok then markSoftError("UI", err) end
        end
    end

    local function renderValue(value)
        local clamped = math.clamp(tonumber(value) or minValue, minValue, maxValue)
        option.Value = clamped
        fill.Size = UDim2.fromScale((clamped - minValue) / math.max(1e-6, maxValue - minValue), 1)
        valueLabel.Text = tostring(clamped)
    end
    renderValue(option.Value)

    connect(bar.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromX(input.Position.X, true)
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            setFromX(input.Position.X, true)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    function option:SetValue(value)
        renderValue(value)
        if type(data.Callback) == "function" then
            local ok, err = safeCall(data.Callback, self.Value)
            if not ok then markSoftError("UI", err) end
        end
    end

    return option
end

function NativeSection:AddDropdown(id, data)
    data = data or {}
    local values = data.Values or {}
    local index = math.clamp(tonumber(data.Default) or 1, 1, math.max(1, #values))
    local option = createOption(values[index])
    option.Values = values
    local row = createRow(self.Container, 44)
    local title = labelText(row, data.Title or id, 44)
    title.Position = UDim2.fromOffset(12, 0)
    title.Size = UDim2.new(0.48, -12, 1, 0)

    local button = uiNew("TextButton", {
        BackgroundColor3 = Color3.fromRGB(20, 23, 30),
        BorderSizePixel = 0,
        Position = UDim2.new(0.48, 0, 0.5, -14),
        Size = UDim2.new(0.52, -10, 0, 28),
        Font = Enum.Font.Gotham,
        Text = tostring(option.Value or "None"),
        TextSize = 12,
        TextColor3 = Color3.fromRGB(220, 225, 235),
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, row)
    uiCorner(button, 6)

    local popup
    local function closePopup()
        if popup then
            popup:Destroy()
            popup = nil
        end
    end

    local function choose(value)
        option:_emit(value)
        button.Text = tostring(value or "None")
        closePopup()
    end

    connect(button.Activated, function()
        if popup then
            closePopup()
            return
        end
        popup = uiNew("ScrollingFrame", {
            BackgroundColor3 = Color3.fromRGB(22, 25, 32),
            BorderSizePixel = 0,
            Position = UDim2.new(0.48, 0, 1, 2),
            Size = UDim2.new(0.52, -10, 0, math.min(150, math.max(34, #option.Values * 30))),
            CanvasSize = UDim2.new(),
            ScrollBarThickness = 3,
            ZIndex = 40,
        }, row)
        uiCorner(popup, 6)
        local layout = uiList(popup, 2)
        uiPadding(popup, 4, 4, 4, 4)
        for _, value in ipairs(option.Values) do
            local entryValue = value
            local entry = uiNew("TextButton", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, -8, 0, 26),
                Font = Enum.Font.Gotham,
                Text = tostring(entryValue),
                TextSize = 12,
                TextColor3 = Color3.fromRGB(218, 223, 234),
                ZIndex = 41,
            }, popup)
            connect(entry.Activated, function()
                choose(entryValue)
            end)
        end
        attachCanvas(popup, layout)
    end)

    function option:SetValues(newValues)
        self.Values = newValues or {}
        local stillExists = false
        for _, value in ipairs(self.Values) do
            if value == self.Value then
                stillExists = true
                break
            end
        end

        if not stillExists then
            local replacement = self.Values[1]
            self:_emit(replacement)
            button.Text = tostring(replacement or "None")
        else
            button.Text = tostring(self.Value or "None")
        end
        closePopup()
    end

    function option:SetValue(value)
        choose(value)
    end

    return option
end

local NativeTab = {}
NativeTab.__index = NativeTab

function NativeTab:AddSection(title)
    local header = labelText(self.Container, title, 28)
    header.Font = Enum.Font.GothamBold
    header.TextSize = 13
    header.TextColor3 = Color3.fromRGB(150, 164, 195)
    header.LayoutOrder = self.NextOrder
    self.NextOrder += 1

    local holder = uiNew("Frame", {
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        LayoutOrder = self.NextOrder,
    }, self.Container)
    self.NextOrder += 1
    local layout = uiList(holder, 6)

    return setmetatable({
        Container = holder,
        Layout = layout,
    }, NativeSection)
end

local NativeWindow = {}
NativeWindow.__index = NativeWindow

function NativeWindow:AddTab(spec)
    spec = spec or {}
    local index = #self.Tabs + 1
    local tabButton = uiNew("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = Color3.fromRGB(27, 30, 38),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -12, 0, 34),
        Font = Enum.Font.GothamMedium,
        Text = tostring(spec.Title or ("Tab " .. index)),
        TextSize = 12,
        TextColor3 = Color3.fromRGB(160, 166, 180),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, self.Sidebar)
    uiPadding(tabButton, 12, 8, 0, 0)
    uiCorner(tabButton, 7)

    local page = uiNew("ScrollingFrame", {
        Active = true,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.new(),
        ScrollBarThickness = 3,
        Visible = false,
    }, self.Content)
    uiPadding(page, 12, 12, 10, 12)
    local layout = uiList(page, 7)
    attachCanvas(page, layout)

    local tab = setmetatable({
        Title = spec.Title,
        Button = tabButton,
        Container = page,
        Layout = layout,
        NextOrder = 1,
    }, NativeTab)
    table.insert(self.Tabs, tab)

    connect(tabButton.Activated, function()
        self:SelectTab(index)
    end)

    if index == 1 then
        self:SelectTab(1)
    end
    return tab
end

function NativeWindow:SelectTab(index)
    index = tonumber(index) or 1
    for i, tab in ipairs(self.Tabs) do
        local active = i == index
        tab.Container.Visible = active
        tab.Button.BackgroundTransparency = active and 0.05 or 1
        tab.Button.BackgroundColor3 = active and Color3.fromRGB(42, 48, 61) or Color3.fromRGB(27, 30, 38)
        tab.Button.TextColor3 = active and Color3.fromRGB(235, 238, 245) or Color3.fromRGB(160, 166, 180)
    end
end

function NativeUI:CreateWindow(spec)
    spec = spec or {}
    if self.RootGui then
        pcall(function() self.RootGui:Destroy() end)
        self.RootGui = nil
    end

    local parent = nativeParent()
    if not parent then
        return nil
    end

    local gui = uiNew("ScreenGui", {
        Name = "SON_HUB_NATIVE",
        ResetOnSpawn = false,
        IgnoreGuiInset = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 50,
    }, parent)
    self.RootGui = gui
    track(gui)

    local panel = uiNew("Frame", {
        Active = true,
        BackgroundColor3 = Color3.fromRGB(18, 20, 26),
        BorderSizePixel = 0,
        Position = UDim2.new(0.5, -360, 0.5, -260),
        Size = UDim2.fromOffset(720, 520),
    }, gui)
    uiCorner(panel, 10)
    uiStroke(panel, 0.62)

    local header = uiNew("Frame", {
        Active = true,
        BackgroundColor3 = Color3.fromRGB(21, 24, 31),
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 50),
    }, panel)
    uiCorner(header, 10)

    local title = labelText(header, spec.Title or ("SON HUB " .. VERSION), 24)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.Position = UDim2.fromOffset(16, 6)
    title.Size = UDim2.new(1, -80, 0, 22)
    local sub = labelText(header, spec.SubTitle or "Nexomia", 18, 0.25)
    sub.TextSize = 11
    sub.Position = UDim2.fromOffset(16, 27)
    sub.Size = UDim2.new(1, -80, 0, 16)

    local minimize = uiNew("TextButton", {
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -44, 0, 8),
        Size = UDim2.fromOffset(34, 30),
        Font = Enum.Font.GothamBold,
        Text = "—",
        TextSize = 16,
        TextColor3 = Color3.fromRGB(188, 193, 205),
    }, header)

    local body = uiNew("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, 50),
        Size = UDim2.new(1, 0, 1, -50),
    }, panel)

    local sidebar = uiNew("Frame", {
        BackgroundColor3 = Color3.fromRGB(21, 24, 31),
        BorderSizePixel = 0,
        Size = UDim2.new(0, 150, 1, 0),
    }, body)
    uiPadding(sidebar, 6, 6, 8, 8)
    uiList(sidebar, 4)

    local content = uiNew("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(150, 0),
        Size = UDim2.new(1, -150, 1, 0),
        ClipsDescendants = false,
    }, body)

    local window = setmetatable({
        Gui = gui,
        Panel = panel,
        Header = header,
        Sidebar = sidebar,
        Content = content,
        Tabs = {},
        Body = body,
        Minimized = false,
    }, NativeWindow)
    self.Window = window

    local dragStart
    local startPos
    local dragging = false
    connect(header.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = panel.Position
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    local function setMinimized(value)
        window.Minimized = value == true
        body.Visible = not window.Minimized
        panel.Size = window.Minimized and UDim2.fromOffset(720, 50) or UDim2.fromOffset(720, 520)
    end
    connect(minimize.Activated, function()
        setMinimized(not window.Minimized)
    end)
    connect(UserInputService.InputBegan, function(input, processed)
        if not processed and input.KeyCode == Enum.KeyCode.LeftControl then
            setMinimized(not window.Minimized)
        end
    end)

    return window
end

function NativeUI:Notify(spec)
    spec = spec or {}
    local gui = self.RootGui
    if not gui or not gui.Parent then
        pcall(function()
            print("[SON HUB] " .. tostring(spec.Title or "Notice") .. ": " .. tostring(spec.Content or ""))
        end)
        return
    end

    local toast = uiNew("Frame", {
        BackgroundColor3 = Color3.fromRGB(23, 26, 34),
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0, 14 + (#self.Toasts * 74)),
        Size = UDim2.fromOffset(310, 64),
        ZIndex = 100,
    }, gui)
    uiCorner(toast, 8)
    uiStroke(toast, 0.7)
    local title = labelText(toast, spec.Title or "SON HUB", 20)
    title.Position = UDim2.fromOffset(10, 7)
    title.Size = UDim2.new(1, -20, 0, 18)
    title.Font = Enum.Font.GothamBold
    title.ZIndex = 101
    local content = labelText(toast, spec.Content or "", 30, 0.08)
    content.Position = UDim2.fromOffset(10, 27)
    content.Size = UDim2.new(1, -20, 0, 30)
    content.TextWrapped = true
    content.TextSize = 11
    content.ZIndex = 101
    table.insert(self.Toasts, toast)

    task.delay(math.max(1, tonumber(spec.Duration) or 3), function()
        for i, item in ipairs(self.Toasts) do
            if item == toast then
                table.remove(self.Toasts, i)
                break
            end
        end
        pcall(function() toast:Destroy() end)
        for i, item in ipairs(self.Toasts) do
            pcall(function()
                item.Position = UDim2.new(1, -14, 0, 14 + ((i - 1) * 74))
            end)
        end
    end)
end

function NativeUI:Destroy()
    if self.RootGui then
        pcall(function() self.RootGui:Destroy() end)
    end
    self.RootGui = nil
    self.Window = nil
    table.clear(self.Toasts)
end

local UIFramework = NativeUI
bootMark("native-ui-ready")



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
    DirectQuest = true,

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

    -- Server info / live watch
    InfoBossNotify = false,
    InfoEventNotify = false,
    InfoPollInterval = 2.0,

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

bootMark("runtime-init")
Runtime = {
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
        TagAttempts = 0,
        AggroDeadline = 0,
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
    StatsSpendPending = false,
    StatsSpendStatus = "Idle",
    StatsSpendAttemptId = 0,
    StatsPhysicalFallbacks = 0,
    StatsLastConfirmed = nil,

    InfoLastBossKey = nil,
    InfoLastEventKey = nil,

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
    FishingRodReason = "Not checked",
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
    MiningIndexRefreshes = 0,
    ProgressLifeSkill = nil,

    IslandLandingCache = {},


    ClaimButtons = setmetatable({}, {__mode = "k"}),

    BlockHeld = false,

    QuestCatalog = {},
    QuestCatalogByName = {},
    QuestToNPCs = {},

    LastLevel = nil,
    ServerHopBusy = false,
    IndexRefreshBusy = false,

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

connect = function(signal, callback)
    if not signal or type(callback) ~= "function" then
        return nil
    end

    local okConnect, connection = pcall(function()
        return signal:Connect(function(...)
            local ok, result = safeCall(callback, ...)
            if not ok then
                markSoftError("Events", result)
            end
        end)
    end)

    if not okConnect or not connection then
        markSoftError("Events", connection or "signal connect failed")
        return nil
    end

    table.insert(Core.Connections, connection)
    return connection
end

track = function(instance)
    table.insert(Core.Instances, instance)
    return instance
end

connect(Workspace.DescendantAdded, function(object)
    NoiseGuard.PatchDialogueObject(object)
end)

connect(ReplicatedStorage.DescendantAdded, function(object)
    NoiseGuard.PatchDialogueObject(object)
    NoiseGuard.PatchSound(object)
end)

local function notify(title, description, duration)
    if not UIFramework then
        return
    end

    pcall(function()
        UIFramework:Notify({
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

local function guiScreenPosition(guiObject)
    if not guiObject or not guiObject:IsA("GuiObject") then
        return nil
    end

    local pos = guiObject.AbsolutePosition
    local screen = guiObject:FindFirstAncestorWhichIsA("ScreenGui")

    if screen and screen.IgnoreGuiInset == false and GuiService then
        local ok, topLeftInset = pcall(function()
            local topLeft = GuiService:GetGuiInset()
            return topLeft
        end)
        if ok and typeof(topLeftInset) == "Vector2" then
            pos += topLeftInset
        end
    end

    return pos
end

local function guiClickPoint(guiObject)
    local pos = guiScreenPosition(guiObject)
    if not pos then
        return nil
    end
    local size = guiObject.AbsoluteSize
    return Vector2.new(pos.X + size.X / 2, pos.Y + size.Y / 2)
end

local function isOnScreen(guiObject)
    if not guiObject or not guiObject:IsA("GuiObject") or not isGuiVisible(guiObject) then
        return false
    end

    local pos = guiScreenPosition(guiObject)
    local size = guiObject.AbsoluteSize
    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)

    return pos ~= nil
        and size.X > 0
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
    return Compat.Key(false, key) or Compat.ReleaseKey(key)
end

local function mouseClickAt(x, y)
    if not Compat.Mouse(x, y, true) then
        return false
    end
    task.wait(0.025)
    return Compat.Mouse(x, y, false) or Compat.ReleaseMouse(x, y)
end

local function mouseClickCenter()
    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)
    return mouseClickAt(viewport.X / 2, viewport.Y / 2)
end

local function mouseButtonAt(x, y, held)
    return Compat.Mouse(x, y, held)
end

local function screenPointOf(object)
    local camera = Workspace.CurrentCamera
    local part = objectRoot(object)
    if not camera or not part then
        return nil
    end

    -- Virtual mouse input uses screen coordinates. WorldToViewportPoint omits
    -- the CoreGui inset, which is exactly the ~58 px offset present in this
    -- game's snapshot. Prefer WorldToScreenPoint so mining/world M1 is aimed
    -- at the same coordinate space as QTE button clicks.
    local okScreen, point, visible = pcall(function()
        return camera:WorldToScreenPoint(part.Position)
    end)

    if not okScreen then
        point, visible = camera:WorldToViewportPoint(part.Position)
        if visible and point.Z > 0 and GuiService then
            local okInset, topLeft = pcall(function()
                return GuiService:GetGuiInset()
            end)
            if okInset and typeof(topLeft) == "Vector2" then
                point = Vector3.new(point.X + topLeft.X, point.Y + topLeft.Y, point.Z)
            end
        end
    end

    if not visible or not point or point.Z <= 0 then
        return nil
    end

    return Vector2.new(point.X, point.Y)
end

local function clickButton(button, allowHiddenSignal)
    if not button or not button:IsA("GuiButton") then
        return false
    end

    local interactable = true
    pcall(function()
        interactable = button.Interactable ~= false
    end)
    if not interactable then
        return false
    end

    -- Prefer a real screen click whenever the button is visible. On Nexomia,
    -- firesignal can return without throwing even when the game handler did not
    -- actually run; using it first created false-positive "clicked" states.
    if isOnScreen(button) then
        local point = guiClickPoint(button)
        if point and mouseClickAt(point.X, point.Y) then
            return true
        end
    end

    if allowHiddenSignal == true or isGuiVisible(button) then
        return Compat.FireSignal(button.Activated)
    end

    return false
end

local function clickButtonReliable(button)
    if not button or not button:IsA("GuiButton") then
        return false
    end

    if isOnScreen(button) then
        return clickButton(button, false)
    end

    -- Hidden menu buttons cannot be physically clicked without changing the
    -- player's UI. Signal firing is therefore only the hidden-button fallback.
    return Compat.FireSignal(button.Activated)
end

local function clickVisibleButton(button)
    if not button or not button:IsA("GuiButton") or not isOnScreen(button) then
        return false
    end

    local point = guiClickPoint(button)
    return point ~= nil and mouseClickAt(point.X, point.Y) or false
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
    LastPressedSlot = nil,
    LastPressedTitle = nil,
    LastPressedAt = 0,
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
    if not data then
        return false
    end

    local ok = pressKey(data.Key, 0.03)
    if ok then
        HotbarService.LastPressedSlot = data.Slot
        HotbarService.LastPressedTitle = data.Title
        HotbarService.LastPressedAt = os.clock()
    end
    return ok
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

    if model:GetAttribute("Dead") == true
        and model:GetAttribute("Ragdolled") == true then
        return "CORPSE"
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

    return objectRoot(model) and "ALIVE" or "INVALID"
end

function TargetService.IsAliveNPC(model)
    return TargetService.GetLifeState(model) == "ALIVE"
end

function TargetService.IsAggroedToLocal(model)
    if not TargetService.IsAliveNPC(model) then
        return false
    end

    local target = model:GetAttribute("Target")

    -- Snapshot evidence shows Target is the exact player/entity name. If the
    -- attribute exists, trust it instead of falling through to generic combat
    -- flags (which can be true while the mob is fighting somebody else).
    if target ~= nil then
        local current = lower(target)
        local wanted = lower(LocalPlayer.Name)
        return current ~= "" and current == wanted
    end

    -- Compatibility fallback only for entities that do not expose Target.
    return model:GetAttribute("NPCCombat") == true
        and model:GetAttribute("PlayerCombat") == true
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
    local set = {}

    -- Use persistent MobZone metadata first. A mob being dead/respawning should
    -- not make its dropdown entry disappear and later cause a false not-found.
    local important = Workspace:FindFirstChild("AA IMPORTANT")
    local zonesRoot = important and important:FindFirstChild("MobZones")
    if zonesRoot then
        for _, object in ipairs(zonesRoot:GetDescendants()) do
            if object:IsA("BasePart") and object:GetAttribute("Active") ~= false then
                local mobName = normalize(object:GetAttribute("Mob") or "")
                if mobName ~= "" then
                    set[mobName] = true
                end
            end
        end
    end

    -- Merge currently live hostile entities so streamed/runtime-only mobs still
    -- appear even when no MobZone metadata exists for them.
    local folder = entitiesFolder()
    if folder then
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") and TargetService.IsHostile(model) then
                local name = tostring(
                    model:GetAttribute("NPCType")
                    or model:GetAttribute("NPCName")
                    or stripRuntimeSuffix(model.Name)
                )

                if name ~= ""
                    and name ~= "Nearest Hostile"
                    and name ~= "Boss Only" then
                    set[name] = true
                end
            end
        end
    end

    local rows = {}
    for name in pairs(set) do
        table.insert(rows, name)
    end
    table.sort(rows)

    local result = {"Nearest Hostile", "Boss Only"}
    for _, name in ipairs(rows) do
        table.insert(result, name)
    end
    return result
end

-- ============================================================
-- Motion
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
    SnapOnArrival = false,
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

function MotionController.Release(owner, force, preserveVelocity)
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
    if root and not preserveVelocity then
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
    motion.SnapOnArrival = false

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
        MotionController.Release(motion.Owner, true, true)
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
    motion.SnapOnArrival = options.SnapOnArrival == true

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
        pcall(function()
            tween:Play()
        end)
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
                local finalPosition = motion.SnapOnArrival
                    and goal.Position
                    or root.Position
                root.CFrame = motionYawCFrame(
                    finalPosition,
                    motion.FacePosition or goal.Position
                )
                if root.AssemblyLinearVelocity.Magnitude > 0.75 then
                    root.AssemblyLinearVelocity = Vector3.zero
                end
                if root.AssemblyAngularVelocity.Magnitude > 0.75 then
                    root.AssemblyAngularVelocity = Vector3.zero
                end
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
                pcall(function()
                    tween:Play()
                end)
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
            and part:GetAttribute("Active") ~= false then

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
    gather.TagAttempts = 0
    gather.AggroDeadline = 0
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
        gather.TagAttempts = 0
        gather.AggroDeadline = 0
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

            if TargetService.IsAggroedToLocal(target) then
                gather.State = "RETURN"
                gather.PhaseSince = now
                return false, "already aggroed"
            end

            local clicked = mouseClickCenter()
            if not clicked then
                gather.TagAttempts += 1
                if gather.TagAttempts >= 3 then
                    gather.Failures += 1
                    gather.Cooldown[target] = now + 1.5
                    gather.Target = nil
                    gather.State = "PICK"
                    return false, "tag input failed"
                end
                return false, "tag input retry"
            end

            gather.TagAttempts += 1
            gather.AggroDeadline = now + 0.55
            gather.State = "WAIT_AGGRO"
            gather.PhaseSince = now
        end

        return false, "tagging"
    end

    if gather.State == "WAIT_AGGRO" then
        if TargetService.IsAggroedToLocal(target) then
            gather.State = "RETURN"
            gather.PhaseSince = now
            return false, "aggro confirmed"
        end

        if now < (gather.AggroDeadline or 0) then
            return false, "confirming aggro"
        end

        if gather.TagAttempts < 3 then
            gather.State = "TAG_TRAVEL"
            gather.PhaseSince = now
            return false, "retrying tag"
        end

        gather.Failures += 1
        gather.Cooldown[target] = now + 2.0
        gather.Target = nil
        gather.State = "PICK"
        gather.PhaseSince = now
        return false, "aggro not confirmed"
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
-- Direct quest bridge
-- Learns a verified outbound quest call from the game's own dialogue flow.
-- It never guesses a RemoteEvent/RemoteFunction signature.
-- ============================================================

QuestDirectService = {}

Runtime.QuestDirect = {
    Installed = false,
    HookOld = nil,
    Context = nil,
    Candidate = nil,
    Template = nil,
    ExactTemplates = {},
    Busy = false,
    Replaying = false,
    AttemptAt = 0,
    BeforeState = nil,
    TargetQuest = nil,
    LastResult = "not learned",
    LastError = nil,
    Failures = 0,
}

local DIRECT_QUEST_REMOTE_NAMES = {
    PromptQuest = true,
    RunDialogueFunctionOnServer = true,
    DialogueRemote = true,
}

local function directRelativePath(root, object)
    if not root or not object then
        return nil
    end
    local names = {}
    local current = object
    while current and current ~= root do
        table.insert(names, 1, current.Name)
        current = current.Parent
    end
    if current ~= root then
        return nil
    end
    return names
end

local function directResolvePath(root, names)
    local current = root
    for _, name in ipairs(names or {}) do
        current = current and current:FindFirstChild(name)
        if not current then
            return nil
        end
    end
    return current
end

local function encodeDirectValue(value, context, depth)
    depth = depth or 0
    if depth > 4 then
        return nil, false, false
    end

    local valueType = typeof(value)
    if valueType == "string" then
        if context and context.Name and lower(value) == lower(context.Name) then
            return {__son = "quest_name"}, true, true
        end
        return {__son = "literal", value = value}, true, false
    elseif valueType == "number" then
        if context and context.Id ~= nil and tostring(value) == tostring(context.Id) then
            return {__son = "quest_id"}, true, true
        end
        return {__son = "literal", value = value}, true, false
    elseif valueType == "boolean" or value == nil then
        return {__son = "literal", value = value}, true, false
    elseif valueType == "Instance" then
        if context and context.NPC and value == context.NPC then
            return {__son = "npc"}, true, true
        end
        if context and context.NPC and value:IsDescendantOf(context.NPC) then
            local path = directRelativePath(context.NPC, value)
            if path then
                return {__son = "npc_path", path = path}, true, true
            end
        end
        -- ReplicatedStorage references are stable enough to preserve exactly.
        if value:IsDescendantOf(ReplicatedStorage) then
            return {__son = "instance", value = value}, true, false
        end
        return nil, false, false
    elseif valueType == "table" then
        local result = {__son = "table", values = {}}
        local dynamic = false
        for key, child in pairs(value) do
            local encodedKey, okKey, keyDynamic = encodeDirectValue(key, context, depth + 1)
            local encodedValue, okValue, valueDynamic = encodeDirectValue(child, context, depth + 1)
            if not okKey or not okValue then
                return nil, false, false
            end
            table.insert(result.values, {encodedKey, encodedValue})
            dynamic = dynamic or keyDynamic or valueDynamic
        end
        return result, true, dynamic
    end

    return nil, false, false
end

local function decodeDirectValue(encoded, context)
    if type(encoded) ~= "table" then
        return nil, false
    end
    local kind = encoded.__son
    if kind == "literal" then
        return encoded.value, true
    elseif kind == "quest_name" then
        return context and context.Name or nil, context and context.Name ~= nil
    elseif kind == "quest_id" then
        return context and context.Id or nil, context and context.Id ~= nil
    elseif kind == "npc" then
        return context and context.NPC or nil, context and context.NPC ~= nil
    elseif kind == "npc_path" then
        local value = context and directResolvePath(context.NPC, encoded.path)
        return value, value ~= nil
    elseif kind == "instance" then
        return encoded.value, encoded.value ~= nil and encoded.value.Parent ~= nil
    elseif kind == "table" then
        local result = {}
        for _, pair in ipairs(encoded.values or {}) do
            local key, okKey = decodeDirectValue(pair[1], context)
            local value, okValue = decodeDirectValue(pair[2], context)
            if not okKey or not okValue then
                return nil, false
            end
            result[key] = value
        end
        return result, true
    end
    return nil, false
end

local function makeDirectContext(questName, npc)
    local id
    local recommended = QuestService.GetRecommended()
    if recommended and lower(recommended.Name) == lower(questName) then
        id = recommended.Id
    else
        for _, quest in ipairs(QuestService.GetActiveQuests()) do
            if lower(quest.Name) == lower(questName) then
                id = quest.Id
                break
            end
        end
    end
    return {
        Name = questName,
        Id = id,
        NPC = npc,
    }
end

function QuestDirectService.SetContext(questName, npc)
    if not questName or questName == "" then
        Runtime.QuestDirect.Context = nil
        return
    end
    Runtime.QuestDirect.Context = makeDirectContext(questName, npc)
end

function QuestDirectService.Observe(remote, method, args)
    local state = Runtime.QuestDirect
    if state.Replaying or not Config.DirectQuest or not state.Context then
        return
    end
    if not remote or not DIRECT_QUEST_REMOTE_NAMES[remote.Name] then
        return
    end
    if method ~= "FireServer" and method ~= "InvokeServer" then
        return
    end

    local encodedArgs = {}
    local dynamic = false
    for index = 1, args.n do
        local encoded, ok, isDynamic = encodeDirectValue(args[index], state.Context, 0)
        if not ok then
            return
        end
        encodedArgs[index] = encoded
        dynamic = dynamic or isDynamic
    end

    state.Candidate = {
        Remote = remote,
        Method = method,
        Args = encodedArgs,
        ArgCount = args.n,
        Dynamic = dynamic,
        QuestName = state.Context.Name,
        BeforeState = QuestService.StateKey(),
        SeenAt = os.clock(),
    }
end

function QuestDirectService.Poll()
    local state = Runtime.QuestDirect
    local now = os.clock()

    if state.Candidate then
        local changed = QuestService.StateKey() ~= state.Candidate.BeforeState
        if changed then
            local candidate = state.Candidate
            if candidate.Dynamic then
                state.Template = candidate
            else
                state.ExactTemplates[lower(candidate.QuestName)] = candidate
            end
            state.LastResult = candidate.Dynamic
                and "learned generic quest call"
                or "learned exact quest call"
            state.Candidate = nil
        elseif now - state.Candidate.SeenAt > 2.0 then
            state.Candidate = nil
        end
    end

    if state.Busy then
        if QuestService.StateKey() ~= state.BeforeState then
            state.Busy = false
            state.Failures = 0
            state.LastResult = "direct quest accepted"
            state.LastError = nil
            return true
        end
        if now - state.AttemptAt > 1.35 then
            state.Busy = false
            state.Replaying = false
            state.Failures += 1
            state.LastResult = "direct call had no quest-state confirmation"
            return false
        end
    end

    return nil
end

local function resolveDirectNpc(questName)
    if TargetService and QuestCatalogService then
        return QuestCatalogService.FindQuestGiver(questName, nil)
            or TargetService.FindNamedDialogueNPC(questName)
    end
    return nil
end

local function directBuildArgs(template, context)
    local args = table.create(template.ArgCount or 0)
    for index = 1, template.ArgCount or 0 do
        local value, ok = decodeDirectValue(template.Args[index], context)
        if not ok then
            return nil, "argument " .. tostring(index) .. " could not be resolved"
        end
        args[index] = value
    end
    return args
end

function QuestDirectService.TryAccept(recommended)
    local state = Runtime.QuestDirect
    QuestDirectService.Poll()

    if not Config.DirectQuest then
        return false, "disabled"
    end
    if state.Busy then
        return false, "pending"
    end
    if not recommended or not recommended.Name then
        return false, "missing recommended quest"
    end
    if state.Failures >= 2 then
        return false, "direct quest temporarily disabled after failed verification"
    end

    local template = state.Template or state.ExactTemplates[lower(recommended.Name)]
    if not template or not template.Remote or not template.Remote.Parent then
        return false, state.Installed and "learning" or "hook unavailable"
    end

    local context = makeDirectContext(
        recommended.Name,
        resolveDirectNpc(recommended.Name)
    )
    context.Id = recommended.Id or context.Id

    if not template.Dynamic and lower(template.QuestName) ~= lower(recommended.Name) then
        return false, "exact template belongs to another quest"
    end

    local args, buildError = directBuildArgs(template, context)
    if not args then
        return false, buildError
    end

    state.Busy = true
    state.Replaying = true
    state.AttemptAt = os.clock()
    state.BeforeState = QuestService.StateKey()
    state.TargetQuest = recommended.Name
    state.LastResult = "direct quest call pending"

    task.spawn(function()
        local ok, result
        if template.Method == "InvokeServer" and template.Remote:IsA("RemoteFunction") then
            ok, result = safeCall(template.Remote.InvokeServer, template.Remote, table.unpack(args, 1, template.ArgCount))
        elseif template.Method == "FireServer" and template.Remote:IsA("RemoteEvent") then
            ok, result = safeCall(template.Remote.FireServer, template.Remote, table.unpack(args, 1, template.ArgCount))
        else
            ok, result = false, "remote/method mismatch"
        end
        state.Replaying = false
        if not ok then
            state.LastError = tostring(result)
        end
    end)

    return false, "pending"
end

function QuestDirectService.Status()
    local state = Runtime.QuestDirect
    return table.concat({
        "Installed: " .. tostring(state.Installed),
        "Generic template: " .. tostring(state.Template ~= nil),
        "Busy: " .. tostring(state.Busy),
        "Failures: " .. tostring(state.Failures),
        "Last: " .. tostring(state.LastResult),
        "Error: " .. tostring(state.LastError or "none"),
    }, "\n")
end

function QuestDirectService.Install()
    local state = Runtime.QuestDirect
    if state.Installed then
        return true
    end
    if type(hookMetamethodFn) ~= "function" or type(getNamecallMethodFn) ~= "function" then
        state.LastResult = "hookmetamethod/getnamecallmethod unavailable"
        return false
    end

    local oldNamecall
    local callback = function(self, ...)
        local method
        local remoteName
        pcall(function()
            method = getNamecallMethodFn()
            remoteName = self and self.Name or nil
        end)

        if remoteName and DIRECT_QUEST_REMOTE_NAMES[remoteName] then
            local packed = table.pack(...)
            pcall(QuestDirectService.Observe, self, method, packed)
        end

        if type(oldNamecall) == "function" then
            return oldNamecall(self, ...)
        end
        return nil
    end

    if type(newCClosureFn) == "function" then
        local okWrap, wrapped = pcall(newCClosureFn, callback)
        if okWrap and type(wrapped) == "function" then
            callback = wrapped
        end
    end

    local ok, old = pcall(hookMetamethodFn, game, "__namecall", callback)
    if not ok or type(old) ~= "function" then
        state.LastResult = "namecall hook failed"
        return false
    end

    oldNamecall = old
    state.HookOld = old
    state.Installed = true
    state.LastResult = "waiting for verified quest call"
    return true
end

function QuestDirectService.Uninstall()
    local state = Runtime.QuestDirect
    if state.Installed and state.HookOld and type(hookMetamethodFn) == "function" then
        pcall(hookMetamethodFn, game, "__namecall", state.HookOld)
    end
    state.Installed = false
    state.HookOld = nil
end

pcall(QuestDirectService.Install)

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

    -- Sending input is not proof that the game accepted it. Record the
    -- quest state and only report success after dialogue opens or quest state
    -- changes. This prevents false NPC_TRIGGER states on partial-UNC input.
    local beforeQuestState = QuestService.StateKey()

    pressKey(
        prompt.KeyboardKeyCode,
        math.max(0.07, (prompt.HoldDuration or 0) + 0.04)
    )

    task.wait(0.10)
    if dialogueIsOpen(npc) then
        return true
    end

    -- Executor helper is only fallback because some custom prompts ignore it.
    if Compat.FirePrompt(prompt, prompt.HoldDuration) then
        task.wait(0.10)
    end

    local afterQuestState = QuestService.StateKey()
    return dialogueIsOpen(npc)
        or afterQuestState ~= beforeQuestState
end

-- ============================================================
-- Mastery / combat
-- ============================================================

CombatService = {}

local function setBlock(held)
    if Runtime.BlockHeld == held then
        return true
    end

    local ok = Compat.Key(held, Enum.KeyCode.F)
    if not ok and not held then
        ok = Compat.ReleaseKey(Enum.KeyCode.F)
    end

    if ok then
        Runtime.BlockHeld = held
    end
    return ok
end

function CombatService.AimAt(model)
    -- Auto Farm v14 deliberately avoids rotating the character every
    -- scheduler tick because that caused stationary jitter.
    return false
end

function CombatService.AttackStep()
    if not Config.AutoAttack then
        return false, "disabled"
    end

    local now = os.clock()
    local minimumDelay =
        1 / math.max(1, Config.AttackRate)

    if now - Runtime.LastAttack < minimumDelay then
        return false, "cooldown"
    end

    -- Do not consume the attack timer if executor input failed; otherwise one
    -- failed click is incorrectly treated like a successful attack cooldown.
    local sent = mouseClickCenter()
    if not sent then
        return false, "input-failed"
    end

    Runtime.LastAttack = now
    return true, "sent"
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
        local digits = tostring(label.Text or ""):gsub("[%s,%.]", ""):match("(%d+)")
        return digits and tonumber(digits) or nil
    end

    -- nil means "unknown / UI not replicated". Zero means a real 0.
    return nil
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
                and tonumber((tostring(label.Text or ""):gsub("[%s,%.]", "")):match("(%d+)"))
                or 0
        end
    end

    return values
end

local function statButton(stat)
    local radar = radarFrame()
    local frame = radar and radar:FindFirstChild(stat or "")
    local button = frame and frame:FindFirstChild("ImageButton")
    return button and button:IsA("ImageButton") and button or nil
end

local function fireStatSignals(button)
    if not button then
        return false
    end

    local sent = false
    local signals = {
        button.Activated,
        button.MouseButton1Click,
        button.MouseButton1Down,
        button.MouseButton1Up,
    }

    for _, signal in ipairs(signals) do
        if signal and Compat.FireSignal(signal) then
            sent = true
        end
    end

    return sent
end

local function physicalStatClick(button)
    if not button or not button.Parent then
        return false, "button unavailable"
    end

    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local menu = playerGui and playerGui:FindFirstChild("Menu")
    if not menu or not menu:IsA("ScreenGui") then
        return false, "menu unavailable"
    end

    local previousEnabled = menu.Enabled
    local hubGui = NativeUI and NativeUI.Window and NativeUI.Window.Gui
    local hubWasEnabled = hubGui and hubGui.Enabled

    if hubGui and hubWasEnabled then
        hubGui.Enabled = false
    end

    if not previousEnabled then
        menu.Enabled = true
        RunService.RenderStepped:Wait()
        RunService.RenderStepped:Wait()
    end

    local ok = clickVisibleButton(button)

    task.defer(function()
        if not previousEnabled and menu and menu.Parent then
            menu.Enabled = false
        end
        if hubGui and hubGui.Parent and hubWasEnabled then
            hubGui.Enabled = true
        end
    end)

    return ok, ok and "physical click" or "physical click failed"
end

function StatsService.ClickStat(stat, physicalOnly)
    local button = statButton(stat)
    if not button then
        return false, "Radar button unavailable"
    end

    if physicalOnly == true then
        return physicalStatClick(button)
    end

    if isOnScreen(button) then
        local clicked = clickVisibleButton(button)
        return clicked, clicked and "visible click" or "visible click failed"
    end

    if fireStatSignals(button) then
        return true, "signal click"
    end

    return physicalStatClick(button)
end

local function statsConfirmationDelay()
    local ping = 0.15
    pcall(function()
        ping = math.max(0.05, LocalPlayer:GetNetworkPing())
    end)
    return math.clamp(0.30 + ping * 3.0, 0.35, 1.25)
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
        totalWeight += (weights[name] or 0)
        totalValue += (values[name] or 0)
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

function StatsService.SpendOne(force)
    local forceOnce = force == true
    if not Config.AutoStats and not forceOnce then
        Runtime.StatsSpendStatus = "Disabled"
        return false
    end

    if Runtime.StatsSpendPending then
        Runtime.StatsSpendStatus = "Waiting for confirmation"
        return false
    end

    local now = os.clock()
    local backoff = math.min(1.0, (Runtime.StatsSpendFailures or 0) * 0.12)
    if now - Runtime.LastStatsSpend < math.max(0.12, Config.StatSpendInterval + backoff) then
        return false
    end

    local before = StatsService.GetStatPoints()
    if before == nil then
        Runtime.StatsSpendStatus = "Waiting for Radar/stat points"
        return false
    end
    if before <= 0 then
        Runtime.StatsSpendStatus = "No points"
        Runtime.StatsSpendFailures = 0
        return false
    end

    local stat = StatsService.ChooseStat()
    if not stat then
        Runtime.StatsSpendStatus = "No stat target"
        return false
    end

    Runtime.LastStatsSpend = now
    Runtime.StatsSpendAttemptId += 1
    local attemptId = Runtime.StatsSpendAttemptId

    local clicked, clickReason = StatsService.ClickStat(stat, false)
    if not clicked then
        Runtime.StatsSpendFailures += 1
        Runtime.StatsSpendStatus = "Input failed: " .. tostring(clickReason)
        return false
    end

    Runtime.StatsSpendPending = true
    Runtime.StatsSpendStatus = "Pending " .. tostring(stat) .. " via " .. tostring(clickReason)

    task.spawn(function()
        local deadline = os.clock() + statsConfirmationDelay()
        local confirmed = false

        while Core.Running
            and (Config.AutoStats or forceOnce)
            and Runtime.StatsSpendAttemptId == attemptId
            and os.clock() <= deadline do

            local after = StatsService.GetStatPoints()
            if after ~= nil and after < before then
                confirmed = true
                Runtime.StatsSpendFailures = 0
                Runtime.StatsLastConfirmed = stat
                Runtime.StatsSpendStatus = "Spent: " .. tostring(stat)
                break
            end
            task.wait(0.08)
        end

        if not confirmed
            and Core.Running
            and (Config.AutoStats or forceOnce)
            and Runtime.StatsSpendAttemptId == attemptId then

            -- Hidden GUI signals are executor-sensitive. If the server did not
            -- confirm them, briefly expose the real Radar and perform one
            -- physical click using the exact screen coordinate.
            local physicalOk, physicalReason = StatsService.ClickStat(stat, true)
            if physicalOk then
                Runtime.StatsPhysicalFallbacks += 1
                Runtime.StatsSpendStatus = "Physical retry: " .. tostring(stat)
                local physicalDeadline = os.clock() + statsConfirmationDelay()

                while Core.Running
                    and (Config.AutoStats or forceOnce)
                    and Runtime.StatsSpendAttemptId == attemptId
                    and os.clock() <= physicalDeadline do

                    local after = StatsService.GetStatPoints()
                    if after ~= nil and after < before then
                        confirmed = true
                        Runtime.StatsSpendFailures = 0
                        Runtime.StatsLastConfirmed = stat
                        Runtime.StatsSpendStatus = "Spent: " .. tostring(stat) .. " (physical fallback)"
                        break
                    end
                    task.wait(0.08)
                end
            else
                Runtime.StatsSpendStatus = "Physical retry failed: " .. tostring(physicalReason)
            end
        end

        if not confirmed and Runtime.StatsSpendAttemptId == attemptId then
            Runtime.StatsSpendFailures += 1
            Runtime.StatsSpendStatus = "No server confirmation: " .. tostring(stat)
        end

        if Runtime.StatsSpendAttemptId == attemptId then
            Runtime.StatsSpendPending = false
        end
    end)

    return true
end

function StatsService.GetSnapshot()
    local values = StatsService.GetValues()
    local points = StatsService.GetStatPoints()
    local rows = {
        "Points: " .. tostring(points ~= nil and points or "Unavailable"),
        "Build: " .. StatsService.GetBuild(),
        "Status: " .. tostring(Runtime.StatsSpendStatus),
        "Last confirmed: " .. tostring(Runtime.StatsLastConfirmed or "none"),
        "Physical fallbacks: " .. tostring(Runtime.StatsPhysicalFallbacks or 0),
        "Failures: " .. tostring(Runtime.StatsSpendFailures or 0),
    }

    for _, name in ipairs(STAT_NAMES) do
        table.insert(rows, name .. ": " .. tostring(values[name] or 0))
    end

    return table.concat(rows, "\n")
end

-- ============================================================
-- Fishing
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

local function setFishingMouseHeld(held, force)
    if Runtime.FishingMouseHeld == held and not (force and held == false) then
        return true
    end

    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)
    local x = viewport.X / 2
    local y = viewport.Y / 2

    local ok = Compat.Mouse(x, y, held)
    if not held then
        -- A toggle can be switched off while our bookkeeping says "released"
        -- even though the executor dropped the previous Button1Up. Force a real
        -- release on reset/clean so the user's screen cannot remain held.
        ok = Compat.ReleaseMouse(x, y) or ok
    end

    if ok then
        Runtime.FishingMouseHeld = held
    end
    return ok
end

local function releaseFishingKey()
    if not Runtime.FishingKeyHeld then
        return true
    end

    local key = Runtime.FishingKeyHeld
    local ok = Compat.Key(false, key) or Compat.ReleaseKey(key)
    if ok then
        Runtime.FishingKeyHeld = nil
    end
    return ok
end

local function holdFishingKey(key)
    if Runtime.FishingKeyHeld == key then
        return true
    end

    if not releaseFishingKey() then
        return false
    end

    local ok = Compat.Key(true, key)
    if ok then
        Runtime.FishingKeyHeld = key
    end
    return ok
end

local function findHotbarRod()
    local hotbar = findHotbar()
    if not hotbar then
        return nil, "Hotbar UI is not client-visible yet"
    end

    HotbarService.Refresh()

    for _, data in pairs(HotbarService.Slots) do
        local value = lower(data.Title)

        if value:find("rod", 1, true) then
            return {
                Name = data.Title,
                Source = "Hotbar",
                Hotbar = data,
            }, "Rod found in hotbar"
        end
    end

    return nil, "No rod in live hotbar"
end

local function findInventoryRod()
    local inventory = fishInventory()
    if not inventory then
        return nil, "FishInventory UI is not client-visible yet"
    end

    local root = inventory:FindFirstChild("Inventory")
        and inventory.Inventory:FindFirstChild("Inventory")

    local rodFrame = root and root:FindFirstChild("RodFrame")
    local inner = rodFrame and rodFrame:FindFirstChild("Frame")
    local itemName = inner and inner:FindFirstChild("ItemName")
    local equip = inner and inner:FindFirstChild("Equip")

    if itemName and itemName:IsA("TextLabel") then
        local name = normalize(itemName.Text):gsub("^%[", ""):gsub("%]$", "")
        if name ~= "" then
            return {
                Name = name,
                Source = "FishInventory",
                EquipButton = equip,
            }, "Rod found in FishInventory"
        end
    end

    return nil, "No rod in FishInventory rod frame"
end

function FishingService.FindRod()
    local now = os.clock()

    if Runtime.FishingRodCache
        and now - Runtime.FishingRodCacheAt < 1.0 then
        return Runtime.FishingRodCache
    end

    Runtime.FishingRodCacheAt = now

    local hotbarRod, hotbarReason = findHotbarRod()
    if hotbarRod then
        Runtime.FishingRodCache = hotbarRod
        Runtime.FishingRodReason = hotbarReason
        return hotbarRod
    end

    local inventoryRod, inventoryReason = findInventoryRod()
    Runtime.FishingRodCache = inventoryRod
    Runtime.FishingRodReason = inventoryRod
        and inventoryReason
        or (tostring(hotbarReason) .. " | " .. tostring(inventoryReason))
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
            water and "Detected Anchor Town water edge" or "Anchor Town water is not client-visible yet"
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
        if not clickVisibleButton(button) then
            setFishingState("SHAKE_INPUT_FAILED", "SHAKE button visible but click input failed")
            return true
        end
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
        if not clickVisibleButton(button) then
            setFishingState("SPAM_INPUT_FAILED", "CLICK QTE visible but click input failed")
            return true
        end
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
        if not setFishingMouseHeld(true) then
            setFishingState("TIMED_RELEASE_INPUT_FAILED", "Unable to hold fishing input")
            return true
        end
        setFishingState(
            "TIMED_RELEASE",
            string.format("Holding %.0f%%", fill * 100)
        )
    else
        if not setFishingMouseHeld(false) then
            setFishingState("TIMED_RELEASE_INPUT_FAILED", "Unable to release fishing input")
            return true
        end
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
        if not setFishingMouseHeld(true) then
            setFishingState("REEL_INPUT_FAILED", "Unable to calibrate fishing hold input")
            return true
        end
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
    if not setFishingMouseHeld(shouldHold) then
        setFishingState("REEL_INPUT_FAILED", "Unable to control reel input")
        return true
    end
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

    local now = os.clock()
    if Runtime.FishingEquippedRod == rod.Name
        and now - (Runtime.FishingEquippedAt or 0) < 12 then

        if rod.Source ~= "Hotbar"
            or HotbarService.LastPressedTitle == rod.Name then
            return true
        end
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
        RodReason = Runtime.FishingRodReason,
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
    if MotionController.IsOwnedBy("Fishing") then
        MotionController.Release("Fishing", true)
    end
    releaseFishingKey()
    setFishingMouseHeld(false, true)
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
        setFishingState("WAIT_ROD", tostring(Runtime.FishingRodReason or "Rod UI is not ready yet"))
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
    local castOk = mouseClickCenter()
    if not castOk then
        Runtime.FishingEquippedRod = nil
        Runtime.FishingEquippedAt = 0
        setFishingState("CAST_FAILED", "Cast input was not accepted by the executor")
        return 0.8
    end

    Runtime.FishingLastCast = os.clock()
    setFishingState("WAIT_QTE", "Cast sent; waiting for SHAKE/QTE")

    return 0.20
end

-- ============================================================
-- Mining
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

local function miningMouse(held, ore, force)
    if Runtime.MiningMouseHeld == held and not (force and held == false) then
        return true
    end

    local point = ore and screenPointOf(ore)
    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)
    local x = point and point.X or viewport.X / 2
    local y = point and point.Y or viewport.Y / 2

    local ok = mouseButtonAt(x, y, held)
    if not held then
        ok = Compat.ReleaseMouse(x, y) or ok
    end

    if ok then
        Runtime.MiningMouseHeld = held
    end
    return ok
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
    if not force and now - (Runtime.MiningLastIndexRefresh or 0) < 3.0 then
        return false
    end
    Runtime.MiningLastIndexRefresh = now
    Runtime.MiningIndexRefreshes = (Runtime.MiningIndexRefreshes or 0) + 1

    local islands = Workspace:FindFirstChild("Islands")
    if not islands then
        return false
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
    return true
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
    if not findHotbar() then
        return nil, "Hotbar UI is not client-visible yet"
    end

    HotbarService.Refresh()

    for _, data in pairs(HotbarService.Slots) do
        if lower(data.Title):find("pickaxe", 1, true) then
            return data, "Pickaxe found"
        end
    end

    return nil, "No pickaxe in the live hotbar"
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
        if not miningMouse(false, ore) then
            setMiningState("QTE_INPUT_FAILED", "Critical zone reached but M1 release failed")
            return true
        end
        Runtime.MiningReleaseDone = true
        Runtime.MiningLastQTE = os.clock()
        setMiningState("RELEASE", string.format("Released on %s critical zone", oreName(ore)))
    elseif not Runtime.MiningReleaseDone then
        if not miningMouse(true, ore) then
            setMiningState("QTE_INPUT_FAILED", "Unable to hold M1 for mining charge")
            return true
        end
        setMiningState("CHARGE", string.format("Charging %s", oreName(ore)))
    end

    return true
end

function MiningQTEService.Reset(reason)
    if MotionController.IsOwnedBy("Mining") then
        MotionController.Release("Mining", true)
    end
    miningMouse(false, Runtime.MiningTarget, true)
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

    if Runtime.IndexRefreshBusy then
        setMiningState("INDEX_REFRESH", "Runtime index is rebuilding")
        return 0.6
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
        MiningQTEService.RefreshOreIndex(false)
        setMiningState(
            "WAIT_STREAM",
            "No live matching ore in the currently streamed islands"
        )
        local waited = os.clock() - Runtime.MiningNoOreSince
        return math.min(4.0, Config.MiningNoOreRetry + waited * 0.08)
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

    local pickaxe, pickaxeReason = findPickaxe()

    if not pickaxe then
        miningMouse(false, ore)
        setMiningState(
            pickaxeReason == "Hotbar UI is not client-visible yet"
                and "WAIT_HOTBAR"
                or "MISSING_PICKAXE",
            tostring(pickaxeReason)
        )
        return 0.8
    end

    if Runtime.MiningEquippedSlot ~= pickaxe.Slot
        or HotbarService.LastPressedSlot ~= pickaxe.Slot then

        local equipped = HotbarService.Press(pickaxe)
        if not equipped then
            Runtime.MiningEquippedSlot = nil
            setMiningState("EQUIP_FAILED", "Pickaxe input failed")
            return 0.8
        end

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
        if not miningMouse(true, ore) then
            setMiningState("M1_INPUT_FAILED", "Unable to start mining M1 hold")
            return 0.8
        end

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
        notify("World Utility", "Prompt is not client-visible yet: " .. tostring(name), 4)
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
-- Auto Farm
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

local FARM_MOTION_OWNERS = {
    Dialogue = true,
    Quest = true,
    Combat = true,
    Loot = true,
    Legacy = true,
}

function FarmMovement.Stop(removePlatform, clearHold, forceAll)
    local owner = Runtime.Motion.Owner
    if owner and (forceAll == true or FARM_MOTION_OWNERS[owner]) then
        MotionController.Release(owner, true)
        return true
    end
    return false
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
        QuestDirectService.SetContext(nil, nil)
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
    QuestDirectService.SetContext(questName, npc)

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

    local attacked, attackReason = CombatService.AttackStep()
    if not attacked then
        local state = attackReason == "disabled"
            and "AUTO_M1_DISABLED"
            or attackReason == "input-failed"
                and "COMBAT_INPUT_FAILED"
                or "COMBAT_COOLDOWN"
        farmSetState(
            state,
            target.Name .. " • " .. tostring(attackReason) .. " • " .. string.format("%.1f", distance)
        )
        return
    end

    farmSetState(
        "FARM_COMBAT",
        target.Name
            .. " • M1 sent • "
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
                .. " is not visible in the live hotbar"
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
    QuestDirectService.Poll()

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

    if Runtime.IndexRefreshBusy then
        farmSetState("INDEX_REFRESH", "Runtime index is rebuilding")
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

        local directStarted, directReason =
            QuestDirectService.TryAccept(plan.Recommended)

        if directStarted or directReason == "pending" then
            FarmMovement.Stop(false, true)
            farmSetState(
                "QUEST_DIRECT",
                plan.Recommended.Name .. " • " .. tostring(directReason)
            )
            return
        end

        -- No verified direct contract yet: use the normal NPC path. This path
        -- also teaches the passive hook; once a real quest-state-changing call
        -- is observed, later compatible quests can skip NPC interaction.
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

function ESPService.ClearAll()
    for object in pairs(ESPService.Map) do
        ESPService.Clear(object)
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

ServerInfoService = {}

local function bossDisplayName(model)
    return normalize(
        model and (
            model:GetAttribute("NPCName")
            or model:GetAttribute("NPCType")
            or stripRuntimeSuffix(model.Name)
        ) or "Unknown Boss"
    )
end

function ServerInfoService.GetLiveBosses()
    local rows = {}
    local seen = {}

    for model in pairs(Runtime.Entities) do
        if model and model.Parent and TargetService.IsBoss(model) then
            local name = bossDisplayName(model)
            local hum = model:FindFirstChildOfClass("Humanoid")
            local hp = hum and string.format("%.0f/%.0f HP", hum.Health, hum.MaxHealth) or "HP ?"
            local target = normalize(model:GetAttribute("Target") or "")
            local line = name .. " • " .. hp
            if target ~= "" then
                line ..= " • target " .. target
            end
            table.insert(rows, line)
            seen[lower(name)] = true
        end
    end

    table.sort(rows)
    return rows, seen
end

function ServerInfoService.GetBossSpawnRows()
    local liveRows, live = ServerInfoService.GetLiveBosses()
    local rows = {}
    local root = mobZoneRoot()
    local seen = {}

    if root then
        for _, object in ipairs(root:GetDescendants()) do
            if object:IsA("BasePart") then
                local respawn = tonumber(object:GetAttribute("RespawnTime"))
                local timerFlag = object:GetAttribute("DisplayRespawnTimer") == true
                    or object:GetAttribute("RespawnTimer") == true

                if timerFlag and respawn and respawn >= 60 then
                    local name = normalize(object:GetAttribute("Mob") or object.Name)
                    if name ~= "" and not seen[lower(name)] then
                        seen[lower(name)] = true
                        local spawned = object:GetAttribute("Spawned") == true
                        local active = object:GetAttribute("Active") ~= false
                        local state = live[lower(name)] and "LIVE"
                            or (spawned and active and "SPAWNED")
                            or "WAITING"
                        local zone = normalize(object:GetAttribute("Zone") or "Unknown zone")
                        local extra = respawn and (" • respawn " .. tostring(math.floor(respawn)) .. "s") or ""
                        table.insert(rows, string.format("%s • %s • %s%s", name, state, zone, extra))
                    end
                end
            end
        end
    end

    -- Live bosses without a respawn-marked MobZone still belong in the report.
    for _, line in ipairs(liveRows) do
        local key = lower(line:match("^(.-)%s+•") or line)
        if not seen[key] then
            table.insert(rows, line .. " • live entity")
        end
    end

    table.sort(rows)
    return rows
end

local function worldEventGuiState()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local gui = playerGui and playerGui:FindFirstChild("WorldEvent")
    local frame = gui and gui:FindFirstChild("Frame")
    if not gui or not frame or not gui.Enabled then
        return nil
    end

    local rows = {}
    for _, name in ipairs({"Header", "Title", "Subheader", "Countdown", "Resistance"}) do
        local object = frame:FindFirstChild(name, true)
        if object and (object:IsA("TextLabel") or object:IsA("TextButton")) then
            local visible = true
            pcall(function() visible = object.Visible end)
            local text = normalize(object.Text)
            if visible and text ~= "" then
                table.insert(rows, text)
            end
        end
    end

    return #rows > 0 and rows or nil
end

function ServerInfoService.GetEventRows()
    local rows = {}

    local weather = normalize(Workspace:GetAttribute("WeatherUniversal") or "Unknown")
    local dayNight = normalize(Workspace:GetAttribute("DayNight") or "Unknown")
    local moon = Workspace:GetAttribute("MoonPhase")
    table.insert(rows, "Weather: " .. weather)
    table.insert(rows, "Time: " .. dayNight)
    if moon ~= nil then
        table.insert(rows, "Moon phase: " .. tostring(moon))
    end

    local guiRows = worldEventGuiState()
    if guiRows then
        table.insert(rows, "World Event: ACTIVE")
        for _, text in ipairs(guiRows) do
            table.insert(rows, "  " .. text)
        end
    else
        table.insert(rows, "World Event UI: no active header detected")
    end

    local important = Workspace:FindFirstChild("AA IMPORTANT")
    local raids = important and important:FindFirstChild("Raids")
    if raids then
        for _, raid in ipairs(raids:GetChildren()) do
            local active = false
            local wanted = lower(raid.Name)
            for model in pairs(Runtime.Entities) do
                if model and model.Parent and TargetService.IsAliveNPC(model) then
                    local blob = lower(table.concat({
                        model.Name,
                        tostring(model:GetAttribute("NPCName") or ""),
                        tostring(model:GetAttribute("NPCType") or ""),
                        tostring(model:GetAttribute("Party") or ""),
                        tostring(model:GetAttribute("DefaultParty") or ""),
                    }, " "))
                    if blob:find(wanted, 1, true) then
                        active = true
                        break
                    end
                end
            end
            table.insert(rows, "Raid " .. raid.Name .. ": " .. (active and "ACTIVE" or "configured / not observed"))
        end
    end

    return rows
end

function ServerInfoService.GetBossReport()
    local rows = ServerInfoService.GetBossSpawnRows()
    if #rows == 0 then
        return "No boss/respawn markers are client-visible in this server state."
    end
    return table.concat(rows, "\n")
end

function ServerInfoService.GetEventReport()
    return table.concat(ServerInfoService.GetEventRows(), "\n")
end

function ServerInfoService.GetOverview()
    local live = ServerInfoService.GetLiveBosses()
    local eventGui = worldEventGuiState()
    return table.concat({
        ServerToolsService and ServerToolsService.GetInfo and ServerToolsService.GetInfo() or "Server tools loading",
        "",
        "Live bosses: " .. tostring(#live),
        "World event header: " .. tostring(eventGui ~= nil),
        "Auto Stats: " .. tostring(Config.AutoStats) .. " • " .. tostring(Runtime.StatsSpendStatus),
    }, "\n")
end

function ServerInfoService.BossKey()
    return ServerInfoService.GetBossReport()
end

function ServerInfoService.EventKey()
    return ServerInfoService.GetEventReport()
end

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

local SpeedBackup = setmetatable({}, {__mode = "k"})
local JumpBackup = setmetatable({}, {__mode = "k"})

function MovementService.RestoreSpeed()
    local hum = humanoid()
    local value = hum and SpeedBackup[hum]
    if hum and value ~= nil then
        pcall(function()
            hum.WalkSpeed = value
        end)
        SpeedBackup[hum] = nil
    end
end

function MovementService.RestoreJump()
    local hum = humanoid()
    local backup = hum and JumpBackup[hum]
    if hum and backup then
        pcall(function()
            hum.UseJumpPower = backup.UseJumpPower
            hum.JumpPower = backup.JumpPower
            hum.JumpHeight = backup.JumpHeight
        end)
        JumpBackup[hum] = nil
    end
end

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
        if SpeedBackup[hum] == nil then
            SpeedBackup[hum] = hum.WalkSpeed
        end
        pcall(function()
            hum.WalkSpeed = Config.WalkSpeed
        end)
    elseif SpeedBackup[hum] ~= nil then
        MovementService.RestoreSpeed()
    end

    if Config.JumpOverride then
        if JumpBackup[hum] == nil then
            JumpBackup[hum] = {
                UseJumpPower = hum.UseJumpPower,
                JumpPower = hum.JumpPower,
                JumpHeight = hum.JumpHeight,
            }
        end
        pcall(function()
            hum.UseJumpPower = true
            hum.JumpPower = Config.JumpPower
        end)
    elseif JumpBackup[hum] ~= nil then
        MovementService.RestoreJump()
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

bootMark("core-services-ready")

-- ============================================================
-- Schedulers
-- ============================================================

local function spawnLoop(name, body, defaultDelay)
    task.spawn(function()
        while Core.Running do
            local ok, delayOrError = safeCall(body)
            if not ok then
                markSoftError(name, delayOrError)
            end
            task.wait(ok and (tonumber(delayOrError) or defaultDelay) or math.max(0.35, defaultDelay or 0.5))
        end
    end)
end

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
        if Config.InfoBossNotify then
            local key = ServerInfoService.BossKey()
            if Runtime.InfoLastBossKey == nil then
                Runtime.InfoLastBossKey = key
            elseif key ~= Runtime.InfoLastBossKey then
                Runtime.InfoLastBossKey = key
                notify("Boss Update", ServerInfoService.GetBossReport(), 10)
            end
        end

        if Config.InfoEventNotify then
            local key = ServerInfoService.EventKey()
            if Runtime.InfoLastEventKey == nil then
                Runtime.InfoLastEventKey = key
            elseif key ~= Runtime.InfoLastEventKey then
                Runtime.InfoLastEventKey = key
                notify("World Event Update", ServerInfoService.GetEventReport(), 10)
            end
        end

        task.wait(math.max(1.0, tonumber(Config.InfoPollInterval) or 2.0))
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
        elseif next(ESPService.Map) ~= nil then
            safeWorker("ESP", ESPService.ClearAll)
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
            "NPC is not client-visible yet: " .. tostring(displayOrName),
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
    if not name or name == "" or name == "Islands unavailable" then
        notify("Island", "Island list is not client-visible yet", 4)
        return false
    end

    local landing = IslandService.FindLanding(name)
    if not landing or not rootPart() then
        notify("Island", "Landing point is not client-visible yet: " .. tostring(name), 4)
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
        "Native Roblox UI / no external UI dependency",
        "Single-owner Tween/Heartbeat motion controller",
        "Fixed MobZone gather + live entity-state filtering",
        "Custom 0-9 Hotbar + Cooldown/EXP",
        "Auto Stats via Radar + verified physical fallback",
        "Live boss / world event server info",
        "Skill EXP / hotbar cooldown detection",
        "Fishing: SHAKE / CLICK / Timed Release / Reel",
        "Mining Critical Zone QTE",
        "Fishing / Mining / Farming",
        "Fruit / FruitLevel",
        "Bounty / Faction / Crew",
        "Pickup / Chest / Fruit Chest / World Boss Chest",
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
        "",
    }

    local order = {
        "Progress",
        "Fishing",
        "Mining",
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
        "loadstring: not required",
        "HTTP: " .. tostring(ExecutorCaps.Http) .. " (server tools only)",
        "request fallback: " .. tostring(ExecutorCaps.Request),
        "VirtualKey: " .. tostring(ExecutorCaps.VirtualKey),
        "VirtualMouse: " .. tostring(ExecutorCaps.VirtualMouse),
        "fireproximityprompt: " .. tostring(ExecutorCaps.FirePrompt),
        "firesignal: " .. tostring(ExecutorCaps.FireSignal),
        "Capability failures: key=" .. tostring(CapabilityFailures.VirtualKey or 0)
            .. " mouse=" .. tostring(CapabilityFailures.VirtualMouse or 0)
            .. " prompt=" .. tostring(CapabilityFailures.FirePrompt or 0)
            .. " signal=" .. tostring(CapabilityFailures.FireSignal or 0),
        "setclipboard: " .. tostring(ExecutorCaps.Clipboard),
        "quest namecall hook: " .. tostring(Runtime.QuestDirect and Runtime.QuestDirect.Installed),
        "UNC mode: capability-based (partial support OK)",
        "WebSocket: not required",
        "getscriptclosure: not required",
        "filesystem: not required",
        "external UI fetch: disabled",
        "snapshot diagnostics: malformed-dialogue=" .. tostring(NoiseGuard.MalformedDialogue)
            .. " archived-sound=" .. tostring(NoiseGuard.ArchivedSounds),
        "soft UI/event guard: enabled",
        "boot stage: " .. tostring(BOOT_STAGE),
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

    add("Native UI", UIFramework ~= nil)
    add("Player ready", PlayerState.IsReady())
    add("Quest UI", questScrollingFrame() ~= nil)
    add("RecommendedQuest storage", questStorage() ~= nil)
    add("Entities", entitiesFolder() ~= nil)
    add("DialogueNPCs", dialogueRoot() ~= nil)
    add("Dialogue E input", ExecutorCaps.VirtualKey == true)
    add("Screen click input", ExecutorCaps.VirtualMouse == true)
    add("World marker cache", Runtime.WorldMarkers ~= nil)
    add("Hotbar", findHotbar() ~= nil)
    add("Quest catalog", #Runtime.QuestCatalog > 0)
    add("Runtime index", Runtime.IndexReady)
    add("Fishing UI", fishingGui() ~= nil)
    add("QTE UI", qteScreen() ~= nil)
    add("Ore cache", next(Runtime.Ores) ~= nil)

    return table.concat(rows, "\n")
end


-- ============================================================
-- Native Roblox UI
-- ============================================================

bootMark("ui-window-native")
local okWindow, Window = safeCall(function()
    return UIFramework:CreateWindow({
        Title = "SON HUB " .. VERSION,
        SubTitle = "Nexomia | hongson",
        TabWidth = 150,
        Size = UDim2.fromOffset(720, 520),
        Acrylic = false,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.LeftControl,
    })
end)

if not okWindow or not Window then
    error("SON HUB native UI bootstrap failed at ui-window: " .. tostring(Window))
end

local function uiMethod(object, methodName, ...)
    if not object then
        return false, "missing UI object for " .. tostring(methodName)
    end
    local method = object[methodName]
    if type(method) ~= "function" then
        return false, "missing UI method " .. tostring(methodName)
    end
    return safeCall(method, object, ...)
end

local function dummySection()
    return {
        AddToggle = function(_, _, data) return dummyOption(data and data.Default) end,
        AddDropdown = function(_, _, data)
            local values = data and data.Values or {}
            return dummyOption(values[(data and data.Default) or 1])
        end,
        AddSlider = function(_, _, data) return dummyOption(data and data.Default) end,
        AddButton = function() return dummyOption(false) end,
        AddInput = function(_, _, data) return dummyOption(data and data.Default or "") end,
    }
end

local function addTab(title, icon)
    local ok, tab = uiMethod(Window, "AddTab", {Title = title, Icon = icon})
    if not ok or not tab then
        markSoftError("UI", "AddTab failed: " .. tostring(title) .. " | " .. tostring(tab))
        return dummySection()
    end
    return tab
end

local function addSection(tab, title)
    local ok, section = uiMethod(tab, "AddSection", title)
    if not ok or not section then
        markSoftError("UI", "AddSection failed: " .. tostring(title) .. " | " .. tostring(section))
        return dummySection()
    end
    return section
end

local function addButton(section, spec)
    if not section or type(section.AddButton) ~= "function" then
        markSoftError("UI", "AddButton unavailable: " .. tostring(spec and spec.Title))
        return dummyOption(false)
    end
    local wrapped = {}
    for k, v in pairs(spec or {}) do wrapped[k] = v end
    local original = wrapped.Callback
    wrapped.Callback = function(...)
        local ok, result = safeCall(original, ...)
        if not ok then markSoftError("UI", result) end
        return result
    end
    local ok, result = safeCall(section.AddButton, section, wrapped)
    if not ok then
        markSoftError("UI", result)
        return dummyOption(false)
    end
    return result or dummyOption(false)
end

local function addInput(section, id, spec)
    if not section or type(section.AddInput) ~= "function" then
        markSoftError("UI", "AddInput unavailable: " .. tostring(id))
        return dummyOption(spec and spec.Default or "")
    end
    local wrapped = {}
    for k, v in pairs(spec or {}) do wrapped[k] = v end
    local original = wrapped.Callback
    wrapped.Callback = function(...)
        local ok, result = safeCall(original, ...)
        if not ok then markSoftError("UI", result) end
        return result
    end
    local ok, result = safeCall(section.AddInput, section, id, wrapped)
    if not ok then
        markSoftError("UI", result)
        return dummyOption(spec and spec.Default or "")
    end
    return result or dummyOption(spec and spec.Default or "")
end

bootMark("ui-tabs")
local Tabs = {
    Home = addTab("Home", "home"),
    Minigame = addTab("Minigame", "gamepad-2"),
    Player = addTab("Player", "user"),
    Info = addTab("Info", "info"),
    Teleport = addTab("Teleport", "map-pin"),
    Settings = addTab("Settings", "settings"),
    Test = addTab("Test", "flask-conical"),
}

local UIOptions = {}

local function bindToggle(section, id, title, defaultValue, callback)
    if not section or type(section.AddToggle) ~= "function" then
        markSoftError("UI", "AddToggle unavailable for " .. tostring(id))
        local fallback = dummyOption(defaultValue == true)
        UIOptions[id] = fallback
        return fallback
    end

    local okCreate, option = safeCall(section.AddToggle, section, id, {
        Title = title,
        Default = defaultValue == true,
    })

    if not okCreate then
        markSoftError("UI", option)
        local fallback = dummyOption(defaultValue == true)
        UIOptions[id] = fallback
        return fallback
    end

    if option and type(option.OnChanged) == "function" then
        local okBind, bindErr = safeCall(option.OnChanged, option, function()
            local ok, result = safeCall(callback, option.Value)
            if not ok then
                markSoftError("UI", result)
            end
        end)
        if not okBind then markSoftError("UI", bindErr) end
    end

    option = option or dummyOption(defaultValue == true)
    UIOptions[id] = option
    return option
end

local function bindDropdown(section, id, title, values, defaultIndex, callback)
    if not section or type(section.AddDropdown) ~= "function" then
        markSoftError("UI", "AddDropdown unavailable for " .. tostring(id))
        local fallback = dummyOption(values and values[defaultIndex or 1])
        UIOptions[id] = fallback
        return fallback
    end

    local resolvedIndex = defaultIndex or 1
    if type(values) == "table" and Config and Config[id] ~= nil then
        for index, value in ipairs(values) do
            if value == Config[id] then
                resolvedIndex = index
                break
            end
        end
    end

    local okCreate, option = safeCall(section.AddDropdown, section, id, {
        Title = title,
        Values = values,
        Multi = false,
        Default = resolvedIndex,
    })

    if not okCreate then
        markSoftError("UI", option)
        local fallback = dummyOption(values and values[resolvedIndex])
        UIOptions[id] = fallback
        return fallback
    end

    if option and type(option.OnChanged) == "function" then
        local okBind, bindErr = safeCall(option.OnChanged, option, function(value)
            local ok, result = safeCall(callback, value)
            if not ok then
                markSoftError("UI", result)
            end
        end)
        if not okBind then markSoftError("UI", bindErr) end
    end

    option = option or dummyOption(values and values[resolvedIndex])
    UIOptions[id] = option
    return option
end

local function bindSlider(section, id, title, minimum, maximum, defaultValue, callback)
    if not section or type(section.AddSlider) ~= "function" then
        markSoftError("UI", "AddSlider unavailable for " .. tostring(id))
        local fallback = dummyOption(defaultValue)
        UIOptions[id] = fallback
        return fallback
    end

    local okCreate, option = safeCall(section.AddSlider, section, id, {
        Title = title,
        Default = defaultValue,
        Min = minimum,
        Max = maximum,
        Rounding = 0,
        Callback = function(value)
            local ok, result = safeCall(callback, value)
            if not ok then
                markSoftError("UI", result)
            end
        end,
    })

    if not okCreate then
        markSoftError("UI", option)
        local fallback = dummyOption(defaultValue)
        UIOptions[id] = fallback
        return fallback
    end

    option = option or dummyOption(defaultValue)
    UIOptions[id] = option
    return option
end

local function setDropdownValues(dropdown, values)
    if dropdown and type(dropdown.SetValues) == "function" then
        local ok, result = safeCall(function()
            dropdown:SetValues(values)
        end)
        if not ok then
            markSoftError("UI", result)
        end
    end
end

-- Home
local FarmSection = addSection(Tabs.Home, "Auto Farm")

local autoFarmToggle
local autoMiningToggle
local autoFishingToggle
local changingPrimaryMode = false

local function disableOtherPrimaryModes(keep)
    if changingPrimaryMode then
        return
    end
    changingPrimaryMode = true

    -- Config is the source of truth; UI state is only a mirror. This prevents a
    -- stale/dummy toggle from leaving two movement owners enabled at once.
    if keep ~= "farm" then
        Config.AutoProgress = false
        if autoFarmToggle and autoFarmToggle.Value then
            autoFarmToggle:SetValue(false)
        end
    end
    if keep ~= "mining" then
        Config.AutoMining = false
        if autoMiningToggle and autoMiningToggle.Value then
            autoMiningToggle:SetValue(false)
        end
    end
    if keep ~= "fishing" then
        Config.AutoFishing = false
        if autoFishingToggle and autoFishingToggle.Value then
            autoFishingToggle:SetValue(false)
        end
    end

    changingPrimaryMode = false
end

autoFarmToggle = bindToggle(FarmSection, "AutoFarm", "Auto Farm", Config.AutoProgress, function(value)
    Config.AutoProgress = value
    if value then
        disableOtherPrimaryModes("farm")
    end
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
        local owner = Runtime.Motion.Owner
        if owner and owner ~= "Manual" then
            MotionController.Release(owner, true)
        end
        if not Runtime.Motion.Owner then
            restoreCollision()
        end
    end
end)

bindToggle(FarmSection, "DirectQuest", "Direct Quest Hook", Config.DirectQuest, function(value)
    Config.DirectQuest = value
    if value then
        QuestDirectService.Install()
    else
        Runtime.QuestDirect.Busy = false
        Runtime.QuestDirect.Replaying = false
        Runtime.QuestDirect.Context = nil
    end
end)

addButton(FarmSection, {
    Title = "Direct Quest Status",
    Callback = function()
        notify("Direct Quest", QuestDirectService.Status(), 9)
    end,
})

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

addButton(FarmSection, {
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

local CombatSection = addSection(Tabs.Home, "Combat Position")

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

local HomeState = addSection(Tabs.Home, "State")
addButton(HomeState, {
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
local MiningSection = addSection(Tabs.Minigame, "Mining")

autoMiningToggle = bindToggle(MiningSection, "AutoMining", "Auto Mining", Config.AutoMining, function(value)
    Config.AutoMining = value
    if value then
        disableOtherPrimaryModes("mining")
    end
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

addButton(MiningSection, {
    Title = "Refresh Ores",
    Callback = function()
        local refreshed = MiningQTEService.RefreshOreIndex(true)
        setDropdownValues(oreDropdown, MiningQTEService.GetOreOptions())
        notify(
            "Mining",
            refreshed and "Ore index refreshed" or "Islands/ores are not client-visible yet",
            3
        )
    end,
})

addButton(MiningSection, {
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

local FishingSection = addSection(Tabs.Minigame, "Fishing")

autoFishingToggle = bindToggle(FishingSection, "AutoFishing", "Auto Fishing", Config.AutoFishing, function(value)
    Config.AutoFishing = value
    if value then
        disableOtherPrimaryModes("fishing")
    end
    FishingService.Reset(value and "Enabled" or "Disabled")
end)

local fishingSpotDropdown = bindDropdown(
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

addButton(FishingSection, {
    Title = "Save Current Spot",
    Callback = function()
        local root = rootPart()
        if root then
            Runtime.FishingSpotCFrame = root.CFrame
            fishingSpotDropdown:SetValue("Saved Position")
            notify("Fishing", "Saved current position", 3)
        else
            notify("Fishing", "Character position is unavailable", 3)
        end
    end,
})

addButton(FishingSection, {
    Title = "Fishing Status",
    Callback = function()
        local data = FishingService.GetConditions()
        notify(
            "Fishing",
            "State: " .. tostring(data.State)
                .. "\nRod: " .. tostring(data.Rod) .. " [" .. tostring(data.RodSource) .. "]"
                .. "\nRod check: " .. tostring(data.RodReason)
                .. "\nBait: " .. tostring(data.Bait) .. " x" .. tostring(data.BaitAmount)
                .. "\nSpot: " .. tostring(data.Spot)
                .. "\nReady: " .. tostring(data.CanStart),
            9
        )
    end,
})

-- Player
local StatsSection = addSection(Tabs.Player, "Auto Stats")

bindToggle(StatsSection, "AutoStats", "Auto Stats", Config.AutoStats, function(value)
    Config.AutoStats = value
    if not value then
        Runtime.StatsSpendPending = false
        Runtime.StatsSpendStatus = "Disabled"
    end
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

addButton(StatsSection, {
    Title = "Stats Status",
    Callback = function()
        notify("Stats", StatsService.GetSnapshot(), 8)
    end,
})

local ESPSection = addSection(Tabs.Player, "ESP")
bindToggle(ESPSection, "PlayerESP", "Player ESP", Config.PlayerESP, function(value)
    Config.PlayerESP = value
    ESPService.Step()
end)
bindToggle(ESPSection, "MobESP", "Mob ESP", Config.MobESP, function(value)
    Config.MobESP = value
    ESPService.Step()
end)
bindToggle(ESPSection, "BossESP", "Boss ESP", Config.BossESP, function(value)
    Config.BossESP = value
    ESPService.Step()
end)
bindToggle(ESPSection, "TargetESP", "Current Target ESP", Config.CurrentTargetESP, function(value)
    Config.CurrentTargetESP = value
    ESPService.Step()
end)
bindToggle(ESPSection, "LootESP", "Loot ESP", Config.LootESP, function(value)
    Config.LootESP = value
    ESPService.Step()
end)

local CameraSection = addSection(Tabs.Player, "Player Camera")
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

addButton(CameraSection, {
    Title = "Refresh Players",
    Callback = function()
        setDropdownValues(cameraDropdown, PlayerToolsService.GetNames())
    end,
})

addButton(CameraSection, {
    Title = "Spectate",
    Callback = function()
        local ok, reason = PlayerToolsService.Spectate(selectedCameraPlayer)
        notify("Camera", ok and ("Spectating " .. tostring(reason)) or tostring(reason), 3)
    end,
})

addButton(CameraSection, {
    Title = "Stop Spectate",
    Callback = function()
        local ok = PlayerToolsService.StopSpectate()
        notify("Camera", ok and "Camera restored" or "Local character camera is not ready yet", 3)
    end,
})

-- Info
local InfoServerSection = addSection(Tabs.Info, "Live Server")
addButton(InfoServerSection, {
    Title = "Server Overview",
    Callback = function()
        notify("Server Overview", ServerInfoService.GetOverview(), 12)
    end,
})
addButton(InfoServerSection, {
    Title = "Boss Status",
    Callback = function()
        notify("Boss Status", ServerInfoService.GetBossReport(), 15)
    end,
})
addButton(InfoServerSection, {
    Title = "World Events",
    Callback = function()
        notify("World Events", ServerInfoService.GetEventReport(), 15)
    end,
})
bindToggle(InfoServerSection, "InfoBossNotify", "Notify Boss Changes", Config.InfoBossNotify, function(value)
    Config.InfoBossNotify = value
    Runtime.InfoLastBossKey = ServerInfoService.BossKey()
end)
bindToggle(InfoServerSection, "InfoEventNotify", "Notify Event Changes", Config.InfoEventNotify, function(value)
    Config.InfoEventNotify = value
    Runtime.InfoLastEventKey = ServerInfoService.EventKey()
end)

local InfoStatsSection = addSection(Tabs.Info, "Auto Stats Health")
addButton(InfoStatsSection, {
    Title = "Stats Diagnostic",
    Callback = function()
        notify("Auto Stats", StatsService.GetSnapshot(), 12)
    end,
})
addButton(InfoStatsSection, {
    Title = "Spend One Stat Point Now",
    Callback = function()
        local ok = StatsService.SpendOne(true)
        notify("Auto Stats", ok and "One-shot spend attempt started" or Runtime.StatsSpendStatus, 5)
    end,
})

-- Teleport
local IslandSection = addSection(Tabs.Teleport, "Islands")
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

addButton(IslandSection, {
    Title = "Refresh Islands",
    Callback = function()
        setDropdownValues(islandDropdown, IslandService.GetNames())
    end,
})

addButton(IslandSection, {
    Title = "Tween To Island",
    Callback = function()
        if selectedIsland then
            IslandService.Teleport(selectedIsland)
        end
    end,
})

local PlayerTeleportSection = addSection(Tabs.Teleport, "Players")
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

addButton(PlayerTeleportSection, {
    Title = "Refresh Players",
    Callback = function()
        setDropdownValues(playerTeleportDropdown, PlayerToolsService.GetNames())
    end,
})

addButton(PlayerTeleportSection, {
    Title = "Tween To Player",
    Callback = function()
        local ok, reason = PlayerToolsService.TeleportTo(selectedTeleportPlayer)
        if not ok then
            notify("Teleport", tostring(reason), 4)
        end
    end,
})

-- Settings
local MovementSection = addSection(Tabs.Settings, "Movement")

bindSlider(MovementSection, "TweenSpeed", "Tween Speed", 50, 450, Config.TweenSpeed, function(value)
    Config.TweenSpeed = value
    Config.PlatformSpeed = value
end)

bindToggle(MovementSection, "SpeedOverride", "WalkSpeed Override", Config.SpeedOverride, function(value)
    Config.SpeedOverride = value
    if not value then
        MovementService.RestoreSpeed()
    end
end)
bindSlider(MovementSection, "WalkSpeed", "WalkSpeed", 16, 100, Config.WalkSpeed, function(value)
    Config.WalkSpeed = value
end)
bindToggle(MovementSection, "JumpOverride", "JumpPower Override", Config.JumpOverride, function(value)
    Config.JumpOverride = value
    if not value then
        MovementService.RestoreJump()
    end
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

local ServerSection = addSection(Tabs.Settings, "Server")
addButton(ServerSection, {
    Title = "Server Info",
    Callback = function()
        notify("Server", ServerToolsService.GetInfo(), 10)
    end,
})
addButton(ServerSection, {
    Title = "Rejoin Server",
    Callback = function()
        local ok, reason = ServerToolsService.Rejoin()
        if not ok then
            notify("Rejoin", tostring(reason), 5)
        end
    end,
})
addButton(ServerSection, {
    Title = "Server Hop",
    Callback = function()
        if Runtime.ServerHopBusy then
            notify("Server Hop", "A server search is already running", 3)
            return
        end
        Runtime.ServerHopBusy = true
        task.spawn(function()
            local callOk, ok, reason = safeCall(ServerToolsService.Hop)
            Runtime.ServerHopBusy = false
            if not callOk then
                notify("Server Hop", "Search failed: " .. tostring(ok), 5)
            elseif not ok then
                notify("Server Hop", tostring(reason), 5)
            end
        end)
    end,
})

local joinJobId = ""
addInput(ServerSection, "JoinServerJobId", {
    Title = "Server UID / JobId",
    Default = "",
    Placeholder = "Paste JobId",
    Numeric = false,
    Finished = true,
    Callback = function(value)
        joinJobId = tostring(value or "")
    end,
})
addButton(ServerSection, {
    Title = "Join Server UID",
    Callback = function()
        local ok, reason = ServerToolsService.JoinJob(joinJobId)
        if not ok then
            notify("Join Server", tostring(reason), 5)
        end
    end,
})

local ScriptSection = addSection(Tabs.Settings, "Script")
addButton(ScriptSection, {
    Title = "Unload SON HUB",
    Callback = function()
        if type(ENV.__SON_HUB_UNLOAD) == "function" then
            ENV.__SON_HUB_UNLOAD()
        end
    end,
})

-- Test
local TestSection = addSection(Tabs.Test, "Diagnostics")
addButton(TestSection, {
    Title = "Game Structure",
    Callback = function()
        notify("Game Structure", TestService.StructureReport(), 12)
    end,
})
addButton(TestSection, {
    Title = "Runtime Self Test",
    Callback = function()
        notify("Self Test", selfTest(), 12)
    end,
})
addButton(TestSection, {
    Title = "Worker Health",
    Callback = function()
        notify("Worker Health", workerHealth(), 14)
    end,
})
addButton(TestSection, {
    Title = "Refresh Index",
    Callback = function()
        if Runtime.IndexRefreshBusy then
            notify("Index", "Refresh is already running", 3)
            return
        end
        Runtime.IndexRefreshBusy = true
        task.spawn(function()
            local ok, err = safeCall(function()
                RuntimeIndex.Rebuild()
                QuestCatalogService.Build()
                MobZoneService.Rebuild(true)
                MiningQTEService.RefreshOreIndex(true)
                HotbarService.Refresh()
            end)
            Runtime.IndexRefreshBusy = false
            notify("Index", ok and "Refreshed" or ("Refresh failed: " .. tostring(err)), 4)
        end)
    end,
})

local CleanSection = addSection(Tabs.Settings, "Clean / Compatibility")
addButton(CleanSection, {
    Title = "Clean Runtime State",
    Callback = function()
        -- Disable runtime flags directly as the source of truth. UI SetValue is
        -- then only synchronization; even a failed/dummy UI option cannot let a
        -- scheduler immediately re-enable the state we just cleaned.
        Config.AutoProgress = false
        Config.AutoMining = false
        Config.AutoFishing = false
        Config.AutoStats = false
        Config.MobHitbox = false
        Config.PlayerESP = false
        Config.MobESP = false
        Config.BossESP = false
        Config.CurrentTargetESP = false
        Config.LootESP = false
        Config.SpeedOverride = false
        Config.JumpOverride = false
        Config.InfiniteJump = false
        Config.Noclip = false

        for _, id in ipairs({
            "AutoFarm",
            "AutoMining",
            "AutoFishing",
            "AutoStats",
            "MobHitbox",
            "PlayerESP",
            "MobESP",
            "BossESP",
            "TargetESP",
            "LootESP",
            "SpeedOverride",
            "JumpOverride",
            "InfiniteJump",
            "Noclip",
        }) do
            local option = UIOptions[id]
            if option and option.Value == true and type(option.SetValue) == "function" then
                option:SetValue(false)
            end
        end

        HitboxService.RestoreAll()
        restoreCollision()
        MovementService.RestoreSpeed()
        MovementService.RestoreJump()
        ESPService.ClearAll()
        MotionController.Release(Runtime.Motion.Owner, true)
        FishingService.Reset("Manual clean")
        MiningQTEService.Reset("Manual clean")
        Runtime.CurrentTarget = nil
        Runtime.CurrentWantedMob = nil
        Runtime.StatsSpendPending = false
        Runtime.QuestDirect.Busy = false
        Runtime.QuestDirect.Replaying = false
        Runtime.QuestDirect.Context = nil
        HotbarService.LastPressedSlot = nil
        HotbarService.LastPressedTitle = nil
        HotbarService.LastPressedAt = 0
        MobGatherService.Reset("Manual clean")
        notify("Clean", "Runtime state restored", 4)
    end,
})

addButton(CleanSection, {
    Title = "Executor Compatibility",
    Callback = function()
        notify("Compatibility", executorStatus(), 10)
    end,
})

local RiskSection = addSection(Tabs.Test, "Duplicate Risk")
addButton(RiskSection, {
    Title = "Scan Duplicate-Risk Surfaces",
    Callback = function()
        notify("Duplicate Risk", TestService.DuplicationRiskReport(), 16)
    end,
})

do
    local ok, result = uiMethod(Window, "SelectTab", 1)
    if not ok then
        markSoftError("UI", result)
    end
end
bootMark("ui-ready")


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
        MovementService.RestoreSpeed()
        MovementService.RestoreJump()
    end)

    pcall(function()
        HitboxService.RestoreAll()
    end)

    pcall(function()
        setBlock(false)
        Compat.ReleaseKey(Enum.KeyCode.F)
        local camera = Workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)
        Compat.ReleaseMouse(viewport.X / 2, viewport.Y / 2)
    end)

    Runtime.BlockHeld = false
    Runtime.StatsSpendPending = false
    pcall(QuestDirectService.Uninstall)
    HotbarService.LastPressedSlot = nil
    HotbarService.LastPressedTitle = nil
    HotbarService.LastPressedAt = 0

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
        if UIFramework and type(UIFramework.Destroy) == "function" then
            safeCall(UIFramework.Destroy, UIFramework)
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
            .. "\nBoot: " .. tostring(BOOT_STAGE),
        7
    )
end)
