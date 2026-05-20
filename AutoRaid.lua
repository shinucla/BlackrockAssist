--[[
  Auto raid: party leader converts to raid, then role-based raid markers.
  You = {circle}
  Healers (by talent spec) = {square}, {moon}, {star}
  DPS = {skull}, {cross} (then diamond, triangle if more)

  WotLK: ConvertToRaid() must run outside roster events (scheduled).
  Roles use NotifyInspect + GetTalentTabInfo(..., true) on INSPECT_TALENT_READY.
]]

local ADDON_NAME = "BlackrockAssist"
local BA = _G[ADDON_NAME]

local ICON_CIRCLE = 2
local HEALER_ICONS = { 6, 5, 1 }
local DPS_ICONS = { 8, 7, 3, 4 }

local CLASS_HEAL_TABS = {
  PALADIN = { [1] = true },
  PRIEST = { [1] = true, [2] = true },
  SHAMAN = { [3] = true },
  DRUID = { [3] = true },
}

local eventFrame = CreateFrame("Frame")
local scheduler = CreateFrame("Frame")
local inspectTicker = CreateFrame("Frame")

local pendingMarkers = false
local scheduled = false
local lastAction = 0
local COOLDOWN = 2

local scanning = false
local inspectQueue = {}
local unitRoles = {}
local currentInspectUnit = nil
local inspectWait = 0
local INSPECT_TIMEOUT = 3
local INSPECT_GAP = 0.25

local ScheduleTryAutoRaid
local ScheduleInspectStep
local ProcessNextInspect
local StartRoleScan
local TryAutoRaidInternal

local function Now()
  return GetTime and GetTime() or 0
end

function BA:AutoRaidLog(msg)
  if self.Print then
    self:Print("|cffffcc00[Auto raid]|r " .. tostring(msg))
  end
end

function BA:IsAutoRaidEnabled()
  return self.db and self.db.autoRaid == true
end

local function IsGroupLeader()
  if IsRaidLeader and IsRaidLeader() then
    return true
  end
  if IsPartyLeader and IsPartyLeader() then
    return true
  end
  return false
end

local function PlayerInRaid()
  local idx = UnitInRaid("player")
  return idx ~= nil and idx ~= false and idx ~= 0
end

local function InParty()
  if GetPartyMember and GetPartyMember(1) then
    return true
  end
  if GetNumPartyMembers and GetNumPartyMembers() > 0 then
    return true
  end
  return false
end

local function CanConvertToRaid()
  if not IsGroupLeader() then
    return false
  end
  if PlayerInRaid() then
    return false
  end
  if not InParty() then
    return false
  end
  if UnitLevel and UnitLevel("player") < 10 then
    return false
  end
  if HasLFGRestrictions and HasLFGRestrictions() then
    return false
  end
  if InCombatLockdown and InCombatLockdown() then
    return false
  end
  return true
end

local function DoConvertToRaid()
  if type(ConvertToRaid) == "function" then
    ConvertToRaid()
    return "ConvertToRaid()"
  end
  local btn = _G["RaidFrameConvertToRaidButton"]
  if btn and btn.IsShown and btn:IsShown() and btn.IsEnabled and btn:IsEnabled() then
    btn:Click()
    return "RaidFrameConvertToRaidButton:Click()"
  end
  return nil
end

local function GetInspectRole(unit)
  local _, class = UnitClass(unit)
  local healTabs = CLASS_HEAL_TABS[class]
  if not healTabs or not GetTalentTabInfo then
    return "dps"
  end

  local bestTab, bestPoints = 1, 0
  local healPoints = 0
  for tab = 1, 3 do
    local _, _, points = GetTalentTabInfo(tab, true)
    points = points or 0
    if points > bestPoints then
      bestPoints = points
      bestTab = tab
    end
    if healTabs[tab] then
      healPoints = healPoints + points
    end
  end

  if healTabs[bestTab] and bestPoints >= 11 then
    return "healer"
  end
  if healPoints >= 11 and healPoints >= bestPoints then
    return "healer"
  end
  return "dps"
end

