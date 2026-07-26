------------------------------------------------------------
-- KillCountDown: Level Stamp module
--
-- Optional, off by default. When enabled, records your real /played
-- time (via RequestTimePlayed / TIME_PLAYED_MSG - the same data the
-- game's own /played command uses) at the moment you hit each level.
-- Stored per-character in KillCountDownCharDB.levelLog, so it lives
-- alongside the kill log and won't bleed between toons.
--
-- Lives in its own file on purpose: if you ever want to strip this
-- feature back out, just remove this file (and its .toc line) and
-- the rest of the addon is untouched.
------------------------------------------------------------

local pendingLevelUp = nil  -- level we're waiting on a TIME_PLAYED_MSG for
local pendingRequest = nil  -- "levelup" or "seed" - which RequestTimePlayed() call is in flight
local seedBaselineIfNeeded  -- forward declaration; defined near the event handler below

local DEFAULT_LEVEL_LOG_WINDOW = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 0,
    width = 420,
    height = 360,
}

local function ensureDefaults()
    KillCountDownDB = KillCountDownDB or {}
    if KillCountDownDB.levelStampEnabled == nil then
        KillCountDownDB.levelStampEnabled = false
    end

    if KillCountDownDB.levelLogWindow == nil then
        KillCountDownDB.levelLogWindow = {
            point = DEFAULT_LEVEL_LOG_WINDOW.point,
            relativePoint = DEFAULT_LEVEL_LOG_WINDOW.relativePoint,
            x = DEFAULT_LEVEL_LOG_WINDOW.x,
            y = DEFAULT_LEVEL_LOG_WINDOW.y,
            width = DEFAULT_LEVEL_LOG_WINDOW.width,
            height = DEFAULT_LEVEL_LOG_WINDOW.height,
        }
    end

    KillCountDownCharDB = KillCountDownCharDB or {}
    if KillCountDownCharDB.levelLog == nil then
        KillCountDownCharDB.levelLog = {}
    end
end

local function formatPlayed(seconds)
    seconds = seconds or 0
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then
        return string.format("%dh %dm %ds", h, m, s)
    end
    return string.format("%dm %ds", m, s)
end

------------------------------------------------------------
-- Level Log window (same layout pattern as the Kill Log window)
------------------------------------------------------------

local levelLogFrame = CreateFrame("Frame", "KillCountDownLevelLogFrame", UIParent, "BasicFrameTemplateWithInset")

-- Placeholder size/position at load time (KillCountDownDB.levelLogWindow
-- doesn't exist yet here) - the real saved position/size gets applied
-- once ADDON_LOADED fires and ensureDefaults() has run.
levelLogFrame:SetSize(DEFAULT_LEVEL_LOG_WINDOW.width, DEFAULT_LEVEL_LOG_WINDOW.height)
levelLogFrame:SetPoint(
    DEFAULT_LEVEL_LOG_WINDOW.point,
    UIParent,
    DEFAULT_LEVEL_LOG_WINDOW.relativePoint,
    DEFAULT_LEVEL_LOG_WINDOW.x,
    DEFAULT_LEVEL_LOG_WINDOW.y
)

levelLogFrame:SetMovable(true)
levelLogFrame:SetResizable(true)
levelLogFrame:EnableMouse(true)
levelLogFrame:SetClampedToScreen(true)

-- Min/max resize bounds (API differs by client version, so support both)
if levelLogFrame.SetResizeBounds then
    levelLogFrame:SetResizeBounds(300, 200, 800, 700) -- modern retail API
elseif levelLogFrame.SetMinResize then
    levelLogFrame:SetMinResize(300, 200)
    levelLogFrame:SetMaxResize(800, 700)
end

levelLogFrame:Hide()

-- Apply the real saved position/size once KillCountDownDB.levelLogWindow
-- exists (called from ADDON_LOADED, after ensureDefaults() has run)
local function applyLevelLogWindowState()
    local saved = KillCountDownDB.levelLogWindow
    levelLogFrame:ClearAllPoints()
    levelLogFrame:SetSize(saved.width, saved.height)
    levelLogFrame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
end

-- Persist whatever position/size the player leaves it at
local function saveLevelLogWindowState()
    local point, _, relativePoint, x, y = levelLogFrame:GetPoint()
    KillCountDownDB.levelLogWindow.point = point
    KillCountDownDB.levelLogWindow.relativePoint = relativePoint
    KillCountDownDB.levelLogWindow.x = x
    KillCountDownDB.levelLogWindow.y = y
    KillCountDownDB.levelLogWindow.width = levelLogFrame:GetWidth()
    KillCountDownDB.levelLogWindow.height = levelLogFrame:GetHeight()
end

levelLogFrame:RegisterForDrag("LeftButton")
levelLogFrame:SetScript("OnDragStart", levelLogFrame.StartMoving)
levelLogFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    saveLevelLogWindowState()
end)

