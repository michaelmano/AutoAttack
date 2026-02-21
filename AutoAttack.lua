-- 1. Starts auto-attack when you press an ability with no rage/energy/mana.
-- 2. Automatically attacks back when a mob attacks you and auto-targets you.
-- 3. In Zul'Gurub: when YOU target Ohgan or Bloodlord Mandokir, begins polling
--    the raid. Suppresses auto-attack while anyone is targeting them. Stops
--    polling once nobody is targeting them anymore.
-- Compatible with Turtle WoW 1.12 client

AutoAttackDB = AutoAttackDB or {
    enabled   = true,
    retaliate = true,
    debug     = false,
}

if AutoAttackDB.retaliate == nil then AutoAttackDB.retaliate = true end
if AutoAttackDB.debug     == nil then AutoAttackDB.debug     = false end

local AutoAttackSession = {
    inCombat     = false,
    zgSuppressed = false,
    inZG         = false,
    polling      = false,
    lastAttack   = 0,
}

local ATTACK_DEBOUNCE = 0.5
local ZG_ZONE         = "Zul'Gurub"

local WATCH_TARGETS = {
    ["ohgan"]              = true,
    ["bloodlord mandokir"] = true,
}

local SCAN_INTERVAL = 0.5
local scanTimer     = 0

-- Debug helper
-------------------------------------------------------------------------------

local function Debug(msg)
    if not AutoAttackDB.debug then return end
    DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[AutoAttack Debug]|r " .. tostring(msg))
end

-- Core attack function
-- forceAttack: bypasses the retaliate check (button presses, SPELLCAST_FAILED)
-------------------------------------------------------------------------------

