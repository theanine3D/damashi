local BALL = scripted_ents.GetStored("damashi_ball").t

local ABSORBABLE = {
	prop_physics              = true,
	prop_physics_multiplayer  = true,
	prop_physics_respawnable  = true,
	prop_ragdoll              = true,
	func_physbox              = true,
	item_item_crate           = true,
}

local function sphereVolume(r)
	return (4 / 3) * math.pi * r ^ 3
end

function BALL:Initialize()
	local mdl = self.PreferredModel or DAMASHI.DefaultBallModel
	local skin = self.PreferredSkin or DAMASHI.DefaultBallSkin
	self:SetModel(mdl)
	self:SetSkin(skin)
	self:SetNWString("DamashiBallModel", mdl)
	self:SetNWString("DamashiBallSkin", skin)

	self.ModelRadius = math.max(self:OBBMaxs().x, 1)
	-- Scale the model once so it matches the starting sphere size, then leave it
	-- fixed forever.  Props pile on at the sphere surface and bury the model;
	-- the physics sphere grows independently via PhysicsInitSphere.
	self:SetModelScale(DAMASHI.BaseRadius / self.ModelRadius, 0)

	self.AbsorbedVolume = 0
	self.VisualProps = {}
	self.PhysRadius = 0
	self.NextJump = 0
	self.NextAbsorbSound = 0
	self.NextCharge = 0
	self.ChargingUntil = 0
	self.NextHurt = 0
	self.ChargeDir = Vector(1, 0, 0)

	-- Tint only the default sphere; custom models carry their own textures.
	if mdl == DAMASHI.DefaultBallModel then
		self:SetColor(HSVToColor(math.random(0, 359), 0.45, 1))
	else
		self:SetColor(Color(255, 255, 255, 255))
	end

	self:ApplyRadius(DAMASHI.BaseRadius)
end

function BALL:ChangeModel(mdl, skin)
	self:SetModel(mdl)
	self:SetSkin(skin)
	self:SetNWString("DamashiBallModel", mdl)
	self:SetNWString("DamashiBallSkin", skin)
	if mdl == DAMASHI.DefaultBallModel then
		self:SetColor(HSVToColor(math.random(0, 359), 0.45, 1))
	else
		self:SetColor(Color(255, 255, 255, 255))
	end
	timer.Simple(0, function()
		if not IsValid(self) then return end
		-- OBBMaxs() returns naturalRadius * currentScale, not naturalRadius.
		-- Setting scale to 1 first guarantees we read the unscaled model bounds,
		-- otherwise ModelRadius is wrong every other call and the size oscillates.
		self:SetModelScale(1, 0)
		self.ModelRadius = math.max(self:OBBMaxs().x, 1)
		self:SetModelScale(DAMASHI.BaseRadius / self.ModelRadius, 0)
	end)
end

-- Firing "Disable"/"Enable" inputs is the only portable way to suppress a specific trigger;
-- brief window is enough for the player to steer clear before re-enable.
local TELE_COOLDOWN = 6
local function disableTrigsAt(pos, r, duration)
	for _, trig in ipairs(ents.FindByClass("trigger_teleport")) do
		if not IsValid(trig) then continue end
		local mins, maxs = trig:WorldSpaceAABB()
		if pos.x >= mins.x - r and pos.x <= maxs.x + r
		and pos.y >= mins.y - r and pos.y <= maxs.y + r
		and pos.z >= mins.z - r and pos.z <= maxs.z + r then
			trig:Fire("Disable", "", 0)
			local t = trig
			timer.Simple(duration, function()
				if IsValid(t) then t:Fire("Enable", "", 0) end
			end)
		end
	end
end

