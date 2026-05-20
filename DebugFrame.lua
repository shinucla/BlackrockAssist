--[[
  Scrollable debug window — select text, Ctrl+C to copy.
  /ba debug on — show window + log popups
  /ba dump     — refresh full diagnostic into window
]]

local ADDON_NAME = "BlackrockAssist"
local BA = _G[ADDON_NAME]

BA.debugLines = BA.debugLines or {}
BA.lastPopupShow = BA.lastPopupShow or nil

local MAX_LINES = 400

local function StripColor(s)
  if not s then
    return ""
  end
  return s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

function BA:DebugClear()
  self.debugLines = {}
  if self.debugEdit then
    self.debugEdit:SetText("")
  end
end

function BA:DebugLine(msg)
  msg = StripColor(tostring(msg))
  local lines = self.debugLines
  lines[#lines + 1] = msg
  while #lines > MAX_LINES do
    table.remove(lines, 1)
  end
  if self.debugFrame and self.debugFrame:IsShown() and self.debugEdit then
    self.debugEdit:Insert(msg .. "\n")
  end
end

function BA:Debug(msg)
  self:DebugLine(msg)
  if self.db and self.db.autoDebug then
    DEFAULT_CHAT_FRAME:AddMessage("|cff888888BA-debug:|r " .. StripColor(tostring(msg)))
  end
end

function BA:DebugSetText(text)
  self.debugLines = {}
  for line in string.gmatch(text .. "\n", "(.-)\n") do
    self.debugLines[#self.debugLines + 1] = line
  end
  if self.debugEdit then
    self.debugEdit:SetText(text)
    self.debugEdit:SetCursorPosition(0)
  end
end

function BA:DebugShow()
  if not self.debugFrame then
    self:CreateDebugFrame()
  end
  self.debugFrame:Show()
end

function BA:DebugHide()
  if self.debugFrame then
    self.debugFrame:Hide()
  end
end

function BA:CreateDebugFrame()
  local f = CreateFrame("Frame", "BlackrockAssistDebugFrame", UIParent)
  f:SetSize(560, 420)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  f:SetBackdropColor(0, 0, 0, 0.92)

  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOP", f, "TOP", 0, -14)
  title:SetText("BlackrockAssist Debug")

  local hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
  hint:SetWidth(520)
  hint:SetText("Click in the box, Ctrl+A select all, Ctrl+C copy. Drag title bar to move.")
  hint:SetJustifyH("CENTER")

  local scroll = CreateFrame("ScrollFrame", "BlackrockAssistDebugScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -52)
  scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -36, 48)

  local edit = CreateFrame("EditBox", "BlackrockAssistDebugEdit", scroll)
  edit:SetMultiLine(true)
  edit:SetMaxLetters(99999)
  edit:SetWidth(480)
  edit:SetHeight(900)
  edit:SetAutoFocus(false)
  edit:SetFontObject(ChatFontNormal)
  edit:SetTextInsets(4, 4, 4, 4)
  edit:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    f:Hide()
  end)
  scroll:SetScrollChild(edit)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
  close:SetScript("OnClick", function()
    f:Hide()
  end)

  local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  clearBtn:SetSize(72, 22)
  clearBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 14)
  clearBtn:SetText("Clear")
  clearBtn:SetScript("OnClick", function()
    BA:DebugClear()
  end)

  local selectBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  selectBtn:SetSize(72, 22)
  selectBtn:SetPoint("LEFT", clearBtn, "RIGHT", 6, 0)
  selectBtn:SetText("SelectAll")
  selectBtn:SetScript("OnClick", function()
    edit:SetFocus()
    local t = edit:GetText() or ""
    if edit.HighlightText then
      edit:HighlightText(0, string.len(t))
    end
  end)

  local dumpBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  dumpBtn:SetSize(72, 22)
  dumpBtn:SetPoint("LEFT", selectBtn, "RIGHT", 6, 0)
  dumpBtn:SetText("Refresh")
  dumpBtn:SetScript("OnClick", function()
    if BA.RunFullDiagnostic then
      BA:RunFullDiagnostic()
    end
  end)

  f:Hide()
  self.debugFrame = f
  self.debugEdit = edit
  self.debugScroll = scroll
end

function BA:RunFullDiagnostic()
  self:DebugShow()
  self:DebugClear()

  self:DebugLine("=== BlackrockAssist diagnostic " .. date("%H:%M:%S") .. " ===")
  self:DebugLine("addon loaded: yes")
  self:DebugLine(
    "autoDelight: "
      .. tostring(self.IsAutoDelightEnabled and self:IsAutoDelightEnabled())
  )
  self:DebugLine(
    "autoDebug: " .. tostring(self.IsAutoDebug and self:IsAutoDebug())
  )
  self:DebugLine("StaticPopup_Show: " .. tostring(StaticPopup_Show ~= nil))
  self:DebugLine("StaticPopup_OnClick: " .. tostring(StaticPopup_OnClick ~= nil))

  if self.lastPopupShow then
    local s = self.lastPopupShow
    self:DebugLine("--- last StaticPopup_Show ---")
    self:DebugLine("  when: " .. tostring(s.when))
    self:DebugLine("  which: " .. tostring(s.which))
    self:DebugLine("  text: " .. tostring(s.text))
    if type(s.data) == "table" then
      for k, v in pairs(s.data) do
        self:DebugLine("  data." .. tostring(k) .. " = " .. tostring(v))
      end
    end
  else
    self:DebugLine("--- last StaticPopup_Show: (none yet) ---")
  end

  self:DebugLine("--- globals ---")
  local names = {
    "StaticPopup1", "StaticPopup1Text", "StaticPopup1ItemFrame",
    "StaticPopup1ItemFrameText", "StaticPopup1Button1", "StaticPopup1Button2",
    "StaticPopup2", "StaticPopup3", "StaticPopup4",
  }
  for i = 1, #names do
    local g = _G[names[i]]
    self:DebugLine(
      "  _G[" .. names[i] .. "] = "
        .. (g and "yes" or "nil")
        .. (g and g.IsVisible and (" visible=" .. tostring(g:IsVisible())) or "")
    )
    if g and names[i]:match("Text$") and g.GetText then
      local t = g:GetText()
      if t and t ~= "" then
        self:DebugLine('    GetText()="' .. t:gsub("\n", "\\n") .. '"')
      end
    end
  end

  self:DebugLine("--- visible StaticPopup slots ---")
  local anyVisible = false
  for i = 1, 4 do
    local popup = _G["StaticPopup" .. i]
    if popup and popup.IsVisible and popup:IsVisible() then
      anyVisible = true
      self:DebugLine("StaticPopup" .. i .. " VISIBLE which=" .. tostring(popup.which))
      if type(popup.data) == "table" then
        for k, v in pairs(popup.data) do
          self:DebugLine("  data." .. tostring(k) .. " = " .. tostring(v))
        end
      end
      if self.DumpPopupTree then
        self:DumpPopupTree(i)
      end
    else
      self:DebugLine("StaticPopup" .. i .. " not visible")
    end
  end

  if not anyVisible then
    self:DebugLine("")
    self:DebugLine("TIP: Open the vendor buy popup, then click Refresh (or /ba dump) again.")
  end

  self:DebugLine("=== end ===")

  if self.debugEdit then
    self.debugEdit:SetText(table.concat(self.debugLines, "\n"))
    self.debugEdit:SetCursorPosition(0)
  end
end