local levelLogTitle = levelLogFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
levelLogTitle:SetPoint("TOP", levelLogFrame, "TOP", 0, -6)
levelLogTitle:SetText("KillCountDown - Level Stamps")

local levelLogScroll = CreateFrame("ScrollFrame", "KillCountDownLevelLogScrollFrame", levelLogFrame, "UIPanelScrollFrameTemplate")
levelLogScroll:SetPoint("TOPLEFT", levelLogFrame, "TOPLEFT", 12, -30)
levelLogScroll:SetPoint("BOTTOMRIGHT", levelLogFrame, "BOTTOMRIGHT", -30, 44)

local levelLogContent = CreateFrame("Frame", nil, levelLogScroll)
levelLogContent:SetSize(1, 1)
levelLogScroll:SetScrollChild(levelLogContent)

local closeLevelLogButton = CreateFrame("Button", nil, levelLogFrame, "GameMenuButtonTemplate")
closeLevelLogButton:SetSize(120, 24)
closeLevelLogButton:SetPoint("BOTTOMRIGHT", levelLogFrame, "BOTTOMRIGHT", -14, 10)
closeLevelLogButton:SetText("Close")
closeLevelLogButton:SetScript("OnClick", function() levelLogFrame:Hide() end)

-- Resize grip (bottom-right corner) - drag to resize the window
local levelLogResizeGrip = CreateFrame("Button", nil, levelLogFrame)
levelLogResizeGrip:SetSize(16, 16)
levelLogResizeGrip:SetPoint("BOTTOMRIGHT", levelLogFrame, "BOTTOMRIGHT", -4, 4)
levelLogResizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
levelLogResizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
levelLogResizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

local refreshLevelLogWindow -- forward declaration so the resize grip can call it below

levelLogResizeGrip:SetScript("OnMouseDown", function()
    levelLogFrame:StartSizing("BOTTOMRIGHT")
end)

levelLogResizeGrip:SetScript("OnMouseUp", function()
    levelLogFrame:StopMovingOrSizing()
    saveLevelLogWindowState()
    refreshLevelLogWindow()
end)

local levelEntryPool = {}
local levelEmptyText
local LEVEL_ROW_HEIGHT = 32

refreshLevelLogWindow = function()
    local log = KillCountDownCharDB.levelLog
    local count = #log

    for _, fs in ipairs(levelEntryPool) do
        fs:Hide()
    end

    if count == 0 then
        if not levelEmptyText then
            levelEmptyText = levelLogContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            levelEmptyText:SetPoint("TOPLEFT", levelLogContent, "TOPLEFT", 4, -4)
        end
        levelEmptyText:SetText(
            KillCountDownDB.levelStampEnabled
            and "No level stamps recorded yet."
            or "Level Stamps is turned off. Enable it in /kcdopt."
        )
        levelEmptyText:Show()
        levelLogContent:SetSize(levelLogScroll:GetWidth(), levelLogScroll:GetHeight())
        return
    elseif levelEmptyText then
        levelEmptyText:Hide()
    end

    -- Most recent level on top
    local row = 0
    for i = count, 1, -1 do
        local entry = log[i]
        row = row + 1

        local fs = levelEntryPool[row]
        if not fs then
            fs = levelLogContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetJustifyH("LEFT")
            fs:SetJustifyV("TOP")
            fs:SetHeight(LEVEL_ROW_HEIGHT)
            levelEntryPool[row] = fs
        end

        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", levelLogContent, "TOPLEFT", 4, -4 - (row - 1) * LEVEL_ROW_HEIGHT)
        fs:SetPoint("RIGHT", levelLogContent, "RIGHT", -4, 0)
        fs:SetText(
            "|cffaaaaaa[" .. entry.date .. "]|r Level |cff88ff88" .. entry.level .. "|r\n" ..
            "This level: |cffffff00" .. formatPlayed(entry.levelPlayed) .. "|r" ..
            "   Total /played: |cffffff00" .. formatPlayed(entry.totalPlayed) .. "|r"
        )
        fs:Show()
    end

    levelLogContent:SetSize(levelLogScroll:GetWidth(), math.max(count * LEVEL_ROW_HEIGHT + 8, levelLogScroll:GetHeight()))
end

levelLogFrame:SetScript("OnShow", function(self)
    refreshLevelLogWindow()
    self:EnableKeyboard(true)
    self:Raise()
end)

