-------------------------------------------------------------------------------
--  PallyPower Integration  (WoW Forever)
--
--  Hover an EllesmereUI player, party or raid frame and:
--    mouse wheel   picks the blessing for that player (your PallyPower
--                  individual assignment, synced to the other paladins)
--    middle-click  casts the picked blessing on them
--  An icon on the frame shows the pick and how long your blessing has left.
--  Works in combat: the choices for every group member are prepared out of
--  combat, and the wheel steps through them in secure code. Optionally hides
--  PallyPower's own bar.
--
--  Uses only PallyPower's public methods and saved assignment table, and finds
--  EllesmereUI's frames through their group headers and the standard
--  ClickCastFrames table. Nothing in either addon is changed; PallyPower's
--  UpdateLayout/UpdateRoster get a post-hook so we know when to rebuild.
-------------------------------------------------------------------------------
local ADDON, ns = ...
local PP = PallyPower
if not (PP and PP.isForever) then return end

local CreateFrame, InCombatLockdown, IsInRaid, IsInGroup = CreateFrame, InCombatLockdown, IsInRaid, IsInGroup
local GetTime, C_AddOns, C_Timer = GetTime, C_AddOns, C_Timer
local issecret = _G.issecretvalue or function() return false end

local WHEEL_BUTTON = "PallyPowerEUIWheel"
local NONE_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local SWIPE = "Interface\\AddOns\\EllesmereUI\\media\\white-square.png"

