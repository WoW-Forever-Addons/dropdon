local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Item facts and the three filters: "my class" (class restriction on the
-- item), "usable" (armour and weapon types your class can ever use) and slot.
-- A filter never hides what it cannot judge: unknown items always pass.
---------------------------------------------------------------------------
local ARMOR, WEAPON = 4, 2

local function S(...)
  local t = {}
  for _, v in ipairs({ ... }) do t[v] = true end
  return t
end

-- Armour subclasses: 0 misc (rings, necks, trinkets), 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield,
-- 7 libram, 8 idol, 9 totem. Weapon subclasses: 0 axe, 1 2H axe, 2 bow, 3 gun, 4 mace, 5 2H mace,
-- 6 polearm, 7 sword, 8 2H sword, 10 staff, 13 fist, 15 dagger, 16 thrown, 18 crossbow, 19 wand.
-- Vanilla proficiencies from memory (not yet checked against Forever in the game): where unsure
-- the table allows (rogue axes), because hiding something you can use is worse than showing one you cannot.
local CLASS_USE = {
  WARRIOR = { armor = S(0, 1, 2, 3, 4, 6), weapon = S(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18) },
  PALADIN = { armor = S(0, 1, 2, 3, 4, 6, 7), weapon = S(0, 1, 4, 5, 6, 7, 8) },
  HUNTER = { armor = S(0, 1, 2, 3), weapon = S(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18) },
  ROGUE = { armor = S(0, 1, 2), weapon = S(0, 2, 3, 4, 7, 13, 15, 16, 18) },
  PRIEST = { armor = S(0, 1), weapon = S(4, 10, 15, 19) },
  SHAMAN = { armor = S(0, 1, 2, 3, 6, 9), weapon = S(0, 1, 4, 5, 10, 13, 15) },
  MAGE = { armor = S(0, 1), weapon = S(7, 10, 15, 19) },
  WARLOCK = { armor = S(0, 1), weapon = S(7, 10, 15, 19) },
  DRUID = { armor = S(0, 1, 2, 8), weapon = S(4, 5, 6, 10, 13, 15) },
}

