-- Create the frame for the options panel
local optionsFrame = CreateFrame("Frame", "KillCountDownOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
optionsFrame:SetSize(300, 300)
optionsFrame:SetPoint("CENTER")
optionsFrame:Hide() -- Hideen by default duh

-- Title for the frame
local title = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
title:SetPoint("TOP", optionsFrame, "TOP", 0, -10)
title:SetText("KillCount Options")

--[[ Saved Variables
KillCountDownDB = KillCountDownDB or {}

KillCountDownDB.modifiedDisplay =
    KillCountDownDB.modifiedDisplay or false

KillCountDownDB.notificationsEnabled =
    KillCountDownDB.notificationsEnabled ~= false

KillCountDownDB.timerActive =
    KillCountDownDB.timerActive or false

]]-- This code doesn't seem to keep the saved DB

--Saved Variables
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

if KillCountDownDB.killLog == nil then -- Added to allow local killLog  = KillCountDB.killLog to work...hopefuly
    KillCountDownDB.killLog = {}
end -- 

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

-- Button: Show Kill Log
local logButton = CreateFrame("Button", nil, optionsFrame, "GameMenuButtonTemplate")
logButton:SetSize(200, 30)
logButton:SetPoint("TOP", timerButton, "BOTTOM", 0, -20)
logButton:SetText("Show Kill Log")

local function displayKillLog()
    if #KillCountDownDB.killLog == 0 then
        print("Kill Log is empty.")
        return
    end

    print("---- Kill Log ----")

    for _, entry in ipairs(KillCountDownDB.killLog) do
        print(
            "[" .. entry.time .. "] " ..
            entry.name ..
            " (Level " .. entry.level .. ")" ..
            " - XP Gained: " .. entry.xp
        )
    end
end

logButton:SetScript("OnClick", displayKillLog)

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
local function displayStats()
    local currentXP = UnitXP("player")
    local maxXP = UnitXPMax("player")
    local xpRemaining = maxXP - currentXP

    local sessionTime = GetTime() - sessionStartTime
    local xpPerHour = 0

    if sessionTime > 0 then
        xpPerHour = math.floor((sessionXP / sessionTime) * 3600)
    end

    if lastKillXP <= 0 then
        return
    end

    if KillCountDownDB.modifiedDisplay then
        print(
            "You need approximately " ..
            math.ceil(xpRemaining / lastKillXP) ..
            " more kills to level up."
        )
    else
        print("You gained " .. lastKillXP .. " XP!")
        print("Remaining XP: " .. xpRemaining)
        print("Estimated Kills Needed: " .. math.ceil(xpRemaining / lastKillXP))
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

            lastKillXP = xpGained
            sessionXP = sessionXP + xpGained

            local splitXP = xpGained

            if #pendingKills > 0 then
                splitXP = math.floor(xpGained / #pendingKills)
            end

            for _, kill in ipairs(pendingKills) do

                table.insert(KillCountDownDB.killLog, {
                    name = kill.name,
                    level = kill.level,
                    xp = splitXP,
                    time = kill.time
                })

                -- Limit log size
                if #KillCountDownDB.killLog > 500 then
                    table.remove(KillCountDownDB.killLog, 1)
                end
            end

            pendingKills = {}

            if KillCountDownDB.notificationsEnabled then
                displayStats()
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

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_XP_UPDATE")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", OnEvent)