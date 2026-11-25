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
  -- (16.11.2026, Daniel: "Sollte Standart sein", like Luredon 1.7.0) both windows from the game's own templates
  -- (DonCore Blizz); without them in the client the Don look stays, without a word
  blizzLook = true,
}
-- (16.11.2026, Blizzard look for all Don addons, pattern Luredon/Core.lua) the one place that says which kit builds
-- Dropdon's windows: DonCore's Kit, or with the option blizzLook the same blocks from the game's own templates (DonCore
-- module Blizz). Returns the kit, true when it is Blizzard's, the Blizz module and the reason ("blizzard", "kit",
-- "kit (missing: ...)").
function ns.LookKit()
  local Core = LibStub("DonCore-1.0")
  local Kit = Core:Get("Kit", 10) or Core:Get("Kit", 1)
  if not (ns.db and ns.db.blizzLook) then return Kit, false, nil, "kit" end
  local Bz = Core:Get("Blizz", 5)
  if not Bz then return Kit, false, nil, "kit (no DonCore Blizz)" end
  local kit, miss = Bz.Kit()
  if not kit then return Kit, false, Bz, "kit (missing: " .. tostring(miss) .. ")" end
  return kit, true, Bz, "blizzard"
end

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

-- (22.11.2026, Ruckler, DonMonitor) every protected call that takes SLOW_MS or more goes into the global ring DonSlowLog
-- (60 entries, not saved; DonMonitor's report lists it): addon, context, where the function was registered, ms. Below
-- the threshold two debugprofilestop calls, no garbage. The game has no debug.getinfo: the place is noted with
-- debugstack when a listener is registered, for timers only while DonMonitor runs.
local SLOW_MS, SLOW_MAX = 8, 200 -- (22.11.2026) 8 ms as DonMonitor's hitch threshold; the report sums them up
local dps = type(debugprofilestop) == "function" and debugprofilestop or nil
local fnWhere = setmetatable({}, { __mode = "k" })
local function Where(level)
  if type(debugstack) ~= "function" then return nil end
  local ok, stack = pcall(debugstack, level, 6, 0)
  if not ok or type(stack) ~= "string" then return nil end
  local first
  for file, line in stack:gsub("\\", "/"):gmatch('([%w_]+%.lua)["%]]*:(%d+)') do
    local at = file .. ":" .. line
    if file ~= "Core.lua" then return at end
    first = first or at
  end
  return first
end
local function NoteWhere(fn, level)
  if type(fn) == "function" and not fnWhere[fn] then fnWhere[fn] = Where(level + 1) end
end
local function NoteSlow(context, fn, ms)
  local log = rawget(_G, "DonSlowLog")
  if type(log) ~= "table" then log = { n = 0 } DonSlowLog = log end
  local okT, clock = pcall(date, "%H:%M:%S")
  log.n = (log.n or 0) + 1
  log[(log.n - 1) % SLOW_MAX + 1] = { n = log.n, t = okT and clock or "?", a = addonName, c = tostring(context),
    f = fnWhere[fn] or "?", ms = math.floor(ms * 10 + 0.5) / 10 }
end
-- pcall with the arguments directly: no table and no closure per call (was one of each, every event and timer)
local function Done(context, ok, a, b, c)
  if ok then return a, b, c end
  pcall(Record, context, a)
end
local function SlowDone(context, fn, t0, ...)
  local ms = dps() - t0
  if ms >= SLOW_MS then pcall(NoteSlow, context, fn, ms) end
  return ...
end
function ns.SafeCall(context, fn, ...)
  if not dps then return Done(context, pcall(fn, ...)) end
  return SlowDone(context, fn, dps(), Done(context, pcall(fn, ...)))
end

function ns.Guard(context, fn)
  return function(...) return ns.SafeCall(context, fn, ...) end
end

function ns.After(delay, fn)
  if rawget(_G, "DonMonitorDB") then NoteWhere(fn, 2) end
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
  NoteWhere(fn, 2)
  return true
end

function ns.OnInit(fn) NoteWhere(fn, 2) table.insert(initCallbacks, fn) end

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
  { "/dd diag", "diagnostics in a window to copy" },
  { "/dd help", "this list" },
}

---------------------------------------------------------------------------
-- (16.11.2026, Daniel: "bei allen addons soll der diag befehl ein fenster zum kopieren aufmachen") /dd diag: the facts
-- in one copy window (game look with blizzLook and the game's templates, else DonCore's Kit, else the chat);
-- /dd diag chat prints them as before. No character or realm names.
---------------------------------------------------------------------------
local function Meta(field)
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local v = get and ns.Call(get, addonName, field)
  return type(v) == "string" and v ~= "" and v or "?"
end

local function YesNo(v) return v and "on" or "off" end

