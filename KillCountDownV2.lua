-- Create the frame for the options panel
local optionsFrame = CreateFrame("Frame", "KillCountDownOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
optionsFrame:SetSize(300, 300)
optionsFrame:SetPoint("CENTER")
optionsFrame:Hide() -- Hideen by default duh


optionsFrame:SetScript("OnShow", function(self)
    self:EnableKeyboard(true)
    self:Raise()
end)

optionsFrame:SetScript("OnHide", function(self)
    self:EnableKeyboard(false)
end)

optionsFrame:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
        self:Hide()
        self:SetPropagateKeyboardInput(false)
    else
        self:SetPropagateKeyboardInput(true)
    end
end)

-- Title for the frame
local title = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
title:SetPoint("TOP", optionsFrame, "TOP", 0, -10)
title:SetText("KillCount Options")

-- Saved Variables
--
-- IMPORTANT: We do NOT touch KillCountDownDB here at file-load time.
-- WoW only injects the real saved data from the SavedVariables file into
-- KillCountDownDB *after* all of this addon's Lua files finish executing,
-- right before ADDON_LOADED fires. If we build/populate the table here,
-- WoW's later restoration simply overwrites our reference wholesale, which
-- is why fields like logWindow kept coming back nil - this is what "This
-- code doesn't seem to keep the saved DB" was actually running into.
--
-- Instead, InitializeSavedVariables() is defined here but only called from
-- the ADDON_LOADED handler further down, once KillCountDownDB is guaranteed
-- to already be the real (or first-time-empty) saved table.

local DEFAULT_LOG_WINDOW = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 0,
    width = 420,
    height = 360,
}

local function InitializeSavedVariables()
    KillCountDownDB = KillCountDownDB or {}

    if KillCountDownDB.modifiedDisplay == nil then
        KillCountDownDB.modifiedDisplay = false
    end

    if KillCountDownDB.notificationsEnabled == nil then
        KillCountDownDB.notificationsEnabled = true
    end

    if KillCountDownDB.timerActive == nil then
        KillCountDownDB.timerActive = false
    end

    -- Kill log lives in its own per-character saved variable (see the .toc
    -- note below) so it doesn't get shared across every toon on the account.
    KillCountDownCharDB = KillCountDownCharDB or {}
    if KillCountDownCharDB.killLog == nil then
        KillCountDownCharDB.killLog = {}
    end

    if KillCountDownDB.logWindow == nil then
        KillCountDownDB.logWindow = {
            point = DEFAULT_LOG_WINDOW.point,
            relativePoint = DEFAULT_LOG_WINDOW.relativePoint,
            x = DEFAULT_LOG_WINDOW.x,
            y = DEFAULT_LOG_WINDOW.y,
            width = DEFAULT_LOG_WINDOW.width,
            height = DEFAULT_LOG_WINDOW.height,
        }
    end
end

local combatStartTime = 0
local pendingKills = {}

local sessionStartTime = 0
local sessionXP = 0

local lastXP = 0
local lastKillXP = 0

-- Button: Toggle Modified Display
local modifiedDisplayButton = CreateFrame("Button", nil, optionsFrame, "GameMenuButtonTemplate")
modifiedDisplayButton:SetSize(200, 30)
modifiedDisplayButton:SetPoint("TOP", optionsFrame, "TOP", 0, -40)
modifiedDisplayButton:SetNormalFontObject("GameFontNormalLarge")

local function updateModifiedDisplayButton()
    modifiedDisplayButton:SetText(
        KillCountDownDB.modifiedDisplay
        and "Modified Display: ON"
        or "Modified Display: OFF"
    )
end

local function toggleModifiedDisplay()
    KillCountDownDB.modifiedDisplay =
        not KillCountDownDB.modifiedDisplay

    updateModifiedDisplayButton()
end

modifiedDisplayButton:SetScript("OnClick", toggleModifiedDisplay)

