-- ---------------------------------------------------------------------------
-- TokenTrend - Minimap button. Tiny, draggable, no external libs.
-- ---------------------------------------------------------------------------

local _, ns = ...
local L = ns.L

local cos, sin, rad, atan2, deg = math.cos, math.sin, math.rad, math.atan2, math.deg

local Minimap = {}
ns.Minimap = Minimap

local MinimapFrame = _G.Minimap
local button
local dragAngle

local function updatePosition()
	if not button then return end
	local angle = rad(ns.db.minimap.angle or 215)
	local r = (MinimapFrame:GetWidth() / 2) + 6
	button:SetPoint("CENTER", MinimapFrame, "CENTER", cos(angle) * r, sin(angle) * r)
end

local function onDragUpdate()
	local mx, my = MinimapFrame:GetCenter()
	local scale = MinimapFrame:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	cx, cy = cx / scale, cy / scale
	dragAngle = deg(atan2(cy - my, cx - mx)) % 360
	local r = (MinimapFrame:GetWidth() / 2) + 6
	local a = rad(dragAngle)
	button:SetPoint("CENTER", MinimapFrame, "CENTER", cos(a) * r, sin(a) * r)
end

local function showMenu(self)
	MenuUtil.CreateContextMenu(self, function(owner, rootDescription)
		rootDescription:CreateTitle(L["TokenTrend"])
		rootDescription:CreateButton(L["Toggle window"], function()
			ns.UI:Toggle()
		end)
		rootDescription:CreateButton(L["Refresh"], function()
			ns:RequestPriceRefresh()
		end)
		rootDescription:CreateDivider()
		rootDescription:CreateButton(L["Hide minimap button"], function()
			Minimap:SetShown(false)
			ns.Print(L["Minimap button hidden. Type /tt minimap to restore."])
		end)
	end)
end

local function createButton()
	button = CreateFrame("Button", "TokenTrendMinimapButton", MinimapFrame)
	button:SetFrameStrata("MEDIUM")
	button:SetSize(31, 31)
	button:SetFrameLevel(8)
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")

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

	button:SetScript("OnClick", function(_, clickBtn)
		if clickBtn == "RightButton" then
			showMenu(button)
		else
			ns.UI:Toggle()
		end
	end)

	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", onDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		if dragAngle then
			ns.db.minimap.angle = dragAngle
			dragAngle = nil
		end
		updatePosition()
	end)

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L["TokenTrend"])
		local price = ns.Data and ns.Data.current
		GameTooltip:AddLine(L["Current Price"] .. ": " .. ns.F.FormatGold(price), 1, 1, 1)
		GameTooltip:AddLine("|cffaaaaaa" .. L["/tt - toggle the window"] .. "|r")
		GameTooltip:AddLine("|cffaaaaaa" .. L["Right-click for menu"] .. "|r")
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

function Minimap:SetShown(show)
	ns.db.minimap.hide = not show
	if show then
		if not button then
			createButton()
		end
		button:Show()
		updatePosition()
	else
		if button then
			button:Hide()
		end
	end
end

function Minimap:Toggle()
	self:SetShown(ns.db.minimap.hide)
end

ns:OnLogin(function()
	Minimap:SetShown(not ns.db.minimap.hide)
end)