function ns.DiagLines()
  local out = {}
  local function Add(s) out[#out + 1] = s end
  Add("Dropdon " .. Meta("Version") .. " diag")
  local version, build, _, toc
  if GetBuildInfo then
    local ok, a, b, c, d = pcall(GetBuildInfo)
    if ok then version, build, toc = a, b, d end
  end
  Add(("Client: %s build %s toc %s, locale %s%s"):format(tostring(version or "?"), tostring(build or "?"), tostring(toc or "?"),
    tostring(ns.Call(GetLocale) or "?"), (ns.IsEra and ns.Call(ns.IsEra)) and ", Classic Era" or ""))
  -- the loot data: instances, bosses, items (bosses, quest rewards, shared drops), ATT files new / old
  local inst, raids, bosses, items, seen, new, old = 0, 0, 0, 0, {}, 0, 0
  local function Count(list)
    for _, e in ipairs(type(list) == "table" and list or {}) do
      local ids = type(e) == "table" and e.items or nil
      if type(e) == "number" then ids = { e } end
      for _, id in ipairs(type(ids) == "table" and ids or {}) do
        if not seen[id] then seen[id], items = true, items + 1 end
      end
    end
  end
  for _, d in pairs(type(ns.DROPS) == "table" and ns.DROPS or {}) do
    inst = inst + 1
    if d.raid then raids = raids + 1 end
    if d.src == "old" then old = old + 1 else new = new + 1 end
    bosses = bosses + #(d.bosses or {})
    Count(d.bosses) Count(d.quests) Count(d.common)
  end
  Add(("Data: %d instances (%d dungeons, %d raids), %d bosses, %d items; ATT files new %d, old %d"):format(
    inst, inst - raids, raids, bosses, items, new, old))
  local here = ns.CurrentInstance and ns.Call(ns.CurrentInstance)
  Add("Here: " .. (here and (tostring(ns.DROPS[here] and ns.DROPS[here].name or "?") .. " (" .. tostring(here) .. ")") or "no instance"))
  local db = ns.db or {}
  Add(("Options: mode %s, blizzLook %s, autoSelect %s, tooltip %s, minimapButton %s"):format(tostring(db.mode),
    YesNo(db.blizzLook), YesNo(db.autoSelect), YesNo(db.tooltip), YesNo(db.minimapButton)))
  Add(("Windows: locked %s, scale %s, opacity %s, combatFade %s"):format(YesNo(db.panelLocked), tostring(db.panelScale),
    tostring(db.panelAlpha), YesNo(db.combatFade)))
  local f = type(db.filters) == "table" and db.filters or {}
  Add(("Filters: class %s, usable %s, slot %s"):format(YesNo(f.class ~= false), YesNo(f.usable ~= false), tostring(f.slot or "ALL")))
  local _, _, _, why = ns.LookKit()
  local Opt = LibStub("DonCore-1.0"):Get("Options", 8)
  Add(("Look: large window %s, small window %s, options %s (option says %s)"):format(
    tostring(ns.WindowLook and ns.WindowLook() or "?"), tostring(ns.MiniLook and ns.MiniLook() or "?"),
    tostring(Opt and Opt.Look() or "?"), tostring(why)))
  if #errors == 0 then
    Add("Errors: none")
  else
    Add("Errors: " .. #errors)
    for _, e in ipairs(errors) do Add(("  %s: %s (x%d)"):format(tostring(e.context), tostring(e.msg), e.count)) end
  end
  return out
end

function ns.PrintDiag()
  for _, line in ipairs(ns.DiagLines()) do ns.Print(line) end
end

-- the copy window; returns the dialog, or nil when it went to the chat
function ns.ShowDiag()
  local text = table.concat(ns.DiagLines(), "\n")
  local title, hint = "Dropdon diag · " .. L["Diagnostics"], L["Ctrl+A selects all, Ctrl+C copies."]
  local words = { selectAll = L["Select all"], close = L["Close"] }
  local UI, blizz = ns.LookKit()
  if blizz and UI and UI.ShowCopy then
    local ok, d = pcall(UI.ShowCopy, title, hint, text, words)
    if ok and d then return d end
    pcall(Record, "diag blizz look", ok and "no dialog" or d)
  end
  local Kit = LibStub("DonCore-1.0"):Get("Kit", 1)
  if Kit and Kit.ShowCopy then
    local ok, d = pcall(Kit.ShowCopy, title, hint, text, words)
    if ok and d then return d end
    pcall(Record, "diag window", ok and "no dialog" or d)
  end
  ns.PrintDiag()
end

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
  elseif msg == "diag" then
    ns.ShowDiag()
  elseif msg == "diag chat" then
    ns.PrintDiag()
  elseif msg == "help" or msg == "?" or msg == "hilfe" then
    ns.PrintHelp()
  else
    ns.Print(L["Unknown command: %s"]:format(msg))
    ns.PrintHelp()
  end
end

SlashCmdList["DROPDON"] = function(msg) ns.SafeCall("slash", ns.Slash, msg) end
