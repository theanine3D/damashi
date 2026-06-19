local BGMTracks     = {}
local BGMChannel    = nil
local BGMCurrentIdx = 0
local BGMShouldPlay = false
local BGMVolume     = 0.5
local MusicFrame    = nil

local function ScanTracks()
	BGMTracks = {}
	local seen = {}

	-- sound.PlayFile (BASS) resolves paths from the game root, not from sound/.
	-- Each dirPath must include "sound/" so BASS finds the file.
	local function addFromDir(dirPath)
		for _, ext in ipairs({ "mp3", "wav", "ogg" }) do
			local files = file.Find(dirPath .. "bgm_*." .. ext, "GAME")
			for _, f in ipairs(files) do
				local key = f:lower()
				if not seen[key] then
					seen[key] = true
					local stem = f:match("^bgm_(.+)%.[^.]+$") or f
					local display = stem:gsub("_", " ")
					display = display:sub(1, 1):upper() .. display:sub(2)
					table.insert(BGMTracks, {
						name      = display,
						soundPath = dirPath .. f,
					})
				end
			end
		end
	end

	addFromDir("gamemodes/damashi/sound/damashi/")
	addFromDir("sound/damashi/")
end

hook.Add("InitPostEntity", "damashi_bgm_scan", function()
	if IsValid(BGMChannel) then BGMChannel:Stop(); BGMChannel = nil end
	BGMCurrentIdx  = 0
	BGMShouldPlay  = false
	ScanTracks()
end)

local function PlayTrack(idx)
	if idx < 1 or idx > #BGMTracks then return end
	if IsValid(BGMChannel) then BGMChannel:Stop(); BGMChannel = nil end

	BGMCurrentIdx  = idx
	BGMShouldPlay  = true

	local track = BGMTracks[idx]
	sound.PlayFile(track.soundPath, "", function(chan, errId, errName)
		if not IsValid(chan) then
			chat.AddText(Color(200, 80, 80), "[Damashi Music] ",
				Color(220, 220, 230), "Could not open '",
				Color(255, 220, 60), track.name,
				Color(220, 220, 230), "' (path tried: ",
				Color(180, 180, 210), track.soundPath,
				Color(220, 220, 230), ") — place tracks in ",
				Color(255, 220, 60), "gamemodes/damashi/sound/damashi/",
				Color(220, 220, 230), " or ",
				Color(255, 220, 60), "garrysmod/sound/damashi/")
			BGMShouldPlay = false
			return
		end
		BGMChannel = chan
		chan:SetVolume(BGMVolume)
		chan:Play()
	end)
end

local function TogglePause()
	if not IsValid(BGMChannel) then return end
	local s = BGMChannel:GetState()
	if s == GMOD_CHANNEL_PLAYING then
		BGMChannel:Pause()
	elseif s == GMOD_CHANNEL_PAUSED then
		BGMChannel:Play()
	end
end

local function StopAll()
	BGMShouldPlay = false
	if IsValid(BGMChannel) then BGMChannel:Stop(); BGMChannel = nil end
	BGMCurrentIdx = 0
end

local function GetPlayState()
	if not IsValid(BGMChannel) then return "stopped" end
	local s = BGMChannel:GetState()
	if s == GMOD_CHANNEL_PLAYING then return "playing"
	elseif s == GMOD_CHANNEL_PAUSED then return "paused"
	else return "stopped" end
end

