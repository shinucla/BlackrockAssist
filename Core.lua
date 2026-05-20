--[[
  BlackrockAssist — WotLK 3.3.5a UI frame inspector
  /ba          toggle on/off
  /ba on|off   explicit state
  /ba click <name>  click a named frame's left button (out of combat for secure frames)
]]

local ADDON_NAME = "BlackrockAssist"
local BA = CreateFrame("Frame", ADDON_NAME)

local function trim(s)
  return (s:gsub("^%s+", "")):gsub("%s+$", "")
end
BA:RegisterEvent("ADDON_LOADED")
BA:RegisterEvent("PLAYER_LOGIN")

local db
local enabled = false
local pollElapsed = 0
local POLL_INTERVAL = 0.05
local lastTarget

local anonCounter = 0
local anonIds = setmetatable({}, { __mode = "k" })

-- ---------------------------------------------------------------------------
-- Overlay: border glow + top label (parented to UIParent, anchored to target)
-- ---------------------------------------------------------------------------

local overlay = CreateFrame("Frame", "BlackrockAssistOverlay", UIParent)
overlay:Hide()
overlay:SetFrameStrata("TOOLTIP")
overlay:SetFrameLevel(200)
overlay:EnableMouse(false)

local function MakeEdgeLine(parent, name)
  local tex = parent:CreateTexture(name, "OVERLAY")
  tex:SetBlendMode("ADD")
  tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  tex:SetVertexColor(0.35, 0.85, 1, 0.95)
  return tex
end

local edgeTop = MakeEdgeLine(overlay, "BlackrockAssistEdgeTop")
local edgeBottom = MakeEdgeLine(overlay, "BlackrockAssistEdgeBottom")
local edgeLeft = MakeEdgeLine(overlay, "BlackrockAssistEdgeLeft")
local edgeRight = MakeEdgeLine(overlay, "BlackrockAssistEdgeRight")

local EDGE = 10

local function LayoutEdges(w, h)
  edgeTop:ClearAllPoints()
  edgeTop:SetPoint("BOTTOMLEFT", overlay, "TOPLEFT", -2, -2)
  edgeTop:SetPoint("BOTTOMRIGHT", overlay, "TOPRIGHT", 2, -2)
  edgeTop:SetHeight(EDGE)

  edgeBottom:ClearAllPoints()
  edgeBottom:SetPoint("TOPLEFT", overlay, "BOTTOMLEFT", -2, 2)
  edgeBottom:SetPoint("TOPRIGHT", overlay, "BOTTOMRIGHT", 2, 2)
  edgeBottom:SetHeight(EDGE)

  edgeLeft:ClearAllPoints()
  edgeLeft:SetPoint("TOPRIGHT", overlay, "TOPLEFT", 2, 2)
  edgeLeft:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMLEFT", 2, -2)
  edgeLeft:SetWidth(EDGE)

  edgeRight:ClearAllPoints()
  edgeRight:SetPoint("TOPLEFT", overlay, "TOPRIGHT", -2, 2)
  edgeRight:SetPoint("BOTTOMLEFT", overlay, "BOTTOMRIGHT", -2, -2)
  edgeRight:SetWidth(EDGE)
end

local fill = overlay:CreateTexture(nil, "BACKGROUND")
fill:SetAllPoints(overlay)
fill:SetTexture("Interface\\Buttons\\WHITE8X8")
fill:SetVertexColor(0.2, 0.55, 1, 0.12)
fill:SetBlendMode("ADD")

local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
label:SetPoint("BOTTOM", overlay, "TOP", 0, 6)
label:SetTextColor(0.4, 1, 0.85, 1)
label:SetShadowColor(0, 0, 0, 1)
label:SetShadowOffset(1, -1)

local sublabel = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
sublabel:SetPoint("TOP", label, "BOTTOM", 0, -2)
sublabel:SetTextColor(1, 0.92, 0.5, 1)
sublabel:SetShadowColor(0, 0, 0, 1)
sublabel:SetShadowOffset(1, -1)

-- ---------------------------------------------------------------------------
-- Frame identity helpers
-- ---------------------------------------------------------------------------

local function IsInspectable(frame)
  if not frame or frame == overlay or frame == UIParent or frame == WorldFrame then
    return false
  end
  if not frame.IsVisible or not frame:IsVisible() then
    return false
  end
  local w, h = frame:GetWidth(), frame:GetHeight()
  if not w or not h or w < 2 or h < 2 then
    return false
  end
  return true
end

local function AnonRef(frame)
  local ref = anonIds[frame]
  if not ref then
    anonCounter = anonCounter + 1
    ref = ("BA_Frame_%d"):format(anonCounter)
    anonIds[frame] = ref
  end
  return ref
end

