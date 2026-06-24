-- ---------------------------------------------------------------------------
-- TokenTrend - NDui-inspired flat skinning (pixel border, shadow, gradient).
-- ---------------------------------------------------------------------------
-- NDui skin media (bundled in TokenTrend/Media/):
--   glowTex.blp — soft drop shadow
--   bgTex.blp   — tiled panel wash
--   flatTex.blp — flat gradient tile (optional; not wired yet)

local _, ns = ...

local Skin = {}
ns.Skin = Skin

local CreateColor = CreateColor
local max = math.max
local floor = math.floor

local ADDON_MEDIA = "Interface\\AddOns\\TokenTrend\\Media\\"
Skin.bdTex = "Interface\\ChatFrame\\ChatFrameBackground"
Skin.blizzBgTex = "Interface\\Tooltips\\UI-Tooltip-Background"

-- Prefer bundled media when present; probe once at load.
local function probeTexture(path)
	local t = UIParent:CreateTexture(nil, "ARTWORK")
	t:SetTexture(path)
	local ok = t:GetTexture() ~= nil
	t:Hide()
	return ok
end

local function pickMedia(filename, fallback)
	local path = ADDON_MEDIA .. filename
	if probeTexture(path) then
		return path
	end
	return fallback
end

Skin.glowTex = pickMedia("glowTex.blp", Skin.bdTex)
Skin.bgTex = pickMedia("bgTex.blp", Skin.blizzBgTex)

local PIXEL = 1

local defaultBD = { bgFile = Skin.bdTex, edgeFile = Skin.bdTex, edgeSize = PIXEL }

local shadowEdgeOnly = { edgeFile = Skin.glowTex, edgeSize = 5 }

function Skin.SetInside(frame, anchor, x, y)
	x = x or PIXEL
	y = y or PIXEL
	anchor = anchor or frame:GetParent()
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, -y)
	frame:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -x, y)
end

function Skin.SetOutside(frame, anchor, x, y)
	x = x or PIXEL
	y = y or PIXEL
	anchor = anchor or frame:GetParent()
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", -x, y)
	frame:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", x, -y)
end

function Skin.EnsureBackdrop(frame)
	if not frame.SetBackdrop then
		Mixin(frame, BackdropTemplateMixin)
	end
end

function Skin.ApplyPixelBorder(bg, alpha)
	bg:SetBackdropBorderColor(0, 0, 0, alpha or 1)
end

function Skin.TintBackdrop(bg, rgb, a)
	bg:SetBackdropColor(rgb[1], rgb[2], rgb[3], a or 1)
end

-- NDui CreateSD — glow edge only, child of frame (hides with parent).
function Skin.CreateShadow(frame, inset)
	if frame.__ttShadow then
		return frame.__ttShadow
	end
	inset = inset or 4

	local shadow = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	Skin.EnsureBackdrop(shadow)
	Skin.SetOutside(shadow, frame, inset, inset)

	shadowEdgeOnly.edgeSize = inset
	shadow:SetBackdrop(shadowEdgeOnly)
	-- NDui default: 0.4 alpha; slightly softer than 1.0 override paths.
	shadow:SetBackdropBorderColor(0, 0, 0, 0.4)
	shadow:SetFrameLevel(0)

	local onSize = shadow:GetScript("OnSizeChanged")
	if onSize then
		shadow:SetScript("OnSizeChanged", function(self, ...)
			pcall(onSize, self, ...)
		end)
	end

	frame.__ttShadow = shadow
	return shadow
end

-- NDui CreateTex — tiled panel wash.
function Skin.CreateBgTex(frame, alpha)
	if frame.__ttBgTex then
		return frame.__ttBgTex
	end
	alpha = alpha or 0.06

	local tex = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
	tex:SetAllPoints()
	tex:SetTexture(Skin.bgTex, true, true)
	tex:SetHorizTile(true)
	tex:SetVertTile(true)
	if Skin.bgTex == Skin.blizzBgTex then
		tex:SetBlendMode("BLEND")
	else
		tex:SetBlendMode("ADD")
	end
	tex:SetAlpha(alpha)

	frame.__ttBgTex = tex
	return tex
end

-- Vertical panel gradient (NDui CreateGradient on frames, palette-aware).
function Skin.ApplyPanelGradient(frame, role)
	if frame.__ttPanelGrad or not CreateColor then
		return
	end

	local tex = frame:CreateTexture(nil, "BORDER", nil, -1)
	Skin.SetInside(tex, frame, 1)
	tex:SetTexture(Skin.bdTex)

	local p = ns:Palette()
	local base = (role == "panel") and p.panel or p.bg
	tex:SetGradient("VERTICAL",
		CreateColor(base[1] * 0.88, base[2] * 0.88, base[3] * 0.88, 0.35),
		CreateColor(base[1] * 1.05, base[2] * 1.05, base[3] * 1.05, 0.12))

	frame.__ttPanelGrad = tex