-- Button: Toggle Notifications
local notificationsButton = CreateFrame("Button", nil, optionsFrame, "GameMenuButtonTemplate")
notificationsButton:SetSize(200, 30)
notificationsButton:SetPoint("TOP", modifiedDisplayButton, "BOTTOM", 0, -20)

local function updateNotificationsButton()
    notificationsButton:SetText(
        KillCountDownDB.notificationsEnabled
        and "Notifications: ON"
        or "Notifications: OFF"
    )
end

local function toggleNotifications()
    KillCountDownDB.notificationsEnabled =
        not KillCountDownDB.notificationsEnabled

    updateNotificationsButton()
end

notificationsButton:SetScript("OnClick", toggleNotifications)

-- Button: Toggle Combat Timer
local timerButton = CreateFrame("Button", nil, optionsFrame, "GameMenuButtonTemplate")
timerButton:SetSize(200, 30)
timerButton:SetPoint("TOP", notificationsButton, "BOTTOM", 0, -20)

local function updateTimerButton()
    timerButton:SetText(
        KillCountDownDB.timerActive
        and "Show Timer: ON"
        or "Show Timer: OFF"
    )
end

local function toggleTimer()
    KillCountDownDB.timerActive =
        not KillCountDownDB.timerActive

    updateTimerButton()
end

timerButton:SetScript("OnClick", toggleTimer)

------------------------------------------------------------
-- Kill Log Window (separate, closable/hideable frame)
------------------------------------------------------------

local killLogFrame = CreateFrame("Frame", "KillCountDownLogFrame", UIParent, "BasicFrameTemplateWithInset")

-- Placeholder size/position at load time. KillCountDownDB.logWindow doesn't
-- exist yet here (see the Saved Variables note above) - the real saved
-- position/size gets applied to this frame once ADDON_LOADED fires and
-- InitializeSavedVariables() has run.
killLogFrame:SetSize(DEFAULT_LOG_WINDOW.width, DEFAULT_LOG_WINDOW.height)
killLogFrame:SetPoint(
    DEFAULT_LOG_WINDOW.point,
    UIParent,
    DEFAULT_LOG_WINDOW.relativePoint,
    DEFAULT_LOG_WINDOW.x,
    DEFAULT_LOG_WINDOW.y
)

killLogFrame:SetMovable(true)
killLogFrame:SetResizable(true)
killLogFrame:EnableMouse(true)
killLogFrame:SetClampedToScreen(true)

-- Min/max resize bounds (API differs by client version, so support both)
if killLogFrame.SetResizeBounds then
    killLogFrame:SetResizeBounds(300, 200, 800, 700) -- modern retail API
elseif killLogFrame.SetMinResize then
    killLogFrame:SetMinResize(300, 200)
    killLogFrame:SetMaxResize(800, 700)
end

killLogFrame:Hide()

-- Apply the real saved position/size once KillCountDownDB.logWindow exists
-- (called from ADDON_LOADED, after InitializeSavedVariables() has run)
local function applyKillLogWindowState()
    local saved = KillCountDownDB.logWindow
    killLogFrame:ClearAllPoints()
    killLogFrame:SetSize(saved.width, saved.height)
    killLogFrame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
end

-- Persist whatever position/size the player leaves it at
local function saveKillLogWindowState()
    local point, _, relativePoint, x, y = killLogFrame:GetPoint()
    KillCountDownDB.logWindow.point = point
    KillCountDownDB.logWindow.relativePoint = relativePoint
    KillCountDownDB.logWindow.x = x
    KillCountDownDB.logWindow.y = y
    KillCountDownDB.logWindow.width = killLogFrame:GetWidth()
    KillCountDownDB.logWindow.height = killLogFrame:GetHeight()
end

killLogFrame:RegisterForDrag("LeftButton")
killLogFrame:SetScript("OnDragStart", killLogFrame.StartMoving)
killLogFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    saveKillLogWindowState()
end)

