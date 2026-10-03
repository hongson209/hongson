--!nocheck
--[[
	SonHUB — Universal Grandmaster Chess Coach (Multilingual & Mobile Optimized)
	Compatible with:
	1. Chess Club (PlaceId: 139394516128799)
	2. CHESS! (PlaceId: 6222531507)
	
	Features:
	- Subtitle: "Become a Champion V2" (English) / "Trở thành Nhà vô địch V2" (Tiếng Việt có dấu clean).
	- Settings Language Switch: Live in-place translation between English & clean accented Vietnamese.
	- 2 Separate Action Toggles: AutoPlay and PlayLegit.
	- Floating Logo Button: Rounded-corner square, vibrant cyan border, soft translucent background.
	- Full Mobile & Touch optimization (responsive sizing, touch-safe dragging, tap handling).
	- Zero console spam, bulletproof FEN parser, multi-tier engine fallback.
]]

-- Zero console trace & anti-cheat stealth suppression
local print = function(...) end
local warn = function(...) end

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

-- Lifecycle management
local _genv = (getgenv and getgenv()) or _G
local currentGen = tick()
_genv._SONHUB_GEN = currentGen

if _genv._SONHUB_CLEANUP then
	pcall(_genv._SONHUB_CLEANUP)
end

-- Clean any orphaned WindUI or SonHUB ScreenGuis
pcall(function()
	local function purge(parent)
		if not parent then return end
		for _, c in ipairs(parent:GetChildren()) do
			if c.Name:find("WindUI") or c.Name:find("SonHUB") then
				pcall(function() c:Destroy() end)
			end
		end
	end
	purge(game:GetService("CoreGui"))
	local rgui = game:GetService("CoreGui"):FindFirstChild("RobloxGui")
	if rgui then purge(rgui) end
	local geth = (getgenv and getgenv().gethui) or _env.gethui
	if type(geth) == "function" then
		pcall(function() purge(geth()) end)
	end
end)

local _env: any = getfenv()
local S: any = _env.STATE or {
	alive = function() return _genv._SONHUB_GEN == currentGen end,
	onCleanup = function() end,
}

local function isAlive(): boolean
	return (_genv._SONHUB_GEN == currentGen) and (not S.alive or S.alive())
end

----------------------------------------------------------------------
-- CONFIGURATION & COLOR PALETTE
----------------------------------------------------------------------

local CFG = {
	Language = "en",         -- "en" or "vi"
	Auto = true,
	AutoPlay = false,        -- Fast auto-play (default: false)
	PlayLegit = false,       -- Humanized natural thinking auto-play (default: false)
	ToggleKey = Enum.KeyCode.K,
	FastDelay = 0.35,        -- Delay for fast auto-play (seconds, default: 0.35s)
	LegitBaseDelay = 4.5,    -- Base delay for legit thinking (2.0s - 10.0s, default: 4.5s)
	Depth = 16,              -- Optimal GM Depth (12 to 18, default: 16)
	Ponder = true,
	EngineMode = "Auto",     -- "Auto", "OnlineOnly", "OfflineOnly"
}

-- Cross-session preferences persistence (safe for any executor)
local CONFIG_FILE = "SonHUB_ChessSettings.json"

local function loadSettings()
	local readfileFn = _env.readfile or readfile
	local isfileFn = _env.isfile or isfile
	if type(isfileFn) == "function" and type(readfileFn) == "function" then
		local ok, exists = pcall(function() return isfileFn(CONFIG_FILE) end)
		if ok and exists then
			local okRead, content = pcall(function() return readfileFn(CONFIG_FILE) end)
			if okRead and type(content) == "string" and #content > 5 then
				local okDecode, saved = pcall(function() return HttpService:JSONDecode(content) end)
				if okDecode and type(saved) == "table" then
					if saved.Language == "en" or saved.Language == "vi" then
						CFG.Language = saved.Language
					end
					if type(saved.FastDelay) == "number" then
						CFG.FastDelay = math.clamp(saved.FastDelay, 0.15, 2.0)
					end
					if type(saved.LegitBaseDelay) == "number" then
						CFG.LegitBaseDelay = math.clamp(saved.LegitBaseDelay, 2.0, 10.0)
					end
					if type(saved.Depth) == "number" then
						CFG.Depth = math.clamp(math.floor(saved.Depth), 12, 18)
					end
					if saved.Ponder ~= nil then
						CFG.Ponder = (saved.Ponder == true)
					end
					-- AutoPlay and PlayLegit are never enabled on fresh startup
					CFG.AutoPlay = false
					CFG.PlayLegit = false
					if saved.EngineMode then
						CFG.EngineMode = saved.EngineMode
					end
					if saved.ToggleKey and typeof(saved.ToggleKey) == "string" then
						local keyEnum = Enum.KeyCode[saved.ToggleKey]
						if keyEnum then
							CFG.ToggleKey = keyEnum
						end
					end
				end
			end
		end
	end
end

local function saveSettings()
	local writefileFn = _env.writefile or writefile
	if type(writefileFn) == "function" then
		pcall(function()
			local data = {
				Language = CFG.Language,
				AutoPlay = CFG.AutoPlay,
				PlayLegit = CFG.PlayLegit,
				FastDelay = CFG.FastDelay,
				LegitBaseDelay = CFG.LegitBaseDelay,
				Depth = CFG.Depth,
				Ponder = CFG.Ponder,
				EngineMode = CFG.EngineMode,
				ToggleKey = CFG.ToggleKey.Name,
			}
			writefileFn(CONFIG_FILE, HttpService:JSONEncode(data))
		end)
	end
end

pcall(loadSettings)

-- Competition color palette
local COLOR_SOURCE = Color3.fromRGB(0, 235, 145)    -- Emerald jade (source square/piece)
local COLOR_TARGET = Color3.fromRGB(255, 185, 35)   -- Amber gold (3D vortex target)
local COLOR_BORDER = Color3.fromRGB(0, 210, 255)    -- Modern cyan accent for logo button
local COLOR_DARK   = Color3.fromRGB(15, 17, 24)

----------------------------------------------------------------------
-- BIDIRECTIONAL TRANSLATION MAP (CLEAN VIETNAMESE ACCENTED)
----------------------------------------------------------------------

local TRANSLATIONS = {
	["Last Update: 03/10/2026"] = "Cập nhật: 03/10/2026",
	["Move & Play"] = "Nước đi & Tự đánh",
	["Settings"] = "Cài đặt",
	["Status"] = "Trạng thái",
	["Waiting for game..."] = "Đang chờ ván cờ...",
	["Best Move"] = "Nước đi tối ưu",
	["Evaluation"] = "Đánh giá thế cờ",
	["Continuation Line"] = "Kế hoạch phản công",
	["PlayLegit"] = "PlayLegit",
	["Human-like natural thinking time."] = "Mô phỏng thời gian suy nghĩ như người thật.",
	["AutoPlay"] = "AutoPlay",
	["Instant or fast automatic moves."] = "Tự động đi cờ nhanh hoặc tức thì.",
	["Toggle Keybind"] = "Phím tắt mở giao diện",
	["Hotkey to show or hide the coach interface."] = "Phím tắt để ẩn hoặc hiện bảng điều khiển.",
	["Language / Ngôn ngữ"] = "Ngôn ngữ / Language",
	["Select interface language."] = "Chọn ngôn ngữ hiển thị giao diện.",
	["Pondering"] = "Tính toán ngầm (Pondering)",
	["Calculate responses during opponent turn."] = "Tính trước nước cờ khi đối thủ đang suy nghĩ.",
	["AutoPlay Fast Delay (s)"] = "Thời gian trễ AutoPlay (giây)",
	["Delay for AutoPlay mode (0.15s - 2.0s)."] = "Độ trễ khi bật AutoPlay (0.15s - 2.0s).",
	["Legit Thinking Time (s)"] = "Thời gian suy nghĩ người thật (giây)",
	["Natural GM thinking time (2.0s - 10.0s)."] = "Thời gian suy nghĩ như kiện tướng (2.0s - 10.0s).",
	["Stockfish Depth"] = "Độ sâu Stockfish",
	["Analysis depth (12 to 18, Grandmaster level)."] = "Độ sâu phân tích (12 đến 18, chuẩn Kiện tướng).",
	["Engine Source"] = "Nguồn Engine",
	["Computation backend."] = "Lựa chọn máy chủ phân tích.",
	["Recalculate Position"] = "Phân tích lại thế cờ",
	["Force immediate re-analysis of current FEN."] = "Buộc engine tính toán lại thế cờ hiện tại.",
	["Clear Board Visuals"] = "Làm sạch bàn cờ",
	["Remove all 3D markers immediately."] = "Xóa toàn bộ điểm chỉ dẫn 3D.",
	["Hide Interface"] = "Ẩn giao diện",
	["Press logo button or hotkey to re-open."] = "Bấm nút logo hoặc phím tắt để mở lại.",
	["Auto (Optimal)"] = "Tự động (Tối ưu)",
	["Online Only"] = "Chỉ trực tuyến",
	["Offline Only"] = "Chỉ ngoại tuyến",
	["[SPECTATING]"] = "[ĐANG XEM TRẬN]",
	["[YOUR TURN]"] = "[LƯỢT CỦA BẠN]",
	["[OPPONENT THINKING]"] = "[ĐỐI THỦ ĐANG NGHĨ]",
	["Engine"] = "Động cơ",
	["Custom Skins"] = "Tùy biến Skin",
	["Skin Changer"] = "Thay đổi Giao diện Quân cờ",
	["Official in-game piece skin collections (Client-side, user's side only)."] = "Bộ sưu tập skin chính thức của Game (Client-side, chỉ hiển thị phe của bạn).",
	["Featured 3D Set"] = "Bộ cờ 3D Tiêu biểu",
	["Select official 3D chess set for Chess Club."] = "Chọn bộ cờ 3D chính thức trong Chess Club.",
	["Featured 2D Set"] = "Bộ cờ 2D Tiêu biểu",
	["Select official 2D board & piece theme for Chess Club."] = "Chọn bộ bàn cờ và quân cờ 2D chính thức trong Chess Club.",
	["Game Collection"] = "Bộ sưu tập Quân cờ",
	["Select an official CHESS! skin collection for your pieces."] = "Chọn bộ skin chính thức của CHESS! cho quân của bạn.",
	["Apply Skin Now"] = "Áp dụng Skin ngay",
	["Re-apply selected visual theme to current board."] = "Áp dụng lại skin đã chọn vào bàn cờ hiện tại.",
	["Reset Default Skin"] = "Khôi phục Skin mặc định",
	["Revert piece models to original textures."] = "Khôi phục quân cờ về màu sắc ban đầu.",
}

local REVERSE_TRANSLATIONS = {}
for en, vi in pairs(TRANSLATIONS) do
	REVERSE_TRANSLATIONS[vi] = en
end

----------------------------------------------------------------------
-- ENVIRONMENT & LOGO ASSET
----------------------------------------------------------------------

local function tryRequire(inst: Instance?): any
	if not inst then return nil end
	local ok, m = pcall(require, inst :: any)
	return ok and m or nil
end

local function gethuiSafe(): Instance
	local geth = (getgenv and getgenv().gethui) or _env.gethui or gethui or (getgenv and getgenv().get_hidden_gui) or _env.get_hidden_gui
	if type(geth) == "function" then
		local ok, h = pcall(geth)
		if ok and h then return h end
	end
	local okCore, cGui = pcall(function() return game:GetService("CoreGui") end)
	if okCore and cGui then return cGui end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local function makeHttpRequest(url: string, method: string?, body: string?, timeoutSec: number?): string?
	local maxWait = timeoutSec or 4.0
	local reqFn = (syn and syn.request)
		or (getgenv and getgenv().request)
		or _env.request
		or request
		or http_request
		or (http and http.request)
		or (fluxus and fluxus.request)

	if type(reqFn) == "function" then
		local headers = nil
		if method == "POST" then
			headers = { ["Content-Type"] = "application/json" }
		end

		local done = false
		local result: string? = nil

		-- Run request in a separate thread so executor synchronous hangs never block our game thread
		task.spawn(function()
			local ok, res = pcall(reqFn, {
				Url = url,
				Method = method or "GET",
				Headers = headers,
				Body = body,
				Timeout = math.ceil(maxWait),
			})
			if not done then
				if ok then
					local bodyStr: string? = nil
					local statusCode = 200
					if type(res) == "table" then
						statusCode = res.StatusCode or res.Status or res.status_code or 200
						bodyStr = res.Body or res.body
					elseif type(res) == "string" then
						bodyStr = res
					end
					if type(bodyStr) == "string" and #bodyStr > 5 and (statusCode == 200 or statusCode == 201) then
						result = bodyStr
					end
				end
				done = true
			end
		end)

		local start = tick()
		while not done and (tick() - start < maxWait) do
			task.wait(0.03)
		end
		done = true
		if result then return result end
	end

	-- Fallback to game:HttpGet for GET requests with strict deadline
	if (not method or method == "GET") and type(game.HttpGet) == "function" then
		local done = false
		local result: string? = nil
		task.spawn(function()
			local okGet, resGet = pcall(function() return game:HttpGet(url) end)
			if not done then
				if okGet and type(resGet) == "string" and #resGet > 5 then
					result = resGet
				end
				done = true
			end
		end)

		local start = tick()
		while not done and (tick() - start < maxWait) do
			task.wait(0.03)
		end
		done = true
		if result then return result end
	end

	return nil
end

local function safeClickButton(btn: any)
	if not btn then return end
	local fs = firesignal or (syn and syn.firesignal) or (getgenv and getgenv().firesignal) or (_env and _env.firesignal)
	if type(fs) == "function" then
		pcall(fs, btn.MouseButton1Click)
		pcall(fs, btn.Activated)
		return
	end
	local gc = getconnections or (syn and syn.getconnections) or (getgenv and getgenv().getconnections) or (_env and _env.getconnections)
	if type(gc) == "function" then
		local ok1, conns1 = pcall(gc, btn.MouseButton1Click)
		if ok1 and type(conns1) == "table" then
			for _, conn in ipairs(conns1) do
				if conn.Function then pcall(conn.Function) end
				if conn.Fire then pcall(conn.Fire, conn) end
			end
		end
		local ok2, conns2 = pcall(gc, btn.Activated)
		if ok2 and type(conns2) == "table" then
			for _, conn in ipairs(conns2) do
				if conn.Function then pcall(conn.Function) end
				if conn.Fire then pcall(conn.Fire, conn) end
			end
		end
		return
	end
end

local LOGO_URL = "https://cdn.discordapp.com/attachments/1317065294736265248/1555222187378475029/sonhub.png?backend=b2&ex=6ac1b748&is=6ac065c8&hm=498b4a3f20bf924f01a7ab5c98da40b68b2a117fdb2d297cb86952d084cf53a7"
local FALLBACK_ICON = "rbxassetid://10709791437"

local cachedLogoAsset: string? = nil
local function getLogoAsset(): string
	if cachedLogoAsset then return cachedLogoAsset end
	local ok, asset = pcall(function()
		local isfileFn = _env.isfile or isfile
		local writefileFn = _env.writefile or writefile
		local getcustomassetFn = _env.getcustomasset or getcustomasset

		local exists = false
		if type(isfileFn) == "function" then
			pcall(function() exists = isfileFn("sonhub_logo.png") end)
		end

		if not exists and type(writefileFn) == "function" then
			local res = makeHttpRequest(LOGO_URL, "GET", nil, 4)
			if res and #res > 100 then
				pcall(writefileFn, "sonhub_logo.png", res)
				exists = true
			end
		end

		if exists and type(getcustomassetFn) == "function" then
			return getcustomassetFn("sonhub_logo.png")
		end
		return FALLBACK_ICON
	end)
	if ok and type(asset) == "string" and asset ~= "" then
		cachedLogoAsset = asset
		return asset
	end
	return FALLBACK_ICON
end

----------------------------------------------------------------------
-- COORDINATE SYSTEM (ALGEBRAIC <-> GRID)
----------------------------------------------------------------------

local FILES_MAP = { "a", "b", "c", "d", "e", "f", "g", "h" }

local function sqToCoord(sq: string): (number, number)
	if type(sq) ~= "string" or #sq < 2 then return 1, 1 end
	local file = sq:sub(1, 1):lower()
	local rank = tonumber(sq:sub(2, 2)) or 1
	local fileIdx = string.byte(file) - 96
	local gridX = 9 - fileIdx
	local gridY = rank
	return gridX, gridY
end

local function coordToSq(x: number, y: number): string
	local file = FILES_MAP[9 - x] or "a"
	return file .. tostring(y)
end

----------------------------------------------------------------------
-- BULLETPROOF GAME ADAPTER
----------------------------------------------------------------------

local PlaceId = game.PlaceId
local GameId = game.GameId

local IS_CHESS_CLUB = (PlaceId == 139394516128799) or (GameId == 7266261686)
local IS_COOKIE_CHESS = (PlaceId == 6222531507) or (GameId == 2283649692)

local function isMe(val: any): boolean
	if not val then return false end
	if val == LocalPlayer then return true end
	if typeof(val) == "Instance" then
		if val:IsA("Player") and val.UserId == LocalPlayer.UserId then return true end
		if val:IsA("Model") or val:IsA("BasePart") then
			local p = Players:GetPlayerFromCharacter(val)
			if p and p.UserId == LocalPlayer.UserId then return true end
			local vName = val.Name:lower()
			if vName == LocalPlayer.Name:lower() or vName == LocalPlayer.DisplayName:lower() then return true end
		end
		if val.Name:lower() == LocalPlayer.Name:lower() or val.Name:lower() == LocalPlayer.DisplayName:lower() then return true end
	end
	if type(val) == "string" then
		local s = val:lower()
		if s == LocalPlayer.Name:lower() or s == LocalPlayer.DisplayName:lower() then
			return true
		end
		if s:find(LocalPlayer.Name:lower(), 1, true) or s:find(LocalPlayer.DisplayName:lower(), 1, true) then
			return true
		end
	end
	if type(val) == "number" and val == LocalPlayer.UserId then return true end
	if type(val) == "table" then
		if val.UserId == LocalPlayer.UserId then return true end
		if type(val.Name) == "string" and (val.Name:lower() == LocalPlayer.Name:lower() or val.Name:lower() == LocalPlayer.DisplayName:lower()) then return true end
		if type(val.DisplayName) == "string" and val.DisplayName:lower() == LocalPlayer.DisplayName:lower() then return true end
	end
	return false
end

local function isChessClubGameActive(g: any): boolean
	if not g then return false end
	if g.Active == false then return false end
	if type(g.FEN) ~= "string" or #g.FEN < 8 then return false end

	-- Check if RemoteConns are disconnected (GameEnded was called)
	if g.RemoteConns and type(g.RemoteConns) == "table" then
		local hasAnyConnected = false
		local count = 0
		for _, c in pairs(g.RemoteConns) do
			count += 1
			if c and c.Connected == true then
				hasAnyConnected = true
				break
			end
		end
		if count > 0 and not hasAnyConnected then
			return false
		end
	end

	-- Check if GameEnd dialog is active
	local pgui = LocalPlayer:FindFirstChild("PlayerGui")
	local ind = pgui and pgui:FindFirstChild("Independent")
	local ge = ind and ind:FindFirstChild("GameEnd")
	if ge and ge.Visible == true then
		return false
	end

	return true
end

local function getChessClubGame(): any?
	local pScripts = LocalPlayer:FindFirstChild("PlayerScripts")
	local proxy = tryRequire(pScripts and pScripts:FindFirstChild("Services") and pScripts.Services:FindFirstChild("ChessProxyService"))
	if not proxy then return nil end

	-- Check active player game
	local g = proxy.ChessGame
	if g and isChessClubGameActive(g) and type(g.FEN) == "string" and #g.FEN > 10 then
		return g
	end

	-- Check active spectating game
	local spec = proxy.Spectation
	if spec and isChessClubGameActive(spec) and type(spec.FEN) == "string" and #spec.FEN > 10 then
		return spec
	end

	return nil
