AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
AddCSLuaFile("ent_ball.lua")
AddCSLuaFile("cl_ball_selector.lua")
AddCSLuaFile("cl_music_selector.lua")
include("shared.lua")
include("ent_ball_sv.lua")

util.AddNetworkString("damashi_win")
util.AddNetworkString("damashi_ball_models")
util.AddNetworkString("damashi_select_ball")
util.AddNetworkString("damashi_emergency_respawn")
util.AddNetworkString("damashi_play_sound")

local function BroadcastSound(snd)
	net.Start("damashi_play_sound")
		net.WriteString(snd)
	net.Broadcast()
end

-- Registered inline: gamemode entities/ folders are not auto-loaded by GMod.
do
	local S = {}
	S.Type       = "point"
	S.Base       = "base_point"
	S.PrintName  = "Damashi Settings"
	S.Spawnable  = false
	function S:KeyValue(key, value)
		key = string.lower(key)
		if key == "roundtime" then
			self.RoundTime = tonumber(value)
		elseif key == "scatter" then
			self.ScatterCount = tonumber(value)
		elseif key == "propmode_hl2" then
			self.PropmodeHL2 = tonumber(value)
		elseif key == "propmode_map" then
			self.PropmodeMap = tonumber(value)
		elseif key == "propmode_server" then
			self.PropmodeServer = tonumber(value)
		elseif key == "spawnmult" then
			self.SpawnMult = tonumber(value)
		end
	end
	scripted_ents.Register(S, "damashi_settings")
end

local cv_scatter   = CreateConVar("damashi_scatter", "800", FCVAR_ARCHIVE + FCVAR_NOTIFY,
	"Number of extra junk props scattered around spawn points each round")
local cv_roundtime = CreateConVar("damashi_roundtime", tostring(DAMASHI.RoundTime), FCVAR_ARCHIVE + FCVAR_NOTIFY,
	"Round length in seconds; when it expires the player with the largest ball wins. A damashi_settings map entity overrides this.")
local cv_propmode_hl2    = CreateConVar("damashi_propmode_hl2", "1", FCVAR_ARCHIVE + FCVAR_NOTIFY,
	"1 = include the built-in HL2 prop list when scattering props, 0 = disable it. A damashi_settings map entity can override this per-map.")
local cv_propmode_map    = CreateConVar("damashi_propmode_map", "0", FCVAR_ARCHIVE + FCVAR_NOTIFY,
	"1 = include physics props already placed inside the map as scatter candidates, 0 = disable. A damashi_settings map entity can override this per-map.")
local cv_propmode_server = CreateConVar("damashi_propmode_server", "1", FCVAR_ARCHIVE + FCVAR_NOTIFY,
	"1 = include models from models/damashi/scatter/ as scatter candidates, 0 = disable. A damashi_settings map entity can override this per-map.")
local cv_spawnmult = CreateConVar("damashi_spawnmult", "1.0", FCVAR_ARCHIVE + FCVAR_NOTIFY,
	"Multiplies the number of scattered props spawned at round start. 2.0 = double, 0.5 = half. A damashi_settings map entity overrides this.")
local cv_wave_interval = CreateConVar("damashi_wave_interval", "60", FCVAR_ARCHIVE + FCVAR_NOTIFY,
	"Seconds between mid-round scatter waves. Set to 0 to disable waves.")
local cv_wave_size = CreateConVar("damashi_wave_size", "120", FCVAR_ARCHIVE + FCVAR_NOTIFY,
	"Number of props dropped per mid-round scatter wave.")
local cv_scatter_passes = CreateConVar("damashi_scatter_passes", "5", FCVAR_ARCHIVE + FCVAR_NOTIFY,
	"Number of flood-fill generations used when scattering props at round start. Each generation uses the previous generation's prop positions as seeds, spreading coverage progressively outward. More generations = wider coverage on large maps. 1 = single-pass scatter around spawn only.")

function GM:InitPostEntity()
	self:CollectBallModels()
	self:CollectMapProps()
	self:CollectServerProps()
	self:SetupRound()
end

function GM:CollectBallModels()
	self.BallModels = { DAMASHI.DefaultBallModel }

	local files = file.Find("models/damashi/ball_*.mdl", "GAME")
	for _, f in ipairs(files) do
		local path = "models/damashi/" .. f
		if path ~= DAMASHI.DefaultBallModel then
			table.insert(self.BallModels, path)
		end
	end
end

