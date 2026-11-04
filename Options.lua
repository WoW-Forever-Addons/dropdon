local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Options in Blizzard's settings (Esc > Options > AddOns > Dropdon), built with ns.BuildSettings (SettingsUI.lua).
-- Pages: Appearance (the same options and names as in the other addons, DESIGN.md) and General.
-- (01.11.2026) With DonCore's Options module the pages are tabs in the options window of all Don addons and
-- Blizzard's page only keeps the status and a button to that window.
---------------------------------------------------------------------------
local category

local function ApplyPanel() ns.ApplyPanelSettings() end

local PAGES = {
  { title = "Appearance", tip = "Windows: lock, size, background opacity, dim in combat.", items = {
    { header = "Window" },
    { kind = "button", name = "Large window", button = "Show / hide", tip = "The window with all instances, bosses and their loot. /dd",
      onClick = function() ns.ToggleBig() end, state = function() local p = _G.DropdonPanel return p ~= nil and p:IsShown() and true or false end },
    { kind = "button", name = "Small window", button = "Show / hide", tip = "The small window with the bosses of your instance. /dd mini",
      onClick = function() ns.ToggleMini() end, state = function() return ns.MiniShown and ns.MiniShown() or false end },
    { key = "panelLocked", name = "Lock window", tip = "The windows can no longer be dragged.", onChange = ApplyPanel },
    { key = "panelScale", kind = "slider", name = "Size", tip = "Size of both windows.", min = 0.6, max = 1.6, step = 0.05, onChange = ApplyPanel },
    { key = "panelAlpha", kind = "slider", name = "Background opacity", tip = "How opaque the window background is. Text stays fully visible.", min = 0, max = 1, step = 0.05, onChange = ApplyPanel },
    { key = "combatFade", name = "Dim in combat", tip = "Dims the whole window to 40 % while you are in combat.", onChange = ApplyPanel },
    { kind = "button", name = "Reset position", button = "Reset", tip = "Puts both windows back to their default place.",
      onClick = function() ns.ResetPanelPosition() end },
  } },
  { title = "General", tip = "Minimap button, instance selection and tooltip line.", items = {
    { header = "Dropdon" },
    ns.MinimapOption(), -- (04.11.2026, Era-Test) the shared switch of DonCore's MinimapButton 3, its texts translated there
    { key = "autoSelect", name = "Select the instance you walk into", tip = "When you enter a dungeon or raid, the windows show its bosses and loot." },
    { key = "tooltip", name = "Drop line in item tooltips", tip = "Adds the instance and boss to the tooltip of items that drop there. /dd tooltip" },
  } },
}

local function Status()
  local lines = {}
  local version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)
  version = version and ns.Call(version, "Dropdon", "Version")
  if type(version) == "string" and version ~= "" then lines[#lines + 1] = L["Version %s"]:format(version) end
  return lines
end

local TOOLS = {
  -- (02.11.2026) on / off tools show their state in DonCore's options window (state)
  { "Large window", "Show / hide", function() ns.ToggleBig() end, "The window with all instances, bosses and their loot. /dd",
    state = function() local p = _G.DropdonPanel return p ~= nil and p:IsShown() and true or false end },
  { "Small window", "Show / hide", function() ns.ToggleMini() end, "The small window with the bosses of your instance. /dd mini",
    state = function() return ns.MiniShown and ns.MiniShown() or false end },
  { "Commands", "Show", function() ns.PrintHelp() end, "Lists the chat commands. /dd help" },
}
for _, t in ipairs(TOOLS) do t[3] = ns.Guard("tool", t[3]) end

-- (01.11.2026, StyleKit 2 step 3) the commands, shown under the status on the Tools tab of the shared options window
local function Help()
  local lines = {}
  for _, c in ipairs(ns.COMMANDS or {}) do lines[#lines + 1] = c[1] .. "  " .. L[c[2]] end
  return table.concat(lines, "\n")
end

local function Build()
  category = ns.BuildSettings({ name = "Dropdon", status = Status, tools = TOOLS, pages = PAGES, help = Help })
end

-- (01.11.2026) DonCore's options window of all Don addons (no Blizzard panel, so also in combat); Blizzard's settings
-- only when that window is not there (an older DonCore), and those stay closed in combat.
function ns.OpenOptions()
  if ns.OpenDonOptions and ns.OpenDonOptions() then return end
  if InCombatLockdown and InCombatLockdown() then
    ns.Print(L["Options cannot be opened in combat."])
    return
  end
  if category and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(category:GetID())
  else
    ns.PrintHelp()
  end
end

ns.OnInit(Build)
