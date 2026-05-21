--[[
  Auto-click "Yes" on honor/token buy popup (CONFIRM_PURCHASE_TOKEN_ITEM).
  Item name: StaticPopup1ItemFrameText / popup.data.name
  Debug: /ba debug on  then open the vendor popup
]]

local ADDON_NAME = "BlackrockAssist"
local BA = _G[ADDON_NAME]

local POPUP_WHICH = "CONFIRM_PURCHASE_TOKEN_ITEM"
local POPUP_YES = "StaticPopup1Button1"
local MAX_POPUPS = 4
local MAX_DUMP_LINES = 50

local STACK_SPLIT_FRAME = "StackSplitFrame"
local STACK_SPLIT_TEXT = "StackSplitText"
local STACK_SPLIT_TARGET = 10
local STACK_SPLIT_CLICK_GAP = 0.12
local STACK_SPLIT_PENDING_SEC = 20

local pollElapsed = 0
local POLL_INTERVAL = 0.05
local lastClickKey
local lastDumpKey
local popupWasVisible = {}
local pendingStackSplit = false
local pendingStackSplitUntil = 0
local stackSplitStep = nil
local stackSplitWait = 0
local stackSplitTargetAmount = STACK_SPLIT_TARGET

-- ---------------------------------------------------------------------------
-- Debug helpers
-- ---------------------------------------------------------------------------

function BA:IsAutoDebug()
  return self.db and self.db.autoDebug == true
end

local function ShortText(s, maxLen)
  if not s or s == "" then
    return "(empty)"
  end
  s = s:gsub("\n", "\\n")
  if #s > (maxLen or 120) then
    return s:sub(1, maxLen or 120) .. "..."
  end
  return s
end

local function StripUI(text)
  if not text or text == "" then
    return ""
  end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  text = text:gsub("|H.-|h%[", ""):gsub("%]|h", "")
  return text
end

local function FrameLine(frame, depth)
  if not frame then
    return nil
  end
  local pad = string.rep("  ", depth or 0)
  local name = (frame.GetName and frame:GetName()) or "<anon>"
  local otype = (frame.GetObjectType and frame:GetObjectType()) or "?"
  local vis = (frame.IsVisible and frame:IsVisible()) and "vis" or "hid"
  local line = pad .. name .. " [" .. otype .. ", " .. vis .. "]"

  if frame.GetText then
    local ok, t = pcall(frame.GetText, frame)
    if ok and t and t ~= "" then
      line = line .. ' text="' .. ShortText(t, 80) .. '"'
    end
  end

  if frame.GetID then
    local id = frame:GetID()
    if id and id ~= 0 then
      line = line .. " id=" .. id
    end
  end

  return line
end

