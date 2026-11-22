-------------------------------------------------------------------------------
--  Settings page in DaylightUI's options window (a DaylightUI plugin), for
--  players without EllesmereUI. The rows read and write the same saved table
--  as the EllesmereUI page (PallyPowerEUIDB), so both always agree. With
--  EllesmereUI loaded its page and visibility checklist are used instead.
-------------------------------------------------------------------------------
local ADDON, ns = ...
if not ns.DB then return end -- Core.lua stopped early (not WoW Forever)
if ns.HasEUI() then return end

local DUI = _G.DaylightUI
local API = ns.DUIAPI()
if not (API and type(DUI.RegisterPlugin) == "function" and type(DUI.RegisterModule) == "function") then return end

local PAGE = ADDON .. ".main" -- the page id DaylightUI gives our module's "main" page

local plugin = DUI:RegisterPlugin(ADDON, {
	needs = {1, 0},
	title = "PallyPower Integration",
	color = "F48CBA", -- paladin pink
	short = "PallyPower",
	blurb = "Pick and cast PallyPower blessings from DaylightUI's unit frames.",
})
if not plugin or plugin.off then return end

-------------------------------------------------------------------------------
--  Rows (get/set straight into our own saved table)
-------------------------------------------------------------------------------
local function Changed()
	ns.Refresh()
	ns.UpdateIcons()
end

local function D() return ns.DB() end
local function Value(key)
	return function() return D()[key] end,
		function(v) D()[key] = v; Changed() end,
		function() return ns.CopyDefault(ns.DEFAULTS[key]) end
end
local function Color(key)
	return function() local c = D()[key]; return {c.r, c.g, c.b, c.a or 1} end,
		function(v) D()[key] = {r = v[1], g = v[2], b = v[3], a = v[4] or 1}; Changed() end,
		function() local c = ns.DEFAULTS[key]; return {c.r, c.g, c.b, c.a or 1} end
end

local function Toggle(key, label, desc, disabled)
	local get, set, default = Value(key)
	return {type = "toggle", label = label, desc = desc, get = get, set = set, default = default, disabled = disabled}
end
local function Slider(key, label, min, max, step, unit, desc, disabled)
	local get, set, default = Value(key)
	return {type = "slider", label = label, min = min, max = max, step = step, unit = unit, desc = desc,
		get = get, set = set, default = default, disabled = disabled}
