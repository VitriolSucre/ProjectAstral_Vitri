
local PA = ProjectAstral or _G.ProjectAstral

local MOUNT_DEBUG = false

local mountSpellIds = {}
local mountNameToId  = {}

local CUSTOM_MOUNT_IDS = {
    550001,  -- Startouched Furline
    550008,  -- Ensorcelled Everwyrm
    550015,  -- Arcanovoid Construct
    550022,  -- Astral Aurochs
    550029,  -- Sunwarmed Furline
    550036,  -- Molten Cormaera
    550043,  -- Unbound Star-Eater
    550050,  -- Herald of Sa'bak
    550057,  -- Ashes of Belo'ren
    550064,  -- Sintouched Deathwalker
    550071,  -- Heart of the Aspects
    550078,  -- Elementium Drake
    550085,  -- Lightwing Dragonhawk
    550092,  -- Voidwing Dragonhawk
    550099,  -- Enchanted Fey Dragon
    550106,  -- Antoran Charhound
    550113,  -- Antoran Gloomhound
    550120,  -- Felsteel Annihilator
    550127,  -- Primal Flamesaber (ground only)
    550134,  -- Flametalon of Alysrazor (ground only)
    550141,  -- Spring Harvesthog (ground only)
    550148,  -- Inarius' Charger
    550155,  -- Coldflame Infernal (ground only)
    550162,  -- Infinite Timereaver
    550169,  -- Duskbrute Harrower
    550176,  -- Tenebrous Harrower
    550183,  -- Venomous Gladiator's Goredrake
    550190,  -- Magmashell (ground only)
    550197,  -- Unbound Manawyrm
    550204,  -- Grove Warden
    550211,  -- Sunflare Driftmoth
    550218,  -- Ascendant Skyrazor
    550225,  -- Starspark Netherdrake
    550232,  -- Smoldering Ember Wyrm
    550239,  -- Challenger's War Yeti (ground only)
    550246,  -- Pegasus
    550253,  -- Embodiment of the Blazing
    550260,  -- Spawn of Vyranoth
    550267,  -- Runebound Firelord
    550274,  -- Blazing Drake
    550281,  -- Tarecgosa
    550288,  -- Zovaal's Soul Eater
    550295,  -- Farseer's Raging Tempest
    550302,  -- Sha-Warped Owl
    550309,  -- Blossomback Arboon
    550316,  -- Blossombranch Groveglider
    550323,  -- Tyrael's Charger
    550330,  -- Uncorrupted Voidwing
    550337,  -- Felscorned War Wyrm
    550344,  -- Winged Guardian
}
if PA then PA.CustomMountIds = CUSTOM_MOUNT_IDS end   -- MountJournal.lua lists these too

local function RebuildMountSet()
    if type(GetNumCompanions) ~= "function" then return end
    mountSpellIds = {}
    mountNameToId  = {}
    local n = GetNumCompanions("MOUNT") or 0
    for i = 1, n do
        local _, name, spellId = GetCompanionInfo("MOUNT", i)
        if spellId then
            mountSpellIds[spellId] = true
            if name and name ~= "" then mountNameToId[name] = spellId end
        end
    end
    for _, id in ipairs(CUSTOM_MOUNT_IDS) do
        mountSpellIds[id] = true
        if GetSpellInfo then
            local sName = GetSpellInfo(id)
            if sName and sName ~= "" then mountNameToId[sName] = id end
        end
    end
    if MOUNT_DEBUG then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffaaffaa[MountSafe.dbg]|r set rebuilt: " .. n .. " companions found")
    end
end

local function IsBlockingMovement()
    if IsFalling and IsFalling() then return true end
    local speed = GetUnitSpeed and GetUnitSpeed("player")
    if speed and speed > 0 then return true end
    return false
end

local function SendMountCommand(spellId)
    if not spellId then return end
    SendChatMessage("." .. "mount " .. spellId, "SAY")
end

local lastHandledSpell = nil
local lastHandledTick  = 0

local lastMovingErrorAt      = 0
local MOVING_ERROR_WINDOW    = 0.1