local function WalkFrame(frame, depth, lines, budget)
  if not frame or budget.count >= budget.max then
    return
  end
  local line = FrameLine(frame, depth)
  if line then
    budget.count = budget.count + 1
    lines[#lines + 1] = line
  end

  if frame.GetRegions then
    for _, region in ipairs({ frame:GetRegions() }) do
      if budget.count >= budget.max then
        break
      end
      local rline = FrameLine(region, depth + 1)
      if rline then
        budget.count = budget.count + 1
        lines[#lines + 1] = rline .. " (region)"
      end
    end
  end

  if frame.GetChildren then
    for _, child in ipairs({ frame:GetChildren() }) do
      if budget.count >= budget.max then
        break
      end
      WalkFrame(child, depth + 1, lines, budget)
    end
  end
end

function BA:DumpPopupTree(popupIndex)
  popupIndex = popupIndex or 1
  local popup = _G["StaticPopup" .. popupIndex]
  if not popup then
    self:DebugLine("StaticPopup" .. popupIndex .. " does not exist.")
    return
  end

  self:DebugLine("--- tree StaticPopup" .. popupIndex .. " which=" .. tostring(popup.which) .. " ---")
  local lines = {}
  WalkFrame(popup, 0, lines, { count = 0, max = MAX_DUMP_LINES })
  for i = 1, #lines do
    self:DebugLine(lines[i])
  end
  if #lines >= MAX_DUMP_LINES then
    self:DebugLine("(tree truncated at " .. MAX_DUMP_LINES .. " lines)")
  end
end

function BA:DumpAllPopups()
  if self.RunFullDiagnostic then
    self:RunFullDiagnostic()
  end
end

local function DebugDataTable(data, label)
  if not BA:IsAutoDebug() then
    return
  end
  if type(data) ~= "table" then
    BA:Debug(label .. " data = " .. tostring(data))
    return
  end
  for k, v in pairs(data) do
    BA:Debug(label .. " data." .. tostring(k) .. " = " .. ShortText(tostring(v), 100))
  end
end

-- ---------------------------------------------------------------------------
-- Item / popup detection
-- ---------------------------------------------------------------------------

local function NameMatches(name)
  if not name or name == "" then
    return false, nil
  end
  local plain = StripUI(name)
  local linkName = plain:match("%[(.-)%]")
  local check = linkName or plain
  local list = BA.GetAutoPurchaseNames and BA:GetAutoPurchaseNames() or {}
  for i = 1, #list do
    local item = list[i]
    if item ~= "" and check:find(item, 1, true) then
      return true, item
    end
  end
  return false, nil
end

local function GetItemNameFromPopup(popup, popupIndex)
  if not popup then
    return nil, "no popup"
  end

  local sources = {}

  if type(popup.data) == "table" and popup.data.name then
    sources[#sources + 1] = { src = "popup.data.name", val = popup.data.name }
  end

  local prefix = "StaticPopup" .. (popupIndex or 1)
  local itemText = _G[prefix .. "ItemFrameText"]
  if itemText and itemText.GetText then
    sources[#sources + 1] = { src = prefix .. "ItemFrameText", val = itemText:GetText() }
  end

  local itemFrame = _G[prefix .. "ItemFrame"]
  if itemFrame and itemFrame.link then
    sources[#sources + 1] = { src = prefix .. "ItemFrame.link", val = itemFrame.link }
  end

  local mainText = _G[prefix .. "Text"]
  if mainText and mainText.GetText then
    sources[#sources + 1] = { src = prefix .. "Text", val = mainText:GetText() }
  end

  for i = 1, #sources do
    local s = sources[i]
    if s.val and s.val ~= "" then
      if BA:IsAutoDebug() then
        BA:Debug("item source " .. s.src .. ' = "' .. ShortText(StripUI(s.val), 80) .. '"')
      end
      local plain = StripUI(s.val)
      local linkName = plain:match("%[(.-)%]")
      return linkName or plain, s.src
    end
  end

  return nil, "no item text found"
end

local function PopupIsPurchaseDialog(popup, popupIndex)
  if not popup then
    return false, "no popup"
  end
  if popup.which == POPUP_WHICH then
    return true, "which=" .. POPUP_WHICH
  end
  local prefix = "StaticPopup" .. (popupIndex or 1)
  local itemFrame = _G[prefix .. "ItemFrame"]
  if itemFrame and itemFrame.IsVisible and itemFrame:IsVisible() then
    return true, "ItemFrame visible (which=" .. tostring(popup.which) .. ")"
  end
  return false, "which=" .. tostring(popup.which) .. ", ItemFrame hidden"
end

local function FindActivePurchasePopup()
  for i = 1, MAX_POPUPS do
    local popup = _G["StaticPopup" .. i]
    if popup and popup:IsVisible() then
      local ok, why = PopupIsPurchaseDialog(popup, i)
      if ok then
        return popup, i, why
      end
    end
  end
  return nil, nil, "no visible purchase popup"
end

local function ClickYes(popup, popupIndex)
  local prefix = "StaticPopup" .. (popupIndex or 1)
  local btn = _G[prefix .. "Button1"] or _G[POPUP_YES]
  if not btn then
    return false, "button missing " .. prefix .. "Button1"
  end
  if not btn:IsVisible() then
    return false, prefix .. "Button1 not visible"
  end
  if btn.IsEnabled and not btn:IsEnabled() then
    return false, prefix .. "Button1 disabled"
  end

  local id = (btn.GetID and btn:GetID()) or 1
  if StaticPopup_OnClick and popup then
    StaticPopup_OnClick(popup, id, popup.data)
    return true, "StaticPopup_OnClick id=" .. id
  end
  if btn.Click then
    btn:Click("LeftButton")
    return true, "Button1:Click()"
  end
  local fn = btn.GetScript and btn:GetScript("OnClick")
  if type(fn) == "function" then
    fn(btn, "LeftButton", true)
    return true, "Button1 OnClick script"
  end
  return false, "no click method"
end

local function StackSplitDialogVisible()
  local frame = _G[STACK_SPLIT_FRAME]
  return frame and frame.IsVisible and frame:IsVisible()
end

local function StackSplitTargetAmount()
  local frame = _G[STACK_SPLIT_FRAME]
  if not frame then
    return STACK_SPLIT_TARGET
  end
  local maxStack = tonumber(frame.maxStack) or STACK_SPLIT_TARGET
  if maxStack < 2 then
    return 1
  end
  if STACK_SPLIT_TARGET > maxStack then
    return maxStack
  end
  return STACK_SPLIT_TARGET
end

-- WotLK uses StackSplitFrame.split + StackSplitText; button :Click() does not update the value.
local function SetStackSplitAmount(amount)
  local frame = _G[STACK_SPLIT_FRAME]
  if not frame or not frame:IsVisible() then
    return false, "StackSplitFrame not visible"
  end

  amount = tonumber(amount) or STACK_SPLIT_TARGET
  local maxStack = tonumber(frame.maxStack) or amount
  if maxStack < 2 then
    return false, "maxStack < 2"
  end
  if amount < 1 then
    amount = 1
  end
  if amount > maxStack then
    amount = maxStack
  end

  frame.split = amount
  frame.typing = 0

  local text = _G[STACK_SPLIT_TEXT]
  if text and text.SetText then
    text:SetText(amount)
  end

  local leftBtn = _G["StackSplitLeftButton"]
  local rightBtn = _G["StackSplitRightButton"]
  if leftBtn and leftBtn.Enable and leftBtn.Disable then
    if amount == 1 then
      leftBtn:Disable()
    else
      leftBtn:Enable()
    end
  end
  if rightBtn and rightBtn.Enable and rightBtn.Disable then
    if amount == maxStack then
      rightBtn:Disable()
    else
      rightBtn:Enable()
    end
  end

  return true, "split=" .. amount .. " max=" .. maxStack
end

local function ConfirmStackSplitOkay()
  if StackSplitFrameOkay_Click then
    StackSplitFrameOkay_Click()
    return true, "StackSplitFrameOkay_Click"
  end
  local btn = _G["StackSplitOkayButton"]
  if btn and btn.Click then
    btn:Click("LeftButton")
    return true, "StackSplitOkayButton:Click"
  end
  return false, "no okay handler"
end

local function ResetStackSplitAutomation()
  pendingStackSplit = false
  pendingStackSplitUntil = 0
  stackSplitStep = nil
  stackSplitWait = 0
  stackSplitTargetAmount = STACK_SPLIT_TARGET
end

local function QueueStackSplitAutomation()
  pendingStackSplit = true
  pendingStackSplitUntil = (GetTime and GetTime() or 0) + STACK_SPLIT_PENDING_SEC
  stackSplitTargetAmount = StackSplitTargetAmount()
  stackSplitStep = "set"
  stackSplitWait = STACK_SPLIT_CLICK_GAP
end

local function TryAutoStackSplit(elapsed)
  if not BA:IsAutoDelightEnabled() then
    ResetStackSplitAutomation()
    return
  end

  if not pendingStackSplit then
    return
  end

  local now = GetTime and GetTime() or 0
  if now > pendingStackSplitUntil then
    if BA:IsAutoDebug() then
      BA:Debug("stack split: pending window expired")
    end
    ResetStackSplitAutomation()
    return
  end

  if not StackSplitDialogVisible() then
    return
  end

  elapsed = tonumber(elapsed) or tonumber(arg1) or 0
  stackSplitWait = stackSplitWait - elapsed
  if stackSplitWait > 0 then
    return
  end

  if stackSplitStep == "set" then
    stackSplitTargetAmount = StackSplitTargetAmount()
    local ok, why = SetStackSplitAmount(stackSplitTargetAmount)
    if BA:IsAutoDebug() then
      BA:Debug("stack split set: " .. tostring(why))
    end
    if ok then
      stackSplitStep = "okay"
      stackSplitWait = STACK_SPLIT_CLICK_GAP
    else
      stackSplitWait = STACK_SPLIT_CLICK_GAP
    end
    return
  end

  if stackSplitStep == "okay" then
    local ok, why = ConfirmStackSplitOkay()
    if ok then
      if BA:IsAutoDebug() then
        BA:Debug("stack split okay: " .. tostring(why))
      else
        BA:Print("Stack split set to |cffffffff" .. stackSplitTargetAmount .. "|r and confirmed.")
      end
      ResetStackSplitAutomation()
    else
      if BA:IsAutoDebug() then
        BA:Debug("stack split okay failed: " .. tostring(why))
      end
      stackSplitWait = STACK_SPLIT_CLICK_GAP
    end
  end
end

local function DumpOnPopupShown(popupIndex, reason)
  if not BA:IsAutoDebug() then
    return
  end
  local key = reason .. "|" .. popupIndex .. "|" .. tostring(GetTime and GetTime() or 0)
  if lastDumpKey == key then
    return
  end
  lastDumpKey = key
  BA:Debug("popup shown: " .. reason)
  BA:DumpPopup(popupIndex)
end

-- ---------------------------------------------------------------------------
-- Try auto yes (checks all StaticPopup slots)
-- ---------------------------------------------------------------------------

local function TryAutoYes()
  if not BA:IsAutoDelightEnabled() then
    return
  end

  local popup, popupIndex, findWhy = FindActivePurchasePopup()
  if not popup then
    for i = 1, MAX_POPUPS do
      popupWasVisible[i] = false
    end
    lastClickKey = nil
    if BA:IsAutoDebug() then
      -- only log when something was visible before
    end
    return
  end

  local visKey = popupIndex .. "|" .. tostring(popup.which)
  if not popupWasVisible[popupIndex] then
    popupWasVisible[popupIndex] = true
    DumpOnPopupShown(popupIndex, "became visible which=" .. tostring(popup.which))
  end

  if BA:IsAutoDebug() then
    BA:Debug("TryAutoYes popup" .. popupIndex .. " " .. findWhy)
  end

  local itemName, itemSrc = GetItemNameFromPopup(popup, popupIndex)
  local matched, matchedItem = NameMatches(itemName)
  if not matched then
    if BA:IsAutoDebug() then
      local list = BA.GetAutoPurchaseNames and table.concat(BA:GetAutoPurchaseNames(), ", ") or "(empty)"
      BA:Debug(
        "SKIP: item mismatch. got="
          .. ShortText(tostring(itemName), 60)
          .. " from "
          .. tostring(itemSrc)
          .. " | list=" .. list
      )
    end
    return
  end

  local key = (popup.which or "") .. "|" .. popupIndex .. "|" .. StripUI(itemName or "")
  if lastClickKey == key then
    if BA:IsAutoDebug() then
      BA:Debug("SKIP: already clicked this popup key")
    end
    return
  end

  local clicked, clickWhy = ClickYes(popup, popupIndex)
  if clicked then
    lastClickKey = key
    QueueStackSplitAutomation()
    --BA:Print("Auto-clicked Yes for |cffffffff" .. (matchedItem or itemName) .. "|r (" .. clickWhy .. ").")
    if BA:IsAutoDebug() then
      BA:Debug("CLICK OK: " .. clickWhy .. " (stack split queued)")
    end
  elseif BA:IsAutoDebug() then
    BA:Debug("CLICK FAILED: " .. tostring(clickWhy))
  end
end

local function OnAutoPoll(self, elapsed)
  elapsed = tonumber(elapsed) or tonumber(arg1) or 0
  pollElapsed = pollElapsed + elapsed
  if pollElapsed < POLL_INTERVAL then
    return
  end
  pollElapsed = 0
  TryAutoYes()
  TryAutoStackSplit(elapsed)
end

-- ---------------------------------------------------------------------------
-- Hook StaticPopup_Show (all dialogs when debug; target dialog always)
-- ---------------------------------------------------------------------------

local hookedShow
local hookedOpenStackSplit

local function HookOpenStackSplitFrame()
  if hookedOpenStackSplit or not OpenStackSplitFrame then
    return
  end
  hookedOpenStackSplit = true
  hooksecurefunc("OpenStackSplitFrame", function(maxStack)
    if not BA:IsAutoDelightEnabled() then
      return
    end
    if BA:IsAutoDebug() then
      BA:Debug("OpenStackSplitFrame maxStack=" .. tostring(maxStack))
    end
    QueueStackSplitAutomation()
  end)
end

local function HookStaticPopupShow()
  if hookedShow or not StaticPopup_Show then
    return
  end
  hookedShow = true
  hooksecurefunc("StaticPopup_Show", function(which, text, data)
    local dataCopy
    if type(data) == "table" then
      dataCopy = {}
      for k, v in pairs(data) do
        dataCopy[k] = v
      end
    end
    BA.lastPopupShow = {
      when = date("%Y-%m-%d %H:%M:%S"),
      which = which,
      text = tostring(text),
      data = dataCopy,
    }

    if BA:IsAutoDebug() then
      BA:DebugShow()
      BA:Debug("StaticPopup_Show which=" .. tostring(which))
      BA:Debug("  text=" .. ShortText(tostring(text), 200))
      DebugDataTable(data, " ")
    end

    local tick = CreateFrame("Frame")
    local frames = 0
    tick:SetScript("OnUpdate", function(f)
      frames = frames + 1
      if frames >= 2 then
        f:SetScript("OnUpdate", nil)
        for i = 1, MAX_POPUPS do
          local popup = _G["StaticPopup" .. i]
          if popup and popup:IsVisible() and popup.which == which then
            if BA:IsAutoDebug() then
              DumpOnPopupShown(i, "after StaticPopup_Show(" .. tostring(which) .. ")")
            end
            local dataMatch = type(data) == "table" and NameMatches(data.name)
            if which == POPUP_WHICH or dataMatch then
              TryAutoYes()
            elseif BA:IsAutoDebug() then
              BA:Debug("hook: which is not " .. POPUP_WHICH .. " and data.name does not match")
            end
          end
        end
      end
    end)
  end)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function BA_SetAutoDebug(state, quiet)
  if not BA.db then
    return
  end
  BA.db.autoDebug = state
  if state then
    HookStaticPopupShow()
    if BA.CreateDebugFrame then
      BA:CreateDebugFrame()
    end
    BA:DebugShow()
    if BA.RunFullDiagnostic then
      BA:RunFullDiagnostic()
    end
    if not quiet then
      BA:Print("Debug window open — open vendor popup, click Refresh or /ba dump.")
    end
  else
    BA:DebugHide()
    if not quiet then
      BA:Print("Popup debug logging |cffff0000OFF|r.")
    end
  end
  if BA.UpdateAutoDelight then
    BA:UpdateAutoDelight()
  end
  if BA.RefreshOptionsPanel then
    BA:RefreshOptionsPanel()
  end
end

function BA_SetAutoDelightEnabled(state, quiet)
  if not BA.db then
    return
  end
  BA.db.autoDelight = state
  BA:UpdateAutoDelight()
  if not quiet and BA.Print then
    if state then
      BA:Print("Auto purchase |cff00ff00ON|r (see item list in Interface -> AddOns).")
    else
      BA:Print("Auto purchase is |cffff0000OFF|r.")
    end
  end
  if BA.RefreshOptionsPanel then
    BA:RefreshOptionsPanel()
  end
end

function BA:IsAutoDelightEnabled()
  return self.db and self.db.autoDelight ~= false
end

function BA:UpdateAutoDelight()
  HookStaticPopupShow()
  HookOpenStackSplitFrame()
  if self:IsAutoDelightEnabled() or self:IsAutoDebug() then
    if not self._autoDelightOnUpdate then
      self._autoDelightOnUpdate = function(frame, elapsed)
        OnAutoPoll(frame, elapsed)
      end
    end
  end
  self:MergeOnUpdate()
end

function BA:MergeOnUpdate()
  local inspector = self._inspectorOnUpdate
  local needPoll = self:IsAutoDelightEnabled() or self:IsAutoDebug()
  local autoYes = needPoll and self._autoDelightOnUpdate or nil

  if not inspector and not autoYes then
    self:SetScript("OnUpdate", nil)
    return
  end

  self:SetScript("OnUpdate", function(frame, elapsed)
    elapsed = tonumber(elapsed) or tonumber(arg1) or 0
    if inspector then
      inspector(frame, elapsed)
    end
    if autoYes then
      autoYes(frame, elapsed)
    end
  end)
end

function BA:Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff40d9ffBlackrockAssist:|r " .. msg)
end

local combatClear = CreateFrame("Frame")
combatClear:RegisterEvent("PLAYER_REGEN_DISABLED")
combatClear:SetScript("OnEvent", function()
  lastClickKey = nil
  lastDumpKey = nil
  popupWasVisible = {}
  ResetStackSplitAutomation()
end)
