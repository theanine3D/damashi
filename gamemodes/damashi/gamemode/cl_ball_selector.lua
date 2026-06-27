local BallModels = {}
local SelectorFrame = nil

local COL_BG       = Color(20, 20, 30, 230)
local COL_BORDER   = Color(60, 60, 80, 255)
local COL_SELECTED = Color(80, 200, 110, 255)
local COL_HOVER    = Color(60, 80, 110, 220)
local COL_TEXT     = Color(240, 240, 245, 255)
local COL_DIM      = Color(170, 170, 185, 255)

net.Receive("damashi_ball_models", function()
	BallModels = {}
	local count = net.ReadUInt(8)
	for i = 1, count do
		table.insert(BallModels, net.ReadString())
	end
end)

local function modelDisplayName(mdl, skin, appendSkinNum)
	if mdl == DAMASHI.DefaultBallModel then return "Default" end
	local stem = mdl:match("ball_([^/]+)%.mdl$")
	local dispName
	if stem then
		stem = stem:gsub("_", " ")
		dispName = stem:sub(1, 1):upper() .. stem:sub(2)
	else
		dispName = mdl:match("([^/]+)%.mdl$") or mdl
	end
	if appendSkinNum then 
		dispName = dispName .. string.format(" (Skin %u)", skin)
	end
	return dispName
end

local function currentModel()
	if not IsValid(LocalPlayer()) then return DAMASHI.DefaultBallModel end
	return LocalPlayer():GetNWString("DamashiBallModel", DAMASHI.DefaultBallModel)
end

local function currentSkin()
	if not IsValid(LocalPlayer()) then return DAMASHI.DefaultBallSkin end
	return LocalPlayer():GetNWString("DamashiBallSkin", DAMASHI.DefaultBallSkin)
end

local ENTRY_W  = 148
local ENTRY_H  = 200
local LABEL_H  = 32
local PADDING  = 10

local function BuildSelector()
	if IsValid(SelectorFrame) then SelectorFrame:Remove() end

	local models = BallModels
	if #models == 0 then
		models = { DAMASHI.DefaultBallModel }
	end

	local cols = math.max(1, math.min(#models, 5))
	local rows = math.ceil(#models / cols)
	local innerW = cols * (ENTRY_W + PADDING) + PADDING
	local innerH = rows * (ENTRY_H + PADDING) + PADDING

	local frameW = math.Clamp(innerW + 20, 280, ScrW() - 60)
	local frameH = math.Clamp(innerH + 60, 200, ScrH() - 80)

	local frame = vgui.Create("DFrame")
	SelectorFrame = frame
	frame:SetTitle("Select Ball")
	frame:SetSize(frameW, frameH)
	frame:Center()
	frame:MakePopup()
	frame:SetDraggable(true)
	frame:SetDeleteOnClose(true)
	// Make frame auto-close when the pause menu opens
	hook.Add("OnPauseMenuShow", frame, function()
		frame:Close()
	end)

	local scroll = vgui.Create("DScrollPanel", frame)
	scroll:Dock(FILL)
	scroll:DockMargin(4, 4, 4, 4)

	local layout = vgui.Create("DIconLayout", scroll)
	layout:Dock(FILL)
	layout:SetSpaceX(PADDING)
	layout:SetSpaceY(PADDING)
	layout:SetBorder(PADDING)

	local selMdl = currentModel()
	local selSkin = currentSkin()
	
	// Set up model list
	for _, mdl in ipairs(models) do
		local skinCount = util.GetModelInfo(mdl).SkinCount
		for skin = 0, skinCount - 1 do
			local isSelected = (mdl == selMdl) and (skin == selSkin or skinCount == 1)

			local entry = vgui.Create("DButton", layout)
			entry:SetSize(ENTRY_W, ENTRY_H)
			entry:SetText("")
			entry.mdl = mdl
			entry.skin = skin

			entry.Paint = function(self, w, h)
				local bg = isSelected and COL_SELECTED or COL_BG
				draw.RoundedBox(6, 0, 0, w, h, bg)
				surface.SetDrawColor(isSelected and COL_SELECTED or COL_BORDER)
				surface.DrawOutlinedRect(0, 0, w, h, 2)
			end

			-- Label docked first so FILL takes the remaining space above it.
			local lbl = vgui.Create("DLabel", entry)
			lbl:Dock(BOTTOM)
			lbl:SetHeight(LABEL_H)
			lbl:SetText(modelDisplayName(mdl, skin, skinCount > 1))
			lbl:SetFont("DamashiHUDSmall")
			lbl:SetTextColor(COL_TEXT)
			lbl:SetContentAlignment(5)

			local mdlPanel = vgui.Create("DModelPanel", entry)
			mdlPanel:Dock(FILL)
			mdlPanel:DockMargin(4, 4, 4, 2)
			mdlPanel:SetModel(mdl)
			local mdlPanelEnt = mdlPanel:GetEntity()
			mdlPanelEnt:SetSkin(skin)
			// set model scale
			local mdlPanelEntBoundsMin, mdlPanelEntBoundsMax = mdlPanelEnt:GetRenderBounds()
			local mdlPanelEntBounds = mdlPanelEntBoundsMax - mdlPanelEntBoundsMin
			local mdlPanelEntBoundsLen = math.max(mdlPanelEntBounds.x, mdlPanelEntBounds.y, mdlPanelEntBounds.z)
			mdlPanelEnt:SetModelScale(75.0 / mdlPanelEntBoundsLen, 0)
			mdlPanel:SetCamPos(Vector(70, 45, 35))
			mdlPanel:SetLookAt(Vector(0, 0, 0))
			mdlPanel:SetFOV(50)
			mdlPanel:SetMouseInputEnabled(false)

			function mdlPanel:LayoutEntity(ent)
				ent:SetAngles(Angle(0, RealTime() * 35 % 360, 0))
			end

			entry.OnCursorEntered = function(self)
				if not isSelected then
					self.Paint = function(s, w, h)
						draw.RoundedBox(6, 0, 0, w, h, COL_HOVER)
						surface.SetDrawColor(COL_BORDER)
						surface.DrawOutlinedRect(0, 0, w, h, 2)
					end
				end
			end
			entry.OnCursorExited = function(self)
				if not isSelected then
					self.Paint = function(s, w, h)
						draw.RoundedBox(6, 0, 0, w, h, COL_BG)
						surface.SetDrawColor(COL_BORDER)
						surface.DrawOutlinedRect(0, 0, w, h, 2)
					end
				end
			end

			entry.DoClick = function(self)
				net.Start("damashi_select_ball")
					net.WriteString(self.mdl)
					net.WriteUInt(self.skin, 10)
				net.SendToServer()
				frame:Close()
			end
			entry:SetCursor("hand")

			-- DModelPanel consumes clicks; forward them to the entry so the whole card is clickable.
			mdlPanel.DoClick = function() entry:DoClick() end
		end
	end
end

concommand.Add("damashi_open_selector", function()
	if IsValid(SelectorFrame) then
		SelectorFrame:Close()
	else
		BuildSelector()
	end
end, nil, "Open the Damashi ball model selector.")

hook.Add("InitPostEntity", "damashi_selector_hint", function()
	timer.Simple(3, function()
		hook.Remove("InitPostEntity", "damashi_selector_hint")
		local ply = LocalPlayer()
		if not IsValid(ply) then return end
		chat.AddText(Color(100, 200, 130), "[Damashi] ",
			Color(220, 220, 230), "Ball selector: ",
			Color(255, 220, 60), "N",
			Color(220, 220, 230), "   Music: ",
			Color(255, 220, 60), "M")
	end)
end)