local function MyClass()
  local ok, name, token = pcall(UnitClass, "player")
  if not ok then return nil, {} end
  local names = {}
  if ns.Str(name) then names[#names + 1] = name end
  for _, g in ipairs({ "LOCALIZED_CLASS_NAMES_MALE", "LOCALIZED_CLASS_NAMES_FEMALE" }) do
    local t = rawget(_G, g)
    if type(t) == "table" and token and ns.Str(t[token]) then names[#names + 1] = t[token] end
  end
  return ns.Str(token), names
end

---------------------------------------------------------------------------
-- Facts that need no server answer (GetItemInfoInstant)
---------------------------------------------------------------------------
local meta = {}

function ns.ItemMeta(id)
  local m = meta[id]
  if m then return m end
  local get = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if type(get) ~= "function" then return { id = id } end
  local ok, _, typeText, subText, equipLoc, icon, classID, subID = pcall(get, id)
  if not ok or not icon then return { id = id } end
  m = { id = id, typeText = ns.Str(typeText), subText = ns.Str(subText), equipLoc = ns.Str(equipLoc) or "",
    icon = icon, classID = ns.Num(classID), subID = ns.Num(subID), known = true }
  meta[id] = m
  return m
end

-- name, quality once the client has the item (nil before)
function ns.ItemName(id)
  local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if type(get) ~= "function" then return nil end
  local ok, name, _, quality = pcall(get, id)
  if ok and ns.Str(name) then return name, ns.Num(quality) end
  return nil
end

-- (02.11.2026, StyleKit 2 step 4) item level and required level once the client has the item (nil before; 0 counts as none)
function ns.ItemLevels(id)
  local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if type(get) ~= "function" then return nil end
  local ok, name, _, _, ilvl, req = pcall(get, id)
  if not (ok and ns.Str(name)) then return nil end
  ilvl, req = ns.Num(ilvl), ns.Num(req)
  return (ilvl and ilvl > 0) and ilvl or nil, (req and req > 0) and req or nil
end

function ns.QualityColor(quality)
  local t = rawget(_G, "ITEM_QUALITY_COLORS")
  local c = type(t) == "table" and quality and t[quality]
  if c then return c.r, c.g, c.b end
  return 0.35, 0.37, 0.40
end

-- armour or weapon your class can never use -> false; everything else (and unknown) -> true
function ns.UsableByClass(m)
  if not m.known or not m.classID then return true end
  local token = MyClass()
  local use = token and CLASS_USE[token]
  if not use then return true end
  if m.classID == ARMOR then return m.subID == nil or use.armor[m.subID] == true or m.subID > 9 end
  if m.classID == WEAPON then return m.subID == nil or use.weapon[m.subID] == true end
  return true
end

---------------------------------------------------------------------------
-- Class restriction ("Classes: Mage, Warlock") from the item tooltip
---------------------------------------------------------------------------
local classCache = {}

local function TooltipLines(id)
  local api = C_TooltipInfo
  if not api then return nil end
  local data
  if type(api.GetItemByID) == "function" then
    data = ns.Value(api.GetItemByID, id)
  elseif type(api.GetHyperlink) == "function" then
    data = ns.Value(api.GetHyperlink, "item:" .. id)
  end
  local lines = type(data) == "table" and data.lines
  if type(lines) ~= "table" or not ns.Usable(lines) then return nil end
  return lines
end

-- true: you may use it (or no restriction), false: restricted to other classes, nil: not known yet
function ns.ClassAllowed(id)
  local c = classCache[id]
  if c ~= nil then return c end
  local lines = TooltipLines(id)
  if not lines or #lines < 2 then return nil end -- item not loaded yet: only the name line, if any
  local fmt = ns.Str(rawget(_G, "ITEM_CLASSES_ALLOWED"))
  local prefix = fmt and (fmt:match("^(.-)%%") or fmt)
  local _, names = MyClass()
  if not prefix or prefix == "" or #names == 0 then return nil end
  local result = true
  for _, line in ipairs(lines) do
    local text = type(line) == "table" and ns.Str(line.leftText)
    if text and text:sub(1, #prefix) == prefix then
      result = false
      for _, n in ipairs(names) do
        if text:find(n, #prefix + 1, true) then result = true break end
      end
      break
    end
  end
  classCache[id] = result
  return result
end

---------------------------------------------------------------------------
-- Slots
---------------------------------------------------------------------------
-- { key, English label, global with the client's label, equip locations }
ns.SLOTS = {
  { "HEAD", "Head", "INVTYPE_HEAD", { "INVTYPE_HEAD" } },
  { "NECK", "Neck", "INVTYPE_NECK", { "INVTYPE_NECK" } },
  { "SHOULDER", "Shoulders", "INVTYPE_SHOULDER", { "INVTYPE_SHOULDER" } },
  { "CLOAK", "Back", "INVTYPE_CLOAK", { "INVTYPE_CLOAK" } },
  { "CHEST", "Chest", "INVTYPE_CHEST", { "INVTYPE_CHEST", "INVTYPE_ROBE" } },
  { "WRIST", "Wrists", "INVTYPE_WRIST", { "INVTYPE_WRIST" } },
  { "HANDS", "Hands", "INVTYPE_HAND", { "INVTYPE_HAND" } },
  { "WAIST", "Waist", "INVTYPE_WAIST", { "INVTYPE_WAIST" } },
  { "LEGS", "Legs", "INVTYPE_LEGS", { "INVTYPE_LEGS" } },
  { "FEET", "Feet", "INVTYPE_FEET", { "INVTYPE_FEET" } },
  { "FINGER", "Rings", "INVTYPE_FINGER", { "INVTYPE_FINGER" } },
  { "TRINKET", "Trinkets", "INVTYPE_TRINKET", { "INVTYPE_TRINKET" } },
  { "WEAPON", "Weapons", "WEAPON", { "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND" } },
  { "OFFHAND", "Off hand", "SECONDARYHANDSLOT", { "INVTYPE_SHIELD", "INVTYPE_HOLDABLE" } },
  { "RANGED", "Ranged", "RANGEDSLOT", { "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_RELIC" } },
}

local slotOf = {}
for _, s in ipairs(ns.SLOTS) do
  for _, loc in ipairs(s[4]) do slotOf[loc] = s[1] end
end

function ns.SlotLabel(key)
  if key == "ALL" then return L["All"] end
  for _, s in ipairs(ns.SLOTS) do
    if s[1] == key then return ns.Str(rawget(_G, s[3])) or L[s[2]] end
  end
  return L["All"]
end

function ns.NextSlot(key, step)
  local order = { "ALL" }
  for _, s in ipairs(ns.SLOTS) do order[#order + 1] = s[1] end
  local at = 1
  for i, k in ipairs(order) do if k == key then at = i end end
  at = ((at - 1 + step) % #order) + 1
  return order[at]
end

---------------------------------------------------------------------------
-- Filters (saved)
---------------------------------------------------------------------------
function ns.Filters()
  local f = ns.db.filters
  if f.class == nil then f.class = true end
  if f.usable == nil then f.usable = true end
  if type(f.slot) ~= "string" then f.slot = "ALL" end
  return f
end

-- true when the item stays in the list
function ns.PassFilters(id, f)
  local m = ns.ItemMeta(id)
  if f.slot ~= "ALL" and slotOf[m.equipLoc or ""] ~= f.slot then return false end
  if f.usable and not ns.UsableByClass(m) then return false end
  if f.class and ns.ClassAllowed(id) == false then return false end
  return true
end

---------------------------------------------------------------------------
-- (04.11.2026, Era-Test) Classic Era: the data carries WoW Forever's own items (ids from 270000 and more), which the
-- Era client does not know; they stayed "Loading item..." for good. On Era those items leave the data once at load,
-- so no list, count, progress or tooltip line sees them. Forever keeps everything.
-- Era = interface below 16000 (Forever 1.60 is 16001) and not WOW_PROJECT_CAMELOT; WOW_PROJECT_ID alone is not
-- enough (FOREVER_FACTS: it was 1 on an early Forever build).
---------------------------------------------------------------------------
function ns.IsEra()
  if WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT then return false end
  local ok, _, _, _, toc = pcall(GetBuildInfo)
  toc = ok and ns.Num(toc)
  return toc ~= nil and toc > 0 and toc < 16000
end

-- false only when the client says so: C_Item.DoesItemExistByID false (or missing) and no instant facts (no icon)
function ns.ItemExists(id)
  local exists = C_Item and C_Item.DoesItemExistByID
  if type(exists) == "function" then
    local ok, r = pcall(exists, id)
    if ok and r == true then return true end
  end
  local get = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if type(get) ~= "function" then return type(exists) ~= "function" end
  local ok, _, _, _, _, icon = pcall(get, id)
  return ok and icon ~= nil
end

local function Keep(list)
  if type(list) ~= "table" then return list, 0 end
  local out, gone = {}, 0
  for _, id in ipairs(list) do
    if ns.ItemExists(id) then out[#out + 1] = id else gone = gone + 1 end
  end
  return out, gone
end

-- removes the items the client does not know (only on Era); returns how many went
function ns.PruneUnknownItems(force)
  if not (force or ns.IsEra()) then return 0 end
  local gone = 0
  for _, d in pairs(ns.DROPS or {}) do
    local n
    for _, b in ipairs(d.bosses or {}) do b.items, n = Keep(b.items) gone = gone + n end
    for _, q in ipairs(d.quests or {}) do q.items, n = Keep(q.items) gone = gone + n end
    if d.common then d.common, n = Keep(d.common) gone = gone + n end
  end
  ns.prunedItems = gone
  return gone
end
ns.PruneUnknownItems()

-- why the item is not for you (for the tile), or nil
function ns.NotForYou(id)
  local m = ns.ItemMeta(id)
  if not ns.UsableByClass(m) then return L["Your class cannot use this type."] end
  if ns.ClassAllowed(id) == false then return L["Restricted to other classes."] end
  return nil
end