local function ApplyRoleMarkers()
  if not IsGroupLeader() or not PlayerInRaid() or not SetRaidTarget then
    return false, "cannot mark"
  end

  SetRaidTarget("player", ICON_CIRCLE)

  local healIdx, dpsIdx = 1, 1
  local summary = { "you={circle}" }

  for i = 1, GetNumRaidMembers() do
    local unit = "raid" .. i
    if UnitExists(unit) and not UnitIsUnit(unit, "player") then
      local role = unitRoles[unit] or "dps"
      local name = UnitName(unit) or unit
      local icon

      if role == "healer" and healIdx <= #HEALER_ICONS then
        icon = HEALER_ICONS[healIdx]
        healIdx = healIdx + 1
        summary[#summary + 1] = name .. "=heal"
      elseif dpsIdx <= #DPS_ICONS then
        icon = DPS_ICONS[dpsIdx]
        dpsIdx = dpsIdx + 1
        summary[#summary + 1] = name .. "=dps"
      end

      if icon then
        SetRaidTarget(unit, icon)
      end
    end
  end

  return true, table.concat(summary, ", ")
end

local function FinishInspectScan()
  scanning = false
  currentInspectUnit = nil
  inspectWait = 0
  inspectTicker:SetScript("OnUpdate", nil)
  if ClearInspectPlayer then
    ClearInspectPlayer()
  end

  local ok, detail = ApplyRoleMarkers()
  if ok then
    pendingMarkers = false
    lastAction = Now()
    BA:AutoRaidLog("Markers: " .. detail)
  end
end

ScheduleTryAutoRaid = function(delay)
  if scheduled then
    return
  end
  scheduled = true
  local wait = delay or 0.15
  local elapsed = 0
  scheduler:SetScript("OnUpdate", function(self, e)
    e = tonumber(e) or tonumber(arg1) or 0
    elapsed = elapsed + e
    if elapsed < wait then
      return
    end
    self:SetScript("OnUpdate", nil)
    scheduled = false
    TryAutoRaidInternal()
  end)
end

ScheduleInspectStep = function(delay)
  scheduler:SetScript("OnUpdate", nil)
  scheduled = true
  local wait = delay or 0.1
  local elapsed = 0
  scheduler:SetScript("OnUpdate", function(self, e)
    e = tonumber(e) or tonumber(arg1) or 0
    elapsed = elapsed + e
    if elapsed < wait then
      return
    end
    self:SetScript("OnUpdate", nil)
    scheduled = false
    ProcessNextInspect()
  end)
end

ProcessNextInspect = function()
  if not scanning then
    return
  end

  if currentInspectUnit then
    return
  end

  if #inspectQueue == 0 then
    FinishInspectScan()
    return
  end

  local unit = table.remove(inspectQueue, 1)
  if not UnitExists(unit) then
    ScheduleInspectStep(INSPECT_GAP)
    return
  end

  local canInspect = true
  if CanInspect then
    canInspect = CanInspect(unit)
  elseif CheckInteractDistance then
    canInspect = CheckInteractDistance(unit, 1)
  end

  if canInspect and NotifyInspect then
    currentInspectUnit = unit
    inspectWait = 0
    NotifyInspect(unit)
    inspectTicker:SetScript("OnUpdate", function(self, elapsed)
      elapsed = tonumber(elapsed) or tonumber(arg1) or 0
      inspectWait = inspectWait + elapsed
      if inspectWait >= INSPECT_TIMEOUT then
        unitRoles[currentInspectUnit] = "dps"
        BA:AutoRaidLog((UnitName(currentInspectUnit) or "?") .. " inspect timeout, treated as dps")
        currentInspectUnit = nil
        ScheduleInspectStep(INSPECT_GAP)
      end
    end)
  else
    unitRoles[unit] = "dps"
    BA:AutoRaidLog((UnitName(unit) or unit) .. " out of range, treated as dps")
    ScheduleInspectStep(INSPECT_GAP)
  end
end

StartRoleScan = function()
  if scanning then
    return
  end
  if not PlayerInRaid() then
    return
  end

  unitRoles = {}
  inspectQueue = {}
  for i = 1, GetNumRaidMembers() do
    local unit = "raid" .. i
    if UnitExists(unit) and not UnitIsUnit(unit, "player") then
      inspectQueue[#inspectQueue + 1] = unit
    end
  end

  if #inspectQueue == 0 then
    local ok, detail = ApplyRoleMarkers()
    if ok then
      BA:AutoRaidLog("Markers: " .. detail)
    end
    return
  end

  scanning = true
  BA:AutoRaidLog("Scanning " .. #inspectQueue .. " member(s) for talents...")
  ProcessNextInspect()
end

TryAutoRaidInternal = function()
  if not BA:IsAutoRaidEnabled() then
    return
  end
  if not IsGroupLeader() then
    pendingMarkers = false
    return
  end

  if PlayerInRaid() then
    StartRoleScan()
    return
  end

  if not CanConvertToRaid() then
    return
  end

  local how = DoConvertToRaid()
  if how then
    pendingMarkers = true
    BA:AutoRaidLog("Converting party to raid via " .. how)
    scheduled = false
    ScheduleTryAutoRaid(0.6)
  else
    BA:AutoRaidLog("Convert failed — open Social (O) -> Raid tab.")
  end
end

local function OnInspectTalentReady()
  if not scanning or not currentInspectUnit then
    return
  end

  local unit = currentInspectUnit
  local role = GetInspectRole(unit)
  unitRoles[unit] = role
  local name = UnitName(unit) or unit
  BA:AutoRaidLog(name .. " detected as " .. role)

  currentInspectUnit = nil
  inspectWait = 0
  inspectTicker:SetScript("OnUpdate", nil)
  if ClearInspectPlayer then
    ClearInspectPlayer()
  end
  ScheduleInspectStep(INSPECT_GAP)
end

local function OnEvent(self, event)
  if not BA:IsAutoRaidEnabled() then
    return
  end

  if event == "INSPECT_TALENT_READY" then
    OnInspectTalentReady()
    return
  end

  if event == "RAID_ROSTER_UPDATE" then
    if pendingMarkers then
      ScheduleTryAutoRaid(0.2)
      return
    end
    if PlayerInRaid() and Now() - lastAction >= COOLDOWN then
      ScheduleTryAutoRaid(0.3)
    end
    return
  end

  if event == "PARTY_MEMBERS_CHANGED" or event == "PARTY_LEADER_CHANGED" then
    scheduled = false
    if pendingMarkers then
      ScheduleTryAutoRaid(0.2)
      return
    end
    if IsGroupLeader() and (InParty() or PlayerInRaid()) then
      ScheduleTryAutoRaid(0.35)
    end
    return
  end

  if event == "PLAYER_ENTERING_WORLD"
    or event == "PLAYER_LOGIN"
    or event == "PLAYER_REGEN_ENABLED" then
    if Now() - lastAction >= COOLDOWN then
      ScheduleTryAutoRaid(0.25)
    end
  end
end

function BA_SetAutoRaidEnabled(state, quiet)
  if not BA.db then
    return
  end
  BA.db.autoRaid = state
  BA:UpdateAutoRaid()

  if state then
    pendingMarkers = false
    ScheduleTryAutoRaid(0.5)
    if not quiet then
      BA:AutoRaidLog("ON — healers: square/moon/star, DPS: skull/cross, you: circle.")
    end
  else
    pendingMarkers = false
    scanning = false
    scheduler:SetScript("OnUpdate", nil)
    inspectTicker:SetScript("OnUpdate", nil)
    scheduled = false
    if not quiet then
      BA:AutoRaidLog("OFF.")
    end
  end

  if BA.RefreshOptionsPanel then
    BA:RefreshOptionsPanel()
  end
end

function BA:UpdateAutoRaid()
  eventFrame:SetScript("OnEvent", OnEvent)
  if self:IsAutoRaidEnabled() then
    eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
    eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PARTY_LEADER_CHANGED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("INSPECT_TALENT_READY")
  else
    eventFrame:UnregisterEvent("PARTY_MEMBERS_CHANGED")
    eventFrame:UnregisterEvent("RAID_ROSTER_UPDATE")
    eventFrame:UnregisterEvent("PARTY_LEADER_CHANGED")
    eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:UnregisterEvent("PLAYER_LOGIN")
    eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:UnregisterEvent("INSPECT_TALENT_READY")
  end
end

function BA_ForceAutoRaid()
  lastAction = 0
  pendingMarkers = false
  scanning = false
  ScheduleTryAutoRaid(0.05)
end