-- By the time this fires, trigger_teleport has already moved the ball to its destination.
function BALL:StartTouch(other)
	if other:GetClass() ~= "trigger_teleport" then return end

	local now       = CurTime()
	local remaining = (self.TeleportCooldownUntil or 0) - now

	if remaining > 0 then
		disableTrigsAt(self:GetPos(), self:GetBallRadius(), remaining + 0.5)
		return
	end

	self.TeleportCooldownUntil = now + TELE_COOLDOWN

	-- Mappers place info_teleport_destination flush with the floor for standing players,
	-- not spheres.  Trace down to find the actual floor and lift the ball clear.
	local pos = self:GetPos()
	local r   = self:GetBallRadius()
	local tr  = util.TraceLine({
		start  = pos + Vector(0, 0, r + 16),
		endpos = pos - Vector(0, 0, 4096),
		mask   = MASK_SOLID_BRUSHONLY,
		filter = self,
	})
	if tr.Hit then
		local safeZ = tr.HitPos.z + r + 8
		if safeZ > pos.z then
			pos = Vector(pos.x, pos.y, safeZ)
			self:SetPos(pos)
			local phys = self:GetPhysicsObject()
			if IsValid(phys) then
				phys:SetVelocity(Vector(0, 0, 0))
				phys:Wake()
			end
		end
	end

	local ball = self
	timer.Simple(0, function()
		if IsValid(ball) then
			disableTrigsAt(ball:GetPos(), ball:GetBallRadius(), TELE_COOLDOWN)
		end
	end)
end

function BALL:ApplyRadius(r)
	self:SetBallRadius(r)

	if self.PhysRadius > 0
		and r < self.PhysRadius * DAMASHI.PhysRebuildGrowth
		and r > self.PhysRadius / DAMASHI.PhysRebuildGrowth then
		return
	end

	local vel, angVel
	local oldPhys = self:GetPhysicsObject()
	if IsValid(oldPhys) then
		vel = oldPhys:GetVelocity()
		angVel = oldPhys:GetAngleVelocity()
	end

	self:PhysicsInitSphere(r, "jeeptire")
	self:SetCollisionBounds(Vector(-r, -r, -r), Vector(r, r, r))
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self.PhysRadius = r

	local phys = self:GetPhysicsObject()
	if IsValid(phys) then
		phys:SetMass(math.Clamp(sphereVolume(r) * 0.0004, 60, 50000))
		phys:SetDamping(0, 0.3)
		phys:EnableMotion(true)
		phys:Wake()
		if vel then
			phys:SetVelocity(vel)
			phys:AddAngleVelocity(angVel - phys:GetAngleVelocity())
		end
	end
end

function BALL:RecomputeRadius()
	local vol = sphereVolume(DAMASHI.BaseRadius) + self.AbsorbedVolume
	local r = (vol * 3 / (4 * math.pi)) ^ (1 / 3)
	local oldR = self:GetBallRadius()

	if r > oldR then
		self:SetPos(self:GetPos() + Vector(0, 0, r - oldR))
	end
	self:ApplyRadius(r)
end

function BALL:GetEntityVolume(ent)
	local total = 0
	for i = 0, ent:GetPhysicsObjectCount() - 1 do
		local phys = ent:GetPhysicsObjectNum(i)
		if IsValid(phys) then
			total = total + (phys:GetVolume() or 0)
		end
	end
	if total <= 0 then
		local size = ent:OBBMaxs() - ent:OBBMins()
		total = size.x * size.y * size.z * 0.5
	end
	return total
end

function BALL:CanAbsorb(ent)
	if not IsValid(ent) or ent.DamashiAbsorbed then return false end
	if not ABSORBABLE[ent:GetClass()] then return false end
	if ent:GetParent() == self then return false end
	if (ent.DamashiNoStick or 0) > CurTime() then return false end
	return self:GetEntityVolume(ent) <= sphereVolume(self:GetBallRadius()) * DAMASHI.AbsorbRatio
end

function BALL:Absorb(ent)
	ent.DamashiAbsorbed = true

	local vol = self:GetEntityVolume(ent)

	constraint.RemoveAll(ent)
	for i = 0, ent:GetPhysicsObjectCount() - 1 do
		local phys = ent:GetPhysicsObjectNum(i)
		if IsValid(phys) then phys:EnableMotion(false) end
	end
	ent:SetSolid(SOLID_NONE)
	ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

	local dir = (ent:WorldSpaceCenter() - self:WorldSpaceCenter())
	if dir:LengthSqr() < 1 then dir = VectorRand() end
	dir:Normalize()
	ent:SetPos(self:WorldSpaceCenter() + dir * self:GetBallRadius())
	ent:SetParent(self)
	self:DeleteOnRemove(ent)

	table.insert(self.VisualProps, ent)
	if #self.VisualProps > DAMASHI.MaxVisualProps then
		local old = table.remove(self.VisualProps, 1)
		if IsValid(old) then old:Remove() end
	end

	self.AbsorbedVolume = self.AbsorbedVolume + vol * DAMASHI.GrowthFactor
	self:RecomputeRadius()

	if CurTime() > self.NextAbsorbSound then
		self.NextAbsorbSound = CurTime() + 0.08
		self:EmitSound("physics/cardboard/cardboard_box_impact_soft2.wav", 70, math.random(150, 210))
	end