levelLogFrame:SetScript("OnHide", function(self)
    self:EnableKeyboard(false)
end)

local function toggleLevelLog()
    if levelLogFrame:IsShown() then
        levelLogFrame:Hide()
    else
        refreshLevelLogWindow()
        levelLogFrame:Show()
    end
end

SLASH_KCDLEVELS1 = "/kcdstamp"
SlashCmdList["KCDLEVELS"] = toggleLevelLog

------------------------------------------------------------
-- Options panel hook-in (uses the shared KillCountDown namespace
-- exposed by the main addon file)
------------------------------------------------------------

local levelStampButton

local function updateLevelStampButton()
    if levelStampButton then
        levelStampButton:SetText(
            KillCountDownDB.levelStampEnabled
            and "Level Stamps: ON"
            or "Level Stamps: OFF"
        )
    end
end

local function addOptionsButtons()
    if not (KillCountDown and KillCountDown.AddOptionsButton) then
        -- Main file didn't expose the shared hook (e.g. unexpected load
        -- order) - skip the options buttons rather than erroring. The
        -- /kcdlevels window still works either way.
        return
    end

    levelStampButton = KillCountDown.AddOptionsButton("Level Stamps: OFF", function()
        KillCountDownDB.levelStampEnabled = not KillCountDownDB.levelStampEnabled
        updateLevelStampButton()

        if KillCountDownDB.levelStampEnabled then
            seedBaselineIfNeeded()
        end
    end)

    KillCountDown.AddOptionsButton("Show Level Stamps", toggleLevelLog)

    updateLevelStampButton()
end

------------------------------------------------------------
-- Level-up capture via real /played data
--
-- Blizzard resets the server-side "time played this level" counter to 0
-- at the instant you ding - before we get a chance to ask for it - so
-- that value is useless for measuring the level you just finished. The
-- overall totalPlayed value does NOT reset on level-up, though, so we
-- track our own baseline (totalPlayed at the start of the current level)
-- and compute levelPlayed = totalPlayed - baseline ourselves.
------------------------------------------------------------

local captureFrame = CreateFrame("Frame")
captureFrame:RegisterEvent("ADDON_LOADED")
captureFrame:RegisterEvent("PLAYER_LOGIN")
captureFrame:RegisterEvent("PLAYER_LEVEL_UP")
captureFrame:RegisterEvent("TIME_PLAYED_MSG")

seedBaselineIfNeeded = function()
    if not KillCountDownDB.levelStampEnabled then
        return
    end
    if KillCountDownCharDB.totalPlayedAtLevelStart ~= nil then
        return -- already have a baseline for this character
    end
    if pendingRequest ~= nil then
        return -- a request is already in flight
    end

    pendingRequest = "seed"
    RequestTimePlayed()
end

captureFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddonName = ...
        if loadedAddonName == "KillCountDown" then
            ensureDefaults()
            applyLevelLogWindowState()
            addOptionsButtons()
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        seedBaselineIfNeeded()
        return
    end

    if event == "PLAYER_LEVEL_UP" then
        if not KillCountDownDB.levelStampEnabled then
            return
        end

        local newLevel = ...
        pendingLevelUp = newLevel
        pendingRequest = "levelup"
        RequestTimePlayed()
        return
    end

    if event == "TIME_PLAYED_MSG" then
        local totalPlayed = ...

        if pendingRequest == "levelup" then
            local baseline = KillCountDownCharDB.totalPlayedAtLevelStart or totalPlayed
            local levelPlayed = totalPlayed - baseline
            if levelPlayed < 0 then
                levelPlayed = 0
            end

            table.insert(KillCountDownCharDB.levelLog, {
                level = pendingLevelUp,
                totalPlayed = totalPlayed,
                levelPlayed = levelPlayed,
                date = date("%Y-%m-%d %H:%M"),
            })

            print(
                "KillCountDown: Reached level " .. pendingLevelUp ..
                " - time on previous level: " .. formatPlayed(levelPlayed)
            )

            -- New level starts now - reset the baseline for next time.
            KillCountDownCharDB.totalPlayedAtLevelStart = totalPlayed

            pendingLevelUp = nil
            pendingRequest = nil

            if levelLogFrame:IsShown() then
                refreshLevelLogWindow()
            end
        elseif pendingRequest == "seed" then
            if KillCountDownCharDB.totalPlayedAtLevelStart == nil then
                KillCountDownCharDB.totalPlayedAtLevelStart = totalPlayed
            end
            pendingRequest = nil
        end
        -- else: the player ran /played manually - not ours to act on
    end
end)