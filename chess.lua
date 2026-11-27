--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")

local lp = Players.LocalPlayer
local PlayerScripts = lp:WaitForChild("PlayerScripts")
local ChessFolder = ReplicatedStorage:WaitForChild("Chess")
local Engine = require(ChessFolder:WaitForChild("Engine"))

local IS_ROCHESS = ReplicatedStorage:FindFirstChild("ChessClient") ~= nil
	and ReplicatedStorage.ChessClient:FindFirstChild("App") ~= nil

local env = (type(getgenv) == "function" and getgenv()) or _G
if type(env.SonChessCleanup) == "function" then
	pcall(env.SonChessCleanup)
end

local App: any = nil
local RoConfig: any = nil
local RoCosmetics: any = nil
local RoBoardView: any = nil

local CdBot: any = nil
local CdProgression: any = nil
local CdLessons: any = nil
local CdCosmetics: any = nil
local CdTheme: any = nil
local CdBoardView: any = nil
local CdCollection: any = nil
local CdAction: any = nil

if IS_ROCHESS then
	local rc = ReplicatedStorage:WaitForChild("ChessClient")
	App = require(rc:WaitForChild("App"))
	RoConfig = require(ChessFolder:WaitForChild("Config"))
	RoCosmetics = require(ChessFolder:WaitForChild("Cosmetics"))
	RoBoardView = require(rc:WaitForChild("BoardView"))
else
	local cc = PlayerScripts:WaitForChild("ChessClient")
	CdBot = require(ChessFolder:WaitForChild("Bot"))
	CdProgression = require(ChessFolder:WaitForChild("Progression"))
	CdLessons = require(ChessFolder:WaitForChild("Lessons"))
	CdCosmetics = require(ChessFolder:WaitForChild("Cosmetics"))
	CdTheme = require(ChessFolder:WaitForChild("Theme"))
	CdBoardView = require(cc:WaitForChild("BoardView"))
	CdCollection = require(cc:WaitForChild("Collection"))
	CdAction = ReplicatedStorage:WaitForChild("ChessRemotes"):WaitForChild("Action")
end

local CFG = {
	HintEnabled = true,
	LiveHint = true,
	ShowTop2Arrow = false,
	NotifyHints = false,

	AutoPlayEnabled = false,
	ApiProvider = "Auto (Max All)",
	Depth = 18,
	StrictEngine = true,
	MoveDelay = 0.4,
	HumanJitter = 0.1,
	PuzzleDelay = 0.35,

	QuestMatchMode = "Bot (Fast)",
	AutoQuestRunning = false,
	QuickFarmTarget = IS_ROCHESS and "Ranked 3+0 (Blitz)" or "Ranked Blitz",
	QuickFarmRunning = false,
	AutoPuzzleRunning = false,
	AutoMatchRunning = false,
	AutoLessonRunning = false,
	MatchDelay = 1.8,

	HideName = true,
	HintColor = Color3.fromRGB(255, 145, 0),
	FromColor = Color3.fromRGB(52, 211, 153),
	ToColor = Color3.fromRGB(255, 145, 0),
	Top2Color = Color3.fromRGB(56, 189, 248),
	DisplayName = "SonHub Hidden",
}

local alive = true
local connections: { RBXScriptConnection } = {}
local nameShieldConns: { RBXScriptConnection } = {}
local hintResizeConn: RBXScriptConnection? = nil

local BoardViewInstance: any = nil
local GameCtx: any = nil
local PuzzleViewInst: any = nil
local GameViewInst: any = nil
local LessonViewInst: any = nil
local lastGcScanAt = 0

local hintGui: Frame? = nil
local currentHintResult: any = nil

local evalCache: { [string]: any } = {}
local cacheOrder: { string } = {}
local MAX_CACHE_ENTRIES = 300
local pendingByFen: { [string]: { done: boolean, result: any } } = {}
local moveLensCooldownUntil = 0
local chessApiCooldownUntil = 0

local requestSeq = 0
local syncSeq = 0
local lastBoardKey: string? = nil
local lastHintFen: string? = nil
local lastAutoFen: string? = nil
local inFlightAutoFen: string? = nil
local inFlightHintFen: string? = nil
local puzzlesSolvedInSession = 0

local Window: any = nil
local HintStatusPara: any = nil
local QuestGoalsPara: any = nil
local QuestStatusPara: any = nil
local AutoPlayToggleCtrl: any = nil
local AutoQuestToggleCtrl: any = nil
local QuickFarmToggleCtrl: any = nil
local paraCache: { [any]: string } = {}

local PIECE_CODES = { [1] = "P", [2] = "N", [3] = "B", [4] = "R", [5] = "Q", [6] = "K" }
local PIECE_VALUES = { [1] = 100, [2] = 320, [3] = 330, [4] = 500, [5] = 900, [6] = 20000 }
local PROMO_TO_ID = { n = 2, b = 3, r = 4, q = 5 }
local ID_TO_PROMO = { [2] = "N", [3] = "B", [4] = "R", [5] = "Q" }

local ALLOWED_ROCHESS_KINDS: { [string]: boolean } = {
	online = true,
	bot = true,
	puzzle = true,
	rush = true,
}

local PST_KNIGHT = {
	-50,-40,-30,-30,-30,-30,-40,-50, -40,-20,  0,  0,  0,  0,-20,-40,
	-30,  0, 10, 15, 15, 10,  0,-30, -30,  5, 15, 20, 20, 15,  5,-30,
	-30,  0, 15, 20, 20, 15,  0,-30, -30,  5, 10, 15, 15, 10,  5,-30,
	-40,-20,  0,  5,  5,  0,-20,-40, -50,-40,-30,-30,-30,-30,-40,-50,
}

local PST_PAWN = {
	 0,  0,  0,  0,  0,  0,  0,  0,  50, 50, 50, 50, 50, 50, 50, 50,
	10, 10, 20, 30, 30, 20, 10, 10,   5,  5, 10, 25, 25, 10,  5,  5,
	 0,  0,  0, 20, 20,  0,  0,  0,   5, -5,-10,  0,  0,-10, -5,  5,
	 5, 10, 10,-20,-20, 10, 10,  5,   0,  0,  0,  0,  0,  0,  0,  0,
}

local httpRequest = (function()
	for _, fn in ipairs({
		env.request,
		request,
		http_request,
		type(syn) == "table" and syn.request or nil,
		type(http) == "table" and http.request or nil,
	}) do
		if type(fn) == "function" then
			return fn
		end
	end
	return nil
end)()

local wsConnect = (type(WebSocket) == "table" and type(WebSocket.connect) == "function" and WebSocket.connect)
	or (type(syn) == "table" and type(syn.websocket) == "table" and type(syn.websocket.connect) == "function" and syn.websocket.connect)
	or nil

local setIdentityFn = env.setthreadidentity or setthreadidentity or env.setidentity or setidentity
local getUpvaluesFn = env.getupvalues or getupvalues or (type(debug) == "table" and debug.getupvalues or nil)
local fireSignalFn = env.firesignal or firesignal
local hookMetamethodFn = env.hookmetamethod or hookmetamethod
local newCClosureFn = env.newcclosure or newcclosure
local checkCallerFn = env.checkcaller or checkcaller
local getNamecallMethodFn = env.getnamecallmethod or getnamecallmethod
local writeFileFn = env.writefile or writefile
local readFileFn = env.readfile or readfile
local isFileFn = env.isfile or isfile
local queueOnTeleportFn = env.queue_on_teleport or queue_on_teleport or env.queueonteleport or queueonteleport
	or (type(syn) == "table" and syn.queue_on_teleport or nil)

local function elevateIdentity()
	if type(setIdentityFn) == "function" then
		pcall(setIdentityFn, 8)
	end
end

local function httpRequestJson(url: string, method: string?, bodyTable: any?, timeoutSec: number?): (boolean, any, number)
	if not httpRequest then
		return false, "no http", 0
	end
	local reqMethod = method or "GET"
	local reqData: { [string]: any } = {
		Url = url,
		Method = reqMethod,
		Headers = {
			["Accept"] = "application/json",
			["User-Agent"] = "SonChess/6.2",
		},
	}
	if bodyTable ~= nil then
		reqData.Headers["Content-Type"] = "application/json"
		reqData.Body = HttpService:JSONEncode(bodyTable)
	end

	local t0 = os.clock()
	local done = false
	local okReq, resData: any = false, nil

	task.spawn(function()
		local ok, res = pcall(httpRequest, reqData)
		okReq = ok
		resData = res
		done = true
	end)

	local limit = timeoutSec or 4.5
	local deadline = t0 + limit
	while not done and alive and os.clock() < deadline do
		task.wait(0.02)
	end
	local elapsed = os.clock() - t0
	if not done then
		return false, "timeout", elapsed
	end
	if not okReq or type(resData) ~= "table" then
		return false, "req failed", elapsed
	end
	local status = tonumber(resData.StatusCode or resData.Status or resData.status_code or resData.status) or 0
	local body = resData.Body or resData.body
	if status ~= 200 or type(body) ~= "string" or #body == 0 then
		return false, "http " .. tostring(status), elapsed
	end
	local decOk, data = pcall(HttpService.JSONDecode, HttpService, body)
	if not decOk or type(data) ~= "table" then
		return false, "bad json", elapsed
	end
	return true, data, elapsed
end

local function isGuiActuallyVisible(gui: Instance?): boolean
	local cur: Instance? = gui
	while cur do
		if cur:IsA("GuiObject") then
			if not cur.Visible then return false end
		elseif cur:IsA("LayerCollector") then
			return cur.Enabled
		end
		cur = cur.Parent
	end
	return false
end