end

function BALL:IsCharging()
	return CurTime() < (self.ChargingUntil or 0)
end

function BALL:TryCharge()
	if CurTime() < (self.NextCharge or 0) then return end
	if GAMEMODE.RoundOver then return end

	local ply = self:GetRollingPlayer()
	local phys = self:GetPhysicsObject()
	if not IsValid(ply) or not IsValid(phys) then return end

	local dir = Angle(0, ply:EyeAngles().y, 0):Forward()

	self.NextCharge = CurTime() + DAMASHI.ChargeCooldown
	self:SetChargeReadyTime(self.NextCharge)
	self.ChargingUntil = CurTime() + DAMASHI.ChargeDuration
	self.ChargeDir = dir

	phys:Wake()
	phys:ApplyForceCenter(dir * phys:GetMass() * DAMASHI.ChargeImpulse)
	self:EmitSound("weapons/physcannon/superphys_launch3.wav", 90, 110)
end

function BALL:ChargeHit(victim)
	if CurTime() < (victim.NextHurt or 0) then return end
	victim.NextHurt = CurTime() + DAMASHI.HurtImmunity

	local lossVol   = sphereVolume(self:GetBallRadius()) * DAMASHI.ChargeDamageFactor
	local dropCount = math.Clamp(math.Round(self:GetBallRadius() / 20), 2, 10)

	-- sqrt catch-up: 4× base radius → 2× damage, 9× → 3×
	local sizeScale = (victim:GetBallRadius() / DAMASHI.BaseRadius) ^ DAMASHI.ChargeSizeScaling
	victim:TakeBallDamage(lossVol * sizeScale, math.Round(dropCount * sizeScale), self.ChargeDir)

	local vphys = victim:GetPhysicsObject()
	if IsValid(vphys) then
		vphys:Wake()
		vphys:ApplyForceCenter((self.ChargeDir * DAMASHI.ChargeKnockback + Vector(0, 0, 150)) * vphys:GetMass())
	end

	victim:EmitSound("physics/body/body_medium_impact_hard3.wav", 95, 90)
	util.ScreenShake(victim:GetPos(), 8, 5, 0.6, 600)
end

function BALL:WallSlam()
	if CurTime() < (self.NextHurt or 0) then return end
	self.NextHurt = CurTime() + DAMASHI.HurtImmunity

	local lossVol = sphereVolume(self:GetBallRadius()) * DAMASHI.WallHitPenalty
	local dropCount = math.Clamp(math.Round(self:GetBallRadius() / 30), 1, 4)

	self:TakeBallDamage(lossVol, dropCount, -self.ChargeDir)

	self:EmitSound("physics/concrete/boulder_impact_hard4.wav", 90, 100)
	util.ScreenShake(self:GetPos(), 6, 5, 0.5, 400)
end

function BALL:TakeBallDamage(lossVol, dropCount, flingDir)
	lossVol = math.min(lossVol, self.AbsorbedVolume)
	self.AbsorbedVolume = self.AbsorbedVolume - lossVol
	self:DropProps(dropCount, flingDir or VectorRand())
	self:RecomputeRadius()
end