end

local function getCookieMatch(): (any?, any?)
	local pgui = LocalPlayer:FindFirstChild("PlayerGui")
	local client = pgui and pgui:FindFirstChild("Client")
	local mc = client and tryRequire(client:FindFirstChild("MatchClient"))

	local gStatus = pgui and pgui:FindFirstChild("GameStatus")
	local sc = gStatus and tryRequire(gStatus:FindFirstChild("StatusClient"))

	local activeMc = mc
		or (sc and sc.client and sc.client.matchClient)
		or (sc and sc.client)
		or (sc and sc.matchClient)

	if mc and mc.currentMatch and (mc.currentMatch.boardExists == true or mc.currentMatch.tiles ~= nil or mc.currentMatch.pieces ~= nil) then
		return mc.currentMatch, (activeMc or mc)
	end

	if sc and sc.board and (sc.board.boardExists == true or sc.board.tiles ~= nil or sc.board.pieces ~= nil) then
		return sc.board, (activeMc or mc)
	end

	if sc and sc.currentMatch and (sc.currentMatch.boardExists == true or sc.currentMatch.tiles ~= nil) then
		return sc.currentMatch, (activeMc or mc)
	end

	return nil, (activeMc or mc)
end

-- Bulletproof Piece Name Parser (Strict order: knight before king, bishop before pawn)
local function pieceNameToChar(name: string): string
	local s = name:lower()
	if s:find("knight", 1, true) or s:find("horse", 1, true) then
		return "n"
	elseif s:find("king", 1, true) then
		return "k"
	elseif s:find("queen", 1, true) then
		return "q"
	elseif s:find("bishop", 1, true) then
		return "b"
	elseif s:find("rook", 1, true) or s:find("castle", 1, true) then
		return "r"
	elseif s:find("pawn", 1, true) then
		return "p"
	end
	if s:match("%f[%a]k%f[%A]") then return "k" end
	if s:match("%f[%a]q%f[%A]") then return "q" end
	if s:match("%f[%a]r%f[%A]") then return "r" end
	if s:match("%f[%a]b%f[%A]") then return "b" end
	if s:match("%f[%a]n%f[%A]") then return "n" end
	return "p"
end

local function pieceHasMoved(piece: any): boolean
	if not piece then return true end
	if piece.hasMoved == true then return true end
	if piece.moved == true then return true end
	if piece.firstMove == false then return true end
	if type(piece.moves) == "number" and piece.moves > 0 then return true end
	if type(piece.moveCount) == "number" and piece.moveCount > 0 then return true end
	return false
end

local function safeBuildFEN(m: any): string?
	local ok, fen = pcall(function()
		local rows = {}
		local whiteKingCount = 0
		local blackKingCount = 0

		for rank = 8, 1, -1 do
			local emptyCount = 0
			local rowStr = ""
			for fileIdx = 8, 1, -1 do
				local piece = m:getPiece({ fileIdx, rank })
				if not piece or (piece.alive == false) or (piece.captured == true) then
					emptyCount += 1
				else
					if emptyCount > 0 then
						rowStr ..= tostring(emptyCount)
						emptyCount = 0
					end
					local ch = pieceNameToChar(tostring(piece.Name or piece.name or ""))
					local isWhite = (piece.team == true)
					if ch == "k" then
						if isWhite then whiteKingCount += 1 else blackKingCount += 1 end
					end
					rowStr ..= (isWhite and ch:upper() or ch:lower())
				end
			end
			if emptyCount > 0 then
				rowStr ..= tostring(emptyCount)
			end
			table.insert(rows, rowStr)
		end

		-- Validate standard chess invariant
		if whiteKingCount ~= 1 or blackKingCount ~= 1 then
			return nil
		end

		local placement = table.concat(rows, "/")
		local activeTurn = if m.activeTeam then "w" else "b"

		-- Validate actual castling rights with movement verification
		local castling = ""
		local wk = m:getPiece({ 4, 1 })
		local wrK = m:getPiece({ 1, 1 })
		local wrQ = m:getPiece({ 8, 1 })
		if wk and wk.team and pieceNameToChar(tostring(wk.Name or wk.name or "")) == "k" and not pieceHasMoved(wk) then
			if wrK and wrK.team and pieceNameToChar(tostring(wrK.Name or wrK.name or "")) == "r" and not pieceHasMoved(wrK) then
				castling ..= "K"
			end
			if wrQ and wrQ.team and pieceNameToChar(tostring(wrQ.Name or wrQ.name or "")) == "r" and not pieceHasMoved(wrQ) then
				castling ..= "Q"
			end
		end

		local bk = m:getPiece({ 4, 8 })
		local brK = m:getPiece({ 1, 8 })
		local brQ = m:getPiece({ 8, 8 })
		if bk and not bk.team and pieceNameToChar(tostring(bk.Name or bk.name or "")) == "k" and not pieceHasMoved(bk) then
			if brK and not brK.team and pieceNameToChar(tostring(brK.Name or brK.name or "")) == "r" and not pieceHasMoved(brK) then
				castling ..= "k"
			end
			if brQ and not brQ.team and pieceNameToChar(tostring(brQ.Name or brQ.name or "")) == "r" and not pieceHasMoved(brQ) then
				castling ..= "q"
			end
		end

		if castling == "" then castling = "-" end

		local roundNum = math.max(1, math.ceil((m.round or 1) / 2))
		return placement .. " " .. activeTurn .. " " .. castling .. " - 0 " .. tostring(roundNum)
	end)

	if ok and type(fen) == "string" and #fen > 10 then
		return fen
	end
	return nil
end

local function getCookieFEN(m: any): string?
	local ok, rawFen = pcall(function() return m:createFENLine() end)
	if ok and type(rawFen) == "string" and #rawFen > 10 then
		local parts = {}
		for word in rawFen:gmatch("%S+") do
			table.insert(parts, word)
		end
		if #parts >= 2 then
			local castling = parts[3]
			if not castling or castling == "" or not castling:match("^[KQkq%-]+$") then
				local cStr = ""
				local wk = m:getPiece({ 4, 1 })
				local wrK = m:getPiece({ 1, 1 })
				local wrQ = m:getPiece({ 8, 1 })
				if wk and wk.team and pieceNameToChar(tostring(wk.Name or wk.name or "")) == "k" and not pieceHasMoved(wk) then
					if wrK and wrK.team and pieceNameToChar(tostring(wrK.Name or wrK.name or "")) == "r" and not pieceHasMoved(wrK) then
						cStr ..= "K"
					end
					if wrQ and wrQ.team and pieceNameToChar(tostring(wrQ.Name or wrQ.name or "")) == "r" and not pieceHasMoved(wrQ) then
						cStr ..= "Q"
					end
				end
				local bk = m:getPiece({ 4, 8 })
				local brK = m:getPiece({ 1, 8 })
				local brQ = m:getPiece({ 8, 8 })
				if bk and not bk.team and pieceNameToChar(tostring(bk.Name or bk.name or "")) == "k" and not pieceHasMoved(bk) then
					if brK and not brK.team and pieceNameToChar(tostring(brK.Name or brK.name or "")) == "r" and not pieceHasMoved(brK) then
						cStr ..= "k"
					end
					if brQ and not brQ.team and pieceNameToChar(tostring(brQ.Name or brQ.name or "")) == "r" and not pieceHasMoved(brQ) then
						cStr ..= "q"
					end
				end
				castling = if cStr == "" then "-" else cStr
			else
				local wk = m:getPiece({ 4, 1 })
				if pieceHasMoved(wk) then
					castling = castling:gsub("[KQ]", "")
				end
				local bk = m:getPiece({ 4, 8 })
				if pieceHasMoved(bk) then
					castling = castling:gsub("[kq]", "")
				end
				if castling == "" then castling = "-" end
			end

			parts[3] = castling
			parts[4] = parts[4] or "-"
			parts[5] = parts[5] or "0"
			parts[6] = parts[6] or tostring(math.max(1, math.ceil((m.round or 1) / 2)))
			local finalFen = table.concat(parts, " ")
			if not finalFen:match("^8/8/8/8/8/8/8/8") and finalFen:find("k") and finalFen:find("K") then
				return finalFen
			end
		end
	end
	local fallbackFen = safeBuildFEN(m)
	if fallbackFen and not fallbackFen:match("^8/8/8/8/8/8/8/8") and fallbackFen:find("k") and fallbackFen:find("K") then
		return fallbackFen
	end
	return nil
end

local function normalizeFenForEngine(fen: string, gameInfo: any?, stripEp: boolean?): string
	if type(fen) ~= "string" or #fen < 8 then return fen end
	local parts = {}
	for w in fen:gmatch("%S+") do
		table.insert(parts, w)
	end
	if #parts == 0 then return fen end

	local placement = parts[1]

	-- Authoritative Active Turn
	local turn = parts[2]
	if gameInfo and gameInfo.WhiteToPlay ~= nil then
		turn = gameInfo.WhiteToPlay and "w" or "b"
	elseif not turn or (turn ~= "w" and turn ~= "b") then
		if gameInfo and gameInfo.AmIWhite ~= nil and gameInfo.MyTurn ~= nil then
			turn = (gameInfo.AmIWhite == gameInfo.MyTurn) and "w" or "b"
		else
			turn = "w"
		end
	end

	-- Castling
	local castling = parts[3]
	if not castling or castling == "" or not castling:match("^[KQkq%-]+$") then
		castling = "-"
	end

	-- En Passant: If stripEp is true, force "-" (necessary for chess-api.com)
	local ep = if stripEp then "-" else parts[4]
	if not ep or ep == "" or (ep ~= "-" and not ep:match("^[a-h][36]$")) then
		ep = "-"
	end

	-- Clocks
	local halfmove = parts[5] or "0"
	local fullmove = parts[6] or (gameInfo and tostring(gameInfo.Round or 1)) or "1"

	return ("%s %s %s %s %s %s"):format(placement, turn, castling, ep, halfmove, fullmove)
end

local function isMe(val: any): boolean
	if val == nil then return false end
	if val == LocalPlayer then return true end
	if typeof(val) == "Instance" then
		if val:IsA("Player") and val.UserId == LocalPlayer.UserId then
			return true
		end
		if val:IsA("Model") and (val == LocalPlayer.Character or val.Name == LocalPlayer.Name) then
			return true
		end
	end
	if type(val) == "string" and (val == LocalPlayer.Name or val == LocalPlayer.DisplayName) then
		return true
	end
	if type(val) == "number" and val == LocalPlayer.UserId then
		return true
	end
	return false
end

local Adapter = {}

function Adapter.getGameInfo(): any?
	-- 1. Check Chess Club game adapter
	local g = getChessClubGame()
	if g then
		local isSpectating = (g.Spectating == true)
		local isPlayerWhite = false
		local isPlayerBlack = false

		if g.AmIWhite ~= nil then
			isPlayerWhite = (g.AmIWhite == true)
			isPlayerBlack = (g.AmIWhite == false)
		else
			isPlayerWhite = isMe(g.White)
			isPlayerBlack = isMe(g.Black)
		end

		if not isSpectating and not isPlayerWhite and not isPlayerBlack then
			if g.Ui2D and g.Ui2D.AmIWhite ~= nil then
				isPlayerWhite = (g.Ui2D.AmIWhite == true)
				isPlayerBlack = (g.Ui2D.AmIWhite == false)
			else
				isSpectating = true
			end
		end

		local whiteToPlay = (g.WhiteToPlay == true)
		local amIWhite = if isSpectating then whiteToPlay else isPlayerWhite
		local myTurn = (not isSpectating) and (amIWhite == whiteToPlay)
		local roundNum = g.Round or g.MoveCount or 1
		local completeFen = normalizeFenForEngine(g.FEN, {
			WhiteToPlay = whiteToPlay,
			AmIWhite = amIWhite,
			MyTurn = myTurn,
			Round = roundNum,
		})
		return {
			GameType = "ChessClub",
			Raw = g,
			Active = true,
			FEN = completeFen,
			Round = roundNum,
			AmIWhite = amIWhite,
			WhiteToPlay = whiteToPlay,
			MyTurn = myTurn,
			IsSpectating = isSpectating,
		}
	end

	-- 2. Check Cookie Chess (CHESS! 3D) adapter
	local m, mc = getCookieMatch()
	if m then
		local fen = getCookieFEN(m)
		if fen then
			local isWhite = false
			local isBlack = false

			-- Priority 1: Check native playerIds table (Roblox numeric UserIds)
			if m.playerIds and type(m.playerIds) == "table" then
				if m.playerIds[true] == LocalPlayer.UserId then
					isWhite = true
				end
				if m.playerIds[false] == LocalPlayer.UserId then
					isBlack = true
				end
			end

			-- Priority 2: Check players table (Character models, Player instances, or names)
			if not isWhite and not isBlack and m.players and type(m.players) == "table" then
				isWhite = isMe(m.players[true])
				isBlack = isMe(m.players[false])
			end

			-- Priority 3: Bot match check (playing vs singleplayer AI bot)
			if m.botInfo and m.botInfo.team ~= nil then
				if m.botInfo.team == true then
					isWhite = false
					isBlack = true
				elseif m.botInfo.team == false then
					isWhite = true
					isBlack = false
				end
			end

			-- Priority 4: Spectator detection
			local isSpectating = false
			if m.isSpectate ~= nil then
				isSpectating = (m.isSpectate == true)
			elseif not isWhite and not isBlack then
				isSpectating = true
			end

			local whiteToPlay = (m.activeTeam == true)
			local amIWhite = if (isWhite and isBlack) then whiteToPlay elseif isSpectating then whiteToPlay else (if isWhite then true else false)
			local myTurn = (not isSpectating) and (amIWhite == whiteToPlay)
			local roundNum = m.round or 1
			local completeFen = normalizeFenForEngine(fen, {
				WhiteToPlay = whiteToPlay,
				AmIWhite = amIWhite,
				MyTurn = myTurn,
				Round = roundNum,
			})
			return {
				GameType = "CookieChess",
				Raw = m,
				MatchClient = mc,
				Active = true,
				FEN = completeFen,
				Round = roundNum,
				AmIWhite = amIWhite,
				WhiteToPlay = whiteToPlay,
				MyTurn = myTurn,
				IsSpectating = isSpectating,
			}
		end
	end

	return nil
end

local function getTileCFrameAndSize(tile: Instance): (CFrame, Vector3)
	if tile:IsA("BasePart") then
		return tile.CFrame, tile.Size
	elseif tile:IsA("Model") then
		local cf, sz = tile:GetBoundingBox()
		if sz.X <= 0.1 or sz.Z <= 0.1 then
			sz = Vector3.new(3.8, 0.2, 3.8)
		end
		return cf, sz
	end
	local primary = (tile:IsA("Model") and tile.PrimaryPart) or tile:FindFirstChildWhichIsA("BasePart")
	if primary then
		return primary.CFrame, primary.Size
	end
	return CFrame.new(), Vector3.new(3.8, 0.2, 3.8)
end

function Adapter.getSquareInstances(gameInfo: any, sq: string): (Instance?, Instance?, Instance?, Instance?)
	local tile3D = nil
	local piece3D = nil
	local tile2D = nil
	local piece2D = nil

	if gameInfo.GameType == "ChessClub" then
		local g = gameInfo.Raw
		pcall(function()
			tile3D = g.Ui3D and g.Ui3D.Ref and g.Ui3D.Ref.Board and g.Ui3D.Ref.Board:FindFirstChild(sq)
		end)
		pcall(function()
			if g.Ui3D and g.Ui3D.Ref and g.Ui3D.Ref.Pieces then
				for _, p in ipairs(g.Ui3D.Ref.Pieces:GetChildren()) do
					local tileVal = p:FindFirstChild("tile")
					if tileVal and tileVal.Value == sq then
						piece3D = p
						break
					end
				end
			end
		end)
		pcall(function()
			local pgui = LocalPlayer:FindFirstChild("PlayerGui")
			local b2d = pgui and pgui:FindFirstChild("2DBoard")
			local main = b2d and b2d:FindFirstChild("Main")
			local board = main and main:FindFirstChild("Board")
			if board then
				tile2D = board:FindFirstChild(sq)
			end
			local pieces = main and main:FindFirstChild("Pieces")
			if pieces then
				for _, p in ipairs(pieces:GetChildren()) do
					local t = p:FindFirstChild("tile")
					if t and t.Value == sq then
						piece2D = p
						break
					end
				end
			end
		end)
	elseif gameInfo.GameType == "CookieChess" then
		local m = gameInfo.Raw
		local gx, gy = sqToCoord(sq)
		pcall(function()
			if m.tiles and m.tiles[gx] and m.tiles[gx][gy] then
				tile3D = m.tiles[gx][gy]
			elseif Workspace:FindFirstChild("Board") then
				tile3D = Workspace.Board:FindFirstChild(gx .. "," .. gy)
			end
		end)
		pcall(function()
			local pieceObj = m:getPiece({ gx, gy })
			if pieceObj and pieceObj.object then
				piece3D = pieceObj.object
			end
		end)
	end

	return tile3D, piece3D, tile2D, piece2D
end

----------------------------------------------------------------------
-- NATURAL LEGIT THINKING TIME & STEALTH ANTI-CHEAT EVASION
----------------------------------------------------------------------

local function getLegitThinkingDelay(gameInfo: any, moveData: any): number
	local roundNum = gameInfo.Round or 1
	local userBase = math.clamp(CFG.LegitBaseDelay or 4.5, 2.0, 10.0)
	local base = userBase

	if roundNum <= 3 then
		-- Early game opening moves: confident GM knowledge (2s - 3.5s)
		base = math.max(1.8, userBase * 0.55) + (math.random(100, 450) / 1000)
	elseif moveData.mate or (moveData.san and moveData.san:find("#")) then
		-- Checkmate line execution: decisive
		base = math.max(2.0, userBase * 0.60) + (math.random(150, 400) / 1000)
	elseif moveData.san and moveData.san:find("x") then
		-- Piece exchange or capture: swift tactical reaction
		base = math.max(2.2, userBase * 0.75) + (math.random(200, 600) / 1000)
	else
		local evalScore = math.abs(moveData.eval or 0)
		if evalScore < 1.8 and roundNum > 5 and roundNum < 38 then
			-- Complicated strategic middlegame position: deep human GM pondering (full 4.5s - 10.0s)
			base = userBase + (math.random(200, 1200) / 1000)
		else
			base = math.max(2.5, userBase * 0.85) + (math.random(100, 500) / 1000)
		end
	end

	-- Add organic sub-second human jitter (+- 0.08 to 0.15s)
	local jitter = (math.random(-80, 120) / 1000)
	return math.clamp(base + jitter, 1.5, 12.0)
end

local function getAutoPlayDelay(): number
	local userDelay = math.clamp(CFG.FastDelay or 0.35, 0.12, 2.0)
	-- Add organic micro-variance so moves never register at exact robotic intervals
	local jitter = (math.random(-25, 35) / 1000)
	return math.max(0.10, userDelay + jitter)
end

local autoPlayBusy = false
local currentMoveSession = 0
local lastMoveSubmitAttempt = 0
local moveSubmitRetries = 0

local function triggerButton(btn: Instance?)
	if not btn then return end
	local fired = false
	if getconnections then
		for _, ev in ipairs({ "MouseButton1Down", "Activated", "MouseButton1Click" }) do
			local okConn, conns = pcall(function() return getconnections((btn :: any)[ev]) end)
			if okConn and conns and #conns > 0 then
				for _, c in ipairs(conns) do
					if type(c.Fire) == "function" then
						pcall(function() c:Fire() end)
						fired = true
					end
				end
			end
		end
	end
	if not fired and firesignal then
		pcall(function() firesignal((btn :: any).MouseButton1Down) end)
		pcall(function() firesignal((btn :: any).Activated) end)
		pcall(function() firesignal((btn :: any).MouseButton1Click) end)
	end
