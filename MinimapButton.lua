local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Minimap button: left click opens the window, right click the small one, drag moves it around the minimap.
-- The button itself comes from DonCore (Libs\DonCore\MinimapButton.lua, DONCORE_PLAN.md step 3).
---------------------------------------------------------------------------
LibStub("DonCore-1.0"):Get("MinimapButton", 1):Attach(ns, {
  name = "DropdonMinimapButton",
  icon = "Interface\\Icons\\INV_Misc_Bag_10",
  angleKey = "minimapAngle", defaultAngle = 160,
  title = ns.WORDMARK,
  hint = function() return L["Left click: window. Right click: small window. Drag: move."] end,
  onLeft = function() if ns.ToggleBig then ns.ToggleBig() end end,
  onRight = function() if ns.ToggleMini then ns.ToggleMini() end end,
})

ns.OnInit(function() ns.SafeCall("minimap button", ns.RefreshMinimapButton) end)