function BALL:DropProps(count, flingDir)
	local dropped = 0
	while dropped < count and #self.VisualProps > 0 do
		local prop = table.remove(self.VisualProps)
		if IsValid(prop) then
			dropped = dropped + 1

			prop:SetParent(NULL)
			self:DontDeleteOnRemove(prop)
			prop.DamashiAbsorbed = nil
			prop.DamashiNoStick = CurTime() + DAMASHI.DropNoStickTime

			local out = prop:WorldSpaceCenter() - self:WorldSpaceCenter()
			if out:LengthSqr() < 1 then out = VectorRand() end
			out:Normalize()
			prop:SetPos(self:WorldSpaceCenter() + out * (self:GetBallRadius() + prop:BoundingRadius() + 6))

			prop:SetSolid(SOLID_VPHYSICS)
			prop:SetCollisionGroup(COLLISION_GROUP_NONE)

			local fling = flingDir * 180 + out * 160 + Vector(0, 0, math.Rand(120, 220))
			for i = 0, prop:GetPhysicsObjectCount() - 1 do
				local phys = prop:GetPhysicsObjectNum(i)
				if IsValid(phys) then
					phys:EnableMotion(true)
					phys:Wake()
					phys:SetVelocity(fling)
				end
			end
		end
	end

	if dropped > 0 then
		self:EmitSound("physics/cardboard/cardboard_box_impact_hard1.wav", 80, math.random(80, 115))
	end
end

function BALL:IsSlamTarget(other)
	if not IsValid(other) or other:IsWorld() then return true end
	if other:GetClass() == "damashi_ball" then return false end
	if not ABSORBABLE[other:GetClass()] then return true end
	return self:GetEntityVolume(other) > sphereVolume(self:GetBallRadius()) * DAMASHI.AbsorbRatio
end

function BALL:PhysicsCollide(data, phys)
	local other = data.HitEntity

	if self:IsCharging() then
		if IsValid(other) and other:GetClass() == "damashi_ball" then
			self.ChargingUntil = 0
			timer.Simple(0, function()
				if IsValid(self) and IsValid(other) then self:ChargeHit(other) end
			end)
			return
		end

		if data.Speed >= DAMASHI.WallHitMinSpeed and self:IsSlamTarget(other) then
			self.ChargingUntil = 0
			timer.Simple(0, function()
				if IsValid(self) then self:WallSlam() end
			end)
			return
		end
	end

	if IsValid(other) and self:CanAbsorb(other) then
		timer.Simple(0, function()
			if IsValid(self) and IsValid(other) and self:CanAbsorb(other) then
				self:Absorb(other)
			end
		end)
	end
end

function BALL:Think()
	local ply = self:GetRollingPlayer()

	if IsValid(ply) and ply:Alive() and ply.DamashiBall == self then
		ply:SetPos(self:GetPos() + Vector(0, 0, self:GetBallRadius() + 8))

		if not GAMEMODE.RoundOver then
			self:HandleInput(ply)
		end
	end

	self:NextThink(CurTime())
	return true
end

function BALL:HandleInput(ply)
	local phys = self:GetPhysicsObject()
	if not IsValid(phys) then return end

	local yaw = Angle(0, ply:EyeAngles().y, 0)
	local dir = Vector(0, 0, 0)
	if ply:KeyDown(IN_FORWARD)   then dir = dir + yaw:Forward() end
	if ply:KeyDown(IN_BACK)      then dir = dir - yaw:Forward() end
	if ply:KeyDown(IN_MOVERIGHT) then dir = dir + yaw:Right() end
	if ply:KeyDown(IN_MOVELEFT)  then dir = dir - yaw:Right() end

	local r = self:GetBallRadius()
	local vel = phys:GetVelocity()
	local horizVel = Vector(vel.x, vel.y, 0)
	local speed = horizVel:Length()
	local speedCap = DAMASHI.SpeedCapBase + r * DAMASHI.SpeedCapPerRadius

	if dir:LengthSqr() > 0 then
		dir:Normalize()
		if speed < speedCap then
			phys:ApplyForceCenter(dir * phys:GetMass() * DAMASHI.Accel * FrameTime())
		end
	end

	if speed > speedCap then
		local excess = speed - speedCap
		phys:ApplyForceCenter(
			-horizVel:GetNormalized() * phys:GetMass() * excess * DAMASHI.ChargeBrake * FrameTime()
		)
	end

	if ply:KeyDown(IN_JUMP) and CurTime() > self.NextJump then
		local tr = util.TraceLine({
			start = self:GetPos(),
			endpos = self:GetPos() - Vector(0, 0, r + 10),
			filter = self,
			mask = MASK_SOLID,
		})
		if tr.Hit then
			self.NextJump = CurTime() + DAMASHI.JumpCooldown
			phys:ApplyForceCenter(Vector(0, 0, phys:GetMass() * DAMASHI.JumpPower))
		end
	end
end