local killLogTitle = killLogFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
killLogTitle:SetPoint("TOP", killLogFrame, "TOP", 0, -6)
killLogTitle:SetText("KillCountDown - Kill Log")

-- Scroll frame + content child
local killLogScroll = CreateFrame("ScrollFrame", "KillCountDownLogScrollFrame", killLogFrame, "UIPanelScrollFrameTemplate")
killLogScroll:SetPoint("TOPLEFT", killLogFrame, "TOPLEFT", 12, -30)
killLogScroll:SetPoint("BOTTOMRIGHT", killLogFrame, "BOTTOMRIGHT", -30, 44)

local killLogContent = CreateFrame("Frame", nil, killLogScroll)
killLogContent:SetSize(1, 1)
killLogScroll:SetScrollChild(killLogContent)

-- Forward declaration so earlier handlers (e.g. the resize grip) can call this
-- before its full definition later in this section.
local refreshKillLogWindow

-- Clear Log button
local clearLogButton = CreateFrame("Button", nil, killLogFrame, "GameMenuButtonTemplate")
clearLogButton:SetSize(120, 24)
clearLogButton:SetPoint("BOTTOMLEFT", killLogFrame, "BOTTOMLEFT", 14, 10)
clearLogButton:SetText("Clear Log")

-- Close button (extra, bottom-right, in addition to the built-in X)
local closeLogButton = CreateFrame("Button", nil, killLogFrame, "GameMenuButtonTemplate")
closeLogButton:SetSize(120, 24)
closeLogButton:SetPoint("BOTTOMRIGHT", killLogFrame, "BOTTOMRIGHT", -14, 10)
closeLogButton:SetText("Close")
closeLogButton:SetScript("OnClick", function() killLogFrame:Hide() end)

-- Resize grip (bottom-right corner) - drag to resize the window
local resizeGrip = CreateFrame("Button", nil, killLogFrame)
resizeGrip:SetSize(16, 16)
resizeGrip:SetPoint("BOTTOMRIGHT", killLogFrame, "BOTTOMRIGHT", -4, 4)
resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

resizeGrip:SetScript("OnMouseDown", function()
    killLogFrame:StartSizing("BOTTOMRIGHT")
end)

resizeGrip:SetScript("OnMouseUp", function()
    killLogFrame:StopMovingOrSizing()
    saveKillLogWindowState()
    refreshKillLogWindow()
end)

-- Pool of reusable FontStrings so we don't leak objects on every refresh
local logEntryPool = {}
local logEmptyText

local ROW_HEIGHT = 16

refreshKillLogWindow = function()
    local log = KillCountDownCharDB.killLog
    local count = #log

    for _, fs in ipairs(logEntryPool) do
        fs:Hide()
    end

    if count == 0 then
        if not logEmptyText then
            logEmptyText = killLogContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            logEmptyText:SetPoint("TOPLEFT", killLogContent, "TOPLEFT", 4, -4)
        end
        logEmptyText:SetText("Kill Log is empty.")
        logEmptyText:Show()
        killLogContent:SetSize(killLogScroll:GetWidth(), killLogScroll:GetHeight())
        return
    elseif logEmptyText then
        logEmptyText:Hide()
    end

    -- Most recent kill on top
    local row = 0
    for i = count, 1, -1 do
        local entry = log[i]
        row = row + 1

        local fs = logEntryPool[row]
        if not fs then
            fs = killLogContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetPoint("RIGHT", killLogContent, "RIGHT", -4, 0)
            fs:SetJustifyH("LEFT")
            fs:SetHeight(ROW_HEIGHT)
            logEntryPool[row] = fs
        end

        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", killLogContent, "TOPLEFT", 4, -4 - (row - 1) * ROW_HEIGHT)
        fs:SetPoint("RIGHT", killLogContent, "RIGHT", -4, 0)
        fs:SetText(
            "|cffaaaaaa[" .. entry.time .. "]|r " ..
            entry.name ..
            " |cff88ff88(Lvl " .. entry.level .. ")|r" ..
            " - |cffffff00" .. entry.xp .. " XP|r"
        )
        fs:Show()
    end

    killLogContent:SetSize(killLogScroll:GetWidth(), math.max(count * ROW_HEIGHT + 8, killLogScroll:GetHeight()))