local function GetFrameRef(frame)
  local name = frame:GetName()
  if name and name ~= "" then
    return name, "_G[\"" .. name .. "\"]"
  end

  local id = frame:GetID()
  if id and id ~= 0 then
    local parent = frame:GetParent()
    local pname = parent and parent:GetName()
    if pname and pname ~= "" then
      local ref = ("_G[\"%s\"] -- child GetID() %d"):format(pname, id)
      return ("id:%d (parent %s)"):format(id, pname), ref
    end
    return ("id:%d"):format(id), "frame with GetID() " .. id
  end

  local anon = AnonRef(frame)
  return anon .. " (no global name)", "BA:GetFrame(\"" .. anon .. "\")"
end

local function GetFrameDetails(frame)
  local ref, luaRef = GetFrameRef(frame)
  local otype = frame.GetObjectType and frame:GetObjectType() or "?"
  local parent = frame:GetParent()
  local pname = parent and parent.GetName and parent:GetName()
  local lines = {
    ref,
    ("type: %s"):format(otype),
  }
  if pname and pname ~= "" then
    lines[#lines + 1] = ("parent: %s"):format(pname)
  end
  lines[#lines + 1] = ("lua: %s"):format(luaRef)
  return ref, table.concat(lines, " | ")
end

-- ---------------------------------------------------------------------------
-- Show / hide overlay on target frame
-- ---------------------------------------------------------------------------

local function HideOverlay()
  overlay:Hide()
  lastTarget = nil
end

local function ShowOverlay(frame)
  overlay:ClearAllPoints()
  overlay:SetAllPoints(frame)
  local w, h = frame:GetWidth(), frame:GetHeight()
  LayoutEdges(w, h)

  local ref, detail = GetFrameDetails(frame)
  label:SetText(ref)
  sublabel:SetText(detail)
  overlay:Show()
  lastTarget = frame
end

-- ---------------------------------------------------------------------------
-- Polling GetMouseFocus while enabled
-- ---------------------------------------------------------------------------

local function OnPoll(self, elapsed)
  -- WotLK 3.3.5: OnUpdate passes (frame, elapsed); elapsed may be in arg1
  elapsed = tonumber(elapsed) or tonumber(arg1) or 0
  pollElapsed = pollElapsed + elapsed
  if pollElapsed < POLL_INTERVAL then
    return
  end
  pollElapsed = 0

  local focus = GetMouseFocus()
  if focus == lastTarget then
    if focus and focus:IsVisible() then
      overlay:SetAllPoints(focus)
    else
      HideOverlay()
    end
    return
  end

  if not IsInspectable(focus) then
    HideOverlay()
    return
  end

  ShowOverlay(focus)
end

local function SetEnabled(state, quiet)
  enabled = state
  if db then
    db.enabled = enabled
  end
  BA._inspectorOnUpdate = enabled and function(frame, elapsed)
    OnPoll(frame, elapsed)
  end or nil
  if BA.MergeOnUpdate then
    BA:MergeOnUpdate()
  elseif enabled then
    BA:SetScript("OnUpdate", BA._inspectorOnUpdate)
  else
    BA:SetScript("OnUpdate", nil)
  end
  if not enabled then
    HideOverlay()
  end
  if not quiet then
    if enabled then
      DEFAULT_CHAT_FRAME:AddMessage("|cff40d9ffBlackrockAssist:|r inspector |cff00ff00ON|r — hover UI elements.")
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cff40d9ffBlackrockAssist:|r inspector |cffff0000OFF|r.")
    end
  end
  if BA.RefreshOptionsPanel then
    BA:RefreshOptionsPanel()
  end
end

function BA:SetInspectorEnabled(state, quiet)
  SetEnabled(state, quiet)
end

-- ---------------------------------------------------------------------------
-- Public: resolve anonymous frames captured during hover
-- ---------------------------------------------------------------------------

function BA_GetFrame(ref)
  for frame, id in pairs(anonIds) do
    if id == ref and frame.IsVisible and frame:IsVisible() then
      return frame
    end
  end
end

_G["BA"] = BA
BA.GetFrame = BA_GetFrame

local function ClickNamedFrame(name)
  local frame = _G[name]
  if not frame then
    DEFAULT_CHAT_FRAME:AddMessage("|cff40d9ffBlackrockAssist:|r no global frame named |cffffffff" .. name .. "|r")
    return
  end
  if frame.Click then
    frame:Click("LeftButton")
    DEFAULT_CHAT_FRAME:AddMessage("|cff40d9ffBlackrockAssist:|r Click() on |cffffffff" .. name .. "|r")
    return
  end
  if frame.GetScript then
    local fn = frame:GetScript("OnClick")
    if type(fn) == "function" then
      fn(frame, "LeftButton")
      DEFAULT_CHAT_FRAME:AddMessage("|cff40d9ffBlackrockAssist:|r OnClick on |cffffffff" .. name .. "|r")
      return
    end
  end
  DEFAULT_CHAT_FRAME:AddMessage("|cff40d9ffBlackrockAssist:|r |cffffffff" .. name .. "|r has no Click/OnClick handler.")
end

-- ---------------------------------------------------------------------------
-- Slash: /ba [on|off|click <name>]
-- ---------------------------------------------------------------------------

SLASH_BLACKROCKASSIST1 = "/ba"
SLASH_BLACKROCKASSIST2 = "/blackrockassist"

StaticPopupDialogs["BLACKROCKASSIST_HELP"] = nil

local function PrintHelp()
  DEFAULT_CHAT_FRAME:AddMessage("|cff40d9ffBlackrockAssist|r — UI frame inspector (3.3.5a)")
  DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/ba|r — toggle on/off")
  DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/ba on|r | |cffffffff/ba off|r")
  DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/ba click <FrameName>|r — e.g. /ba click TradeFrameCloseButton")
  DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/ba auto on|r | |cffffffff/ba auto off|r — auto Yes for items in options list")
  DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/ba debug on|r — open debug window; |cffffffff/ba dump|r — refresh copyable dump")
  DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/ba raid on|r | |cffffffff/ba raid off|r | |cffffffff/ba raid now|r — retry convert/markers")
  DEFAULT_CHAT_FRAME:AddMessage("  Esc -> Interface -> AddOns -> BlackrockAssist for all settings.")
  DEFAULT_CHAT_FRAME:AddMessage("Hover a window/button; the label shows the global name or |cffffcc00BA_Frame_N|r ref.")
end

SlashCmdList["BLACKROCKASSIST"] = function(msg)
  msg = trim(msg or ""):lower()
  if msg == "" then
    SetEnabled(not enabled)
    return
  end
  if msg == "on" or msg == "1" or msg == "true" then
    SetEnabled(true)
    return
  end
  if msg == "off" or msg == "0" or msg == "false" then
    SetEnabled(false)
    return
  end
  if msg == "help" or msg == "?" then
    PrintHelp()
    return
  end
  local clickName = msg:match("^click%s+(.+)$")
  if clickName then
    clickName = trim(clickName)
    ClickNamedFrame(clickName)
    return
  end
  if msg == "auto on" or msg == "auto 1" then
    if BA_SetAutoDelightEnabled then
      BA_SetAutoDelightEnabled(true, false)
    end
    return
  end
  if msg == "auto off" or msg == "auto 0" then
    if BA_SetAutoDelightEnabled then
      BA_SetAutoDelightEnabled(false, false)
    end
    return
  end
  if msg == "debug on" or msg == "debug 1" then
    if BA_SetAutoDebug then
      BA_SetAutoDebug(true, false)
    end
    return
  end
  if msg == "debug off" or msg == "debug 0" then
    if BA_SetAutoDebug then
      BA_SetAutoDebug(false, false)
    end
    return
  end
  if msg == "raid on" or msg == "raid 1" then
    if BA_SetAutoRaidEnabled then
      BA_SetAutoRaidEnabled(true, false)
    end
    return
  end
  if msg == "raid off" or msg == "raid 0" then
    if BA_SetAutoRaidEnabled then
      BA_SetAutoRaidEnabled(false, false)
    end
    return
  end
  if msg == "raid now" or msg == "raid try" then
    if BA_ForceAutoRaid then
      BA_ForceAutoRaid()
    end
    return
  end
  if msg == "dump" or msg == "debug dump" then
    if BA.CreateDebugFrame then
      BA:CreateDebugFrame()
    end
    if BA.RunFullDiagnostic then
      BA:RunFullDiagnostic()
    elseif BA.DumpAllPopups then
      BA:DumpAllPopups()
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cff40d9ffBlackrockAssist:|r debug module not loaded.")
    end
    return
  end
  PrintHelp()
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

BA:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    BlackrockAssistDB = BlackrockAssistDB or {}
    db = BlackrockAssistDB
    if db.enabled == nil then
      db.enabled = false
    end
    if db.autoDelight == nil then
      db.autoDelight = true
    end
    if db.autoDebug == nil then
      db.autoDebug = false
    end
    if db.autoPurchaseList == nil then
      db.autoPurchaseList = "Savory Deviate Delight"
    end
    if db.autoRaid == nil then
      db.autoRaid = false
    end
    BA.db = db
    if BA.ParseAutoPurchaseList then
      BA:ParseAutoPurchaseList()
    end
    DEFAULT_CHAT_FRAME:AddMessage(
      "|cff40d9ffBlackrockAssist|r loaded (v1.3.0). Options: Esc -> Interface -> AddOns."
    )
    if BA.InitOptionsPanel then
      BA:InitOptionsPanel()
    end
  elseif event == "PLAYER_LOGIN" then
    if BA.ApplyAllSettings then
      BA:ApplyAllSettings(true)
    else
      SetEnabled(db.enabled == true, true)
      if BA.UpdateAutoDelight then
        BA:UpdateAutoDelight()
      end
    end
    self:UnregisterEvent("PLAYER_LOGIN")
  end
end)
