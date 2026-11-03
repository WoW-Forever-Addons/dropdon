local _, ns = ...
local L = ns.L
local Core = LibStub("DonCore-1.0")
local Kit = Core:Get("Kit", 10) or Core:Get("Kit", 1)
local C = Kit.C

---------------------------------------------------------------------------
-- Main window (02.11.2026, StyleKit 2 step 4, mockup docs/layout_2026-11-02/dropdon/, approved by Daniel): built from
-- DonCore's kit only. Kit.Window 720x420 to 1300x900 (place and size in DropdonDB.win), logo, the instance as subtitle,
-- head symbols small window, cog, close; footer with the instance's level range and bosses.
-- Three columns: instances (search, groups Dungeons / Raids, level range in Blizzard's quest colours of the lowest level,
-- blue mark where you are), bosses (wings as group heads, the title in <> as second line, "fit / all" on the right, a
-- divider, shared drops, quest rewards), loot (switches My class and Usable, slot list, chip "Hidden n", Kit.Table:
-- symbol with the quality edge, type and slot below, item level and required level, sortable).
-- Under 960 px the first two columns get narrower, under 800 px the instance column goes and a dropdown above the
-- bosses chooses the instance. Every text one line, cut with "...", the whole text in the tooltip.
---------------------------------------------------------------------------
local W -- the Kit.Window
local sel = { inst = nil, entry = nil, showAll = false }
local hiddenCount = 0
local lootIDs = {} -- the item ids of the table, in order (tests)
local GAP = 8
local HEAD = 28   -- column heads (Kit.GroupHeader)
local BAR = 40    -- the filter bar
local SEARCH = 40 -- search box over the instances

---------------------------------------------------------------------------
-- Data helpers
---------------------------------------------------------------------------
local sorted
local function Instances()
  if sorted then return sorted end
  sorted = { dungeons = {}, raids = {} }
  for id, d in pairs(ns.DROPS or {}) do
    table.insert(d.raid and sorted.raids or sorted.dungeons, { id = id, d = d })
  end
  table.sort(sorted.dungeons, function(a, b)
    if a.d.min ~= b.d.min then return a.d.min < b.d.min end
    if a.d.max ~= b.d.max then return a.d.max < b.d.max end
    return a.d.name < b.d.name
  end)
  table.sort(sorted.raids, function(a, b) return a.d.name < b.d.name end)
  return sorted
end

local function PlayerLevel()
  return ns.Num(ns.Call(UnitLevel, "player")) or 0
end

local function LevelText(d)
  if (d.min or 0) <= 0 then return "" end
  if d.min == d.max then return tostring(d.min) end
  return d.min .. "-" .. d.max
end

-- (Daniel 02.11.2026) Blizzard's quest colours, measured at the instance's lowest level
local function LevelColor(d)
  if (d.min or 0) <= 0 then return C.muted end
  local st = Kit.STATUS[Kit.QuestDifficulty(d.min, PlayerLevel() > 0 and PlayerLevel() or nil)]
  return st and st.fg or C.muted
end

local function Hex(c) return "|c" .. (c.hex or Kit.HexColor and Kit.HexColor(c) or "ffffffff") end

-- "Name <Title>" -> "Name", "Title"
local function SplitName(name)
  name = tostring(name or "")
  local main, title = name:match("^(.-)%s*<([^>]*)>%s*$")
  if main and main ~= "" then return main, title end
  return name, nil
end
ns.SplitBossName = SplitName