local function sq64ToAlg(sq: number): string
	return string.char(97 + (sq - 1) % 8) .. tostring((sq - 1) // 8 + 1)
end

local function algToSq64(sqStr: string): number?
	if #sqStr ~= 2 then return nil end
	local f = string.byte(sqStr, 1) - 97
	local r = tonumber(string.sub(sqStr, 2, 2))
	if not r or f < 0 or f > 7 or r < 1 or r > 8 then return nil end
	return (r - 1) * 8 + f + 1
end

local function countPiecesAndKings64(board64: { number }): (number, number, number)
	local total, wk, bk = 0, 0, 0
	for i = 1, 64 do
		local p = board64[i] or 0
		if p ~= 0 then
			total += 1
			if p == 6 then wk += 1 elseif p == -6 then bk += 1 end
		end
	end
	return total, wk, bk
end

local function sanitizeFen64(fen: string?, board64: { number }?, turn: number?): string?
	if type(fen) ~= "string" or #fen == 0 then return nil end
	if not board64 then return fen end
	local parts = string.split(fen, " ")
	if #parts < 4 then return fen end

	local castle = parts[3] or "-"
	if castle ~= "-" then
		local out = ""
		if castle:find("K", 1, true) and board64[5] == 6 and board64[8] == 4 then out ..= "K" end
		if castle:find("Q", 1, true) and board64[5] == 6 and board64[1] == 4 then out ..= "Q" end
		if castle:find("k", 1, true) and board64[61] == -6 and board64[64] == -4 then out ..= "k" end
		if castle:find("q", 1, true) and board64[61] == -6 and board64[57] == -4 then out ..= "q" end
		parts[3] = (out ~= "") and out or "-"
	end

	local epStr = parts[4] or "-"
	if epStr ~= "-" then
		local epSq = algToSq64(epStr)
		local t = turn or (parts[2] == "b" and -1 or 1)
		local validEp = false
		if epSq then
			local epFile = (epSq - 1) % 8
			local rankSq = epSq - 8 * t
			for _, df in ipairs({ -1, 1 }) do
				local nf = epFile + df
				if nf >= 0 and nf <= 7 then
					local adj = rankSq + df
					if adj >= 1 and adj <= 64 and board64[adj] == t then
						validEp = true
						break
					end
				end
			end
		end
		if not validEp then parts[4] = "-" end
	end

	parts[5] = parts[5] or "0"
	parts[6] = parts[6] or "1"
	return table.concat(parts, " ")
end

local function cachePut(key: string, value: any)
	if not evalCache[key] then
		table.insert(cacheOrder, key)
		if #cacheOrder > MAX_CACHE_ENTRIES then
			local oldest = table.remove(cacheOrder, 1)
			if oldest then evalCache[oldest] = nil end
		end
	end
	evalCache[key] = value
end

local function formatCpEval(cp: number): string
	local pawns = cp / 100
	return (pawns >= 0) and string.format("+%.2f", pawns) or string.format("%.2f", pawns)
end

type NormMove = {
	uci: string,
	from64: number,
	to64: number,
	promo: number,
	san: string?,
	raw: any,
}

type StateSnapshot = {
	fen: string?,
	board64: { number },
	turn: number,
	legalMoves: { NormMove },
	bv: any,
}

local function isValidCdBoardView(bv: any): boolean
	return type(bv) == "table"
		and type(bv.cells) == "table"
		and typeof(bv.frame) == "Instance"
		and bv.frame.Parent ~= nil
		and type(bv.state) == "table"
		and type(bv.state.board) == "table"
end

local function scoreCdBoardView(bv: any): number
	if not isValidCdBoardView(bv) then return -1 end
	local score = 0
	if isGuiActuallyVisible(bv.frame) then score += 100 elseif bv.frame.Visible then score += 20 end
	if type(bv.onMove) == "function" then score += 30 end
	if type(bv.legal) == "table" and #bv.legal > 0 then score += 50 end
	if bv.side == 1 or bv.side == -1 then score += 40 end
	return score
end

local function scanControllers(force: boolean?)
	if IS_ROCHESS then
		if App and App.board then
			BoardViewInstance = App.board
			env.SonChessBoardView = App.board
		end
		return
	end

	if not force and isValidCdBoardView(BoardViewInstance) and GameCtx and GameViewInst and PuzzleViewInst and LessonViewInst then
		return
	end
	local now = os.clock()
	if not force and (now - lastGcScanAt) < 2.0 then
		return
	end
	lastGcScanAt = now

	if type(getgc) ~= "function" then return end
	local bestBv: any = isValidCdBoardView(BoardViewInstance) and BoardViewInstance or nil
	local bestScore = bestBv and scoreCdBoardView(bestBv) or 0

	local ok, gcList = pcall(getgc, true)
	if not ok or type(gcList) ~= "table" then return end
	for _, obj in ipairs(gcList) do
		if type(obj) == "table" then
			if rawget(obj, "cells") and rawget(obj, "arrowLayer") and rawget(obj, "state") and getmetatable(obj) == CdBoardView then
				local sc = scoreCdBoardView(obj)
				if sc > bestScore then
					bestScore = sc
					bestBv = obj
				end
			elseif rawget(obj, "profile") and rawget(obj, "board") and rawget(obj, "Action") and type(rawget(obj, "mode")) == "function" then
				GameCtx = obj
			elseif rawget(obj, "start") and rawget(obj, "endRush") and rawget(obj, "next") and rawget(obj, "hint") then
				PuzzleViewInst = obj
			elseif rawget(obj, "newGame") and rawget(obj, "play") and rawget(obj, "onReward") and rawget(obj, "current") then
				GameViewInst = obj
			elseif rawget(obj, "loadStep") and rawget(obj, "nextLesson") and rawget(obj, "start") then
				LessonViewInst = obj
			end
		end
	end

	if bestBv then
		BoardViewInstance = bestBv
		env.SonChessBoardView = bestBv
		env.SonChessBoard = bestBv.state
	end
end

local function getCurrentMode(): string
	if IS_ROCHESS then
		local s = App and App.session
		return s and s.kind or "idle"
	end
	if GameCtx and type(GameCtx.mode) == "function" then
		local ok, m = pcall(GameCtx.mode)
		if ok and type(m) == "string" then return m end
	end
	return "unknown"
end

local function isBoardVisible(): boolean
	local bv = BoardViewInstance
	return type(bv) == "table" and typeof(bv.frame) == "Instance" and bv.frame.Parent ~= nil and isGuiActuallyVisible(bv.frame)
end

local function getActiveBoardKey(): string?
	if IS_ROCHESS then
		local s = App and App.session
		if not s then return nil end
		return tostring(s.id or s.kind) .. ":" .. tostring(s.ucis and #s.ucis or 0) .. ":" .. tostring(s.version or 0) .. ":" .. tostring(s.engine and s.engine.side or 0)
	end
	local bv = BoardViewInstance
	if not isValidCdBoardView(bv) then return nil end
	local st = bv.state
	return tostring(st.turn or 0) .. ":" .. tostring(st.ply or 0) .. ":" .. tostring(type(bv.legal) == "table" and #bv.legal or 0) .. ":" .. tostring(bv.side or 0)
end

local function isMyTurn(): boolean
	if IS_ROCHESS then
		if App and App.board then BoardViewInstance = App.board end
		if not isBoardVisible() then return false end
		local s = App and App.session
		if not s or not ALLOWED_ROCHESS_KINDS[s.kind] or s.over then return false end
		if type(s.status) == "function" then
			local stOk, stVal = pcall(s.status, s)
			if stOk and stVal ~= "ongoing" then return false end
		end
		if s.viewPly ~= nil and s.ucis and s.viewPly ~= #s.ucis then return false end
		local pz = s.pz
		if (s.kind == "puzzle" or s.kind == "rush") and pz then
			if pz.busy or pz.done or pz.wrong then return false end
		end
		if s.myColor ~= 1 and s.myColor ~= -1 then return false end
		if not s.engine or s.engine.side ~= s.myColor then return false end
		return true
	end

	scanControllers(false)
	if not isBoardVisible() then return false end
	local bv = BoardViewInstance
	if not isValidCdBoardView(bv) then return false end
	if type(bv.onMove) ~= "function" or type(bv.legal) ~= "table" or #bv.legal == 0 then return false end

	local mode = getCurrentMode()
	if mode == "home" or mode == "queue" or mode == "analysis" or mode == "review" or mode == "watch" or mode == "spectate" then
		return false
	end
	if mode == "game" and GameViewInst and type(GameViewInst.current) == "function" then
		local okG, curG = pcall(GameViewInst.current)
		if okG and type(curG) == "table" and (curG.over or curG.past or curG.you == 0) then
			return false
		end
	end

	local side = bv.side
	if mode == "puzzle" or mode == "lesson" then
		if side ~= nil and side ~= 0 and bv.state.turn ~= side then return false end
		return true
	end
	return (side == 1 or side == -1) and bv.state.turn == side
end

local function getStateSnapshot(): StateSnapshot?
	scanControllers(false)
	local bv = BoardViewInstance
	if not bv then return nil end

	if IS_ROCHESS then
		local s = App and App.session
		local eng = s and ALLOWED_ROCHESS_KINDS[s.kind] and s.engine or nil
		if not eng then return nil end
		local board64 = eng:boardArray()
		local rawFen = eng:getFen()
		local turn = eng.side or 1
		local fen = sanitizeFen64(rawFen, board64, turn)

		local legalMoves: { NormMove } = {}
		for _, rawMv in ipairs(eng:legalMoves() or {}) do
			local f64, t64 = Engine.moveSquares64(rawMv)
			local promo = Engine.movePromo(rawMv) or 0
			table.insert(legalMoves, {
				uci = eng:moveToUci(rawMv),
				from64 = f64,
				to64 = t64,
				promo = promo,
				san = nil,
				raw = rawMv,
			})
		end
		return { fen = fen, board64 = board64, turn = turn, legalMoves = legalMoves, bv = bv }
	end

	if not isValidCdBoardView(bv) then return nil end
	local st = bv.state
	local rawLegals = (type(bv.legal) == "table" and #bv.legal > 0) and bv.legal or (Engine.legalMoves(st) or {})
	local legalMoves: { NormMove } = {}
	for _, rawMv in ipairs(rawLegals) do
		table.insert(legalMoves, {
			uci = Engine.uci(rawMv),
			from64 = rawMv.from,
			to64 = rawMv.to,
			promo = rawMv.promo or 0,
			san = nil,
			raw = rawMv,
		})
	end
	local okFen, rawFen = pcall(Engine.toFEN, st)
	local fen = okFen and sanitizeFen64(rawFen, st.board, st.turn) or nil
	return { fen = fen, board64 = st.board, turn = st.turn, legalMoves = legalMoves, bv = bv }
end

local function computeSanForMove(snap: StateSnapshot, mv: NormMove): string
	if mv.san then return mv.san end
	if IS_ROCHESS then
		local eng = App and App.session and App.session.engine
		if eng then
			local ok, s = pcall(eng.moveToSan, eng, mv.raw)
			if ok and type(s) == "string" then
				mv.san = s
				return s
			end
		end
		return mv.uci
	end
	local ok, s = pcall(Engine.san, Engine.clone(snap.bv.state), mv.raw)
	mv.san = (ok and type(s) == "string") and s or mv.uci
	return mv.san :: string
end

local function formatMoveLabel(snap: StateSnapshot, mv: NormMove): string
	local piece = math.abs(snap.board64[mv.from64] or 0)
	local pCode = PIECE_CODES[piece] or "?"
	local promoTag = (mv.promo ~= 0) and ("=" .. (ID_TO_PROMO[mv.promo] or "Q")) or ""
	return string.format("[%s] %s -> %s%s (%s)", pCode, sq64ToAlg(mv.from64), sq64ToAlg(mv.to64), promoTag, computeSanForMove(snap, mv))
end

local function resolveLegalMove(legalMoves: { NormMove }, uci: string): NormMove?
	if type(uci) ~= "string" or #uci < 4 then return nil end
	uci = string.lower(uci)
	local fromSq = algToSq64(string.sub(uci, 1, 2))
	local toSq = algToSq64(string.sub(uci, 3, 4))
	if not fromSq or not toSq then return nil end
	local promoChar = #uci >= 5 and string.sub(uci, 5, 5) or nil
	local promoId = promoChar and PROMO_TO_ID[promoChar] or nil

	local fallback: NormMove? = nil
	for _, mv in ipairs(legalMoves) do
		if mv.from64 == fromSq and mv.to64 == toSq then
			if promoId then
				if mv.promo == promoId then return mv end
			elseif mv.promo == 0 or mv.promo == 5 then
				return mv
			end
			fallback = fallback or mv
		end
	end
	return fallback
end

local function executeMoveOnBoard(snap: StateSnapshot, mv: NormMove): boolean
	local bv = snap.bv
	if not bv then return false end
	if IS_ROCHESS then
		if type(bv.commit) == "function" then
			local ok = pcall(bv.commit, bv, mv.from64, mv.to64, mv.promo or 0, false)
			if ok then return true end
		end
		return false
	end
	if type(bv.commit) == "function" then
		local ok = pcall(bv.commit, bv, mv.raw, true, true)
		if ok then return true end
	end
	if type(bv.onMove) == "function" then
		local ok = pcall(bv.onMove, mv.raw, true)
		if ok then return true end
	end
	CdAction:FireServer("move", { from = mv.from64, to = mv.to64, promo = mv.promo or 0 })
	return true
end

local function getCdPuzzleState(): (any, number?)
	if IS_ROCHESS or not PuzzleViewInst or type(getUpvaluesFn) ~= "function" or type(PuzzleViewInst.hint) ~= "function" then
		return nil, nil
	end
	local ok, ups = pcall(getUpvaluesFn, PuzzleViewInst.hint)
	if not ok or type(ups) ~= "table" then return nil, nil end

	local puzzleObj: any = nil
	local evenNums: { number } = {}
	local otherNums: { number } = {}
	for _, v in pairs(ups) do
		if type(v) == "table" and type(v.moves) == "table" and type(v.fen) == "string" then
			puzzleObj = v
		elseif type(v) == "number" and v >= 1 and v % 1 == 0 then
			if v >= 2 and v % 2 == 0 then
				table.insert(evenNums, v)
			else
				table.insert(otherNums, v)
			end
		end
	end
	if not puzzleObj then return nil, nil end
	table.sort(evenNums)
	table.sort(otherNums)
	return puzzleObj, evenNums[1] or otherNums[1]
end

local function tryGetPuzzleSolution(snap: StateSnapshot): any
	local mode = getCurrentMode()
	if mode ~= "puzzle" and mode ~= "rush" then return nil end

	if IS_ROCHESS then
		local pz = App and App.session and App.session.pz
		if type(pz) == "table" and type(pz.sol) == "table" and type(pz.step) == "number" then
			local uci = pz.sol[pz.step]
			if type(uci) == "string" then
				local mv = resolveLegalMove(snap.legalMoves, uci)
				if mv then
					return { move = mv, evalText = "R:" .. tostring(pz.data and pz.data.rating or "?"), source = "Puzzle", fen = snap.fen, depth = 99, trusted = true }
				end
			end
		end
		return nil
	end

	local puzzleObj, stepIdx = getCdPuzzleState()
	if not puzzleObj then return nil end

	local uci = stepIdx and puzzleObj.moves[stepIdx] or nil
	if type(uci) == "string" then
		local mv = resolveLegalMove(snap.legalMoves, uci)
		if mv then
			return { move = mv, evalText = "R:" .. tostring(puzzleObj.rating or "?"), source = "Puzzle", fen = snap.fen, depth = 99, trusted = true }
		end
	end
	for i = 2, #puzzleObj.moves, 2 do
		local cand = puzzleObj.moves[i]
		if type(cand) == "string" then
			local mv = resolveLegalMove(snap.legalMoves, cand)
			if mv then
				return { move = mv, evalText = "R:" .. tostring(puzzleObj.rating or "?"), source = "Puzzle", fen = snap.fen, depth = 99, trusted = true }
			end
		end
	end
	return nil
end

local function getCurrentLessonGoal(): string?
	if IS_ROCHESS or not LessonViewInst or type(LessonViewInst.loadStep) ~= "function" or type(getUpvaluesFn) ~= "function" then
		return nil
	end
	local ok, ups = pcall(getUpvaluesFn, LessonViewInst.loadStep)
	if not ok or type(ups) ~= "table" then return nil end
	for _, v in pairs(ups) do
		if type(v) == "table" and type(v.goal) == "string" and type(v.fen) == "string" then
			return v.goal
		end
	end
	return nil
end

local function bfsCdLessonMove(state: any, legalMoves: { NormMove }, predicate: (any, number) -> boolean): NormMove?
	local startSq: number? = nil
	for i = 1, 64 do
		if state.board[i] > 0 then startSq = i; break end
	end
	if not startSq then return nil end

	local queue: { { state: any, firstUci: string? } } = { { state = Engine.clone(state), firstUci = nil } }
	local visited: { [number]: boolean } = { [startSq] = true }
	local head = 1

	while head <= #queue and head <= 160 do
		local node = queue[head]
		head += 1
		if head == 2 then
			for _, mv in ipairs(legalMoves) do
				if not visited[mv.to64] then
					visited[mv.to64] = true
					if predicate(node.state, mv.to64) then return mv end
					local nextSt = Engine.clone(node.state)
					Engine.makeMove(nextSt, mv.raw)
					nextSt.turn = 1
					nextSt.ep = 0
					table.insert(queue, { state = nextSt, firstUci = mv.uci })
				end
			end
		else
			for _, rawMv in ipairs(Engine.pseudoMoves(node.state)) do
				if not visited[rawMv.to] then
					visited[rawMv.to] = true
					if predicate(node.state, rawMv.to) then
						local verified = node.firstUci and resolveLegalMove(legalMoves, node.firstUci)
						if verified then return verified end
					end
					local nextSt = Engine.clone(node.state)
					Engine.makeMove(nextSt, rawMv)
					nextSt.turn = 1
					nextSt.ep = 0
					table.insert(queue, { state = nextSt, firstUci = node.firstUci })
				end
			end
		end
	end
	return nil
end

local function trySolveLesson(snap: StateSnapshot): any
	if IS_ROCHESS or getCurrentMode() ~= "lesson" then return nil end
	local bv = snap.bv
	local state = bv.state
	local legalMoves = snap.legalMoves
	local lessonGoal = getCurrentLessonGoal()
	local pieceCount, wk, bk = countPiecesAndKings64(snap.board64)

	if wk == 1 and bk == 1 then
		if lessonGoal == "castle" or (not lessonGoal and pieceCount <= 6) then
			for _, mv in ipairs(legalMoves) do
				if mv.raw.kind == Engine.CASTLE_K or mv.raw.kind == Engine.CASTLE_Q then
					return { move = mv, evalText = "Castle", source = "Lesson", fen = snap.fen, depth = 99, trusted = true }
				end
			end
		end
		if lessonGoal == "check" then
			local clone = Engine.clone(state)
			for _, mv in ipairs(legalMoves) do
				local undo = Engine.makeMove(clone, mv.raw)
				local gaveCheck = Engine.inCheck(clone)
				Engine.unmakeMove(clone, undo)
				if gaveCheck then
					return { move = mv, evalText = "Check+", source = "Lesson", fen = snap.fen, depth = 99, trusted = true }
				end
			end
		end
		if lessonGoal == "mate" then
			local clone = Engine.clone(state)
			for _, mv in ipairs(legalMoves) do
				local undo = Engine.makeMove(clone, mv.raw)
				local opp = Engine.inCheck(clone) and Engine.legalMoves(clone) or nil
				Engine.unmakeMove(clone, undo)
				if opp and #opp == 0 then
					return { move = mv, evalText = "Mate#", source = "Lesson", fen = snap.fen, depth = 99, trusted = true }
				end
			end
		end
	end

	if type(bv.stars) == "table" and next(bv.stars) ~= nil then
		for _, mv in ipairs(legalMoves) do
			if bv.stars[mv.to64] then
				return { move = mv, evalText = "Star", source = "Lesson BFS", fen = snap.fen, depth = 99, trusted = true }
			end
		end
		local bfsMv = bfsCdLessonMove(state, legalMoves, function(_, sq) return bv.stars[sq] == true end)
		if bfsMv then
			return { move = bfsMv, evalText = "Star", source = "Lesson BFS", fen = snap.fen, depth = 99, trusted = true }
		end
	end

	if wk == 0 or bk == 0 then
		for _, mv in ipairs(legalMoves) do
			if (snap.board64[mv.to64] or 0) < 0 then
				return { move = mv, evalText = "Capture", source = "Lesson", fen = snap.fen, depth = 99, trusted = true }
			end
		end
		local bfsMv = bfsCdLessonMove(state, legalMoves, function(st, sq) return (st.board[sq] or 0) < 0 end)
		if bfsMv then
			return { move = bfsMv, evalText = "Capture", source = "Lesson BFS", fen = snap.fen, depth = 99, trusted = true }
		end
	end

	return nil
end

local function findMateInOne(snap: StateSnapshot): NormMove?
	if IS_ROCHESS then
		if not snap.fen then return nil end
		local ok, eng = pcall(Engine.new, snap.fen)
		if not ok or not eng then return nil end
		for _, mv in ipairs(snap.legalMoves) do
			local raw = eng:moveFromUci(mv.uci)
			if raw then
				eng:play(raw)
				local isMate = eng:inCheck() and #(eng:legalMoves()) == 0
				eng:takeback()
				if isMate then return mv end
			end
		end
		return nil
	end

	local clone = Engine.clone(snap.bv.state)
	for _, mv in ipairs(snap.legalMoves) do
		local undo = Engine.makeMove(clone, mv.raw)
		local oppMoves = Engine.inCheck(clone) and Engine.legalMoves(clone) or nil
		Engine.unmakeMove(clone, undo)
		if oppMoves and #oppMoves == 0 then return mv end
	end
	return nil
end

local function evalStaticBoard64(board64: { number }, sideToMove: number): number
	local score = 0
	for sq = 1, 64 do
		local p = board64[sq] or 0
		if p ~= 0 then
			local absP = math.abs(p)
			local val = PIECE_VALUES[absP] or 0
			local f = (sq - 1) % 8
			local r = (sq - 1) // 8
			local pstIdx = (p > 0) and ((7 - r) * 8 + f + 1) or (r * 8 + f + 1)
			if absP == 1 then
				val += PST_PAWN[pstIdx] or 0
			elseif absP == 2 then
				val += PST_KNIGHT[pstIdx] or 0
			elseif absP == 3 or absP == 5 then
				val += ((3.5 - math.abs(f - 3.5)) + (3.5 - math.abs(r - 3.5))) * 3
			end
			score += (p > 0) and val or -val
		end
	end
	return score * sideToMove
end

local function localAlphaBetaFallback(snap: StateSnapshot, maxDepth: number, timeBudgetSec: number): NormMove
	local deadline = os.clock() + timeBudgetSec
	local sliceStart = os.clock()
	local nodes = 0
	local aborted = false

	local function checkBudget(): boolean
		nodes += 1
		local now = os.clock()
		if now > deadline then
			aborted = true
			return true
		end
		if nodes % 256 == 0 and (now - sliceStart) >= 0.008 then
			task.wait()
			sliceStart = os.clock()
			if os.clock() > deadline or not alive then
				aborted = true
				return true
			end
		end
		return false
	end

	if IS_ROCHESS and snap.fen then
		local ok, eng = pcall(Engine.new, snap.fen)
		if ok and eng then
			local function orderMoves(rawMoves: { any }): { any }
				local b = eng:boardArray()
				local scored = {}
				for _, m in ipairs(rawMoves) do
					local f, t = Engine.moveSquares64(m)
					local cap = math.abs(b[t] or 0)
					local att = math.abs(b[f] or 0)
					local promo = Engine.movePromo(m) or 0
					local sc = (cap > 0 and (10000 + cap * 100 - att) or 0) + (promo * 500)
					table.insert(scored, { m = m, s = sc })
				end
				table.sort(scored, function(a, b2) return a.s > b2.s end)
				local out = {}
				for _, e in ipairs(scored) do table.insert(out, e.m) end
				return out
			end

			local function quiesce(alpha: number, beta: number, qply: number): number
				if checkBudget() then return alpha end
				local stand = evalStaticBoard64(eng:boardArray(), eng.side)
				if stand >= beta then return beta end
				if stand > alpha then alpha = stand end
				if qply >= 4 then return alpha end

				local b = eng:boardArray()
				local caps = {}
				for _, m in ipairs(eng:legalMoves() or {}) do
					local _, t = Engine.moveSquares64(m)
					if (b[t] or 0) ~= 0 or (Engine.movePromo(m) or 0) ~= 0 then
						table.insert(caps, m)
					end
				end
				for _, m in ipairs(orderMoves(caps)) do
					eng:play(m)
					local sc = -quiesce(-beta, -alpha, qply + 1)
					eng:takeback()
					if aborted then return alpha end
					if sc >= beta then return beta end
					if sc > alpha then alpha = sc end
				end
				return alpha
			end

			local function ab(depth: number, alpha: number, beta: number, ply: number): (number, any)
				if checkBudget() then return alpha, nil end
				local moves = eng:legalMoves() or {}
				if #moves == 0 then
					return eng:inCheck() and (-90000 + ply) or 0, nil
				end
				if depth <= 0 then
					return quiesce(alpha, beta, 0), nil
				end
				local bestMv = nil
				for _, m in ipairs(orderMoves(moves)) do
					eng:play(m)
					local sc = -ab(depth - 1, -beta, -alpha, ply + 1)
					eng:takeback()
					if aborted then return alpha, bestMv end
					if sc > alpha then alpha = sc; bestMv = m end
					if alpha >= beta then break end
				end
				return alpha, bestMv
			end

			local bestUci: string? = nil
			for d = 1, maxDepth do
				aborted = false
				local _, mv = ab(d, -100000, 100000, 0)
				if aborted then break end
				if mv then bestUci = eng:moveToUci(mv) end
			end
			if bestUci then
				local resolved = resolveLegalMove(snap.legalMoves, bestUci)
				if resolved then return resolved end
			end
		end
	else
		local clone = Engine.clone(snap.bv.state)
		local function orderMovesCd(moves: { any }): { any }
			local scored = {}
			for _, m in ipairs(moves) do
				local cap = math.abs(clone.board[m.to] or 0)
				local att = math.abs(clone.board[m.from] or 0)
				local sc = (cap > 0 and (10000 + cap * 100 - att) or 0) + ((m.promo or 0) * 500)
				table.insert(scored, { m = m, s = sc })
			end
			table.sort(scored, function(a, b2) return a.s > b2.s end)
			local out = {}
			for _, e in ipairs(scored) do table.insert(out, e.m) end
			return out
		end

		local function quiesceCd(alpha: number, beta: number, qply: number): number
			if checkBudget() then return alpha end
			local stand = evalStaticBoard64(clone.board, clone.turn)
			if stand >= beta then return beta end
			if stand > alpha then alpha = stand end
			if qply >= 4 then return alpha end

			local caps = {}
			for _, m in ipairs(Engine.legalMoves(clone)) do
				if (clone.board[m.to] or 0) ~= 0 or (m.promo or 0) ~= 0 then
					table.insert(caps, m)
				end
			end
			for _, m in ipairs(orderMovesCd(caps)) do
				local u = Engine.makeMove(clone, m)
				local sc = -quiesceCd(-beta, -alpha, qply + 1)
				Engine.unmakeMove(clone, u)
				if aborted then return alpha end
				if sc >= beta then return beta end
				if sc > alpha then alpha = sc end
			end
			return alpha
		end

		local function abCd(depth: number, alpha: number, beta: number, ply: number): (number, any)
			if checkBudget() then return alpha, nil end
			local moves = Engine.legalMoves(clone)
			if #moves == 0 then
				return Engine.inCheck(clone) and (-90000 + ply) or 0, nil
			end
			if depth <= 0 then
				return quiesceCd(alpha, beta, 0), nil
			end
			local bestMv = nil
			for _, m in ipairs(orderMovesCd(moves)) do
				local u = Engine.makeMove(clone, m)
				local sc = -abCd(depth - 1, -beta, -alpha, ply + 1)
				Engine.unmakeMove(clone, u)
				if aborted then return alpha, bestMv end
				if sc > alpha then alpha = sc; bestMv = m end
				if alpha >= beta then break end
			end
			return alpha, bestMv
		end

		local bestUci: string? = nil
		for d = 1, maxDepth do
			aborted = false
			local _, mv = abCd(d, -100000, 100000, 0)
			if aborted then break end
			if mv then bestUci = Engine.uci(mv) end
		end
		if bestUci then
			local resolved = resolveLegalMove(snap.legalMoves, bestUci)
			if resolved then return resolved end
		end
	end

	return snap.legalMoves[1]
end

local function pickBestTablebaseEntry(rootCat: string?, entries: { any }): any
	local best = entries[1]
	if rootCat == "win" then
		local bestDtm = math.huge
		for _, e in ipairs(entries) do
			if e.category == "loss" then
				local d = math.abs(tonumber(e.dtm) or tonumber(e.dtz) or 9999)
				if d < bestDtm then bestDtm = d; best = e end
			end
		end
	elseif rootCat == "draw" then
		for _, e in ipairs(entries) do
			if e.category == "draw" or e.category == "cursed-win" then best = e; break end
		end
	elseif rootCat == "loss" then
		local maxD = -1
		for _, e in ipairs(entries) do
			local d = math.abs(tonumber(e.dtm) or tonumber(e.dtz) or 0)
			if d > maxD then maxD = d; best = e end
		end
	end
	return best
end

local function queryLichessTablebase(fen: string, legalMoves: { NormMove }): any
	local ok, data = httpRequestJson("https://tablebase.lichess.ovh/standard?fen=" .. HttpService:UrlEncode(fen), "GET", nil, 3.0)
	if not ok or type(data.moves) ~= "table" or #data.moves == 0 then return nil end
	local bestEntry = pickBestTablebaseEntry(data.category, data.moves)
	local mv = resolveLegalMove(legalMoves, bestEntry.uci)
	if not mv then return nil end

	local evalStr = tostring(data.category or "tb")
	local isMate = bestEntry.dtm ~= nil
	if bestEntry.dtm ~= nil then
		evalStr = "M#" .. tostring(math.abs(tonumber(bestEntry.dtm) or 0))
	elseif bestEntry.dtz ~= nil then
		evalStr = string.format("%s (%s)", tostring(data.category or ""), tostring(bestEntry.dtz))
	end
	local secondMv = data.moves[2] and resolveLegalMove(legalMoves, data.moves[2].uci) or nil
	return { move = mv, secondMove = secondMv, evalText = evalStr, source = "Tablebase 7m", depth = 90, isMate = isMate, trusted = true }
end

local function queryLichessCloudEval(fen: string, legalMoves: { NormMove }): any
	local ok, data = httpRequestJson("https://lichess.org/api/cloud-eval?fen=" .. HttpService:UrlEncode(fen) .. "&multiPv=5", "GET", nil, 2.5)
	if not ok or type(data.pvs) ~= "table" or #data.pvs == 0 then return nil end
	local pv1 = data.pvs[1]
	if type(pv1) ~= "table" or type(pv1.moves) ~= "string" then return nil end
	local uci1 = string.match(pv1.moves, "^(%S+)")
	local mv = uci1 and resolveLegalMove(legalMoves, uci1)
	if not mv then return nil end

	local evalStr = "?"
	local isMate = pv1.mate ~= nil
	if pv1.mate ~= nil then
		evalStr = "M#" .. tostring(pv1.mate)
	elseif pv1.cp ~= nil then
		evalStr = formatCpEval(tonumber(pv1.cp) or 0)
	end
	local secondMv = nil
	if data.pvs[2] and type(data.pvs[2].moves) == "string" then
		local uci2 = string.match(data.pvs[2].moves, "^(%S+)")
		if uci2 then secondMv = resolveLegalMove(legalMoves, uci2) end
	end
	local d = tonumber(data.depth) or 20
	return { move = mv, secondMove = secondMv, evalText = evalStr, source = "Lichess d" .. tostring(d), depth = d, isMate = isMate, trusted = true }
end

local function queryMoveLensApi(fen: string, depth: number, legalMoves: { NormMove }, ignoreCooldown: boolean?): any
	if not ignoreCooldown and os.clock() < moveLensCooldownUntil then
		return nil
	end
	local quality = (depth >= 15) and "max" or (depth >= 12 and "deep" or "standard")
	local ok, data, elapsed = httpRequestJson("https://sanjaymarathi-movelens.hf.space/api/analyse", "POST", {
		fen = fen,
		count = 5,
		quality = quality,
	}, 4.0)
	if not ok or type(data.lines) ~= "table" or #data.lines == 0 then
		if elapsed >= 3.8 or tostring(data) == "http 503" or tostring(data) == "http 429" then
			moveLensCooldownUntil = os.clock() + 90
		end
		return nil
	end

	local line1 = data.lines[1]
	if type(line1) ~= "table" or type(line1.uci) ~= "string" then return nil end
	local mv = resolveLegalMove(legalMoves, line1.uci)
	if not mv then return nil end

	local secondMv = nil
	if data.lines[2] and type(data.lines[2].uci) == "string" then
		secondMv = resolveLegalMove(legalMoves, data.lines[2].uci)
	end

	local evTbl = line1.eval or data.eval or {}
	local isMate = evTbl.mate ~= nil
	local evalStr = "?"
	if evTbl.mate ~= nil then
		evalStr = "M#" .. tostring(evTbl.mate)
	elseif type(evTbl.text) == "string" and #evTbl.text > 0 then
		evalStr = evTbl.text
	elseif evTbl.cp ~= nil then
		evalStr = formatCpEval(tonumber(evTbl.cp) or 0)
	end
	local d = tonumber(line1.depth) or 14
	return { move = mv, secondMove = secondMv, evalText = evalStr, source = "MoveLens SF19 d" .. tostring(d), depth = d, isMate = isMate, priority = 2, trusted = true }
end

local function queryStockfishOnline(fen: string, depth: number, legalMoves: { NormMove }): any
	local d = math.clamp(math.floor(depth), 8, 15)
	local ok, data = httpRequestJson("https://stockfish.online/api/s/v2.php?fen=" .. HttpService:UrlEncode(fen) .. "&depth=" .. tostring(d), "GET", nil, 4.0)
	if not ok or data.success ~= true or type(data.bestmove) ~= "string" then return nil end
	local uci = string.match(data.bestmove, "bestmove%s+(%S+)")
	if not uci or uci == "(none)" then return nil end
	local mv = resolveLegalMove(legalMoves, uci)
	if not mv then return nil end

	local isMate = data.mate ~= nil
	local evalStr = "?"
	if data.mate ~= nil then
		evalStr = "M#" .. tostring(data.mate)
	elseif data.evaluation ~= nil then
		local ev = tonumber(data.evaluation)
		evalStr = ev and ((ev >= 0) and string.format("+%.2f", ev) or string.format("%.2f", ev)) or tostring(data.evaluation)
	end
	return { move = mv, evalText = evalStr, source = "Stockfish.online d" .. tostring(d), depth = d, isMate = isMate, priority = 1, trusted = true }
end

local function queryChessDB(fen: string, turn: number, legalMoves: { NormMove }): any
	local ok, data = httpRequestJson("https://www.chessdb.cn/cdb.php?action=queryall&board=" .. HttpService:UrlEncode(fen) .. "&json=1", "GET", nil, 2.5)
	if not ok or data.status ~= "ok" or type(data.moves) ~= "table" or #data.moves == 0 then return nil end

	local top = data.moves[1]
	if type(top) ~= "table" or type(top.uci) ~= "string" then return nil end
	local rank = tonumber(top.rank) or 0
	local note = tostring(top.note or "")
	if rank < 2 and string.sub(note, 1, 1) ~= "!" then
		return nil
	end

	local mv = resolveLegalMove(legalMoves, top.uci)
	if not mv then return nil end

	local secondMv = nil
	local m2 = data.moves[2]
	if type(m2) == "table" and type(m2.uci) == "string" and (tonumber(m2.rank) or 0) >= 1 then
		secondMv = resolveLegalMove(legalMoves, m2.uci)
	end

	local score = tonumber(top.score)
	local evalStr = "?"
	local isMate = false
	if score then
		if math.abs(score) >= 24000 then
			isMate = true
			evalStr = score > 0 and "Win" or "Loss"
		else
			evalStr = formatCpEval(score * turn)
		end
	end
	return { move = mv, secondMove = secondMv, evalText = evalStr, source = "ChessDB !", depth = 25, isMate = isMate, trusted = true }
end

local function queryChessApiCom(fen: string, depth: number, legalMoves: { NormMove }, ignoreCooldown: boolean?): any
	if not ignoreCooldown and os.clock() < chessApiCooldownUntil then
		return nil
	end
	local d = math.clamp(math.floor(depth), 8, 18)

	if wsConnect then
		local t0 = os.clock()
		local okWs, ws = pcall(wsConnect, "wss://chess-api.com/v1")
		if okWs and ws then
			local done = false
			local bestData: any = nil
			local queuedWait = false
			local c1 = ws.OnMessage:Connect(function(msg)
				local dok, tbl = pcall(HttpService.JSONDecode, HttpService, msg)
				if dok and type(tbl) == "table" then
					if tbl.type == "info" and type(tbl.text) == "string" and tbl.text:find("public queue", 1, true) then
						queuedWait = true
					elseif tbl.type == "bestmove" or tbl.move then
						bestData = tbl
						if tbl.type == "bestmove" then done = true end
					end
				end
			end)
			local c2 = ws.OnClose:Connect(function() done = true end)
			pcall(ws.Send, ws, HttpService:JSONEncode({ fen = fen, depth = d, maxThinkingTime = 100, variants = 2 }))

			local wsCap = ignoreCooldown and 5.0 or 2.8
			local deadline = t0 + wsCap
			while not done and alive and os.clock() < deadline do
				if not ignoreCooldown and queuedWait and (os.clock() - t0) > 1.2 then
					break
				end
				task.wait(0.03)
			end
			pcall(function() c1:Disconnect() end)
			pcall(function() c2:Disconnect() end)
			pcall(ws.Close, ws)

			if bestData then
				local uci = (type(bestData.move) == "string" and bestData.move)
					or (type(bestData.from) == "string" and type(bestData.to) == "string" and (bestData.from .. bestData.to .. tostring(bestData.promotion or "")) or nil)
				local mv = uci and resolveLegalMove(legalMoves, uci)
				if mv then
					local evStr = "?"
					local isMate = bestData.mate ~= nil
					if bestData.mate ~= nil then
						evStr = "M#" .. tostring(bestData.mate)
					elseif bestData.eval ~= nil then
						local ev = tonumber(bestData.eval)
						evStr = ev and ((ev >= 0) and string.format("+%.2f", ev) or string.format("%.2f", ev)) or tostring(bestData.eval)
					end
					local rd = tonumber(bestData.depth) or d
					return { move = mv, evalText = evStr, source = "ChessAPI d" .. tostring(rd), depth = rd, isMate = isMate, trusted = true }
				end
			elseif queuedWait and not ignoreCooldown then
				chessApiCooldownUntil = os.clock() + 180
				return nil
			end
		end
	end

	local ok, data, elapsed = httpRequestJson("https://chess-api.com/v1", "POST", {
		fen = fen,
		depth = d,
		maxThinkingTime = 100,
		variants = 2,
	}, ignoreCooldown and 5.5 or 3.5)
	if not ok then
		if elapsed >= 3.2 then
			chessApiCooldownUntil = os.clock() + 180
		end
		return nil
	end
	local uci = (type(data.move) == "string" and data.move)
		or (type(data.from) == "string" and type(data.to) == "string" and (data.from .. data.to .. tostring(data.promotion or "")) or nil)
	local mv = uci and resolveLegalMove(legalMoves, uci)
	if not mv then return nil end

	local isMate = data.mate ~= nil
	local evalStr = "?"
	if data.mate ~= nil then
		evalStr = "M#" .. tostring(data.mate)
	elseif data.eval ~= nil then
		local ev = tonumber(data.eval)
		evalStr = ev and ((ev >= 0) and string.format("+%.2f", ev) or string.format("%.2f", ev)) or tostring(data.eval)
	end
	local rd = tonumber(data.depth) or d
	return { move = mv, evalText = evalStr, source = "ChessAPI d" .. tostring(rd), depth = rd, isMate = isMate, trusted = true }
end

local function queryLichessMasters(fen: string, legalMoves: { NormMove }): any
	local ok, data = httpRequestJson("https://explorer.lichess.ovh/masters?fen=" .. HttpService:UrlEncode(fen) .. "&topGames=0&recentGames=0", "GET", nil, 2.5)
	if not ok or type(data.moves) ~= "table" or #data.moves == 0 then return nil end
	local bestMove = nil
	local bestGames = 0
	for _, m in ipairs(data.moves) do
		local tot = (tonumber(m.white) or 0) + (tonumber(m.draws) or 0) + (tonumber(m.black) or 0)
		if tot >= 25 and tot > bestGames then
			local resolved = resolveLegalMove(legalMoves, m.uci)
			if resolved then
				bestGames = tot
				bestMove = resolved
			end
		end
	end
	return bestMove and { move = bestMove, evalText = "GM (" .. tostring(bestGames) .. ")", source = "Masters Book", depth = 16, trusted = true } or nil
end

local function raceBestEngines(fen: string, depth: number, legalMoves: { NormMove }): any
	local sfRes: any = nil
	local mlRes: any = nil
	local sfDone, mlDone = false, false

	task.spawn(function()
		mlRes = queryMoveLensApi(fen, depth, legalMoves, false)
		mlDone = true
	end)
	task.spawn(function()
		sfRes = queryStockfishOnline(fen, math.min(15, depth), legalMoves)
		sfDone = true
	end)

	local t0 = os.clock()
	local firstAt: number? = nil
	while alive and not (sfDone and mlDone) do
		local now = os.clock()
		if (now - t0) >= 3.8 then break end
		if sfRes or mlRes then
			if not firstAt then firstAt = now end
			if (now - firstAt) >= 0.4 then break end
		end
		task.wait(0.025)
	end

	if mlRes and sfRes then
		if mlRes.isMate and not sfRes.isMate then return mlRes end
		if sfRes.isMate and not mlRes.isMate then return sfRes end
		local mlD = tonumber(mlRes.depth) or 0
		local sfD = tonumber(sfRes.depth) or 0
		if mlD >= sfD then return mlRes end
		return sfRes
	end
	return mlRes or sfRes
end

local function solveBestMoveInternal(snap: StateSnapshot): any
	local legalMoves = snap.legalMoves
	if #legalMoves == 0 then return nil end

	local puzzleRes = tryGetPuzzleSolution(snap)
	if puzzleRes then return puzzleRes end

	local lessonRes = trySolveLesson(snap)
	if lessonRes then return lessonRes end

	if #legalMoves == 1 then
		return { move = legalMoves[1], evalText = "Forced", source = "Instant", depth = 99, fen = snap.fen, trusted = true }
	end

	local pieceCount, wk, bk = countPiecesAndKings64(snap.board64)
	local isStandard = (wk == 1 and bk == 1)

	if isStandard then
		local mateMv = findMateInOne(snap)
		if mateMv then
			return { move = mateMv, evalText = "M#1", source = "Mate Scan", depth = 99, fen = snap.fen, isMate = true, trusted = true }
		end
	end

	local fen = snap.fen
	local provider = CFG.ApiProvider
	local cacheKey = fen and (fen .. "|" .. provider .. "|d" .. tostring(CFG.Depth)) or nil
	if cacheKey and evalCache[cacheKey] then
		local cached = evalCache[cacheKey]
		local verified = resolveLegalMove(legalMoves, cached.move.uci)
		if verified then
			local copy = table.clone(cached)
			copy.move = verified
			if cached.secondMove then
				copy.secondMove = resolveLegalMove(legalMoves, cached.secondMove.uci)
			end
			return copy
		end
	end

	local function finish(res: any)
		res.fen = fen
		if cacheKey then cachePut(cacheKey, res) end
		return res
	end

	if provider ~= "Offline AlphaBeta" and isStandard and fen and httpRequest then
		if pieceCount <= 7 then
			local tb = queryLichessTablebase(fen, legalMoves)
			if tb then return finish(tb) end
		end

		if provider == "MoveLens SF19 (Max)" then
			local ml = queryMoveLensApi(fen, CFG.Depth, legalMoves, true)
			if ml then return finish(ml) end
			local sf = queryStockfishOnline(fen, math.min(15, CFG.Depth), legalMoves)
			if sf then return finish(sf) end
		elseif provider == "Stockfish.online (d15)" then
			for _, d in ipairs({ math.min(15, CFG.Depth), 13, 11 }) do
				local sf = queryStockfishOnline(fen, d, legalMoves)
				if sf then return finish(sf) end
			end
		elseif provider == "ChessDB (Verified !)" then
			local cdb = queryChessDB(fen, snap.turn, legalMoves)
			if cdb then return finish(cdb) end
			local live = raceBestEngines(fen, CFG.Depth, legalMoves)
			if live then return finish(live) end
		elseif provider == "Lichess Cloud (d20+)" then
			local ce = queryLichessCloudEval(fen, legalMoves)
			if ce then return finish(ce) end
			local gm = queryLichessMasters(fen, legalMoves)
			if gm then return finish(gm) end
			local live = raceBestEngines(fen, CFG.Depth, legalMoves)
			if live then return finish(live) end
		elseif provider == "Chess-API (d18)" then
			local ca = queryChessApiCom(fen, CFG.Depth, legalMoves, true)
			if ca then return finish(ca) end
			local live = raceBestEngines(fen, CFG.Depth, legalMoves)
			if live then return finish(live) end
		else
			local ceRes: any = nil
			local cdbRes: any = nil
			local ceDone, cdbDone = false, false

			task.spawn(function()
				ceRes = queryLichessCloudEval(fen, legalMoves)
				ceDone = true
			end)
			task.spawn(function()
				cdbRes = queryChessDB(fen, snap.turn, legalMoves)
				cdbDone = true
			end)

			local t0 = os.clock()
			while alive and not (ceDone and cdbDone) do
				if ceRes then break end
				if (os.clock() - t0) >= 2.2 then break end
				task.wait(0.025)
			end
			if ceRes then return finish(ceRes) end
			if cdbRes then return finish(cdbRes) end

			local live = raceBestEngines(fen, CFG.Depth, legalMoves)
			if live then return finish(live) end

			local sfRetry = queryStockfishOnline(fen, math.min(12, CFG.Depth), legalMoves)
			if sfRetry then return finish(sfRetry) end

			local gm = queryLichessMasters(fen, legalMoves)
			if gm then return finish(gm) end

			local ca = queryChessApiCom(fen, CFG.Depth, legalMoves, false)
			if ca then return finish(ca) end
		end
	end

	local abMove = localAlphaBetaFallback(snap, 4, 0.45)
	return { move = abMove, evalText = "Offline", source = "AlphaBeta", depth = 4, fen = fen, trusted = false }
end

local function solveBestMove(snap: StateSnapshot): any
	local fen = snap.fen
	local dedupKey = fen and (fen .. "|" .. CFG.ApiProvider .. "|" .. tostring(CFG.Depth)) or nil
	if dedupKey and pendingByFen[dedupKey] then
		local entry = pendingByFen[dedupKey]
		while alive and not entry.done do task.wait(0.03) end
		if entry.result and entry.result.move then
			local verified = resolveLegalMove(snap.legalMoves, entry.result.move.uci)
			if verified then
				local copy = table.clone(entry.result)
				copy.move = verified
				return copy
			end
		end
	end

	local entry = { done = false, result = nil }
	if dedupKey then pendingByFen[dedupKey] = entry end
	local ok, res = pcall(solveBestMoveInternal, snap)
	entry.result = ok and res or nil
	entry.done = true
	if dedupKey and pendingByFen[dedupKey] == entry then pendingByFen[dedupKey] = nil end
	return entry.result
end

local function findBoardFrame(): GuiObject?
	if BoardViewInstance and typeof(BoardViewInstance.frame) == "Instance" and BoardViewInstance.frame.Parent then
		return BoardViewInstance.frame
	end
	local pg = lp:FindFirstChild("PlayerGui")
	if not pg then return nil end
	for _, desc in ipairs(pg:GetDescendants()) do
		if desc.Name == "Board" and desc:IsA("GuiObject") and desc.Visible then return desc end
	end
	return nil
end

local function squareToCellCoords(sq: number, flipped: boolean): (number, number)
	local f = (sq - 1) % 8
	local r = (sq - 1) // 8
	return flipped and (7 - f) or f, flipped and r or (7 - r)
end

local function clearHint()
	currentHintResult = nil
	inFlightHintFen = nil
	requestSeq += 1
	if hintResizeConn then hintResizeConn:Disconnect(); hintResizeConn = nil end
	if hintGui then hintGui:Destroy(); hintGui = nil end
end

local function drawArrowSegment(parent: Instance, p1: Vector2, p2: Vector2, thickness: number, color: Color3, transparency: number, zIndex: number)
	local diff = p2 - p1
	local len = diff.Magnitude
	if len < 1 then return end
	local mid = (p1 + p2) / 2
	local line = Instance.new("Frame")
	line.Name = "ArrowSeg"
	line.BorderSizePixel = 0
	line.BackgroundColor3 = color
	line.BackgroundTransparency = transparency
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromOffset(mid.X, mid.Y)
	line.Size = UDim2.fromOffset(len + thickness * 0.4, thickness)
	line.Rotation = math.deg(math.atan2(diff.Y, diff.X))
	line.ZIndex = zIndex
	line.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = line
end

local function drawPixelArrow(parent: Instance, boardSize: Vector2, fromSq: number, toSq: number, flipped: boolean, color: Color3, transparency: number, scaleFactor: number, zIndex: number)
	local cellW, cellH = boardSize.X / 8, boardSize.Y / 8
	local cellMin = math.min(cellW, cellH)
	local fx1, fy1 = squareToCellCoords(fromSq, flipped)
	local fx2, fy2 = squareToCellCoords(toSq, flipped)
	local pFrom = Vector2.new((fx1 + 0.5) * cellW, (fy1 + 0.5) * cellH)
	local pTo = Vector2.new((fx2 + 0.5) * cellW, (fy2 + 0.5) * cellH)
	if (pTo - pFrom).Magnitude < 1 then return end

	local df = math.abs((fromSq - 1) % 8 - (toSq - 1) % 8)
	local dr = math.abs((fromSq - 1) // 8 - (toSq - 1) // 8)
	local isKnight = (df == 1 and dr == 2) or (df == 2 and dr == 1)

	local thickness = math.max(4, math.round(cellMin * 0.11 * scaleFactor))
	local tipBack = cellMin * 0.18
	local startOffset = cellMin * 0.16
	local headLen = cellMin * 0.34 * scaleFactor
	local lastDir: Vector2
	local tipPoint: Vector2

	if isKnight then
		local delta = pTo - pFrom
		local elbow = math.abs(delta.X) > math.abs(delta.Y) and Vector2.new(pTo.X, pFrom.Y) or Vector2.new(pFrom.X, pTo.Y)
		local dir1 = (elbow - pFrom).Unit
		local dir2 = (pTo - elbow).Unit
		lastDir = dir2
		tipPoint = pTo - dir2 * tipBack
		drawArrowSegment(parent, pFrom + dir1 * startOffset, elbow, thickness, color, transparency, zIndex)
		drawArrowSegment(parent, elbow, tipPoint, thickness, color, transparency, zIndex)
	else
		local dir = (pTo - pFrom).Unit
		lastDir = dir
		tipPoint = pTo - dir * tipBack
		drawArrowSegment(parent, pFrom + dir * startOffset, tipPoint, thickness, color, transparency, zIndex)
	end

	local wingAngle = math.rad(38)
	for _, sign in ipairs({ 1, -1 }) do
		local a = wingAngle * sign
		local cosA, sinA = math.cos(a), math.sin(a)
		local rot = Vector2.new(lastDir.X * cosA - lastDir.Y * sinA, lastDir.X * sinA + lastDir.Y * cosA)
		drawArrowSegment(parent, tipPoint, tipPoint - rot * headLen, thickness, color, transparency, zIndex + 1)
	end
end

local function createSquareHighlight(parent: Instance, sq: number, flipped: boolean, fillColor: Color3, fillTrans: number, strokeColor: Color3, badgeText: string?, zIndex: number)
	local fx, fy = squareToCellCoords(sq, flipped)
	local box = Instance.new("Frame")
	box.Name = "HintSquare_" .. tostring(sq)
	box.BackgroundColor3 = fillColor
	box.BackgroundTransparency = fillTrans
	box.BorderSizePixel = 0
	box.Position = UDim2.fromScale(fx / 8, fy / 8)
	box.Size = UDim2.fromScale(0.125, 0.125)
	box.ZIndex = zIndex
	box.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.12, 0)
	corner.Parent = box

	local stroke = Instance.new("UIStroke")
	stroke.Color = strokeColor
	stroke.Thickness = 2.5
	stroke.Transparency = 0.15
	stroke.Parent = box

	if badgeText and #badgeText > 0 then
		local lbl = Instance.new("TextLabel")
		lbl.Name = "Badge"
		lbl.BackgroundColor3 = strokeColor
		lbl.BackgroundTransparency = 0.18
		lbl.BorderSizePixel = 0
		lbl.AnchorPoint = Vector2.new(1, 0)
		lbl.Position = UDim2.fromScale(0.96, 0.04)
		lbl.Size = UDim2.fromScale(0.52, 0.20)
		lbl.Font = Enum.Font.GothamBold
		lbl.Text = badgeText
		lbl.TextColor3 = Color3.fromRGB(15, 20, 28)
		lbl.TextScaled = true
		lbl.ZIndex = zIndex + 2
		lbl.Parent = box
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0.3, 0)
		bc.Parent = lbl
	end
end

local function drawHint(result: any, snap: StateSnapshot?): boolean
	if not result or not result.move or not isMyTurn() then return false end
	if hintResizeConn then hintResizeConn:Disconnect(); hintResizeConn = nil end
	if hintGui then hintGui:Destroy(); hintGui = nil end

	local curSnap = snap or getStateSnapshot()
	local frame = findBoardFrame()
	if not curSnap or not frame or not isGuiActuallyVisible(frame) then return false end

	local bv = curSnap.bv
	local flipped = bv and (bv.flipped == true) or (curSnap.turn == -1)
	local absSize = frame.AbsoluteSize
	if absSize.X < 40 or absSize.Y < 40 then absSize = Vector2.new(480, 480) end

	local container = Instance.new("Frame")
	container.Name = "SonChessHint"
	container.BackgroundTransparency = 1
	container.Size = UDim2.fromScale(1, 1)
	container.ZIndex = 45
	container.Parent = frame
	hintGui = container
	currentHintResult = result

	local mv: NormMove = result.move
	local pieceId = math.abs(curSnap.board64[mv.from64] or 0)
	local fromBadge = (PIECE_CODES[pieceId] or "?") .. " " .. sq64ToAlg(mv.from64)
	local promoTag = (mv.promo ~= 0) and ("=" .. (ID_TO_PROMO[mv.promo] or "Q")) or ""
	local isCapture = (curSnap.board64[mv.to64] or 0) ~= 0
	local toBadge = (isCapture and "x " or "> ") .. sq64ToAlg(mv.to64) .. promoTag

	createSquareHighlight(container, mv.from64, flipped, CFG.FromColor, 0.72, CFG.FromColor, fromBadge, 46)
	createSquareHighlight(container, mv.to64, flipped, CFG.ToColor, 0.66, CFG.ToColor, toBadge, 46)

	if CFG.ShowTop2Arrow and result.secondMove and result.secondMove.from64 and result.secondMove.to64 then
		drawPixelArrow(container, absSize, result.secondMove.from64, result.secondMove.to64, flipped, CFG.Top2Color, 0.55, 0.72, 47)
	end

	local mainColor = (result.trusted == false) and Color3.fromRGB(239, 68, 68) or CFG.HintColor
	drawPixelArrow(container, absSize, mv.from64, mv.to64, flipped, mainColor, 0.16, 1.0, 49)

	hintResizeConn = frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if alive and CFG.HintEnabled and currentHintResult == result and isMyTurn() then
			task.defer(drawHint, result)
		end
	end)
	return true
end

local function updatePara(para: any, content: string)
	if not para or type(para.SetContent) ~= "function" then return end
	if paraCache[para] == content then return end
	paraCache[para] = content
	elevateIdentity()
	pcall(para.SetContent, para, content)
end

local function safeNotify(opts: { Title: string, Content: string, Duration: number?, Type: string? })
	if not Window or type(Window.Notify) ~= "function" then return end
	elevateIdentity()
	pcall(Window.Notify, Window, opts)
end

local function clickUiButton(root: Instance?, textMatch: { string }): boolean
	if typeof(root) ~= "Instance" then return false end
	for _, obj in ipairs(root:GetDescendants()) do
		if (obj:IsA("TextButton") or obj:IsA("TextLabel")) and isGuiActuallyVisible(obj) then
			for _, targetText in ipairs(textMatch) do
				if obj.Text == targetText then
					local btn: Instance? = obj:IsA("TextButton") and obj or obj.Parent
					while btn and not btn:IsA("GuiButton") do btn = btn.Parent end
					if btn and btn:IsA("GuiButton") and type(fireSignalFn) == "function" then
						pcall(fireSignalFn, btn.Activated)
						pcall(fireSignalFn, btn.MouseButton1Click)
						return true
					end
				end
			end
		end
	end
	return false
end

local function claimRoChessTasks()
	if not IS_ROCHESS or not App or not App.pages or not App.pages.tasks then return 0 end
	local tasksPage = App.pages.tasks
	if type(tasksPage.claim) ~= "function" then return 0 end
	local t = App.tasks or (App.profile and App.profile.tasks)
	if type(t) ~= "table" then return 0 end
	local claimed = 0
	local pMap, cMap, gMap = t.p or {}, t.c or {}, t.g or {}
	for _, def in ipairs(RoConfig.DAILY_TASKS or {}) do
		local goal = tonumber(gMap[def.id]) or def.goal or 1
		if (tonumber(pMap[def.id]) or 0) >= goal and not cMap[def.id] then
			pcall(tasksPage.claim, def.id)
			claimed += 1
		end
	end
	local w = t.w
	if type(w) == "table" and not w.c and (tonumber(w.p) or 0) >= (tonumber(w.goal) or 1e9) then
		pcall(tasksPage.claim, w.id)
		claimed += 1
	end
	return claimed
end

local function refreshGoalsUI()
	if not QuestGoalsPara then return end
	scanControllers(false)

	if IS_ROCHESS then
		local p = App and App.profile
		if not p then updatePara(QuestGoalsPara, "Loading profile..."); return end
		local r = p.ratings or {}
		local t = App.tasks or p.tasks or {}
		local lines = {
			string.format(
				"B:%d Z:%d R:%d | Puz:%d | Tokens:%d",
				r.bullet and r.bullet.r or 800, r.blitz and r.blitz.r or 800,
				r.rapid and r.rapid.r or 800, p.puzzle and p.puzzle.r or 400, tonumber(t.tokens) or 0
			),
		}
		local pMap, cMap, gMap = t.p or {}, t.c or {}, t.g or {}
		for _, def in ipairs(RoConfig.DAILY_TASKS or {}) do
			local goal = tonumber(gMap[def.id]) or def.goal or 1
			local prog = math.min(tonumber(pMap[def.id]) or 0, goal)
			local tag = cMap[def.id] and "[DONE]" or string.format("[%d/%d]", prog, goal)
			table.insert(lines, string.format("%s %s", tag, string.format(def.fmt or def.label, goal)))
		end
		if type(t.w) == "table" then
			local w = t.w
			local wGoal = tonumber(w.goal) or 1
			local wProg = math.min(tonumber(w.p) or 0, wGoal)
			local wTag = w.c and "[DONE]" or string.format("[%d/%d]", wProg, wGoal)
			table.insert(lines, string.format("%s Weekly: %s", wTag, tostring(w.label or w.id)))
		end
		updatePara(QuestGoalsPara, table.concat(lines, "\n"))
		return
	end

	local p = GameCtx and GameCtx.profile
	local prog = p and p.progress
	if not p or not prog then updatePara(QuestGoalsPara, "Loading profile..."); return end
	local r = p.ratings or {}
	local lines = {
		string.format(
			"Lv.%d (%d/%d XP) | Coins %d\nB:%d Z:%d R:%d | Puz:%d",
			tonumber(prog.level) or 1,
			tonumber(prog.levelXp) or 0,
			tonumber(prog.levelNeed) or 100,
			tonumber(prog.coins) or 0,
			r.bullet and r.bullet.rating or 400, r.blitz and r.blitz.rating or 400,
			r.rapid and r.rapid.rating or 400, tonumber(p.puzzle) or 400
		),
	}
	for _, g in ipairs(prog.goals or {}) do
		local meta = CdProgression.goal(g.id)
		local label = meta and meta.text or g.id
		local target = meta and meta.target or "?"
		local tag = g.done and "[DONE]" or string.format("[%s/%s]", tostring(g.progress or 0), tostring(target))
		table.insert(lines, string.format("%s %s", tag, label))
	end
	updatePara(QuestGoalsPara, table.concat(lines, "\n"))
end

local function triggerHintAsync(force: boolean?)
	elevateIdentity()
	if not isMyTurn() then
		clearHint()
		if force then
			safeNotify({ Title = "Hint", Content = "Not your turn.", Duration = 2, Type = "Warning" })
		else
			updatePara(HintStatusPara, "Opponent turn...")
		end
		return
	end

	local snap = getStateSnapshot()
	if not snap or #snap.legalMoves == 0 then
		if force then updatePara(HintStatusPara, "No legal moves.") end
		return
	end

	local fen = snap.fen
	if not force and fen and (fen == lastHintFen or fen == inFlightHintFen) then return end

	requestSeq += 1
	local mySeq = requestSeq
	inFlightHintFen = fen
	updatePara(HintStatusPara, "Analyzing (" .. CFG.ApiProvider .. ")...")

	task.spawn(function()
		elevateIdentity()
		local res = solveBestMove(snap)
		if inFlightHintFen == fen then inFlightHintFen = nil end
		if not alive or mySeq ~= requestSeq or not res or not res.move then return end
		if not isMyTurn() then
			clearHint()
			updatePara(HintStatusPara, "Opponent turn...")
			return
		end

		local nowSnap = getStateSnapshot()
		if not nowSnap or nowSnap.turn ~= snap.turn or (fen and nowSnap.fen ~= fen) then return end

		lastHintFen = fen
		local label = formatMoveLabel(nowSnap, res.move)
		updatePara(HintStatusPara, string.format("%s | %s (%s)", label, tostring(res.evalText or "?"), tostring(res.source or "?")))

		if CFG.HintEnabled then drawHint(res, nowSnap) end
		if force or CFG.NotifyHints then
			safeNotify({
				Title = "Best Move",
				Content = label .. " | " .. tostring(res.evalText) .. " (" .. tostring(res.source) .. ")",
				Duration = 2.5,
				Type = res.trusted == false and "Warning" or "Info",
			})
		end
	end)
end

local autoRunning = false

local function stepAutoPlay()
	if not CFG.AutoPlayEnabled or not alive then return end
	if not isMyTurn() then
		if hintGui then clearHint() end
		return
	end

	local snap = getStateSnapshot()
	if not snap or #snap.legalMoves == 0 then return end

	local fen = snap.fen
	if fen and (fen == lastAutoFen or fen == inFlightAutoFen) then return end

	inFlightAutoFen = fen
	updatePara(HintStatusPara, "Thinking (" .. CFG.ApiProvider .. ")...")

	local res = solveBestMove(snap)

	if res and res.trusted == false and CFG.StrictEngine and CFG.ApiProvider ~= "Offline AlphaBeta" and httpRequest and isMyTurn() then
		local mode = getCurrentMode()
		if mode == "game" or mode == "online" or mode == "bot" then
			for _, waitRetry in ipairs({ 0.4, 0.7 }) do
				if not alive or not CFG.AutoPlayEnabled or not isMyTurn() then break end
				updatePara(HintStatusPara, "Retrying Engine API...")
				task.wait(waitRetry)
				local retrySnap = isMyTurn() and getStateSnapshot() or nil
				if retrySnap and retrySnap.fen == fen and retrySnap.turn == snap.turn then
					local retry = solveBestMove(retrySnap)
					if retry and retry.trusted then
						res = retry
						break
					end
				else
					break
				end
			end
		end
	end

	if inFlightAutoFen == fen then inFlightAutoFen = nil end
	if not alive or not CFG.AutoPlayEnabled or not isMyTurn() or not res or not res.move then return end

	if CFG.HintEnabled then drawHint(res, snap) end
	local label = formatMoveLabel(snap, res.move)
	updatePara(HintStatusPara, string.format("%s | %s (%s)", label, tostring(res.evalText or "?"), tostring(res.source or "?")))

	local modeNow = getCurrentMode()
	local waitSec = (modeNow == "puzzle" or modeNow == "rush") and CFG.PuzzleDelay or CFG.MoveDelay
	if (modeNow == "game" or modeNow == "online" or modeNow == "bot") and CFG.HumanJitter > 0 then
		waitSec += math.random() * CFG.HumanJitter
	end
	if waitSec > 0 then task.wait(waitSec) end

	if not alive or not CFG.AutoPlayEnabled or not isMyTurn() then return end
	local nowSnap = getStateSnapshot()
	if not nowSnap or nowSnap.turn ~= snap.turn or (fen and nowSnap.fen ~= fen) then return end

	local verified = resolveLegalMove(nowSnap.legalMoves, res.move.uci)
	if not verified then return end

	lastAutoFen = fen
	lastHintFen = fen
	executeMoveOnBoard(nowSnap, verified)
end

local function startAuto()
	if autoRunning then return end
	autoRunning = true
	task.spawn(function()
		elevateIdentity()
		while alive and CFG.AutoPlayEnabled do
			local ok, err = pcall(stepAutoPlay)
			if not ok then updatePara(HintStatusPara, "Err: " .. tostring(err)) end
			task.wait(0.18)
		end
		autoRunning = false
	end)
end

local function ensureAutoPlay(state: boolean)
	if CFG.AutoPlayEnabled == state then return end
	if AutoPlayToggleCtrl and type(AutoPlayToggleCtrl.Set) == "function" then
		elevateIdentity()
		pcall(AutoPlayToggleCtrl.Set, AutoPlayToggleCtrl, state)
	else
		CFG.AutoPlayEnabled = state
		if state then startAuto() end
	end
end

local function getCdGoalRemaining(goalId: string): number
	local gList = GameCtx and GameCtx.profile and GameCtx.profile.progress and GameCtx.profile.progress.goals or {}
	for _, g in ipairs(gList) do
		if g.id == goalId then
			if g.done then return 0 end
			local meta = CdProgression and CdProgression.goal(goalId)
			local target = meta and meta.target or 1
			return math.max(1, target - (tonumber(g.progress) or 0))
		end
	end
	return 0
end

local function isNamedGuiVisible(root: Instance?, nameSet: { [string]: boolean }): boolean
	if typeof(root) ~= "Instance" then return false end
	for _, obj in ipairs(root:GetDescendants()) do
		if nameSet[obj.Name] and obj:IsA("GuiObject") and isGuiActuallyVisible(obj) then
			return true
		end
	end
	return false
end

local function runAutoPuzzle(mode: string, targetCount: number, questGoalId: string?)
	if CFG.AutoPuzzleRunning then return end
	CFG.AutoPuzzleRunning = true
	puzzlesSolvedInSession = 0

	task.spawn(function()
		elevateIdentity()
		scanControllers(true)

		if IS_ROCHESS then
			if mode == "rush" and getCurrentMode() ~= "rush" then
				pcall(App.openRush); task.wait(0.8)
			elseif mode ~= "rush" and getCurrentMode() ~= "puzzle" then
				pcall(App.openPuzzles); task.wait(0.8)
			end

			local lastSolvedKey: any = nil
			while alive and CFG.AutoPuzzleRunning do
				local curMode = getCurrentMode()
				if curMode == "puzzle" or curMode == "rush" then
					local s = App.session
					local pz = s and s.pz
					if isMyTurn() then
						local snap = getStateSnapshot()
						if snap then
							local res = tryGetPuzzleSolution(snap) or solveBestMove(snap)
							if res and res.move and isMyTurn() then
								local nowSnap = getStateSnapshot()
								local mv = nowSnap and resolveLegalMove(nowSnap.legalMoves, res.move.uci)
								if mv and nowSnap then
									if CFG.HintEnabled then drawHint(res, nowSnap) end
									executeMoveOnBoard(nowSnap, mv)
									updatePara(QuestStatusPara, string.format("Puzzle (%s): %d solved", mode, puzzlesSolvedInSession))
									task.wait(math.max(0.2, CFG.PuzzleDelay))
								end
							end
						end
					elseif s and s.over and pz then
						local pKey = (pz.data and pz.data.id) or pz.fen or tostring(s.id)
						if lastSolvedKey ~= pKey then
							lastSolvedKey = pKey
							puzzlesSolvedInSession += 1
							refreshGoalsUI()
						end
						if targetCount > 0 and puzzlesSolvedInSession >= targetCount then
							updatePara(QuestStatusPara, string.format("Puzzle done (%d/%d).", puzzlesSolvedInSession, targetCount))
							break
						end
						task.wait(0.45)
						local pageFrame = (curMode == "rush") and (App.pages.rush and App.pages.rush.frame) or (App.pages.puzzles and App.pages.puzzles.frame)
						clickUiButton(pageFrame, { "Next", "Play Again", "Start" })
						task.wait(0.7)
					end
				else
					if mode == "rush" then pcall(App.openRush) else pcall(App.openPuzzles) end
					task.wait(0.8)
				end
				task.wait(0.18)
			end
		else
			if not GameCtx or not PuzzleViewInst then
				CFG.AutoPuzzleRunning = false
				return
			end
			if getCurrentMode() ~= "puzzle" then
				pcall(GameCtx.startPuzzles, mode); task.wait(0.9)
			end
			local lastSolvedId: any = nil
			while alive and CFG.AutoPuzzleRunning do
				scanControllers(false)
				if questGoalId and getCdGoalRemaining(questGoalId) <= 0 then
					updatePara(QuestStatusPara, "Puzzle goal completed.")
					pcall(PuzzleViewInst.exit)
					break
				end
				if getCurrentMode() ~= "puzzle" then
					if mode == "daily" and puzzlesSolvedInSession >= 1 then break end
					pcall(GameCtx.startPuzzles, mode); task.wait(0.8)
				else
					local rushScore: number? = nil
					if mode == "rush" and type(PuzzleViewInst.endRush) == "function" and type(getUpvaluesFn) == "function" then
						local rOk, rUps = pcall(getUpvaluesFn, PuzzleViewInst.endRush)
						if rOk and type(rUps) == "table" then
							for _, v in pairs(rUps) do
								if type(v) == "table" and type(v.score) == "number" and type(v.lives) == "number" then
									rushScore = v.score; break
								end
							end
						end
					end
					if mode == "rush" and rushScore and targetCount > 0 and rushScore >= targetCount then
						puzzlesSolvedInSession = rushScore
						updatePara(QuestStatusPara, string.format("Rush target reached (%d/%d), submitting...", rushScore, targetCount))
						task.wait(0.25)
						pcall(PuzzleViewInst.endRush)
						task.wait(0.9)
						pcall(PuzzleViewInst.exit)
						refreshGoalsUI()
						break
					end
					if isMyTurn() then
						local snap = getStateSnapshot()
						if snap then
							local res = tryGetPuzzleSolution(snap) or solveBestMove(snap)
							if res and res.move and isMyTurn() then
								local nowSnap = getStateSnapshot()
								local mv = nowSnap and resolveLegalMove(nowSnap.legalMoves, res.move.uci)
								if mv and nowSnap then
									if CFG.HintEnabled then drawHint(res, nowSnap) end
									executeMoveOnBoard(nowSnap, mv)
									local shownCount = (mode == "rush" and rushScore) or puzzlesSolvedInSession
									updatePara(QuestStatusPara, string.format("Puzzle (%s): %d solved", mode, shownCount))
									task.wait(math.max(0.2, CFG.PuzzleDelay))
								end
							end
						end
					elseif BoardViewInstance and type(BoardViewInstance.legal) == "table" and #BoardViewInstance.legal == 0 then
						local frame = PuzzleViewInst.frame
						local nextReady = isNamedGuiVisible(frame, { Next = true })
						if not nextReady and typeof(frame) == "Instance" then
							for _, obj in ipairs(frame:GetDescendants()) do
								if (obj:IsA("TextButton") or obj:IsA("TextLabel"))
									and (obj.Text == "Next Puzzle" or obj.Text == "Back" or obj.Text == "Play Again")
									and isGuiActuallyVisible(obj)
								then
									nextReady = true; break
								end
							end
						end
						if nextReady then
							local pObj = getCdPuzzleState()
							local pId = (pObj and pObj.id) or (currentHintResult and currentHintResult.fen) or os.clock()
							if mode == "rush" then
								updatePara(QuestStatusPara, "Rush ended early, retrying...")
								task.wait(0.6)
								pcall(PuzzleViewInst.next)
								task.wait(0.7)
							else
								if lastSolvedId ~= pId then
									lastSolvedId = pId
									puzzlesSolvedInSession += 1
									refreshGoalsUI()
								end
								if mode == "daily" then
									task.wait(0.85)
									pcall(PuzzleViewInst.exit)
									refreshGoalsUI()
									break
								elseif targetCount > 0 and puzzlesSolvedInSession >= targetCount then
									task.wait(0.6)
									pcall(PuzzleViewInst.exit)
									refreshGoalsUI()
									break
								else
									task.wait(0.4)
									pcall(PuzzleViewInst.next)
									task.wait(0.65)
								end
							end
						end
					end
				end
				task.wait(0.18)
			end
		end

		CFG.AutoPuzzleRunning = false
	end)
end

local function runAutoLessonOnce(): boolean
	if IS_ROCHESS or CFG.AutoLessonRunning then return false end
	CFG.AutoLessonRunning = true
	updatePara(QuestStatusPara, "Completing 1 lesson...")
	scanControllers(true)
	if not GameCtx then CFG.AutoLessonRunning = false; return false end

	local targetIdx = 1
	local doneMap = GameCtx.profile and GameCtx.profile.lessons or {}
	for idx, lesson in ipairs(CdLessons) do
		if not doneMap[lesson.id] then targetIdx = idx; break end
	end
	local targetId = CdLessons[targetIdx] and CdLessons[targetIdx].id or nil
	local wasDone = targetId and doneMap[targetId] == true or false

	pcall(GameCtx.startLesson, targetIdx)
	task.wait(0.85)

	local idleTicks = 0
	local completed = false
	while alive and CFG.AutoLessonRunning do
		scanControllers(false)
		if getCurrentMode() ~= "lesson" then break end
		if isMyTurn() then
			idleTicks = 0
			local snap = getStateSnapshot()
			if snap then
				local res = trySolveLesson(snap) or solveBestMove(snap)
				if res and res.move then
					local nowSnap = getStateSnapshot()
					local mv = nowSnap and resolveLegalMove(nowSnap.legalMoves, res.move.uci)
					if mv and nowSnap then
						if CFG.HintEnabled then drawHint(res, nowSnap) end
						executeMoveOnBoard(nowSnap, mv)
						task.wait(0.32)
					end
				end
			end
		else
			local frame = LessonViewInst and LessonViewInst.frame
			local finished = isNamedGuiVisible(frame, { NextLesson = true })
			if not finished and targetId and not wasDone and GameCtx.profile and GameCtx.profile.lessons and GameCtx.profile.lessons[targetId] then
				finished = true
			end
			if not finished and typeof(frame) == "Instance" then
				for _, obj in ipairs(frame:GetDescendants()) do
					if obj:IsA("TextLabel") and obj.Text:find("Lesson complete!") and isGuiActuallyVisible(obj) then
						finished = true; break
					end
				end
			end
			if finished then
				completed = true
				updatePara(QuestStatusPara, "Lesson completed, syncing...")
				task.wait(0.95)
				pcall(GameCtx.setMode, "home", "play")
				break
			end
			idleTicks += 1
			if idleTicks > 45 then
				pcall(GameCtx.setMode, "home", "play")
				break
			end
		end
		task.wait(0.2)
	end

	CFG.AutoLessonRunning = false
	refreshGoalsUI()
	return completed
end

local lastQueueTick = 0
local queueSinceAt = 0

local function isCdQueueBanned(): (boolean, number)
	if IS_ROCHESS or not GameCtx or type(GameCtx.profile) ~= "table" then return false, 0 end
	local ban = tonumber(GameCtx.profile.queueBan) or 0
	if ban > 0 then
		return true, math.ceil(ban)
	end
	return false, 0
end

local function ensureCdHomeForSwitch()
	if IS_ROCHESS or not GameCtx then return end
	local mode = getCurrentMode()
	if mode == "home" then return end
	if mode == "puzzle" and PuzzleViewInst and type(PuzzleViewInst.exit) == "function" then
		pcall(PuzzleViewInst.exit)
		task.wait(0.4)
	elseif mode == "queue" then
		CdAction:FireServer("cancelQueue")
		pcall(GameCtx.setMode, "home", "play")
		task.wait(0.4)
	elseif mode == "lesson" or mode == "practice" then
		pcall(GameCtx.setMode, "home", "play")
		task.wait(0.4)
	elseif mode == "game" then
		local curGame = GameViewInst and type(GameViewInst.current) == "function" and GameViewInst.current() or nil
		if not curGame or curGame.over or curGame.past or curGame.you == 0 then
			CdAction:FireServer("lobby")
			pcall(GameCtx.setMode, "home", "play")
			task.wait(0.5)
		end
	end
end

local function startMatchTarget(target: string)
	if os.clock() - lastQueueTick < 2.4 then return end
	lastQueueTick = os.clock()
	scanControllers(false)

	if IS_ROCHESS then
		if not App then return end
		if string.sub(target, 1, 4) == "bot:" then
			pcall(App.startBotGame, string.sub(target, 5), "white")
		elseif not App.searching and not App.joining then
			pcall(App.startSearch, target)
		end
		return
	end

	if not GameCtx then return end
	if string.sub(target, 1, 4) == "bot:" then
		local lvl = string.sub(target, 5)
		local botInfo = CdBot and CdBot.LEVELS and CdBot.LEVELS[lvl]
		if botInfo and botInfo.vip and not (GameCtx.profile and GameCtx.profile.vip) then
			lvl = "pip"
		end
		CdAction:FireServer("playBot", { level = lvl, tc = "blitz", color = 0 })
	else
		if getCurrentMode() == "game" then
			CdAction:FireServer("lobby")
			pcall(GameCtx.setMode, "home", "play")
			task.wait(0.45)
		end
		queueSinceAt = os.clock()
		CdAction:FireServer("queue", { tc = target })
	end
end

local function stepAutoMatchWithTarget(target: string)
	scanControllers(false)
	if IS_ROCHESS then
		local s = App and App.session
		local isBot = string.sub(target, 1, 4) == "bot:"
		if App and App.searching then
			updatePara(QuestStatusPara, "Searching (" .. target .. ")...")
			task.wait(1.0)
		elseif not s or s.kind == "idle" or s.over then
			if s and s.over then
				claimRoChessTasks()
				refreshGoalsUI()
				task.wait(CFG.MatchDelay)
			end
			if alive and (CFG.AutoMatchRunning or CFG.AutoQuestRunning) then
				updatePara(QuestStatusPara, "Starting: " .. target)
				startMatchTarget(target)
				task.wait(isBot and 1.0 or 2.0)
			end
		else
			updatePara(QuestStatusPara, "Playing: " .. target)
		end
		return
	end

	local mode = getCurrentMode()
	if mode == "puzzle" or mode == "lesson" or mode == "practice" then
		ensureCdHomeForSwitch()
		mode = getCurrentMode()
	end

	if mode == "home" then
		queueSinceAt = 0
		if string.sub(target, 1, 4) ~= "bot:" then
			local banned, banSec = isCdQueueBanned()
			if banned then
				updatePara(QuestStatusPara, string.format("Queue timeout (%ds)...", banSec))
				task.wait(1.5)
				return
			end
		end
		updatePara(QuestStatusPara, "Starting: " .. target)
		startMatchTarget(target)
		task.wait(string.sub(target, 1, 4) == "bot:" and 1.2 or 2.2)
	elseif mode == "queue" then
		if queueSinceAt == 0 then queueSinceAt = os.clock() end
		local elapsed = math.floor(os.clock() - queueSinceAt)
		updatePara(QuestStatusPara, string.format("Searching %s (%ds)...", target, elapsed))
		task.wait(1.0)
	elseif mode == "game" then
		queueSinceAt = 0
		local curGame = GameViewInst and type(GameViewInst.current) == "function" and GameViewInst.current() or nil
		if curGame and (curGame.over or curGame.past or curGame.you == 0) then
			refreshGoalsUI()
			task.wait(CFG.MatchDelay)
			if alive and (CFG.AutoMatchRunning or CFG.AutoQuestRunning) then
				updatePara(QuestStatusPara, "Next match: " .. target)
				startMatchTarget(target)
				task.wait(string.sub(target, 1, 4) == "bot:" and 1.2 or 2.2)
			end
		else
			updatePara(QuestStatusPara, "Playing: " .. target)
		end
	end
end

local function stopAllAutomation()
	CFG.AutoQuestRunning = false
	CFG.QuickFarmRunning = false
	CFG.AutoPuzzleRunning = false
	CFG.AutoMatchRunning = false
	CFG.AutoLessonRunning = false
	if AutoQuestToggleCtrl and type(AutoQuestToggleCtrl.Set) == "function" then
		local cur = AutoQuestToggleCtrl.Get and AutoQuestToggleCtrl:Get()
		if cur then elevateIdentity(); pcall(AutoQuestToggleCtrl.Set, AutoQuestToggleCtrl, false) end
	end
	if QuickFarmToggleCtrl and type(QuickFarmToggleCtrl.Set) == "function" then
		local cur = QuickFarmToggleCtrl.Get and QuickFarmToggleCtrl:Get()
		if cur then elevateIdentity(); pcall(QuickFarmToggleCtrl.Set, QuickFarmToggleCtrl, false) end
	end
end

local function resolveQuestModeTarget(): string
	if CFG.QuestMatchMode == "Ranked (Blitz)" then
		return IS_ROCHESS and "3+0" or "blitz"
	elseif CFG.QuestMatchMode == "Ranked (Bullet)" then
		return IS_ROCHESS and "1+0" or "bullet"
	end
	return IS_ROCHESS and "bot:pebble" or "bot:pip"
end

local function startSmartAutoQuest()
	if CFG.AutoQuestRunning then return end
	CFG.QuickFarmRunning = false
	CFG.AutoPuzzleRunning = false
	CFG.AutoMatchRunning = false
	if QuickFarmToggleCtrl and QuickFarmToggleCtrl.Get and QuickFarmToggleCtrl:Get() then
		pcall(QuickFarmToggleCtrl.Set, QuickFarmToggleCtrl, false)
	end

	CFG.AutoQuestRunning = true
	ensureAutoPlay(true)

	task.spawn(function()
		elevateIdentity()
		scanControllers(true)
		refreshGoalsUI()

		if IS_ROCHESS then
			claimRoChessTasks()
			local function roHasPending(): boolean
				local t = App and (App.tasks or (App.profile and App.profile.tasks))
				if type(t) ~= "table" then return false end
				local pMap, cMap, gMap = t.p or {}, t.c or {}, t.g or {}
				for _, def in ipairs(RoConfig.DAILY_TASKS or {}) do
					local goal = tonumber(gMap[def.id]) or def.goal or 1
					if (tonumber(pMap[def.id]) or 0) < goal or not cMap[def.id] then return true end
				end
				return false
			end

			local target = resolveQuestModeTarget()
			while alive and CFG.AutoQuestRunning do
				claimRoChessTasks()
				refreshGoalsUI()
				if not roHasPending() then
					updatePara(QuestStatusPara, "All daily tasks done & claimed!")
					safeNotify({ Title = "Auto Quest", Content = "Daily tasks completed!", Duration = 3, Type = "Success" })
					break
				end
				stepAutoMatchWithTarget(target)
				task.wait(0.8)
			end
		else
			if getCurrentMode() == "game" and GameViewInst and type(GameViewInst.current) == "function" then
				local curG = GameViewInst.current()
				while alive and CFG.AutoQuestRunning and getCurrentMode() == "game" and curG and not curG.over and not curG.past and curG.you ~= 0 do
					updatePara(QuestStatusPara, "Finishing active match...")
					task.wait(0.8)
					curG = GameViewInst.current()
				end
				if alive and CFG.AutoQuestRunning and curG and curG.over then
					refreshGoalsUI()
					ensureCdHomeForSwitch()
				end
			end

			if alive and CFG.AutoQuestRunning and getCdGoalRemaining("lesson1") > 0 then
				ensureCdHomeForSwitch()
				runAutoLessonOnce()
				task.wait(0.7)
			end
			if alive and CFG.AutoQuestRunning and getCdGoalRemaining("daily1") > 0 then
				ensureCdHomeForSwitch()
				runAutoPuzzle("daily", 1, "daily1")
				while alive and CFG.AutoQuestRunning and CFG.AutoPuzzleRunning do task.wait(0.4) end
				task.wait(0.7)
			end
			local remPuz = getCdGoalRemaining("puzzles5")
			if alive and CFG.AutoQuestRunning and remPuz > 0 then
				ensureCdHomeForSwitch()
				runAutoPuzzle("rated", remPuz, "puzzles5")
				while alive and CFG.AutoQuestRunning and CFG.AutoPuzzleRunning do task.wait(0.4) end
				task.wait(0.7)
			end
			if alive and CFG.AutoQuestRunning and getCdGoalRemaining("rush5") > 0 then
				ensureCdHomeForSwitch()
				local meta = CdProgression.goal("rush5")
				runAutoPuzzle("rush", meta and meta.target or 5, "rush5")
				while alive and CFG.AutoQuestRunning and CFG.AutoPuzzleRunning do task.wait(0.4) end
				task.wait(0.7)
			end

			while alive and CFG.AutoQuestRunning do
				refreshGoalsUI()
				local needBlitz = getCdGoalRemaining("blitz2") > 0
				local needOnline = getCdGoalRemaining("online1") > 0
				local needBotOrMatch = getCdGoalRemaining("play3") > 0 or getCdGoalRemaining("win1") > 0 or getCdGoalRemaining("mate1") > 0
				if not (needBlitz or needOnline or needBotOrMatch) then
					updatePara(QuestStatusPara, "All daily goals completed!")
					safeNotify({ Title = "Auto Quest", Content = "Daily goals completed!", Duration = 3, Type = "Success" })
					break
				end

				local target: string
				if needBlitz then
					target = "blitz"
				elseif needOnline then
					target = (CFG.QuestMatchMode == "Ranked (Bullet)") and "bullet" or "blitz"
				else
					target = resolveQuestModeTarget()
				end

				if string.sub(target, 1, 4) ~= "bot:" and needBotOrMatch then
					local banned = isCdQueueBanned()
					if banned then
						target = "bot:pip"
					end
				end

				stepAutoMatchWithTarget(target)
				task.wait(0.8)
			end
		end

		CFG.AutoQuestRunning = false
		refreshGoalsUI()
		if AutoQuestToggleCtrl and AutoQuestToggleCtrl.Get and AutoQuestToggleCtrl:Get() then
			elevateIdentity()
			pcall(AutoQuestToggleCtrl.Set, AutoQuestToggleCtrl, false)
		end
	end)
end

local FARM_TARGET_MAP: { [string]: { kind: string, value: string } } = {
	["Ranked 3+0 (Blitz)"] = { kind = "match", value = "3+0" },
	["Ranked 1+0 (Bullet)"] = { kind = "match", value = "1+0" },
	["Ranked 10+0 (Rapid)"] = { kind = "match", value = "10+0" },
	["Bot: Pebble (250)"] = { kind = "match", value = "bot:pebble" },
	["Bot: Milo (400)"] = { kind = "match", value = "bot:milo" },
	["Bot: Clara (600)"] = { kind = "match", value = "bot:clara" },
	["Ranked Blitz"] = { kind = "match", value = "blitz" },
	["Ranked Bullet"] = { kind = "match", value = "bullet" },
	["Ranked Rapid"] = { kind = "match", value = "rapid" },
	["Bot: Pip (200)"] = { kind = "match", value = "bot:pip" },
	["Bot: Clover (500)"] = { kind = "match", value = "bot:clover" },
	["Bot: Bramble (800)"] = { kind = "match", value = "bot:bramble" },
	["Bot: Maple (1100)"] = { kind = "match", value = "bot:maple" },
	["Bot: Flint (1400)"] = { kind = "match", value = "bot:flint" },
	["Bot: Sable (1700)"] = { kind = "match", value = "bot:sable" },
	["Bot: Onyx (2000)"] = { kind = "match", value = "bot:onyx" },
	["Bot: Vesper (2300)"] = { kind = "match", value = "bot:vesper" },
	["Puzzles (Rated)"] = { kind = "puzzle", value = "rated" },
	["Puzzle Rush"] = { kind = "puzzle", value = "rush" },
}

local function startQuickFarm()
	if CFG.QuickFarmRunning then return end
	CFG.AutoQuestRunning = false
	CFG.AutoPuzzleRunning = false
	CFG.AutoMatchRunning = false
	if AutoQuestToggleCtrl and AutoQuestToggleCtrl.Get and AutoQuestToggleCtrl:Get() then
		pcall(AutoQuestToggleCtrl.Set, AutoQuestToggleCtrl, false)
	end

	CFG.QuickFarmRunning = true
	local spec = FARM_TARGET_MAP[CFG.QuickFarmTarget]
	if not spec then
		CFG.QuickFarmRunning = false
		return
	end

	if spec.kind == "puzzle" then
		runAutoPuzzle(spec.value, 0, nil)
		task.spawn(function()
			while alive and CFG.QuickFarmRunning and CFG.AutoPuzzleRunning do task.wait(0.3) end
			CFG.QuickFarmRunning = false
			updatePara(QuestStatusPara, "Farm stopped.")
		end)
	else
		CFG.AutoMatchRunning = true
		ensureAutoPlay(true)
		task.spawn(function()
			elevateIdentity()
			while alive and CFG.QuickFarmRunning do
				stepAutoMatchWithTarget(spec.value)
				task.wait(0.8)
			end
			CFG.AutoMatchRunning = false
			updatePara(QuestStatusPara, "Farm stopped.")
		end)
	end
end

local MOD_SKIN = {
	unlocked = false,
	eq = {} :: { [string]: string },
}

local cdPreviewingBoard = false
local syncSkinDropdownsCb: (() -> ())? = nil
local STATE_FILE = "SonChess_v6_state.json"

local function cloneNestedMap(src: any): { [string]: any }
	local out: { [string]: any } = {}
	if type(src) ~= "table" then return out end
	for k, v in pairs(src) do
		out[k] = (type(v) == "table") and table.clone(v) or v
	end
	return out
end

local function saveSessionState(withResume: boolean?)
	if type(writeFileFn) ~= "function" then return end
	local gameKey = IS_ROCHESS and "rochess" or "chessduels"
	local existing: { [string]: any } = {}
	if type(isFileFn) == "function" and type(readFileFn) == "function" then
		local okEx, raw = pcall(function()
			return isFileFn(STATE_FILE) and readFileFn(STATE_FILE) or nil
		end)
		if okEx and type(raw) == "string" and #raw > 0 then
			local okDec, tbl = pcall(HttpService.JSONDecode, HttpService, raw)
			if okDec and type(tbl) == "table" then existing = tbl end
		end
	end

	existing.cfg = {
		ApiProvider = CFG.ApiProvider,
		Depth = CFG.Depth,
		StrictEngine = CFG.StrictEngine,
		MoveDelay = CFG.MoveDelay,
		HumanJitter = CFG.HumanJitter,
		PuzzleDelay = CFG.PuzzleDelay,
		QuestMatchMode = CFG.QuestMatchMode,
		QuickFarmTarget = existing.cfg and existing.cfg.QuickFarmTarget or nil,
		HideName = CFG.HideName,
		HintEnabled = CFG.HintEnabled,
		LiveHint = CFG.LiveHint,
		ShowTop2Arrow = CFG.ShowTop2Arrow,
		NotifyHints = CFG.NotifyHints,
	}
	existing.cfg[gameKey .. "_farm"] = CFG.QuickFarmTarget
	existing.skin = existing.skin or {}
	existing.skin[gameKey] = {
		unlocked = MOD_SKIN.unlocked,
		eq = table.clone(MOD_SKIN.eq),
	}
	if withResume and (CFG.AutoQuestRunning or CFG.QuickFarmRunning or CFG.AutoPlayEnabled) then
		existing.resume = {
			gameId = game.GameId,
			ts = os.time(),
			quest = CFG.AutoQuestRunning,
			farm = CFG.QuickFarmRunning,
			farmTarget = CFG.QuickFarmTarget,
			autoplay = CFG.AutoPlayEnabled,
		}
	elseif withResume == false then
		existing.resume = nil
	end
	pcall(writeFileFn, STATE_FILE, HttpService:JSONEncode(existing))
end

local function loadSessionState(): any
	if type(isFileFn) ~= "function" or type(readFileFn) ~= "function" then return nil end
	local ok, raw = pcall(function()
		return isFileFn(STATE_FILE) and readFileFn(STATE_FILE) or nil
	end)
	if not ok or type(raw) ~= "string" or #raw == 0 then return nil end
	local okDec, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if not okDec or type(data) ~= "table" then return nil end

	local gameKey = IS_ROCHESS and "rochess" or "chessduels"
	if type(data.cfg) == "table" then
		local c = data.cfg
		if type(c.ApiProvider) == "string" then CFG.ApiProvider = c.ApiProvider end
		if type(c.Depth) == "number" then CFG.Depth = math.clamp(math.floor(c.Depth), 8, 18) end
		if type(c.StrictEngine) == "boolean" then CFG.StrictEngine = c.StrictEngine end
		if type(c.MoveDelay) == "number" then CFG.MoveDelay = math.clamp(c.MoveDelay, 0, 3) end
		if type(c.HumanJitter) == "number" then CFG.HumanJitter = math.clamp(c.HumanJitter, 0, 1) end
		if type(c.PuzzleDelay) == "number" then CFG.PuzzleDelay = math.clamp(c.PuzzleDelay, 0.1, 2) end
		if type(c.QuestMatchMode) == "string" then CFG.QuestMatchMode = c.QuestMatchMode end
		if type(c[gameKey .. "_farm"]) == "string" then CFG.QuickFarmTarget = c[gameKey .. "_farm"] end
		if type(c.HideName) == "boolean" then CFG.HideName = c.HideName end
		if type(c.HintEnabled) == "boolean" then CFG.HintEnabled = c.HintEnabled end
		if type(c.LiveHint) == "boolean" then CFG.LiveHint = c.LiveHint end
		if type(c.ShowTop2Arrow) == "boolean" then CFG.ShowTop2Arrow = c.ShowTop2Arrow end
		if type(c.NotifyHints) == "boolean" then CFG.NotifyHints = c.NotifyHints end
	end
	if type(data.skin) == "table" and type(data.skin[gameKey]) == "table" then
		local sk = data.skin[gameKey]
		MOD_SKIN.unlocked = sk.unlocked == true
		if type(sk.eq) == "table" then
			for k, v in pairs(sk.eq) do
				if type(k) == "string" and type(v) == "string" and v ~= "" then
					MOD_SKIN.eq[k] = v
				end
			end
		end
	end
	return data.resume
end

local function snapshotRealRoSkins()
	if not IS_ROCHESS or not App then return nil end
	if not env._RoRealSkins and type(App.cos) == "table" then
		local realOwned = {}
		for _, id in ipairs(App.cos.inv or {}) do realOwned[id] = true end
		env._RoRealSkins = {
			inv = table.clone(App.cos.inv or {}),
			eq = table.clone(App.cos.eq or {}),
			extra = table.clone(App.cos.extra or {}),
			crates = App.cos.crates or 0,
			prompted = App.cos.prompted or false,
			theme = App.settings and App.settings.theme or "green",
			ownedMap = realOwned,
		}
	end
	return env._RoRealSkins
end

local function isRealOwnedRoSkin(id: string): boolean
	if not IS_ROCHESS or not RoCosmetics then return false end
	local item = RoCosmetics.BY_ID[id]
	if item and item.free == true then return true end
	local real = snapshotRealRoSkins()
	return real ~= nil and real.ownedMap[id] == true
end

local function buildAllRoSkinIds(): { string }
	local allIds = {}
	if RoCosmetics and type(RoCosmetics.ITEMS) == "table" then
		for _, item in ipairs(RoCosmetics.ITEMS) do
			if type(item.id) == "string" then table.insert(allIds, item.id) end
		end
	end
	return allIds
end

local function refreshRoInventoryUI()
	if IS_ROCHESS and App and App.pages and App.pages.inventory and type(App.pages.inventory.refresh) == "function" then
		pcall(App.pages.inventory.refresh)
	end
end

local function applyRoSkinState()
	if not IS_ROCHESS or not App then return end
	local real = snapshotRealRoSkins()
	local origSetCos = env._RoOrigSetCos or App.setCos
	local origApplySettings = App.applySettings

	if not MOD_SKIN.unlocked then
		if real then
			local restoreCos = {
				inv = table.clone(real.inv),
				eq = table.clone(real.eq),
				extra = table.clone(real.extra),
				crates = real.crates,
				prompted = real.prompted,
			}
			if App.settings then App.settings.theme = real.theme end
			if type(origSetCos) == "function" then pcall(origSetCos, restoreCos) end
			if type(origApplySettings) == "function" then pcall(origApplySettings) end
			refreshRoInventoryUI()
		end
		return
	end

	local curCos = App.cos or { inv = {}, eq = {} }
	local nextEq = table.clone(curCos.eq or (real and real.eq) or {})
	for k, v in pairs(MOD_SKIN.eq) do
		if type(v) == "string" and v ~= "" then nextEq[k] = v end
	end
	local modCos = {
		inv = buildAllRoSkinIds(),
		eq = nextEq,
		extra = curCos.extra or {},
		crates = curCos.crates or 0,
		prompted = curCos.prompted or false,
	}
	if App.settings and nextEq.board then App.settings.theme = nextEq.board end
	if type(origSetCos) == "function" then
		pcall(origSetCos, modCos)
	else
		App.cos = modCos
		if type(App.applyCosmetics) == "function" then pcall(App.applyCosmetics) end
	end
	if type(origApplySettings) == "function" then pcall(origApplySettings) end
	refreshRoInventoryUI()
end

local function installRoSkinHooks()
	if not IS_ROCHESS or not App then return end
	snapshotRealRoSkins()

	env._RoOrigOwns = env._RoOrigOwns or App.owns
	env._RoOrigSetCos = env._RoOrigSetCos or App.setCos
	env._RoOrigRequest = env._RoOrigRequest or App.request

	local origOwns = env._RoOrigOwns
	local origSetCos = env._RoOrigSetCos
	local origRequest = env._RoOrigRequest

	App.owns = function(id)
		if alive and MOD_SKIN.unlocked and RoCosmetics and RoCosmetics.BY_ID[id] ~= nil then return true end
		return origOwns(id)
	end

	App.setCos = function(cosTable)
		if type(cosTable) == "table" then
			local allCount = RoCosmetics and RoCosmetics.ITEMS and #RoCosmetics.ITEMS or 999
			if #(cosTable.inv or {}) < allCount then
				local realOwned = {}
				for _, id in ipairs(cosTable.inv or {}) do realOwned[id] = true end
				env._RoRealSkins = {
					inv = table.clone(cosTable.inv or {}),
					eq = table.clone(cosTable.eq or {}),
					extra = table.clone(cosTable.extra or {}),
					crates = cosTable.crates or 0,
					prompted = cosTable.prompted or false,
					theme = (cosTable.eq and cosTable.eq.board) or (App.settings and App.settings.theme) or "green",
					ownedMap = realOwned,
				}
			end
		end

		if alive and MOD_SKIN.unlocked and type(cosTable) == "table" then
			local mergedEq = table.clone(cosTable.eq or {})
			for k, v in pairs(MOD_SKIN.eq) do
				if type(v) == "string" and v ~= "" then mergedEq[k] = v end
			end
			local patched = {
				inv = buildAllRoSkinIds(),
				eq = mergedEq,
				extra = cosTable.extra or {},
				crates = cosTable.crates or 0,
				prompted = cosTable.prompted or false,
			}
			if App.settings and mergedEq.board then App.settings.theme = mergedEq.board end
			return origSetCos(patched)
		end
		return origSetCos(cosTable)
	end

	App.request = function(payload)
		if alive and MOD_SKIN.unlocked and type(payload) == "table" and payload.type == "equip" then
			local kind, id = payload.kind, payload.id
			if type(kind) == "string" and type(id) == "string" and not isRealOwnedRoSkin(id) then
				MOD_SKIN.eq[kind] = id
				task.defer(applyRoSkinState)
				return { ok = true, cos = App.cos }
			end
		end
		return origRequest(payload)
	end
end

local function countTotalCdSkins(): number
	if IS_ROCHESS or not CdCosmetics then return 0 end
	local total = 0
	for _, cat in ipairs(CdCosmetics.CATEGORIES or {}) do
		local list = CdCosmetics[cat.key]
		if type(list) == "table" then total += #list end
	end
	return total
end

local function snapshotRealCdSkins()
	if IS_ROCHESS or not GameCtx or not GameCtx.profile then return nil end
	local prog = GameCtx.profile.progress
	if type(prog) ~= "table" then return env._CdRealSkins end
	if prog.inventory ~= env._CdModInvRef and type(prog.inventory) == "table" then
		env._CdRealSkins = {
			inventory = cloneNestedMap(prog.inventory),
			equipped = table.clone(prog.equipped or (CdCosmetics and CdCosmetics.DEFAULTS) or {}),
		}
	elseif not env._CdRealSkins then
		env._CdRealSkins = {
			inventory = cloneNestedMap(prog.inventory or {}),
			equipped = table.clone(prog.equipped or (CdCosmetics and CdCosmetics.DEFAULTS) or {}),
		}
	end
	return env._CdRealSkins
end

local function isRealOwnedCdSkin(cat: string, id: string): boolean
	if IS_ROCHESS or not CdCosmetics then return false end
	local item = CdCosmetics.item(cat, id)
	if item and item.price == 0 then return true end
	local real = snapshotRealCdSkins()
	return real ~= nil and type(real.inventory) == "table" and type(real.inventory[cat]) == "table" and real.inventory[cat][id] == true
end

local function buildAllCdInventory(): { [string]: { [string]: boolean } }
	local inv: { [string]: { [string]: boolean } } = {}
	if not CdCosmetics then return inv end
	for _, cat in ipairs(CdCosmetics.CATEGORIES or {}) do
		local catMap: { [string]: boolean } = {}
		for _, item in ipairs(CdCosmetics[cat.key] or {}) do
			if type(item.id) == "string" then
				catMap[item.id] = true
			end
		end
		inv[cat.key] = catMap
	end
	return inv
end

local function patchCdProgressOnly(): boolean
	if IS_ROCHESS or not MOD_SKIN.unlocked or not GameCtx or not GameCtx.profile or type(GameCtx.profile.progress) ~= "table" then
		return false
	end
	local prog = GameCtx.profile.progress
	snapshotRealCdSkins()
	if prog.inventory ~= env._CdModInvRef then
		local modInv = buildAllCdInventory()
		env._CdModInvRef = modInv
		prog.inventory = modInv
	end
	local real = snapshotRealCdSkins()
	local eq = table.clone((real and real.equipped) or (CdCosmetics and CdCosmetics.DEFAULTS) or {})
	for k, v in pairs(MOD_SKIN.eq) do
		if type(v) == "string" and v ~= "" then eq[k] = v end
	end
	prog.equipped = eq
	return true
end

local function applyCdSeatFrame(seatHost: any, frameId: string?)
	if type(seatHost) ~= "table" or type(seatHost.seat) ~= "table" or type(seatHost.setSeat) ~= "function" then return end
	if seatHost.seat.frame == frameId then return end
	local nextSeat = table.clone(seatHost.seat)
	nextSeat.frame = frameId
	pcall(seatHost.setSeat, seatHost, nextSeat, seatHost.side)
end

local function applyCdActiveGameCosmetics(curGame: any, eq: { [string]: string }, restoring: boolean)
	if type(curGame) ~= "table" or (curGame.you ~= 1 and curGame.you ~= -1) then return end
	local mySeat = (curGame.you == 1) and curGame.white or curGame.black
	if type(mySeat) ~= "table" then return end

	env._CdRealMatchCos = env._CdRealMatchCos or {}
	local gKey = tostring(curGame.id or "cur")
	if not env._CdRealMatchCos[gKey] then
		env._CdRealMatchCos[gKey] = {
			trail = mySeat.trail,
			capture = mySeat.capture,
			frame = mySeat.frame,
		}
	end

	if restoring then
		local saved = env._CdRealMatchCos[gKey]
		mySeat.trail = saved and saved.trail or eq.trails
		mySeat.capture = saved and saved.capture or eq.captures
		mySeat.frame = saved and saved.frame or eq.frames
	else
		mySeat.trail = eq.trails or mySeat.trail
		mySeat.capture = eq.captures or mySeat.capture
		mySeat.frame = eq.frames or mySeat.frame
	end
end

local function applyCdSkinState()
	if IS_ROCHESS or not CdCosmetics or not CdTheme then return end
	scanControllers(false)
	local real = snapshotRealCdSkins()
	local prog = GameCtx and GameCtx.profile and GameCtx.profile.progress
	local bv = (GameCtx and GameCtx.board) or BoardViewInstance

	if not MOD_SKIN.unlocked then
		env._CdSkinActive = false
		env._CdModInvRef = nil
		local eq = (real and table.clone(real.equipped)) or table.clone(CdCosmetics.DEFAULTS)
		if type(prog) == "table" and real then
			prog.inventory = cloneNestedMap(real.inventory)
			prog.equipped = table.clone(real.equipped)
		end
		if type(bv) == "table" and not cdPreviewingBoard then
			local bItem = CdCosmetics.item("boards", eq.boards) or CdCosmetics.boards[1]
			local hItem = CdCosmetics.item("highlights", eq.highlights) or CdCosmetics.highlights[1]
			local pItem = CdCosmetics.item("pieces", eq.pieces)
			local wantLight = Color3.fromHex(bItem.light)
			local wantDark = Color3.fromHex(bItem.dark)
			local wantHl = Color3.fromHex(hItem.color)
			if bv.lightColor ~= wantLight or bv.darkColor ~= wantDark or bv.highlightColor ~= wantHl or bv.fx ~= bItem.fx then
				if type(bv.setTheme) == "function" then
					pcall(bv.setTheme, bv, wantLight, wantDark, wantHl, bItem.fx)
				end
			end
			local wantPieces = (CdTheme.PieceSets and CdTheme.PieceSets[eq.pieces]) or CdTheme.Piece
			local wantPieceFx = pItem and pItem.fx or nil
			if bv.pieceSet ~= wantPieces or bv.pieceFx ~= wantPieceFx then
				local setPiecesFn = env._CdOrigSetPieceSet or bv.setPieceSet
				if type(setPiecesFn) == "function" then
					pcall(setPiecesFn, bv, wantPieces, wantPieceFx)
				end
			end
		end
		if GameCtx and GameCtx.bottom then
			applyCdSeatFrame(GameCtx.bottom, eq.frames)
		end
		if GameViewInst and type(GameViewInst.current) == "function" then
			local okG, curG = pcall(GameViewInst.current)
			if okG and type(curG) == "table" then
				applyCdActiveGameCosmetics(curG, eq, true)
			end
		end
		if CdCollection and type(CdCollection.refreshAll) == "function" then
			pcall(CdCollection.refreshAll)
		end
		if GameCtx and type(GameCtx.onProfile) == "function" and GameCtx.profile then
			pcall(GameCtx.onProfile, GameCtx.profile)
		end
		return
	end

	env._CdSkinActive = true
	patchCdProgressOnly()
	local eq = (type(prog) == "table" and prog.equipped) or {}
	for _, cat in ipairs(CdCosmetics.CATEGORIES or {}) do
		if not eq[cat.key] then
			eq[cat.key] = (MOD_SKIN.eq[cat.key]) or (real and real.equipped and real.equipped[cat.key]) or CdCosmetics.DEFAULTS[cat.key]
		end
	end

	if type(bv) == "table" and not cdPreviewingBoard then
		local bItem = CdCosmetics.item("boards", eq.boards) or CdCosmetics.boards[1]
		local hItem = CdCosmetics.item("highlights", eq.highlights) or CdCosmetics.highlights[1]
		local pItem = CdCosmetics.item("pieces", eq.pieces)
		local wantLight = Color3.fromHex(bItem.light)
		local wantDark = Color3.fromHex(bItem.dark)
		local wantHl = Color3.fromHex(hItem.color)
		if bv.lightColor ~= wantLight or bv.darkColor ~= wantDark or bv.highlightColor ~= wantHl or bv.fx ~= bItem.fx then
			if type(bv.setTheme) == "function" then
				pcall(bv.setTheme, bv, wantLight, wantDark, wantHl, bItem.fx)
			end
		end
		local wantPieces = (CdTheme.PieceSets and CdTheme.PieceSets[eq.pieces]) or CdTheme.Piece
		local wantPieceFx = pItem and pItem.fx or nil
		if bv.pieceSet ~= wantPieces or bv.pieceFx ~= wantPieceFx then
			local setPiecesFn = env._CdOrigSetPieceSet or bv.setPieceSet
			if type(setPiecesFn) == "function" then
				pcall(setPiecesFn, bv, wantPieces, wantPieceFx)
			end
		end
	end

	if GameCtx and GameCtx.bottom then
		applyCdSeatFrame(GameCtx.bottom, eq.frames)
	end
	if GameViewInst and type(GameViewInst.current) == "function" then
		local okG, curG = pcall(GameViewInst.current)
		if okG and type(curG) == "table" then
			applyCdActiveGameCosmetics(curG, eq, false)
		end
	end
	if CdCollection and type(CdCollection.refreshAll) == "function" then
		pcall(CdCollection.refreshAll)
	end
end

local function installCdSkinHooks()
	if IS_ROCHESS then return end
	scanControllers(false)
	snapshotRealCdSkins()

	if CdBoardView and type(CdBoardView.setPieceSet) == "function" and not env._CdOrigSetPieceSet then
		env._CdOrigSetPieceSet = CdBoardView.setPieceSet
	end
	if env._CdOrigSetPieceSet and CdBoardView then
		local origSetPieces = env._CdOrigSetPieceSet
		CdBoardView.setPieceSet = function(self, pSet, pFx)
			local res = origSetPieces(self, pSet, pFx)
			if alive and MOD_SKIN.unlocked then
				patchCdProgressOnly()
				task.defer(applyCdSkinState)
			end
			return res
		end
	end

	if GameCtx then
		if type(GameCtx.onProfile) == "function" and not env._CdOrigOnProfile then
			env._CdOrigOnProfile = GameCtx.onProfile
		end
		local origOnProfile = env._CdOrigOnProfile
		GameCtx.onProfile = function(profile)
			snapshotRealCdSkins()
			if alive and MOD_SKIN.unlocked then
				patchCdProgressOnly()
			end
			local res = origOnProfile and origOnProfile(profile)
			if alive then
				if MOD_SKIN.unlocked then
					task.defer(applyCdSkinState)
				end
				task.defer(refreshGoalsUI)
			end
			return res
		end

		if type(GameCtx.previewBoard) == "function" and not env._CdOrigPreviewBoard then
			env._CdOrigPreviewBoard = GameCtx.previewBoard
		end
		local origPreview = env._CdOrigPreviewBoard
		if origPreview then
			GameCtx.previewBoard = function(boardDef)
				cdPreviewingBoard = (boardDef ~= nil)
				local res = origPreview(boardDef)
				if alive and MOD_SKIN.unlocked and boardDef == nil then
					task.defer(applyCdSkinState)
				end
				return res
			end
		end
	end

	if GameViewInst and type(GameViewInst.apply) == "function" then
		env._CdOrigGameApply = env._CdOrigGameApply or GameViewInst.apply
		local origApply = env._CdOrigGameApply
		GameViewInst.apply = function(stateData)
			if alive and MOD_SKIN.unlocked and type(stateData) == "table" and (stateData.you == 1 or stateData.you == -1) then
				patchCdProgressOnly()
				local prog = GameCtx and GameCtx.profile and GameCtx.profile.progress
				local eq = type(prog) == "table" and prog.equipped or MOD_SKIN.eq
				applyCdActiveGameCosmetics(stateData, eq, false)
			end
			return origApply(stateData)
		end
	end

	env._CdEquipInterceptor = function(cat: string, id: string): boolean
		if not alive or not MOD_SKIN.unlocked then return false end
		if isRealOwnedCdSkin(cat, id) then
			MOD_SKIN.eq[cat] = id
			task.defer(function()
				applyCdSkinState()
				if syncSkinDropdownsCb then syncSkinDropdownsCb() end
			end)
			saveSessionState()
			return false
		end
		MOD_SKIN.eq[cat] = id
		task.defer(function()
			applyCdSkinState()
			if syncSkinDropdownsCb then syncSkinDropdownsCb() end
		end)
		saveSessionState()
		return true
	end

	if not env._CdNamecallHooked and type(hookMetamethodFn) == "function" and type(newCClosureFn) == "function"
		and type(checkCallerFn) == "function" and type(getNamecallMethodFn) == "function"
	then
		env._CdNamecallHooked = true
		local origNc: any
		origNc = hookMetamethodFn(game, "__namecall", newCClosureFn(function(self, ...)
			if env._CdSkinActive and not checkCallerFn() and self == CdAction and getNamecallMethodFn() == "FireServer" then
				local actionName, payload = ...
				if actionName == "equip" and type(payload) == "table"
					and type(payload.category) == "string" and type(payload.id) == "string"
					and type(env._CdEquipInterceptor) == "function"
				then
					if env._CdEquipInterceptor(payload.category, payload.id) then
						return nil
					end
				end
			end
			return origNc(self, ...)
		end))
	end
end

local function onBoardUpdated()
	elevateIdentity()
	if not alive then return end
	if not isMyTurn() then
		lastBoardKey = nil
		if hintGui or currentHintResult or inFlightHintFen then
			clearHint()
		end
		if not CFG.AutoPlayEnabled and not CFG.AutoPuzzleRunning then
			updatePara(HintStatusPara, "Opponent turn...")
		end
		return
	end

	local bKey = getActiveBoardKey()
	if bKey and bKey == lastBoardKey and currentHintResult then
		return
	end
	lastBoardKey = bKey

	syncSeq += 1
	local mySync = syncSeq

	task.delay(0.08, function()
		elevateIdentity()
		if not alive or mySync ~= syncSeq then return end
		if not isMyTurn() then
			clearHint()
			return
		end

		if CFG.LiveHint and CFG.HintEnabled and not CFG.AutoPlayEnabled and not CFG.AutoPuzzleRunning then
			triggerHintAsync(false)
		end
	end)
end

if IS_ROCHESS then
	env._RoChessOrigRender = env._RoChessOrigRender or App.render
	env._RoChessOrigSetPos = env._RoChessOrigSetPos or RoBoardView.setPosition
	env._RoChessOrigSetFlip = env._RoChessOrigSetFlip or RoBoardView.setFlipped

	local origRender = env._RoChessOrigRender
	local origSetPos = env._RoChessOrigSetPos
	local origSetFlip = env._RoChessOrigSetFlip

	App.render = function(opts)
		local res = origRender(opts)
		if alive then task.defer(onBoardUpdated) end
		return res
	end
	RoBoardView.setPosition = function(self, pos, last, opts)
		local res = origSetPos(self, pos, last, opts)
		if alive then task.defer(onBoardUpdated) end
		return res
	end
	RoBoardView.setFlipped = function(self, flipped)
		local res = origSetFlip(self, flipped)
		if alive and self == BoardViewInstance and currentHintResult and CFG.HintEnabled and isMyTurn() then
			task.defer(drawHint, currentHintResult)
		end
		return res
	end
else
	env._CdOrigShow = env._CdOrigShow or CdBoardView.show
	env._CdOrigSetLegal = env._CdOrigSetLegal or CdBoardView.setLegal
	env._CdOrigSetFlip = env._CdOrigSetFlip or CdBoardView.setFlipped

	local origShow = env._CdOrigShow
	local origSetLegal = env._CdOrigSetLegal
	local origSetFlip = env._CdOrigSetFlip

	CdBoardView.show = function(self, state, opts)
		local res = origShow(self, state, opts)
		if alive then task.defer(onBoardUpdated) end
		return res
	end
	CdBoardView.setLegal = function(self, legal, side)
		local res = origSetLegal(self, legal, side)
		if alive then task.defer(onBoardUpdated) end
		return res
	end
	CdBoardView.setFlipped = function(self, flipped)
		local res = origSetFlip(self, flipped)
		if alive and self == BoardViewInstance and currentHintResult and CFG.HintEnabled and isMyTurn() then
			task.defer(drawHint, currentHintResult)
		end
		return res
	end
end

local origName = lp.Name
local origDisplayName = lp.DisplayName
local nameShieldInstalled = false

local function maskGuiName(inst: Instance)
	if not CFG.HideName then return end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") then
		local t = inst.Text
		if t == origName or t == origDisplayName then
			inst.Text = CFG.DisplayName
		end
	end
end

local function installNameShield()
	if not CFG.HideName then return end
	pcall(function()
		if lp.DisplayName ~= CFG.DisplayName then lp.DisplayName = CFG.DisplayName end
	end)
	if nameShieldInstalled then return end
	nameShieldInstalled = true

	table.insert(nameShieldConns, lp:GetPropertyChangedSignal("DisplayName"):Connect(function()
		if alive and CFG.HideName and lp.DisplayName ~= CFG.DisplayName then
			pcall(function() lp.DisplayName = CFG.DisplayName end)
		end
	end))

	local pg = lp:FindFirstChild("PlayerGui")
	if not pg then return end
	local chessUI = pg:FindFirstChild("ChessUI") or pg

	task.spawn(function()
		local descs = chessUI:GetDescendants()
		for i, g in ipairs(descs) do
			if not alive or not CFG.HideName then break end
			maskGuiName(g)
			if i % 600 == 0 then task.wait() end
		end
	end)

	table.insert(nameShieldConns, chessUI.DescendantAdded:Connect(function(d)
		if alive and CFG.HideName then
			maskGuiName(d)
		end
	end))
end

local function findSonUiScreenGui(): ScreenGui?
	elevateIdentity()
	local containers = { game:GetService("CoreGui") }
	if type(gethui) == "function" then
		local ok, h = pcall(gethui)
		if ok and h then table.insert(containers, h) end
	end
	for _, root in ipairs(containers) do
		local ui = root:FindFirstChild("SonUI_SonChess")
		if ui and ui:IsA("ScreenGui") then
			return ui
		end
	end
	return nil
end

local function patchSonScrollFrame(sf: ScrollingFrame)
	if sf.ScrollingDirection == Enum.ScrollingDirection.Y or sf.AutomaticCanvasSize == Enum.AutomaticSize.Y then
		sf.CanvasSize = UDim2.fromOffset(0, 0)
		sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
		sf.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	end
	if sf.Name == "InlineOptions" then
		sf.Size = UDim2.new(1, -20, 1, -(sf.Position.Y.Offset + 8))
		sf.CanvasPosition = Vector2.zero
		if not sf:GetAttribute("SonScrollFixed") then
			sf:SetAttribute("SonScrollFixed", true)
			table.insert(connections, sf:GetPropertyChangedSignal("Visible"):Connect(function()
				if sf.Visible then
					sf.CanvasSize = UDim2.fromOffset(0, 0)
					sf.Size = UDim2.new(1, -20, 1, -(sf.Position.Y.Offset + 8))
					sf.CanvasPosition = Vector2.zero
				end
			end))
			table.insert(connections, sf:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
				if sf.CanvasSize.Y.Scale ~= 0 or sf.CanvasSize.Y.Offset ~= 0 then
					sf.CanvasSize = UDim2.fromOffset(0, 0)
				end
			end))
		end
	elseif sf.Name == "PopScroll" then
		sf.CanvasSize = UDim2.fromOffset(0, 0)
		sf.CanvasPosition = Vector2.zero
	end
end

local function hardenSonUi()
	local ui = findSonUiScreenGui()
	if not ui then return end
	ui.AutoLocalize = false
	for _, d in ipairs(ui:GetDescendants()) do
		if d:IsA("GuiObject") or d:IsA("LayerCollector") then
			pcall(function() (d :: any).AutoLocalize = false end)
		end
		if d:IsA("ScrollingFrame") then
			patchSonScrollFrame(d)
		end
	end
	if not ui:GetAttribute("SonHookedAdded") then
		ui:SetAttribute("SonHookedAdded", true)
		table.insert(connections, ui.DescendantAdded:Connect(function(d)
			if not alive then return end
			if d:IsA("GuiObject") or d:IsA("LayerCollector") then
				pcall(function() (d :: any).AutoLocalize = false end)
			end
			if d:IsA("ScrollingFrame") then
				task.defer(patchSonScrollFrame, d)
			end
		end))
	end
end

local SonUI = nil
do
	local ok, src = pcall(function()
		if httpRequest then
			local r = httpRequest({
				Url = "https://raw.githubusercontent.com/hongson209/sonlibrary/refs/heads/main/sonlibrary.lua",
				Method = "GET",
			})
			if type(r) == "table" and tonumber(r.StatusCode) == 200 then return r.Body end
		end
		return game:HttpGet("https://raw.githubusercontent.com/hongson209/sonlibrary/refs/heads/main/sonlibrary.lua")
	end)
	if ok and type(src) == "string" and not src:find("404: Not Found") then
		local lOk, res = pcall(function() return loadstring(src)() end)
		if lOk and type(res) == "table" and res.CreateWindow then SonUI = res end
	end
	SonUI = SonUI or env.SonUI or env.SonLibrary
end

scanControllers(true)
local savedResumeState = loadSessionState()

if SonUI then
	local gameTitle = IS_ROCHESS and "RoChess" or "ChessDuels"
	Window = SonUI:CreateWindow({
		Name = "SonChess",
		Title = "SonChess v6.3",
		Subtitle = gameTitle .. " | Multi-Engine Max",
		Layout = "Sidebar",
		Style = "Acrylic Frosted",
		Size = UDim2.fromOffset(520, 460),
		ToggleKey = Enum.KeyCode.RightControl,
		Closable = true,
	})

	hardenSonUi()
	safeNotify({ Title = "SonChess v6.3", Content = gameTitle .. " | H: Hint | P: AutoPlay", Duration = 3, Type = "Success" })

	local AssistTab = Window:CreateTab({ Name = "Assistant", Description = "Hint, AutoPlay & API" })
	HintStatusPara = AssistTab:CreateParagraph({ Title = "Best Move", Content = "Waiting for turn..." })

	AssistTab:CreateSection("Hint")
	AssistTab:CreateButton({ Name = "Hint Now (H)", Variant = "Primary", Callback = function() triggerHintAsync(true) end })
	AssistTab:CreateToggle({
		Name = "Show Arrow",
		Default = CFG.HintEnabled,
		Callback = function(v)
			CFG.HintEnabled = v
			if not v then clearHint() elseif currentHintResult then drawHint(currentHintResult) end
			saveSessionState()
		end,
	})
	AssistTab:CreateToggle({
		Name = "Auto Hint",
		Default = CFG.LiveHint,
		Callback = function(v)
			CFG.LiveHint = v
			if v then triggerHintAsync(false) end
			saveSessionState()
		end,
	})
	AssistTab:CreateToggle({
		Name = "Top-2 Arrow",
		Default = CFG.ShowTop2Arrow,
		Callback = function(v)
			CFG.ShowTop2Arrow = v
			if CFG.HintEnabled and currentHintResult then drawHint(currentHintResult) end
			saveSessionState()
		end,
	})

	AssistTab:CreateSection("AutoPlay")
	AutoPlayToggleCtrl = AssistTab:CreateToggle({
		Name = "AutoPlay (P)",
		Default = CFG.AutoPlayEnabled,
		Callback = function(v)
			CFG.AutoPlayEnabled = v
			if v then startAuto() end
			saveSessionState(v)
		end,
	})
	AssistTab:CreateSlider({ Name = "Move Delay (0.1s)", Min = 0, Max = 30, Default = math.round(CFG.MoveDelay * 10), Callback = function(v) CFG.MoveDelay = v / 10; saveSessionState() end })
	AssistTab:CreateSlider({ Name = "Human Jitter (0.1s)", Min = 0, Max = 10, Default = math.round(CFG.HumanJitter * 10), Callback = function(v) CFG.HumanJitter = v / 10; saveSessionState() end })

	AssistTab:CreateSection("Stockfish API")
	AssistTab:CreateDropdown({
		Name = "API Source",
		Mode = "Inline",
		Options = {
			"Auto (Max All)",
			"MoveLens SF19 (Max)",
			"Stockfish.online (d15)",
			"ChessDB (Verified !)",
			"Lichess Cloud (d20+)",
			"Chess-API (d18)",
			"Offline AlphaBeta",
		},
		Default = CFG.ApiProvider,
		Callback = function(v)
			CFG.ApiProvider = v
			lastHintFen = nil
			lastAutoFen = nil
			saveSessionState()
			if isMyTurn() and CFG.LiveHint and CFG.HintEnabled and not CFG.AutoPlayEnabled then
				triggerHintAsync(false)
			end
		end,
	})
	AssistTab:CreateSlider({ Name = "Max Depth (Auto-Clamp)", Min = 8, Max = 18, Default = CFG.Depth, Callback = function(v) CFG.Depth = math.floor(v); saveSessionState() end })
	AssistTab:CreateToggle({ Name = "Strict API (Retry)", Default = CFG.StrictEngine, Callback = function(v) CFG.StrictEngine = v; saveSessionState() end })

	local QuestTab = Window:CreateTab({ Name = "Auto Quest", Description = "Quests, Rank & Puzzles" })
	QuestGoalsPara = QuestTab:CreateParagraph({ Title = "Progress", Content = "Loading..." })
	QuestStatusPara = QuestTab:CreateParagraph({ Title = "Status", Content = "Idle" })

	QuestTab:CreateSection("Smart Auto Quest")
	QuestTab:CreateDropdown({
		Name = "Quest Mode",
		Mode = "Inline",
		Options = { "Bot (Fast)", "Ranked (Blitz)", "Ranked (Bullet)" },
		Default = CFG.QuestMatchMode,
		Callback = function(v) CFG.QuestMatchMode = v; saveSessionState() end,
	})
	AutoQuestToggleCtrl = QuestTab:CreateToggle({
		Name = "Auto Complete Quests",
		Default = CFG.AutoQuestRunning,
		Callback = function(v)
			if v then
				startSmartAutoQuest()
				saveSessionState(true)
			else
				CFG.AutoQuestRunning = false
				CFG.AutoPuzzleRunning = false
				CFG.AutoMatchRunning = false
				CFG.AutoLessonRunning = false
				updatePara(QuestStatusPara, "Stopped.")
				saveSessionState(false)
			end
		end,
	})
	if IS_ROCHESS then
		QuestTab:CreateButton({
			Name = "Claim Completed Tasks",
			Callback = function()
				local n = claimRoChessTasks()
				refreshGoalsUI()
				safeNotify({ Title = "Tasks", Content = n > 0 and ("Claimed " .. tostring(n) .. " task(s).") or "No tasks ready.", Duration = 2, Type = n > 0 and "Success" or "Info" })
			end,
		})
	end

	QuestTab:CreateSection("Quick Farm")
	local farmOptions = IS_ROCHESS
		and { "Ranked 3+0 (Blitz)", "Ranked 1+0 (Bullet)", "Ranked 10+0 (Rapid)", "Bot: Pebble (250)", "Bot: Milo (400)", "Bot: Clara (600)", "Puzzles (Rated)", "Puzzle Rush" }
		or {
			"Ranked Blitz", "Ranked Bullet", "Ranked Rapid",
			"Bot: Pip (200)", "Bot: Clover (500)", "Bot: Bramble (800)", "Bot: Maple (1100)",
			"Bot: Flint (1400)", "Bot: Sable (1700)", "Bot: Onyx (2000)", "Bot: Vesper (2300)",
			"Puzzles (Rated)", "Puzzle Rush",
		}
	QuestTab:CreateDropdown({
		Name = "Farm Target",
		Mode = "Inline",
		Options = farmOptions,
		Default = CFG.QuickFarmTarget,
		Callback = function(v) CFG.QuickFarmTarget = v; saveSessionState() end,
	})
	QuickFarmToggleCtrl = QuestTab:CreateToggle({
		Name = "Start Farm",
		Default = CFG.QuickFarmRunning,
		Callback = function(v)
			if v then
				startQuickFarm()
				saveSessionState(true)
			else
				CFG.QuickFarmRunning = false
				CFG.AutoPuzzleRunning = false
				CFG.AutoMatchRunning = false
				updatePara(QuestStatusPara, "Farm stopped.")
				saveSessionState(false)
			end
		end,
	})

	local SkinTab = Window:CreateTab({ Name = "Skins", Description = "Unlock All Skins" })
	SkinTab:CreateSection("Mod Skin (Client)")

	local skinUnlockToggle: any = nil
	local skinDropdowns: { [string]: any } = {}
	local suppressSkinCb = false

	if IS_ROCHESS then
		installRoSkinHooks()
		if MOD_SKIN.unlocked then applyRoSkinState() end

		local function getRoSkinOptions(kind: string): ({ string }, { [string]: string }, string)
			local opts = {}
			local idToLabel = {}
			local curId = (MOD_SKIN.eq[kind]) or (App.cos and App.cos.eq and App.cos.eq[kind]) or (RoCosmetics.DEFAULT and RoCosmetics.DEFAULT[kind]) or ""
			if kind == "board" and App.settings and App.settings.theme then
				curId = MOD_SKIN.eq.board or App.settings.theme
			end
			for _, item in ipairs(RoCosmetics.BY_TYPE[kind] or {}) do
				local lbl = string.format("%s [%s]", tostring(item.name or item.id), tostring(item.id))
				table.insert(opts, lbl)
				idToLabel[item.id] = lbl
			end
			return opts, idToLabel, idToLabel[curId] or opts[1] or ""
		end

		local function equipRoModSkin(kind: string, choiceLabel: string)
			if suppressSkinCb then return end
			local id = string.match(choiceLabel, "%[([^%]]+)%]$")
			if not id then return end
			if not MOD_SKIN.unlocked then
				MOD_SKIN.unlocked = true
				if skinUnlockToggle and type(skinUnlockToggle.Set) == "function" then
					suppressSkinCb = true
					pcall(skinUnlockToggle.Set, skinUnlockToggle, true)
					suppressSkinCb = false
				end
			end
			MOD_SKIN.eq[kind] = id
			applyRoSkinState()
			saveSessionState()
		end

		skinUnlockToggle = SkinTab:CreateToggle({
			Name = "Unlock All Skins (139/139)",
			Default = MOD_SKIN.unlocked,
			Callback = function(v)
				if suppressSkinCb then return end
				MOD_SKIN.unlocked = v
				if not v then table.clear(MOD_SKIN.eq) end
				applyRoSkinState()
				saveSessionState()
				safeNotify({
					Title = "Skin Mod",
					Content = v and "All skins unlocked!" or "Restored real skins.",
					Duration = 2,
					Type = v and "Success" or "Info",
				})
			end,
		})

		SkinTab:CreateButton({
			Name = "Reset Real Skins",
			Callback = function()
				MOD_SKIN.unlocked = false
				table.clear(MOD_SKIN.eq)
				if skinUnlockToggle and type(skinUnlockToggle.Set) == "function" then
					suppressSkinCb = true
					pcall(skinUnlockToggle.Set, skinUnlockToggle, false)
					suppressSkinCb = false
				end
				applyRoSkinState()
				local real = snapshotRealRoSkins()
				if real then
					suppressSkinCb = true
					for kind, dd in pairs(skinDropdowns) do
						local _, idToLabel = getRoSkinOptions(kind)
						local realId = (kind == "board") and real.theme or (real.eq and real.eq[kind])
						if realId and idToLabel[realId] and type(dd.Set) == "function" then
							pcall(dd.Set, dd, idToLabel[realId])
						end
					end
					suppressSkinCb = false
				end
				saveSessionState()
				safeNotify({ Title = "Skin Mod", Content = "Restored original skins.", Duration = 2, Type = "Info" })
			end,
		})

		SkinTab:CreateSection("Quick Equip")
		for _, spec in ipairs({
			{ kind = "board", title = "Board Theme" },
			{ kind = "pieces", title = "Piece Colour" },
			{ kind = "design", title = "Piece Design" },
			{ kind = "background", title = "Background" },
			{ kind = "accessory", title = "Accessory" },
			{ kind = "effect", title = "Effect" },
		}) do
			local opts, _, defLabel = getRoSkinOptions(spec.kind)
			skinDropdowns[spec.kind] = SkinTab:CreateDropdown({
				Name = spec.title,
				Mode = "Inline",
				Options = opts,
				Default = defLabel,
				Callback = function(val) equipRoModSkin(spec.kind, val) end,
			})
		end
	else
		installCdSkinHooks()
		if MOD_SKIN.unlocked then applyCdSkinState() end

		local function formatCdLabel(item: any): string
			local base = tostring(item.name or item.id)
			if item.vip or item.rarity == "vip" then
				return string.format("%s (VIP) [%s]", base, tostring(item.id))
			elseif item.rarity == "epic" then
				return string.format("%s (EPIC) [%s]", base, tostring(item.id))
			elseif item.rarity == "gift" then
				return string.format("%s (GIFT) [%s]", base, tostring(item.id))
			end
			return string.format("%s [%s]", base, tostring(item.id))
		end

		local function getCdSkinOptions(cat: string): ({ string }, { [string]: string }, string)
			local opts = {}
			local idToLabel = {}
			local prog = GameCtx and GameCtx.profile and GameCtx.profile.progress
			local curId = MOD_SKIN.eq[cat]
				or (prog and prog.equipped and prog.equipped[cat])
				or (CdCosmetics.DEFAULTS and CdCosmetics.DEFAULTS[cat])
				or ""
			for _, item in ipairs(CdCosmetics[cat] or {}) do
				local lbl = formatCdLabel(item)
				table.insert(opts, lbl)
				idToLabel[item.id] = lbl
			end
			return opts, idToLabel, idToLabel[curId] or opts[1] or ""
		end

		syncSkinDropdownsCb = function()
			suppressSkinCb = true
			local prog = GameCtx and GameCtx.profile and GameCtx.profile.progress
			local eq = (type(prog) == "table" and prog.equipped) or MOD_SKIN.eq
			for cat, dd in pairs(skinDropdowns) do
				local _, idToLabel = getCdSkinOptions(cat)
				local targetId = MOD_SKIN.eq[cat] or (eq and eq[cat])
				if targetId and idToLabel[targetId] and type(dd.Set) == "function" then
					pcall(dd.Set, dd, idToLabel[targetId])
				end
			end
			suppressSkinCb = false
		end

		local function equipCdModSkin(cat: string, choiceLabel: string)
			if suppressSkinCb then return end
			local id = string.match(choiceLabel, "%[([^%]]+)%]$")
			if not id then return end
			if not MOD_SKIN.unlocked then
				MOD_SKIN.unlocked = true
				if skinUnlockToggle and type(skinUnlockToggle.Set) == "function" then
					suppressSkinCb = true
					pcall(skinUnlockToggle.Set, skinUnlockToggle, true)
					suppressSkinCb = false
				end
			end
			MOD_SKIN.eq[cat] = id
			applyCdSkinState()
			saveSessionState()
		end

		local totalCd = countTotalCdSkins()
		skinUnlockToggle = SkinTab:CreateToggle({
			Name = string.format("Unlock All Skins (%d/%d)", totalCd, totalCd),
			Default = MOD_SKIN.unlocked,
			Callback = function(v)
				if suppressSkinCb then return end
				MOD_SKIN.unlocked = v
				if not v then table.clear(MOD_SKIN.eq) end
				applyCdSkinState()
				if syncSkinDropdownsCb then syncSkinDropdownsCb() end
				saveSessionState()
				safeNotify({
					Title = "Skin Mod",
					Content = v and "All ChessDuels skins unlocked!" or "Restored real skins.",
					Duration = 2,
					Type = v and "Success" or "Info",
				})
			end,
		})

		SkinTab:CreateButton({
			Name = "Reset Real Skins",
			Callback = function()
				MOD_SKIN.unlocked = false
				table.clear(MOD_SKIN.eq)
				if skinUnlockToggle and type(skinUnlockToggle.Set) == "function" then
					suppressSkinCb = true
					pcall(skinUnlockToggle.Set, skinUnlockToggle, false)
					suppressSkinCb = false
				end
				applyCdSkinState()
				local real = snapshotRealCdSkins()
				if real and real.equipped then
					suppressSkinCb = true
					for cat, dd in pairs(skinDropdowns) do
						local _, idToLabel = getCdSkinOptions(cat)
						local realId = real.equipped[cat]
						if realId and idToLabel[realId] and type(dd.Set) == "function" then
							pcall(dd.Set, dd, idToLabel[realId])
						end
					end
					suppressSkinCb = false
				end
				saveSessionState()
				safeNotify({ Title = "Skin Mod", Content = "Restored original skins.", Duration = 2, Type = "Info" })
			end,
		})

		SkinTab:CreateSection("Quick Equip")
		for _, spec in ipairs({
			{ kind = "boards", title = "Board Theme" },
			{ kind = "pieces", title = "Piece Style" },
			{ kind = "highlights", title = "Highlight Color" },
			{ kind = "trails", title = "Move Trail" },
			{ kind = "captures", title = "Capture Effect" },
			{ kind = "frames", title = "Avatar Frame" },
		}) do
			local opts, _, defLabel = getCdSkinOptions(spec.kind)
			skinDropdowns[spec.kind] = SkinTab:CreateDropdown({
				Name = spec.title,
				Mode = "Inline",
				Options = opts,
				Default = defLabel,
				Callback = function(val) equipCdModSkin(spec.kind, val) end,
			})
		end
	end

	local ConfigTab = Window:CreateTab({ Name = "Config", Description = "System & Tools" })
	ConfigTab:CreateSection("Preferences")
	ConfigTab:CreateToggle({ Name = "Notify Hints", Default = CFG.NotifyHints, Callback = function(v) CFG.NotifyHints = v; saveSessionState() end })
	ConfigTab:CreateToggle({
		Name = "Hide Name (SonHub Hidden)",
		Default = CFG.HideName,
		Callback = function(v)
			CFG.HideName = v
			if v then installNameShield() end
			saveSessionState()
		end,
	})

	ConfigTab:CreateSection("Maintenance")
	ConfigTab:CreateButton({
		Name = "Rescan Board",
		Callback = function()
			scanControllers(true)
			if not IS_ROCHESS then installCdSkinHooks() end
			refreshGoalsUI()
			local snap = getStateSnapshot()
			safeNotify({
				Title = snap and "Board Ready" or "No Board",
				Content = snap and string.format("%s (%s) | Legal %d", gameTitle, getCurrentMode(), #snap.legalMoves) or "Profile refreshed.",
				Duration = 2,
				Type = "Info",
			})
		end,
	})
	ConfigTab:CreateButton({
		Name = "Clear Cache",
		Callback = function()
			table.clear(evalCache)
			table.clear(cacheOrder)
			moveLensCooldownUntil = 0
			chessApiCooldownUntil = 0
			lastHintFen = nil
			lastAutoFen = nil
			lastBoardKey = nil
			clearHint()
			safeNotify({ Title = "Cleared", Content = "Cache & hint cleared.", Duration = 2, Type = "Info" })
		end,
	})

	hardenSonUi()
else
	warn("[SonChess] SonLibrary unavailable")
end

table.insert(connections, lp.OnTeleport:Connect(function(state)
	if not alive then return end
	if state == Enum.TeleportState.Started then
		saveSessionState(true)
		if type(queueOnTeleportFn) == "function" and type(env.SonChessReloadCode) == "string" and #env.SonChessReloadCode > 0 then
			pcall(queueOnTeleportFn, env.SonChessReloadCode)
		end
	end
end))

table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not alive then return end
	if input.KeyCode == Enum.KeyCode.H then
		triggerHintAsync(true)
	elseif input.KeyCode == Enum.KeyCode.P then
		local nextVal = not CFG.AutoPlayEnabled
		ensureAutoPlay(nextVal)
		safeNotify({ Title = "AutoPlay", Content = nextVal and "ON" or "OFF", Duration = 1.8, Type = nextVal and "Success" or "Warning" })
	end
end))

