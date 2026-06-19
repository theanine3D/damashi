include("shared.lua")
include("cl_ball_selector.lua")
include("cl_music_selector.lua")

surface.CreateFont("DamashiHUD", {
	font = "Trebuchet MS",
	size = 28,
	weight = 700,
	antialias = true,
})

surface.CreateFont("DamashiHUDSmall", {
	font = "Trebuchet MS",
	size = 18,
	weight = 500,
	antialias = true,
})

surface.CreateFont("DamashiTimer", {
	font = "Trebuchet MS",
	size = 40,
	weight = 900,
	antialias = true,
})

surface.CreateFont("DamashiWin", {
	font = "Trebuchet MS",
	size = 64,
	weight = 900,
	antialias = true,
})

local winText, winSize, winUntil

local EmergRespawnStart = nil
local EmergRespawnFired = false

net.Receive("damashi_win", function()
	winText = net.ReadString()
	winSize = net.ReadFloat()
	winUntil = CurTime() + net.ReadFloat()
end)

net.Receive("damashi_play_sound", function()
	surface.PlaySound(net.ReadString())
end)

function GM:CalcView(ply, origin, angles, fov)
	local ball = ply:GetNWEntity("DamashiBall")
	if not IsValid(ball) or ball:GetClass() ~= "damashi_ball" or not ball.GetBallRadius or not ply:Alive() then return end

	local r = ball:GetBallRadius()
	local center = ball:WorldSpaceCenter()
	local dist = r * 3.5 + 90

	local wishPos = center - angles:Forward() * dist + Vector(0, 0, r * 0.6 + 25)

	-- Brushes only so loose rolling props don't jitter the camera.
	local tr = util.TraceHull({
		start = center,
		endpos = wishPos,
		mins = Vector(-8, -8, -8),
		maxs = Vector(8, 8, 8),
		mask = MASK_SOLID_BRUSHONLY,
	})

	return {
		origin = tr.HitPos,
		angles = angles,
		fov = fov,
		drawviewer = true,
	}
end

local HIDE_HUD = {
	CHudHealth = true,
	CHudBattery = true,
	CHudAmmo = true,
	CHudSecondaryAmmo = true,
	CHudCrosshair = true,
	CHudDamageIndicator = true,
}

function GM:HUDShouldDraw(name)
	if HIDE_HUD[name] then return false end
	return true
end

local COL_BG     = Color(20, 20, 30, 200)
local COL_BAR    = Color(90, 200, 120, 255)
local COL_BARHOT = Color(230, 80, 60, 255)
local COL_READY  = Color(120, 190, 255, 255)
local COL_TEXT   = Color(240, 240, 245, 255)
local COL_DIM    = Color(200, 200, 210, 180)

local COL_TAG_BG   = Color(0, 0, 0, 150)
local COL_TAG_TEXT = Color(255, 255, 255, 230)

-- GetChildren() reflects server-side SetParent calls, so this tracks the live prop
-- stack without any client-side bookkeeping.
local function getBallTopHeight(ball, r)
	local maxH = r
	for _, child in ipairs(ball:GetChildren()) do
		if IsValid(child) then
			local childTop = child:WorldSpaceCenter().z - ball:GetPos().z + child:BoundingRadius()
			if childTop > maxH then maxH = childTop end
		end
	end
	return maxH
end