-------------------------------------------------------------------------------
--  Settings
-------------------------------------------------------------------------------
ns.DEFAULTS = {
	enabled      = true,          -- hover, wheel and middle-click on EUI frames
	hideBar      = true,          -- hide PallyPower's own buff bar
	-- visibility (EllesmereUI's visibility modes)
	visibility   = "mouseover",   -- mouseover = only the frame under the mouse
	hoverAlways  = true,          -- with a condition: the hovered frame shows its icon anyway
	-- position
	anchor       = "RIGHT",       -- key into ns.ANCHORS
	x            = -3,
	y            = 0,
	size         = 0,             -- 0 = fit the frame (or the portrait)
	-- style
	borderSize   = 1,
	borderColor  = {r = 0, g = 0, b = 0, a = 1},
	showMissing  = true,          -- border turns this color when the player lacks your blessing
	missingColor = {r = 0.9, g = 0.15, b = 0.15, a = 1},
	-- cooldown (your blessing's remaining time on that player)
	cdSwipe      = true,
	cdSwipeAlpha = 0.7,
	cdReverse    = false,
	cdText       = true,
	cdThreshold  = 0,             -- minutes; timer text only below this (0 = always)
	cdTextSize   = 10,
	cdTextColor  = {r = 1, g = 1, b = 1, a = 1},
	cdTextPos    = "CENTER",
	cdTextX      = 0,
	cdTextY      = 0,
}

-- key -> { label, icon point, frame point }
ns.ANCHORS = {
	PORTRAIT    = {"Portrait",            "CENTER",      "CENTER"},
	LEFT        = {"Inside left",         "LEFT",        "LEFT"},
	RIGHT       = {"Inside right",        "RIGHT",       "RIGHT"},
	CENTER      = {"Center",              "CENTER",      "CENTER"},
	TOP         = {"Inside top",          "TOP",         "TOP"},
	BOTTOM      = {"Inside bottom",       "BOTTOM",      "BOTTOM"},
	TOPLEFT     = {"Inside top left",     "TOPLEFT",     "TOPLEFT"},
	TOPRIGHT    = {"Inside top right",    "TOPRIGHT",    "TOPRIGHT"},
	BOTTOMLEFT  = {"Inside bottom left",  "BOTTOMLEFT",  "BOTTOMLEFT"},
	BOTTOMRIGHT = {"Inside bottom right", "BOTTOMRIGHT", "BOTTOMRIGHT"},
	OUT_LEFT    = {"Outside left",        "RIGHT",       "LEFT"},
	OUT_RIGHT   = {"Outside right",       "LEFT",        "RIGHT"},
	OUT_TOP     = {"Above",               "BOTTOM",      "TOP"},
	OUT_BOTTOM  = {"Below",               "TOP",         "BOTTOM"},
}
ns.ANCHOR_ORDER = {
	"PORTRAIT", "---", "RIGHT", "LEFT", "CENTER", "TOP", "BOTTOM",
	"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT",
	"---", "OUT_RIGHT", "OUT_LEFT", "OUT_TOP", "OUT_BOTTOM",
}

ns.TEXT_POINTS = {
	CENTER = "Center", TOP = "Top", BOTTOM = "Bottom", LEFT = "Left", RIGHT = "Right",
	TOPLEFT = "Top left", TOPRIGHT = "Top right", BOTTOMLEFT = "Bottom left", BOTTOMRIGHT = "Bottom right",
}
ns.TEXT_POINT_ORDER = {"CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}

local function CopyDefault(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = x end
	return t
end
ns.CopyDefault = CopyDefault

local db
function ns.DB()
	if not db then
		PallyPowerEUIDB = type(PallyPowerEUIDB) == "table" and PallyPowerEUIDB or {}
		db = PallyPowerEUIDB
		-- 1.0: "showIcon = false" became the "never" visibility
		if db.showIcon == false and db.visibility == nil then db.visibility = "never" end
		db.showIcon = nil
		for k, v in pairs(ns.DEFAULTS) do
			if db[k] == nil or type(db[k]) ~= type(v) then db[k] = CopyDefault(v) end
		end
		if not ns.ANCHORS[db.anchor] then db.anchor = ns.DEFAULTS.anchor end
		if not ns.TEXT_POINTS[db.cdTextPos] then db.cdTextPos = ns.DEFAULTS.cdTextPos end
	end
	return db
end

function ns.ResetDB()
	local d = ns.DB()
	for k in pairs(d) do d[k] = nil end
	for k, v in pairs(ns.DEFAULTS) do d[k] = CopyDefault(v) end
end

local header, wheel
local wrapped = {}      -- unit frame -> true once our secure scripts are on it
local icons = {}        -- unit frame -> our icon frame (a child of it)
ns.icons = icons
local cache = {}        -- unit token -> { name, classID, list = { {b, spell, icon, track} }, k }
local applied = {}      -- unit token -> number of entries written to the header
local refreshing = false
local dirty = false
local hoverFrame

-------------------------------------------------------------------------------
--  PallyPower access (public methods and its saved assignment table only)
-------------------------------------------------------------------------------
local function EUIFramesLoaded()
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
	return loaded and (loaded("EllesmereUIRaidFrames") or loaded("EllesmereUIUnitFrames")) or false
end

-- A paladin PallyPower is enabled for and has already scanned (CanBuff errors until then).
local function PallyReady()
	if UnitClassBase("player") ~= "PALADIN" then return false end
	if not (PP.opt and PP.opt.enabled and PP.player) then return false end
	return (pcall(PP.CanBuff, PP, PP.player, 1))
end

local function Active()
	return ns.DB().enabled and EUIFramesLoaded() and PallyReady()
end

local function UnitInfo(unit)
	if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
	local name = GetUnitName(unit, true)
	local classID = PP:GetClassID((UnitClassBase(unit)))
	if not name or not classID or classID < 1 then return end
	return name, classID
end

local function Assigned(name, classID)
	local mine = PallyPower_NormalAssignments and PallyPower_NormalAssignments[PP.player]
	return (mine and mine[classID] and mine[classID][name]) or 0
end

-- Same as PallyPower's own (file-local) SetNormalBlessings: write the assignment,
-- then after 2 quiet seconds send it to the other paladins and redraw. A table
-- write plus a timer, so safe in combat.
local sendTimers = {}
local function Assign(name, classID, blessing)
	local me = PP.player
	PallyPower_NormalAssignments[me] = PallyPower_NormalAssignments[me] or {}
	PallyPower_NormalAssignments[me][classID] = PallyPower_NormalAssignments[me][classID] or {}
	PallyPower_NormalAssignments[me][classID][name] = (blessing ~= 0) and blessing or nil
	local key = classID .. ":" .. name
	if sendTimers[key] then sendTimers[key]:Cancel() end
	sendTimers[key] = C_Timer.NewTimer(2, function()
		sendTimers[key] = nil
		local t = PallyPower_NormalAssignments[me]
		if t and t[classID] and t[classID][name] then
			PP:SendNormalBlessings(me, classID, name)
		end
		PP:UpdateLayout()
	end)
end

-- Your blessing number b on the unit (either the normal or the greater version).
-- Returns "timed", start, duration | "present" | "missing" | nil (can't tell).
-- PallyPower:FindBuff already copes with auras the client hides in combat.
local wantedCache = {}
local function BlessingState(unit, b)
	if not b or b == 0 or type(PP.FindBuff) ~= "function" then return end
	local wanted = wantedCache[b]
	if not wanted then
		wanted = {}
		if PP.Spells and PP.Spells[b] then wanted[PP.Spells[b]] = true end
		if PP.GSpells and PP.GSpells[b] then wanted[PP.GSpells[b]] = true end
		wantedCache[b] = wanted
	end
	if not next(wanted) then return end
	local ok, name, remaining, duration = pcall(PP.FindBuff, PP, unit, wanted)
	if not ok or issecret(name) then return end
	if not name then
		if UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then return end
		return "missing"
	end
	if issecret(remaining) or issecret(duration) then return "present" end
	if not remaining or remaining <= 0 or not duration or duration <= 0 then return "present" end
	return "timed", GetTime() - (duration - remaining), duration
end

-------------------------------------------------------------------------------
--  Secure snippets
--  All run in the header's restricted environment, so pp_hover is shared.
--  Header attributes, per unit token u:
--    n:u        number of choices      k:u    current choice (1..n)
--    s:u:k      spell to cast for choice k
-------------------------------------------------------------------------------
local ENTER = [[
	local u = self:GetAttribute("unit")
	local n = u and control:GetAttribute("pp-on") and control:GetAttribute("n:" .. u)
	if not n then
		-- not one of ours (pet, target, disabled): drop a middle-click we set earlier
		if self:GetAttribute("pp-owned") then
			self:SetAttribute("type3", nil)
			self:SetAttribute("spell3", nil)
			self:SetAttribute("pp-owned", nil)
		end
		return
	end
	pp_hover = self
	local k = control:GetAttribute("k:" .. u) or 1
	self:SetAttribute("pp-owned", true)
	self:SetAttribute("type3", "spell")
	self:SetAttribute("spell3", control:GetAttribute("s:" .. u .. ":" .. k))
	control:SetBindingClick(true, "MOUSEWHEELUP", "]] .. WHEEL_BUTTON .. [[", "Up")
	control:SetBindingClick(true, "MOUSEWHEELDOWN", "]] .. WHEEL_BUTTON .. [[", "Down")
]]

local LEAVE = [[
	if pp_hover == self then pp_hover = nil end
	control:ClearBindings()
]]

-- Wheel up goes to the previous blessing, as on PallyPower's own player buttons.
local WHEEL = [[
	if down == false then return false end
	local f = pp_hover
	if not f or not f:IsUnderMouse(true) then
		pp_hover = nil
		control:ClearBindings()
		return false
	end
	local u = f:GetAttribute("unit")
	local n = u and control:GetAttribute("n:" .. u)
	if not n or n < 1 then return false end
	local k = control:GetAttribute("k:" .. u) or 1
	if button == "Up" then k = k - 1 else k = k + 1 end
	if k < 1 then k = n elseif k > n then k = 1 end
	control:SetAttribute("k:" .. u, k)
	f:SetAttribute("spell3", control:GetAttribute("s:" .. u .. ":" .. k))
	return false
]]

-------------------------------------------------------------------------------
--  The blessing icon (also used by the settings preview)
-------------------------------------------------------------------------------
function ns.NewIcon(parent)
	local o = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	o:EnableMouse(false)
	o.icon = o:CreateTexture(nil, "ARTWORK")
	o.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	o.cd = CreateFrame("Cooldown", nil, o, "CooldownFrameTemplate")
	o.cd:SetAllPoints(o.icon)
	o.cd:SetDrawEdge(false)
	o.cd:SetDrawBling(false)
	pcall(o.cd.SetSwipeTexture, o.cd, SWIPE)
	o:Hide()
	return o
end

-- The portrait EllesmereUI shows on a unit frame (player/target style frames), if any.
local function PortraitRegion(f)
	local p = f.Portrait
	local r = type(p) == "table" and (p.backdrop or p)
	if type(r) == "table" and r.IsShown and r:IsShown() then
		local w, h = r:GetSize()
		if w and h and w > 0 and h > 0 then return r end
	end
end

local function FontFor()
	local EUI = EllesmereUI
	local path = EUI and EUI.GetFontPath and EUI.GetFontPath("EllesmereUIUnitFrames")
	local flags = EUI and EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag("EllesmereUIUnitFrames")
	return path or STANDARD_TEXT_FONT, flags or "OUTLINE"
end

-- Paints icon o on unit frame f.
--   texture, usable : the picked blessing's icon and whether you can cast it
--   state, start, duration : from BlessingState
-- Returns the time the timer text needs a repaint (threshold), or nil.
function ns.PaintIcon(o, f, texture, usable, state, start, duration)
	local d = ns.DB()

	-- border and icon
	local bs = d.borderSize or 0
	if o._bs ~= bs then
		o:SetBackdrop(bs > 0 and {bgFile = WHITE, edgeFile = WHITE, edgeSize = bs} or {bgFile = WHITE})
		o._bs = bs
	end
	o:SetBackdropColor(0, 0, 0, 0.6)
	if bs > 0 then
		local c = (state == "missing" and d.showMissing) and d.missingColor or d.borderColor
		o:SetBackdropBorderColor(c.r, c.g, c.b, c.a or 1)
	end
	o.icon:ClearAllPoints()
	o.icon:SetPoint("TOPLEFT", bs, -bs)
	o.icon:SetPoint("BOTTOMRIGHT", -bs, bs)
	o.icon:SetTexture(texture or NONE_ICON)
	o.icon:SetDesaturated(not usable)

	-- position and size
	local a = ns.ANCHORS[d.anchor] or ns.ANCHORS.RIGHT
	local target, p1, p2 = f, a[2], a[3]
	local auto
	if d.anchor == "PORTRAIT" then
		local pr = PortraitRegion(f)
		if pr then
			target = pr
			local w, h = pr:GetSize()
			auto = math.min(w, h)
		else
			-- no portrait on this frame (party/raid): a square at the frame's left edge
			p1, p2 = "LEFT", "LEFT"
			auto = f:GetHeight()
		end
	end
	local size = d.size or 0
	if size <= 0 then
		size = auto or math.max(14, math.min(24, (f:GetHeight() or 20) - 6))
	end
	o:ClearAllPoints()
	o:SetPoint(p1, target, p2, d.x or 0, d.y or 0)
	o:SetSize(size, size)
	o:SetFrameLevel(math.max(f:GetFrameLevel(), target:GetFrameLevel()) + 20)

	-- cooldown: your blessing's time left on that player
	local cd, wake = o.cd, nil
	if state == "timed" and (d.cdSwipe or d.cdText) then
		cd:SetDrawSwipe(d.cdSwipe and true or false)
		cd:SetSwipeColor(0, 0, 0, d.cdSwipeAlpha or 0.7)
		cd:SetReverse(d.cdReverse and true or false)
		cd:SetCooldown(start, duration)
		local hideText = not d.cdText
		local thr = (d.cdThreshold or 0) * 60
		if d.cdText and thr > 0 then
			local remain = start + duration - GetTime()
			if remain > thr then
				hideText = true
				wake = GetTime() + (remain - thr) + 0.05
			end
		end
		cd:SetHideCountdownNumbers(hideText)
		local fs = cd.GetCountdownFontString and cd:GetCountdownFontString()
		if fs then
			local path, flags = FontFor()
			fs:SetFont(path, d.cdTextSize or 10, flags)
			if flags == "" then fs:SetShadowOffset(1, -1) else fs:SetShadowOffset(0, 0) end
			local c = d.cdTextColor
			fs:SetTextColor(c.r, c.g, c.b, c.a or 1)
			fs:ClearAllPoints()
			fs:SetPoint(d.cdTextPos or "CENTER", o, d.cdTextPos or "CENTER", d.cdTextX or 0, d.cdTextY or 0)
		end
		cd:Show()
	else
		cd:Clear()
		cd:Hide()
	end

	o:Show()
	return wake
end

-------------------------------------------------------------------------------
--  Which frames show their icon
-------------------------------------------------------------------------------
-- EllesmereUI's visibility checklist (Never / Always / Mouseover, match all or any,
-- Show and Hide lanes per condition), evaluated the way EUI's own modules do it.
-- Returns true (show), false (hide) or "mouseover" (show on the hovered frame only).
local function Verdict(d)
	local EUI = EllesmereUI
	local state = {
		inCombat = InCombatLockdown() or UnitAffectingCombat("player") or false,
		inRaid = IsInRaid(),
		inParty = IsInGroup() and not IsInRaid(),
	}
	local ok, r = pcall(function()
		if EUI.EvalVisibilityExtended then
			if d.visibilityMatch ~= "any" and EUI.CheckVisibilityOptions
				and EUI.CheckVisibilityOptions(d) then return false end
			local r = EUI.EvalVisibilityExtended(d, "visibility", state, EUI.VIS_CAPS_DEFAULT)
			if r ~= nil then return r end
		end
		local mode = d.visibility or "always"
		if mode == "mouseover" then return "mouseover" end
		return EUI.CheckVisibilityMode(mode, state) and true or false
	end)
	if ok then return r end
	return d.visibility == "never" and false or "mouseover"
end
ns.Verdict = Verdict

local function ShouldShow(f, verdict)
	local d = ns.DB()
	if d.visibility == "never" then return false end
	if f == hoverFrame and (verdict == "mouseover" or d.hoverAlways) then return true end
	return verdict == true and f:IsVisible()
end

local wakeTimer, wakeAt
local UpdateIcons

local function ScheduleWake(at)
	if not at then return end
	if wakeAt and wakeAt <= at then return end
	if wakeTimer then wakeTimer:Cancel() end
	wakeAt = at
	wakeTimer = C_Timer.NewTimer(math.max(0.05, at - GetTime()), function()
		wakeTimer, wakeAt = nil, nil
		UpdateIcons()
	end)
end

local function UpdateIcon(f, condition)
	local o = icons[f]
	if not o then return end
	local u = Active() and f:GetAttribute("unit")
	local c = u and cache[u]
	local k = c and header:GetAttribute("k:" .. u)
	local e = c and k and c.list[k]
	if not e or not ShouldShow(f, condition) then
		o:Hide()
		return
	end
	local state, start, duration = BlessingState(u, e.track)
	ScheduleWake(ns.PaintIcon(o, f, e.icon, e.spell ~= nil, state, start, duration))
end

function UpdateIcons()
	local verdict = Verdict(ns.DB())
	for f in pairs(icons) do UpdateIcon(f, verdict) end
end
ns.UpdateIcons = UpdateIcons

local function OnFrameEnter(f)
	hoverFrame = f
	UpdateIcon(f, Verdict(ns.DB()))
end

local function OnFrameLeave(f)
	if hoverFrame == f then hoverFrame = nil end
	UpdateIcon(f, Verdict(ns.DB()))
end

-------------------------------------------------------------------------------
--  Building each unit's choices (out of combat only)
-------------------------------------------------------------------------------
local function UnitTokens()
	-- "player" always: the EUI player frame lets you bless yourself solo, in party and in raid
	local t = {"player"}
	if IsInRaid() then
		for i = 1, MAX_RAID_MEMBERS do t[#t + 1] = "raid" .. i end
	else
		for i = 1, MAX_PARTY_MEMBERS do t[#t + 1] = "party" .. i end
	end
	return t
end

-- The cycle PallyPower's own player buttons use: 0 (the class blessing) then every
-- blessing this paladin knows and the player still needs. The current pick always stays in.
local function BuildChoices(unit)
	local name, classID = UnitInfo(unit)
	if not name then return end
	local current = Assigned(name, classID)
	local list, k = {}, 1

	local _, classBlessing = PP:GetSpellID(classID)
	local classSpell = classBlessing > 0 and PP:CanBuffBlessing(classBlessing, 0, unit) or nil
	list[1] = {
		b = 0, spell = classSpell, track = classBlessing,
		icon = classBlessing > 0 and PP.BlessingIcons[classBlessing] or nil,
	}

	local isSelf = (name == PP.player)
	local last = isSelf and 6 or 7 -- no Blessing of Sacrifice on yourself
	for i = 1, last do
		if i == current or (PP:CanBuff(PP.player, i) and PP:NeedsBuff(classID, i, name)) then
			local spell = PP:CanBuffBlessing(i, 0, unit)
			if spell or i == current then
				list[#list + 1] = {b = i, spell = spell, track = i, icon = PP.NormalBlessingIcons[i]}
				if i == current then k = #list end
			end
		end
	end
	return {name = name, classID = classID, list = list, k = k}
end

local function ClearUnit(u)
	local n = applied[u]
	if not n then return end
	header:SetAttribute("n:" .. u, nil)
	header:SetAttribute("k:" .. u, nil)
	for k = 1, n do header:SetAttribute("s:" .. u .. ":" .. k, nil) end
	applied[u] = nil
end

-------------------------------------------------------------------------------
--  Finding the EllesmereUI unit frames
-------------------------------------------------------------------------------
local HEADERS = {"ERFPartyHeader", "ERFFlatHeader"}
for g = 1, 8 do HEADERS[#HEADERS + 1] = "ERFGroupHeader" .. g end

local function Wrap(f)
	if wrapped[f] or not f or not f.IsProtected or not f:IsProtected() then return end
	if not f.RegisterForClicks or f:IsForbidden() then return end
	header:WrapScript(f, "OnEnter", ENTER)
	header:WrapScript(f, "OnLeave", LEAVE)
	f:HookScript("OnEnter", OnFrameEnter)
	f:HookScript("OnLeave", OnFrameLeave)
	icons[f] = ns.NewIcon(f)
	wrapped[f] = true
end

local function ScanFrames()
	-- EUI's own player frame, by name too, in case another addon owns ClickCastFrames
	Wrap(_G.EllesmereUIUnitFrames_Player)
	for _, hname in ipairs(HEADERS) do
		local h = _G[hname]
		if h and h.GetChildren then
			for _, child in ipairs({h:GetChildren()}) do
				Wrap(child)
			end
		end
	end
	-- EUI lists its frames here while its own click-casting is off. A metatable
	-- means another click-cast addon owns the table: leave it to them.
	if type(ClickCastFrames) == "table" and not getmetatable(ClickCastFrames) then
		for f, on in pairs(ClickCastFrames) do
			if on and type(f) == "table" then Wrap(f) end
		end
	end
end

-------------------------------------------------------------------------------
--  Refresh
-------------------------------------------------------------------------------
local function SetBarHidden()
	local bar = _G.PallyPowerFrame
	if not bar or InCombatLockdown() then return end
	local d = ns.DB()
	bar:SetShown(not (d.enabled and d.hideBar))
end

local function Refresh()
	if not header then return end
	if InCombatLockdown() then dirty = true UpdateIcons() return end
	dirty = false
	refreshing = true

	local on = Active()
	header:SetAttribute("pp-on", on or nil)
	if on then
		ScanFrames()
		local seen = {}
		for _, u in ipairs(UnitTokens()) do
			local c = BuildChoices(u)
			if c then
				seen[u] = true
				local old = applied[u]
				header:SetAttribute("n:" .. u, #c.list)
				header:SetAttribute("k:" .. u, c.k)
				for k, e in ipairs(c.list) do
					header:SetAttribute("s:" .. u .. ":" .. k, e.spell)
				end
				for k = #c.list + 1, old or 0 do
					header:SetAttribute("s:" .. u .. ":" .. k, nil)
				end
				applied[u] = #c.list
				cache[u] = c
			end
		end
		for u in pairs(applied) do
			if not seen[u] then ClearUnit(u) cache[u] = nil end
		end
	else
		for u in pairs(applied) do ClearUnit(u) end
		wipe(cache)
		ClearOverrideBindings(header)
	end

	-- Middle-click: set up on the frame being hovered right now; the enter
	-- snippet does it for every other frame. Turned off cleanly when disabled.
	for f in pairs(wrapped) do
		local u = f:GetAttribute("unit")
		local c = on and u and cache[u]
		if c then
			if f == hoverFrame then
				f:SetAttribute("pp-owned", true)
				f:SetAttribute("type3", "spell")
				f:SetAttribute("spell3", c.list[c.k] and c.list[c.k].spell)
			end
		elseif f:GetAttribute("pp-owned") then
			f:SetAttribute("type3", nil)
			f:SetAttribute("spell3", nil)
			f:SetAttribute("pp-owned", nil)
		end
	end

	refreshing = false
	SetBarHidden()
	UpdateIcons()
end

local queued = false
local function QueueRefresh()
	if queued then return end
	queued = true
	C_Timer.After(0.2, function()
		queued = false
		Refresh()
	end)
end
ns.Refresh = QueueRefresh

local iconsQueued = false
local function QueueIcons()
	if iconsQueued then return end
	iconsQueued = true
	C_Timer.After(0.15, function()
		iconsQueued = false
		UpdateIcons()
	end)
end

-------------------------------------------------------------------------------
--  A wheel step changed a unit's pick: make it the PallyPower assignment.
-------------------------------------------------------------------------------
local function OnHeaderAttribute(_, name, value)
	if refreshing or type(name) ~= "string" then return end
	local u = name:match("^k:(.+)$")
	local c = u and cache[u]
	local e = c and value and c.list[value]
	if not e then return end
	c.k = value
	Assign(c.name, c.classID, e.b)
	UpdateIcons()
	-- You can show up twice (player frame + your party/raid frame): rebuild so both agree.
	-- In combat the other frame catches up when combat ends.
	if not InCombatLockdown() then QueueRefresh() end
end

-------------------------------------------------------------------------------
--  Setup
-------------------------------------------------------------------------------
local function Setup()
	if header then return end
	ns.DB()
	-- PallyPower failed to load properly (its error is already reported): stay out of the way
	if type(PP.UpdateLayout) ~= "function" or type(PP.CanBuff) ~= "function" then return end

	header = CreateFrame("Frame", "PallyPowerEUIHeader", UIParent, "SecureHandlerBaseTemplate")
	header:HookScript("OnAttributeChanged", OnHeaderAttribute)

	wheel = CreateFrame("Button", WHEEL_BUTTON, UIParent, "SecureActionButtonTemplate")
	wheel:RegisterForClicks("AnyDown", "AnyUp")
	header:WrapScript(wheel, "OnClick", WHEEL)

	-- PallyPower rebuilds its layout whenever the roster, spells or assignments change.
	hooksecurefunc(PP, "UpdateLayout", QueueRefresh)
	hooksecurefunc(PP, "UpdateRoster", QueueRefresh)

	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_REGEN_ENABLED")
	ev:RegisterEvent("PLAYER_REGEN_DISABLED")
	ev:RegisterEvent("GROUP_ROSTER_UPDATE")
	ev:RegisterEvent("PLAYER_ENTERING_WORLD")
	ev:RegisterEvent("SPELLS_CHANGED")
	ev:RegisterEvent("UNIT_AURA")
	ev:SetScript("OnEvent", function(_, event, unit)
		if event == "UNIT_AURA" then
			if unit and cache[unit] then QueueIcons() end
		elseif event == "PLAYER_REGEN_ENABLED" then
			if dirty then Refresh() else UpdateIcons() end
		elseif event == "PLAYER_REGEN_DISABLED" then
			UpdateIcons()
		else
			QueueRefresh()
		end
	end)
	-- target, zone, mount, resting and Party Mode edges for the visibility conditions
	if EllesmereUI.RegisterVisibilityUpdater then
		EllesmereUI.RegisterVisibilityUpdater(QueueIcons)
	end
	QueueRefresh()
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	Setup()
end)