end
local function NoSeparators(order)
	local out = {}
	for _, k in ipairs(order) do if k ~= "---" then out[#out + 1] = k end end
	return out
end
local function Dropdown(key, label, values, order, desc, disabled)
	local get, set, default = Value(key)
	return {type = "dropdown", label = label, values = values, order = NoSeparators(order), desc = desc,
		get = get, set = set, default = default, disabled = disabled}
end
local function ColorRow(key, label, disabled)
	local get, set, default = Color(key)
	return {type = "color", label = label, alpha = true, get = get, set = set, default = default, disabled = disabled}
end

local function Off(key) return function() return not D()[key] end end
local function NoBorder() return (D().borderSize or 0) == 0 end
local function hoverOnly() local v = D().visibility; return v == "never" or v == "mouseover" end

local anchorLabels = {}
for key, a in pairs(ns.ANCHORS) do anchorLabels[key] = a[1] end

local swipeGet = function() return math.floor((D().cdSwipeAlpha or 0.7) * 100 + 0.5) end
local swipeSet = function(v) D().cdSwipeAlpha = v / 100; Changed() end

local options = {pages = {{
	id = "main", label = "Blessings",
	desc = "Hover a DaylightUI player, party or raid frame: the mouse wheel picks that player's PallyPower blessing and the cast click casts it. Works in combat.",
	groups = {
		{label = "Unit Frames", items = {
			Toggle("enabled", "Blessings on unit frames",
				"Hover a player, party or raid frame: the mouse wheel picks that player's blessing and the cast click casts it."),
			Toggle("hideBar", "Hide the PallyPower bar",
				"Hides PallyPower's own buff bar. /ppe assign, /pp blessings or a left-click on the minimap icon still open the assignment window.",
				Off("enabled")),
		}},
		{label = "Bindings", items = {
			Dropdown("castButton", "Cast with", ns.CAST_BUTTONS, ns.CAST_BUTTON_ORDER,
				"The click on a hovered frame that casts its blessing. Plain left and right click stay with the frame (target and menu), so they're only offered with a modifier. Takes effect out of combat.",
				Off("enabled")),
			Dropdown("wheelMod", "Scroll with", ns.WHEEL_MODS, ns.WHEEL_MOD_ORDER,
				"A modifier to hold while scrolling to pick the blessing. With one set, plain scrolling over a frame still zooms the camera. Takes effect out of combat.",
				Off("enabled")),
		}},
		{label = "Visibility", items = {
			Dropdown("visibility", "Show icon", ns.VIS_MODES, ns.VIS_MODE_ORDER,
				"Mouseover: only on the frame under the mouse. Any other choice shows the icon on every group frame while it applies."),
			Toggle("hoverAlways", "Always show on hover",
				"The frame under the mouse shows its icon even when the condition doesn't apply.", hoverOnly),
		}},
		{label = "Position", items = {
			Dropdown("anchor", "Position", anchorLabels, ns.ANCHOR_ORDER,
				"Portrait covers the frame's portrait (player-style frames). Frames without one get it at their left edge."),
			Slider("size", "Icon size", 0, 64, 1, "px", "0 fits the frame, or the portrait."),
			Slider("x", "X offset", -80, 80, 1, "px"),
			Slider("y", "Y offset", -80, 80, 1, "px"),
		}},
		{label = "Style", items = {
			Slider("borderSize", "Border size", 0, 4, 1, "px"),
			ColorRow("borderColor", "Border color", NoBorder),
			Toggle("showMissing", "Highlight a missing blessing",
				"Colors the border when the player doesn't have your blessing.", NoBorder),
			ColorRow("missingColor", "Missing color", function() return NoBorder() or not D().showMissing end),
		}},
		{label = "Cooldown", items = {
			Toggle("cdSwipe", "Show swipe", "Darkens the icon as your blessing on that player runs down."),
			{type = "slider", label = "Swipe opacity", min = 0, max = 100, step = 5, unit = "%",
				get = swipeGet, set = swipeSet, default = function() return 70 end, disabled = Off("cdSwipe")},
			Toggle("cdReverse", "Reverse swipe", nil, Off("cdSwipe")),
			Toggle("cdText", "Show timer text"),
			Slider("cdThreshold", "Timer under (minutes)", 0, 60, 1, nil,
				"Only show the timer text once the blessing has less than this many minutes left. 0 always shows it.",
				Off("cdText")),
			Slider("cdTextSize", "Text size", 6, 24, 1, nil, nil, Off("cdText")),
			Dropdown("cdTextPos", "Text position", ns.TEXT_POINTS, ns.TEXT_POINT_ORDER, nil, Off("cdText")),
			ColorRow("cdTextColor", "Text color", Off("cdText")),
			Slider("cdTextX", "Text X offset", -30, 30, 1, "px", nil, Off("cdText")),
			Slider("cdTextY", "Text Y offset", -30, 30, 1, "px", nil, Off("cdText")),
		}},
		{label = "Assignments", items = {
			{type = "button", label = "PallyPower blessing assignments", text = "Open",
				desc = "PallyPower's own window for every paladin's class assignments (/ppe assign).",
				func = function() if ns.OpenAssignments then ns.OpenAssignments() end end},
		}},
	},
}}}

DUI:RegisterModule(ADDON, {
	plugin = ADDON,
	label = "Blessings",
	defaults = {},
	options = options,
})

-- /ppe opens this page (Options.lua).
function ns.OpenDaylight()
	local panel = DUI.OptionsPanel
	if not (panel and type(panel.Show) == "function") then return false end
	return (pcall(panel.Show, PAGE))
end
