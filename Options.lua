-------------------------------------------------------------------------------
--  Settings page in the EllesmereUI options panel, and the /ppe command.
-------------------------------------------------------------------------------
local ADDON, ns = ...
if not ns.DB then return end -- Core.lua stopped early (not WoW Forever)

local EUI = EllesmereUI
local PP = PallyPower
local PLUGIN_ID = ADDON -- "PallyPower_EllesmereUI": the plugin id is the folder name
local WHITE = "Interface\\Buttons\\WHITE8x8"
local issecretvalue = _G.issecretvalue or function() return false end

local function OpenAssignments()
	if EUI and EUI.IsShown and EUI:IsShown() then EUI:Hide() end
	if PallyPowerBlessings_Toggle then PallyPowerBlessings_Toggle() end
end

-------------------------------------------------------------------------------
--  Preview: a copy of your EllesmereUI player frame (size, portrait, bars and
--  every text it shows) with a castbar under it, like EUI's own player preview,
--  and the blessing icon painted exactly as on the real frames. (EUI's own
--  preview builder is private to its options addon, so it is rebuilt here.)
-------------------------------------------------------------------------------
local preview -- { frame, mock, icon, name }
local PREVIEW_PAD = 26

-- region's rectangle relative to the live frame's top left, in the live frame's scale
local function RelRect(live, region)
	if not (region and region.GetLeft and region.IsShown and region:IsShown()) then return end
	local ok, l, t, w, h = pcall(function()
		return region:GetLeft(), region:GetTop(), region:GetSize()
	end)
	local fl, ft = live:GetLeft(), live:GetTop()
	if not (ok and l and t and w and h and fl and ft) then return end
	local s = region:GetEffectiveScale() / live:GetEffectiveScale()
	return l * s - fl, t * s - ft, w * s, h * s
end

local function BarLook(bar, fallbackR, fallbackG, fallbackB)
	local tex, r, g, b = WHITE, fallbackR, fallbackG, fallbackB
	if bar and bar.GetStatusBarTexture then
		pcall(function()
			local t = bar:GetStatusBarTexture()
			local file = t and t:GetTexture()
			if file then tex = file end
			local cr, cg, cb = bar:GetStatusBarColor()
			if cr and not issecretvalue(cr) then r, g, b = cr, cg, cb end
		end)
	end
	return tex, r, g, b
end

