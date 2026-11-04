local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Minimap button: left click opens the window, right click a small menu, drag moves it around the minimap.
-- The button itself comes from DonCore (Libs\DonCore\MinimapButton.lua, DONCORE_PLAN.md step 3).
-- (04.11.2026, Era-Test) MinimapButton 3: the gold ring with Dropdon's own symbol (Media\minimap.tga), the switch is
-- ns.MinimapOption() (Options.lua), default angle 225 so the Don buttons do not cover each other (saved angles stay);
-- the tooltip has one line of state: the instance you are in
-- (04.11.2026, Era-Test, Daniel: "bei questdon kommt mit rechtsklick so ein menü, das hätte ich bei den anderen auch gerne")
-- right click opens Questdon's menu: loot window, mini window, a line, the main switches (check rows, the menu stays
-- open), a line, all options; DonCore's MinimapButton 4 adds a line and "Hide minimap button" at the end.
---------------------------------------------------------------------------
local function StateLine()
  local id = ns.CurrentInstance and ns.CurrentInstance()
  local name = id and ns.InstanceName and ns.InstanceName(id) or ""
  if name ~= "" then return { L["You are here: %s"]:format(name) } end
  return { L["Not in a dungeon or raid"] }
end

-- The switches: label (the option's text), key in ns.db, what to refresh (as in Options.lua).
local function ApplyPanel() if ns.ApplyPanelSettings then ns.ApplyPanelSettings() end end
local SWITCHES = {
  { label = "Lock window", key = "panelLocked", apply = ApplyPanel },
  { label = "Dim in combat", key = "combatFade", apply = ApplyPanel },
  { label = "Select the instance you walk into", key = "autoSelect" },
  { label = "Drop line in item tooltips", key = "tooltip", defaultOn = true }, -- nil counts as on (Tooltip.lua)
}

local function IsOn(sw)
  local v = ns.db and ns.db[sw.key]
  if sw.defaultOn then return v ~= false end
  return v and true or false
end

local function Toggle(sw)
  if type(ns.db) ~= "table" then return end
  ns.db[sw.key] = not IsOn(sw)
  if sw.apply then ns.SafeCall("minimap menu", sw.apply) end
  if ns.RefreshSettingsUI then ns.SafeCall("minimap menu", ns.RefreshSettingsUI) end
end
ns.MinimapMenuToggle = function(i) local sw = SWITCHES[i] if sw then Toggle(sw) end end -- (tests)

-- The menu's rows: both windows, a line, the switches (check rows), a line, all options.
local function MenuItems()
  local items = {
    { text = L["Loot window"], onClick = function() if ns.ToggleBig then ns.ToggleBig() end end },
    { text = L["Mini window"], onClick = function() if ns.ToggleMini then ns.ToggleMini() end end },
    { line = true },
  }
  for _, sw in ipairs(SWITCHES) do
    items[#items + 1] = { text = L[sw.label], onClick = function() Toggle(sw) end, isOn = function() return IsOn(sw) end }
  end
  items[#items + 1] = { line = true }
  items[#items + 1] = { text = L["All options"], onClick = function() if ns.OpenOptions then ns.OpenOptions() end end }
  return items
end

LibStub("DonCore-1.0"):Get("MinimapButton", 4):Attach(ns, {
  name = "DropdonMinimapButton", addon = "Dropdon",
  icon = "Interface\\AddOns\\Dropdon\\Media\\minimap",
  angleKey = "minimapAngle", defaultAngle = 225,
  title = ns.WORDMARK,
  lines = function() local ok, t = pcall(StateLine) return ok and t or nil end,
  hint = function() return L["Left click: window. Right click: menu. Drag: move."] end,
  onLeft = function() if ns.ToggleBig then ns.ToggleBig() end end,
  menu = { name = "DropdonMinimapMenu", title = ns.WORDMARK, width = 250, items = MenuItems },
})

ns.OnInit(function() ns.SafeCall("minimap button", ns.RefreshMinimapButton) end)