end

local function applyButtonGradient(tex, p, accent)
	if not tex or not CreateColor then
		return
	end
	if accent then
		tex:SetGradient("VERTICAL",
			CreateColor(p.accent[1] * 0.4, p.accent[2] * 0.4, p.accent[3] * 0.4, 0.7),
			CreateColor(p.accent[1] * 0.15, p.accent[2] * 0.15, p.accent[3] * 0.15, 0.2))
	else
		local r, g, b = p.panel[1], p.panel[2], p.panel[3]
		tex:SetGradient("VERTICAL",
			CreateColor(r * 0.72, g * 0.72, b * 0.72, 0.98),
			CreateColor(r * 1.18, g * 1.18, b * 1.18, 0.42))
	end
end

function Skin.RefreshBackdrop(bg)
	if not bg then
		return
	end
	local p = ns:Palette()
	if bg.__ttIsButton then
		bg:SetBackdropColor(0, 0, 0, 0)
		Skin.ApplyPixelBorder(bg, 1)
		applyButtonGradient(bg.__ttGradient, p, false)
		return
	end

	local rgb = p.panel
	if bg.__ttRole == "window" or bg.__ttRole == "plot" then
		rgb = p.bg
	end
	Skin.TintBackdrop(bg, rgb, 1)
	Skin.ApplyPixelBorder(bg, 1)

	if bg.__ttPanelGrad and CreateColor then
		local base = rgb
		bg.__ttPanelGrad:SetGradient("VERTICAL",
			CreateColor(base[1] * 0.88, base[2] * 0.88, base[3] * 0.88, 0.35),
			CreateColor(base[1] * 1.05, base[2] * 1.05, base[3] * 1.05, 0.12))
	end
end

function Skin.ApplyPanelBackdrop(frame, role)
	Skin.EnsureBackdrop(frame)
	defaultBD.edgeSize = PIXEL
	frame:SetBackdrop(defaultBD)
	frame.__ttRole = role

	local p = ns:Palette()
	local rgb = p.panel
	if role == "window" or role == "plot" then
		rgb = p.bg
	end
	Skin.TintBackdrop(frame, rgb, 1)
	Skin.ApplyPixelBorder(frame, 1)
	Skin.ApplyPanelGradient(frame, role)
end

function Skin.AttachButtonBg(button, opts)
	opts = opts or {}

	local bg = CreateFrame("Frame", nil, button, "BackdropTemplate")
	Skin.EnsureBackdrop(bg)
	bg:SetBackdrop(defaultBD)
	bg:SetBackdropColor(0, 0, 0, 0)
	Skin.ApplyPixelBorder(bg, 1)

	bg:SetFrameLevel(max(0, button:GetFrameLevel() - 1))
	Skin.SetInside(bg, button, 0)

	local wash = bg:CreateTexture(nil, "BORDER")
	Skin.SetInside(wash, bg, 1)
	wash:SetTexture(Skin.bdTex)

	bg.__ttIsButton = true
	bg.__ttGradient = wash
	button.__bg = bg
	button.__ttGradient = wash

	local function rest()
		local p = ns:Palette()
		bg:SetBackdropColor(0, 0, 0, 0)
		Skin.ApplyPixelBorder(bg, 1)
		applyButtonGradient(wash, p, false)
	end

	function button:SetFlatHover(on)
		local p = ns:Palette()
		if on then
			bg:SetBackdropBorderColor(p.accent[1], p.accent[2], p.accent[3], 1)
			applyButtonGradient(wash, p, true)
		else
			rest()
		end
	end

	button.SetFlatRest = rest
	rest()

	if not opts.noHover then
		button:HookScript("OnEnter", function(self)
			if self:IsEnabled() ~= false and not self.__ttActive then
				self:SetFlatHover(true)
			end
		end)
		button:HookScript("OnLeave", function(self)
			if not self.__ttActive then
				self:SetFlatHover(false)
			end
		end)
	end

	return bg
end

function Skin.SetButtonActive(button, active)
	if not button or not button.__bg then
		return
	end
	button.__ttActive = active and true or nil
	button:SetFlatHover(active and true or false)
end

-- Expose pixel backdrop table for banners/tooltips.
function Skin.BackdropTable()
	return { bgFile = Skin.bdTex, edgeFile = Skin.bdTex, edgeSize = PIXEL }
end