local function BuildMock(parent)
	local live = _G.EllesmereUIUnitFrames_Player
	local W, H = 240, 50
	if live then
		local w, h = live:GetSize()
		if w and h and w > 20 and h > 10 then W, H = w, h end
	end

	local m = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	m:SetSize(W, H)
	m:SetBackdrop({bgFile = WHITE, edgeFile = WHITE, edgeSize = 1})
	m:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
	m:SetBackdropBorderColor(0, 0, 0, 1)

	-- portrait
	local px, py, pw, ph
	if live then
		local p = live.Portrait
		px, py, pw, ph = RelRect(live, type(p) == "table" and (p.backdrop or p) or nil)
	end
	if not px and not live then px, py, pw, ph = 0, 0, H, H end
	if px then
		local pf = CreateFrame("Frame", nil, m)
		pf:SetPoint("TOPLEFT", m, "TOPLEFT", px, py)
		pf:SetSize(pw, ph)
		local tex = pf:CreateTexture(nil, "ARTWORK")
		tex:SetAllPoints()
		SetPortraitTexture(tex, "player")
		tex:SetTexCoord(0.15, 0.85, 0.15, 0.85)
		m.Portrait = {backdrop = pf} -- same shape PaintIcon looks for on EUI frames
	end

	-- health and power bars
	local function Bar(region, fr, fg, fb, value, defaultRect)
		local x, y, w, h
		if live and region then x, y, w, h = RelRect(live, region) end
		if not x then x, y, w, h = defaultRect[1], defaultRect[2], defaultRect[3], defaultRect[4] end
		local tex, r, g, b = BarLook(region, fr, fg, fb)
		local bar = CreateFrame("StatusBar", nil, m)
		bar:SetPoint("TOPLEFT", m, "TOPLEFT", x, y)
		bar:SetSize(w, h)
		bar:SetStatusBarTexture(tex)
		bar:SetStatusBarColor(r, g, b)
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(value)
		local bg = bar:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.5)
		return bar
	end
	local left = px and (px + pw) or 0
	local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS.PALADIN or {r = 0.96, g = 0.55, b = 0.73}
	local health = Bar(live and live.Health, cc.r, cc.g, cc.b, 0.62, {left, 0, W - left, H * 0.72})
	Bar(live and live.Power, 0, 0.55, 1, 0.6, {left, -H * 0.72, W - left, H * 0.28})

	-- text: every font string the live frame shows (name/level, health, power ...),
	-- copied with its font, color and place; drawn above the bars
	local textLayer = CreateFrame("Frame", nil, m)
	textLayer:SetAllPoints()
	textLayer:SetFrameLevel(m:GetFrameLevel() + 10)
	local top, bottom, copied = 0, 0, 0
	local function Within(r)
		local p = r
		while p and p ~= live do
			if p.IsShown and not p:IsShown() then return false end
			p = p:GetParent()
		end
		return p == live
	end
	local function Visit(fr, depth)
		if depth > 5 or copied >= 16 then return end
		for _, r in ipairs({fr:GetRegions()}) do
			if r:GetObjectType() == "FontString" and Within(r) then
				local x, y, w, h = RelRect(live, r)
				if x and w > 0 and h > 0 then
					local ok = pcall(function()
						local text = r:GetText()
						if not issecretvalue(text) and (not text or text == "") then error("empty") end
						local fs = textLayer:CreateFontString(nil, "OVERLAY")
						local font, size, flags = r:GetFont()
						fs:SetFont(font, size, flags)
						fs:SetTextColor(r:GetTextColor())
						fs:SetShadowColor(r:GetShadowColor())
						fs:SetShadowOffset(r:GetShadowOffset())
						fs:SetJustifyH(r:GetJustifyH())
						fs:SetJustifyV(r:GetJustifyV())
						fs:SetWordWrap(false)
						fs:SetSize(w + 2, h)
						fs:SetPoint("TOPLEFT", m, "TOPLEFT", x, y)
						fs:SetText(text)
					end)
					if ok then
						copied = copied + 1
						if y > top then top = y end
						if -(y - h) - H > bottom then bottom = -(y - h) - H end
					end
				end
			end
		end
		for _, c in ipairs({fr:GetChildren()}) do
			-- skip our own blessing icon and cooldown timers
			if not ns.icons[live] or c ~= ns.icons[live] then
				if c:GetObjectType() ~= "Cooldown" then Visit(c, depth + 1) end
			end
		end
	end
	if live then pcall(Visit, live, 0) end
	if copied == 0 then
		-- no live frame to copy: "level | name" above, as EllesmereUI shows it
		local path, flags = STANDARD_TEXT_FONT, "OUTLINE"
		if EUI.GetFontPath then path = EUI.GetFontPath("EllesmereUIUnitFrames") or path end
		if EUI.GetFontOutlineFlag then flags = EUI.GetFontOutlineFlag("EllesmereUIUnitFrames") or flags end
		local name = textLayer:CreateFontString(nil, "OVERLAY")
		name:SetFont(path, 14, flags)
		name:SetText("|cffffd100" .. (UnitLevel("player") or "") .. "|r | " .. (UnitName("player") or ""))
		name:SetTextColor(cc.r, cc.g, cc.b)
		name:SetPoint("BOTTOM", m, "TOP", 0, 3)
		top = 20
	end

	-- castbar under the frame, like EllesmereUI's own player preview
	local cbH = 14
	local castbar = CreateFrame("StatusBar", nil, m)
	castbar:SetPoint("TOPLEFT", m, "BOTTOMLEFT", cbH, 0)
	castbar:SetPoint("TOPRIGHT", m, "BOTTOMRIGHT", 0, 0)
	castbar:SetHeight(cbH)
	castbar:SetStatusBarTexture((BarLook(live and live.Health, 1, 1, 1)))
	castbar:SetStatusBarColor(0.58, 0.52, 0.86)
	castbar:SetMinMaxValues(0, 1)
	castbar:SetValue(0.7)
	local cbg = castbar:CreateTexture(nil, "BACKGROUND")
	cbg:SetAllPoints()
	cbg:SetColorTexture(0, 0, 0, 0.6)
	local cicon = castbar:CreateTexture(nil, "ARTWORK")
	cicon:SetSize(cbH, cbH)
	cicon:SetPoint("RIGHT", castbar, "LEFT", 0, 0)
	cicon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local holy = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(635)) or 135920
	cicon:SetTexture(holy)
	local cpath, cflags = STANDARD_TEXT_FONT, "OUTLINE"
	if EUI.GetFontPath then cpath = EUI.GetFontPath("EllesmereUIUnitFrames") or cpath end
	if EUI.GetFontOutlineFlag then cflags = EUI.GetFontOutlineFlag("EllesmereUIUnitFrames") or cflags end
	local cname = castbar:CreateFontString(nil, "OVERLAY")
	cname:SetFont(cpath, 11, cflags)
	cname:SetPoint("LEFT", castbar, "LEFT", 4, 0)
	cname:SetText((C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(635)) or "Holy Light")
	local ctime = castbar:CreateFontString(nil, "OVERLAY")
	ctime:SetFont(cpath, 11, cflags)
	ctime:SetPoint("RIGHT", castbar, "RIGHT", -4, 0)
	ctime:SetText("0.8")
	bottom = math.max(bottom, cbH)

	m.extentTop, m.extentBottom = top, bottom
	return m
