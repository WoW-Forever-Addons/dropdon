local _, ns = ...
local L = ns.L
local Style = ns.Style
local Core = LibStub("DonCore-1.0")
local Kit = Core:Get("Kit", 10) or Core:Get("Kit", 1)
local C = Kit.C

---------------------------------------------------------------------------
-- Small window (02.11.2026, StyleKit 2 step 4, mockup docs/layout_2026-11-02/dropdon/): Style.Panel in the Don look like
-- Questdon's quest list and Leveldon. Head 28: bag, wordmark, the instance in gold; large window, cog, fold, close.
-- First line "Only for me" (a switch: class and usable filters together), then the bosses with a green mark when
-- something fits you and the number on the right. A click on a boss opens its loot as a grid of item symbols
-- (Kit.ItemGrid: tooltip, shift-click links). The grip drags the width (220 to 400, Style.WidthGrip).
---------------------------------------------------------------------------
local WIDTH, MIN_W, MAX_W = 260, 220, 400
local ICON = 28
local panel, gridFrame, grid, mineFrame, mine
local boss -- chosen boss index
local Rebuild
-- (16.11.2026, Blizzard look for all Don addons, pattern Luredon/Panel.lua) with the option blizzLook the panel wears
-- the game's look (DonCore Blizz PanelLook: Style's game look on the game's tooltip box), the switch and the item grid
-- come from the game's blocks. One set of parts per kit, switched live with the option.
local partsOf = {}

local function Instance()
  local id = ns.db.last.inst
  if not (id and ns.DROPS[id]) then id = ns.DefaultInstance and ns.DefaultInstance() end
  return id, id and ns.DROPS[id]
end

