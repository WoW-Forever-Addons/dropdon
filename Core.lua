local addonName, ns = ...
local L = ns.L
ns.Style = LibStub("DonCore-1.0"):Get("Style", 3) -- shared kit from DonCore (Libs\DonCore\Style.lua)
LibStub("DonCore-1.0"):Get("Settings", 1):Attach(addonName, ns) -- Blizzard options from DonCore (Libs\DonCore\Settings.lua)

---------------------------------------------------------------------------
-- Dropdon: dungeon and raid loot for WoW Forever.
-- Own frames only: no hooksecurefunc, no HookScript, no Blizzard frame scripts.
---------------------------------------------------------------------------
ns.defaults = {
  panel = {},        -- window position, scale, alpha, collapsed, shown (Style.Panel get/set)
  last = {},         -- last chosen instance and entry
  filters = {},      -- class / usable / slot (see Filter.lua)
  panelMini = {},    -- position etc. of the small window
  mode = "big",      -- which window /dd and the minimap button open ("big" or "mini")
  minimapButton = true,
  minimapAngle = 225, -- (04.11.2026, Era-Test) 225 so the Don minimap buttons do not cover each other
  autoSelect = true, -- select the instance you walk into
  tooltip = true,    -- the line Instance - Boss in item tooltips
  -- Look of both windows (Options > Appearance). Position and collapsed state stay per window in panel / panelMini.
  panelLocked = false,
  panelScale = 1,
  panelAlpha = 0.82, -- background opacity (same as Style.DEFAULT_ALPHA)
  combatFade = false,
}
ns.SCHEMA = 1
ns.WORDMARK = "|cff3fa9f5Drop|rdon"

---------------------------------------------------------------------------
-- Error guard: handlers, timers and UI callbacks run protected.
---------------------------------------------------------------------------
local MAX_ERRORS, MAX_MSG = 10, 160
local errors, warned = {}, false

local function Shorten(msg)
  msg = tostring(msg or "?"):gsub("\\", "/")
  msg = msg:gsub("[^%s:]*/([%w_]+%.[lx][um][al])", "%1")
  if #msg > MAX_MSG then msg = msg:sub(1, MAX_MSG) .. "..." end
  return msg
end

local function Record(context, err)
  if type(err) ~= "string" then err = "(unreadable error)" end
  local ok, msg = pcall(Shorten, err)
  if not ok then msg = "(unreadable error)" end
  for _, e in ipairs(errors) do
    if e.msg == msg and e.context == context then e.count = e.count + 1 return end
  end
  if #errors < MAX_ERRORS then errors[#errors + 1] = { context = context, msg = msg, count = 1 } end
  if not warned then
    warned = true
    print(ns.WORDMARK .. ": " .. L["an error occurred, /dd diag for details"])
  end
end

function ns.Errors() return errors end

function ns.SafeCall(context, fn, ...)
  local args, n = { ... }, select("#", ...)
  local ok, a, b, c = xpcall(function() return fn(unpack(args, 1, n)) end, function(err)
    pcall(Record, context, err)
    return err
  end)
  if ok then return a, b, c end
end

function ns.Guard(context, fn)
  return function(...) return ns.SafeCall(context, fn, ...) end
end

function ns.After(delay, fn)
  if C_Timer and C_Timer.After then C_Timer.After(delay, ns.Guard("timer", fn)) end
end

---------------------------------------------------------------------------
-- Events on our own frame. Several modules may listen to one event.
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local listeners, initCallbacks = {}, {}

function ns.On(event, fn)
  if not listeners[event] then
    listeners[event] = {}
    local ok = pcall(frame.RegisterEvent, frame, event) -- unknown events throw
    if not ok then listeners[event] = nil return false end
  end
  table.insert(listeners[event], fn)
  return true
end

function ns.OnInit(fn) table.insert(initCallbacks, fn) end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= addonName then return end
    DropdonDB = type(DropdonDB) == "table" and DropdonDB or {}
    -- 24.10.: look settings moved from the per window tables to one shared setting (took the big window's values)
    local old = type(DropdonDB.panel) == "table" and DropdonDB.panel or {}
    local oldMini = type(DropdonDB.panelMini) == "table" and DropdonDB.panelMini or {}
    for flat, key in pairs({ panelLocked = "locked", panelScale = "scale", panelAlpha = "alpha", combatFade = "combatFade" }) do
      if DropdonDB[flat] == nil and type(old[key]) == type(ns.defaults[flat]) then DropdonDB[flat] = old[key] end
      old[key], oldMini[key] = nil, nil
    end
    for k, v in pairs(ns.defaults) do
      if type(DropdonDB[k]) ~= type(v) then DropdonDB[k] = type(v) == "table" and {} or v end
    end
    DropdonDB.schema = ns.SCHEMA
    ns.db = DropdonDB
    for _, fn in ipairs(initCallbacks) do ns.SafeCall("init", fn) end
    return
  end
  if not ns.db then return end
  local list = listeners[event]
  if list then
    for i = 1, #list do ns.SafeCall(event, list[i], event, ...) end
  end
end)