end

local function PaintPreview()
	if not (preview and preview.icon) then return end
	local d = ns.DB()
	local o, m = preview.icon, preview.mock
	if d.visibility == "never" then o:Hide() return end
	-- the class blessing you have set for paladins, or Blessing of Might
	local b = 0
	pcall(function() local _, g = PP:GetSpellID(PP:GetClassID("PALADIN")); b = g or 0 end)
	if b == 0 then b = 2 end
	local tex = (PP.NormalBlessingIcons and PP.NormalBlessingIcons[b]) or nil
	local dur = 3600
	ns.PaintIcon(o, m, tex, true, "timed", GetTime() - (dur - 42 * 60), dur)
end
ns.RefreshPreview = PaintPreview

local function HeaderBuilder(hdr, width)
	if not preview then
		local frame = CreateFrame("Frame", nil, hdr)
		preview = {frame = frame}
		preview.mock = BuildMock(frame)
		preview.icon = ns.NewIcon(preview.mock)
		local path = STANDARD_TEXT_FONT
		if EUI.GetFontPath then path = EUI.GetFontPath("EllesmereUIUnitFrames") or path end
		local hint = frame:CreateFontString(nil, "OVERLAY")
		hint:SetFont(path, 11, "")
		hint:SetAlpha(0.45)
		hint:SetText("Preview: your blessing with 42 minutes left")
		preview.hint = hint
	end
	local m = preview.mock
	local above, below = m.extentTop or 0, m.extentBottom or 0
	local h = PREVIEW_PAD + above + m:GetHeight() + below + PREVIEW_PAD + 24
	preview.frame:SetParent(hdr)
	preview.frame:ClearAllPoints()
	preview.frame:SetAllPoints(hdr)
	preview.frame:Show()
	m:ClearAllPoints()
	m:SetPoint("TOP", preview.frame, "TOP", 0, -(PREVIEW_PAD + above))
	preview.hint:ClearAllPoints()
	preview.hint:SetPoint("BOTTOM", preview.frame, "BOTTOM", 0, 10)
	PaintPreview()
	return h
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------
local function Changed()
	ns.Refresh()
	ns.UpdateIcons()
	PaintPreview()
end

local function Get(key) return function() return ns.DB()[key] end end
local function Set(key) return function(v) ns.DB()[key] = v; Changed() end end
local function GetColor(key)
	return function() local c = ns.DB()[key]; return c.r, c.g, c.b, c.a or 1 end
end
local function SetColor(key)
	return function(r, g, b, a) ns.DB()[key] = {r = r, g = g, b = b, a = a or 1}; Changed() end
end
local function Off(key) return function() return not ns.DB()[key] end end

