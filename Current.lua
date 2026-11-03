local _, ns = ...

---------------------------------------------------------------------------
-- Which instance are you in? The map of the player or one of its parents is a dungeon map of the data
-- (uiMapID from Questdon's ATT_DUNGEONS); else the instance name against the names of the data.
-- When you walk in, Dropdon selects it (option autoSelect).
---------------------------------------------------------------------------
local byMap, byName

local function Norm(s)
  s = tostring(s or ""):lower():gsub("^the ", ""):gsub("[^%w]", "")
  return s
end

local function Index()
  if byMap then return end
  byMap, byName = {}, {}
  for id, d in pairs(ns.DROPS or {}) do
    if (d.map or 0) > 0 then byMap[d.map] = id end
    byName[Norm(d.name)] = id
  end
end

function ns.CurrentInstance()
  Index()
  local m = C_Map and ns.Num(ns.Value(C_Map.GetBestMapForUnit, "player"))
  for _ = 1, 4 do
    if not m or m <= 0 then break end
    if byMap[m] then return byMap[m] end
    local info = ns.Value(C_Map.GetMapInfo, m)
    m = type(info) == "table" and ns.Num(info.parentMapID) or nil
  end
  if ns.Value(IsInInstance) ~= true then return nil end
  local name = ns.Value(GetInstanceInfo)
  if type(name) ~= "string" or name == "" then return nil end
  return byName[Norm(name)]
end

local last
local function Check()
  if ns.ListenForBosses then ns.ListenForBosses() end
  local id = ns.CurrentInstance()
  if id then ns.LearnInstanceName(id) end
  if id == last then return end
  last = id
  if id and ns.db.autoSelect and ns.ShowInstance then ns.ShowInstance(id) end
end

ns.On("PLAYER_ENTERING_WORLD", function() ns.After(1, Check) end)
ns.On("ZONE_CHANGED_NEW_AREA", function() ns.After(0.5, Check) end)

---------------------------------------------------------------------------
-- (25.10., OFFEN "Bossnamen nur Englisch") Boss and instance names in the game's language. No open source has them
-- (ATT, CMaNGOS and ForeverDB are English), so Dropdon learns them in the game: a boss you target, mouse over or see
-- on a nameplate (its creature ID from the GUID), the instance you are in (GetInstanceInfo). Kept per language in
-- DropdonDB.bossNames / DropdonDB.instanceNames; until then the English name. English clients learn nothing.
---------------------------------------------------------------------------
local bossIds

local function BossIndex()
  if bossIds then return end
  bossIds = {}
  for _, d in pairs(ns.DROPS or {}) do
    for _, b in ipairs(d.bosses or {}) do
      if not b.enc and ns.Num(b.id) then bossIds[b.id] = true end
    end
  end
end

local function Lang()
  local loc = ns.Str(ns.Value(GetLocale))
  if not loc or loc == "enUS" or loc == "enGB" then return nil end
  return loc
end

local function Kept(field, loc)
  if not (ns.db and loc) then return nil end
  if type(ns.db[field]) ~= "table" then ns.db[field] = {} end
  if type(ns.db[field][loc]) ~= "table" then ns.db[field][loc] = {} end
  return ns.db[field][loc]
end

-- (Leistungsprüfung D23, 31.10.2026) a learned name rebuilds the tooltip index and redraws the window: the first at once,
-- more boss names within 2 seconds (nameplates of a whole boss room) together once after them; an instance name (once per
-- instance) at once
local QUIET = 2
local lastChange, changeDue = -QUIET, false
local function ApplyChange()
  lastChange = GetTime and GetTime() or 0
  if ns.ResetTooltipIndex then ns.ResetTooltipIndex() end
  if ns.RefreshWindow then ns.SafeCall("names", ns.RefreshWindow) end
end
local function Changed(now)
  if now then return ApplyChange() end
  local t = GetTime and GetTime() or 0
  if t - lastChange >= QUIET then return ApplyChange() end
  if changeDue then return end
  changeDue = true
  ns.After(QUIET, function() changeDue = false ApplyChange() end)
end

function ns.BossName(b)
  if type(b) ~= "table" then return "" end
  local loc = Lang()
  local t = loc and type(ns.db and ns.db.bossNames) == "table" and ns.db.bossNames[loc]
  local n = type(t) == "table" and not b.enc and b.id and t[b.id]
  return n or b.name or ""
end

function ns.InstanceName(id, d)
  d = d or (ns.DROPS and ns.DROPS[id])
  if type(d) ~= "table" then return "" end
  local loc = Lang()
  local t = loc and type(ns.db and ns.db.instanceNames) == "table" and ns.db.instanceNames[loc]
  return type(t) == "table" and t[id] or d.name or ""
end

function ns.LearnBossName(unit)
  local loc = Lang()
  if not loc then return end
  local guid = ns.Str(ns.Value(UnitGUID, unit))
  if not guid then return end
  local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  id = tonumber(id)
  if not (id and (kind == "Creature" or kind == "Vehicle")) then return end
  BossIndex()
  if not bossIds[id] then return end
  local name = ns.Str(ns.Value(UnitName, unit))
  if not name then return end
  local t = Kept("bossNames", loc)
  if t[id] ~= name then t[id] = name Changed() end
end

function ns.LearnInstanceName(id)
  local loc = Lang()
  if not (loc and id) then return end
  if ns.Value(IsInInstance) ~= true then return end
  local name = ns.Str(ns.Value(GetInstanceInfo))
  if not name then return end
  local t = Kept("instanceNames", loc)
  if t[id] ~= name then t[id] = name Changed(true) end
end

ns.On("PLAYER_TARGET_CHANGED", function() ns.LearnBossName("target") end)

-- (D23, 31.10.2026) mouseover and nameplates fire all the time in the open world, but the bosses are all in instances:
-- listened to only inside an instance and only on clients that learn names (not English); switched at every zone change
local unitFrame = CreateFrame("Frame")
local UNIT_EVENTS = { "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED" }
local listening = false
unitFrame:SetScript("OnEvent", ns.Guard("names", function(_, event, unit)
  if event == "UPDATE_MOUSEOVER_UNIT" then ns.LearnBossName("mouseover")
  elseif ns.Str(unit) then ns.LearnBossName(unit) end
end))
-- on: nil = decide by language and instance
function ns.ListenForBosses(on)
  if on == nil then on = Lang() ~= nil and ns.Value(IsInInstance) == true end
  on = on and true or false
  if on == listening then return end
  listening = on
  for _, e in ipairs(UNIT_EVENTS) do pcall(on and unitFrame.RegisterEvent or unitFrame.UnregisterEvent, unitFrame, e) end
end
function ns.ListeningForBosses() return listening end