end

clearLogButton:SetScript("OnClick", function()
    wipe(KillCountDownCharDB.killLog)
    refreshKillLogWindow()
    print("KillCountDown: Kill log cleared.")
end)

killLogFrame:SetScript("OnShow", function(self)
    refreshKillLogWindow()
    self:EnableKeyboard(true)
    self:Raise()
end)

killLogFrame:SetScript("OnHide", function(self)
    self:EnableKeyboard(false)
end)

killLogFrame:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
        self:Hide()
        self:SetPropagateKeyboardInput(false)
    else
        self:SetPropagateKeyboardInput(true)
    end
end)

-- Toggles the kill log window (used by both the options button and /kcdlog)
local function displayKillLog()
    if killLogFrame:IsShown() then
        killLogFrame:Hide()
    else
        refreshKillLogWindow()
        killLogFrame:Show()
    end
end

------------------------------------------------------------

-- Button: Show Kill Log (opens the window instead of printing to chat)
local logButton = CreateFrame("Button", nil, optionsFrame, "GameMenuButtonTemplate")
logButton:SetSize(200, 30)
logButton:SetPoint("TOP", timerButton, "BOTTOM", 0, -20)
logButton:SetText("Show Kill Log")
logButton:SetScript("OnClick", displayKillLog)

------------------------------------------------------------
-- Shared namespace
--
-- optionsFrame and its buttons above are all `local` to this file, so a
-- second addon file (e.g. a level-stamp module) can't reach them directly.
-- This small global table is the hand-off point: other files can call
-- KillCountDown.AddOptionsButton(...) to stack a new button onto the
-- options panel (growing the frame to fit) without needing anything else
-- from this file.
------------------------------------------------------------
KillCountDown = KillCountDown or {}
KillCountDown.optionsFrame = optionsFrame

local lastOptionsButton = logButton

function KillCountDown.AddOptionsButton(text, onClick)
    local button = CreateFrame("Button", nil, optionsFrame, "GameMenuButtonTemplate")
    button:SetSize(200, 30)
    button:SetPoint("TOP", lastOptionsButton, "BOTTOM", 0, -20)
    button:SetText(text)
    button:SetScript("OnClick", onClick)

    lastOptionsButton = button
    optionsFrame:SetHeight(optionsFrame:GetHeight() + 50)

    return button
end

-- Slash Commands
SLASH_KCDOPT1 = "/kcdopt"

SlashCmdList["KCDOPT"] = function()
    if optionsFrame:IsShown() then
        optionsFrame:Hide()
    else
        optionsFrame:Show()
    end
end

SLASH_KCDLOG1 = "/kcdlog"
SlashCmdList["KCDLOG"] = displayKillLog

-- XP Display
local function displayStats(isKillGain, xpGained)
    local currentXP = UnitXP("player")
    local maxXP = UnitXPMax("player")
    local xpRemaining = maxXP - currentXP

    local sessionTime = GetTime() - sessionStartTime
    local xpPerHour = 0

    if sessionTime > 0 then
        xpPerHour = math.floor((sessionXP / sessionTime) * 3600)
    end

    -- lastKillXP only updates on actual kills, so this stays a real
    -- "kills needed" estimate even when the current gain was from a quest
    -- turn-in or exploration.
    if lastKillXP <= 0 then
        return
    end

    local sourceLabel = isKillGain and "a kill" or "a quest or exploration"

    if KillCountDownDB.modifiedDisplay then
        if isKillGain then
            print(
                "You need approximately " ..
                math.ceil(xpRemaining / lastKillXP) ..
                " more kills to level up."
            )
        else
            print(
                "You gained " .. xpGained .. " XP from " .. sourceLabel ..
                ". Still need approximately " ..
                math.ceil(xpRemaining / lastKillXP) ..
                " kills (at your current kill rate) to level up."
            )
        end
    else
        print("You gained " .. xpGained .. " XP from " .. sourceLabel .. "!")
        print("Remaining XP: " .. xpRemaining)
        print("Estimated Kills Needed (at current kill rate): " .. math.ceil(xpRemaining / lastKillXP))
        print("XP Per Hour: " .. xpPerHour)
    end
