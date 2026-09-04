--[[
    HongSondev Chess Trainer v12 - Amethyst UI Edition (FIXED)
    Chạy được trong và ngoài Roblox Studio
    Sử dụng Amethyst UI Library cho giao diện hiện đại
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LOCAL_PLAYER = Players.LocalPlayer
local GUI_NAME = "2DBoard"

-- ============================================================================
-- PHÁT HIỆN MÔI TRƯỜNG
-- ============================================================================

local function isStudio()
    return RunService:IsStudio()
end

local function isServer()
    return not isStudio() and RunService:IsRunning()
end

local function getEnvironment()
    if isStudio() then return "Studio" end
    if isServer() then return "Server" end
    return "Unknown"
end

-- ============================================================================
-- TẢI AMETHYST UI LIBRARY
-- ============================================================================

local AmethystUI = nil
local function loadAmethystUI()
    if AmethystUI then return AmethystUI end
    
    local success, result = pcall(function()
        local sources = {
            "https://raw.githubusercontent.com/J0se-j/My-Lua-Library/refs/heads/main/Booting-the-library.lua",
            "https://raw.githubusercontent.com/J0se-j/My-Lua-Library/main/Booting-the-library.lua",
        }
        
        for _, url in ipairs(sources) do
            local ok, lib = pcall(function()
                return loadstring(game:HttpGet(url))()
            end)
            if ok and lib then
                return lib
            end
        end
        return nil
    end)
    
    if success and result then
        AmethystUI = result
        print("[HongSondev Chess Trainer] ✅ Amethyst UI loaded successfully")
        return AmethystUI
    end
    
    warn("[HongSondev Chess Trainer] ❌ Failed to load Amethyst UI, falling back to native UI")
    return nil
end

-- ============================================================================
-- CẤU HÌNH ENGINE
-- ============================================================================

local SEARCH_MAX_DEPTH = 18
local SEARCH_TIME_BUDGET = 4.00
local QUIESCENCE_DEPTH = 8
local REFRESH_DEBOUNCE = 0.14

local TT_MAX_ENTRIES = 240000

local MOVE_GUIDE_THICKNESS = 4
local MOVE_GUIDE_SHADOW = 7
local ASPIRATION_START = 35
local ASPIRATION_ADJUST = 20
local MAX_ASPIRATION = 500
local MATE_SCORE = 1000000
local MIN_STABLE_DEPTH = 3
local STABLE_DEPTHS_REQUIRED = 2
local HARD_BUDGET_MULTIPLIER = 2.0
local HARD_BUDGET_CAP = 16.0
local SCORE_STABILITY_CP = 40
local PV_DISPLAY_PLIES = 8

local DELTA_PRUNE_MARGIN = 170
local LMP_MAX_DEPTH = 3
local CHECK_EXTENSION_MAX_DEPTH = 5
local CHECK_EXTENSION_MAX_PLY = 10
local NMP_VERIFY_DEPTH = 8
local NMP_BASE_REDUCTION = 2

local GREEN_FROM = Color3.fromRGB(96, 128, 84)
local GREEN_TO = Color3.fromRGB(116, 148, 98)
local GUIDE_SHADOW = Color3.fromRGB(38, 49, 36)
local PANEL_BG = Color3.fromRGB(20, 24, 28)
local PANEL_TEXT = Color3.fromRGB(245, 247, 250)
local PANEL_MUTED = Color3.fromRGB(173, 181, 189)

-- ============================================================================
-- CHESS MODEL
-- ============================================================================

local FILES = "abcdefgh"
local SIDES = { "w", "b" }
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

-- Zobrist Keys
local HASH_BASE = 67108864
local HASH_MASK = 0x03ffffff
local HASH_SEED = 0x2f6e2b1

local function nextHashRandom()
    HASH_SEED = bit32.bxor(HASH_SEED, bit32.lshift(HASH_SEED, 13))
    HASH_SEED = bit32.bxor(HASH_SEED, bit32.rshift(HASH_SEED, 17))
    HASH_SEED = bit32.bxor(HASH_SEED, bit32.lshift(HASH_SEED, 5))
    return bit32.band(HASH_SEED, HASH_MASK)
end

local ZOBRIST_PIECE = {}
local ZOBRIST_SIDE = { nextHashRandom(), nextHashRandom() }
local ZOBRIST_CASTLING = {}
local ZOBRIST_EP = {}
local ZOBRIST_CASTLING_KEYS = { "wK", "wQ", "bK", "bQ" }
local ZOBRIST_PIECES = { "wP", "wN", "wB", "wR", "wQ", "wK", "bP", "bN", "bB", "bR", "bQ", "bK" }

for file = 1, 8 do
    for rank = 1, 8 do
        local square = SQUARE_AT[file][rank]
        local pieceKeys = {}
        ZOBRIST_PIECE[square] = pieceKeys
        for _, piece in ipairs(ZOBRIST_PIECES) do
            pieceKeys[piece] = { nextHashRandom(), nextHashRandom() }
        end
    end
end
for _, key in ipairs(ZOBRIST_CASTLING_KEYS) do
    ZOBRIST_CASTLING[key] = { nextHashRandom(), nextHashRandom() }
end
for file = 1, 8 do
    ZOBRIST_EP[file] = { nextHashRandom(), nextHashRandom() }
end

local function hashToggle(a, b, pair)
    return bit32.bxor(a, pair[1]), bit32.bxor(b, pair[2])
end

local function computeBoardHash(board)
    local a, b = 0, 0
    for square, piece in pairs(board) do
        local pair = ZOBRIST_PIECE[square] and ZOBRIST_PIECE[square][piece]
        if pair then a, b = hashToggle(a, b, pair) end
    end
    return a, b
end

local function ensureBoardHash(position)
    if position.hashA == nil or position.hashB == nil then
        position.hashA, position.hashB = computeBoardHash(position.board)
    end
    return position.hashA, position.hashB
end

-- Piece-square tables
local PAWN_PST = {
    { 0, 0, 0, 0, 0, 0, 0, 0 },
    { 5, 10, 10, -20, -20, 10, 10, 5 },
    { 5, -5, -10, 0, 0, -10, -5, 5 },
    { 0, 0, 0, 20, 20, 0, 0, 0 },
    { 5, 5, 10, 25, 25, 10, 5, 5 },
    { 10, 10, 20, 30, 30, 20, 10, 10 },
    { 50, 50, 50, 50, 50, 50, 50, 50 },
    { 0, 0, 0, 0, 0, 0, 0, 0 },
}

local KNIGHT_PST = {
    {-50,-40,-30,-30,-30,-30,-40,-50},
    {-40,-20, 0, 5, 5, 0,-20,-40},
    {-30, 5, 10, 15, 15, 10, 5,-30},
    {-30, 0, 15, 20, 20, 15, 0,-30},
    {-30, 5, 15, 20, 20, 15, 5,-30},
    {-30, 0, 10, 15, 15, 10, 0,-30},
    {-40,-20, 0, 0, 0, 0,-20,-40},
    {-50,-40,-30,-30,-30,-30,-40,-50},
}

local BISHOP_PST = {
    {-20,-10,-10,-10,-10,-10,-10,-20},
    {-10, 5, 0, 0, 0, 0, 5,-10},
    {-10, 10, 10, 10, 10, 10, 10,-10},
    {-10, 0, 10, 10, 10, 10, 0,-10},
    {-10, 5, 5, 10, 10, 5, 5,-10},
    {-10, 0, 5, 10, 10, 5, 0,-10},
    {-10, 0, 0, 0, 0, 0, 0,-10},
    {-20,-10,-10,-10,-10,-10,-10,-20},
}

local ROOK_PST = {
    { 0, 0, 0, 5, 5, 0, 0, 0},
    {-5, 0, 0, 0, 0, 0, 0,-5},
    {-5, 0, 0, 0, 0, 0, 0,-5},
    {-5, 0, 0, 0, 0, 0, 0,-5},
    {-5, 0, 0, 0, 0, 0, 0,-5},
    {-5, 0, 0, 0, 0, 0, 0,-5},
    { 5,10,10,10,10,10,10, 5},
    { 0, 0, 0, 0, 0, 0, 0, 0},
}

local QUEEN_PST = {
    {-20,-10,-10,-5,-5,-10,-10,-20},
    {-10, 0, 5, 0, 0, 0, 0,-10},
    {-10, 5, 5, 5, 5, 5, 0,-10},
    { 0, 0, 5, 5, 5, 5, 0,-5},
    {-5, 0, 5, 5, 5, 5, 0,-5},
    {-10, 0, 5, 5, 5, 5, 0,-10},
    {-10, 0, 0, 0, 0, 0, 0,-10},
    {-20,-10,-10,-5,-5,-10,-10,-20},
}

local KING_MG_PST = {
    {20,30,10,0,0,10,30,20},
    {20,20,0,0,0,0,20,20},
    {-10,-20,-20,-20,-20,-20,-20,-10},
    {-20,-30,-30,-40,-40,-30,-30,-20},
    {-30,-40,-40,-50,-50,-40,-40,-30},
    {-30,-40,-40,-50,-50,-40,-40,-30},
    {-30,-40,-40,-50,-50,-40,-40,-30},
    {-30,-40,-40,-50,-50,-40,-40,-30},
}

local KING_EG_PST = {
    {-50,-40,-30,-20,-20,-30,-40,-50},
    {-30,-20,-10,0,0,-10,-20,-30},
    {-30,-10,20,30,30,20,-10,-30},
    {-30,-10,30,40,40,30,-10,-30},
    {-30,-10,30,40,40,30,-10,-30},
    {-30,-10,20,30,30,20,-10,-30},
    {-30,-30,0,0,0,0,-30,-30},
    {-50,-30,-30,-30,-30,-30,-30,-50},
}

local PST_BY_KIND = {
    P = PAWN_PST, N = KNIGHT_PST, B = BISHOP_PST,
    R = ROOK_PST, Q = QUEEN_PST,
}

-- Directions
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
    pondering = false,
    lastRenderedKey = nil,
    sideToMove = nil,
    positionSide = nil,
    moveHistory = {},
    positionCounts = {},
    halfmoveClock = 0,
    fullmoveNumber = 1,
    lastOpponentMove = nil,
    lastOpponentIntent = "Chưa có nước đối thủ.",
    lastOpponentThreatSquares = {},
    phase = "Khai cuộc",
    bookEligible = false,
    connections = {},
    
    -- Amethyst UI
    amethyst = nil,
    mainWindow = nil,
    mainTab = nil,
    engineTab = nil,
    statusLabel = nil,
    statsLabel = nil,
    opponentLabel = nil,
    uiReady = false,
    
    searchBudget = SEARCH_TIME_BUDGET,
    frameTimeEMA = 1 / 60,
    fps = 60,
    performanceTier = "Smooth",
    
    engineStats = { nodes = 0, ttHits = 0, cutoffs = 0, qNodes = 0, elapsed = 0 },
    lastMove = nil,
    castling = {
        wK = true, wQ = true,
        bK = true, bQ = true,
    },
}

-- ============================================================================
-- BOARD HELPERS
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

local function shallowCopyBoard(board)
    local copy = {}
    if not board then return copy end
    for square, piece in pairs(board) do
        copy[square] = piece
    end
    return copy
end

local function copyCastling(castling)
    if not castling then
        return { wK = true, wQ = true, bK = true, bQ = true }
    end
    return {
        wK = castling.wK, wQ = castling.wQ,
        bK = castling.bK, bQ = castling.bQ,
    }
end

local function pieceSide(piece)
    return piece and piece:sub(1, 1) or nil
end

local function pieceType(piece)
    return piece and piece:sub(2, 2) or nil
end

-- ============================================================================
-- ATTACK & MOVE GENERATION (SIMPLIFIED)
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

local function findKing(board, side)
    local wanted = side .. "K"
    for square, piece in pairs(board) do
        if piece == wanted then
            return square
        end
    end
    return nil
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
    move.id = from .. to .. (move.promotion or "") .. (move.castle or "")
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

local function moveIdentity(move)
    if not move then return "" end
    return (move.from or "") .. (move.to or "") .. (move.promotion or "") .. (move.castle or "")
end

-- ============================================================================
-- EVALUATION (SIMPLIFIED)
-- ============================================================================

local function getPST(kind, side, file, rank)
    local r = side == "w" and rank or (9 - rank)
    local tableForPiece = PST_BY_KIND[kind]
    if not tableForPiece or not tableForPiece[r] then return 0 end
    return tableForPiece[r][file] or 0
end

local function countPseudoMobility(board, side)
    local count = 0
    if not board then return 0 end
    for square, piece in pairs(board) do
        if pieceSide(piece) == side then
            local kind = pieceType(piece)
            local file, rank = SQUARE_FILE[square], SQUARE_RANK[square]
            
            if kind == "N" then
                for _, delta in ipairs(KNIGHT_DELTAS) do
                    local target = toSquare(file + delta[1], rank + delta[2])
                    if target and (not board[target] or pieceSide(board[target]) ~= side) then
                        count = count + 1
                    end
                end
            elseif kind == "K" then
                for _, delta in ipairs(KING_DELTAS) do
                    local target = toSquare(file + delta[1], rank + delta[2])
                    if target and (not board[target] or pieceSide(board[target]) ~= side) then
                        count = count + 1
                    end
                end
            end
        end
    end
    return count
end

local function evaluate(board, side, castling)
    local score = 0
    if not board then return 0 end
    
    local pieceCount = 0
    local bishops = { w = 0, b = 0 }
    
    for square, piece in pairs(board) do
        pieceCount = pieceCount + 1
        local pSide = pieceSide(piece)
        local kind = pieceType(piece)
        local sign = pSide == "w" and 1 or -1
        local value = PIECE_VALUE[kind] or 0
        local file, rank = SQUARE_FILE[square], SQUARE_RANK[square]
        
        score = score + sign * value
        if kind ~= "K" then
            score = score + sign * getPST(kind, pSide, file, rank)
        end
        
        if kind == "B" then bishops[pSide] = bishops[pSide] + 1
    end
    
    if bishops.w >= 2 then score = score + 45 end
    if bishops.b >= 2 then score = score - 45 end
    
    local whiteMob = countPseudoMobility(board, "w")
    local blackMob = countPseudoMobility(board, "b")
    score = score + (whiteMob - blackMob) * 2
    
    return score
end

-- ============================================================================
-- SEARCH (SIMPLIFIED)
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
        return nil, evaluate(board, side, castling)
    end
    
    local moves = generateLegalMoves(board, side, castling, lastMove)
    if #moves == 0 then
        if inCheck(board, side) then
            return nil, -MATE_SCORE + depth
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
    local bestMove, score = searchBestMove(board, side, castling, lastMove, 4, -math.huge, math.huge)
    return bestMove, score, 4, { nodes = 0 }
end

-- ============================================================================
-- UI HELPERS
-- ============================================================================

local function clearHighlights()
    if not state.boardFrame then return end
    
    local guide = state.boardGui and state.boardGui:FindFirstChild("HongSondevMoveGuide")
    if guide then guide:Destroy() end
    
    for _, square in ipairs(state.boardFrame:GetChildren()) do
        local hint = square:FindFirstChild("HongSondevHint")
        if hint then hint:Destroy() end
    end
end

local function addSquareHighlight(squareName, color, isTarget)
    if not state.boardFrame then return end
    local square = state.boardFrame:FindFirstChild(squareName)
    if not square or not square:IsA("GuiObject") then return end
    
    local overlay = Instance.new("Frame")
    overlay.Name = "HongSondevHint"
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
    if not fromSquare or not toSquare or not fromSquare:IsA("GuiObject") or not toSquare:IsA("GuiObject") then return end
    
    addSquareHighlight(fromName, GREEN_FROM, false)
    addSquareHighlight(toName, GREEN_TO, true)
end

local function setStatus(text)
    if state.statusLabel and state.uiReady then
        pcall(function() state.statusLabel:Set(text) end)
    end
end

local function setEngineStats(text)
    if state.statsLabel and state.uiReady then
        pcall(function() state.statsLabel:Set(text) end)
    end
end

-- ============================================================================
-- AMETHYST UI SETUP (FIXED)
-- ============================================================================

local function setupAmethystUI()
    local Amethyst = loadAmethystUI()
    if not Amethyst then
        warn("[HongSondev Chess Trainer] Failed to load Amethyst UI")
        return false
    end
    
    state.amethyst = Amethyst
    
    local success, err = pcall(function()
        state.mainWindow = Amethyst:CreateWindow({
            Title = "♟ Chess Trainer v12",
            SubTitle = "HongSondev · Elite Search Engine",
            TabWidth = 160,
            Size = UDim2.fromOffset(520, 480),
            Theme = "Dark",
            MinimizeKey = Enum.KeyCode.RightShift,
        })
        
        state.mainTab = state.mainWindow:AddTab({
            Title = "🎯 Phân tích",
            Icon = "target",
        })
        
        state.engineTab = state.mainWindow:AddTab({
            Title = "⚙️ Engine",
            Icon = "settings",
        })
        
        local statusSection = state.mainTab:AddSection({
            Title = "📊 Trạng thái",
            Side = "Left",
        })
        
        state.statusLabel = statusSection:AddParagraph({
            Title = "Trạng thái",
            Content = "Đang đọc bàn cờ...",
            Size = "Medium",
        })
        
        state.opponentLabel = statusSection:AddParagraph({
            Title = "Đối thủ",
            Content = "Chưa có dữ liệu",
            Size = "Small",
        })
        
        state.statsLabel = statusSection:AddParagraph({
            Title = "Engine",
            Content = "Đang khởi tạo...",
            Size = "Small",
        })
        
        local controlSection = state.mainTab:AddSection({
            Title = "🎮 Điều khiển",
            Side = "Right",
        })
        
        controlSection:AddButton({
            Title = "🔄 Tính lại",
            Description = "Chạy lại phân tích từ đầu",
            Callback = function()
                scheduleRefresh(true)
            end,
        })
        
        controlSection:AddButton({
            Title = "🧹 Xóa gợi ý",
            Description = "Xóa highlight khỏi bàn cờ",
            Callback = function()
                clearHighlights()
            end,
        })
        
        controlSection:AddDropdown({
            Title = "Phe cần gợi ý",
            Values = { "Auto", "White", "Black" },
            Multi = false,
            Default = 1,
            Callback = function(value)
                state.sideMode = value
                scheduleRefresh(true)
            end,
        })
        
        local engineSection = state.engineTab:AddSection({
            Title = "⚡ Cấu hình Engine",
        })
        
        engineSection:AddDropdown({
            Title = "Mức độ tính toán",
            Description = "Tăng thời gian để search sâu hơn",
            Values = {
                "Nhanh · 1.5s",
                "Cân bằng · 3s",
                "Mạnh · 6s",
                "Rất mạnh · 9s",
                "Tối đa · 12s"
            },
            Multi = false,
            Default = 3,
            Callback = function(value)
                local budgets = {
                    ["Nhanh · 1.5s"] = 1.5,
                    ["Cân bằng · 3s"] = 3.0,
                    ["Mạnh · 6s"] = 6.0,
                    ["Rất mạnh · 9s"] = 9.0,
                    ["Tối đa · 12s"] = 12.0,
                }
                state.searchBudget = budgets[value] or SEARCH_TIME_BUDGET
                scheduleRefresh(true)
            end,
        })
        
        engineSection:AddParagraph({
            Title = "🔬 Engine Info",
            Content = "Iterative Deepening · Alpha-Beta · TT · LMR · Null Move · Quiescence",
            Size = "Small",
        })
        
        state.uiReady = true
        print("[HongSondev Chess Trainer] ✅ Amethyst UI setup complete")
    end)
    
    if not success then
        warn("[HongSondev Chess Trainer] Amethyst UI error: " .. tostring(err))
        state.uiReady = false
        return false
    end
    
    return true
end

-- ============================================================================
-- BOARD SYNC
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
    
    for _, pieceObject in ipairs(state.piecesFrame:GetChildren()) do
        local code = PIECE_CODE[pieceObject.Name]
        if code then
            local tile = pieceObject:FindFirstChild("tile")
            local visible = true
            if pieceObject:IsA("GuiObject") then visible = pieceObject.Visible end
            if tile and tile:IsA("StringValue") and visible and string.match(tile.Value or "", "^[a-h][1-8]$") then
                board[tile.Value] = code
            end
        end
    end
    
    return board
end

local function detectSideFromDragState()
    if not state.piecesFrame then return nil end
    
    local enabledWhite = 0
    local enabledBlack = 0
    
    for _, pieceObject in ipairs(state.piecesFrame:GetChildren()) do
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
    local youDNR = playerInfo and playerInfo:FindFirstChild("YouDNR")
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
    state.moveHistory = {}
    state.positionCounts = {}
    state.halfmoveClock = 0
    state.fullmoveNumber = 1
    state.trackedSide = "w"
end

-- ============================================================================
-- SCHEDULE REFRESH
-- ============================================================================

local scheduleRefresh = function(immediate)
    local board = readBoardFromGui()
    local key = positionKey(board)
    local playerSide = chosenPlayerSide()
    local detectedTurn = detectSideFromDragState()
    local sideToMove = detectedTurn or state.trackedSide or playerSide
    
    if not findKing(board, "w") then
        clearHighlights()
        setStatus("Không tìm thấy vua Trắng", true)
        return
    end
    if not findKing(board, "b") then
        clearHighlights()
        setStatus("Không tìm thấy vua Đen", true)
        return
    end
    
    if state.lastPositionKey == nil or key ~= state.lastPositionKey then
        resetGameState(board)
        state.lastPositionKey = key
        state.lastBoard = shallowCopyBoard(board)
    end
    
    playerSide = chosenPlayerSide()
    sideToMove = detectedTurn or state.trackedSide or playerSide
    
    -- Opponent turn: no render
    if state.sideMode == "Auto" and sideToMove ~= playerSide then
        clearHighlights()
        setStatus((playerSide == "w" and "Bạn: Trắng" or "Bạn: Đen") .. " · lượt đối thủ", true)
        return
    end
    
    local side = sideToMove
    if state.sideMode == "White" then side = "w" end
    if state.sideMode == "Black" then side = "b" end
    
    clearHighlights()
    setStatus((side == "w" and "Trắng" or "Đen") .. " · đang phân tích...", true)
    
    task.spawn(function()
        local bestMove, score, depth, stats = findBestMove(
            board, side, state.castling, state.lastMove
        )
        
        if not bestMove then
            if inCheck(board, side) then
                setStatus((side == "w" and "Trắng" or "Đen") .. ": chiếu hết", false)
            else
                setStatus((side == "w" and "Trắng" or "Đen") .. ": hòa", false)
            end
            return
        end
        
        drawMoveGuide(bestMove.from, bestMove.to)
        
        local scoreText = score and string.format("%+.2f", score / 100) or "?"
        local sideText = side == "w" and "Trắng" or "Đen"
        setStatus(string.format("%s: %s → %s · depth %d · eval %s", sideText, bestMove.from, bestMove.to, depth, scoreText), false)
        setEngineStats(string.format("nodes: %d", stats and stats.nodes or 0))
    end)
end

-- ============================================================================
-- WATCH PIECES
-- ============================================================================

local function watchPiece(pieceObject)
    if not PIECE_CODE[pieceObject.Name] then return end
    
    local tile = pieceObject:FindFirstChild("tile")
    if tile and tile:IsA("StringValue") then
        tile:GetPropertyChangedSignal("Value"):Connect(function()
            scheduleRefresh()
        end)
    end
    
    if pieceObject:IsA("GuiObject") then
        pieceObject:GetPropertyChangedSignal("Visible"):Connect(function()
            scheduleRefresh()
        end)
    end
end

-- ============================================================================
-- BIND BOARD
-- ============================================================================

local function bindBoard(boardGui)
    state.boardGui = boardGui
    state.main = boardGui:FindFirstChild("Main")
    if not state.main then
        state.main = boardGui:WaitForChild("Main", 10)
    end
    if not state.main then
        warn("[HongSondev Chess Trainer] Main not found")
        return false
    end
    
    state.boardFrame = state.main:FindFirstChild("Board")
    if not state.boardFrame then
        state.boardFrame = state.main:WaitForChild("Board", 10)
    end
    
    state.piecesFrame = state.main:FindFirstChild("Pieces")
    if not state.piecesFrame then
        state.piecesFrame = state.main:WaitForChild("Pieces", 10)
    end
    
    if not state.boardFrame or not state.piecesFrame then
        warn("[HongSondev Chess Trainer] Board/Pieces not found")
        return false
    end
    
    -- Setup Amethyst UI
    if not setupAmethystUI() then
        warn("[HongSondev Chess Trainer] Falling back to native UI")
        -- Tạo native panel fallback ở đây nếu cần
    end
    
    -- Watch pieces
    if state.piecesFrame then
        for _, child in ipairs(state.piecesFrame:GetChildren()) do
            watchPiece(child)
        end
    end
    
    scheduleRefresh()
    return true
end

-- ============================================================================
-- BOOT
-- ============================================================================

local function boot()
    print(string.format("[HongSondev Chess Trainer] Environment: %s", getEnvironment()))
    
    local playerGui = LOCAL_PLAYER:FindFirstChild("PlayerGui")
    if not playerGui then
        playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui", 30)
    end
    
    if not playerGui then
        warn("[HongSondev Chess Trainer] PlayerGui not found")
        return
    end
    
    local boardGui = playerGui:FindFirstChild(GUI_NAME)
    if not boardGui then
        boardGui = playerGui:WaitForChild(GUI_NAME, 30)
    end
    
    if not boardGui then
        warn("[HongSondev Chess Trainer] PlayerGui/2DBoard not found within 30 seconds.")
        return
    end
    
    bindBoard(boardGui)
end

-- Khởi chạy
local success, err = pcall(boot)
if not success then
    warn("[HongSondev Chess Trainer] Boot error: " .. tostring(err))
end
