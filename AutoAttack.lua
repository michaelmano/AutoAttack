-- AutoAttack.lua
-- 1. Starts auto-attack when you press an ability with no rage/energy/mana.
-- 2. Automatically attacks back when a mob attacks you and auto-targets you.
-- 3. In Zul'Gurub (zone 1977): when YOU target Ohgan or Bloodlord Mandokir,
--    begins polling the raid. Suppresses the AutoAttack Addon while anyone is targeting
--    them. Stops polling once nobody is targeting them anymore.
-- Compatible with Turtle WoW 1.12 client

AutoAttackDB = AutoAttackDB or {
    enabled = true,
}

-- Runtime-only state — not persisted
local AutoAttackSession = {
    inCombat     = false,
    zgSuppressed = false,
    inZG         = false,
    polling      = false,
}

local ZG_ZONE = "Zul'Gurub"

local WATCH_TARGETS = {
    ["ohgan"]              = true,
    ["bloodlord mandokir"] = true,
}

local SCAN_INTERVAL = 0.5
local scanTimer     = 0

-- Core attack function
-------------------------------------------------------------------------------

local function TryStartAttack()
    if not AutoAttackDB.enabled then return end
    if AutoAttackSession.zgSuppressed then return end

    if UnitExists("target")
       and UnitCanAttack("player", "target")
       and not UnitIsDead("target")
       and not UnitIsCorpse("target") then
        if SlashCmdList["STARTATTACK"] then
            SlashCmdList["STARTATTACK"]("")
        end
    end
end

-- ZG helpers
-------------------------------------------------------------------------------

local function PlayerTargetingWatchedUnit()
    if not UnitExists("target") then return false end
    local name = UnitName("target")
    return name and WATCH_TARGETS[string.lower(name)]
end

local function AnyRaidMemberTargetingWatchedUnit()
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        for i = 1, numRaid do
            local target = "raid" .. i .. "target"
            if UnitExists(target) then
                local name = UnitName(target)
                if name and WATCH_TARGETS[string.lower(name)] then
                    return true, name
                end
            end
        end
    else
        if UnitExists("target") then
            local name = UnitName("target")
            if name and WATCH_TARGETS[string.lower(name)] then
                return true, name
            end
        end
    end
    return false, nil
end

local function UpdateZGSuppression()
    local watching, targetName = AnyRaidMemberTargetingWatchedUnit()

    if watching and not AutoAttackSession.zgSuppressed then
        AutoAttackSession.zgSuppressed = true
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff00ff00AutoAttack|r: |cffff4400Suppressed|r — raid targeting " .. tostring(targetName) .. "."
        )

    elseif not watching and AutoAttackSession.zgSuppressed then
        AutoAttackSession.zgSuppressed = false
        AutoAttackSession.polling      = false
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff00ff00AutoAttack|r: |cff00ff00Resumed|r — no raid member targeting watched units."
        )

    elseif not watching and not AutoAttackSession.zgSuppressed then
        AutoAttackSession.polling = false
    end
end

-- Event frame
-------------------------------------------------------------------------------

local frame = CreateFrame("Frame", "AutoAttackFrame")

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("SPELLCAST_FAILED")
frame:RegisterEvent("UI_ERROR_MESSAGE")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")

local RESOURCE_ERRORS = {
    ["Not enough rage"]    = true,
    ["Not enough energy"]  = true,
    ["Not enough mana"]    = true,
    ["Not enough focus"]   = true,
}

local AutoAttack = {}

frame:SetScript("OnEvent", function()
    if event == "PLAYER_LOGIN" then
        AutoAttack:HookActionButtons()

    elseif event == "PLAYER_ENTERING_WORLD" then
        AutoAttackSession.inZG = (GetZoneText() == ZG_ZONE)
        if not AutoAttackSession.inZG then
            AutoAttackSession.zgSuppressed = false
            AutoAttackSession.polling      = false
        end

    elseif event == "SPELLCAST_FAILED" then
        TryStartAttack()

    elseif event == "UI_ERROR_MESSAGE" then
        if arg1 and RESOURCE_ERRORS[arg1] then
            TryStartAttack()
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        AutoAttackSession.inCombat = true
        TryStartAttack()

    elseif event == "PLAYER_REGEN_ENABLED" then
        AutoAttackSession.inCombat = false

    elseif event == "PLAYER_TARGET_CHANGED" then
        if AutoAttackSession.inZG and PlayerTargetingWatchedUnit() and not AutoAttackSession.polling then
            AutoAttackSession.polling  = true
            scanTimer   = 0
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff00ff00AutoAttack|r: |cffffff00Watching|r — " ..
                UnitName("target") .. " targeted, monitoring raid."
            )
        end

        if AutoAttackSession.inCombat then
            TryStartAttack()
        end
    end
end)

-- OnUpdate: only active while AutoAttackSession.polling is true
-------------------------------------------------------------------------------

frame:SetScript("OnUpdate", function()
    if not AutoAttackSession.polling then return end

    scanTimer = scanTimer + arg1
    if scanTimer < SCAN_INTERVAL then return end
    scanTimer = 0

    UpdateZGSuppression()
end)

-- Action button hooking
-------------------------------------------------------------------------------

local BUTTON_PREFIXES = {
    "ActionButton",
    "MultiBarBottomLeftButton",
    "MultiBarBottomRightButton",
    "MultiBarRightButton",
    "MultiBarLeftButton",
}

function AutoAttack:HookActionButtons()
    for _, prefix in ipairs(BUTTON_PREFIXES) do
        for i = 1, 12 do
            local btnName = prefix .. i
            local btn = getglobal(btnName)
            if btn then
                local original = btn:GetScript("OnClick")
                if original then
                    btn:SetScript("OnClick", function()
                        TryStartAttack()
                        original()
                    end)
                end
            end
        end
    end
end

-- Slash commands:  /autoattack  or  /aa
-------------------------------------------------------------------------------

SLASH_AUTOATTACK1 = "/autoattack"
SLASH_AUTOATTACK2 = "/aa"

SlashCmdList["AUTOATTACK"] = function(msg)
    msg = string.lower(msg or "")
    if msg == "on" then
        AutoAttackDB.enabled = true
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00AutoAttack|r: Enabled.")
    elseif msg == "off" then
        AutoAttackDB.enabled = false
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00AutoAttack|r: Disabled.")
    elseif msg == "status" then
        local state = AutoAttackDB.enabled and "|cff00ff00ON|r"  or "|cffff0000OFF|r"
        local zg    = AutoAttackSession.inZG              and "|cff00ff00yes|r" or "no"
        local poll  = AutoAttackSession.polling           and "|cffffff00yes|r" or "no"
        local supp  = AutoAttackSession.zgSuppressed      and "|cffff4400yes|r" or "no"
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00AutoAttack|r: " .. state ..
            "  |  Zone: " .. tostring(GetZoneText()) ..
            "  |  In ZG: " .. zg ..
            "  |  Polling: " .. poll ..
            "  |  Suppressed: " .. supp)
    else
        local state = AutoAttackDB.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00AutoAttack|r: Currently " .. state ..
            ".  Usage: /aa on | /aa off | /aa status")
    end
end