end

-- Combat Timer
local function startCombatTimer()
    combatStartTime = GetTime()
end

local function stopCombatTimer()

    local currentXP = UnitXP("player")
    local maxXP = UnitXPMax("player")
    local xpRemaining = maxXP - currentXP

    local sessionTime = GetTime() - sessionStartTime

    if sessionXP <= 0 or sessionTime <= 0 then
        return
    end

    local xpPerSecond = sessionXP / sessionTime
    local secondsToLevel = xpRemaining / xpPerSecond

    local minutes = math.floor(secondsToLevel / 60)
    local seconds = math.floor(secondsToLevel % 60)

    if KillCountDownDB.timerActive then
        print(
            "Estimated Time to level: " ..
            minutes .. "m " .. seconds .. "s"
        )
    end
end

-- Event Handler
local function OnEvent(self, event, ...)

    if event == "ADDON_LOADED" then
        local loadedAddonName = ...

        if loadedAddonName == "KillCountDown" then
            -- KillCountDownDB is now the REAL saved table (or a fresh one on
            -- first-ever load) - safe to fill in any missing defaults here.
            InitializeSavedVariables()
            applyKillLogWindowState()

            updateModifiedDisplayButton()
            updateNotificationsButton()
            updateTimerButton()
        end
    end

    if event == "PLAYER_LOGIN" then

        local currentXP = UnitXP("player")
        lastXP = currentXP

        sessionStartTime = GetTime()
        sessionXP = 0

        updateModifiedDisplayButton()
        updateNotificationsButton()
        updateTimerButton()

        print("KillCountDown Loaded! Type /kcdopt for options.")
    end

    if event == "PLAYER_XP_UPDATE" then

        local currentXP = UnitXP("player")
        local xpGained = currentXP - lastXP

        lastXP = currentXP

        if xpGained > 0 then

            local isKillGain = #pendingKills > 0

            if isKillGain then
                lastKillXP = xpGained
            end

            sessionXP = sessionXP + xpGained

            local splitXP = xpGained

            if #pendingKills > 0 then
                splitXP = math.floor(xpGained / #pendingKills)
            end

            for _, kill in ipairs(pendingKills) do

                table.insert(KillCountDownCharDB.killLog, {
                    name = kill.name,
                    level = kill.level,
                    xp = splitXP,
                    time = kill.time
                })

                -- Limit log size
                if #KillCountDownCharDB.killLog > 500 then
                    table.remove(KillCountDownCharDB.killLog, 1)
                end
            end

            pendingKills = {}

            -- Keep the log window live if it's open while farming.
            if killLogFrame:IsShown() then
                refreshKillLogWindow()
            end

            if KillCountDownDB.notificationsEnabled then
                displayStats(isKillGain, xpGained)
            end
        end
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then

        local _, subEvent, _, _, _, _, _, _, destName =
            CombatLogGetCurrentEventInfo()

        if subEvent == "PARTY_KILL" then

            startCombatTimer()

            local enemyName = destName or "Unknown"
            local enemyLevel = -1

            if UnitExists("target") and UnitName("target") == enemyName then
                enemyLevel = UnitLevel("target")
            end

            table.insert(pendingKills, {
                name = enemyName,
                level = enemyLevel,
                time = date("%H:%M:%S")
            })
        end
    end

    if event == "PLAYER_REGEN_ENABLED" then
        stopCombatTimer()
    end
end

-- Register Events
local frame = CreateFrame("Frame")

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_XP_UPDATE")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", OnEvent)