local function VisValues()
	local values, order = {}, {}
	local src = EUI.VIS_VALUES or {never = "Never", always = "Always", mouseover = "Mouseover",
		in_combat = "In Combat", out_of_combat = "Out of Combat", in_raid = "In Raid Group",
		in_party = "In Party", solo = "Solo"}
	for k, v in pairs(src) do values[k] = v end
	values.mouseover = "Mouseover (hovered frame)"
	for _, k in ipairs(EUI.VIS_ORDER or {"never", "always", "mouseover", "in_combat", "out_of_combat", "---", "in_raid", "in_party", "solo"}) do
		if k == "---" or values[k] then order[#order + 1] = k end
	end
	return values, order
end

local function BuildPage(_, parent, yOffset)
	local W = EUI.Widgets
	local y = yOffset
	local _, h
	local d = ns.DB

	-- EllesmereUI's pages draw their preview strip from inside the page build;
	-- getHeaderBuilder only brings it back when a cached page is shown again.
	local prebuild = EUI.IsSearchPrebuild and EUI.IsSearchPrebuild()
	if not prebuild and EUI.SetContentHeader then
		local ok, err = pcall(EUI.SetContentHeader, EUI, HeaderBuilder)
		if not ok then geterrorhandler()(err) end
	end

	local anchorLabels = {}
	for key, a in pairs(ns.ANCHORS) do anchorLabels[key] = a[1] end
	local visValues, visOrder = VisValues()
	-- Always Show on Hover does nothing for Never, or when Mouseover is picked
	local function hoverOnly()
		local db = d()
		if db.visibility == "never" then return true end
		if EUI.GetVisibilitySelection then
			local ok, sel = pcall(EUI.GetVisibilitySelection, db, "visibility")
			if ok and sel then return sel.never or sel.mouseover or false end
		end
		return db.visibility == "mouseover"
	end
	local function cdOff() return not (d().cdSwipe or d().cdText) end

	_, h = W:SectionHeader(parent, "UNIT FRAMES", y); y = y - h
	_, h = W:DualRow(parent, y,
		{type = "toggle", text = "Blessings on Unit Frames", getValue = Get("enabled"), setValue = Set("enabled"),
			tooltip = "Hover an EllesmereUI player, party or raid frame: the mouse wheel picks that player's blessing and middle-click casts it. Works in combat."},
		{type = "toggle", text = "Hide PallyPower Bar", getValue = Get("hideBar"), setValue = Set("hideBar"),
			disabled = Off("enabled"), disabledTooltip = "Blessings on Unit Frames is off.",
			tooltip = "Hides PallyPower's own buff bar. /ppe assign, /pp blessings or a left-click on the minimap icon still open the assignment window."}); y = y - h

	_, h = W:SectionHeader(parent, "VISIBILITY", y); y = y - h
	local hoverCfg = {type = "toggle", text = "Always Show on Hover", getValue = Get("hoverAlways"), setValue = Set("hoverAlways"),
		disabled = hoverOnly, disabledTooltip = "Only used with Always or conditions.",
		tooltip = "The frame under the mouse shows its icon even when the conditions don't apply."}
	if EUI.BuildVisibilityRow then
		-- EllesmereUI's own visibility checklist: Never / Always / Mouseover, Match All
		-- or Any, and a Show and a Hide lane for every condition.
		_, h = EUI.BuildVisibilityRow(W, parent, y, {
			getStore = ns.DB,
			legacyKey = "visibility",
			label = "Show Icon",
			tooltip = "Mouseover: only on the frame under the mouse. Otherwise the icon shows on every group frame while the conditions apply.",
			onChanged = Changed,
			onOptionChanged = Changed,
		}, hoverCfg); y = y - h
	else
		_, h = W:DualRow(parent, y,
			{type = "dropdown", text = "Show Icon", values = visValues, order = visOrder,
				getValue = Get("visibility"), setValue = Set("visibility"),
				tooltip = "Mouseover: only on the frame under the mouse. Any other choice shows the icon on every group frame while it applies."},
			hoverCfg); y = y - h
	end

	_, h = W:SectionHeader(parent, "POSITION", y); y = y - h
	_, h = W:DualRow(parent, y,
		{type = "dropdown", text = "Position", values = anchorLabels, order = ns.ANCHOR_ORDER,
			getValue = Get("anchor"), setValue = Set("anchor"),
			tooltip = "Portrait covers the frame's portrait (player-style frames). Frames without one get it at their left edge."},
		{type = "slider", text = "Icon Size", min = 0, max = 64, step = 1, getValue = Get("size"), setValue = Set("size"),
			tooltip = "0 fits the frame, or the portrait."}); y = y - h
	_, h = W:DualRow(parent, y,
		{type = "slider", text = "X Offset", min = -80, max = 80, step = 1, getValue = Get("x"), setValue = Set("x")},
		{type = "slider", text = "Y Offset", min = -80, max = 80, step = 1, getValue = Get("y"), setValue = Set("y")}); y = y - h

	_, h = W:SectionHeader(parent, "STYLE", y); y = y - h
	_, h = W:DualRow(parent, y,
		{type = "slider", text = "Border Size", min = 0, max = 4, step = 1, getValue = Get("borderSize"), setValue = Set("borderSize")},
		{type = "colorpicker", text = "Border Color", hasAlpha = true, getValue = GetColor("borderColor"), setValue = SetColor("borderColor"),
			disabled = function() return (d().borderSize or 0) == 0 end}); y = y - h
	_, h = W:DualRow(parent, y,
		{type = "toggle", text = "Highlight Missing Blessing", getValue = Get("showMissing"), setValue = Set("showMissing"),
			disabled = function() return (d().borderSize or 0) == 0 end, disabledTooltip = "Needs a border.",
			tooltip = "Colors the border when the player doesn't have your blessing."},
		{type = "colorpicker", text = "Missing Color", hasAlpha = true, getValue = GetColor("missingColor"), setValue = SetColor("missingColor"),
			disabled = function() return not d().showMissing or (d().borderSize or 0) == 0 end}); y = y - h

	_, h = W:SectionHeader(parent, "COOLDOWN", y); y = y - h
	_, h = W:DualRow(parent, y,
		{type = "toggle", text = "Show Swipe", getValue = Get("cdSwipe"), setValue = Set("cdSwipe"),
			tooltip = "Darkens the icon as your blessing on that player runs down."},
		{type = "slider", text = "Swipe Opacity", min = 0, max = 100, step = 5,
			getValue = function() return math.floor((d().cdSwipeAlpha or 0.7) * 100 + 0.5) end,
			setValue = function(v) d().cdSwipeAlpha = v / 100; Changed() end,
			disabled = Off("cdSwipe")}); y = y - h
	_, h = W:DualRow(parent, y,
		{type = "toggle", text = "Reverse Swipe", getValue = Get("cdReverse"), setValue = Set("cdReverse"),
			disabled = Off("cdSwipe")},
		{type = "toggle", text = "Show Timer Text", getValue = Get("cdText"), setValue = Set("cdText")}); y = y - h
	_, h = W:DualRow(parent, y,
		{type = "slider", text = "Timer Under (min)", min = 0, max = 60, step = 1, getValue = Get("cdThreshold"), setValue = Set("cdThreshold"),
			disabled = Off("cdText"), tooltip = "Only show the timer text once the blessing has less than this many minutes left. 0 always shows it."},
		{type = "slider", text = "Text Size", min = 6, max = 24, step = 1, getValue = Get("cdTextSize"), setValue = Set("cdTextSize"),
			disabled = Off("cdText")}); y = y - h
	_, h = W:DualRow(parent, y,
		{type = "dropdown", text = "Text Position", values = ns.TEXT_POINTS, order = ns.TEXT_POINT_ORDER,
			getValue = Get("cdTextPos"), setValue = Set("cdTextPos"), disabled = Off("cdText")},
		{type = "colorpicker", text = "Text Color", hasAlpha = true, getValue = GetColor("cdTextColor"), setValue = SetColor("cdTextColor"),
			disabled = Off("cdText")}); y = y - h
	_, h = W:DualRow(parent, y,
		{type = "slider", text = "Text X Offset", min = -30, max = 30, step = 1, getValue = Get("cdTextX"), setValue = Set("cdTextX"),
			disabled = Off("cdText")},
		{type = "slider", text = "Text Y Offset", min = -30, max = 30, step = 1, getValue = Get("cdTextY"), setValue = Set("cdTextY"),
			disabled = Off("cdText")}); y = y - h

	_, h = W:SectionHeader(parent, "ASSIGNMENTS", y); y = y - h
	_, h = W:WideButton(parent, "Open PallyPower Blessing Assignments", y, OpenAssignments); y = y - h

	return math.abs(y)
end

if EUI and EUI.RegisterPlugin then
	EUI.RegisterPlugin(PLUGIN_ID, {
		label = "PallyPower",
		modules = {
			{
				key = "Blessings",
				title = "Blessings",
				description = "Pick and cast PallyPower blessings from EllesmereUI unit frames.",
				pages = {"Settings"},
				buildPage = BuildPage,
				getHeaderBuilder = function() return HeaderBuilder end,
				onPageCacheRestore = function() PaintPreview() end,
				onReset = function()
					ns.ResetDB()
					Changed()
					if EUI.RefreshPage then EUI:RefreshPage(true) end
				end,
			},
		},
	})
end

-------------------------------------------------------------------------------
--  /ppe            open the settings
--  /ppe assign     open PallyPower's blessing assignment window
-------------------------------------------------------------------------------
SLASH_PALLYPOWEREUI1 = "/ppe"
SlashCmdList.PALLYPOWEREUI = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "assign" or msg == "blessings" then
		OpenAssignments()
		return
	end
	if InCombatLockdown() then
		print("|cff00ccffPallyPower EUI:|r settings can't open in combat.")
		return
	end
	if not (EUI and EUI.OpenPlugin and EUI.OpenPlugin(PLUGIN_ID)) then
		print("|cff00ccffPallyPower EUI:|r couldn't open the EllesmereUI settings panel.")
	end
end
