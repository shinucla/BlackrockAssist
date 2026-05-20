--[[
  Esc -> Interface -> AddOns -> BlackrockAssist
]]

local ADDON_NAME = "BlackrockAssist"
local BA = _G[ADDON_NAME]

local DEFAULT_AUTO_LIST = "Savory Deviate Delight"

local inspectCheck
local autoCheck
local debugCheck
local raidCheck
local itemListEdit
local itemListBox
local itemListScroll

local SCROLL_WIDTH = 396
local BOX_PAD = 6
local SCROLL_BAR_W = 16
local SCROLL_BAR_FROM_RIGHT = 10
local SCROLL_BAR_TOP_INSET = 20
local SCROLL_BAR_BOTTOM_INSET = 20
local SCROLL_BAR_GAP = 25
local SCROLL_INSET_RIGHT = SCROLL_BAR_FROM_RIGHT + SCROLL_BAR_W + SCROLL_BAR_GAP
local EDIT_WIDTH = SCROLL_WIDTH - BOX_PAD - SCROLL_INSET_RIGHT - 4
local LINE_HEIGHT = 14
local MAX_VISIBLE_LINES = 8
local SCROLL_VIEW_HEIGHT = LINE_HEIGHT * MAX_VISIBLE_LINES + 8

local function trim(s)
  return (s:gsub("^%s+", "")):gsub("%s+$", "")
end

local function PlayCheckSound(checked)
  if checked then
    PlaySound("igMainMenuOptionCheckBoxOn")
  else
    PlaySound("igMainMenuOptionCheckBoxOff")
  end
end

local function CountLines(text)
  if not text or text == "" then
    return 1
  end
  local n = 1
  for _ in string.gmatch(text, "\n") do
    n = n + 1
  end
  return n
end

local function UpdateItemListEditHeight()
  if not itemListEdit then
    return
  end
  local lines = CountLines(itemListEdit:GetText() or "")
  local contentHeight = lines * LINE_HEIGHT + 12
  local minHeight = SCROLL_VIEW_HEIGHT
  itemListEdit:SetHeight(math.max(minHeight, contentHeight))
  if itemListScroll and itemListScroll.UpdateScrollChildRect then
    itemListScroll:UpdateScrollChildRect()
  end
end

local function SaveItemListFromEdit()
  if not itemListEdit or not BA.db then
    return
  end
  BA.db.autoPurchaseList = itemListEdit:GetText() or ""
  if BA.ParseAutoPurchaseList then
    BA:ParseAutoPurchaseList()
  end
  UpdateItemListEditHeight()
end

-- Checkbox row; returns bottom anchor frame for the next row.
local function AddOptionRow(panel, anchor, shortLabel, desc, rowHeight)
  local row = CreateFrame("Frame", nil, panel)
  row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
  row:SetSize(480, rowHeight or 36)

  local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)

  local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  label:SetPoint("TOPLEFT", cb, "TOPRIGHT", 4, -2)
  label:SetWidth(440)
  label:SetJustifyH("LEFT")
  label:SetText(shortLabel)

  if desc and desc ~= "" then
    local tip = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    tip:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    tip:SetWidth(440)
    tip:SetJustifyH("LEFT")
    tip:SetText(desc)
  end

  return cb, row
end

