-------------------------------------------------------------------------------
--  EllesmereUI skin for PallyPower's blessing assignment window
--  (/pp blessings, /ppe assign). Uses EllesmereUI's skinning API, so it follows
--  the user's theme and can be turned off under Blizzard Skins+ > Window
--  Skins > Third-Party Addons ("PallyPower").
-------------------------------------------------------------------------------
local ADDON, ns = ...
if not ns.DB then return end -- Core.lua stopped early (not WoW Forever)

local EUI = EllesmereUI
if not (EUI and EUI.RegisterSkin) then return end

local MENU_BUTTONS = {"Refresh", "Clear", "AutoAssign", "Options", "Preset", "Report"}

-- Every texture named ...Icon / ...IconN / ...AIconN gets squared; every font string re-fonted.
local function SkinTree(S, frame, depth)
	if depth > 6 or not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
	for _, r in ipairs({frame:GetRegions()}) do
		local name = r.GetName and r:GetName()
		local kind = r.GetObjectType and r:GetObjectType()
		if kind == "FontString" then
			S.Font(r)
		elseif kind == "Texture" and name then
			if name:match("Icon%d*$") then
				S.SquareIcon(r)
			elseif name:match("Line$") then
				-- the column dividers: a hairline in the theme instead of tooltip art
				r:SetColorTexture(1, 1, 1, 0.08)
				r:SetWidth(1)
			end
		end
	end
	for _, child in ipairs({frame:GetChildren()}) do
		SkinTree(S, child, depth + 1)
	end
end

-- The checkbox EllesmereUI's own options use: an 18px dark box with a thin border,
-- filled with a solid accent square when checked (accent border too). S.Checkbox
-- only flattens the box and tints Blizzard's checkmark, which reads as stock art.
local WHITE = "Interface\\Buttons\\WHITE8x8"
local function EUICheckbox(S, cb)
	if cb.IsForbidden and cb:IsForbidden() then return end
	for _, get in ipairs({"GetNormalTexture", "GetPushedTexture", "GetHighlightTexture",
		"GetCheckedTexture", "GetDisabledCheckedTexture", "GetDisabledTexture"}) do
		local t = cb[get] and cb[get](cb)
		if t then t:SetAlpha(0) end
	end
	for _, r in ipairs({cb:GetRegions()}) do
		if r.IsObjectType and r:IsObjectType("Texture") then r:SetAlpha(0) end
	end

	local box = CreateFrame("Frame", nil, cb, "BackdropTemplate")
	box:SetSize(18, 18)
	box:SetPoint("CENTER")
	box:SetFrameLevel(cb:GetFrameLevel() + 1)
	box:SetBackdrop({bgFile = WHITE, edgeFile = WHITE, edgeSize = 1})
	box:EnableMouse(false)
	local check = box:CreateTexture(nil, "ARTWORK")
	check:SetPoint("TOPLEFT", 2, -2)
	check:SetPoint("BOTTOMRIGHT", -2, 2)

	local hovering = false
	local function Paint()
		local acc = EUI.ELLESMERE_GREEN or {}
		local ar, ag, ab = acc.r or 0.047, acc.g or 0.824, acc.b or 0.616
		local br, bg, bb = EUI.CB_BOX_R or 0.08, EUI.CB_BOX_G or 0.08, EUI.CB_BOX_B or 0.08
		local er, eg, eb = EUI.BORDER_R or 1, EUI.BORDER_G or 1, EUI.BORDER_B or 1
		local brdA, actA = EUI.CB_BRD_A or 0.25, EUI.CB_ACT_BRD_A or 0.6
		check:SetColorTexture(ar, ag, ab, 1)
		if cb:GetChecked() then
			check:Show()
			box:SetBackdropColor(br, bg, bb, 1)
			box:SetBackdropBorderColor(ar, ag, ab, actA)
		else
			check:Hide()
			local a = hovering and 1 or 0.8
			box:SetBackdropColor(br, bg, bb, a)
			box:SetBackdropBorderColor(er, eg, eb, brdA * a)
		end
	end
	hooksecurefunc(cb, "SetChecked", Paint)
	cb:HookScript("OnClick", Paint)
	cb:HookScript("OnShow", Paint)
	cb:HookScript("OnEnter", function() hovering = true Paint() end)
	cb:HookScript("OnLeave", function() hovering = false Paint() end)
	S.OnLooksChanged(Paint)
	Paint()
end

EUI.RegisterSkin("PallyPower", function(S)
	local f = _G.PallyPowerBlessingsFrame
	if not f then return end
	S.Shell(f)
	if f.NineSlice then S.FadeNineSlice(f.NineSlice) end

	local close = _G.PallyPowerBlessingsFrameCloseButton
	if close then S.CloseButton(close) end

	for _, key in ipairs(MENU_BUTTONS) do
		local b = _G["PallyPowerBlessingsFrame" .. key]
		if b then
			S.Button(b)
			S.WhiteButtonLabel(b)
		end
	end

	local free = _G.PallyPowerBlessingsFrameFreeAssign
	if free then EUICheckbox(S, free) end

	SkinTree(S, f, 0)

	local title = _G.PallyPowerBlessingsFrameTitleText
	if title then
		local r, g, b = S.GetAccentColor()
		S.Font(title, r, g, b)
		S.OnLooksChanged(function()
			S.Font(title, S.GetAccentColor())
		end)
	end
end)