local function Passing(b)
  local f, out = ns.Filters(), {}
  for _, id in ipairs(b.items) do
    if ns.PassFilters(id, f) then out[#out + 1] = id end
  end
  return out
end

local function Mine()
  local f = ns.Filters()
  return f.class and f.usable and true or false
end

local function GridWidth()
  return math.max(60, (panel._width or WIDTH) - 2 * (Style.SPACING and Style.SPACING.padX or 8))
end

local function ShowGrid(ids)
  local entries = {}
  for i, id in ipairs(ids) do
    local _, q = ns.ItemName(id)
    entries[i] = { itemID = id, quality = q, tipFallback = ns.TipFallback(id) } -- (05.11.2026) while the game does not know it
  end
  grid:SetItems(entries)
  local h = grid:Layout(GridWidth())
  local c = Style.Content(panel, gridFrame, math.max(h, ICON) + 4)
  c:SetGapBefore(2)
end

function Rebuild()
  if not panel then return end
  local id, d = Instance()
  panel:ClearRows()
  local name = d and ns.InstanceName(id, d) or ""
  -- (18.11.2026, Daniel's picture: "DROPDON  RUINS OF...") in the game's look the instance alone in the game's gold and
  -- normal writing (the panel sets the gold), as the game's own windows name what they show; Don's look keeps its wordmark
  if panel.blizzLook then
    panel:SetTitle(name ~= "" and name or "Dropdon")
  else
    panel:SetTitle("DROPDON" .. (name ~= "" and ("  |c" .. C.txGold.hex .. Kit.Upper(name) .. "|r") or ""))
  end
  if not d then
    Style.Row(panel):SetText(L["Choose an instance."], "textHint")
    return
  end
  mine:SetValue(Mine())
  Style.Content(panel, mineFrame, 26)
  for i, b in ipairs(d.bosses) do
    local list = Passing(b)
    local n = #list
    local bossName = ns.SplitBossName and (ns.SplitBossName(ns.BossName(b))) or ns.BossName(b)
    local row = Style.Row(panel):SetText(bossName, n == 0 and "textHint" or "textPrimary")
      :SetValue(tostring(n), n == 0 and "textHint" or C.txGold)
    row:SetMark(n > 0 and C.green or nil)
    row:SetActive(i == boss)
    row:SetOnClick(function() ns.MiniSelectBoss(i) end)
    if i == boss and n > 0 then ShowGrid(list) end
  end
end

local function Build()
  panel = Style.Panel("DropdonMiniPanel", UIParent, {
    look = "don", logo = "Interface\\Icons\\INV_Misc_Bag_10",
    title = "DROPDON",
    width = WIDTH,
    close = true,
    collapse = true,
    get = ns.PanelGet("panelMini"),
    set = ns.PanelSet("panelMini"),
    defaultPoint = { "LEFT", "LEFT", 40, 80 },
    closeTooltip = { L["Hide window"], nil, L["/dd shows it again."] },
    collapseTooltip = { L["Collapse / expand"], nil, nil },
    -- right to left after fold and close: large window, then the cog of every Don addon (DonCore's Options)
    buttons = { { kind = "expand", key = "big", tooltip = { L["Large window"], nil, nil },
      onClick = function() if ns.ToggleBig then ns.HideMini() ns.ToggleBig() end end },
      { key = "options", donOptions = "Dropdon", hint = "/dd options", onClick = function() ns.OpenOptions() end } },
  })
  ns.TrackPanel(panel)
  if Style.WidthGrip then
    Style.WidthGrip(panel, { min = MIN_W, max = MAX_W, onWidth = function() Rebuild() end,
      tooltip = { L["Window width"], { L["Drag: width of the window."] } } })
  end
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "DropdonMiniPanel") end
  ns.ApplyMiniLook()
end

-- the switch "Only for me" and the item grid from one kit (made once per kit)
local function MakeParts(kit)
  local p = { kit = kit }
  p.mineFrame = CreateFrame("Frame", nil, UIParent)
  p.mine = kit.Toggle(p.mineFrame, { label = L["Only for me"], get = Mine, set = function() ns.MiniToggleMine() end })
  p.mine:SetPoint("LEFT", p.mineFrame, "LEFT", 2, 0)
  p.mine:SetTooltip(L["Only for me"], { L["Hides items restricted to other classes."], L["Hides armor and weapon types your class cannot use."] })
  p.gridFrame = CreateFrame("Frame", nil, UIParent)
  p.grid = kit.ItemGrid(p.gridFrame, { size = ICON, gap = 4 })
  p.grid:SetPoint("TOPLEFT", p.gridFrame, "TOPLEFT", 0, -2)
  return p
end

local function UseParts(p)
  if mineFrame and mineFrame ~= p.mineFrame then mineFrame:Hide() gridFrame:Hide() end
  p.mineFrame:Show() p.gridFrame:Show()
  mineFrame, mine, gridFrame, grid = p.mineFrame, p.mine, p.gridFrame, p.grid
end

-- the option blizzLook (or the client's templates) decides: the game's look or Don's; built anew while shown
function ns.ApplyMiniLook()
  if not panel then return end
  local kit, blizz, Bz = ns.LookKit()
  if blizz then
    if not partsOf[kit] then
      local ok, p = pcall(MakeParts, kit)
      if ok then partsOf[kit] = p else blizz = false end
    end
  end
  if not blizz then kit = Kit end
  local was = panel.blizzLook and true or false
  if blizz and Bz and Bz.PanelLook then
    Bz.PanelLook(panel, true)
  elseif panel.blizzLook then
    local B = Core:Get("Blizz", 3)
    if B then B.PanelLook(panel, false) end
  end
  partsOf[kit] = partsOf[kit] or MakeParts(kit)
  UseParts(partsOf[kit])
  -- the opacity and the rest of the shared settings once more onto the new ground
  if was ~= (panel.blizzLook and true or false) and ns.ApplyPanelSettings then ns.ApplyPanelSettings() end
  if panel:IsShown() then Rebuild() end
end
-- "blizzard" or "kit" (tests, diagnostics)
function ns.MiniLook() return panel and panel.blizzLook and "blizzard" or "kit" end

function ns.MiniSelectBoss(i)
  boss = (boss ~= i) and i or nil
  Rebuild()
end

-- "Only for me": class and usable filters together
function ns.MiniToggleMine()
  local fl = ns.Filters()
  local on = not (fl.class and fl.usable)
  fl.class, fl.usable = on, on
  Rebuild()
  if ns.RefreshBig then ns.RefreshBig() end
end

function ns.MiniShown() return panel ~= nil and panel:IsShown() end

function ns.ShowMini()
  if not panel then Build() end
  ns.db.mode = "mini"
  boss = nil
  Rebuild()
  panel:FadeIn()
end

function ns.HideMini()
  if panel and panel:IsShown() then panel:FadeOut() end
end

function ns.ToggleMini()
  if ns.MiniShown() then
    ns.HideMini()
  else
    if ns.HideBig then ns.HideBig() end
    ns.ShowMini()
  end
end

-- instance changed (walked into a dungeon, chose one in the big window) or items arrived
function ns.RefreshMini(resetBoss)
  if not ns.MiniShown() then return end
  if resetBoss then boss = nil end
  Rebuild()
end

function ns.MiniState() return boss, grid and grid.icons or {}, panel, grid end

local repaint = false
ns.On("GET_ITEM_INFO_RECEIVED", function()
  if repaint or not ns.MiniShown() then return end
  repaint = true
  ns.After(0.3, function()
    repaint = false
    Rebuild()
  end)
end)
