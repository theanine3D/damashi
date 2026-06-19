local BALL = {}
BALL.Type        = "anim"
BALL.Base        = "base_anim"
BALL.PrintName   = "Damashi Ball"
BALL.Spawnable   = false
BALL.AdminOnly   = false

function BALL:SetupDataTables()
	self:NetworkVar("Float",  0, "BallRadius")
	self:NetworkVar("Float",  1, "ChargeReadyTime")
	self:NetworkVar("Entity", 0, "RollingPlayer")
end

scripted_ents.Register(BALL, "damashi_ball")