local function QuestItems(d)
  local seen, out, from = {}, {}, {}
  for _, q in ipairs(d.quests or {}) do
    for _, id in ipairs(q.items) do
      if not seen[id] then seen[id] = true out[#out + 1] = id from[id] = q.name end
    end
  end
  return out, from
end

local function EntryItems(d, entry)
  if entry == "common" then return d.common or {} end
  if entry == "quests" then return (QuestItems(d)) end
  local b = d.bosses[entry]
  return b and b.items or {}
end

local function EntryName(d, entry)
  if entry == "common" then return L["Shared drops"] end
  if entry == "quests" then return L["Quest rewards"] end
  local b = d.bosses[entry]
  return b and (SplitName(ns.BossName(b))) or ""
end

local function ItemsText(n)
  return (n == 1 and L["%d item"] or L["%d items"]):format(n)
end

local function Passing(ids)
  local f, n = ns.Filters(), 0
  for _, id in ipairs(ids) do if ns.PassFilters(id, f) then n = n + 1 end end
  return n
end

-- the right column of a boss row: fitting items gold, the total quiet ("4/6")
local function FitText(fit, all)
  return Hex(fit > 0 and C.txGold or C.quiet) .. fit .. "|r" .. Hex(C.quiet) .. "/" .. all .. "|r"
end

---------------------------------------------------------------------------
-- Loot table
---------------------------------------------------------------------------
-- the line under the name: weapon and armour "type · slot", the rest "class · subclass"
local function SubLine(id)
  local m = ns.ItemMeta(id)
  local slot = m.equipLoc ~= "" and ns.Str(rawget(_G, m.equipLoc)) or nil
  local a, b
  if m.classID == 2 or m.classID == 4 then
    a, b = m.subText, slot
  else
    a = m.typeText
    if m.subText and m.subText ~= m.typeText then b = m.subText end
  end
  if a and b then return a .. " · " .. b end
  return a or b or ""
end

local function SortItems(items)
  local s = ns.db.sort
  if type(s) ~= "table" or not s.key then return end
  local key, asc = s.key, s.asc and true or false
  local function v(it)
    if key == "title" then return it.title or "" end
    return tonumber(it.cells[key]) or -1
  end
  table.sort(items, function(a, b)
    local x, y = v(a), v(b)
    if x == y then return a.order < b.order end
    if asc then return x < y end
    return x > y
  end)
end

local function LootItems(d)
  local all = EntryItems(d, sel.entry)
  local _, quest = QuestItems(d)
  local f, lvl = ns.Filters(), PlayerLevel()
  local items, hidden = {}, 0
  for i, id in ipairs(all) do
    local pass = ns.PassFilters(id, f)
    if not pass then hidden = hidden + 1 end
    if pass or sel.showAll then
      local name, quality = ns.ItemName(id)
      local ilvl, req = ns.ItemLevels(id)
      local sub = SubLine(id)
      if sel.entry == "quests" and quest[id] then sub = sub ~= "" and (sub .. " · " .. quest[id]) or quest[id] end
      local it = { kind = "trow", itemID = id, order = i, title = name or L["Loading item..."],
        titleColor = not name and C.quiet or nil, quality = name and quality or nil,
        icon = ns.ItemMeta(id).icon, sub = sub, cells = { ilvl = ilvl or "", req = req or "" },
        cellColors = (req and lvl > 0 and req > lvl) and { req = C.red } or nil }
      if not pass then it.unusable = ns.NotForYou(id) or L["Hidden by your filters."] end
      items[#items + 1] = it
    end
  end
  SortItems(items)
  return items, hidden, #all
end

local function Columns()
  return {
    { key = "title", title = L["Item"], sort = true },
    { key = "ilvl", title = L["Item level"], width = 64, sort = true, minWidth = 600, fold = L["iLvl"] },
    { key = "req", title = L["Req."], width = 48, sort = true },
  }
end

local Place

local function RefreshLoot(keep)
  local d = ns.DROPS[sel.inst]
  if not (W and d) or sel.entry == nil then return end
  local items, hidden, total = LootItems(d)
  hiddenCount = hidden
  lootIDs = {}
  for i, it in ipairs(items) do lootIDs[i] = it.itemID end
  W.lootHead:SetItem({ kind = "group", static = true, text = L["Loot"] .. ": " .. EntryName(d, sel.entry), count = ItemsText(total) })
  W.hiddenChip:SetCount(hidden, hidden > 0 and C.txGold or C.quiet)
  W.hiddenChip:SetSelected(sel.showAll)
  W.hiddenChip:SetDisabled(hidden == 0 and not sel.showAll)
  if #items == 0 then
    W.table:SetEmpty(total == 0 and L["No loot data for this entry."] or L["No matching loot for your filters."])
  end
  W.table:SetItems(items, not keep)
  if #items == 0 and hidden > 0 then
    W.showAll:SetText(L["Show %d hidden items"]:format(hidden))
    W.showAll:Show()
  else
    W.showAll:Hide()
  end
  if ns.RefreshMini then ns.RefreshMini() end
end

---------------------------------------------------------------------------
-- Instance and boss lists
---------------------------------------------------------------------------
local function InstanceRow(e, here)
  local d = e.d
  local tip = { ns.InstanceName(e.id, d), {} }
  if (d.min or 0) > 0 then tip[2][#tip[2] + 1] = L["Level %d to %d"]:format(d.min, d.max) end
  if d.src == "old" then tip[2][#tip[2] + 1] = L["Data from the older source: items may differ in Forever."] end
  local n = #(d.bosses or {})
  local sub = (n == 1 and L["%d boss"] or L["%d bosses"]):format(n)
  if here then sub = Hex(C.blue) .. L["You are here"] .. "|r · " .. sub end
  return { key = e.id, title = ns.InstanceName(e.id, d), sub = sub, right = LevelText(d), rightColor = LevelColor(d),
    markColor = here and C.blue or nil, tooltip = tip }
end

local function InstanceItems()
  local inst, out = Instances(), {}
  local q = W and W.query or ""
  local here = ns.CurrentInstance and ns.CurrentInstance()
  ns.db.closed = type(ns.db.closed) == "table" and ns.db.closed or {}
  for _, g in ipairs({ { "dungeons", L["Dungeons"] }, { "raids", L["Raids"] } }) do
    local rows = {}
    for _, e in ipairs(inst[g[1]]) do
      local name = ns.InstanceName(e.id, e.d)
      if q == "" or tostring(name):lower():find(q, 1, true) then rows[#rows + 1] = InstanceRow(e, e.id == here) end
    end
    if #rows > 0 then
      local closed = ns.db.closed[g[1]] and q == ""
      out[#out + 1] = { kind = "group", group = g[1], text = g[2], count = #rows, collapsed = closed }
      if not closed then for _, r in ipairs(rows) do out[#out + 1] = r end end
    end
  end
  return out
end

local function BossItems(d)
  local out, wing = {}, nil
  for i, b in ipairs(d.bosses) do
    if b.wing ~= "" and b.wing ~= wing then
      wing = b.wing
      out[#out + 1] = { kind = "group", static = true, text = wing }
    end
    local name, title = SplitName(ns.BossName(b))
    local fit = Passing(b.items)
    out[#out + 1] = { key = i, title = name, sub = title, h = title and 36 or 28, right = FitText(fit, #b.items),
      markColor = fit > 0 and C.green or nil, tooltip = title and { ns.BossName(b) } or nil }
  end
  -- 24.10. (Daniel): a divider sets the special entries apart from the bosses
  local extra = {}
  if d.common and #d.common > 0 then
    local fit = Passing(d.common)
    extra[#extra + 1] = { key = "common", title = L["Shared drops"], h = 28, right = FitText(fit, #d.common), markColor = fit > 0 and C.green or nil }
  end
  local qi = QuestItems(d)
  if #qi > 0 then
    local fit = Passing(qi)
    extra[#extra + 1] = { key = "quests", title = L["Quest rewards"], h = 28, right = FitText(fit, #qi), markColor = fit > 0 and C.green or nil }
  end
  if #extra > 0 and #out > 0 then out[#out + 1] = { kind = "divider", text = L["More"] } end
  for _, e in ipairs(extra) do out[#out + 1] = e end
  return out
end

local function Find(list, key)
  for _, it in ipairs(list.items or {}) do if it.key ~= nil and it.key == key then return it end end
end

local function Footer(id, d)
  local parts = { ns.InstanceName(id, d) }
  if (d.min or 0) > 0 then parts[#parts + 1] = L["Level %d to %d"]:format(d.min, d.max) end
  local n = #(d.bosses or {})
  parts[#parts + 1] = (n == 1 and L["%d boss"] or L["%d bosses"]):format(n)
  return table.concat(parts, " · ")
end

local function SelectEntry(entry)
  if entry ~= sel.entry then sel.showAll = false end
  sel.entry = entry
  if not ns.DROPS[sel.inst] then return end
  ns.db.last.inst, ns.db.last.entry = sel.inst, entry
  local it = Find(W.bossList, entry)
  W.bossList:Select(it)
  if it then W.bossList:ScrollTo(it) end
  RefreshLoot()
end

local function SelectInstance(id, entry)
  local d = ns.DROPS[id]
  if not (W and d) then return end
  sel.inst = id
  sel.showAll = false
  local it = Find(W.instList, id)
  W.instList:Select(it)
  if it then W.instList:ScrollTo(it) end
  W.instDrop:Update(id)
  local items = BossItems(d)
  W.bossList:SetItems(items, true)
  W.bossHead:SetItem({ kind = "group", static = true, text = L["Bosses"], count = #(d.bosses or {}) })
  W:SetSubtitle(ns.InstanceName(id, d))
  W:SetStatus(Footer(id, d))
  if entry == nil or (type(entry) == "number" and not d.bosses[entry]) then
    entry = nil
    for _, e in ipairs(items) do if e.key ~= nil then entry = e.key break end end
  end
  sel.entry = nil
  if entry ~= nil then SelectEntry(entry) else W.table:SetItems({}, true) end
  if ns.RefreshMini then ns.RefreshMini(true) end
end

local function DefaultInstance()
  local last = ns.db.last
  if last.inst and ns.DROPS[last.inst] then return last.inst, last.entry end
  local lvl = PlayerLevel()
  local best
  for _, e in ipairs(Instances().dungeons) do
    if lvl >= e.d.min and lvl <= e.d.max then best = e.id break end
  end
  if not best then
    local first = Instances().dungeons[1]
    best = first and first.id
  end
  return best
end

-- the instance dropdown of the narrow window: the same groups and colours
local function DropItems()
  local inst, out = Instances(), {}
  for _, g in ipairs({ { "dungeons", L["Dungeons"] }, { "raids", L["Raids"] } }) do
    out[#out + 1] = { header = true, text = g[2] }
    for _, e in ipairs(inst[g[1]]) do
      out[#out + 1] = { value = e.id, text = ns.InstanceName(e.id, e.d), right = LevelText(e.d), rightColor = LevelColor(e.d) }
    end
  end
  return out
end

local function RefreshInstances()
  W.instList:SetItems(InstanceItems())
  W.instList:Select(Find(W.instList, sel.inst))
end

---------------------------------------------------------------------------
-- Layout: three columns; under 800 px the dropdown instead of the instance column
---------------------------------------------------------------------------
function Place(win, w, h, mode)
  if not W or not W.built then return end
  local instW = mode == "full" and 230 or mode == "overlay" and 200 or 0
  local bossW = mode == "full" and 230 or 200
  local lootW = w - instW - bossW
  -- instances
  if instW > 0 then
    W.instCol:Show()
    W.instCol:SetSize(instW, h)
    W.search:Layout(instW - 2 * GAP)
    W.instList:Resize(instW - 1, h - SEARCH)
  else
    W.instCol:Hide()
  end
  -- bosses
  W.bossCol:ClearAllPoints()
  W.bossCol:SetPoint("TOPLEFT", W.body, "TOPLEFT", instW, 0)
  W.bossCol:SetSize(bossW, h)
  local top = 0
  if instW == 0 then
    W.instDrop:Show()
    W.instDrop:Layout(bossW - 2 * GAP)
    W.instDrop:ClearAllPoints()
    W.instDrop:SetPoint("TOPLEFT", W.bossCol, "TOPLEFT", GAP, -6)
    top = SEARCH
  else
    W.instDrop:Hide()
  end
  W.bossHead:ClearAllPoints()
  W.bossHead:SetPoint("TOPLEFT", W.bossCol, "TOPLEFT", 0, -top)
  W.bossHead:SetSize(bossW - 1, HEAD)
  W.bossHead:Layout(bossW - 1)
  W.bossList:ClearAllPoints()
  W.bossList:SetPoint("TOPLEFT", W.bossCol, "TOPLEFT", 0, -(top + HEAD))
  W.bossList:Resize(bossW - 1, h - top - HEAD)
  -- loot
  W.lootCol:ClearAllPoints()
  W.lootCol:SetPoint("TOPLEFT", W.body, "TOPLEFT", instW + bossW, 0)
  W.lootCol:SetSize(lootW, h)
  W.lootHead:SetSize(lootW, HEAD)
  W.lootHead:Layout(lootW)
  -- the bar: two switches, the slot list, the chip on the right; the list gives way when room is short
  local x = GAP + 4
  W.myClass:ClearAllPoints() W.myClass:SetPoint("LEFT", W.bar, "LEFT", x, 0)
  x = x + W.myClass:GetWidth() + 12
  W.usable:ClearAllPoints() W.usable:SetPoint("LEFT", W.bar, "LEFT", x, 0)
  x = x + W.usable:GetWidth() + 12
  local chipW = W.hiddenChip:GetWidth() or 100
  local ddW = math.max(90, math.min(160, lootW - x - chipW - 2 * GAP - 8))
  W.slot:Layout(ddW)
  W.slot:ClearAllPoints() W.slot:SetPoint("LEFT", W.bar, "LEFT", x, 0)
  W.hiddenChip:ClearAllPoints() W.hiddenChip:SetPoint("RIGHT", W.bar, "RIGHT", -GAP - 4, 0)
  W.bar:SetSize(lootW, BAR)
  W.table:ClearAllPoints()
  W.table:SetPoint("TOPLEFT", W.lootCol, "TOPLEFT", 0, -(HEAD + BAR))
  W.table:Layout(lootW, h - HEAD - BAR)
  W.lootW = lootW
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
local function Line(parent, vertical)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetColorTexture(C.goldMuted[1], C.goldMuted[2], C.goldMuted[3], 1)
  if vertical then
    t:SetPoint("TOPRIGHT") t:SetPoint("BOTTOMRIGHT") t:SetWidth(1)
  else
    t:SetPoint("BOTTOMLEFT") t:SetPoint("BOTTOMRIGHT") t:SetHeight(1)
  end
  return t
end

local function Column(parent)
  local f = CreateFrame("Frame", nil, parent)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 1)
  Line(f, true)
  return f
end

local function Build()
  ns.db.win = type(ns.db.win) == "table" and ns.db.win or {}
  W = Kit.Window("DropdonPanel", { title = "Dropdon", logo = "Interface\\Icons\\INV_Misc_Bag_10",
    options = "Dropdon", hint = "/dd options", footer = true, store = ns.db.win, width = 1000, height = 600,
    buttons = { { kind = "collapse", key = "mini", tooltip = L["Small window"],
      onClick = function() ns.HideBig() if ns.ShowMini then ns.ShowMini() end end } },
    onLayout = function(win, w, h, mode) Place(win, w, h, mode) end })
  W:Hide()
  -- instances
  W.instCol = Column(W.body)
  W.instCol:SetPoint("TOPLEFT", W.body, "TOPLEFT", 0, 0)
  W.search = Kit.SearchBox(W.instCol, { placeholder = L["Search instance"], onChange = function(t)
    W.query = tostring(t or ""):lower()
    RefreshInstances()
  end })
  W.search:SetPoint("TOPLEFT", W.instCol, "TOPLEFT", GAP, -6)
  W.instList = Kit.List(W.instCol, {
    onClick = function(it) if it.key then SelectInstance(it.key) end end,
    onToggle = function(it) ns.db.closed[it.group] = it.collapsed and true or nil RefreshInstances() end })
  W.instList:SetPoint("TOPLEFT", W.instCol, "TOPLEFT", 0, -SEARCH)
  -- bosses
  W.bossCol = Column(W.body)
  W.instDrop = Kit.Dropdown(W.bossCol, { width = 180, items = DropItems, get = function() return sel.inst end,
    set = function(v) SelectInstance(v) end })
  W.bossHead = Kit.GroupHeader(W.bossCol)
  W.bossList = Kit.List(W.bossCol, { onClick = function(it) if it.key ~= nil then SelectEntry(it.key) end end })
  -- loot
  W.lootCol = CreateFrame("Frame", nil, W.body)
  W.lootHead = Kit.GroupHeader(W.lootCol)
  W.lootHead:SetPoint("TOPLEFT", W.lootCol, "TOPLEFT", 0, 0)
  W.bar = CreateFrame("Frame", nil, W.lootCol)
  W.bar:SetPoint("TOPLEFT", W.lootCol, "TOPLEFT", 0, -HEAD)
  Line(W.bar)
  local function Switch(key, label, tip)
    local t = Kit.Toggle(W.bar, { label = label, get = function() return ns.Filters()[key] == true end,
      set = function(v) ns.Filters()[key] = v and true or false sel.showAll = false ns.RefreshBig() if ns.RefreshMini then ns.RefreshMini() end end })
    t:SetTooltip(label, { tip })
    return t
  end
  W.myClass = Switch("class", L["My class"], L["Hides items restricted to other classes."])
  W.usable = Switch("usable", L["Usable"], L["Hides armor and weapon types your class cannot use."])
  W.slot = Kit.Dropdown(W.bar, { width = 140,
    items = function()
      local list = { { value = "ALL", text = L["All slots"] } }
      for _, s in ipairs(ns.SLOTS) do list[#list + 1] = { value = s[1], text = ns.SlotLabel(s[1]) } end
      return list
    end,
    get = function() return ns.Filters().slot end,
    set = function(v) ns.Filters().slot = v sel.showAll = false RefreshLoot() end })
  W.slot:SetTooltip(L["Slot"], { L["Click: choose a slot."] })
  W.hiddenChip = Kit.Chip(W.bar, L["Hidden"], function()
    sel.showAll = not sel.showAll
    RefreshLoot(true)
  end)
  W.hiddenChip:SetTooltip(L["Hidden"], { L["Shows the items your filters hide, dimmed, with the reason in the tooltip."] })
  W.table = Kit.Table(W.lootCol, { columns = Columns(),
    onSort = function(key)
      local s = ns.db.sort
      if type(s) ~= "table" then s = {} ns.db.sort = s end
      if s.key == key then s.asc = not s.asc else s.key, s.asc = key, key == "title" end
      W.table:SetSort(s.key, s.asc)
      RefreshLoot(true)
    end })
  if type(ns.db.sort) == "table" and ns.db.sort.key then W.table:SetSort(ns.db.sort.key, ns.db.sort.asc) end
  W.showAll = Kit.Button(W.table, "", { small = true, onClick = function() sel.showAll = true RefreshLoot() end })
  W.showAll:SetPoint("TOP", W.table, "TOP", 0, -24 - 56)
  W.showAll:SetWidth(220)
  W.showAll:Hide()
  W.built = true
  -- size, scale, lock: the options of Dropdon's appearance page
  ns.TrackPanel({
    ApplySettings = function()
      if W.SetOwnScale then W:SetOwnScale(tonumber(ns.db.panelScale) or 1) elseif W.SetScale then W:SetScale(tonumber(ns.db.panelScale) or 1) end
      if W.header and W.header.EnableMouse then W.header:EnableMouse(not ns.db.panelLocked) end
    end,
    ResetPosition = function()
      ns.db.win.point, ns.db.win.relPoint, ns.db.win.x, ns.db.win.y = nil, nil, nil, nil
      W:ClearAllPoints()
      W:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    end,
  })
  -- (Kit minor 13) the size option on top of the shared window scale of all Don windows
  if W.SetOwnScale then W:SetOwnScale(tonumber(ns.db.panelScale) or 1) elseif W.SetScale then W:SetScale(tonumber(ns.db.panelScale) or 1) end
  if W.header and W.header.EnableMouse then W.header:EnableMouse(not ns.db.panelLocked) end
  W:Layout()
  RefreshInstances()
  local id, entry = DefaultInstance()
  if id then SelectInstance(id, entry) end
end

-- For tests and diagnostics: the selection, the lists, the loot table and the ids it shows.
function ns.WindowState() return sel, W and W.instList, W and W.bossList, W and W.table, hiddenCount, lootIDs end
function ns.WindowFrame() return W end
function ns.WindowBar() return W and { class = W.myClass, usable = W.usable, slot = W.slot, chip = W.hiddenChip, showAll = W.showAll } end
-- (tests) what a click on an instance or a boss row does
function ns.WindowSelect(id, entry)
  if not W then return end
  if id ~= nil and id ~= sel.inst then SelectInstance(id, entry) elseif entry ~= nil then SelectEntry(entry) end
end

function ns.DefaultInstance() return DefaultInstance() end

function ns.ToggleBig()
  if not W then Build() end
  if W:IsShown() then
    W:Hide()
  else
    if ns.HideMini then ns.HideMini() end
    ns.db.mode = "big"
    W:Show()
    W:Layout()
  end
end

function ns.BigShown() return W ~= nil and W:IsShown() end

function ns.HideBig()
  if W and W:IsShown() then W:Hide() end
end

-- /dd: the window you used last
function ns.ToggleWindow()
  if ns.MiniShown and ns.MiniShown() then ns.HideMini() return end
  if W and W:IsShown() then W:Hide() return end
  if ns.db.mode == "mini" and ns.ShowMini then ns.ShowMini() else ns.ToggleBig() end
end

-- walked into an instance (or asked for it): select it everywhere
function ns.ShowInstance(id)
  if not ns.DROPS[id] then return end
  ns.db.last.inst, ns.db.last.entry = id, nil
  if W then RefreshInstances() SelectInstance(id) end
  if ns.RefreshMini then ns.RefreshMini(true) end
end

-- (25.10.) a boss or instance name was learned in the game's language: lists and heading again, same selection
function ns.RefreshWindow()
  if W then
    RefreshInstances()
    if sel.inst and ns.DROPS[sel.inst] then SelectInstance(sel.inst, sel.entry) end
  end
  if ns.RefreshMini then ns.RefreshMini() end
end

-- filters changed (here or in the small window): switches, counts of the bosses and the loot again
function ns.RefreshBig()
  if not W then return end
  W.myClass:Update() W.usable:Update() W.slot:Update()
  local d = ns.DROPS[sel.inst]
  if d then
    W.bossList:SetItems(BossItems(d))
    W.bossList:Select(Find(W.bossList, sel.entry))
  end
  if sel.inst and sel.entry ~= nil then RefreshLoot(true) end
end

-- Item names and qualities arrive late: repaint once they do.
local repaint = false
ns.On("GET_ITEM_INFO_RECEIVED", function()
  if repaint or not W or not W:IsShown() or not sel.inst then return end
  repaint = true
  ns.After(0.3, function()
    repaint = false
    if W and W:IsShown() and sel.inst and sel.entry ~= nil then RefreshLoot(true) end
  end)
end)