local function HandleMountIntent(spellId)
    if not spellId or not mountSpellIds[spellId] then return end

    local now = GetTime()
    if spellId == lastHandledSpell and (now - lastHandledTick) < 0.20 then
        return
    end
    lastHandledSpell = spellId
    lastHandledTick  = now

    local clientMounted = IsMounted and IsMounted()
    local auraMounted = false
    if not clientMounted then
        for i = 1, 40 do
            local name = UnitBuff("player", i)
            if not name then break end
            if mountNameToId[name] then auraMounted = true; break end
        end
    end
    local mounted = clientMounted or auraMounted
    if MOUNT_DEBUG then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cffaaffaa[MountSafe.dbg]|r HandleMountIntent spell=%d IsMounted=%s auraMounted=%s moving=%s",
            spellId, tostring(clientMounted), tostring(auraMounted), tostring(IsBlockingMovement())))
    end
    if mounted then
        if MOUNT_DEBUG then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffaaffaa[MountSafe.dbg]|r → sending '.unmount'")
        end
        SendChatMessage(".unmount", "SAY")
        return
    end

    if UnitAffectingCombat and UnitAffectingCombat("player") then
        if UIErrorsFrame and SPELL_FAILED_AFFECTING_COMBAT then
            UIErrorsFrame:AddMessage(SPELL_FAILED_AFFECTING_COMBAT,
                                     1.0, 0.1, 0.1, 1.0)
        end
        return
    end

    if not IsBlockingMovement() then return end

    if (GetTime() - lastMovingErrorAt) > MOVING_ERROR_WINDOW then
        if MOUNT_DEBUG then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cffaaffaa[MountSafe.dbg]|r no recent SPELL_FAILED_MOVING for %d → skip fallback",
                spellId))
        end
        return
    end

    if MOUNT_DEBUG then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffaaffaa[MountSafe.dbg]|r client blocked → sending .mount " .. spellId)
    end
    SendMountCommand(spellId)
end

if type(CastSpell) == "function" then
    hooksecurefunc("CastSpell", function(spellSlot, bookType)
        if bookType ~= BOOKTYPE_SPELL and bookType ~= "spell" then return end
        if not spellSlot then return end
        local link = GetSpellLink and GetSpellLink(spellSlot, "spell")
        local id = link and tonumber(link:match("spell:(%d+)"))
        if not id then return end
        HandleMountIntent(id)
    end)
end

-- actionType~="spell" would silently skip every mount slot.
if type(UseAction) == "function" then
    hooksecurefunc("UseAction", function(slot)
        if not slot then return end
        local actionType, id, subType = GetActionInfo(slot)
        if actionType == "spell" then
            HandleMountIntent(id)
        elseif actionType == "companion" and subType == "MOUNT" and id then
            local _, _, spellId = GetCompanionInfo("MOUNT", id)
            if spellId then HandleMountIntent(spellId) end
        end
    end)
end

if type(CastSpellByID) == "function" then
    hooksecurefunc("CastSpellByID", function(spellId)
        HandleMountIntent(spellId)
    end)
end

if type(CastSpellByName) == "function" then
    hooksecurefunc("CastSpellByName", function(name)
        if not name then return end
        local id = mountNameToId[name]
        if not id then return end
        HandleMountIntent(id)
    end)
end

if type(CallCompanion) == "function" then
    hooksecurefunc("CallCompanion", function(companionType, index)
        if companionType ~= "MOUNT" then return end
        if not index then return end
        local _, _, spellId = GetCompanionInfo("MOUNT", index)
        if not spellId then return end
        HandleMountIntent(spellId)
    end)
end

if MOUNT_DEBUG then
    local function tag(label)
        return function(...)
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffaaffaa[MountSafe.dbg]|r " .. label .. " " ..
                tostring((...)) .. " moving=" .. tostring(IsBlockingMovement()))
        end
    end
    hooksecurefunc("UseAction",       tag("UseAction"))
    hooksecurefunc("CastSpell",       tag("CastSpell"))
    hooksecurefunc("CastSpellByID",   tag("CastSpellByID"))
    hooksecurefunc("CastSpellByName", tag("CastSpellByName"))
    if type(CallCompanion) == "function" then
        hooksecurefunc("CallCompanion", function(t, i)
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffaaffaa[MountSafe.dbg]|r CallCompanion " ..
                tostring(t) .. " " .. tostring(i) ..
                " moving=" .. tostring(IsBlockingMovement()))
        end)
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("COMPANION_LEARNED")
f:RegisterEvent("COMPANION_UNLEARNED")
f:RegisterEvent("COMPANION_UPDATE")
f:SetScript("OnEvent", RebuildMountSet)

do
    local SUPPRESS = {}
    if SPELL_FAILED_MOVING and SPELL_FAILED_MOVING ~= "" then
        SUPPRESS[SPELL_FAILED_MOVING] = true
    end

    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        local original = UIErrorsFrame.AddMessage
        UIErrorsFrame.AddMessage = function(self, msg, ...)
            local suppressed = msg and SUPPRESS[msg]
            if MOUNT_DEBUG then
                DEFAULT_CHAT_FRAME:AddMessage(string.format(
                    "|cffffaaaa[MountSafe.UIE]|r msg=%q suppressed=%s",
                    tostring(msg or "nil"), tostring(suppressed)))
            end

            if suppressed then
                lastMovingErrorAt = GetTime()
            end

            if suppressed then return end
            return original(self, msg, ...)
        end
    end
end

function PA.MountSafe(spellId)
    if not spellId or type(spellId) ~= "number" then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffff8888[MountSafe]|r Usage: /run ProjectAstral.MountSafe(<spellId>)")
        return
    end
    if IsBlockingMovement() then
        SendMountCommand(spellId)
    else
        CastSpellByID(spellId)
    end
end
PA.Mount = PA.MountSafe