---------------------------------------------------------------------------
-- Both windows share locked / scale / opacity / combat dimming (one setting each); position and collapsed state
-- stay per window. Style.Panel asks through these callbacks.
---------------------------------------------------------------------------
local SHARED = { locked = "panelLocked", scale = "panelScale", alpha = "panelAlpha", combatFade = "combatFade" }
function ns.PanelGet(tableName)
  return function(key)
    local flat = SHARED[key]
    if flat then return ns.db[flat] end
    return ns.db[tableName][key]
  end
end
function ns.PanelSet(tableName)
  return function(key, value)
    local flat = SHARED[key]
    if flat then ns.db[flat] = value else ns.db[tableName][key] = value end
  end
end

local panels = {}
function ns.TrackPanel(p) panels[#panels + 1] = p end

-- after an option changed: both windows read their settings again
function ns.ApplyPanelSettings()
  for _, p in ipairs(panels) do p:ApplySettings() end
end

function ns.ResetPanelPosition()
  ns.db.panel.pos, ns.db.panelMini.pos = nil, nil
  for _, p in ipairs(panels) do p:ResetPosition() end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function ns.Print(msg) print(ns.WORDMARK .. ": " .. tostring(msg)) end

-- Secret values (Midnight rules) never reach comparisons or table keys in our code.
function ns.Usable(v)
  if type(v) == "nil" then return false end
  if canaccessvalue then
    local ok, r = pcall(canaccessvalue, v)
    if ok then return r and true or false end
    return false
  end
  if issecretvalue then
    local ok, r = pcall(issecretvalue, v)
    if ok then return not r end
    return false
  end
  return true
end

function ns.Num(v)
  if type(v) == "number" and ns.Usable(v) then return v end
  return nil
end

function ns.Str(v)
  if type(v) == "string" and ns.Usable(v) and v ~= "" then return v end
  return nil
end

function ns.Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if ok then return v end
  return nil
end

function ns.Value(fn, ...)
  local v = ns.Call(fn, ...)
  if ns.Usable(v) then return v end
  return nil
end

function Dropdon_OnAddonCompartmentClick()
  if ns.ToggleWindow then ns.ToggleWindow() end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_DROPDON1 = "/dd"
SLASH_DROPDON2 = "/dropdon"
ns.COMMANDS = {
  { "/dd", "show or hide the window" },
  { "/dd mini", "small window with the bosses of your instance" },
  { "/dd options", "open the options" },
  { "/dd button", "show or hide the minimap button" },
  { "/dd tooltip", "show or hide the drop line in item tooltips" },
  { "/dd help", "this list" },
}

function ns.PrintHelp()
  ns.Print(L["Commands:"])
  for _, c in ipairs(ns.COMMANDS) do print("  |cffebebeb" .. c[1] .. "|r  |cff9ea3ad" .. L[c[2]] .. "|r") end
end

function ns.Slash(msg)
  msg = tostring(msg or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
  if msg == "" or msg == "show" or msg == "toggle" then
    if ns.ToggleWindow then ns.ToggleWindow() end
  elseif msg == "mini" or msg == "klein" then
    if ns.ToggleMini then ns.ToggleMini() end
  elseif msg == "options" or msg == "optionen" or msg == "config" then
    if ns.OpenOptions then ns.OpenOptions() end
  elseif msg == "button" or msg == "minimap" then
    ns.db.minimapButton = not ns.db.minimapButton
    if ns.RefreshMinimapButton then ns.RefreshMinimapButton() end
  elseif msg == "tooltip" then
    ns.db.tooltip = ns.db.tooltip == false
    ns.Print(ns.db.tooltip and L["Tooltip line on."] or L["Tooltip line off."])
  elseif msg == "help" or msg == "?" or msg == "hilfe" then
    ns.PrintHelp()
  else
    ns.Print(L["Unknown command: %s"]:format(msg))
    ns.PrintHelp()
  end
end

SlashCmdList["DROPDON"] = function(msg) ns.SafeCall("slash", ns.Slash, msg) end