local function drawNametags()
	local localPly = LocalPlayer()
	surface.SetFont("DamashiHUDSmall")

	for _, ply in ipairs(player.GetAll()) do
		if ply == localPly then continue end

		local ball = ply:GetNWEntity("DamashiBall")
		if not IsValid(ball) or ball:GetClass() ~= "damashi_ball" or not ball.GetBallRadius then continue end

		local r     = ball:GetBallRadius()
		local top   = ball:GetPos() + Vector(0, 0, getBallTopHeight(ball, r) + 24)
		local s     = top:ToScreen()
		if not s.visible then continue end

		local name   = ply:Nick()
		local tw, th = surface.GetTextSize(name)
		local pad    = 5
		local bw, bh = tw + pad * 2, th + pad * 2

		draw.RoundedBox(4, s.x - bw * 0.5, s.y - bh, bw, bh, COL_TAG_BG)
		draw.SimpleText(name, "DamashiHUDSmall",
			s.x, s.y - bh * 0.5, COL_TAG_TEXT,
			TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

local function findLeader()
	local leader, bestR
	for _, p in ipairs(player.GetAll()) do
		local b = p:GetNWEntity("DamashiBall")
		if IsValid(b) and b.GetBallRadius and (not bestR or b:GetBallRadius() > bestR) then
			leader, bestR = p, b:GetBallRadius()
		end
	end
	return leader, bestR
end

function GM:HUDPaint()
	drawNametags()

	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local sw, sh = ScrW(), ScrH()

	local remaining = math.max(0, GetGlobalFloat("DamashiRoundEnd", 0) - CurTime())
	local mins = math.floor(remaining / 60)
	local secs = math.floor(remaining % 60)
	draw.RoundedBox(6, sw / 2 - 70, 14, 140, 48, COL_BG)
	draw.SimpleText(string.format("%d:%02d", mins, secs), "DamashiTimer", sw / 2, 38,
		remaining < 30 and COL_BARHOT or COL_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	if winText and winUntil and CurTime() < winUntil then
		draw.SimpleText(winText .. " WINS!", "DamashiWin", sw / 2, sh * 0.3,
			COL_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		if winSize and winSize > 0 then
			draw.SimpleText(string.format("Largest ball: %.2f m", winSize), "DamashiHUD",
				sw / 2, sh * 0.3 + 50, COL_DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		draw.SimpleText(string.format("Next round in %d...", math.max(0, math.ceil(winUntil - CurTime()))),
			"DamashiHUDSmall", sw / 2, sh * 0.3 + 82, COL_DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	draw.SimpleText("Wins: " .. ply:GetNWInt("DamashiWins", 0), "DamashiHUD",
		sw - 30, 30, COL_TEXT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)

	local leader, leaderR = findLeader()
	if IsValid(leader) then
		draw.SimpleText(string.format("Leader: %s — %.2f m", leader:Nick(),
			leaderR * 2 * DAMASHI.UnitsToMeters), "DamashiHUDSmall",
			sw - 30, 64, leader == ply and COL_BAR or COL_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
	end

	if EmergRespawnStart then
		local elapsed = CurTime() - EmergRespawnStart
		if elapsed >= 3 then
			local secsLeft = math.max(1, math.ceil(10 - elapsed))
			local line1 = string.format("EMERGENCY RESPAWN in %ds", secsLeft)
			surface.SetFont("DamashiHUD")
			local tw = surface.GetTextSize(line1)
			local pad = 14
			local bw, bh = tw + pad * 2, 66
			local bx = sw * 0.5 - bw * 0.5
			local by = sh * 0.6 - bh * 0.5
			draw.RoundedBox(8, bx, by, bw, bh, Color(110, 20, 5, 220))
			draw.SimpleText(line1, "DamashiHUD",
				sw * 0.5, by + 16, Color(255, 200, 160, 255),
				TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			draw.SimpleText("Release R to cancel", "DamashiHUDSmall",
				sw * 0.5, by + bh - 14, Color(200, 175, 155, 200),
				TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		end
	end

	local ball = ply:GetNWEntity("DamashiBall")
	if not IsValid(ball) or ball:GetClass() ~= "damashi_ball" or not ball.GetBallRadius then return end

	local meters = ball:GetBallRadius() * 2 * DAMASHI.UnitsToMeters

	local bw, bh = math.min(520, sw * 0.45), 16
	local bx, by = (sw - bw) / 2, sh - 64

	draw.RoundedBox(6, bx - 8, by - 40, bw + 16, bh + 50, COL_BG)
	draw.SimpleText(string.format("Ball size: %.2f m", meters), "DamashiHUD",
		sw / 2, by - 20, COL_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	local readyAt = ball:GetChargeReadyTime() or 0
	local frac = 1 - math.Clamp((readyAt - CurTime()) / DAMASHI.ChargeCooldown, 0, 1)

	surface.SetDrawColor(0, 0, 0, 220)
	surface.DrawRect(bx, by, bw, bh)
	surface.SetDrawColor(frac >= 1 and COL_READY or COL_BAR)
	surface.DrawRect(bx + 2, by + 2, (bw - 4) * frac, bh - 4)

	if frac >= 1 then
		draw.SimpleText("CHARGE READY", "DamashiHUDSmall", sw / 2, by + bh / 2,
			Color(10, 20, 40, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	if self.LastHintBall ~= ball then
		self.LastHintBall = ball
		self.HintUntil = CurTime() + 20
	end
	if (self.HintUntil or 0) > CurTime() then
		draw.SimpleText("WASD to roll  •  SPACE to hop  •  LMB to charge attack  •  Mouse to steer",
			"DamashiHUDSmall", sw / 2, sh - 18, COL_DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

hook.Add("OnSpawnMenuOpen", "damashi_block_spawnmenu", function() return false end)

-- Think-based edge detection because GMod's security layer blocks concommand-based key binds.
do
	local prevN, prevM = false, false
	hook.Add("Think", "damashi_hotkeys", function()
		local focused = vgui.GetKeyboardFocus()

		if not focused then
			local n = input.IsKeyDown(KEY_N)
			if n and not prevN then RunConsoleCommand("damashi_open_selector") end
			prevN = n

			local m = input.IsKeyDown(KEY_M)
			if m and not prevM then RunConsoleCommand("damashi_open_music") end
			prevM = m

			if input.IsKeyDown(KEY_R) then
				if not EmergRespawnStart then
					EmergRespawnStart = CurTime()
					EmergRespawnFired = false
				elseif not EmergRespawnFired and CurTime() - EmergRespawnStart >= 10 then
					EmergRespawnFired = true
					net.Start("damashi_emergency_respawn")
					net.SendToServer()
					EmergRespawnStart = nil
					chat.AddText(Color(100, 200, 130), "[Damashi] ",
						Color(220, 220, 230), "Emergency respawn!")
				end
			else
				EmergRespawnStart = nil
				EmergRespawnFired = false
			end
		else
			-- VGUI has focus: cancel hold so typing "r" in chat never triggers respawn.
			EmergRespawnStart = nil
			EmergRespawnFired = false
		end
	end)
end

-- shared.lua registered the class; Draw only exists on the client.
local BALL = scripted_ents.GetStored("damashi_ball").t
function BALL:Draw()
	self:DrawModel()
end