env.SonChessCleanup = function()
	alive = false
	stopAllAutomation()
	CFG.AutoPlayEnabled = false
	for _, conn in ipairs(connections) do pcall(conn.Disconnect, conn) end
	table.clear(connections)
	for _, conn in ipairs(nameShieldConns) do pcall(conn.Disconnect, conn) end
	table.clear(nameShieldConns)
	table.clear(paraCache)
	clearHint()

	if IS_ROCHESS then
		MOD_SKIN.unlocked = false
		table.clear(MOD_SKIN.eq)
		applyRoSkinState()
		if env._RoChessOrigRender and App then App.render = env._RoChessOrigRender end
		if env._RoChessOrigSetPos and RoBoardView then RoBoardView.setPosition = env._RoChessOrigSetPos end
		if env._RoChessOrigSetFlip and RoBoardView then RoBoardView.setFlipped = env._RoChessOrigSetFlip end
		if env._RoOrigOwns and App then App.owns = env._RoOrigOwns end
		if env._RoOrigSetCos and App then App.setCos = env._RoOrigSetCos end
		if env._RoOrigRequest and App then App.request = env._RoOrigRequest end
	else
		MOD_SKIN.unlocked = false
		env._CdSkinActive = false
		env._CdEquipInterceptor = nil
		table.clear(MOD_SKIN.eq)
		applyCdSkinState()
		if env._CdOrigShow and CdBoardView then CdBoardView.show = env._CdOrigShow end
		if env._CdOrigSetLegal and CdBoardView then CdBoardView.setLegal = env._CdOrigSetLegal end
		if env._CdOrigSetFlip and CdBoardView then CdBoardView.setFlipped = env._CdOrigSetFlip end
		if env._CdOrigSetPieceSet and CdBoardView then CdBoardView.setPieceSet = env._CdOrigSetPieceSet end
		if env._CdOrigOnProfile and GameCtx then GameCtx.onProfile = env._CdOrigOnProfile end
		if env._CdOrigPreviewBoard and GameCtx then GameCtx.previewBoard = env._CdOrigPreviewBoard end
		if env._CdOrigGameApply and GameViewInst then GameViewInst.apply = env._CdOrigGameApply end
	end

	if Window and type(Window.Destroy) == "function" then
		pcall(Window.Destroy, Window)
	end
