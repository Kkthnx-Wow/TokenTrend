-- ---------------------------------------------------------------------------
-- TokenTrend - Minimap button. Tiny, draggable, no external libs.
-- ---------------------------------------------------------------------------

local _, ns = ...
local L = ns.L

local cos, sin, rad, atan2, deg = math.cos, math.sin, math.rad, math.atan2, math.deg

local Minimap = _G.Minimap

local button

-- Park the button on the minimap ring at the saved angle.
local function updatePosition()
	local angle = rad(ns.db.minimap.angle or 215)
	local r = (Minimap:GetWidth() / 2) + 6
	button:SetPoint("CENTER", Minimap, "CENTER", cos(angle) * r, sin(angle) * r)
end

-- Dragging: convert cursor position relative to minimap center into an angle.
local function onDragUpdate()
	local mx, my = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	cx, cy = cx / scale, cy / scale
	ns.db.minimap.angle = deg(atan2(cy - my, cx - mx)) % 360
	updatePosition()
end

local function createButton()
	button = CreateFrame("Button", "TokenTrendMinimapButton", Minimap)
	button:SetFrameStrata("MEDIUM")
	button:SetSize(31, 31)
	button:SetFrameLevel(8)
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")

	-- Ring overlay (the classic minimap-button border).
	local overlay = button:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53)
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")

	local bg = button:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetPoint("TOPLEFT", 7, -5)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(19, 19)
	icon:SetPoint("TOPLEFT", 7, -6)
	ns.F.SetTokenIcon(icon)

	button:SetScript("OnClick", function()
		ns.UI:Toggle()
	end)

	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", onDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L["TokenTrend"])
		local price = ns.Data and ns.Data.current
		GameTooltip:AddLine(L["Current Price"] .. ": " .. ns.F.FormatGold(price), 1, 1, 1)
		GameTooltip:AddLine("|cffaaaaaa" .. L["/tt - toggle the window"] .. "|r")
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

ns:OnLogin(function()
	if ns.db.minimap.hide then return end
	createButton()
	updatePosition()
end)