function BA:ParseAutoPurchaseList()
  local text = (self.db and self.db.autoPurchaseList) or DEFAULT_AUTO_LIST
  local names = {}
  local seen = {}
  for line in string.gmatch(text .. "\n", "(.-)\n") do
    line = trim(line)
    if line ~= "" and not seen[line] then
      seen[line] = true
      names[#names + 1] = line
    end
  end
  self._autoPurchaseNames = names
  return names
end

function BA:GetAutoPurchaseNames()
  if not self._autoPurchaseNames then
    self:ParseAutoPurchaseList()
  end
  return self._autoPurchaseNames
end

function BA:RefreshOptionsPanel()
  if not self.optionsPanel or not inspectCheck then
    return
  end
  local db = self.db
  if not db then
    return
  end
  inspectCheck:SetChecked(db.enabled == true)
  autoCheck:SetChecked(db.autoDelight ~= false)
  debugCheck:SetChecked(db.autoDebug == true)
  if raidCheck then
    raidCheck:SetChecked(db.autoRaid == true)
  end
  if itemListEdit then
    itemListEdit:SetText(db.autoPurchaseList or DEFAULT_AUTO_LIST)
    UpdateItemListEditHeight()
  end
end

function BA:ApplyDefaults()
  local db = self.db
  if not db then
    return
  end
  db.enabled = false
  db.autoDelight = true
  db.autoDebug = false
  db.autoRaid = false
  db.autoPurchaseList = DEFAULT_AUTO_LIST
  self:ParseAutoPurchaseList()
  self:ApplyAllSettings(true)
  self:RefreshOptionsPanel()
end

function BA:ApplyAllSettings(quiet)
  local db = self.db
  if not db then
    return
  end
  self:ParseAutoPurchaseList()
  if self.SetInspectorEnabled then
    self:SetInspectorEnabled(db.enabled == true, quiet)
  end
  if BA_SetAutoDelightEnabled then
    BA_SetAutoDelightEnabled(db.autoDelight ~= false, quiet)
  end
  if BA_SetAutoDebug then
    BA_SetAutoDebug(db.autoDebug == true, quiet)
  end
  if BA_SetAutoRaidEnabled then
    BA_SetAutoRaidEnabled(db.autoRaid == true, quiet)
  end
end

function BA:InitOptionsPanel()
  if self.optionsPanel then
    return
  end

  local panel = CreateFrame("Frame", "BlackrockAssistOptionsPanel", UIParent)
  panel.name = "BlackrockAssist"
  panel.addon = ADDON_NAME

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("BlackrockAssist")

  local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  subtitle:SetText("Independent features — enable any combination.")

  local inspectRow
  inspectCheck, inspectRow = AddOptionRow(
    panel,
    subtitle,
    "Frame inspector",
    "Hover UI for glow and frame names. Command: /ba",
    36
  )

  local autoRow
  autoCheck, autoRow = AddOptionRow(
    panel,
    inspectRow,
    "Auto purchase",
    "Auto-click Yes on vendor popup.",
    24
  )

  local listLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  listLabel:SetPoint("TOPLEFT", autoRow, "BOTTOMLEFT", 4, -2)
  listLabel:SetText("Items (one per line, press Enter):")

  itemListBox = CreateFrame("Frame", "BlackrockAssistItemListBox", panel)
  itemListBox:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", 0, -4)
  itemListBox:SetSize(SCROLL_WIDTH, SCROLL_VIEW_HEIGHT)
  itemListBox:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  itemListBox:SetBackdropColor(0, 0, 0, 0.85)

  itemListScroll = CreateFrame("ScrollFrame", "BlackrockAssistItemListScroll", itemListBox, "UIPanelScrollFrameTemplate")
  itemListScroll:SetPoint("TOPLEFT", itemListBox, "TOPLEFT", BOX_PAD, -BOX_PAD)
  itemListScroll:SetPoint("BOTTOMRIGHT", itemListBox, "BOTTOMRIGHT", -SCROLL_INSET_RIGHT, BOX_PAD)

  local scrollBar = _G["BlackrockAssistItemListScrollScrollBar"]
  if not scrollBar and itemListScroll.GetChildren then
    for _, child in ipairs({ itemListScroll:GetChildren() }) do
      if child and child.GetObjectType and child:GetObjectType() == "Slider" then
        scrollBar = child
        break
      end
    end
  end
  if scrollBar then
    scrollBar:ClearAllPoints()
    scrollBar:SetPoint("TOPRIGHT", itemListBox, "TOPRIGHT", -SCROLL_BAR_FROM_RIGHT, -SCROLL_BAR_TOP_INSET)
    scrollBar:SetPoint("BOTTOMRIGHT", itemListBox, "BOTTOMRIGHT", -SCROLL_BAR_FROM_RIGHT, SCROLL_BAR_BOTTOM_INSET)
    scrollBar:SetWidth(SCROLL_BAR_W)
  end

  itemListEdit = CreateFrame("EditBox", "BlackrockAssistItemListEdit", itemListScroll)
  itemListEdit:SetMultiLine(true)
  itemListEdit:SetMaxLetters(4096)
  itemListEdit:SetWidth(EDIT_WIDTH)
  itemListEdit:SetHeight(SCROLL_VIEW_HEIGHT)
  itemListEdit:SetAutoFocus(false)
  itemListEdit:SetFontObject(ChatFontNormal)
  itemListEdit:SetTextInsets(4, 6, 4, 4)
  itemListEdit:EnableMouse(true)
  itemListEdit:SetScript("OnEnterPressed", function(self)
    self:Insert("\n")
  end)
  itemListEdit:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  itemListScroll:SetScrollChild(itemListEdit)

  itemListEdit:SetScript("OnTextChanged", function()
    SaveItemListFromEdit()
  end)
  itemListEdit:SetScript("OnEditFocusLost", function()
    SaveItemListFromEdit()
  end)

  local autoBlock = CreateFrame("Frame", nil, panel)
  autoBlock:SetPoint("TOPLEFT", itemListBox, "BOTTOMLEFT", 0, 0)
  autoBlock:SetSize(1, 1)

  local debugRow
  debugCheck, debugRow = AddOptionRow(
    panel,
    autoBlock,
    "Debug mode",
    "Copyable debug window for popup inspection. Command: /ba dump",
    36
  )

  raidCheck, _ = AddOptionRow(
    panel,
    debugRow,
    "Auto raid",
    "Leader: convert to raid. You {circle}, healers {square}/{moon}/{star}, DPS {skull}/{cross}.",
    36
  )

  inspectCheck:SetScript("OnClick", function(self)
    PlayCheckSound(self:GetChecked())
    BA.db.enabled = self:GetChecked() and true or false
    BA:SetInspectorEnabled(BA.db.enabled, true)
  end)

  autoCheck:SetScript("OnClick", function(self)
    PlayCheckSound(self:GetChecked())
    BA.db.autoDelight = self:GetChecked() and true or false
    if BA_SetAutoDelightEnabled then
      BA_SetAutoDelightEnabled(BA.db.autoDelight, true)
    end
  end)

  debugCheck:SetScript("OnClick", function(self)
    PlayCheckSound(self:GetChecked())
    BA.db.autoDebug = self:GetChecked() and true or false
    if BA_SetAutoDebug then
      BA_SetAutoDebug(BA.db.autoDebug, true)
    end
  end)

  raidCheck:SetScript("OnClick", function(self)
    PlayCheckSound(self:GetChecked())
    BA.db.autoRaid = self:GetChecked() and true or false
    if BA_SetAutoRaidEnabled then
      BA_SetAutoRaidEnabled(BA.db.autoRaid, true)
    end
  end)

  panel.refresh = function()
    BA:RefreshOptionsPanel()
  end

  panel.okay = function()
    SaveItemListFromEdit()
    BA:ApplyAllSettings(true)
    BA:RefreshOptionsPanel()
  end

  panel.cancel = function()
    BA:RefreshOptionsPanel()
    BA:ApplyAllSettings(true)
  end

  panel.default = function()
    BA:ApplyDefaults()
  end

  if InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end

  self.optionsPanel = panel
  self.itemListEdit = itemListEdit
  self:RefreshOptionsPanel()
  self:ParseAutoPurchaseList()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    if BA.db then
      BA:InitOptionsPanel()
    end
  end
end)