end

installNameShield()
scanControllers(true)
if not IS_ROCHESS then
	installCdSkinHooks()
	if MOD_SKIN.unlocked then applyCdSkinState() end
end
refreshGoalsUI()

if type(savedResumeState) == "table"
	and savedResumeState.gameId == game.GameId
	and (os.time() - (tonumber(savedResumeState.ts) or 0)) <= 180
then
	if savedResumeState.quest then
		if AutoQuestToggleCtrl and type(AutoQuestToggleCtrl.Set) == "function" then
			pcall(AutoQuestToggleCtrl.Set, AutoQuestToggleCtrl, true)
		else
			startSmartAutoQuest()
		end
	elseif savedResumeState.farm then
		if type(savedResumeState.farmTarget) == "string" then
			CFG.QuickFarmTarget = savedResumeState.farmTarget
		end
		if QuickFarmToggleCtrl and type(QuickFarmToggleCtrl.Set) == "function" then
			pcall(QuickFarmToggleCtrl.Set, QuickFarmToggleCtrl, true)
		else
			startQuickFarm()
		end
	elseif savedResumeState.autoplay then
		ensureAutoPlay(true)
	end
end

if isMyTurn() and CFG.LiveHint and CFG.HintEnabled then
	triggerHintAsync(false)
end

task.spawn(function()
	elevateIdentity()
	while alive do
		task.wait(3.0)
		if not alive then break end
		pcall(refreshGoalsUI)
		if not IS_ROCHESS and not GameViewInst then
			scanControllers(false)
			if GameViewInst then installCdSkinHooks() end
		end
		if not isBoardVisible() then
			local prev = BoardViewInstance
			scanControllers(false)
			if BoardViewInstance and BoardViewInstance ~= prev then
				onBoardUpdated()
			end
		elseif hintGui and not hintGui.Parent then
			hintGui = nil
		end
	end
end)

print(string.format("[SonChess v6.3] Ready (%s)", IS_ROCHESS and "RoChess" or "ChessDuels"))
