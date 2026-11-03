local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Item tooltips: one line "Instance - Boss" for every item that drops in a dungeon or raid (18.10.).
-- No hooks: TooltipDataProcessor.AddTooltipPostCall. The index (item -> places) is built on the
-- first tooltip. Switch: /dd tooltip. Quest rewards are not listed.
---------------------------------------------------------------------------
local MAX_LINES = 3
local BAG = "|TInterface\\Icons\\INV_Misc_Bag_10:14:14:0:0:64:64:5:59:5:59|t " -- loot bag in front of the line (Daniel 18.10.)
local index

local function Plain(name)
  return (name:gsub("%s*<[^>]*>%s*$", ""))
end

local function Add(id, text)
  local t = index[id]
  if not t then t = {} index[id] = t end
  for i = 1, #t do if t[i] == text then return end end
  t[#t + 1] = text
end

local function Build()
  index = {}
  local ids = {}
  for id in pairs(ns.DROPS or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, iid in ipairs(ids) do
    local d = ns.DROPS[iid]
    for _, b in ipairs(d.bosses or {}) do
      local text = ns.InstanceName(iid, d) .. " - " .. Plain(ns.BossName(b))
      for _, item in ipairs(b.items or {}) do Add(item, text) end
    end
    for _, item in ipairs(d.common or {}) do Add(item, ns.InstanceName(iid, d) .. " - " .. L["Shared drops"]) end
  end
end

-- (25.10.) names learned in the game's language: the index is built again on the next tooltip
function ns.ResetTooltipIndex() index = nil end

function ns.DropPlaces(itemID)
  if not index then Build() end
  return index[itemID]
end

local function OnItem(tooltip, data)
  if not ns.db or ns.db.tooltip == false then return end
  local id = type(data) == "table" and ns.Num(data.id)
  if not id then return end
  local places = ns.DropPlaces(id)
  if not places then return end
  -- (02.11.2026, StyleKit 2) the gold of the Don style (Kit.C.txGold)
  local Kit = LibStub("DonCore-1.0"):Get("Kit", 1)
  local gold = Kit and Kit.C.txGold or { 0.83, 0.69, 0.35 }
  local n = math.min(#places, MAX_LINES)
  for i = 1, n do pcall(tooltip.AddLine, tooltip, BAG .. places[i], gold[1], gold[2], gold[3]) end
  if #places > n then
    pcall(tooltip.AddLine, tooltip, L["+%d more places"]:format(#places - n), 0.58, 0.57, 0.66)
  end
end

ns.OnInit(function()
  local T = TooltipDataProcessor
  local E = Enum and Enum.TooltipDataType
  if not (T and T.AddTooltipPostCall and E and E.Item) then return end
  pcall(T.AddTooltipPostCall, E.Item, ns.Guard("tooltip:item", OnItem))
end)
