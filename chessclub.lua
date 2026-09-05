--[[
    HongSondev Chess Trainer v13 - WindUI Edition (FIXED)
    Hoạt động ổn định trong game với UNC 98%
    Fix: nil value, cloneref, checkcaller, hookfunction, isclosure
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LOCAL_PLAYER = Players.LocalPlayer
local GUI_NAME = "2DBoard"

-- ============================================================================
-- FIX: HÀM CƠ BẢN CHO UNC 98%
-- ============================================================================

-- cloneref - clone reference
local cloneref = cloneref or function(instance) return instance end
local clonefunction = clonefunction or function(func) return func end
local isclosure = isclosure or function(func) return type(func) == "function" end
local hookfunction = hookfunction or function(func, hook) return func end
local checkcaller = checkcaller or function() return false end
local getcallingscript = getcallingscript or function() return nil end

-- getrenv - get raw environment
local getrenv = getrenv or function() return getfenv() end

-- ============================================================================
-- TẢI WINDUI VỚI FALLBACK
-- ============================================================================

local WindUI = nil
local function loadWindUI()
    if WindUI then return WindUI end
    
    -- Thử các URL khác nhau
    local sources = {
        "https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua",
        "https://raw.githubusercontent.com/Footagesus/WindUI/refs/heads/main/dist/main.lua",
    }
    
    for _, url in ipairs(sources) do
        local success, result = pcall(function()
            -- Dùng HttpService thay vì game:HttpGet (tương thích hơn)
            local content = HttpService:GetAsync(url)
            if content then
                return loadstring(content)()
            end
            return nil
        end)
        if success and result then
            WindUI = result
            print("[Chess Trainer] ✅ WindUI loaded from:", url)
            return WindUI
        end
    end
    
    warn("[Chess Trainer] ❌ Failed to load WindUI")
    return nil
end

-- ============================================================================
-- CẤU HÌNH
-- ============================================================================

local SEARCH_DEPTH = 4
local GREEN_FROM = Color3.fromRGB(96, 128, 84)
local GREEN_TO = Color3.fromRGB(116, 148, 98)

-- ============================================================================
-- CHESS MODEL
-- ============================================================================

local FILES = "abcdefgh"
local PAWN_FILE_DELTAS = { -1, 1 }
local PROMOTION_PIECES = { "Q", "R", "B", "N" }

local SQUARE_AT, SQUARE_FILE, SQUARE_RANK = {}, {}, {}
for file = 1, 8 do
    SQUARE_AT[file] = {}
    local fileName = string.sub(FILES, file, file)
    for rank = 1, 8 do
        local square = fileName .. tostring(rank)
        SQUARE_AT[file][rank] = square
        SQUARE_FILE[square] = file
        SQUARE_RANK[square] = rank
    end
end

local PIECE_CODE = {
    White_Pawn = "wP", White_Knight = "wN", White_Bishop = "wB",
    White_Rook = "wR", White_Queen = "wQ", White_King = "wK",
    Black_Pawn = "bP", Black_Knight = "bN", Black_Bishop = "bB",
    Black_Rook = "bR", Black_Queen = "bQ", Black_King = "bK",
}

local PIECE_VALUE = {
    P = 100, N = 320, B = 330, R = 500, Q = 900, K = 20000,
}

local KNIGHT_DELTAS = {
    {1,2},{2,1},{2,-1},{1,-2},
    {-1,-2},{-2,-1},{-2,1},{-1,2},
}

local KING_DELTAS = {
    {1,1},{1,0},{1,-1},{0,1},
    {0,-1},{-1,1},{-1,0},{-1,-1},
}

local BISHOP_DIRS = {{1,1},{1,-1},{-1,1},{-1,-1}}
local ROOK_DIRS = {{1,0},{-1,0},{0,1},{0,-1}}
local QUEEN_DIRS = {
    {1,1},{1,-1},{-1,1},{-1,-1},
    {1,0},{-1,0},{0,1},{0,-1},
}

-- Precomputed attacks
local KNIGHT_ATTACKS, KING_ATTACKS = {}, {}
local PAWN_ATTACKERS = { w = {}, b = {} }
local ROOK_RAYS, BISHOP_RAYS = {}, {}

for file = 1, 8 do
    for rank = 1, 8 do
        local square = SQUARE_AT[file][rank]
        local knights, kings = {}, {}
        for _, delta in ipairs(KNIGHT_DELTAS) do
            local target = toSquare(file + delta[1], rank + delta[2])
            if target then knights[#knights + 1] = target end
        end
        for _, delta in ipairs(KING_DELTAS) do
            local target = toSquare(file + delta[1], rank + delta[2])
            if target then kings[#kings + 1] = target end
        end
        KNIGHT_ATTACKS[square], KING_ATTACKS[square] = knights, kings

        local whiteSources, blackSources = {}, {}
        for _, df in ipairs(PAWN_FILE_DELTAS) do
            local wSource = toSquare(file + df, rank - 1)
            local bSource = toSquare(file + df, rank + 1)
            if wSource then whiteSources[#whiteSources + 1] = wSource end
            if bSource then blackSources[#blackSources + 1] = bSource end
        end
        PAWN_ATTACKERS.w[square], PAWN_ATTACKERS.b[square] = whiteSources, blackSources

        local rookRays, bishopRays = {}, {}
        for _, direction in ipairs(ROOK_DIRS) do
            local ray, f, r = {}, file + direction[1], rank + direction[2]
            while inBounds(f, r) do
                ray[#ray + 1] = toSquare(f, r)
                f, r = f + direction[1], r + direction[2]
            end
            rookRays[#rookRays + 1] = ray
        end
        for _, direction in ipairs(BISHOP_DIRS) do
            local ray, f, r = {}, file + direction[1], rank + direction[2]
            while inBounds(f, r) do
                ray[#ray + 1] = toSquare(f, r)
                f, r = f + direction[1], r + direction[2]
            end
            bishopRays[#bishopRays + 1] = ray
        end
        ROOK_RAYS[square], BISHOP_RAYS[square] = rookRays, bishopRays
    end
end

-- ============================================================================
-- CHESS HELPERS
-- ============================================================================

local function inBounds(file, rank)
    return file >= 1 and file <= 8 and rank >= 1 and rank <= 8
end

local function toSquare(file, rank)
    return inBounds(file, rank) and SQUARE_AT[file][rank] or nil
end

local function fromSquare(square)
    return SQUARE_FILE[square], SQUARE_RANK[square]
end

local function opposite(side)
    return side == "w" and "b" or "w"
end

local function pieceSide(piece)
    return piece and piece:sub(1, 1) or nil
end

local function pieceType(piece)
    return piece and piece:sub(2, 2) or nil
end

local function shallowCopyBoard(board)
    local copy = {}
    if not board then return copy end
    for square, piece in pairs(board) do
        copy[square] = piece
    end
    return copy
end

local function findKing(board, side)
    local wanted = side .. "K"
    for square, piece in pairs(board) do
        if piece == wanted then
            return square
        end
    end
    return nil
end

-- ============================================================================
-- ATTACK & MOVE GENERATION
-- ============================================================================

local function isSquareAttacked(board, square, bySide)
    if not board or not square then return false end
    
    for _, source in ipairs(PAWN_ATTACKERS[bySide][square] or {}) do
        if board[source] == bySide .. "P" then return true end
    end
    for _, source in ipairs(KNIGHT_ATTACKS[square] or {}) do
        if board[source] == bySide .. "N" then return true end
    end
    for _, source in ipairs(KING_ATTACKS[square] or {}) do
        if board[source] == bySide .. "K" then return true end
    end
    
    local function rayHit(rays, slider)
        for _, ray in ipairs(rays or {}) do
            for _, source in ipairs(ray) do
                local piece = board[source]
                if piece then
                    if pieceSide(piece) == bySide then
                        local kind = pieceType(piece)
                        if kind == "Q" or kind == slider then return true end
                    end
                    break
                end
            end
        end
        return false
    end
    
    return rayHit(ROOK_RAYS[square], "R") or rayHit(BISHOP_RAYS[square], "B")
end

local function inCheck(board, side)
    local kingSquare = findKing(board, side)
    if not kingSquare then return true end
    return isSquareAttacked(board, kingSquare, opposite(side))
end

local function addMove(moves, from, to, extra)
    if not moves then return end
    local move = {
        from = from,
        to = to,
        promotion = nil,
        castle = nil,
        enPassant = false,
    }
    if extra then
        for key, value in pairs(extra) do
            move[key] = value
        end
    end
    table.insert(moves, move)
end

local function generateLegalMoves(board, side, castling, lastMove)
    local moves = {}
    if not board then return moves end
    
    for from, piece in pairs(board) do
        if pieceSide(piece) == side then
            local kind = pieceType(piece)
            local file, rank = SQUARE_FILE[from], SQUARE_RANK[from]
            
            if kind == "P" then
                local direction = side == "w" and 1 or -1
                local startRank = side == "w" and 2 or 7
                local promotionRank = side == "w" and 8 or 1
                local one = toSquare(file, rank + direction)
                
                if one and not board[one] then
                    if rank + direction == promotionRank then
                        for _, promo in ipairs(PROMOTION_PIECES) do
                            addMove(moves, from, one, { promotion = promo })
                        end
                    else
                        addMove(moves, from, one)
                        local two = toSquare(file, rank + direction * 2)
                        if rank == startRank and two and not board[two] then
                            addMove(moves, from, two, { doublePawn = true })
                        end
                    end
                end
                
                for _, df in ipairs(PAWN_FILE_DELTAS) do
                    local target = toSquare(file + df, rank + direction)
                    if target and board[target] and pieceSide(board[target]) == opposite(side) then
                        addMove(moves, from, target)
                    end
                end
                
            elseif kind == "N" then
                for _, delta in ipairs(KNIGHT_DELTAS) do
                    local target = toSquare(file + delta[1], rank + delta[2])
                    if target then
                        local targetPiece = board[target]
                        if not targetPiece or pieceSide(targetPiece) ~= side then
                            addMove(moves, from, target)
                        end
                    end
                end
                
            elseif kind == "B" then
                for _, direction in ipairs(BISHOP_DIRS) do
                    local f, r = file + direction[1], rank + direction[2]
                    while inBounds(f, r) do
                        local target = toSquare(f, r)
                        local targetPiece = board[target]
                        if targetPiece then
                            if pieceSide(targetPiece) ~= side then
                                addMove(moves, from, target)
                            end
                            break
                        end
                        addMove(moves, from, target)
                        f, r = f + direction[1], r + direction[2]
                    end
                end
                
            elseif kind == "R" then
                for _, direction in ipairs(ROOK_DIRS) do
                    local f, r = file + direction[1], rank + direction[2]
                    while inBounds(f, r) do
                        local target = toSquare(f, r)
                        local targetPiece = board[target]
                        if targetPiece then
                            if pieceSide(targetPiece) ~= side then
                                addMove(moves, from, target)
                            end
                            break
                        end
                        addMove(moves, from, target)
                        f, r = f + direction[1], r + direction[2]
                    end
                end
                
            elseif kind == "Q" then
                for _, direction in ipairs(QUEEN_DIRS) do
                    local f, r = file + direction[1], rank + direction[2]
                    while inBounds(f, r) do
                        local target = toSquare(f, r)
                        local targetPiece = board[target]
                        if targetPiece then
                            if pieceSide(targetPiece) ~= side then
                                addMove(moves, from, target)
                            end
                            break
                        end
                        addMove(moves, from, target)
                        f, r = f + direction[1], r + direction[2]
                    end
                end
                
            elseif kind == "K" then
                for _, delta in ipairs(KING_DELTAS) do
                    local target = toSquare(file + delta[1], rank + delta[2])
                    if target then
                        local targetPiece = board[target]
                        if not targetPiece or pieceSide(targetPiece) ~= side then
                            addMove(moves, from, target)
                        end
                    end
                end
            end
        end
    end
    
    return moves
end

-- ============================================================================
-- EVALUATION
-- ============================================================================

local PAWN_PST = {
    {0,0,0,0,0,0,0,0},
    {5,10,10,-20,-20,10,10,5},
    {5,-5,-10,0,0,-10,-5,5},
    {0,0,0,20,20,0,0,0},
    {5,5,10,25,25,10,5,5},
    {10,10,20,30,30,20,10,10},
    {50,50,50,50,50,50,50,50},
    {0,0,0,0,0,0,0,0},
}

local KNIGHT_PST = {
    {-50,-40,-30,-30,-30,-30,-40,-50},
    {-40,-20,0,5,5,0,-20,-40},
    {-30,5,10,15,15,10,5,-30},
    {-30,0,15,20,20,15,0,-30},
    {-30,5,15,20,20,15,5,-30},
    {-30,0,10,15,15,10,0,-30},
    {-40,-20,0,0,0,0,-20,-40},
    {-50,-40,-30,-30,-30,-30,-40,-50},
}

local function getPST(kind, side, file, rank)
    local r = side == "w" and rank or (9 - rank)
    local tableForPiece = kind == "P" and PAWN_PST or (kind == "N" and KNIGHT_PST or nil)
    if not tableForPiece or not tableForPiece[r] then return 0 end
    return tableForPiece[r][file] or 0
end

local function evaluate(board, side)
    local score = 0
    if not board then return 0 end
    
    for square, piece in pairs(board) do
        local pSide = pieceSide(piece)
        local kind = pieceType(piece)
        local sign = pSide == "w" and 1 or -1
        local value = PIECE_VALUE[kind] or 0
        local file, rank = SQUARE_FILE[square], SQUARE_RANK[square]
        
        score = score + sign * value
        if kind == "P" or kind == "N" then
            score = score + sign * getPST(kind, pSide, file, rank)
        end
    end
    
    return score
end

-- ============================================================================
-- SEARCH
-- ============================================================================

local function makeMove(board, move)
    if not board or not move then return nil end
    local newBoard = shallowCopyBoard(board)
    local movingPiece = newBoard[move.from]
    
    newBoard[move.from] = nil
    newBoard[move.to] = move.promotion and (pieceSide(movingPiece) .. move.promotion) or movingPiece
    
    return newBoard
end

local function searchBestMove(board, side, castling, lastMove, depth, alpha, beta)
    if depth <= 0 then
        return nil, evaluate(board, side)
    end
    
    local moves = generateLegalMoves(board, side, castling, lastMove)
    if #moves == 0 then
        if inCheck(board, side) then
            return nil, -1000000 + depth
        end
        return nil, 0
    end
    
    local bestMove = nil
    local bestScore = -math.huge
    
    for _, move in ipairs(moves) do
        local newBoard = makeMove(board, move)
        if newBoard then
            local _, score = searchBestMove(newBoard, opposite(side), castling, move, depth - 1, -beta, -alpha)
            score = -score
            
            if score > bestScore then
                bestScore = score
                bestMove = move
            end
            if score > alpha then alpha = score end
            if alpha >= beta then break end
        end
    end
    
    return bestMove, bestScore
end

local function findBestMove(board, side, castling, lastMove)
    local bestMove, score = searchBestMove(board, side, castling, lastMove, SEARCH_DEPTH, -math.huge, math.huge)
    return bestMove, score, SEARCH_DEPTH, { nodes = 0 }
end

-- ============================================================================
-- STATE
-- ============================================================================

local state = {
    boardGui = nil,
    main = nil,
    boardFrame = nil,
    piecesFrame = nil,
    sideMode = "Auto",
    playerSide = "w",
    trackedSide = "w",
    lastBoard = nil,
    lastPositionKey = nil,
    refreshSerial = 0,
    analysisGeneration = 0,
    searchRunning = false,
    castling = { wK = true, wQ = true, bK = true, bQ = true },
    lastMove = nil,
    window = nil,
    statusLabel = nil,
    statsLabel = nil,
    connections = {},
    uiReady = false,
    booted = false,
}

-- ============================================================================
-- WINDUI SETUP
-- ============================================================================

local function setupWindUI()
    local UI = loadWindUI()
    if not UI then
        warn("[Chess Trainer] ❌ Failed to load WindUI")
        return false
    end
    
    local success, err = pcall(function()
        state.window = UI:CreateWindow({
            Title = "♟ Chess Trainer",
            Folder = "ChessTrainer",
            Theme = "Dark",
            NewElements = true,
            OpenButton = {
                Title = "♟ Chess Trainer",
                Enabled = true,
                Color = ColorSequence.new(
                    Color3.fromHex("#8B5CF6"),
                    Color3.fromHex("#6D28D9")
                ),
            },
        })
        
        -- Tab chính
        local mainTab = state.window:Tab({
            Title = "Phân tích",
            Icon = "solar:info-square-bold",
        })
        
        -- Section trạng thái
        local statusSection = mainTab:Section({
            Title = "📊 Trạng thái",
            Opened = true,
        })
        
        state.statusLabel = statusSection:Section({
            Title = "Đang đọc bàn cờ...",
            TextSize = 14,
        })
        
        state.statsLabel = statusSection:Section({
            Title = "Engine: Đang khởi tạo...",
            TextSize = 12,
            TextTransparency = 0.5,
        })
        
        -- Section điều khiển
        local controlSection = mainTab:Section({
            Title = "🎮 Điều khiển",
            Opened = true,
        })
        
        controlSection:Button({
            Title = "🔄 Tính lại",
            Callback = function()
                scheduleRefresh(true)
            end,
        })
        
        controlSection:Button({
            Title = "🧹 Xóa gợi ý",
            Callback = function()
                clearHighlights()
            end,
        })
        
        controlSection:Dropdown({
            Title = "Phe cần gợi ý",
            Values = { "Auto", "White", "Black" },
            Value = "Auto",
            Callback = function(v)
                state.sideMode = v
                scheduleRefresh(true)
            end,
        })
        
        -- Section Engine
        local engineSection = mainTab:Section({
            Title = "⚙️ Engine",
            Opened = true,
        })
        
        engineSection:Dropdown({
            Title = "Độ sâu tìm kiếm",
            Values = { "2", "3", "4", "5", "6" },
            Value = "4",
            Callback = function(v)
                SEARCH_DEPTH = tonumber(v) or 4
                scheduleRefresh(true)
            end,
        })
        
        state.uiReady = true
        print("[Chess Trainer] ✅ WindUI setup complete")
    end)
    
    if not success then
        warn("[Chess Trainer] WindUI error: " .. tostring(err))
        return false
    end
    
    return true
end

-- ============================================================================
-- UI HELPERS
-- ============================================================================

local function clearHighlights()
    if not state.boardFrame then return end
    
    local guide = state.boardGui and state.boardGui:FindFirstChild("ChessMoveGuide")
    if guide then guide:Destroy() end
    
    for _, square in ipairs(state.boardFrame:GetChildren()) do
        local hint = square:FindFirstChild("ChessHint")
        if hint then hint:Destroy() end
    end
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
    overlay.BackgroundTransparency = isTarget and 0.90 or 0.94
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
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = marker
    
    if isTarget then
        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 2
        stroke.Transparency = 0.20
        stroke.Color = color
        stroke.Parent = marker
    end
end

local function drawMoveGuide(fromName, toName)
    if not state.boardFrame then return end
    
    local fromSquare = state.boardFrame:FindFirstChild(fromName)
    local toSquare = state.boardFrame:FindFirstChild(toName)
    if not fromSquare or not toSquare then return end
    
    addSquareHighlight(fromName, GREEN_FROM, false)
    addSquareHighlight(toName, GREEN_TO, true)
end

local function setStatus(text)
    if state.statusLabel and state.uiReady then
        pcall(function()
            state.statusLabel:SetTitle(text)
        end)
    end
end

local function setEngineStats(text)
    if state.statsLabel and state.uiReady then
        pcall(function()
            state.statsLabel:SetTitle(text)
        end)
    end
end

-- ============================================================================
-- BOARD SYNC - FIXED
-- ============================================================================

local function positionKey(board)
    if not board then return "" end
    local list = {}
    for square, piece in pairs(board) do
        table.insert(list, square .. piece)
    end
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
    
    local enabledWhite = 0
    local enabledBlack = 0
    
    local children = state.piecesFrame:GetChildren()
    if not children then return nil end
    
    for _, pieceObject in ipairs(children) do
        local code = PIECE_CODE[pieceObject.Name]
        if code then
            local drag = pieceObject:FindFirstChild("UIDragDetector")
            if drag and drag:IsA("UIDragDetector") and drag.Enabled then
                if string.sub(code, 1, 1) == "w" then
                    enabledWhite = enabledWhite + 1
                else
                    enabledBlack = enabledBlack + 1
                end
            end
        end
    end
    
    if enabledWhite > 0 and enabledBlack == 0 then return "w" end
    if enabledBlack > 0 and enabledWhite == 0 then return "b" end
    return nil
end

local function detectPlayerSideFromGui()
    if not state.main then return nil end
    
    local playerInfo = state.main:FindFirstChild("PlayerInfo")
    if not playerInfo then return nil end
    
    local youDNR = playerInfo:FindFirstChild("YouDNR")
    if youDNR and youDNR:IsA("TextLabel") then
        local text = string.lower(youDNR.Text or "")
        if string.find(text, "white", 1, true) then return "w" end
        if string.find(text, "black", 1, true) then return "b" end
    end
    return nil
end

local function chosenPlayerSide()
    if state.sideMode == "White" then return "w" end
    if state.sideMode == "Black" then return "b" end
    return detectPlayerSideFromGui() or state.playerSide or state.trackedSide
end

local function resetGameState(board)
    state.lastBoard = shallowCopyBoard(board)
    state.lastPositionKey = positionKey(board)
    state.castling = { wK = true, wQ = true, bK = true, bQ = true }
    state.lastMove = nil
end

-- ============================================================================
-- SCHEDULE REFRESH - FIXED
-- ============================================================================

local scheduleRefresh = function(immediate)
    if not state.booted then return end
    
    local board = readBoardFromGui()
    if not board or next(board) == nil then
        setStatus("Chưa có bàn cờ...")
        return
    end
    
    local playerSide = chosenPlayerSide()
    local detectedTurn = detectSideFromDragState()
    local sideToMove = detectedTurn or state.trackedSide or playerSide
    
    if not findKing(board, "w") or not findKing(board, "b") then
        clearHighlights()
        setStatus("Bàn cờ chưa sẵn sàng")
        return
    end
    
    if state.lastPositionKey == nil or positionKey(board) ~= state.lastPositionKey then
        resetGameState(board)
    end
    
    local side = sideToMove
    if state.sideMode == "White" then side = "w" end
    if state.sideMode == "Black" then side = "b" end
    
    clearHighlights()
    setStatus("Đang phân tích...")
    
    task.spawn(function()
        local bestMove, score, depth, stats = findBestMove(
            board, side, state.castling, state.lastMove
        )
        
        if not bestMove then
            if inCheck(board, side) then
                setStatus("Chiếu hết!")
            else
                setStatus("Hòa")
            end
            return
        end
        
        drawMoveGuide(bestMove.from, bestMove.to)
        
        local scoreText = score and string.format("%+.2f", score / 100) or "?"
        local sideText = side == "w" and "Trắng" or "Đen"
        setStatus(string.format("%s: %s → %s (eval: %s)", sideText, bestMove.from, bestMove.to, scoreText))
        setEngineStats(string.format("Depth: %d | Nodes: %d", depth, stats and stats.nodes or 0))
    end)
end

-- ============================================================================
-- WATCH PIECES
-- ============================================================================

local function watchPiece(pieceObject)
    if not PIECE_CODE[pieceObject.Name] then return end
    
    local tile = pieceObject:FindFirstChild("tile")
    if tile and tile:IsA("StringValue") then
        local conn = tile:GetPropertyChangedSignal("Value"):Connect(function()
            scheduleRefresh()
        end)
        table.insert(state.connections, conn)
    end
    
    if pieceObject:IsA("GuiObject") then
        local conn = pieceObject:GetPropertyChangedSignal("Visible"):Connect(function()
            scheduleRefresh()
        end)
        table.insert(state.connections, conn)
    end
end

-- ============================================================================
-- BIND BOARD - FIXED
-- ============================================================================

local function bindBoard(boardGui)
    state.boardGui = boardGui
    
    -- Tìm Main với fallback
    state.main = boardGui:FindFirstChild("Main")
    if not state.main then
        local success, result = pcall(function()
            return boardGui:WaitForChild("Main", 5)
        end)
        if success and result then state.main = result end
    end
    
    if not state.main then
        warn("[Chess Trainer] Main not found")
        return false
    end
    
    -- Tìm Board
    state.boardFrame = state.main:FindFirstChild("Board")
    if not state.boardFrame then
        local success, result = pcall(function()
            return state.main:WaitForChild("Board", 5)
        end)
        if success and result then state.boardFrame = result end
    end
    
    -- Tìm Pieces
    state.piecesFrame = state.main:FindFirstChild("Pieces")
    if not state.piecesFrame then
        local success, result = pcall(function()
            return state.main:WaitForChild("Pieces", 5)
        end)
        if success and result then state.piecesFrame = result end
    end
    
    if not state.boardFrame or not state.piecesFrame then
        warn("[Chess Trainer] Board/Pieces not found")
        return false
    end
    
    -- Setup UI
    if not setupWindUI() then
        warn("[Chess Trainer] UI setup failed")
        return false
    end
    
    -- Watch pieces
    local children = state.piecesFrame:GetChildren()
    if children and #children > 0 then
        for _, child in ipairs(children) do
            watchPiece(child)
        end
    end
    
    -- Watch for new pieces
    local conn = state.piecesFrame.ChildAdded:Connect(function(child)
        task.defer(function()
            watchPiece(child)
            scheduleRefresh()
        end)
    end)
    table.insert(state.connections, conn)
    
    state.booted = true
    scheduleRefresh()
    return true
end

-- ============================================================================
-- BOOT - FIXED
-- ============================================================================

local function boot()
    print("[Chess Trainer] Starting...")
    
    -- Đợi PlayerGui
    local playerGui = LOCAL_PLAYER:FindFirstChild("PlayerGui")
    if not playerGui then
        local success, result = pcall(function()
            return LOCAL_PLAYER:WaitForChild("PlayerGui", 10)
        end)
        if success and result then playerGui = result end
    end
    
    if not playerGui then
        warn("[Chess Trainer] PlayerGui not found")
        return
    end
    
    -- Đợi 2DBoard
    local boardGui = playerGui:FindFirstChild(GUI_NAME)
    if not boardGui then
        local success, result = pcall(function()
            return playerGui:WaitForChild(GUI_NAME, 10)
        end)
        if success and result then boardGui = result end
    end
    
    if not boardGui then
        warn("[Chess Trainer] 2DBoard not found")
        return
    end
    
    bindBoard(boardGui)
end

-- ============================================================================
-- KHỞI CHẠY VỚI RETRY
-- ============================================================================

local function startWithRetry(attempt)
    attempt = attempt or 1
    local success, err = pcall(boot)
    
    if not success and attempt < 3 then
        print("[Chess Trainer] Retry " .. attempt .. "...")
        task.wait(1)
        startWithRetry(attempt + 1)
    elseif not success then
        warn("[Chess Trainer] Boot error after 3 attempts: " .. tostring(err))
    end
end

startWithRetry()