local lastAutoAdvance = 0
hook.Add("Think", "damashi_bgm_advance", function()
	if not BGMShouldPlay or BGMCurrentIdx == 0 or #BGMTracks == 0 then return end
	if CurTime() - lastAutoAdvance < 2 then return end
	if IsValid(BGMChannel) and BGMChannel:GetState() == GMOD_CHANNEL_STOPPED then
		lastAutoAdvance = CurTime()
		PlayTrack(BGMCurrentIdx % #BGMTracks + 1)
	end
end)

local COL_TRACK_BG  = Color(22, 22, 35, 200)
local COL_PLAYING   = Color(50, 140, 75, 220)
local COL_HOVER     = Color(38, 52, 78, 220)
local COL_BTN       = Color(28, 35, 58, 220)
local COL_BTN_HOV   = Color(55, 70, 120, 220)
local COL_TEXT      = Color(235, 235, 245, 255)
local COL_DIM       = Color(170, 175, 195, 255)
local COL_GREEN     = Color(130, 220, 155, 255)
local COL_CTRL_BG   = Color(12, 12, 22, 235)

local function BuildMusicWindow()
	if IsValid(MusicFrame) then
		MusicFrame:Remove()
		return
	end

	ScanTracks()

	if #BGMTracks == 0 then
		chat.AddText(Color(100, 200, 130), "[Damashi] ",
			Color(220, 220, 230), "No tracks found. Add ",
			Color(255, 220, 60), "bgm_*.mp3/wav/ogg",
			Color(220, 220, 230), " to ",
			Color(255, 220, 60), "gamemodes/damashi/sound/damashi/",
			Color(220, 220, 230), " (packaged) or ",
			Color(255, 220, 60), "garrysmod/sound/damashi/",
			Color(220, 220, 230), " (custom).")
		return
	end

	local fh = math.Clamp(#BGMTracks * 36 + 160, 280, ScrH() - 80)
	local frame = vgui.Create("DFrame")
	MusicFrame = frame
	frame:SetTitle("Music")
	frame:SetSize(400, fh)
	frame:Center()
	frame:MakePopup()
	frame:SetDraggable(true)
	frame:SetDeleteOnClose(true)
	frame.OnRemove = function() MusicFrame = nil end

	local scroll = vgui.Create("DScrollPanel", frame)
	scroll:Dock(FILL)
	scroll:DockMargin(6, 6, 6, 0)

	local trackBtns = {}

	for i, track in ipairs(BGMTracks) do
		local btn = vgui.Create("DButton", scroll)
		btn:Dock(TOP)
		btn:DockMargin(0, 0, 0, 2)
		btn:SetHeight(34)
		btn:SetText("")
		btn.idx   = i
		btn.track = track

		btn.Paint = function(self, w, h)
			local playing = (BGMCurrentIdx == self.idx)
			local col = playing and COL_PLAYING or
				(self:IsHovered() and COL_HOVER or COL_TRACK_BG)
			draw.RoundedBox(4, 0, 0, w, h, col)
			local prefix = playing and "▶  " or "♫  "
			draw.SimpleText(prefix .. self.track.name, "DamashiHUDSmall",
				10, h * 0.5, playing and COL_GREEN or COL_TEXT,
				TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end

		btn.DoClick = function(self)
			PlayTrack(self.idx)
		end

		table.insert(trackBtns, btn)
	end

	local ctrl = vgui.Create("DPanel", frame)
	ctrl:Dock(BOTTOM)
	ctrl:SetHeight(114)
	ctrl:DockMargin(6, 4, 6, 6)
	ctrl.Paint = function(self, w, h)
		draw.RoundedBox(6, 0, 0, w, h, COL_CTRL_BG)
	end

	local nowLbl = vgui.Create("DLabel", ctrl)
	nowLbl:Dock(TOP)
	nowLbl:SetHeight(26)
	nowLbl:DockMargin(10, 6, 10, 0)
	nowLbl:SetFont("DamashiHUDSmall")
	nowLbl:SetTextColor(COL_GREEN)
	nowLbl:SetText("No track selected")

	local volRow = vgui.Create("DPanel", ctrl)
	volRow:Dock(TOP)
	volRow:SetHeight(28)
	volRow:DockMargin(10, 4, 10, 0)
	volRow.Paint = function() end

	local volLbl = vgui.Create("DLabel", volRow)
	volLbl:Dock(LEFT)
	volLbl:SetWidth(56)
	volLbl:SetFont("DamashiHUDSmall")
	volLbl:SetTextColor(COL_DIM)
	volLbl:SetText("Volume:")

	local volSlider = vgui.Create("DSlider", volRow)
	volSlider:Dock(FILL)
	volSlider:SetSlideX(BGMVolume)
	volSlider.OnValueChanged = function(self, x, _)
		BGMVolume = math.Clamp(x, 0, 1)
		if IsValid(BGMChannel) then
			BGMChannel:SetVolume(BGMVolume)
		end
	end

	local btnRow = vgui.Create("DPanel", ctrl)
	btnRow:Dock(BOTTOM)
	btnRow:SetHeight(38)
	btnRow:DockMargin(10, 0, 10, 8)
	btnRow.Paint = function() end

	local function MakeBtn(label, w, onClick)
		local b = vgui.Create("DButton", btnRow)
		b:Dock(LEFT)
		b:SetWide(w)
		b:DockMargin(0, 0, 4, 0)
		b:SetText("")
		b._label = label
		b.DoClick = onClick
		b.Paint = function(self, bw, bh)
			draw.RoundedBox(4, 0, 0, bw, bh,
				self:IsHovered() and COL_BTN_HOV or COL_BTN)
			draw.SimpleText(self._label, "DamashiHUDSmall",
				bw * 0.5, bh * 0.5, COL_TEXT,
				TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		return b
	end

	MakeBtn("◀ Prev", 70, function()
		if #BGMTracks == 0 then return end
		local prev = BGMCurrentIdx > 1 and BGMCurrentIdx - 1 or #BGMTracks
		PlayTrack(prev)
	end)

	local btnPlay = MakeBtn("▶ Play", 82, function()
		local s = GetPlayState()
		if s == "playing" or s == "paused" then
			TogglePause()
		else
			PlayTrack(BGMCurrentIdx > 0 and BGMCurrentIdx or 1)
		end
	end)

	MakeBtn("■ Stop", 68, function()
		StopAll()
	end)

	MakeBtn("Next ▶", 70, function()
		if #BGMTracks == 0 then return end
		PlayTrack(BGMCurrentIdx % #BGMTracks + 1)
	end)

	-- Each track button's Paint reads BGMCurrentIdx directly each frame; no invalidation needed.
	frame.Think = function(self)
		if not IsValid(self) then return end

		local s = GetPlayState()

		if IsValid(nowLbl) then
			if BGMCurrentIdx > 0 and BGMCurrentIdx <= #BGMTracks then
				local icon = s == "playing" and "▶  " or (s == "paused" and "‖  " or "■  ")
				nowLbl:SetText(icon .. BGMTracks[BGMCurrentIdx].name)
			else
				nowLbl:SetText("No track selected")
			end
		end

		if IsValid(btnPlay) then
			btnPlay._label = s == "playing" and "‖ Pause" or
			                 (s == "paused" and "▶ Resume" or "▶ Play")
		end
	end
end

concommand.Add("damashi_open_music", function()
	BuildMusicWindow()
end, nil, "Open the Damashi music selector.")