local function TryStartAttack(forceAttack)
    if not AutoAttackDB.enabled then
        Debug("TryStartAttack blocked — addon disabled")
        return
    end
    if AutoAttackSession.zgSuppressed then
        Debug("TryStartAttack blocked — ZG suppressed")
        return
    end
    if not forceAttack and not AutoAttackDB.retaliate then
        Debug("TryStartAttack blocked — retaliate is off")
        return
    end

    local now = GetTime()
    if (now - AutoAttackSession.lastAttack) < ATTACK_DEBOUNCE then
        Debug("TryStartAttack blocked — debounce (" .. string.format("%.2f", now - AutoAttackSession.lastAttack) .. "s ago)")
        return
    end

    if not UnitExists("target") then
        Debug("TryStartAttack blocked — no target")
        return
    end
    if not UnitCanAttack("player", "target") then
        Debug("TryStartAttack blocked — cannot attack target")
        return
    end
    if UnitIsDead("target") or UnitIsCorpse("target") then
        Debug("TryStartAttack blocked — target is dead")
        return
    end

    if SlashCmdList["STARTATTACK"] then
        AutoAttackSession.lastAttack = now
        Debug("TryStartAttack — calling STARTATTACK on: " .. tostring(UnitName("target")))
        SlashCmdList["STARTATTACK"]("")
    else
        Debug("TryStartAttack blocked — STARTATTACK handler is nil!")
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
            "|cffffb6c1AutoAttack|r: |cffff4400Suppressed|r — raid targeting " .. tostring(targetName) .. "."
        )

    elseif not watching and AutoAttackSession.zgSuppressed then
        AutoAttackSession.zgSuppressed = false
        AutoAttackSession.polling      = false
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffffb6c1AutoAttack|r: |cff00ff00Resumed|r — no raid member targeting watched units."
        )

    elseif not watching and not AutoAttackSession.zgSuppressed then
        Debug("ZG poll — no watched targets found, stopping poll")
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
        Debug("PLAYER_LOGIN — hooking action buttons")
        AutoAttack:HookActionButtons()

    elseif event == "PLAYER_ENTERING_WORLD" then
        local zone = GetZoneText()
        AutoAttackSession.inZG = (zone == ZG_ZONE)
        Debug("PLAYER_ENTERING_WORLD — zone: " .. tostring(zone) .. "  inZG: " .. tostring(AutoAttackSession.inZG))
        if not AutoAttackSession.inZG then
            AutoAttackSession.zgSuppressed = false
            AutoAttackSession.polling      = false
        end

    elseif event == "SPELLCAST_FAILED" then
        Debug("SPELLCAST_FAILED — calling TryStartAttack (forced)")
        TryStartAttack(true)

    elseif event == "UI_ERROR_MESSAGE" then
        if arg1 and RESOURCE_ERRORS[arg1] then
            Debug("UI_ERROR_MESSAGE — resource error: " .. tostring(arg1))
            TryStartAttack(true)
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        AutoAttackSession.inCombat = true
        Debug("PLAYER_REGEN_DISABLED — entered combat  retaliate: " .. tostring(AutoAttackDB.retaliate))
        TryStartAttack(false)

    elseif event == "PLAYER_REGEN_ENABLED" then
        Debug("PLAYER_REGEN_ENABLED — left combat")
        AutoAttackSession.inCombat = false

    elseif event == "PLAYER_TARGET_CHANGED" then
        local targetName = UnitExists("target") and UnitName("target") or "none"
        Debug("PLAYER_TARGET_CHANGED — target: " .. targetName .. "  inCombat: " .. tostring(AutoAttackSession.inCombat))

        if AutoAttackSession.inZG and PlayerTargetingWatchedUnit() and not AutoAttackSession.polling then
            AutoAttackSession.polling = true
            scanTimer = 0
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffffb6c1AutoAttack|r: |cffffff00Watching|r — " ..
                targetName .. " targeted, monitoring raid."
            )
        end

        if AutoAttackSession.inCombat then
            Debug("PLAYER_TARGET_CHANGED — in combat, calling TryStartAttack (not forced)")
            TryStartAttack(false)
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
                        Debug("Button pressed: " .. btnName)
                        TryStartAttack(true)
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

    if msg == "" then
        AutoAttackDB.enabled = not AutoAttackDB.enabled
        local state = AutoAttackDB.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        DEFAULT_CHAT_FRAME:AddMessage("|cffffb6c1AutoAttack|r: Toggled " .. state .. ".")

    elseif msg == "retaliate" then
        AutoAttackDB.retaliate = not AutoAttackDB.retaliate
        local state = AutoAttackDB.retaliate and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        DEFAULT_CHAT_FRAME:AddMessage("|cffffb6c1AutoAttack|r: Retaliate toggled " .. state .. ".")

    elseif msg == "debug" then
        AutoAttackDB.debug = not AutoAttackDB.debug
        local state = AutoAttackDB.debug and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        DEFAULT_CHAT_FRAME:AddMessage("|cffffb6c1AutoAttack|r: Debug toggled " .. state .. ".")

    elseif msg == "on" then
        AutoAttackDB.enabled = true
        DEFAULT_CHAT_FRAME:AddMessage("|cffffb6c1AutoAttack|r: Enabled.")
    elseif msg == "off" then
        AutoAttackDB.enabled = false
        DEFAULT_CHAT_FRAME:AddMessage("|cffffb6c1AutoAttack|r: Disabled.")

    elseif msg == "retaliate on" then
        AutoAttackDB.retaliate = true
        DEFAULT_CHAT_FRAME:AddMessage("|cffffb6c1AutoAttack|r: Retaliate Enabled.")
    elseif msg == "retaliate off" then
        AutoAttackDB.retaliate = false
        DEFAULT_CHAT_FRAME:AddMessage("|cffffb6c1AutoAttack|r: Retaliate Disabled.")

    elseif msg == "debug on" then
        AutoAttackDB.debug = true
        DEFAULT_CHAT_FRAME:AddMessage("|cffffb6c1AutoAttack|r: Debug Enabled.")
    elseif msg == "debug off" then
        AutoAttackDB.debug = false
        DEFAULT_CHAT_FRAME:AddMessage("|cffffb6c1AutoAttack|r: Debug Disabled.")

    elseif msg == "status" then
        local state = AutoAttackDB.enabled          and "|cff00ff00ON|r"  or "|cffff0000OFF|r"
        local retal = AutoAttackDB.retaliate        and "|cff00ff00ON|r"  or "|cffff0000OFF|r"
        local dbg   = AutoAttackDB.debug            and "|cff00ff00ON|r"  or "|cffff0000OFF|r"
        local zg    = AutoAttackSession.inZG         and "|cff00ff00yes|r" or "no"
        local poll  = AutoAttackSession.polling      and "|cffffff00yes|r" or "no"
        local supp  = AutoAttackSession.zgSuppressed and "|cffff4400yes|r" or "no"
        DEFAULT_CHAT_FRAME:AddMessage("|cffffb6c1AutoAttack|r: " .. state ..
            "  |  Retaliate: " .. retal ..
            "  |  Debug: " .. dbg ..
            "  |  Zone: " .. tostring(GetZoneText()) ..
            "  |  In ZG: " .. zg ..
            "  |  Polling: " .. poll ..
            "  |  Suppressed: " .. supp)

    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffffb6c1AutoAttack|r: Usage:")
        DEFAULT_CHAT_FRAME:AddMessage("  /aa  |  /aa toggle          — toggle addon on/off")
        DEFAULT_CHAT_FRAME:AddMessage("  /aa on  |  /aa off          — explicit on/off")
        DEFAULT_CHAT_FRAME:AddMessage("  /aa retaliate               — toggle retaliate")
        DEFAULT_CHAT_FRAME:AddMessage("  /aa retaliate on|off        — explicit retaliate")
        DEFAULT_CHAT_FRAME:AddMessage("  /aa debug                   — toggle debug")
        DEFAULT_CHAT_FRAME:AddMessage("  /aa debug on|off            — explicit debug")
        DEFAULT_CHAT_FRAME:AddMessage("  /aa status                  — show all settings")
    end
end