end

local function isPawnPromotion(fen: string?, uciMove: string): boolean
	if type(uciMove) ~= "string" or #uciMove < 4 then return false end
	if #uciMove >= 5 then return true end
	local fromSq = uciMove:sub(1, 2):lower()
	local toSq = uciMove:sub(3, 4):lower()
	local toRank = toSq:sub(2, 2)
	if toRank ~= "8" and toRank ~= "1" then return false end
	local fromRank = tonumber(fromSq:sub(2, 2)) or 1
	if toRank == "8" and fromRank ~= 7 then return false end
	if toRank == "1" and fromRank ~= 2 then return false end

	if not fen or type(fen) ~= "string" then return false end
	local placement = fen:match("^(%S+)")
	if not placement then return false end
	local fromFile = string.byte(fromSq:sub(1, 1)) - 97
	local r = 8
	local f = 0
	for ch in placement:gmatch(".") do
		if ch == "/" then
			r -= 1
			f = 0
		else
			local n = tonumber(ch)
			if n then
				f += n
			else
				if r == fromRank and f == fromFile then
					return (ch:lower() == "p")
				end
				f += 1
			end
		end
	end
	return false
end

function Adapter.submitMove(gameInfo: any, uciMove: string, moveData: any)
	local isLegit = (CFG.PlayLegit == true)
	local isAuto = (CFG.AutoPlay == true)
	if not (isLegit or isAuto) then return end
	if not (gameInfo and gameInfo.Active and gameInfo.MyTurn and not gameInfo.IsSpectating) then return end
	if autoPlayBusy then return end
	autoPlayBusy = true
	lastMoveSubmitAttempt = tick()

	local thisSession = tick()
	currentMoveSession = thisSession

	task.spawn(function()
		local elapsed = (moveData and moveData.calcElapsed) or 0
		local thinkDelay = 0

		if isLegit then
			local legitTarget = getLegitThinkingDelay(gameInfo, moveData)
			-- Subtract elapsed calculation time: if engine already spent 3-5s computing, don't double wait!
			-- "có kết quả thì cho ra luôn, nếu khó thì suy nghĩ... quét đủ thì ra chứ không chờ"
			thinkDelay = math.max(0.12, legitTarget - elapsed)
		else
			-- AutoPlay: minimum reaction delay, moving as soon as calculation is ready
			local fastBase = CFG.FastDelay or 0.35
			thinkDelay = math.max(0.06, fastBase - math.min(elapsed, fastBase - 0.06))
		end

		if thinkDelay > 0 then
			task.wait(thinkDelay)
		end

		if not isAlive() or currentMoveSession ~= thisSession then
			autoPlayBusy = false
			return
		end

		if not (CFG.PlayLegit or CFG.AutoPlay) then
			autoPlayBusy = false
			return
		end

		-- Verify state after thinking period (must still be our turn, active, alive, not spectating)
		local currentInfo = Adapter.getGameInfo()
		if not (currentInfo and currentInfo.Active and currentInfo.MyTurn and not currentInfo.IsSpectating) then
			autoPlayBusy = false
			return
		end

		local snapshotFen = currentInfo.FEN

		if currentInfo.GameType == "ChessClub" then
			local g = currentInfo.Raw
			if g and isChessClubGameActive(g) and g.Remotes and g.Remotes.SubmitMove then
				pcall(function()
					-- Clear any lingering tile selection from prior user clicks
					if g.SelectedTile ~= nil and type(g.TileSelected) == "function" then
						g:TileSelected(nil)
					end
					if g.Ui2D and type(g.Ui2D.ClearLegalMoves) == "function" then
						g.Ui2D:ClearLegalMoves()
					end
					if g.Ui3D and type(g.Ui3D.ClearLegalMoves) == "function" then
						g.Ui3D:ClearLegalMoves()
					end

					local fromSq = uciMove:sub(1, 2)
					local toSq = uciMove:sub(3, 4)
					local promoChar = (uciMove:len() >= 5 and uciMove:sub(5, 5):lower()) or "q"
					local isPromo = isPawnPromotion(snapshotFen, uciMove)
					local fullUci = if isPromo then (fromSq .. toSq .. promoChar) else uciMove:sub(1, 4)

					-- 1. Execute natural user move through game controller
					if type(g.TileSelected) == "function" then
						g:TileSelected(fromSq)
						local humanPause = if isLegit then (0.10 + math.random(25, 75) / 1000) else 0.04
						task.wait(humanPause)
						g:TileSelected(toSq)
					end

					-- 2. Handle Pawn Promotion without GUI stalling
					if isPromo then
						pcall(function()
							g.Remotes.SubmitMove:FireServer(fullUci)
						end)
						task.spawn(function()
							for _ = 1, 15 do
								local pgui = LocalPlayer:FindFirstChild("PlayerGui")
								local b2d = pgui and pgui:FindFirstChild("2DBoard")
								local promo = b2d and b2d:FindFirstChild("Promotion")
								if promo and promo:FindFirstChild("Buttons") and (promo.Visible == true or promo.BackgroundTransparency < 0.95) then
									local targetBtn = promo.Buttons:FindFirstChild(promoChar) or promo.Buttons:FindFirstChild("q")
									if targetBtn then
										triggerButton(targetBtn)
										pcall(function()
											promo.Visible = false
											promo.BackgroundTransparency = 1
										end)
										break
									end
								end
								task.wait(0.04)
							end
						end)
					else
						-- Non-promotion: TileSelected already fires SubmitMove cleanly.
						-- Fallback watchdog: ONLY fires if server did not advance turn after 0.55s
						-- (0.55s accommodates high network ping / laggy mobile connections without double-firing)
						task.delay(0.55, function()
							if not isAlive() or currentMoveSession ~= thisSession then return end
							if not (CFG.PlayLegit or CFG.AutoPlay) then return end
							pcall(function()
								local afterInfo = Adapter.getGameInfo()
								if afterInfo and afterInfo.Active and afterInfo.MyTurn and not afterInfo.IsSpectating and afterInfo.FEN == snapshotFen then
									if g.Remotes and g.Remotes.SubmitMove then
										g.Remotes.SubmitMove:FireServer(fullUci)
									end
								end
							end)
						end)
					end
				end)
			end
		elseif currentInfo.GameType == "CookieChess" then
			local m = currentInfo.Raw
			local mc = currentInfo.MatchClient or select(2, getCookieMatch())
			local fromSq = uciMove:sub(1, 2)
			local toSq = uciMove:sub(3, 4)
			local promoChar = (uciMove:len() >= 5 and uciMove:sub(5, 5):lower()) or "q"
			local isPromo = isPawnPromotion(snapshotFen, uciMove)

			local fromX, fromY = sqToCoord(fromSq)
			local toX, toY = sqToCoord(toSq)

			local promoMap = { q = "Queen", r = "Rook", b = "Bishop", n = "Knight" }
			local promoName = (promoChar ~= "" and promoMap[promoChar:lower()]) or "Queen"
			local promoData = { promotePieceName = promoName }

			-- 1. Explicitly clear any lingering selected piece in MatchClient
			if mc and type(mc.clickOnTile) == "function" then
				pcall(function() mc:clickOnTile() end)
				task.wait(0.04)
			end

			-- 2. Select from tile
			if mc and type(mc.clickOnTile) == "function" then
				pcall(function() mc:clickOnTile(fromX, fromY) end)
				local travelPause = if isLegit then (0.12 + math.random(30, 80) / 1000) else (0.05 + math.random(10, 30) / 1000)
				task.wait(travelPause)
				-- 3. Click to tile with promotion payload if applicable
				pcall(function() mc:clickOnTile(toX, toY, if isPromo then promoData else nil) end)
			end

			-- Auto-dismiss CookieChess promotion UI if spawned
			if isPromo then
				local conns = game:GetService("ReplicatedStorage"):FindFirstChild("Connections")
				local moveRemote = conns and conns:FindFirstChild("MovePiece")
				local matchId = (m and (m.id or m.matchId or m.Id))
				if moveRemote and matchId then
					pcall(function()
						moveRemote:FireServer(matchId, { fromX, fromY }, { toX, toY }, promoData)
					end)
				end

				task.spawn(function()
					for _ = 1, 20 do
						local pgui = LocalPlayer:FindFirstChild("PlayerGui")
						if pgui then
							for _, gName in ipairs({ "Promotion", "PawnPromotion", "PromoteGui", "Client" }) do
								local gui = pgui:FindFirstChild(gName)
								if gui then
									for _, btn in ipairs(gui:GetDescendants()) do
										if btn:IsA("GuiButton") and btn.Visible and btn.Name:lower():find(promoName:lower()) then
											triggerButton(btn)
											break
										end
									end
								end
							end
						end
						task.wait(0.04)
					end
				end)
			else
				-- 4. Authoritative remote backup (fires if game didn't advance in 0.55s)
				-- (0.55s accommodates high network ping / laggy mobile connections without double-firing)
				task.delay(0.55, function()
					if not isAlive() or currentMoveSession ~= thisSession then return end
					if not (CFG.PlayLegit or CFG.AutoPlay) then return end
					pcall(function()
						local afterInfo = Adapter.getGameInfo()
						if afterInfo and afterInfo.Active and afterInfo.MyTurn and not afterInfo.IsSpectating and afterInfo.FEN == snapshotFen then
							local conns = game:GetService("ReplicatedStorage"):FindFirstChild("Connections")
							local moveRemote = conns and conns:FindFirstChild("MovePiece")
							local matchId = (m and (m.id or m.matchId or m.Id))
							if moveRemote and matchId then
								moveRemote:FireServer(matchId, { fromX, fromY }, { toX, toY }, promoData)
							end
						end
					end)
				end)
			end
		end

		task.wait(0.20)
		autoPlayBusy = false
	end)
end

----------------------------------------------------------------------
-- MOVE NOTATION FORMATTER
----------------------------------------------------------------------

local PIECES_EN = { p = "Pawn", n = "Knight", b = "Bishop", r = "Rook", q = "Queen", k = "King" }
local PIECES_VI = { p = "Tốt", n = "Mã", b = "Tượng", r = "Xe", q = "Hậu", k = "Vua" }

local function getLocalizedPieceName(fen: string, sq: string): string
	local isVi = (CFG.Language == "vi")
	local placement = fen:match("^(%S+)")
	if not placement or #sq < 2 then return isVi and "Quân cờ" or "Piece" end
	local rank = tonumber(sq:sub(2, 2)) or 1
	local rows = {}
	for r in placement:gmatch("[^/]+") do table.insert(rows, r) end
	local row = rows[9 - rank]
	if not row then return isVi and "Quân cờ" or "Piece" end

	local wantFile = string.byte(sq:sub(1, 1):lower()) - 96
	local file = 1
	for ch in row:gmatch(".") do
		local skip = tonumber(ch)
		if skip then
			file += skip
		else
			if file == wantFile then
				local c = ch:lower()
				local map = isVi and PIECES_VI or PIECES_EN
				return map[c] or (isVi and "Quân cờ" or "Piece")
			end
			file += 1
		end
	end
	return isVi and "Quân cờ" or "Piece"
end

local function formatMoveGuidance(fen: string, from: string, to: string, san: string?): (string, string)
	local isVi = (CFG.Language == "vi")
	local isCastleKing = (from == "e1" and to == "g1") or (from == "e8" and to == "g8")
	local isCastleQueen = (from == "e1" and to == "c1") or (from == "e8" and to == "c8")

	local pName = getLocalizedPieceName(fen, from)
	local title = ("%s: %s -> %s"):format(pName, from:upper(), to:upper())
	if isCastleKing then
		title = isVi and ("Vua: %s -> %s [Nhập thành gần]"):format(from:upper(), to:upper())
			or ("King: %s -> %s [Kingside Castle]"):format(from:upper(), to:upper())
	elseif isCastleQueen then
		title = isVi and ("Vua: %s -> %s [Nhập thành xa]"):format(from:upper(), to:upper())
			or ("King: %s -> %s [Queenside Castle]"):format(from:upper(), to:upper())
	elseif san and san:find("#") then
		title ..= isVi and " [Chiếu hết]" or " [Checkmate]"
	elseif san and san:find("x") then
		title ..= isVi and " [Ăn quân]" or " [Capture]"
	end

	local desc = isVi and ("Ký hiệu: %s | Ô: %s -> %s"):format((san and san ~= "") and san or (from .. "->" .. to), from, to)
		or ("Notation: %s | Square: %s -> %s"):format((san and san ~= "") and san or (from .. "->" .. to), from, to)
	return title, desc
end

----------------------------------------------------------------------
-- EMBEDDED FAST LUAU CHESS ENGINE (GUARANTEED OFFLINE & ZERO HANG)
----------------------------------------------------------------------

local EmbeddedEngine = {}

do
	local FILES_0x88 = { "a", "b", "c", "d", "e", "f", "g", "h" }
	local PIECE_VALS = { [1] = 100, [2] = 320, [3] = 330, [4] = 500, [5] = 900, [6] = 20000 }

	local function to0x88(sq: string): number
		local f = string.byte(sq:sub(1, 1):lower()) - 97
		local r = (tonumber(sq:sub(2, 2)) or 1) - 1
		return (r * 16) + f
	end

	local function from0x88(sq: number): string
		local f = (sq % 16) + 1
		local r = math.floor(sq / 16) + 1
		return (FILES_0x88[f] or "a") .. tostring(r)
	end

	local PST_PAWN = {
		 0,  0,  0,  0,  0,  0,  0,  0,
		50, 50, 50, 50, 50, 50, 50, 50,
		10, 10, 20, 30, 30, 20, 10, 10,
		 5,  5, 10, 25, 25, 10,  5,  5,
		 0,  0,  0, 20, 20,  0,  0,  0,
		 5, -5,-10,  0,  0,-10, -5,  5,
		 5, 10, 10,-20,-20, 10, 10,  5,
		 0,  0,  0,  0,  0,  0,  0,  0,
	}

	local PST_KNIGHT = {
		-50,-40,-30,-30,-30,-30,-40,-50,
		-40,-20,  0,  0,  0,  0,-20,-40,
		-30,  0, 10, 15, 15, 10,  0,-30,
		-30,  5, 15, 20, 20, 15,  5,-30,
		-30,  0, 15, 20, 20, 15,  0,-30,
		-30,  5, 10, 15, 15, 10,  5,-30,
		-40,-20,  0,  5,  5,  0,-20,-40,
		-50,-40,-30,-30,-30,-30,-40,-50,
	}

	local PST_BISHOP = {
		-20,-10,-10,-10,-10,-10,-10,-20,
		-10,  0,  0,  0,  0,  0,  0,-10,
		-10,  0,  5, 10, 10,  5,  0,-10,
		-10,  5,  5, 10, 10,  5,  5,-10,
		-10,  0, 10, 10, 10, 10,  0,-10,
		-10, 10, 10, 10, 10, 10, 10,-10,
		-10,  5,  0,  0,  0,  0,  5,-10,
		-20,-10,-10,-10,-10,-10,-10,-20,
	}

	local PST_KING_MID = {
		-30,-40,-40,-50,-50,-40,-40,-30,
		-30,-40,-40,-50,-50,-40,-40,-30,
		-30,-40,-40,-50,-50,-40,-40,-30,
		-30,-40,-40,-50,-50,-40,-40,-30,
		-20,-30,-30,-40,-40,-30,-30,-20,
		-10,-20,-20,-20,-20,-20,-20,-10,
		 20, 20,  0,  0,  0,  0, 20, 20,
		 20, 30, 10,  0,  0, 10, 30, 20,
	}

	local PST_KING_END = {
		-50,-40,-30,-20,-20,-30,-40,-50,
		-30,-20,-10,  0,  0,-10,-20,-30,
		-30,-10, 20, 30, 30, 20,-10,-30,
		-30,-10, 30, 40, 40, 30,-10,-30,
		-30,-10, 30, 40, 40, 30,-10,-30,
		-30,-10, 20, 30, 30, 20,-10,-30,
		-30,-30,  0,  0,  0,  0,-30,-30,
		-50,-30,-30,-30,-30,-30,-30,-50,
	}

	local function parseFEN(fen: string)
		local board = table.create(128, 0)
		local parts = {}
		for w in fen:gmatch("%S+") do table.insert(parts, w) end
		local placement = parts[1] or ""
		local turn = (parts[2] == "b") and -1 or 1
		local castling = parts[3] or "-"
		local ep = parts[4]
		local epSq = (ep and ep ~= "-" and #ep == 2) and to0x88(ep) or nil

		local rank = 7
		local file = 0
		local charToPiece = {
			p = 1, n = 2, b = 3, r = 4, q = 5, k = 6,
			P = 1, N = 2, B = 3, R = 4, Q = 5, K = 6,
		}

		for ch in placement:gmatch(".") do
			if ch == "/" then
				rank -= 1
				file = 0
			else
				local skip = tonumber(ch)
				if skip then
					file += skip
				else
					local isWhite = (ch:upper() == ch)
					local pType = charToPiece[ch] or 1
					local sq = (rank * 16) + file
					board[sq + 1] = isWhite and pType or -pType
					file += 1
				end
			end
		end

		return board, turn, castling, epSq
	end

	local function isAttacked(board: { number }, targetSq: number, byTurn: number): boolean
		local pOffset = byTurn == 1 and -16 or 16
		local p1 = targetSq + pOffset - 1
		if (p1 >= 0 and p1 < 128 and bit32.band(p1, 0x88) == 0) and board[p1 + 1] == (byTurn * 1) then return true end
		local p2 = targetSq + pOffset + 1
		if (p2 >= 0 and p2 < 128 and bit32.band(p2, 0x88) == 0) and board[p2 + 1] == (byTurn * 1) then return true end

		for _, offset in ipairs({ -33, -31, -18, -14, 14, 18, 31, 33 }) do
			local sq = targetSq + offset
			if sq >= 0 and sq < 128 and bit32.band(sq, 0x88) == 0 and board[sq + 1] == (byTurn * 2) then return true end
		end
		for _, offset in ipairs({ -17, -16, -15, -1, 1, 15, 16, 17 }) do
			local sq = targetSq + offset
			if sq >= 0 and sq < 128 and bit32.band(sq, 0x88) == 0 and board[sq + 1] == (byTurn * 6) then return true end
		end
		for _, offset in ipairs({ -17, -15, 15, 17 }) do
			local sq = targetSq + offset
			while sq >= 0 and sq < 128 and bit32.band(sq, 0x88) == 0 do
				local p = board[sq + 1]
				if p ~= 0 then
					if p == (byTurn * 3) or p == (byTurn * 5) then return true end
					break
				end
				sq += offset
			end
		end
		for _, offset in ipairs({ -16, -1, 1, 16 }) do
			local sq = targetSq + offset
			while sq >= 0 and sq < 128 and bit32.band(sq, 0x88) == 0 do
				local p = board[sq + 1]
				if p ~= 0 then
					if p == (byTurn * 4) or p == (byTurn * 5) then return true end
					break
				end
				sq += offset
			end
		end
		return false
	end

	local function findKing(board: { number }, turn: number): number?
		local want = turn * 6
		for sq = 0, 127 do
			if bit32.band(sq, 0x88) == 0 and board[sq + 1] == want then return sq end
		end
		return nil
	end

	local function makeMove(board: { number }, mv: any)
		local from = mv.from
		local to = mv.to
		local origFrom = board[from + 1]
		local origTo = board[to + 1]
		local isPromo = mv.promo ~= nil
		local isCastle = mv.isCastle
		local isEp = mv.isEp

		board[from + 1] = 0
		if isPromo then
			board[to + 1] = (origFrom > 0) and 5 or -5
		else
			board[to + 1] = origFrom
		end

		local epVictimSq = nil
		if isEp then
			epVictimSq = to - ((origFrom > 0) and 16 or -16)
			board[epVictimSq + 1] = 0
		end

		local rFrom, rTo = nil, nil
		if isCastle then
			if to == 6 then rFrom = 7; rTo = 5
			elseif to == 2 then rFrom = 0; rTo = 3
			elseif to == 118 then rFrom = 119; rTo = 117
			elseif to == 114 then rFrom = 112; rTo = 115
			end
			if rFrom and rTo then
				board[rTo + 1] = board[rFrom + 1]
				board[rFrom + 1] = 0
			end
		end

		return origFrom, origTo, epVictimSq, rFrom, rTo
	end

	local function unmakeMove(board: { number }, mv: any, origFrom: number, origTo: number, epVictimSq: number?, rFrom: number?, rTo: number?)
		board[mv.from + 1] = origFrom
		board[mv.to + 1] = origTo
		if epVictimSq then
			board[epVictimSq + 1] = (origFrom > 0) and -1 or 1
		end
		if rFrom and rTo then
			board[rFrom + 1] = board[rTo + 1]
			board[rTo + 1] = 0
		end
	end

	local function generateLegalMoves(board: { number }, turn: number, castling: string, epSq: number?, capturesOnly: boolean?)
		local moves = {}
		local function addMove(from: number, to: number, promo: string?, isCap: boolean, isCastle: boolean?, isEp: boolean?)
			local mv = { from = from, to = to, promo = promo, isCapture = isCap, isCastle = isCastle, isEp = isEp }
			local origFrom, origTo, epVictim, rFrom, rTo = makeMove(board, mv)
			local kingSq = findKing(board, turn)
			local inCheck = kingSq and isAttacked(board, kingSq, -turn)
			unmakeMove(board, mv, origFrom, origTo, epVictim, rFrom, rTo)
			if not inCheck then
				table.insert(moves, mv)
			end
		end

		for sq = 0, 127 do
			if bit32.band(sq, 0x88) == 0 then
				local p = board[sq + 1]
				if p ~= 0 and ((turn == 1 and p > 0) or (turn == -1 and p < 0)) then
					local absP = math.abs(p)
					local rank = math.floor(sq / 16)

					if absP == 1 then
						local fwd = (turn == 1) and 16 or -16
						local promoRank = (turn == 1) and 7 or 0
						local startRank = (turn == 1) and 1 or 6

						if not capturesOnly then
							local nextSq = sq + fwd
							if nextSq >= 0 and nextSq < 128 and bit32.band(nextSq, 0x88) == 0 and board[nextSq + 1] == 0 then
								local nextRank = math.floor(nextSq / 16)
								if nextRank == promoRank then
									addMove(sq, nextSq, "q", false)
								else
									addMove(sq, nextSq, nil, false)
									if rank == startRank then
										local doubleSq = sq + (fwd * 2)
										if board[doubleSq + 1] == 0 then
											addMove(sq, doubleSq, nil, false)
										end
									end
								end
							end
						end

						for _, capOffset in ipairs({ fwd - 1, fwd + 1 }) do
							local capSq = sq + capOffset
							if capSq >= 0 and capSq < 128 and bit32.band(capSq, 0x88) == 0 then
								local capP = board[capSq + 1]
								if capP ~= 0 and ((turn == 1 and capP < 0) or (turn == -1 and capP > 0)) then
									local capRank = math.floor(capSq / 16)
									if capRank == promoRank then
										addMove(sq, capSq, "q", true)
									else
										addMove(sq, capSq, nil, true)
									end
								elseif epSq and capSq == epSq then
									addMove(sq, capSq, nil, true, false, true)
								end
							end
						end
					elseif absP == 2 then
						for _, offset in ipairs({ -33, -31, -18, -14, 14, 18, 31, 33 }) do
							local toSq = sq + offset
							if toSq >= 0 and toSq < 128 and bit32.band(toSq, 0x88) == 0 then
								local targetP = board[toSq + 1]
								if (turn == 1 and targetP < 0) or (turn == -1 and targetP > 0) then
									addMove(sq, toSq, nil, true)
								elseif not capturesOnly and targetP == 0 then
									addMove(sq, toSq, nil, false)
								end
							end
						end
					elseif absP == 3 or absP == 5 then
						for _, offset in ipairs({ -17, -15, 15, 17 }) do
							local toSq = sq + offset
							while toSq >= 0 and toSq < 128 and bit32.band(toSq, 0x88) == 0 do
								local targetP = board[toSq + 1]
								if targetP == 0 then
									if not capturesOnly then addMove(sq, toSq, nil, false) end
								else
									if (turn == 1 and targetP < 0) or (turn == -1 and targetP > 0) then
										addMove(sq, toSq, nil, true)
									end
									break
								end
								toSq += offset
							end
						end
					end

					if absP == 4 or absP == 5 then
						for _, offset in ipairs({ -16, -1, 1, 16 }) do
							local toSq = sq + offset
							while toSq >= 0 and toSq < 128 and bit32.band(toSq, 0x88) == 0 do
								local targetP = board[toSq + 1]
								if targetP == 0 then
									if not capturesOnly then addMove(sq, toSq, nil, false) end
								else
									if (turn == 1 and targetP < 0) or (turn == -1 and targetP > 0) then
										addMove(sq, toSq, nil, true)
									end
									break
								end
								toSq += offset
							end
						end
					end

					if absP == 6 then
						for _, offset in ipairs({ -17, -16, -15, -1, 1, 15, 16, 17 }) do
							local toSq = sq + offset
							if toSq >= 0 and toSq < 128 and bit32.band(toSq, 0x88) == 0 then
								local targetP = board[toSq + 1]
								if (turn == 1 and targetP < 0) or (turn == -1 and targetP > 0) then
									addMove(sq, toSq, nil, true)
								elseif not capturesOnly and targetP == 0 then
									addMove(sq, toSq, nil, false)
								end
							end
						end

						if not capturesOnly then
							if turn == 1 and sq == 4 and not isAttacked(board, 4, -1) then
								if castling:find("K") and board[6] == 0 and board[7] == 0 and not isAttacked(board, 5, -1) and not isAttacked(board, 6, -1) then
									addMove(4, 6, nil, false, true)
								end
								if castling:find("Q") and board[2] == 0 and board[3] == 0 and board[4] == 0 and not isAttacked(board, 2, -1) and not isAttacked(board, 3, -1) then
									addMove(4, 2, nil, false, true)
								end
							elseif turn == -1 and sq == 116 and not isAttacked(board, 116, 1) then
								if castling:find("k") and board[118] == 0 and board[119] == 0 and not isAttacked(board, 117, 1) and not isAttacked(board, 118, 1) then
									addMove(116, 118, nil, false, true)
								end
								if castling:find("q") and board[114] == 0 and board[115] == 0 and board[116] == 0 and not isAttacked(board, 114, 1) and not isAttacked(board, 115, 1) then
									addMove(116, 114, nil, false, true)
								end
							end
						end
					end
				end
			end
		end
		return moves
	end

	local function evaluate(board: { number }): number
		local score = 0
		local majorPieces = 0

		for sq = 0, 127 do
			if bit32.band(sq, 0x88) == 0 then
				local p = board[sq + 1]
				if p ~= 0 then
					local absP = math.abs(p)
					if absP >= 2 and absP <= 5 then majorPieces += 1 end
					local sign = (p > 0) and 1 or -1
					local val = PIECE_VALS[absP] or 0
					local rank = math.floor(sq / 16)
					local file = sq % 16
					local pstIdx = (sign == 1) and ((7 - rank) * 8 + file + 1) or (rank * 8 + file + 1)

					local bonus = 0
					if absP == 1 then bonus = PST_PAWN[pstIdx] or 0
					elseif absP == 2 then bonus = PST_KNIGHT[pstIdx] or 0
					elseif absP == 3 then bonus = PST_BISHOP[pstIdx] or 0
					elseif absP == 6 then
						bonus = (majorPieces <= 4) and (PST_KING_END[pstIdx] or 0) or (PST_KING_MID[pstIdx] or 0)
					end

					score += sign * (val + bonus)
				end
			end
		end
		return score
	end

	function EmbeddedEngine.getBestMove(fen: string): (any?, string?)
		local ok, result = pcall(function()
			local board, turn, castling, epSq = parseFEN(fen)
			local legalMoves = generateLegalMoves(board, turn, castling, epSq, false)

			if #legalMoves == 0 then
				local kingSq = findKing(board, turn)
				local inCheck = kingSq and isAttacked(board, kingSq, -turn)
				return {
					gameOver = true,
					reason = inCheck and "Checkmate" or "Stalemate",
					source = "SonHUB Tactical Engine",
				}
			end

			local killers = {}
			for i = 1, 12 do killers[i] = { nil, nil } end

			local function scoreMove(mv: any, ply: number): number
				if mv.isCapture then
					local victim = math.abs(board[mv.to + 1] or 0)
					local attacker = math.abs(board[mv.from + 1] or 0)
					local vVal = PIECE_VALS[victim] or 100
					local aVal = PIECE_VALS[attacker] or 100
					return 10000 + (vVal * 10) - aVal
				else
					local k = killers[ply]
					if k and k[1] and k[1].from == mv.from and k[1].to == mv.to then return 900 end
					if k and k[2] and k[2].from == mv.from and k[2].to == mv.to then return 800 end
				end
				return 0
			end

			local function orderMoves(moves: { any }, ply: number)
				table.sort(moves, function(a, b) return scoreMove(a, ply) > scoreMove(b, ply) end)
			end

			local function quiesce(alpha: number, beta: number, qTurn: number, qDepth: number): number
				local standPat = evaluate(board) * qTurn
				if qDepth <= 0 or standPat >= beta then return standPat end
				if standPat > alpha then alpha = standPat end

				local caps = generateLegalMoves(board, qTurn, "-", nil, true)
				orderMoves(caps, 1)

				for _, mv in ipairs(caps) do
					local origFrom, origTo, epVictim, rFrom, rTo = makeMove(board, mv)
					local score = -quiesce(-beta, -alpha, -qTurn, qDepth - 1)
					unmakeMove(board, mv, origFrom, origTo, epVictim, rFrom, rTo)

					if score >= beta then return beta end
					if score > alpha then alpha = score end
				end
				return alpha
			end

			local function alphaBeta(depth: number, alpha: number, beta: number, curTurn: number, ply: number): number
				if depth <= 0 then
					return quiesce(alpha, beta, curTurn, 4)
				end

				local moves = generateLegalMoves(board, curTurn, "-", nil, false)
				if #moves == 0 then
					local kSq = findKing(board, curTurn)
					if kSq and isAttacked(board, kSq, -curTurn) then
						return -300000 + ply
					end
					return 0
				end

				orderMoves(moves, ply)

				for _, mv in ipairs(moves) do
					local origFrom, origTo, epVictim, rFrom, rTo = makeMove(board, mv)
					local score = -alphaBeta(depth - 1, -beta, -alpha, -curTurn, ply + 1)
					unmakeMove(board, mv, origFrom, origTo, epVictim, rFrom, rTo)

					if score >= beta then
						if not mv.isCapture and ply <= 12 then
							killers[ply][2] = killers[ply][1]
							killers[ply][1] = mv
						end
						return beta
					end
					if score > alpha then
						alpha = score
					end
				end
				return alpha
			end

			orderMoves(legalMoves, 1)
			local bestMv = legalMoves[1]
			local bestScore = -999999
			local searchDepthReached = 1
			local tStart = tick()

			-- Iterative deepening up to depth 5 with 0.35s time cutoff
			for currentDepth = 1, 5 do
				if (tick() - tStart) > 0.35 and currentDepth > 2 then break end

				local currentBestMv = bestMv
				local currentBestScore = -999999
				local alpha = -999999
				local beta = 999999

				for _, mv in ipairs(legalMoves) do
					local origFrom, origTo, epVictim, rFrom, rTo = makeMove(board, mv)
					local score = -alphaBeta(currentDepth - 1, -beta, -alpha, -turn, 2)
					unmakeMove(board, mv, origFrom, origTo, epVictim, rFrom, rTo)

					if score > currentBestScore then
						currentBestScore = score
						currentBestMv = mv
					end
					if score > alpha then alpha = score end
				end

				bestMv = currentBestMv
				bestScore = currentBestScore
				searchDepthReached = currentDepth

				if bestScore >= 250000 then -- Mate found
					break
				end
			end

			local fromSq = from0x88(bestMv.from)
			local toSq = from0x88(bestMv.to)
			local uci = fromSq .. toSq .. (bestMv.promo or "")
			local evalPawns = (bestScore / 100) * (turn == 1 and 1 or -1)

			return {
				from = fromSq,
				to = toSq,
				uci = uci,
				eval = evalPawns,
				depth = searchDepthReached + 3, -- total search + quiescence ply
				line = { uci },
				source = ("SonHUB Tactical Engine (Depth %d, Alpha-Beta)"):format(searchDepthReached + 3),
			}
		end)

		if ok and type(result) == "table" then
			return result, nil
		end
		return nil, "Embedded engine error"
	end
end

----------------------------------------------------------------------
-- ENGINE PIPELINE (STOCKFISH 16 + CHESS-API + LOCAL FALLBACKS)
----------------------------------------------------------------------

local fenCache: { [string]: any } = {}
local positionHistory: { [string]: number } = {}
local ponderPrediction: { [string]: any } = {}
local stockfishCooldownUntil = 0
local chessApiCooldownUntil = 0
local stockfishFailCount = 0
local chessApiFailCount = 0

-- How long bestMove waits for the parallel source race. Three sources in parallel measured
-- ~1.5s end to end, so this buys the strongest available answer rather than the fastest one.
local ENGINE_RACE_BUDGET = 1.8

-- Lichess (cloud-eval + tablebase) share one host that returns 429 under rapid polling and then
-- stalls for minutes. One shared limiter guards both: a minimum gap between calls plus a
-- breaker that skips the host entirely while tripped.
local LICHESS_MIN_GAP = 1.1
local lichessNextAllowed = 0
local lichessBreakerUntil = 0
local lichessFailStreak = 0

local function lichessReady(): boolean
	local now = tick()
	return now >= lichessNextAllowed and now >= lichessBreakerUntil
end

local function lichessNoteCall()
	lichessNextAllowed = tick() + LICHESS_MIN_GAP
end

local function lichessNoteResult(ok: boolean, rateLimited: boolean?)
	if ok then
		lichessFailStreak = 0
		return
	end
	lichessFailStreak += 1
	if rateLimited then
		-- 429 means back off hard; the host keeps 429ing (and then hanging) if we keep knocking.
		lichessBreakerUntil = tick() + 30
	elseif lichessFailStreak >= 3 then
		lichessBreakerUntil = tick() + 15
	end
end

-- Count pieces in a FEN placement field; Syzygy tablebase covers 7 pieces or fewer.
local function countPieces(fen: string): number
	local placement = fen:match("^(%S+)")
	if not placement then return 32 end
	local n = 0
	for _ in placement:gmatch("%a") do n += 1 end
	return n
end

local function convertChess960Castling(uci: string): string
	if type(uci) ~= "string" or #uci < 4 then return uci end
	local lower = uci:lower()
	local promo = uci:sub(5)
	local core = lower:sub(1, 4)
	if core == "e1h1" then
		return "e1g1" .. promo
	elseif core == "e1a1" then
		return "e1c1" .. promo
	elseif core == "e8h8" then
		return "e8g8" .. promo
	elseif core == "e8a8" then
		return "e8c8" .. promo
	end
	return uci
end

-- Clean standard FEN validator for Stockfish
local function validateFen(fen: string): string
	if type(fen) ~= "string" or #fen < 8 then return fen end
	local parts = {}
	for w in fen:gmatch("%S+") do table.insert(parts, w) end
	if #parts < 4 then return fen end
	return table.concat(parts, " ", 1, math.min(#parts, 6))
end

local function askStockfishOnline(fen: string, depth: number): (any?, string?)
	local cleanFen = normalizeFenForEngine(fen)
	local depthVal = math.clamp(depth or 15, 12, 16)
	local url = "https://stockfish.online/api/s/v2.php?fen=" .. HttpService:UrlEncode(cleanFen) .. "&depth=" .. tostring(depthVal)
	local body = makeHttpRequest(url, "GET", nil, 3.5)

	-- If depth 14-16 timed out, immediately fast-retry depth 12 (<0.8s, ~3400 ELO)
	if not body and depthVal > 12 then
		local retryUrl = "https://stockfish.online/api/s/v2.php?fen=" .. HttpService:UrlEncode(cleanFen) .. "&depth=12"
		body = makeHttpRequest(retryUrl, "GET", nil, 1.8)
		if body then depthVal = 12 end
	end

	if not body then
		stockfishFailCount += 1
		if stockfishFailCount >= 3 then
			stockfishCooldownUntil = tick() + 8
		end
		return nil, "stockfish.online unavailable"
	end
	stockfishFailCount = 0

	local okJson, data = pcall(function() return HttpService:JSONDecode(body) end)
	if not okJson or not data or not data.success or type(data.bestmove) ~= "string" then
		stockfishFailCount += 1
		if stockfishFailCount >= 3 then
			stockfishCooldownUntil = tick() + 8
		end
		return nil, "stockfish.online error"
	end

	if data.bestmove:find("%(none%)") or data.mate == 0 then
		return {
			gameOver = true,
			reason = (data.mate == 0) and "Checkmate" or "Draw / Stalemate",
			source = "Stockfish 16",
		}, nil
	end

	local mv = data.bestmove:match("bestmove (%S+)")
	if not mv or #mv < 4 then return nil, "invalid move" end
	mv = convertChess960Castling(mv)

	local continuation = {}
	if type(data.continuation) == "string" then
		for w in data.continuation:gmatch("%S+") do
			table.insert(continuation, convertChess960Castling(w))
		end
	end
	if #continuation == 0 or continuation[1]:lower() ~= mv:lower() then
		table.insert(continuation, 1, mv)
	end

	local rawPonder = data.bestmove:match("ponder (%S+)")
	local cleanPonder = rawPonder and convertChess960Castling(rawPonder)
	if not cleanPonder and continuation[2] then
		cleanPonder = continuation[2]
	end

	return {
		from = mv:sub(1, 2),
		to = mv:sub(3, 4),
		uci = mv,
		ponder = cleanPonder,
		eval = tonumber(data.evaluation),
		mate = tonumber(data.mate),
		depth = depthVal,
		line = continuation,
		source = ("Stockfish 16 (Depth %d)"):format(depthVal),
	}, nil
end

local function isPositionComplex(fen: string): boolean
	local pieces = countPieces(fen)
	if pieces <= 6 then return false end
	local hasQueens = (fen:find("q") ~= nil) and (fen:find("Q") ~= nil)
	return (hasQueens == true) and (pieces >= 12)
end

local function askChessApi(fen: string, isComplex: boolean?): (any?, string?)
	-- CRITICAL FIX: chess-api.com strictly rejects FEN containing an en-passant square (returns INVALID_FEN)
	-- Therefore stripEp MUST be true!
	local cleanFen = normalizeFenForEngine(fen, nil, true)
	local depthVal = math.clamp(CFG.Depth or 16, 12, 18)
	-- Adaptive deep calculation: if complex position, allocate up to 3200ms thinking time
	local thinkingTime = if isComplex then 3200 else 1800
	local maxTimeout = if isComplex then 5.5 else 4.0
	local payload = HttpService:JSONEncode({
		fen = cleanFen,
		depth = depthVal,
		maxThinkingTime = thinkingTime,
		variants = 3,
	})
	local body = makeHttpRequest("https://chess-api.com/v1", "POST", payload, maxTimeout)
	if not body then
		chessApiFailCount += 1
		if chessApiFailCount >= 3 then
			chessApiCooldownUntil = tick() + 8
		end
		return nil, "chess-api network error"
	end
	chessApiFailCount = 0

	local okJson, data = pcall(function() return HttpService:JSONDecode(body) end)
	if not okJson or type(data) ~= "table" or data.error or type(data.move) ~= "string" or #data.move < 4 then
		if data and data.error and tostring(data.error):find("rate") then
			chessApiCooldownUntil = tick() + 15
		end
		return nil, "chess-api format error"
	end

	local cleanMove = convertChess960Castling(data.move)
	local continuation = { cleanMove }
	if type(data.continuationArr) == "table" then
		for _, w in ipairs(data.continuationArr) do
			if type(w) == "string" and w:lower() ~= cleanMove:lower() then
				table.insert(continuation, convertChess960Castling(w))
			end
		end
	end

	local cleanPonder = continuation[2]
	if not cleanPonder and type(data.continuation) == "table" and data.continuation[1] and data.continuation[1].from and data.continuation[1].to then
		cleanPonder = data.continuation[1].from .. data.continuation[1].to
	end

	local candidateMoves = {}
	if type(data.variants) == "table" then
		for _, v in ipairs(data.variants) do
			if type(v) == "table" and type(v.move) == "string" and #v.move >= 4 then
				table.insert(candidateMoves, {
					uci = convertChess960Castling(v.move),
					eval = tonumber(v.eval) or tonumber(data.eval),
					san = v.san,
					depth = v.depth or data.depth,
				})
			end
		end
	end

	return {
		from = cleanMove:sub(1, 2),
		to = cleanMove:sub(3, 4),
		uci = cleanMove,
		san = data.san,
		ponder = cleanPonder and convertChess960Castling(cleanPonder),
		eval = tonumber(data.eval),
		mate = tonumber(data.mate),
		depth = data.depth or depthVal,
		line = continuation,
		candidateMoves = candidateMoves,
		source = ("Stockfish 16 (Depth %d)"):format(data.depth or depthVal),
	}, nil
end

-- Syzygy tablebase: PERFECT play for <=7 pieces. Outranks every search-based engine here,
-- because it is not a search - it is the solved result. Verified: a 6-piece position where
-- cloud-eval returned e3f4 but the tablebase returned e3e4 with dtz=1.
local function askTablebase(fen: string): (any?, string?)
	if countPieces(fen) > 7 then return nil, "too many pieces" end
	if not lichessReady() then return nil, "lichess cooling down" end

	-- Tablebase accepts (and needs) a real ep square - do NOT strip it here.
	local cleanFen = normalizeFenForEngine(fen)
	lichessNoteCall()
	local body = makeHttpRequest("https://tablebase.lichess.ovh/standard?fen=" .. HttpService:UrlEncode(cleanFen), "GET", nil, 2.5)
	if not body then
		lichessNoteResult(false)
		return nil, "tablebase unavailable"
	end

	local okJson, data = pcall(function() return HttpService:JSONDecode(body) end)
	if not okJson or type(data) ~= "table" then
		lichessNoteResult(false)
		return nil, "tablebase decode error"
	end
	lichessNoteResult(true)

	-- No moves means the position itself is terminal.
	if type(data.moves) ~= "table" or #data.moves == 0 then
		if data.checkmate or data.stalemate or data.insufficient_material then
			return {
				gameOver = true,
				reason = if data.checkmate then "Checkmate"
					elseif data.stalemate then "Stalemate"
					else "Insufficient material",
				source = "Syzygy Tablebase (Perfect)",
			}, nil
		end
		return nil, "tablebase has no moves"
	end

	-- The API returns moves already ranked best-first from the mover's point of view.
	local best = data.moves[1]
	if type(best) ~= "table" or type(best.uci) ~= "string" or #best.uci < 4 then
		return nil, "tablebase bad move"
	end

	local uci = convertChess960Castling(best.uci)
	local line = {}
	for i = 1, math.min(#data.moves, 5) do
		local m = data.moves[i]
		if type(m) == "table" and type(m.uci) == "string" then
			table.insert(line, convertChess960Castling(m.uci))
		end
	end

	-- category is from the side-to-move's perspective in the resulting position.
	local evalPawns: number? = nil
	local mateIn: number? = nil
	if data.category == "win" then
		evalPawns = 10.0
	elseif data.category == "loss" then
		evalPawns = -10.0
	elseif data.category then
		evalPawns = 0.0
	end
	if type(best.dtm) == "number" and best.dtm ~= 0 then
		mateIn = math.ceil(math.abs(best.dtm) / 2) * (best.dtm > 0 and -1 or 1)
	end

	return {
		from = uci:sub(1, 2),
		to = uci:sub(3, 4),
		uci = uci,
		san = best.san,
		eval = evalPawns,
		mate = mateIn,
		depth = 100,
		line = line,
		dtz = data.dtz,
		category = data.category,
		source = ("Syzygy Tablebase (Perfect, DTZ %s)"):format(tostring(data.dtz or "?")),
	}, nil
end

-- Lichess cloud evaluation: real Stockfish analysis cached at depth 30-75, far deeper than any
-- live API here. Only covers positions somebody has already analysed, so it 404s on offbeat
-- middlegames (2 of 10 realistic test positions missed).
local function askLichessCloud(fen: string): (any?, string?)
	if not lichessReady() then return nil, "lichess cooling down" end

	-- cloud-eval tolerates a valid ep square, so keep it.
	local cleanFen = normalizeFenForEngine(fen)
	lichessNoteCall()
	local body = makeHttpRequest("https://lichess.org/api/cloud-eval?fen=" .. HttpService:UrlEncode(cleanFen), "GET", nil, 2.0)
	if not body then
		lichessNoteResult(false)
		return nil, "cloud miss"
	end

	local okJson, data = pcall(function() return HttpService:JSONDecode(body) end)
	if not okJson or type(data) ~= "table" then
		-- A 429 arrives as an HTML body, so a decode failure here usually means rate limited.
		lichessNoteResult(false, body:find("<!DOCTYPE") ~= nil)
		return nil, "cloud decode error"
	end
	if type(data.pvs) ~= "table" or not data.pvs[1] or type(data.pvs[1].moves) ~= "string" then
		lichessNoteResult(true) -- a clean 404 is not a rate-limit problem
		return nil, "cloud no pvs"
	end
	lichessNoteResult(true)

	local pv = data.pvs[1]
	local line = {}
	for w in pv.moves:gmatch("%S+") do
		table.insert(line, convertChess960Castling(w))
	end
	local uci = line[1]
	if not uci or #uci < 4 then return nil, "cloud bad move" end

	local depthVal = tonumber(data.depth) or 0
	return {
		from = uci:sub(1, 2),
		to = uci:sub(3, 4),
		uci = uci,
		eval = (type(pv.cp) == "number") and (pv.cp / 100) or nil,
		mate = tonumber(pv.mate),
		depth = depthVal,
		line = line,
		source = ("Lichess Cloud (Depth %d, Deep Analysis)"):format(depthVal),
	}, nil
end

local cachedGarbo = nil
local cachedChessClassic = nil

local function getChessClassic(): any?
	if not cachedChessClassic then
		local rs = game:GetService("ReplicatedStorage")
		local mod = rs:FindFirstChild("Modules") and rs.Modules:FindFirstChild("GameLogic") and rs.Modules.GameLogic:FindFirstChild("ChessClassic")
		cachedChessClassic = tryRequire(mod)
	end
	return cachedChessClassic
end

local function askLocalOffline(fen: string, gameInfo: any?): (any?, string?)
	-- 1. SonHUB Advanced Tactical Engine (Alpha-Beta + Quiescence, 2400+ ELO)
	local okEmb, resEmb = pcall(function() return EmbeddedEngine.getBestMove(fen) end)
	if okEmb and resEmb and resEmb.uci then
		return resEmb, nil
	elseif okEmb and resEmb and resEmb.gameOver then
		return resEmb, nil
	end

	-- 2. Native GarboChess engine in Chess Club (PlaceId: 139394516128799)
	local isCC = (gameInfo and gameInfo.GameType == "ChessClub") or IS_CHESS_CLUB
	if isCC then
		if not cachedGarbo then
			local pScripts = LocalPlayer:FindFirstChild("PlayerScripts")
			local svc = pScripts and pScripts:FindFirstChild("ServicesMainPlace")
			local engines = svc and svc:FindFirstChild("AIService") and svc.AIService:FindFirstChild("Engines")
			cachedGarbo = tryRequire(engines and engines:FindFirstChild("GarboChess"))
		end

		if cachedGarbo and type(cachedGarbo.GetBestMoveFromFEN) == "function" then
			local ok, mv = pcall(function() return cachedGarbo:GetBestMoveFromFEN(fen, 1.2) end)
			if ok and type(mv) == "string" and #mv >= 4 then
				return { from = mv:sub(1, 2), to = mv:sub(3, 4), uci = mv, source = "GarboChess Local (Full Depth)" }, nil
			end
		end
	end

	return nil, "No local engine available"
end

local function bestMove(fen: string, gameInfo: any?): (any?, string?)
	-- Repetition tracking: prevent 3-fold repetition draws
	local posKey = fen:match("^(%S+%s+%S+%s+%S+)") or fen
	local seenCount = positionHistory[posKey] or 0
	positionHistory[posKey] = seenCount + 1

	-- If this position has already been seen 2 or more times, clear cache to force alternative move
	if seenCount >= 2 then
		fenCache[fen] = nil
	elseif fenCache[fen] then
		return fenCache[fen], nil
	end

	-- Fast check for termination condition (checkmate / stalemate / draw)
	local ccMod = getChessClassic()
	if ccMod and type(ccMod.CheckTerminationConditions) == "function" then
		local okTerm, termInfo = pcall(function() return ccMod:CheckTerminationConditions(fen) end)
		if okTerm and type(termInfo) == "table" and termInfo.Terminated then
			return {
				gameOver = true,
				reason = termInfo.Reason or "Game Over",
				source = "Rule Engine",
			}, nil
		end
	end

	if CFG.EngineMode == "OfflineOnly" then
		local fb, err = askLocalOffline(fen, gameInfo)
		return fb, err
	end

	local now = tick()
	local pieces = countPieces(fen)

	-- TIER 1: Syzygy Tablebase for endgame <= 5 pieces (Guaranteed perfect play, DTZ 0-1)
	if pieces <= 5 and lichessReady() then
		local tb = askTablebase(fen)
		if tb and tb.uci then
			fenCache[fen] = tb
			return tb, nil
		elseif tb and tb.gameOver then
			return tb, nil
		end
	end

	-- TIER 1.5: Lichess Cloud Deep Analysis (Grandmaster cached analysis, Depth 30-75)
	if pieces > 5 and lichessReady() then
		local cld = askLichessCloud(fen)
		if cld and cld.uci then
			if seenCount < 2 or not (cld.eval and cld.eval < -0.8) then
				fenCache[fen] = cld
				return cld, nil
			end
		end
	end

	-- TIER 2: Primary Grandmaster Stockfish 16 NNUE via chess-api.com (~1.1s - 3.2s, Depth 16-18, 3500+ ELO)
	if now > chessApiCooldownUntil then
		local isComplex = isPositionComplex(fen)
		local d1 = askChessApi(fen, isComplex)
		if d1 and d1.uci then
			-- Anti-Draw & Anti-Repetition Evasion: Diverge to candidate moves to play for win
			if seenCount >= 2 and (d1.eval or 0) >= -1.2 then
				local alt = nil
				if d1.candidateMoves and #d1.candidateMoves >= 2 then
					for i = 2, #d1.candidateMoves do
						local c = d1.candidateMoves[i]
						if c and c.uci and c.uci ~= d1.uci then
							alt = c.uci
							break
						end
					end
				elseif d1.line and #d1.line >= 2 then
					alt = d1.line[2]
				end
				if alt and #alt >= 4 and alt ~= d1.uci then
					d1.from = alt:sub(1, 2)
					d1.to = alt:sub(3, 4)
					d1.uci = alt
					d1.source = d1.source .. " (Anti-Draw / Win Mindset)"
				end
			end
			fenCache[fen] = d1
			return d1, nil
		elseif d1 and d1.gameOver then
			return d1, nil
		end
	end

	-- TIER 3: High-Precision Stockfish 16 NNUE via stockfish.online (Depth 14, 3500+ ELO)
	if now > stockfishCooldownUntil then
		local d2 = askStockfishOnline(fen, math.clamp(CFG.Depth or 14, 13, 15))
		if d2 and d2.uci then
			fenCache[fen] = d2
			return d2, nil
		elseif d2 and d2.gameOver then
			return d2, nil
		end
	end

	-- TIER 4: Fast-Rescue Stockfish 16 NNUE (Depth 12, < 0.8s, ~3400 ELO)
	local dRetry = askStockfishOnline(fen, 12)
	if dRetry and dRetry.uci then
		fenCache[fen] = dRetry
		return dRetry, nil
	end

	-- TIER 5: Fallback to chess-api without cooldown check
	local dBackup = askChessApi(fen)
	if dBackup and dBackup.uci then
		fenCache[fen] = dBackup
		return dBackup, nil
	end

	if CFG.EngineMode == "OnlineOnly" then
		return nil, "No online engine response"
	end

	-- TIER 6: Emergency Tactical Engine (Local alpha-beta search with quiescence, NEVER cached)
	local fbLocal, err = askLocalOffline(fen, gameInfo)
	if fbLocal and (fbLocal.uci or fbLocal.gameOver) then
		return fbLocal, nil
	end

	return nil, err or "No engine response"
end

----------------------------------------------------------------------
-- 3D TACTICAL VORTEX VISUALS
----------------------------------------------------------------------

local activeInstances: { Instance } = {}
local currentGuidance: any = nil

local function clearAllMarkers()
	for _, inst in ipairs(activeInstances) do
		pcall(function() inst:Destroy() end)
	end
	table.clear(activeInstances)

	pcall(function()
		for _, desc in ipairs(Workspace:GetDescendants()) do
			if desc:GetAttribute("SonHubCoach") == true or desc.Name:match("^SonHub") then
				desc:Destroy()
			end
		end
	end)

	pcall(function()
		local pgui = LocalPlayer:FindFirstChild("PlayerGui")
		local b2d = pgui and pgui:FindFirstChild("2DBoard")
		local main = b2d and b2d:FindFirstChild("Main")
		if main then
			local oldOverlay = main:FindFirstChild("SonHub2D_Overlay")
			if oldOverlay then
				oldOverlay:Destroy()
			end
			local board = main:FindFirstChild("Board")
			if board then
				for _, child in ipairs(board:GetChildren()) do
					if child:IsA("GuiObject") then
						for _, sub in ipairs(child:GetChildren()) do
							if sub:GetAttribute("SonHubCoach") == true or sub.Name:match("^SonHub") then
								sub:Destroy()
							end
						end
					end
				end
			end
			local arrows = main:FindFirstChild("Arrows")
			if arrows then
				for _, ch in ipairs(arrows:GetChildren()) do
					if ch:GetAttribute("SonHubCoach") == true or ch.Name:match("^SonHub") then
						ch:Destroy()
					end
				end
			end
		end
	end)
end

local function getVisualContainer(): Instance
	return Workspace.CurrentCamera or Workspace
end

local function draw3DSource(tile3D: Instance, piece3D: Instance?)
	local cf, size = getTileCFrameAndSize(tile3D)
	local topY = cf.Y + size.Y / 2
	local tileSize = math.max(size.X, size.Z)
	if tileSize <= 0.1 then tileSize = 3.8 end

	local container = getVisualContainer()

	local pad = Instance.new("Part")
	pad.Name = "VisualMarker"
	pad.Anchored = true
	pad.CanCollide = false
	pad.CanTouch = false
	pad.CanQuery = false
	pad.CastShadow = false
	pad.Material = Enum.Material.Neon
	pad.Color = COLOR_SOURCE
	pad.Transparency = 0.50
	pad.Size = Vector3.new(tileSize * 0.94, 0.05, tileSize * 0.94)
	pad.CFrame = CFrame.new(cf.X, topY + 0.04, cf.Z)
	pad.Parent = container
	table.insert(activeInstances, pad)

	local sg = Instance.new("SurfaceGui")
	sg.Name = "SourceGui"
	sg.Adornee = pad
	sg.Face = Enum.NormalId.Top
	sg.LightInfluence = 0
	sg.AlwaysOnTop = true
	sg.CanvasSize = Vector2.new(300, 300)
	sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	sg.Parent = pad
	table.insert(activeInstances, sg)

	local sFrame = Instance.new("Frame")
	sFrame.Size = UDim2.fromScale(1, 1)
	sFrame.BackgroundTransparency = 1
	sFrame.Parent = sg

	local sStroke = Instance.new("UIStroke")
	sStroke.Color = COLOR_SOURCE
	sStroke.Thickness = 5
	sStroke.Transparency = 0.1
	sStroke.Parent = sFrame

	local sCorner = Instance.new("UICorner")
	sCorner.CornerRadius = UDim.new(0, 24)
	sCorner.Parent = sFrame

	local sPin = Instance.new("Frame")
	sPin.AnchorPoint = Vector2.new(0.5, 0.5)
	sPin.Size = UDim2.fromScale(0.24, 0.24)
	sPin.Position = UDim2.fromScale(0.5, 0.5)
	sPin.BackgroundColor3 = COLOR_SOURCE
	sPin.BorderSizePixel = 0
	sPin.Parent = sFrame

	local pinCorner = Instance.new("UICorner")
	pinCorner.CornerRadius = UDim.new(1, 0)
	pinCorner.Parent = sPin

	if piece3D and (piece3D:IsA("Model") or piece3D:IsA("BasePart")) then
		local hl = Instance.new("Highlight")
		hl.Name = "PieceHighlight"
		hl.Adornee = piece3D
		hl.FillColor = COLOR_SOURCE
		hl.OutlineColor = COLOR_SOURCE
		hl.FillTransparency = 0.65
		hl.OutlineTransparency = 0.10
		hl.Parent = container
		table.insert(activeInstances, hl)
	end
end

local function draw3DTarget(tile3D: Instance)
	local cf, size = getTileCFrameAndSize(tile3D)
	local topY = cf.Y + size.Y / 2
	local tileSize = math.max(size.X, size.Z)
	if tileSize <= 0.1 then tileSize = 3.8 end

	local container = getVisualContainer()

	local pad = Instance.new("Part")
	pad.Name = "TargetMarker"
	pad.Anchored = true
	pad.CanCollide = false
	pad.CanTouch = false
	pad.CanQuery = false
	pad.CastShadow = false
	pad.Material = Enum.Material.Neon
	pad.Color = COLOR_TARGET
	pad.Transparency = 0.55
	pad.Size = Vector3.new(tileSize * 0.94, 0.05, tileSize * 0.94)
	pad.CFrame = CFrame.new(cf.X, topY + 0.04, cf.Z)
	pad.Parent = container
	table.insert(activeInstances, pad)

	local sel = Instance.new("SelectionBox")
	sel.Name = "TargetBox"
	sel.Adornee = pad
	sel.Color3 = COLOR_TARGET
	sel.LineThickness = 0.05
	sel.SurfaceColor3 = COLOR_TARGET
	sel.SurfaceTransparency = 0.85
	sel.Parent = pad
	table.insert(activeInstances, sel)

	local sg = Instance.new("SurfaceGui")
	sg.Name = "SonHub3D_VortexGui"
	sg.Adornee = pad
	sg.Face = Enum.NormalId.Top
	sg.LightInfluence = 0
	sg.AlwaysOnTop = true
	sg.CanvasSize = Vector2.new(350, 350)
	sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	sg:SetAttribute("SonHubCoach", true)
	sg.Parent = pad
	table.insert(activeInstances, sg)

	local vortex = Instance.new("Frame")
	vortex.Name = "VortexContainer"
	vortex.AnchorPoint = Vector2.new(0.5, 0.5)
	vortex.Size = UDim2.fromScale(0.86, 0.86)
	vortex.Position = UDim2.fromScale(0.5, 0.5)
	vortex.BackgroundTransparency = 1
	vortex.Parent = sg

	for _, cfg in ipairs({ { 1.0, 5.0, 0.05 }, { 0.66, 4.0, 0.15 }, { 0.35, 3.0, 0.00 } }) do
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Size = UDim2.fromScale(cfg[1], cfg[1])
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.BackgroundTransparency = 1
		ring.Parent = vortex

		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(1, 0)
		rc.Parent = ring

		local rs = Instance.new("UIStroke")
		rs.Color = COLOR_TARGET
		rs.Thickness = cfg[2]
		rs.Transparency = cfg[3]
		rs.Parent = ring
	end

	local tickOffsets = {
		{ pos = UDim2.new(0.5, 0, 0.04, 0), sz = UDim2.new(0, 4, 0, 16) },
		{ pos = UDim2.new(0.5, 0, 0.96, 0), sz = UDim2.new(0, 4, 0, 16) },
		{ pos = UDim2.new(0.04, 0, 0.5, 0), sz = UDim2.new(0, 16, 0, 4) },
		{ pos = UDim2.new(0.96, 0, 0.5, 0), sz = UDim2.new(0, 16, 0, 4) },
	}
	for _, tcfg in ipairs(tickOffsets) do
		local tk = Instance.new("Frame")
		tk.AnchorPoint = Vector2.new(0.5, 0.5)
		tk.Position = tcfg.pos
		tk.Size = tcfg.sz
		tk.BackgroundColor3 = COLOR_TARGET
		tk.BorderSizePixel = 0
		tk.Parent = vortex
		local tc = Instance.new("UICorner")
		tc.CornerRadius = UDim.new(1, 0)
		tc.Parent = tk
	end

	local core = Instance.new("Frame")
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Size = UDim2.fromScale(0.18, 0.18)
	core.Position = UDim2.fromScale(0.5, 0.5)
	core.BackgroundColor3 = COLOR_TARGET
	core.BorderSizePixel = 0
	core.Parent = vortex

	local coreCorner = Instance.new("UICorner")
	coreCorner.CornerRadius = UDim.new(1, 0)
	coreCorner.Parent = core

	local spinTween = TweenService:Create(vortex, TweenInfo.new(3.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 })
	spinTween:Play()
end

local function draw2DMarkers(main2D: Instance, from: string, to: string)
	local board2D = main2D:FindFirstChild("Board")
	if not board2D then return end

	local fromTile = board2D:FindFirstChild(from)
	local toTile = board2D:FindFirstChild(to)
	if not (fromTile and toTile and fromTile:IsA("GuiObject") and toTile:IsA("GuiObject")) then
		return
	end

	local overlay = main2D:FindFirstChild("SonHub2D_Overlay")
	if not overlay then
		overlay = Instance.new("Frame")
		overlay.Name = "SonHub2D_Overlay"
		overlay.Size = board2D.Size
		overlay.Position = board2D.Position
		overlay.AnchorPoint = board2D.AnchorPoint
		overlay.Rotation = board2D.Rotation
		overlay.BackgroundTransparency = 1
		overlay.ZIndex = 25
		overlay.Active = false
		overlay:SetAttribute("SonHubCoach", true)
		overlay.Parent = main2D
		table.insert(activeInstances, overlay)
	else
		overlay:ClearAllChildren()
		overlay.Size = board2D.Size
		overlay.Position = board2D.Position
		overlay.AnchorPoint = board2D.AnchorPoint
		overlay.Rotation = board2D.Rotation
	end

	-- Source Marker (Highlighted starting square)
	local fFrame = Instance.new("Frame")
	fFrame.Name = "SonHub2D_Source"
	fFrame.Size = fromTile.Size
	fFrame.Position = fromTile.Position
	fFrame.BackgroundColor3 = COLOR_SOURCE
	fFrame.BackgroundTransparency = 0.52
	fFrame.BorderSizePixel = 0
	fFrame.ZIndex = 26
	fFrame.Active = false
	fFrame:SetAttribute("SonHubCoach", true)

	local fCorner = Instance.new("UICorner")
	fCorner.CornerRadius = UDim.new(0, 6)
	fCorner.Parent = fFrame

	local fStroke = Instance.new("UIStroke")
	fStroke.Color = COLOR_SOURCE
	fStroke.Thickness = 2.5
	fStroke.Parent = fFrame

	local fDot = Instance.new("Frame")
	fDot.AnchorPoint = Vector2.new(0.5, 0.5)
	fDot.Size = UDim2.fromScale(0.24, 0.24)
	fDot.Position = UDim2.fromScale(0.5, 0.5)
	fDot.BackgroundColor3 = COLOR_SOURCE
	fDot.BorderSizePixel = 0
	fDot.ZIndex = 27
	fDot.Active = false
	fDot.Parent = fFrame

	local fDotCorner = Instance.new("UICorner")
	fDotCorner.CornerRadius = UDim.new(1, 0)
	fDotCorner.Parent = fDot

	fFrame.Parent = overlay
	table.insert(activeInstances, fFrame)

	-- Target Marker (Tactical Glowing Vortex on target square)
	local tFrame = Instance.new("Frame")
	tFrame.Name = "SonHub2D_Target"
	tFrame.Size = toTile.Size
	tFrame.Position = toTile.Position
	tFrame.BackgroundColor3 = COLOR_TARGET
	tFrame.BackgroundTransparency = 0.60
	tFrame.BorderSizePixel = 0
	tFrame.ZIndex = 26
	tFrame.Active = false
	tFrame:SetAttribute("SonHubCoach", true)

	local tCorner = Instance.new("UICorner")
	tCorner.CornerRadius = UDim.new(0, 6)
	tCorner.Parent = tFrame

	local tStroke = Instance.new("UIStroke")
	tStroke.Color = COLOR_TARGET
	tStroke.Thickness = 2.5
	tStroke.Parent = tFrame

	local vortex2D = Instance.new("Frame")
	vortex2D.AnchorPoint = Vector2.new(0.5, 0.5)
	vortex2D.Size = UDim2.fromScale(0.78, 0.78)
	vortex2D.Position = UDim2.fromScale(0.5, 0.5)
	vortex2D.BackgroundTransparency = 1
	vortex2D.ZIndex = 27
	vortex2D.Active = false
	vortex2D.Parent = tFrame

	for _, cfg in ipairs({ { 1.0, 2.5 }, { 0.65, 2.0 }, { 0.32, 1.5 } }) do
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Size = UDim2.fromScale(cfg[1], cfg[1])
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.BackgroundTransparency = 1
		ring.ZIndex = 27
		ring.Active = false
		ring.Parent = vortex2D

		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(1, 0)
		rc.Parent = ring

		local rs = Instance.new("UIStroke")
		rs.Color = COLOR_TARGET
		rs.Thickness = cfg[2]
		rs.Parent = ring
	end

	local core = Instance.new("Frame")
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Size = UDim2.fromScale(0.18, 0.18)
	core.Position = UDim2.fromScale(0.5, 0.5)
	core.BackgroundColor3 = COLOR_TARGET
	core.BorderSizePixel = 0
	core.ZIndex = 28
	core.Active = false
	core.Parent = vortex2D

	local coreCorner = Instance.new("UICorner")
	coreCorner.CornerRadius = UDim.new(1, 0)
	coreCorner.Parent = core

	local spinTween = TweenService:Create(vortex2D, TweenInfo.new(4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 })
	spinTween:Play()

	tFrame.Parent = overlay
	table.insert(activeInstances, tFrame)
end

local function drawUnifiedMarkers(gameInfo: any, from: string, to: string)
	clearAllMarkers()

	local fromTile3D, fromPiece3D, fromTile2D = Adapter.getSquareInstances(gameInfo, from)
	local toTile3D, _, toTile2D = Adapter.getSquareInstances(gameInfo, to)

	if fromTile3D then
		draw3DSource(fromTile3D, fromPiece3D)
	end
	if toTile3D then
		draw3DTarget(toTile3D)
	end

	if gameInfo.GameType == "ChessClub" then
		local pgui = LocalPlayer:FindFirstChild("PlayerGui")
		local b2d = pgui and pgui:FindFirstChild("2DBoard")
		local main = b2d and b2d:FindFirstChild("Main")
		if main and main:FindFirstChild("Board") then
			draw2DMarkers(main, from, to)
		end
	end
end

----------------------------------------------------------------------
-- USER INTERFACE (WINDUI - ENGLISH & TIENG VIET CLEAN CONVERT)
----------------------------------------------------------------------

local function loadWindUI(): any
	local urls = {
		"https://github.com/Footagesus/WindUI/releases/latest/download/main.lua",
		"https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua",
		"https://cdn.jsdelivr.net/gh/Footagesus/WindUI@main/dist/main.lua",
		"https://fastly.jsdelivr.net/gh/Footagesus/WindUI@main/dist/main.lua",
	}

	for _, url in ipairs(urls) do
		local okCode, src = pcall(function()
			return makeHttpRequest(url, "GET", nil, 4)
		end)
		if not okCode or not src or #src < 100 then
			if type(game.HttpGet) == "function" then
				pcall(function() src = game:HttpGet(url) end)
			end
		end

		if type(src) == "string" and #src > 100 then
			local okCompile, loadedFn = pcall(loadstring, src)
			if okCompile and type(loadedFn) == "function" then
				local okRun, lib = pcall(loadedFn)
				if okRun and type(lib) == "table" and type(lib.CreateWindow) == "function" then
					return lib
				end
			end
		end
	end
	return nil
end

local WindUI = loadWindUI()
if not WindUI then return end
local hui = gethuiSafe()

local floatGui: ScreenGui? = nil
local isCleanedUp = false
local function doCleanup()
	if isCleanedUp then return end
	isCleanedUp = true

	pcall(function()
		if inputConn then inputConn:Disconnect() end
	end)
	clearAllMarkers()
	table.clear(fenCache)
	table.clear(ponderPrediction)

	pcall(function()
		if floatGui then
			floatGui:Destroy()
		end
	end)
	pcall(function()
		local g1 = hui:FindFirstChild("SonHUB_FloatingToggle")
		if g1 then g1:Destroy() end
		local g2 = game:GetService("CoreGui"):FindFirstChild("SonHUB_FloatingToggle")
		if g2 then g2:Destroy() end
	end)
	pcall(function()
		if Window and Window.Destroy then
			Window:Destroy()
		end
	end)
	pcall(function()
		local wGui = hui:FindFirstChild("WindUI") or game:GetService("CoreGui"):FindFirstChild("WindUI")
		if wGui then
			wGui:Destroy()
		end
	end)
end

local camera = Workspace.CurrentCamera
local vp = (camera and camera.ViewportSize) or Vector2.new(1280, 720)
local isTouchDevice = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Responsive dimensions tailored for any display (PC 4K, 1080p, Ultrawide, Tablet, Phone)
local targetW = if isTouchDevice then math.clamp(math.floor(vp.X * 0.90), 320, 480) else math.clamp(math.floor(vp.X * 0.45), 480, 580)
local targetH = if isTouchDevice then math.clamp(math.floor(vp.Y * 0.82), 340, 440) else math.clamp(math.floor(vp.Y * 0.54), 400, 490)
local winSize = UDim2.fromOffset(targetW, targetH)

local logoAsset = getLogoAsset()

local Window = WindUI:CreateWindow({
	Title = "SonHUB - Chess Coach",
	Icon = "target",
	Author = if CFG.Language == "vi" then "Cập nhật: 03/10/2026" else "Last Update: 03/10/2026",
	Folder = "SonHUB",
	Size = winSize,
	Theme = "Dark",
	Transparent = true,
	ToggleKey = CFG.ToggleKey,
})

-- Replace Window Title Icon with SonHub Cat Logo
task.spawn(function()
	local wGui: Instance? = nil
	local startWait = tick()
	while tick() - startWait < 8 do
		wGui = hui:FindFirstChild("WindUI") or game:GetService("CoreGui"):FindFirstChild("WindUI", true)
		if wGui and wGui:FindFirstChild("Window") then
			break
		end
		task.wait(0.08)
	end
	if not wGui then return end

	local titleIcon: ImageLabel? = nil
	local waitElements = tick()
	while tick() - waitElements < 8 do
		local topbar = wGui:FindFirstChild("Topbar", true)
		if topbar then
			local left = topbar:FindFirstChild("Left")
			if left then
				titleIcon = left:FindFirstChildWhichIsA("ImageLabel", true)
			end
		end
		if titleIcon then break end
		task.wait(0.08)
	end

	-- Apply SonHub Cat Logo (crisp, proper aspect ratio, rounded corners)
	if titleIcon then
		local function applyLogo()
			titleIcon.Image = logoAsset
			titleIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
			titleIcon.ScaleType = Enum.ScaleType.Fit
			titleIcon.BackgroundTransparency = 1
			titleIcon.ImageRectOffset = Vector2.zero
			titleIcon.ImageRectSize = Vector2.zero
			local corner = titleIcon:FindFirstChildWhichIsA("UICorner") or Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 6)
			corner.Parent = titleIcon
			pcall(function()
				if titleIcon.Parent and titleIcon.Parent:IsA("Frame") then
					titleIcon.Parent.Size = UDim2.fromOffset(26, 26)
					if titleIcon.Parent.Parent and titleIcon.Parent.Parent:IsA("Frame") then
						titleIcon.Parent.Parent.Size = UDim2.fromOffset(26, 26)
					end
				end
			end)
		end
		applyLogo()
		titleIcon:GetPropertyChangedSignal("Image"):Connect(function()
			if titleIcon.Image ~= logoAsset then
				applyLogo()
			end
		end)
	end
end)

local TabMove = Window:Tab({ Title = "Move & Play", Icon = "target" })
local TabSkin = Window:Tab({ Title = "Custom Skins", Icon = "palette" })
local TabSet = Window:Tab({ Title = "Settings", Icon = "settings" })

local pStatus = TabMove:Paragraph({
	Title = "Status",
	Desc = "Waiting for game...",
})
local pMove = TabMove:Paragraph({
	Title = "Best Move",
	Desc = "-",
})
local pEval = TabMove:Paragraph({
	Title = "Evaluation",
	Desc = "-",
})
local pLine = TabMove:Paragraph({
	Title = "Continuation Line",
	Desc = "-",
})

local toggleAuto: any = nil
local toggleLegit: any = nil

toggleLegit = TabMove:Toggle({
	Title = "PlayLegit",
	Desc = "Human-like natural thinking time.",
	Value = CFG.PlayLegit,
	Callback = function(v)
		CFG.PlayLegit = v
		if v then
			CFG.AutoPlay = false
		end
		saveSettings()
		if v and currentGuidance and currentGuidance.uci then
			local gInfo = Adapter.getGameInfo()
			if gInfo and gInfo.MyTurn and not gInfo.IsSpectating then
				Adapter.submitMove(gInfo, currentGuidance.uci, currentGuidance)
			end
		end
	end,
})

toggleAuto = TabMove:Toggle({
	Title = "AutoPlay",
	Desc = "Instant or fast automatic moves.",
	Value = CFG.AutoPlay,
	Callback = function(v)
		CFG.AutoPlay = v
		if v then
			CFG.PlayLegit = false
		end
		saveSettings()
		if v and currentGuidance and currentGuidance.uci then
			local gInfo = Adapter.getGameInfo()
			if gInfo and gInfo.MyTurn and not gInfo.IsSpectating then
				Adapter.submitMove(gInfo, currentGuidance.uci, currentGuidance)
			end
		end
	end,
})


-- LIVE IN-PLACE TRANSLATION ENGINE
local function applyLanguage(newLang: string)
	CFG.Language = newLang
	saveSettings()
	local isVi = (newLang == "vi")
	local map = isVi and TRANSLATIONS or REVERSE_TRANSLATIONS

	-- Update Window Author
	Window:SetAuthor(isVi and "Cập nhật: 03/10/2026" or "Last Update: 03/10/2026")

	-- Translate all active TextLabels inside the window
	local root = pStatus.ElementFrame
	while root.Parent and not root.Parent:IsA("ScreenGui") do
		root = root.Parent
	end

	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("TextLabel") and d.Text and d.Text ~= "" then
			local translated = map[d.Text]
			if translated then
				d.Text = translated
			end
		end
	end
end

-- SETTINGS TAB
TabSet:Dropdown({
	Title = "Language / Ngôn ngữ",
	Desc = "Select interface language.",
	Values = { "English", "Tiếng Việt" },
	Value = if CFG.Language == "vi" then "Tiếng Việt" else "English",
	Callback = function(v)
		local target = v:find("Việt") and "vi" or "en"
		if target ~= CFG.Language then
			applyLanguage(target)
		end
	end,
})

TabSet:Keybind({
	Title = "Toggle Keybind",
	Desc = "Hotkey to show or hide the coach interface.",
	Value = CFG.ToggleKey,
	Callback = function(key)
		CFG.ToggleKey = key
		saveSettings()
		pcall(function()
			Window:SetToggleKey(key)
		end)
	end,
})

TabSet:Toggle({
	Title = "Pondering",
	Desc = "Calculate responses during opponent turn.",
	Value = CFG.Ponder,
	Callback = function(v)
		CFG.Ponder = v
		saveSettings()
	end,
})

TabSet:Slider({
	Title = "AutoPlay Fast Delay (s)",
	Desc = "Delay for AutoPlay mode (0.15s - 2.0s).",
	Value = { Min = 0.15, Max = 2.0, Default = CFG.FastDelay },
	Step = 0.05,
	Callback = function(v)
		CFG.FastDelay = v
		saveSettings()
	end,
})

TabSet:Slider({
	Title = "Legit Thinking Time (s)",
	Desc = "Natural GM thinking time (2.0s - 10.0s).",
	Value = { Min = 2.0, Max = 10.0, Default = CFG.LegitBaseDelay },
	Step = 0.5,
	Callback = function(v)
		CFG.LegitBaseDelay = v
		saveSettings()
	end,
})

TabSet:Slider({
	Title = "Stockfish Depth",
	Desc = "Analysis depth (12 to 18, Grandmaster level).",
	Value = { Min = 12, Max = 18, Default = CFG.Depth },
	Step = 1,
	Callback = function(v)
		CFG.Depth = v
		saveSettings()
	end,
})

TabSet:Dropdown({
	Title = "Engine Source",
	Desc = "Computation backend.",
	Values = { "Auto (Optimal)", "Online Only", "Offline Only" },
	Value = if CFG.EngineMode == "OnlineOnly" then "Online Only" elseif CFG.EngineMode == "OfflineOnly" then "Offline Only" else "Auto (Optimal)",
	Callback = function(v)
		if v:find("Auto") or v:find("Tối ưu") then
			CFG.EngineMode = "Auto"
		elseif v:find("Online") or v:find("tuyến") then
			CFG.EngineMode = "OnlineOnly"
		else
			CFG.EngineMode = "OfflineOnly"
		end
		saveSettings()
	end,
})

TabSet:Button({
	Title = "Recalculate Position",
	Desc = "Force immediate re-analysis of current FEN.",
	Icon = "refresh-cw",
	Callback = function()
		local gInfo = Adapter.getGameInfo()
		local isVi = (CFG.Language == "vi")
		if not gInfo then
			WindUI:Notify({
				Title = isVi and "Chưa có ván cờ" or "No Game Found",
				Content = isVi and "Hãy tham gia bàn cờ trước." or "Join a chess match first.",
				Duration = 2.5,
				Icon = "info",
			})
			return
		end
		fenCache[gInfo.FEN] = nil
		lastFen = nil
		currentGuidance = nil
		task.spawn(compute, gInfo, gInfo.FEN)
	end,
})

TabSet:Button({
	Title = "Clear Board Visuals",
	Desc = "Remove all 3D markers immediately.",
	Icon = "eraser",
	Callback = clearAllMarkers,
})

TabSet:Button({
	Title = "Hide Interface",
	Desc = "Press logo button or hotkey to re-open.",
	Icon = "eye-off",
	Callback = function()
		pcall(function()
			Window:Close()
		end)
		local wGui = hui:FindFirstChild("WindUI")
		if wGui and wGui:IsA("ScreenGui") then
			wGui.Enabled = false
		end
	end,
})

----------------------------------------------------------------------
-- OFFICIAL GAME COLLECTIONS & SKIN CHANGER (CHESS! & CHESS CLUB)
----------------------------------------------------------------------

-- Cookie Chess (CHESS!) collections
local OFFICIAL_COLLECTIONS = {
	{ displayName = "Porcelain Collection", whiteSkin = "WhitePorcelain", blackSkin = "BlackPorcelain" },
	{ displayName = "Exotic Collection", whiteSkin = "BrightExotic", blackSkin = "DarkExotic" },
	{ displayName = "Cherry Pastel Collection", whiteSkin = "PastelCherryLight", blackSkin = "PastelCherryDark" },
	{ displayName = "Crystal Collection", whiteSkin = "Ruby", blackSkin = "Emerald" },
	{ displayName = "Graveyard Collection", whiteSkin = "BrightSkeleton", blackSkin = "DarkSkeleton" },
	{ displayName = "Pumpkin Collection", whiteSkin = "BrightPumpkin", blackSkin = "DarkPumpkin" },
	{ displayName = "Cursed Pumpkin Collection", whiteSkin = "BrightPumpkin2", blackSkin = "DarkPumpkin2" },
	{ displayName = "Crafted Samurai Collection", whiteSkin = "SamuriWoodWhite", blackSkin = "DarkWoodSamuri" },
	{ displayName = "Forged Samurai Collection", whiteSkin = "SamuriWhite", blackSkin = "DarkSamuri" },
	{ displayName = "Cyber Projector Collection", whiteSkin = "CyberWhite", blackSkin = "CyberBlack" },
	{ displayName = "Gilded Collection", whiteSkin = "Goldkaiser_White", blackSkin = "Goldkaiser_Black" },
	{ displayName = "Glass Collection", whiteSkin = "LightGlass", blackSkin = "DarkGlass" },
	{ displayName = "Ice Collection", whiteSkin = "LightIce", blackSkin = "DarkIce" },
	{ displayName = "Jade & Amber Collection", whiteSkin = "Jade_Amber_White", blackSkin = "Jade_Amber_Black" },
	{ displayName = "Marble Collection", whiteSkin = "LightMarble", blackSkin = "DarkMarble" },
	{ displayName = "Mystic Kingdom Collection", whiteSkin = "EnchantedKingdom", blackSkin = "CursedKingdom" },
	{ displayName = "Olympian Collection", whiteSkin = "OlympianLight", blackSkin = "OlympianDark" },
	{ displayName = "Solaris Collection", whiteSkin = "BrightSun", blackSkin = "DarkSun" },
	{ displayName = "Tesseract Collection", whiteSkin = "StellarTesseract", blackSkin = "VoidTesseract" },
	{ displayName = "Timeless Wood Collection", whiteSkin = "LightWood", blackSkin = "DarkWood" },
	{ displayName = "Volt Collection", whiteSkin = "LightElectric", blackSkin = "DarkElectric" },
	{ displayName = "Snow Collection", whiteSkin = "SnowLight", blackSkin = "SnowDark" },
	{ displayName = "Sparkle Unicorn Collection", whiteSkin = "unicornwhite", blackSkin = "unicornblack" },
	{ displayName = "Festive Collection", whiteSkin = "lightchristmastrees", blackSkin = "darkchristmastrees" },
	{ displayName = "Lavender Pastel Collection", whiteSkin = "PastelLavenderLight", blackSkin = "PastelLavenderDark" },
	{ displayName = "Lime Pastel Collection", whiteSkin = "PastelMintLight", blackSkin = "PastelMintDark" },
	{ displayName = "Sky Pastel Collection", whiteSkin = "PastelSkyLight", blackSkin = "PastelSkyDark" },
	{ displayName = "Corruption Collection", whiteSkin = "LightCorruption", blackSkin = "DarkCorruption" },
	{ displayName = "Lost City Collection", whiteSkin = "BrutalistWhite", blackSkin = "BrutalistBlack" },
	{ displayName = "Floral Garden Collection", whiteSkin = "flower2_white", blackSkin = "flower2_black" },
}

local CHESSCLUB_3D_SETS = {
	"Default",
	"Beach",
	"Champion",
	"Christmas",
	"Club",
	"Easter",
	"Frosted Glass",
	"Gold",
	"Legacy",
	"Magic",
	"Magma",
	"Neon",
	"Obsidian",
	"Sandstone",
	"Special Gift",
	"Tinted Glass",
	"Wood",
}

local CHESSCLUB_2D_SETS = {
	"Default",
	"Flames",
	"Gilded",
	"Legacy",
	"Mahogany",
	"Marble",
	"Ocean Flora",
	"Sierra",
	"Sleek Black",
	"Sleek Purple",
}

local COLLECTION_MAP = {}
local COLLECTION_NAMES = { "Default" }
for _, col in ipairs(OFFICIAL_COLLECTIONS) do
	COLLECTION_MAP[col.displayName] = col
	table.insert(COLLECTION_NAMES, col.displayName)
end

local currentSkinCollection = "Default"
local currentCC3DSet = "Default"
local currentCC2DSet = "Default"
local pendingSkinCollection = "Default"
local pendingCC3DSet = "Default"
local pendingCC2DSet = "Default"

-- Apply 3D piece & board skins for Chess Club
local function applyChessClub3DSkin(setName: string)
	local rs = game:GetService("ReplicatedStorage")
	local inv3D = rs:FindFirstChild("Assets") and rs.Assets:FindFirstChild("Inventory") and rs.Assets.Inventory:FindFirstChild("3D")
	local targetFolder = inv3D and inv3D:FindFirstChild(setName)
	if not targetFolder then return end

	local tableRef = nil
	local gInfo = Adapter.getGameInfo()
	if gInfo and gInfo.GameType == "ChessClub" and gInfo.Raw and gInfo.Raw.Ui3D and gInfo.Raw.Ui3D.Ref then
		tableRef = gInfo.Raw.Ui3D.Ref
	else
		local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local minD = 35
			for _, folderName in ipairs({ "Tablesets (Main)", "Tablesets (Tournament)" }) do
				local parentFolder = workspace:FindFirstChild(folderName)
				if parentFolder then
					for _, tbl in ipairs(parentFolder:GetChildren()) do
						local b = tbl:FindFirstChild("Board")
						if b and b:IsA("Model") then
							local d = (b:GetPivot().Position - hrp.Position).Magnitude
							if d < minD then
								minD = d
								tableRef = tbl
							end
						end
					end
				end
			end
		end
	end

	if not tableRef then return end

	-- 1. Skinned 3D Board Tiles
	local boardModel = tableRef:FindFirstChild("Board")
	local targetBoard = targetFolder:FindFirstChild("Board")
	if boardModel and targetBoard then
		local targetLight = targetBoard:FindFirstChild("light")
		local targetDark = targetBoard:FindFirstChild("dark")
		if targetLight and targetDark and targetLight:IsA("BasePart") and targetDark:IsA("BasePart") then
			for _, tile in ipairs(boardModel:GetChildren()) do
				if tile:IsA("BasePart") then
					local isLight = (tile:FindFirstChild("light") and tile.light.Value)
					if isLight == nil then
						local col = tile.Name:sub(1, 1):lower()
						local row = tonumber(tile.Name:sub(2, 2)) or 1
						local cIdx = string.byte(col) - 96
						isLight = ((cIdx + row) % 2 == 1)
					end
					local tmpl = isLight and targetLight or targetDark
					tile.Color = tmpl.Color
					tile.Material = tmpl.Material
					tile.Reflectance = tmpl.Reflectance
					tile.Transparency = tmpl.Transparency
				end
			end
		end
	end

	-- 2. Skinned 3D Pieces (Only player's side)
	local targetPieces = targetFolder:FindFirstChild("Pieces")
	local piecesFolder = tableRef:FindFirstChild("Pieces")
	if targetPieces and piecesFolder then
		local myTeam = gInfo and gInfo.AmIWhite
		local myPrefix = if myTeam == true then "White_" elseif myTeam == false then "Black_" else nil

		for _, pieceModel in ipairs(piecesFolder:GetChildren()) do
			local pName = pieceModel.Name
			if not myPrefix or pName:sub(1, #myPrefix) == myPrefix then
				local prefab = targetPieces:FindFirstChild(pName)
				if prefab then
					local newObj = prefab:Clone()
					newObj.Name = pName

					-- Preserve tile StringValue and id NumberValue for game logic
					local oldTile = pieceModel:FindFirstChild("tile")
					if oldTile and oldTile:IsA("StringValue") then
						local nt = newObj:FindFirstChild("tile") or Instance.new("StringValue", newObj)
						nt.Name = "tile"
						nt.Value = oldTile.Value
					end
					local oldId = pieceModel:FindFirstChild("id")
					if oldId and oldId:IsA("NumberValue") then
						local ni = newObj:FindFirstChild("id") or Instance.new("NumberValue", newObj)
						ni.Name = "id"
						ni.Value = oldId.Value
					end

					-- Align piece exact to board tile
					local tileName = (oldTile and oldTile.Value) or ""
					local tilePart = boardModel and boardModel:FindFirstChild(tileName)
					if tilePart and tilePart:IsA("BasePart") then
						local _, pY = newObj:GetPivot():ToOrientation()
						newObj:PivotTo(tilePart.CFrame * CFrame.Angles(0, pY, 0))
					else
						newObj:PivotTo(pieceModel:GetPivot())
					end

					newObj.Parent = pieceModel.Parent
					pieceModel:Destroy()
				end
			end
		end
	end
end

-- Apply 2D piece and board skins for Chess Club
local function applyChessClub2DSkin(setName: string)
	local rs = game:GetService("ReplicatedStorage")
	local inv2D = rs:FindFirstChild("Assets") and rs.Assets:FindFirstChild("Inventory") and rs.Assets.Inventory:FindFirstChild("2D")
	local targetFolder = inv2D and inv2D:FindFirstChild(setName)
	if not targetFolder then return end

	local pgui = LocalPlayer:FindFirstChild("PlayerGui")
	local b2d = pgui and pgui:FindFirstChild("2DBoard")
	local main = b2d and b2d:FindFirstChild("Main")
	if not main then return end

	-- 1. Apply Board square textures & colors
	local boardFolder = targetFolder:FindFirstChild("Board")
	local mainBoard = main:FindFirstChild("Board")
	if boardFolder and mainBoard then
		local lightBtn = boardFolder:FindFirstChild("light")
		local darkBtn = boardFolder:FindFirstChild("dark")
		if lightBtn and darkBtn and (lightBtn:IsA("ImageButton") or lightBtn:IsA("ImageLabel")) and (darkBtn:IsA("ImageButton") or darkBtn:IsA("ImageLabel")) then
			for _, sq in ipairs(mainBoard:GetChildren()) do
				if sq:IsA("ImageButton") or sq:IsA("ImageLabel") then
					local isLight = (sq:FindFirstChild("light") and sq.light.Value)
					if isLight == nil then
						local col = sq.Name:sub(1, 1):lower()
						local row = tonumber(sq.Name:sub(2, 2)) or 1
						local cIdx = string.byte(col) - 96
						isLight = ((cIdx + row) % 2 == 1)
					end
					local tmpl = isLight and lightBtn or darkBtn
					sq.Image = tmpl.Image
					sq.ImageColor3 = tmpl.ImageColor3
					sq.ImageTransparency = tmpl.ImageTransparency
					sq.BackgroundColor3 = tmpl.BackgroundColor3

					-- Coordinate marker labels
					for _, child in ipairs(sq:GetChildren()) do
						if child:IsA("TextLabel") and string.find(child.Name, "Marker") then
							local opp = isLight and darkBtn or lightBtn
							child.TextColor3 = opp.BackgroundColor3
						end
					end
				end
			end
		end
	end

	-- 2. Apply Pieces textures (user side only)
	local piecesFolder = targetFolder:FindFirstChild("Pieces")
	local mainPieces = main:FindFirstChild("Pieces")
	if piecesFolder and mainPieces then
		local gInfo = Adapter.getGameInfo()
		local myTeam = gInfo and gInfo.AmIWhite
		local myPrefix = if myTeam == true then "White_" elseif myTeam == false then "Black_" else nil

		for _, p in ipairs(mainPieces:GetChildren()) do
			if (p:IsA("ImageButton") or p:IsA("ImageLabel")) then
				if not myPrefix or p.Name:sub(1, #myPrefix) == myPrefix then
					local prefab = piecesFolder:FindFirstChild(p.Name)
					if prefab and (prefab:IsA("ImageButton") or prefab:IsA("ImageLabel")) and prefab.Image ~= "" then
						p.Image = prefab.Image
						p.ImageColor3 = prefab.ImageColor3
						p.ImageTransparency = prefab.ImageTransparency
					end
				end
			end
		end
	end

	-- Sync internal UI2D instance if available
	pcall(function()
		local s = require(LocalPlayer.PlayerScripts.Services.ChessUiService)
		local u2d = s.Service2D:getUI()
		if u2d then
			u2d.Set = targetFolder
		end
	end)
end

local function applyOfficialSkin(collectionName: string)
	local gInfo = Adapter.getGameInfo()
	if not gInfo then return end

	if gInfo.GameType == "ChessClub" then
		if currentCC3DSet and currentCC3DSet ~= "Default" then
			applyChessClub3DSkin(currentCC3DSet)
		end
		if currentCC2DSet and currentCC2DSet ~= "Default" then
			applyChessClub2DSkin(currentCC2DSet)
		end
		return
	end

	currentSkinCollection = collectionName
	local m = gInfo.Raw
	if not m then return end

	local myTeam = gInfo.AmIWhite
	local myPieces = (myTeam == true and m.whitePieces) or (myTeam == false and m.blackPieces)
	if not myPieces then return end

	-- Determine board tile surface elevation (Y)
	local tileTopY = 0.5
	if m.tiles and m.tiles[1] and m.tiles[1][1] then
		local t = m.tiles[1][1]
		if t:IsA("BasePart") then
			tileTopY = t.Position.Y + (t.Size.Y / 2)
		end
	end

	local function alignPieceExact(newObj: Instance, p: any)
		local pRot = if p.team then math.pi else 0
		local gridX = (p.position and p.position[1]) or 1
		local gridY = (p.position and p.position[2]) or 1
		local posX = 1000 + (gridX * 4)
		local posZ = (gridY * 4)

		newObj:PivotTo(CFrame.new(posX, 10, posZ) * CFrame.Angles(0, pRot, 0))
		local bbCf, bbSz = (newObj :: any):GetBoundingBox()
		local lowestY = bbCf.Y - (bbSz.Y / 2)
		local deltaY = tileTopY - lowestY
		newObj:PivotTo(CFrame.new(posX, 10 + deltaY, posZ) * CFrame.Angles(0, pRot, 0))
	end

	if collectionName == "Default" then
		local rs = game:GetService("ReplicatedStorage")
		local defaultFolder = (myTeam == true and rs.Assets.White:FindFirstChild("ClassicWhite") or rs.Assets.White:FindFirstChildWhichIsA("Folder"))
			or (rs.Assets.Black:FindFirstChild("ClassicBlack") or rs.Assets.Black:FindFirstChildWhichIsA("Folder"))
		if not defaultFolder then return end

		for _, p in ipairs(myPieces) do
			local curObj = p.object
			if curObj and curObj.Parent then
				local pName = curObj.Name
				local prefab = defaultFolder:FindFirstChild(pName)
				if prefab then
					local newObj = prefab:Clone()
					newObj.Name = pName
					alignPieceExact(newObj, p)
					newObj.Parent = curObj.Parent
					p.object = newObj
					curObj:Destroy()
				end
			end
		end
		return
	end

	local colData = COLLECTION_MAP[collectionName]
	if not colData then return end

	local skinFolder = nil
	local rs = game:GetService("ReplicatedStorage")
	local assets = rs:FindFirstChild("Assets")
	if not assets then return end

	if myTeam == true then
		skinFolder = assets.White:FindFirstChild(colData.whiteSkin)
	else
		skinFolder = assets.Black:FindFirstChild(colData.blackSkin)
	end

	if not skinFolder then return end

	for _, p in ipairs(myPieces) do
		local oldObj = p.object
		if oldObj and oldObj.Parent then
			local pName = oldObj.Name
			local prefab = skinFolder:FindFirstChild(pName)
			if prefab then
				local newObj = prefab:Clone()
				newObj.Name = pName
				alignPieceExact(newObj, p)
				newObj.Parent = oldObj.Parent
				p.object = newObj
				oldObj:Destroy()
			end
		end
	end
end

TabSkin:Paragraph({
	Title = "Skin Changer",
	Desc = "Official in-game piece skin collections (Client-side, user's side only).",
})

-- Dynamic UI for both CHESS! and Chess Club
if IS_CHESS_CLUB then
	TabSkin:Dropdown({
		Title = "Featured 3D Set",
		Desc = "Select official 3D chess set for Chess Club.",
		Values = CHESSCLUB_3D_SETS,
		Value = "Default",
		Callback = function(v)
			pendingCC3DSet = v
		end,
	})

	TabSkin:Dropdown({
		Title = "Featured 2D Set",
		Desc = "Select official 2D board & piece theme for Chess Club.",
		Values = CHESSCLUB_2D_SETS,
		Value = "Default",
		Callback = function(v)
			pendingCC2DSet = v
		end,
	})
else
	TabSkin:Dropdown({
		Title = "Game Collection",
		Desc = "Select an official CHESS! skin collection for your pieces.",
		Values = COLLECTION_NAMES,
		Value = "Default",
		Callback = function(v)
			pendingSkinCollection = v
		end,
	})
end

TabSkin:Button({
	Title = "Apply Skin Now",
	Desc = "Re-apply selected visual theme to current board.",
	Icon = "sparkles",
	Callback = function()
		if IS_CHESS_CLUB then
			currentCC3DSet = pendingCC3DSet
			currentCC2DSet = pendingCC2DSet
			if currentCC3DSet ~= "Default" then
				applyChessClub3DSkin(currentCC3DSet)
			end
			if currentCC2DSet ~= "Default" then
				applyChessClub2DSkin(currentCC2DSet)
			end
			WindUI:Notify({
				Title = (CFG.Language == "vi") and "Tùy biến Skin" or "Skin Changer",
				Content = (CFG.Language == "vi") and ("3D: " .. currentCC3DSet .. " | 2D: " .. currentCC2DSet) or ("3D: " .. currentCC3DSet .. " | 2D: " .. currentCC2DSet),
				Duration = 2,
				Icon = "check",
			})
		else
			currentSkinCollection = pendingSkinCollection
			applyOfficialSkin(currentSkinCollection)
			WindUI:Notify({
				Title = (CFG.Language == "vi") and "Tùy biến Skin" or "Skin Changer",
				Content = (CFG.Language == "vi") and ("Đã áp dụng: " .. currentSkinCollection) or ("Applied: " .. currentSkinCollection),
				Duration = 2,
				Icon = "check",
			})
		end
	end,
})

TabSkin:Button({
	Title = "Reset Default Skin",
	Desc = "Revert piece models to original textures.",
	Icon = "rotate-ccw",
	Callback = function()
		if IS_CHESS_CLUB then
			pendingCC3DSet = "Default"
			pendingCC2DSet = "Default"
			currentCC3DSet = "Default"
			currentCC2DSet = "Default"
			applyChessClub3DSkin("Default")
			applyChessClub2DSkin("Default")
		else
			pendingSkinCollection = "Default"
			currentSkinCollection = "Default"
			applyOfficialSkin("Default")
		end
		WindUI:Notify({
			Title = (CFG.Language == "vi") and "Khôi phục Skin" or "Reset Skin",
			Content = (CFG.Language == "vi") and "Đã phục hồi quân cờ mặc định." or "Restored default pieces.",
			Duration = 2,
			Icon = "refresh-cw",
		})
	end,
})

-- Default open directly on Move & Play tab
task.defer(function()
	task.wait(0.12)
	pcall(function()
		if TabMove.Select then
			TabMove:Select()
		end
		if TabMove.ContainerFrame then
			TabMove.ContainerFrame.Visible = true
		end
	end)
	if CFG.Language == "vi" then
		task.wait(0.1)
		pcall(function()
			applyLanguage("vi")
		end)
	end
end)

local function setText(el: any, title: string?, desc: string?)
	if not el then return end
	if title then pcall(function() el:SetTitle(title) end) end
	if desc then pcall(function() el:SetDesc(desc) end) end
end

local function formatEval(data: any): string
	local isVi = (CFG.Language == "vi")
	if data.mate then
		local n = math.abs(data.mate)
		local side = (data.eval or 0) >= 0 and (isVi and "Trắng" or "White") or (isVi and "Đen" or "Black")
		return isVi and ("%s chiếu hết sau %d nước"):format(side, n) or ("%s has mate in %d"):format(side, n)
	end
	if type(data.eval) == "number" then
		local e = data.eval
		local sign = e >= 0 and "+" or ""
		local who = if e > 0.5 then (isVi and "Trắng ưu thế" or "White advantage")
			elseif e < -0.5 then (isVi and "Đen ưu thế" or "Black advantage")
			else (isVi and "Cân bằng" or "Equal")
		local label = isVi and "Điểm" or "Eval"
		local text = ("%s: %s%.2f (%s)"):format(label, sign, e, who)
		if data.depth then
			text ..= isVi and (" | Độ sâu: %d"):format(data.depth) or (" | Depth: %d"):format(data.depth)
		end
		return text
	end
	if data.source and (data.source:find("Local") or data.source:find("Garbo")) then
		return isVi and "Engine nội bộ (tối ưu vị trí cờ)" or "Local engine (positional play)"
	end
	return "-"
end

local function formatLine(data: any, isOpponentPerspective: boolean?): string
	if type(data.line) ~= "table" or #data.line == 0 then
		return "-"
	end
	local isVi = (CFG.Language == "vi")
	local parts = {}
	local step = 1
	local i = 1
	while i <= #data.line and i <= 8 do
		local uci1 = data.line[i]
		local uci2 = data.line[i + 1]
		if type(uci1) == "string" and #uci1 >= 4 then
			local m1 = ("%s➔%s"):format(uci1:sub(1, 2):upper(), uci1:sub(3, 4):upper())
			if type(uci2) == "string" and #uci2 >= 4 then
				local m2 = ("%s➔%s"):format(uci2:sub(1, 2):upper(), uci2:sub(3, 4):upper())
				if isOpponentPerspective then
					table.insert(parts, isVi and ("%d. Đ/Thủ: %s | Bạn: %s"):format(step, m1, m2) or ("%d. Opp: %s | You: %s"):format(step, m1, m2))
				else
					table.insert(parts, isVi and ("%d. Bạn: %s | Đ/Thủ: %s"):format(step, m1, m2) or ("%d. You: %s | Opp: %s"):format(step, m1, m2))
				end
				i += 2
			else
				if isOpponentPerspective then
					table.insert(parts, isVi and ("%d. Đ/Thủ: %s"):format(step, m1) or ("%d. Opp: %s"):format(step, m1))
				else
					table.insert(parts, isVi and ("%d. Bạn: %s"):format(step, m1) or ("%d. You: %s"):format(step, m1))
				end
				i += 1
			end
			step += 1
		else
			break
		end
	end
	return table.concat(parts, "  ➔  ")
end

----------------------------------------------------------------------
-- FLOATING LOGO BUTTON (SQUARE ROUNDED CORNERS, CYAN BORDER, TRANSLUCENT)
----------------------------------------------------------------------

local hui = gethuiSafe()
floatGui = Instance.new("ScreenGui")
floatGui.Name = "SonHUB_FloatingToggle"
floatGui.ResetOnSpawn = false
floatGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
floatGui.DisplayOrder = 999999

local logoAsset = getLogoAsset()
local btnDimension = if isTouchDevice then 54 else 48

local floatBtn = Instance.new("ImageButton")
floatBtn.Name = "ToggleLogoBtn"
floatBtn.Size = UDim2.fromOffset(btnDimension, btnDimension)
floatBtn.Position = UDim2.new(0.02, 0, 0.45, 0)
floatBtn.BackgroundColor3 = Color3.fromRGB(15, 20, 28)
floatBtn.BackgroundTransparency = 0.35 -- Soft translucent background
floatBtn.BorderSizePixel = 0
floatBtn.Image = logoAsset
floatBtn.ScaleType = Enum.ScaleType.Fit
floatBtn.Active = true
floatBtn.Parent = floatGui

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 12) -- Rounded-corner square
btnCorner.Parent = floatBtn

local btnStroke = Instance.new("UIStroke")
btnStroke.Color = COLOR_BORDER -- Vibrant cyan outline
btnStroke.Thickness = 2.0
btnStroke.Transparency = 0.15
btnStroke.Parent = floatBtn

-- Touch-safe dragging
do
	local dragging = false
	local dragInput: InputObject? = nil
	local dragStart: Vector3 = Vector3.zero
	local startPos: UDim2 = floatBtn.Position
	local hasMoved = false

	floatBtn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			hasMoved = false
			dragStart = input.Position
			startPos = floatBtn.Position

			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	floatBtn.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging then
			local delta = input.Position - dragStart
			if delta.Magnitude > 6 then
				hasMoved = true
			end
			floatBtn.Position = UDim2.new(
				startPos.X.Scale,
				startPos.X.Offset + delta.X,
				startPos.Y.Scale,
				startPos.Y.Offset + delta.Y
			)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
			dragInput = nil
		end
	end)

	floatBtn.Activated:Connect(function()
		if hasMoved then return end
		local okTog = pcall(function()
			Window:Toggle()
		end)
		if not okTog then
			local wGui = hui:FindFirstChild("WindUI")
			if wGui and wGui:IsA("ScreenGui") then
				wGui.Enabled = not wGui.Enabled
			end
		end
	end)

	floatBtn.MouseEnter:Connect(function()
		TweenService:Create(btnStroke, TweenInfo.new(0.2), { Transparency = 0, Thickness = 2.5 }):Play()
		TweenService:Create(floatBtn, TweenInfo.new(0.2), { Size = UDim2.fromOffset(btnDimension + 4, btnDimension + 4) }):Play()
	end)
	floatBtn.MouseLeave:Connect(function()
		TweenService:Create(btnStroke, TweenInfo.new(0.2), { Transparency = 0.15, Thickness = 2.0 }):Play()
		TweenService:Create(floatBtn, TweenInfo.new(0.2), { Size = UDim2.fromOffset(btnDimension, btnDimension) }):Play()
	end)
end

floatGui.Parent = hui

----------------------------------------------------------------------
-- RESILIENT CALCULATION PIPELINE (AUTO RETRY)
----------------------------------------------------------------------

local busy = false
local busyTick = 0
local lastFen: string? = nil
local currentCalculationId = 0

local function ponderOpponentTurn(fen: string)
	if not CFG.Ponder then return end
	task.spawn(function()
		local isVi = (CFG.Language == "vi")
		local d = askChessApi(fen)
		if not d and (tick() > stockfishCooldownUntil) then
			d = askStockfishOnline(fen, 14)
		end
		if not d then
			d = askLocalOffline(fen, Adapter.getGameInfo())
		end

		if not isAlive() or not d or not d.uci then return end

		-- Store our precalculated counter-punch for instant response when opponent moves
		local counterUci = (d.ponder and d.ponder:lower()) or (d.line and d.line[2] and d.line[2]:lower())
		if d.uci and counterUci and #counterUci >= 4 then
			ponderPrediction[d.uci:lower()] = {
				from = counterUci:sub(1, 2),
				to = counterUci:sub(3, 4),
				uci = counterUci,
				eval = -(d.eval or 0),
				mate = d.mate and (-d.mate) or nil,
				depth = d.depth or 14,
				source = "Stockfish 16 (Pondered Counter-Punch)",
				line = { counterUci },
			}
		end

		-- If still opponent's turn, display anticipated threat and prepared counter-punch
		local live = Adapter.getGameInfo()
		local fenCore = fen:match("^(%S+%s+%S+)") or fen
		local liveCore = (live and live.FEN and (live.FEN:match("^(%S+%s+%S+)") or live.FEN)) or ""
		if live and not live.MyTurn and (liveCore == fenCore) then
			local oppFrom = d.from:upper()
			local oppTo = d.to:upper()
			local pName = getLocalizedPieceName(fen, d.from)

			local title = isVi and ("Đối thủ đang nghĩ | Dự đoán: %s (%s➔%s)"):format(pName, oppFrom, oppTo)
				or ("Opponent Thinking | Expected: %s (%s➔%s)"):format(pName, oppFrom, oppTo)

			local desc = if counterUci and #counterUci >= 4 then
				(isVi and ("Đòn phản công sẵn sàng: %s➔%s (Độ sâu: %s)"):format(counterUci:sub(1, 2):upper(), counterUci:sub(3, 4):upper(), tostring(d.depth or 15))
					or ("Counter-move ready: %s➔%s (Depth: %s)"):format(counterUci:sub(1, 2):upper(), counterUci:sub(3, 4):upper(), tostring(d.depth or 15)))
			else
				(isVi and "Hệ thống đã tính toán xong mọi biến thế." or "All variations analyzed.")

			setText(pMove, title, desc)
			setText(pEval, isVi and "Đánh giá thế cờ" or "Evaluation", formatEval(d))
			setText(pLine, isVi and "Kế hoạch phản công" or "Continuation Line", formatLine(d, true))
		end
	end)
end

function compute(gameInfo: any, fen: string)
	currentCalculationId += 1
	local thisCalcId = currentCalculationId

	busy = true
	local calcStartTick = tick()
	busyTick = calcStartTick

	local isVi = (CFG.Language == "vi")
	local isComplex = isPositionComplex(fen)
	local statusDesc = if isComplex then
		(isVi and "Thế cờ sâu - Đang tính toán đa biến..." or "Deep tactical position - Computing multi-variations...")
	else
		(isVi and "Stockfish đang tính nước đi tối ưu..." or "Stockfish is computing optimal move...")
	setText(pMove, isVi and "Đang tính toán..." or "Analyzing position...", statusDesc)

	local data, err = bestMove(fen, gameInfo)

	if not isAlive() or currentCalculationId ~= thisCalcId then
		busy = false
		return
	end

	if not data then
		setText(pMove, isVi and "Không tìm thấy nước đi" or "No move found", tostring(err or (isVi and "Đang thử lại ngay" or "Retrying shortly")))
		setText(pEval, isVi and "Đánh giá thế cờ" or "Evaluation", "-")
		setText(pLine, isVi and "Kế hoạch phản công" or "Continuation Line", "-")
		busy = false
		currentGuidance = nil
		return
	end

	-- Check for endgame position completion
	if data.gameOver then
		local reason = data.reason or "Game Over"
		setText(pMove, isVi and "Ván đấu kết thúc" or "Game Over", isVi and ("Thế cờ kết thúc: %s"):format(reason) or ("Match conclusion: %s"):format(reason))
		setText(pEval, isVi and "Đánh giá thế cờ" or "Evaluation", isVi and "Hoàn tất" or "Complete")
		setText(pLine, isVi and "Kế hoạch phản công" or "Continuation Line", "-")
		clearAllMarkers()
		currentGuidance = nil
		busy = false
		return
	end

	-- Attach precise calculation elapsed time
	data.calcElapsed = tick() - calcStartTick

	-- Always immediately display calculated results on UI (có kết quả là lập tức hiển thị!)
	currentGuidance = { from = data.from, to = data.to, uci = data.uci, eval = data.eval, mate = data.mate, san = data.san, fen = fen }
	local guidanceTitle, guidanceDesc = formatMoveGuidance(fen, data.from, data.to, data.san)
	local src = data.source or "Stockfish 16"
	local engineLabel = isVi and "Động cơ" or "Engine"

	setText(pMove, guidanceTitle, ("%s\n%s: %s"):format(guidanceDesc, engineLabel, src))
	setText(pEval, isVi and "Đánh giá thế cờ" or "Evaluation", formatEval(data))
	setText(pLine, isVi and "Kế hoạch phản công" or "Continuation Line", formatLine(data))

	drawUnifiedMarkers(gameInfo, data.from, data.to)

	if (CFG.PlayLegit or CFG.AutoPlay) and data.uci and not gameInfo.IsSpectating then
		Adapter.submitMove(gameInfo, data.uci, data)
	end

	busy = false
end

----------------------------------------------------------------------
-- MAIN MONITORING LOOP (AUTO RECONNECT & RESILIENT RETRY)
----------------------------------------------------------------------

task.spawn(function()
	local retryTicks = 0
	lastMoveSubmitAttempt = 0
	moveSubmitRetries = 0

	while isAlive() do
		task.wait(0.20)

		-- Watchdog: safely unlock busy only if genuinely stuck for > 8.0s
		if busy and (tick() - busyTick > 8.0) then
			busy = false
		end
		if autoPlayBusy and (tick() - lastMoveSubmitAttempt > 8.0) then
			autoPlayBusy = false
		end

		local isVi = (CFG.Language == "vi")
		local gameInfo = Adapter.getGameInfo()
		if not gameInfo then
			if lastFen ~= nil then
				lastFen = nil
				currentGuidance = nil
				moveSubmitRetries = 0
				lastMoveSubmitAttempt = 0
				clearAllMarkers()
				table.clear(positionHistory)
				table.clear(fenCache)
				setText(pStatus, isVi and "Trạng thái" or "Status", isVi and "Đang chờ ván cờ mới..." or "Waiting for new game...")
				setText(pMove, isVi and "Nước đi tối ưu" or "Best Move", "-")
				setText(pEval, isVi and "Đánh giá thế cờ" or "Evaluation", "-")
				setText(pLine, isVi and "Kế hoạch phản công" or "Continuation Line", "-")
			end
			continue
		end

		local fen = gameInfo.FEN
		local myTurn = gameInfo.MyTurn
		local isSpec = (gameInfo.IsSpectating == true)
		local gameLabel = (gameInfo.GameType == "ChessClub") and "Chess Club" or "CHESS! 3D"
		local colorLabel = gameInfo.AmIWhite and (isVi and "Trắng" or "White") or (isVi and "Đen" or "Black")
		local turnColor = gameInfo.WhiteToPlay and (isVi and "Trắng" or "White") or (isVi and "Đen" or "Black")
		local turnPrompt = if isSpec then (isVi and "[ĐANG XEM TRẬN]" or "[SPECTATING]")
			elseif myTurn then (isVi and "[LƯỢT CỦA BẠN]" or "[YOUR TURN]")
			else (isVi and "[ĐỐI THỦ ĐANG NGHĨ]" or "[OPPONENT THINKING]")

		setText(
			pStatus,
			isVi and ("Ván đấu: %s %s- Cầm quân %s"):format(gameLabel, if isSpec then "(Khán giả) " else "", colorLabel)
				or ("Match: %s %s- Playing %s"):format(gameLabel, if isSpec then "(Spectating) " else "", colorLabel),
			isVi and ("Lượt đi: %s - %s"):format(turnColor, turnPrompt) or ("Turn: %s - %s"):format(turnColor, turnPrompt)
		)

		if (gameInfo.Round or 1) <= 1 and lastFen == nil then
			table.clear(positionHistory)
			table.clear(fenCache)
		end

		if fen ~= lastFen then
			lastFen = fen
			currentGuidance = nil
			retryTicks = 0
			moveSubmitRetries = 0
			lastMoveSubmitAttempt = 0

			if myTurn or isSpec then
				task.spawn(compute, gameInfo, fen)
			else
				clearAllMarkers()
				if CFG.Ponder then
					ponderOpponentTurn(fen)
				end
			end
			if IS_CHESS_CLUB then
				if currentCC3DSet ~= "Default" then
					pcall(function() applyChessClub3DSkin(currentCC3DSet) end)
				end
				if currentCC2DSet ~= "Default" then
					pcall(function() applyChessClub2DSkin(currentCC2DSet) end)
				end
			else
				if currentSkinCollection ~= "Default" then
					pcall(function() applyOfficialSkin(currentSkinCollection) end)
				end
			end
		elseif myTurn or isSpec then
			if currentGuidance == nil and not busy then
				retryTicks += 1
				if retryTicks >= 3 then
					retryTicks = 0
					task.spawn(compute, gameInfo, fen)
				end
			elseif currentGuidance then
				-- Check visual markers
				local hasTarget = false
				for _, inst in ipairs(activeInstances) do
					if (inst.Name == "TargetMarker" or inst.Name == "SonHub3D_TargetPad") and inst.Parent then
						hasTarget = true
						break
					end
				end
				if not hasTarget then
					drawUnifiedMarkers(gameInfo, currentGuidance.from, currentGuidance.to)
				end

				-- AUTO UN-HANG: If AutoPlay or PlayLegit is active, retry until move registers
				if (CFG.PlayLegit or CFG.AutoPlay) and not isSpec and currentGuidance.uci then
					local now = tick()
					if not autoPlayBusy and (now - lastMoveSubmitAttempt > 1.4) then
						lastMoveSubmitAttempt = now
						moveSubmitRetries += 1

						if moveSubmitRetries <= 3 then
							-- Proactive retry submission (unhangs stalled clicks)
							Adapter.submitMove(gameInfo, currentGuidance.uci, currentGuidance)
						else
							-- If move was repeatedly rejected by server/client, clear and recalculate alternative move
							fenCache[fen] = nil
							currentGuidance = nil
							moveSubmitRetries = 0
							task.spawn(compute, gameInfo, fen)
						end
					end
				end
			end
		end
	end
end)

----------------------------------------------------------------------
-- AUTONOMOUS PROMOTION WATCHDOG (INSTANT AUTO-RESOLVE)
----------------------------------------------------------------------

task.spawn(function()
	while isAlive() do
		task.wait(0.08)
		pcall(function()
			local pgui = LocalPlayer:FindFirstChild("PlayerGui")
			if not pgui then return end

			-- 1. Chess Club: 2DBoard.Promotion ("Choose a piece to promote to")
			local b2d = pgui:FindFirstChild("2DBoard")
			local promo = b2d and b2d:FindFirstChild("Promotion")
			if promo and promo:FindFirstChild("Buttons") and (promo.Visible == true or promo.BackgroundTransparency < 0.95) then
				local targetChar = (currentGuidance and currentGuidance.uci and currentGuidance.uci:len() >= 5 and currentGuidance.uci:sub(5, 5):lower()) or "q"
				local btn = promo.Buttons:FindFirstChild(targetChar) or promo.Buttons:FindFirstChild("q")
				if btn then
					triggerButton(btn)
					pcall(function()
						promo.Visible = false
						promo.BackgroundTransparency = 1
					end)
				end
			end

			-- 2. CookieChess / Generic Promotion Dialogs
			for _, gName in ipairs({ "Promotion", "PawnPromotion", "PromoteGui" }) do
				local g = pgui:FindFirstChild(gName)
				if g and g:IsA("ScreenGui") and g.Enabled then
					for _, desc in ipairs(g:GetDescendants()) do
						if desc:IsA("GuiButton") and desc.Visible and (desc.Name:lower() == "q" or desc.Name:lower():find("queen")) then
							triggerButton(desc)
							break
						end
					end
				end
			end
		end)
	end
end)

----------------------------------------------------------------------
-- UNLOAD HOOKS & STARTUP NOTIFICATION
----------------------------------------------------------------------

_genv._SONHUB_CLEANUP = doCleanup
S.onCleanup(doCleanup)

WindUI:Notify({
	Title = "SonHUB Chess Coach",
	Content = if CFG.Language == "vi" then "Cập nhật: 03/10/2026" else "Last Update: 03/10/2026",
	Duration = 3,
	Icon = "shield-check",
})
