GM.Name     = "Damashi"
GM.Author   = "Theanine3D"
GM.Email    = ""
GM.Website  = "https://www.youtube.com/@Theanine3D"

DeriveGamemode("base")

DAMASHI = DAMASHI or {}

DAMASHI.BaseRadius          = 24      -- source units
DAMASHI.AbsorbRatio         = 0.40
DAMASHI.GrowthFactor        = 0.65
DAMASHI.MaxVisualProps      = 90      -- volume is retained when old visual props are culled
DAMASHI.PhysRebuildGrowth   = 1.03

DAMASHI.Accel               = 750
DAMASHI.SpeedCapBase        = 420
DAMASHI.SpeedCapPerRadius   = 1.5
DAMASHI.ChargeBrake         = 2.0
DAMASHI.JumpPower           = 280
DAMASHI.JumpCooldown        = 0.9

DAMASHI.ChargeImpulse       = 1400
DAMASHI.ChargeDuration      = 0.45
DAMASHI.ChargeCooldown      = 4.0
DAMASHI.ChargeDamageFactor  = 0.06
DAMASHI.ChargeSizeScaling   = 0.5    -- sqrt catch-up: 4× base radius → 2× damage, 9× → 3×
DAMASHI.ChargeKnockback     = 500
DAMASHI.WallHitPenalty      = 0.05
DAMASHI.WallHitMinSpeed     = 350
DAMASHI.HurtImmunity        = 1.0
DAMASHI.DropNoStickTime     = 1.5

DAMASHI.RoundTime           = 300
DAMASHI.RoundRestartDelay   = 10
DAMASHI.RespawnDelay        = 3

DAMASHI.UnitsToMeters       = 0.01905  -- 1 source unit ≈ 1.905 cm; HUD readout only

DAMASHI.DefaultBallModel    = "models/hunter/misc/sphere075x075.mdl"
DAMASHI.DefaultBallSkin		= 0

-- GMod does not auto-load entities/ from a gamemode folder; explicit include is required.
include("ent_ball.lua")

function GM:CanPlayerSuicide(ply)
	return false
end

function GM:PlayerNoClip(ply, desired)
	return false
end

function GM:PlayerCanHearPlayersVoice(listener, talker)
	return true
end