function GM:SendBallModelList(ply)
	net.Start("damashi_ball_models")
		net.WriteUInt(#self.BallModels, 8)
		for _, mdl in ipairs(self.BallModels) do
			net.WriteString(mdl)
		end
	if ply then
		net.Send(ply)
	else
		net.Broadcast()
	end
end

function GM:PlayerInitialSpawn(ply)
	timer.Simple(2, function()
		if IsValid(ply) then
			self:SendBallModelList(ply)
		end
	end)
end

net.Receive("damashi_select_ball", function(len, ply)
	local mdl = net.ReadString()
	local skin = net.ReadUInt(10)

	-- Only allow models from the server-approved list.
	local allowed = false
	for _, m in ipairs(GAMEMODE.BallModels or {}) do
		if m == mdl then allowed = true break end
	end
	if not allowed then return end

	ply.DamashiBallModel = mdl
	ply.DamashiBallSkin = skin
	ply:SetNWString("DamashiBallModel", mdl)
	ply:SetNWString("DamashiBallSkin", skin)

	local ball = ply.DamashiBall
	if IsValid(ball) then
		ball:ChangeModel(mdl, skin)
	end
end)

-- Only prop_physics* and prop_ragdoll are scanned — they are guaranteed to have .phy files.
function GM:CollectMapProps()
	local seen = {}
	self.MapPropModels = {}

	local classes = {
		"prop_physics",
		"prop_physics_multiplayer",
		"prop_physics_respawnable",
		"prop_ragdoll",
	}

	for _, class in ipairs(classes) do
		for _, ent in ipairs(ents.FindByClass(class)) do
			local mdl = ent:GetModel()
			if mdl and mdl ~= "" and not seen[mdl] then
				seen[mdl] = true
				table.insert(self.MapPropModels, mdl)
			end
		end
	end
end

function GM:CollectServerProps()
	self.ServerPropModels = {}

	local mdlFiles = file.Find("models/damashi/scatter/*.mdl", "GAME")
	for _, f in ipairs(mdlFiles) do
		table.insert(self.ServerPropModels, "models/damashi/scatter/" .. f)
	end

	if #self.ServerPropModels == 0 then return end

	print(string.format("[Damashi] %d server scatter model(s) found in models/damashi/scatter/",
		#self.ServerPropModels))

	-- Each .mdl needs its companion files queued separately.
	local MODEL_EXTS = { "mdl", "phy", "vvd", "dx90.vtx", "dx80.vtx", "sw.vtx" }
	for _, mdl in ipairs(self.ServerPropModels) do
		local base = mdl:sub(1, -5)
		for _, ext in ipairs(MODEL_EXTS) do
			local path = base .. "." .. ext
			if file.Exists(path, "GAME") then
				resource.AddFile(path)
			end
		end
	end

	local function queueDir(dir)
		local files, subdirs = file.Find(dir .. "*", "GAME")
		for _, f in ipairs(files or {}) do
			resource.AddFile(dir .. f)
		end
		for _, d in ipairs(subdirs or {}) do
			queueDir(dir .. d .. "/")
		end
	end
	queueDir("materials/models/damashi/scatter/")
end

local SCATTER_MODELS = include("scatter_models.lua")

local SPAWN_CLASSES = {
	"info_player_start", "info_player_deathmatch",
	"info_player_combine", "info_player_rebel",
	"info_teleport_destination",
}

function GM:GetScatterModels(useHL2, useMap, useServer, minTier)
	minTier = minTier or 1
	local list   = {}
	local inList = {}

	if useHL2 then
		for _, entry in ipairs(SCATTER_MODELS) do
			local mdl, tier = entry[1], entry[2]
			inList[mdl] = true  -- always mark to prevent map/server duplication
			if tier >= minTier then
				table.insert(list, mdl)
			end
		end
	end

	local function appendUnique(src)
		for _, mdl in ipairs(src) do
			if not inList[mdl] then
				inList[mdl] = true
				table.insert(list, mdl)
			end
		end
	end

	if useMap    then appendUnique(self.MapPropModels    or {}) end
	if useServer then appendUnique(self.ServerPropModels or {}) end

	if #list == 0 then
		local fallback = {}
		for _, entry in ipairs(SCATTER_MODELS) do
			table.insert(fallback, entry[1])
		end
		return fallback
	end
	return list
end

-- func_movelinear excluded: also used for elevators and custom sliding brushes.
local DOOR_CLASSES = {
	"func_door",
	"func_door_rotating",
	"prop_door_rotating",
}

function GM:RemoveDoors()
	local removed = 0
	for _, class in ipairs(DOOR_CLASSES) do
		for _, ent in ipairs(ents.FindByClass(class)) do
			ent:Remove()
			removed = removed + 1
		end
	end
	if removed > 0 then
		print(string.format("[Damashi] Removed %d door(s) to clear ball paths.", removed))
	end
end

function GM:SetupRound()
	self.RoundOver = false
	self:RemoveDoors()

	-- Most maps only set spawnflag 1 (Players), which skips VPhysics entities.
	-- Flags 1+2+4+8=15 add NPCs, Pushables, and Physics Objects.
	-- Must re-run every SetupRound: game.CleanUpMap() restores original flags.
	for _, trig in ipairs(ents.FindByClass("trigger_teleport")) do
		if IsValid(trig) then
			trig:SetKeyValue("spawnflags", "15")
		end
	end

	local roundTime    = math.max(cv_roundtime:GetFloat(), 10)
	local scatterCount = cv_scatter:GetInt()
	local useHL2       = cv_propmode_hl2:GetInt()    ~= 0
	local useMap       = cv_propmode_map:GetInt()    ~= 0
	local useServer    = cv_propmode_server:GetInt() ~= 0
	local spawnMult    = math.max(cv_spawnmult:GetFloat(), 0)

	local settings = ents.FindByClass("damashi_settings")[1]
	if IsValid(settings) then
		if (settings.RoundTime    or 0)  > 0  then roundTime    = settings.RoundTime end
		if (settings.ScatterCount or -1) >= 0  then scatterCount = settings.ScatterCount end
		if settings.PropmodeHL2    ~= nil then useHL2    = settings.PropmodeHL2    ~= 0 end
		if settings.PropmodeMap    ~= nil then useMap    = settings.PropmodeMap    ~= 0 end
		if settings.PropmodeServer ~= nil then useServer = settings.PropmodeServer ~= 0 end
		if (settings.SpawnMult    or -1) >= 0  then spawnMult   = math.max(settings.SpawnMult, 0) end
	end

	self.RoundEndTime = CurTime() + roundTime
	SetGlobalFloat("DamashiRoundEnd", self.RoundEndTime)

	if navmesh.IsLoaded() then
		self:NavmeshScatter(math.Round(scatterCount * spawnMult), useHL2, useMap, useServer)
	else
		self:FloodFillScatter(math.Round(scatterCount * spawnMult), useHL2, useMap, useServer)
	end

	local waveInterval = cv_wave_interval:GetFloat()
	if waveInterval > 0 then
		timer.Create("DamashiScatterWave", waveInterval, 0, function()
			if GAMEMODE.RoundOver then return end
			local n = cv_wave_size:GetInt()
			if n > 0 then
				GAMEMODE:ScatterProps(n, useHL2, useMap, useServer, GAMEMODE.WaveAnchors)
				PrintMessage(HUD_PRINTTALK, "More props have appeared around the map!")
			end
		end)
	else
		timer.Remove("DamashiScatterWave")
	end

	BroadcastSound("buttons/bell1.wav")
end

function GM:RestartRound()
	-- Must nil before CleanUpMap: game.CleanUpMap() defers removal to end-of-frame,
	-- so old balls remain IsValid() during SetupRound and bleed their sizes into
	-- BallRadiusToMinTier, causing only tier-5 props to spawn on every subsequent round.
	for _, ply in ipairs(player.GetAll()) do
		ply.DamashiBall = nil
	end

	game.CleanUpMap()
	self:SetupRound()

	for _, ply in ipairs(player.GetAll()) do
		ply:Spawn()
	end
end

function GM:Think()
	if not self.RoundOver and self.RoundEndTime and CurTime() >= self.RoundEndTime then
		self:EndRoundByTimer()
	end
end

function GM:EndRoundByTimer()
	self.RoundOver = true
	timer.Remove("DamashiScatterWave")

	local winner, bestRadius = nil, -1
	for _, ply in ipairs(player.GetAll()) do
		local ball = ply.DamashiBall
		if IsValid(ball) and ball:GetBallRadius() > bestRadius then
			winner, bestRadius = ply, ball:GetBallRadius()
		end
	end

	local name = "Nobody"
	if IsValid(winner) then
		name = winner:Nick()
		winner:SetNWInt("DamashiWins", winner:GetNWInt("DamashiWins", 0) + 1)
		winner:AddFrags(10)
		PrintMessage(HUD_PRINTTALK, string.format("Time's up! %s wins the round with a %.2f m ball!",
			name, bestRadius * 2 * DAMASHI.UnitsToMeters))
	else
		PrintMessage(HUD_PRINTTALK, "Time's up! Nobody wins this round.")
	end

	BroadcastSound("npc/turret_floor/retire.wav")

	net.Start("damashi_win")
		net.WriteString(name)
		net.WriteFloat(math.max(bestRadius, 0) * 2 * DAMASHI.UnitsToMeters)
		net.WriteFloat(DAMASHI.RoundRestartDelay)
	net.Broadcast()

	timer.Simple(DAMASHI.RoundRestartDelay, function()
		self:RestartRound()
	end)
end

function GM:KeyPress(ply, key)
	if key ~= IN_ATTACK then return end
	if not ply:Alive() then return end

	local ball = ply.DamashiBall
	if IsValid(ball) then
		ball:TryCharge()
	end
end

function GM:PlayerSpawn(ply)
	self.BaseClass.PlayerSpawn(self, ply)

	if not ply.DamashiSpawnOrigin then
		ply.DamashiSpawnOrigin = ply:GetPos()
	end

	ply:StripWeapons()
	ply:StripAmmo()
	ply:SetCanWalk(false)

	self:AttachBall(ply)
end

function GM:PlayerLoadout(ply)
	return true -- no weapons in this gamemode
end

function GM:AttachBall(ply)
	if IsValid(ply.DamashiBall) then
		ply.DamashiBall:Remove()
	end

	-- On first spawn, randomly pick a custom model; fall back to default only if none exist.
	if not ply.DamashiBallModel then
		local customs = {}
		for _, m in ipairs(self.BallModels or {}) do
			if m ~= DAMASHI.DefaultBallModel then
				for s = 0, util.GetModelInfo(m).SkinCount - 1 do 
					table.insert(customs, {m, s})
				end
			end
		end
		if #customs > 0 then
			ply.DamashiBallModel = customs[math.random(#customs)][1]
			ply.DamashiBallSkin = customs[math.random(#customs)][2]
		else
			ply.DamashiBallModel = DAMASHI.DefaultBallModel
			ply.DamashiBallSkin = 0
		end
		ply:SetNWString("DamashiBallModel", ply.DamashiBallModel)
		ply:SetNWString("DamashiBallSkin", ply.DamashiBallSkin)
	end

	local ball = ents.Create("damashi_ball")
	if not IsValid(ball) then return end

	ball.PreferredModel = ply.DamashiBallModel
	ball.PreferredSkin = ply.DamashiBallSkin

	ball:SetPos(ply:GetPos() + Vector(0, 0, DAMASHI.BaseRadius + 4))
	ball:Spawn()
	ball:Activate()
	ball:SetRollingPlayer(ply)

	ply.DamashiBall = ball
	ply:SetNWEntity("DamashiBall", ball)

	ply:SetNoDraw(true)
	ply:DrawShadow(false)
	ply:SetNoTarget(true)
	ply:SetSolid(SOLID_NONE)
	ply:SetMoveType(MOVETYPE_NONE)
	ply:SetPos(ball:GetPos() + Vector(0, 0, DAMASHI.BaseRadius + 8))
end

function GM:PlayerDeathThink(ply)
	if self.RoundOver then return false end

	if not ply.NextDamashiSpawn then
		ply.NextDamashiSpawn = CurTime() + DAMASHI.RespawnDelay
	end
	if CurTime() < ply.NextDamashiSpawn then return false end

	ply.NextDamashiSpawn = nil
	ply:Spawn()
end

function GM:PostPlayerDeath(ply)
	if IsValid(ply.DamashiBall) then
		ply.DamashiBall:Remove()
		ply.DamashiBall = nil
	end
end

function GM:PlayerDisconnected(ply)
	if IsValid(ply.DamashiBall) then
		ply.DamashiBall:Remove()
	end
end

function GM:PlayerShouldTakeDamage(ply, attacker)
	return false
end

function GM:GetAverageBallRadius()
	local total, count = 0, 0
	for _, ply in ipairs(player.GetAll()) do
		local ball = ply.DamashiBall
		if IsValid(ball) then
			total = total + ball:GetBallRadius()
			count = count + 1
		end
	end
	if count == 0 then return DAMASHI.BaseRadius end
	return total / count
end

function GM:BallRadiusToMinTier(radius)
	if radius >= 200 then return 5 end
	if radius >= 150 then return 4 end
	if radius >=  80 then return 3 end
	if radius >=  40 then return 2 end
	return 1
end

function GM:BuildNavAreaCache()
	if self.NavAreaCache ~= nil then return end
	local areas = navmesh.GetAllNavAreas()
	if not areas or #areas == 0 then self.NavAreaCache = false; return end

	local total = 0
	for _, area in ipairs(areas) do
		total = total + math.max(area:GetSizeX() * area:GetSizeY(), 1)
	end
	local cdf, cum = {}, 0
	for i, area in ipairs(areas) do
		cum      = cum + math.max(area:GetSizeX() * area:GetSizeY(), 1) / total
		cdf[i]   = cum
	end
	self.NavAreaCache = { areas = areas, cdf = cdf }
end

function GM:PickNavArea()
	local c = self.NavAreaCache
	if not c or c == false then return nil end
	local r, lo, hi = math.random(), 1, #c.cdf
	while lo < hi do
		local mid = math.floor((lo + hi) / 2)
		if c.cdf[mid] < r then lo = mid + 1 else hi = mid end
	end
	return c.areas[lo]
end

function GM:NavmeshScatter(count, useHL2, useMap, useServer)
	if count <= 0 then return end

	local minTier    = self:BallRadiusToMinTier(self:GetAverageBallRadius())
	local models     = self:GetScatterModels(useHL2, useMap, useServer, minTier)
	local modelCount = #models
	if modelCount == 0 then return end

	self:BuildNavAreaCache()
	if not self.NavAreaCache then
		self:FloodFillScatter(count, useHL2, useMap, useServer)
		return
	end

	local waveAnchors        = {}
	local spawned, attempts  = 0, 0
	while spawned < count and attempts < count * 4 do
		attempts = attempts + 1
		local area = self:PickNavArea()
		if area then
			local pos = area:GetRandomPoint() + Vector(0, 0, 16)
			if util.IsInWorld(pos) then
				local prop = ents.Create("prop_physics")
				if IsValid(prop) then
					prop:SetModel(models[math.random(modelCount)])
					prop:SetPos(pos)
					prop:SetAngles(Angle(0, math.Rand(0, 360), 0))
					prop:Spawn()
					prop:Activate()
					prop.DamashiScattered = true
					table.insert(waveAnchors, prop:GetPos())
					spawned = spawned + 1
				end
			end
		end
	end

	self.WaveAnchors = waveAnchors
end

function GM:FloodFillScatter(count, useHL2, useMap, useServer)
	if count <= 0 then return end

	local minTier    = self:BallRadiusToMinTier(self:GetAverageBallRadius())
	local models     = self:GetScatterModels(useHL2, useMap, useServer, minTier)
	local modelCount = #models
	if modelCount == 0 then return end

	local maxGens   = math.max(cv_scatter_passes:GetInt(), 1)
	local genRadius = math.max(math.floor(3500 / math.sqrt(maxGens)), 300)
	local genTarget = math.ceil(count / maxGens)

	local seeds = {}
	for _, class in ipairs(SPAWN_CLASSES) do
		for _, ent in ipairs(ents.FindByClass(class)) do
			table.insert(seeds, ent:GetPos())
		end
	end
	if #seeds == 0 then return end

	local spawnCentroid = Vector(0, 0, 0)
	for _, pos in ipairs(seeds) do
		spawnCentroid = spawnCentroid + pos
	end
	spawnCentroid = spawnCentroid * (1 / #seeds)

	local waveAnchors = {}
	for _, pos in ipairs(seeds) do
		table.insert(waveAnchors, pos)
	end

	local totalSpawned = 0

	for _ = 1, maxGens do
		if totalSpawned >= count or #seeds == 0 then break end

		local batchTarget = math.min(genTarget, count - totalSpawned)
		local newSeeds    = {}
		local attempts    = 0
		local batchDone   = 0

		while batchDone < batchTarget and attempts < batchTarget * 6 do
			attempts = attempts + 1

			local origin = seeds[math.random(#seeds)]
			local ang    = math.Rand(0, math.pi * 2)
			local dist   = math.Rand(150, genRadius)
			local start  = origin + Vector(math.cos(ang) * dist, math.sin(ang) * dist, 128)

			if util.IsInWorld(start) then
				local tr = util.TraceLine({
					start  = start,
					endpos = start - Vector(0, 0, 4096),
					mask   = MASK_SOLID_BRUSHONLY,
				})
				if tr.HitWorld and not tr.StartSolid and tr.HitNormal.z > 0.7 then
					local prop = ents.Create("prop_physics")
					if IsValid(prop) then
						prop:SetModel(models[math.random(modelCount)])
						prop:SetPos(tr.HitPos + Vector(0, 0, 16))
						prop:SetAngles(Angle(0, math.Rand(0, 360), 0))
						prop:Spawn()
						prop:Activate()
						prop.DamashiScattered = true
						local pos = prop:GetPos()
						table.insert(newSeeds, pos)
						table.insert(waveAnchors, pos)
						batchDone = batchDone + 1
					end
				end
			end
		end

		totalSpawned = totalSpawned + batchDone

		-- Keep the farthest prop per 45° sector so each generation expands outward
		-- rather than diffusing back toward spawn like a random walk.
		local sectorBest = {}
		for _, pos in ipairs(newSeeds) do
			local dx  = pos.x - spawnCentroid.x
			local dy  = pos.y - spawnCentroid.y
			local sec = (math.floor((math.atan2(dy, dx) + math.pi) / (math.pi * 2) * 8) % 8) + 1
			local dSq = pos:DistToSqr(spawnCentroid)
			if not sectorBest[sec] or dSq > sectorBest[sec][2] then
				sectorBest[sec] = { pos, dSq }
			end
		end
		seeds = {}
		for _, best in pairs(sectorBest) do
			table.insert(seeds, best[1])
		end
	end

	self.WaveAnchors = waveAnchors
end

function GM:ScatterProps(count, useHL2, useMap, useServer, anchors)
	if count <= 0 then return end

	local minTier = self:BallRadiusToMinTier(self:GetAverageBallRadius())
	local models = self:GetScatterModels(
		useHL2    ~= false,   -- default true if not explicitly passed
		useMap    == true,
		useServer ~= false,
		minTier)
	local modelCount = #models
	if modelCount == 0 then return end

	local spawns
	if anchors and #anchors > 0 then
		spawns = anchors
	else
		spawns = {}
		for _, class in ipairs(SPAWN_CLASSES) do
			for _, ent in ipairs(ents.FindByClass(class)) do
				table.insert(spawns, ent:GetPos())
			end
		end
		if #spawns == 0 then return end
	end

	local spawned = 0
	local attempts = 0
	while spawned < count and attempts < count * 6 do
		attempts = attempts + 1

		local origin = spawns[math.random(#spawns)]
		local ang = math.Rand(0, math.pi * 2)
		local dist = math.Rand(150, 3500)
		local start = origin + Vector(math.cos(ang) * dist, math.sin(ang) * dist, 128)

		if util.IsInWorld(start) then
			local tr = util.TraceLine({
				start = start,
				endpos = start - Vector(0, 0, 4096),
				mask = MASK_SOLID_BRUSHONLY,
			})

			if tr.HitWorld and not tr.StartSolid and tr.HitNormal.z > 0.7 then
				local prop = ents.Create("prop_physics")
				if IsValid(prop) then
					prop:SetModel(models[math.random(modelCount)])
					prop:SetPos(tr.HitPos + Vector(0, 0, 16))
					prop:SetAngles(Angle(0, math.Rand(0, 360), 0))
					prop:Spawn()
					prop:Activate()
					prop.DamashiScattered = true
					spawned = spawned + 1
				end
			end
		end
	end
end

net.Receive("damashi_emergency_respawn", function(_, ply)
	if not IsValid(ply) or not ply:Alive() then return end

	local ball = ply.DamashiBall
	if not IsValid(ball) or ball:GetClass() ~= "damashi_ball" then return end

	if (ply.NextEmergRespawn or 0) > CurTime() then return end
	ply.NextEmergRespawn = CurTime() + 20

	local origin = ply.DamashiSpawnOrigin
	if not origin then
		for _, class in ipairs(SPAWN_CLASSES) do
			local ent = ents.FindByClass(class)[1]
			if IsValid(ent) then origin = ent:GetPos(); break end
		end
	end
	if not origin then return end

	local r  = ball:GetBallRadius()
	local tr = util.TraceLine({
		start  = origin + Vector(0, 0, r + 64),
		endpos = origin - Vector(0, 0, 4096),
		mask   = MASK_SOLID_BRUSHONLY,
	})
	local safeZ = tr.Hit and (tr.HitPos.z + r + 8) or (origin.z + r + 8)

	ball:SetPos(Vector(origin.x, origin.y, safeZ))
	local phys = ball:GetPhysicsObject()
	if IsValid(phys) then
		phys:SetVelocity(Vector(0, 0, 0))
		phys:Wake()
	end
end)
