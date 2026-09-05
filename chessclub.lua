-- HongSondev Chess Trainer v17 - SERVER COMPATIBLE
-- Co GUI WindUI voi nut bat/tat
-- Dung Stockfish API, chay duoc tren moi truong

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

spawn(function()
    local cloneref = cloneref or function(instance) return instance end
    
    -- Fetch URL
    local function fetchURL(url)
        local success, response = pcall(function()
            return HttpService:GetAsync(url)
        end)
        if success and response then
            return response
        end
        return nil
    end

    -- Load WindUI
    local WindUI = nil
    local function loadWindUI()
        if WindUI then return WindUI end
        local sources = {
            "https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua",
            "https://raw.githubusercontent.com/Footagesus/WindUI/refs/heads/main/dist/main.lua"
        }
        for _, url in ipairs(sources) do
            local content = fetchURL(url)
            if content then
                local success, result = pcall(function() return loadstring(content)() end)
                if success and result then
                    WindUI = result
                    return WindUI
                end
            end
        end
        return nil
    end

    -- Cau hinh
    local SEARCH_DEPTH = 12
    local GREEN_FROM = Color3.fromRGB(96, 128, 84)
    local GREEN_TO = Color3.fromRGB(116, 148, 98)
    local ARROW_COLOR = Color3.fromRGB(255, 170, 0)

    local PIECE_CODE = {
        White_Pawn = "wP", White_Knight = "wN", White_Bishop = "wB",
        White_Rook = "wR", White_Queen = "wQ", White_King = "wK",
        Black_Pawn = "bP", Black_Knight = "bN", Black_Bishop = "bB",
        Black_Rook = "bR", Black_Queen = "bQ", Black_King = "bK",
    }
    
    local PIECE_TO_FEN = {
        wP = "P", wN = "N", wB = "B", wR = "R", wQ = "Q", wK = "K",
        bP = "p", bN = "n", bB = "b", bR = "r", bQ = "q", bK = "k"
    }

    local function boardToFEN(board, sideToMove)
        local fen = ""
        for rank = 8, 1, -1 do
            local emptySquares = 0
            for file = 1, 8 do
                local fileStr = string.char(96 + file)
                local square = fileStr .. tostring(rank)
                local piece = board[square]
                
                if piece and PIECE_TO_FEN[piece] then
                    if emptySquares > 0 then
                        fen = fen .. tostring(emptySquares)
                        emptySquares = 0
                    end
                    fen = fen .. PIECE_TO_FEN[piece]
                else
                    emptySquares = emptySquares + 1
                end
            end
            if emptySquares > 0 then fen = fen .. tostring(emptySquares) end
            if rank > 1 then fen = fen .. "/" end
        end
        local turn = (sideToMove == "w") and "w" or "b"
        fen = fen .. " " .. turn .. " KQkq - 0 1"
        return fen
    end

    local function getStockfishBestMove(fen, depth)
        local encodedFEN = HttpService:UrlEncode(fen)
        local url = "https://stockfish.online/api/s/v2.php?fen=" .. encodedFEN .. "&depth=" .. tostring(depth)
        local responseBody = fetchURL(url)
        
        if responseBody then
            local success, data = pcall(function() return HttpService:JSONDecode(responseBody) end)
            if success and data and data.success then
                local bestmoveStr = string.match(data.bestmove, "bestmove (%S+)")
                if bestmoveStr then
                    return { from = string.sub(bestmoveStr, 1, 2), to = string.sub(bestmoveStr, 3, 4) }
                end
            end
        end
        return nil
    end

    -- State
    local state = {
        boardGui = nil, main = nil, boardFrame = nil, piecesFrame = nil,
        sideMode = "Auto", playerSide = "w", trackedSide = "w",
        lastPositionKey = nil, searchRunning = false,
        window = nil, statusLabel = nil, statsLabel = nil,
        connections = {}, uiReady = false, booted = false,
    }
    
    -- UI Helpers
    local function clearHighlights()
        if not state.boardFrame then return end
        for _, child in ipairs(state.boardFrame:GetChildren()) do
            if child.Name == "ChessHint" or child.Name == "MoveArrow" then
                child:Destroy()
            end
        end
    end
    
    local function drawArrow(fromSquare, toSquare)
        if not state.boardFrame or not fromSquare or not toSquare then return end
        
        local arrowContainer = Instance.new("Frame")
        arrowContainer.Name = "MoveArrow"
        arrowContainer.BackgroundTransparency = 1
        arrowContainer.Size = UDim2.fromScale(1, 1)
        arrowContainer.ZIndex = 25
        arrowContainer.Parent = state.boardFrame
        
        local p1 = fromSquare.AbsolutePosition + (fromSquare.AbsoluteSize / 2)
        local p2 = toSquare.AbsolutePosition + (toSquare.AbsoluteSize / 2)
        local boardPos = state.boardFrame.AbsolutePosition
        
        local rel1 = p1 - boardPos
        local rel2 = p2 - boardPos
        
        local distance = (rel2 - rel1).Magnitude
        local angle = math.deg(math.atan2(rel2.Y - rel1.Y, rel2.X - rel1.X))
        
        local line = Instance.new("Frame")
        line.BackgroundColor3 = ARROW_COLOR
        line.BorderSizePixel = 0
        line.AnchorPoint = Vector2.new(0, 0.5)
        line.Position = UDim2.fromOffset(rel1.X, rel1.Y)
        line.Size = UDim2.new(0, distance, 0, 6)
        line.Rotation = angle
        line.ZIndex = 25
        line.Parent = arrowContainer
        
        local headLength = 18
        local headAngle = 35
        
        local leftWing = Instance.new("Frame")
        leftWing.BackgroundColor3 = ARROW_COLOR
        leftWing.BorderSizePixel = 0
        leftWing.AnchorPoint = Vector2.new(1, 0.5)
        leftWing.Position = UDim2.fromOffset(rel2.X, rel2.Y)
        leftWing.Size = UDim2.new(0, headLength, 0, 6)
        leftWing.Rotation = angle - 180 + headAngle
        leftWing.ZIndex = 26
        leftWing.Parent = arrowContainer
        
        local rightWing = leftWing:Clone()
        rightWing.Rotation = angle - 180 - headAngle
        rightWing.Parent = arrowContainer
    end

    local function addSquareHighlight(squareName, color, isTarget)
        if not state.boardFrame then return end
        local square = state.boardFrame:FindFirstChild(squareName)
        if not square or not square:IsA("GuiObject") then return end
        
        local overlay = Instance.new("Frame")
        overlay.Name = "ChessHint"
        overlay.Size = UDim2.fromScale(1, 1)
        overlay.Position = UDim2.fromScale(0, 0)
        overlay.BackgroundColor3 = color
        overlay.BackgroundTransparency = isTarget and 0.85 or 0.90
        overlay.BorderSizePixel = 0
        overlay.ZIndex = math.max((square.ZIndex or 1) + 8, 18)
        overlay.Parent = square
        
        local marker = Instance.new("Frame")
        marker.Name = "Marker"
        marker.AnchorPoint = Vector2.new(0.5, 0.5)
        marker.Position = UDim2.fromScale(0.5, 0.5)
        marker.Size = isTarget and UDim2.fromScale(0.54, 0.54) or UDim2.fromScale(0.16, 0.16)
        marker.BackgroundColor3 = isTarget and Color3.fromRGB(28, 32, 27) or color
        marker.BackgroundTransparency = isTarget and 1 or 0.18
        marker.BorderSizePixel = 0
        marker.ZIndex = overlay.ZIndex + 1
        marker.Parent = overlay
        
        Instance.new("UICorner", marker).CornerRadius = UDim.new(1, 0)
        
        if isTarget then
            local stroke = Instance.new("UIStroke")
            stroke.Thickness = 2
            stroke.Transparency = 0.20
            stroke.Color = color
            stroke.Parent = marker
        end
        return square
    end
    
    local function drawMoveGuide(fromName, toName)
        if not state.boardFrame then return end
        local fromSq = addSquareHighlight(fromName, GREEN_FROM, false)
        local toSq = addSquareHighlight(toName, GREEN_TO, true)
        drawArrow(fromSq, toSq)
    end
    
    local function setStatus(text)
        if state.statusLabel and state.uiReady then
            pcall(function() state.statusLabel:SetTitle(text) end)
        end
    end
    
    local function setEngineStats(text)
        if state.statsLabel and state.uiReady then
            pcall(function() state.statsLabel:SetTitle(text) end)
        end
    end

    -- WindUI Setup (CO NUT BAT/TAT)
    local function setupWindUI()
        local UI = loadWindUI()
        if not UI then return false end
        
        local success = pcall(function()
            state.window = UI:CreateWindow({
                Title = "Stockfish Chess Trainer",
                Folder = "ChessTrainer",
                Theme = "Dark",
                NewElements = true,
                -- NUT BAT/TAT UI
                OpenButton = {
                    Title = "♟ Stockfish",
                    Enabled = true,
                    Color = ColorSequence.new(Color3.fromHex("#8B5CF6"), Color3.fromHex("#6D28D9")),
                },
            })
            
            local mainTab = state.window:Tab({ Title = "Dieu Khien", Icon = "solar:info-square-bold" })
            local statusSection = mainTab:Section({ Title = "Trang Thai", Opened = true })
            
            state.statusLabel = statusSection:Section({ Title = "Dang ket noi API...", TextSize = 14 })
            state.statsLabel = statusSection:Section({ Title = "Stockfish Depth: 12", TextSize = 12, TextTransparency = 0.5 })
            
            local controlSection = mainTab:Section({ Title = "Dieu Khien", Opened = true })
            
            controlSection:Dropdown({
                Title = "Phe can goi y",
                Values = { "Auto", "White", "Black" },
                Value = "Auto",
                Callback = function(v) state.sideMode = v end,
            })
            
            controlSection:Dropdown({
                Title = "Stockfish Depth",
                Values = { "8", "10", "12", "15" },
                Value = "12",
                Callback = function(v) SEARCH_DEPTH = tonumber(v) or 12 end,
            })
            
            controlSection:Button({
                Title = "Xoa goi y",
                Callback = function() clearHighlights() end,
            })
            state.uiReady = true
        end)
        return success
    end

    -- Board functions
    local function positionKey(board)
        if not board then return "" end
        local list = {}
        for square, piece in pairs(board) do table.insert(list, square .. piece) end
        table.sort(list)
        return table.concat(list, "|")
    end
    
    local function readBoardFromGui()
        local board = {}
        if not state.piecesFrame then return board end
        local children = state.piecesFrame:GetChildren()
        if not children or #children == 0 then return board end
        for _, pieceObject in ipairs(children) do
            local code = PIECE_CODE[pieceObject.Name]
            if code then
                local tile = pieceObject:FindFirstChild("tile")
                if tile and tile:IsA("StringValue") then
                    local val = tile.Value or ""
                    if string.match(val, "^[a-h][1-8]$") then
                        board[val] = code
                    end
                end
            end
        end
        return board
    end
    
    local function detectSideFromDragState()
        if not state.piecesFrame then return nil end
        local enabledWhite, enabledBlack = 0, 0
        local children = state.piecesFrame:GetChildren()
        if not children then return nil end
        for _, pieceObject in ipairs(children) do
            local code = PIECE_CODE[pieceObject.Name]
            if code then
                local drag = pieceObject:FindFirstChild("UIDragDetector")
                if drag and drag:IsA("UIDragDetector") and drag.Enabled then
                    if string.sub(code, 1, 1) == "w" then enabledWhite = enabledWhite + 1
                    else enabledBlack = enabledBlack + 1 end
                end
            end
        end
        if enabledWhite > 0 and enabledBlack == 0 then return "w" end
        if enabledBlack > 0 and enabledWhite == 0 then return "b" end
        return nil
    end
    
    local function chosenPlayerSide()
        if state.sideMode == "White" then return "w" end
        if state.sideMode == "Black" then return "b" end
        return detectSideFromDragState() or state.playerSide
    end

    -- Schedule refresh
    local function scheduleRefresh()
        if not state.booted or state.searchRunning then return end
        
        local board = readBoardFromGui()
        if not board or next(board) == nil then
            setStatus("Chua co ban co...")
            return
        end
        
        local currentKey = positionKey(board)
        if state.lastPositionKey == currentKey then return end
        
        local side = chosenPlayerSide()
        if not side then return end
        
        state.lastPositionKey = currentKey
        clearHighlights()
        setStatus("Dang goi Stockfish API...")
        state.searchRunning = true
        
        task.spawn(function()
            local fen = boardToFEN(board, side)
            local bestMove = getStockfishBestMove(fen, SEARCH_DEPTH)
            
            if not bestMove then
                setStatus("Khong tim thay nuoc di (API loi)")
            else
                drawMoveGuide(bestMove.from, bestMove.to)
                setStatus(string.format("Goi y: %s -> %s", bestMove.from, bestMove.to))
                setEngineStats(string.format("Depth: %d | Luot: %s", SEARCH_DEPTH, side == "w" and "Trang" or "Den"))
            end
            
            state.searchRunning = false
        end)
    end

    -- Watch pieces
    local function watchPiece(pieceObject)
        if not PIECE_CODE[pieceObject.Name] then return end
        local tile = pieceObject:FindFirstChild("tile")
        if tile and tile:IsA("StringValue") then
            local conn = tile:GetPropertyChangedSignal("Value"):Connect(function() 
                task.wait(0.5)
                scheduleRefresh() 
            end)
            table.insert(state.connections, conn)
        end
    end
    
    -- Bind board
    local function bindBoard(boardGui)
        state.boardGui = boardGui
        state.main = boardGui:WaitForChild("Main", 5)
        if not state.main then return false end
        state.boardFrame = state.main:WaitForChild("Board", 5)
        state.piecesFrame = state.main:WaitForChild("Pieces", 5)
        
        if not state.boardFrame or not state.piecesFrame then return false end
        setupWindUI()
        
        local children = state.piecesFrame:GetChildren()
        if children and #children > 0 then
            for _, child in ipairs(children) do watchPiece(child) end
        end
        
        local conn = state.piecesFrame.ChildAdded:Connect(function(child)
            task.defer(function() 
                watchPiece(child) 
                task.wait(0.5)
                scheduleRefresh() 
            end)
        end)
        table.insert(state.connections, conn)
        
        state.booted = true
        scheduleRefresh()
        return true
    end

    -- Boot
    local function boot()
        local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", 10)
        if not playerGui then return end
        local boardGui = playerGui:WaitForChild("2DBoard", 10)
        if not boardGui then return end
        bindBoard(boardGui)
    end
    
    pcall(boot)
end)
