-- File: media/lua/shared/BitcoinMining_Util.lua
-- Improved detection for Desktop Computers with GroupName 'Computer'
-- and sprite names like 'appliances_com_01_*'.

require("BitcoinMining_Sandbox")

BitcoinMining = BitcoinMining or {}
local Util = {}
BitcoinMining.Util = Util

----------------------------------------------------
-- Logging
----------------------------------------------------
local function _ts()
    return string.format("%.2f", getGameTime():getWorldAgeHours())
end

function Util.log(tag, fmt, ...)
    local ok, msg = pcall(string.format, fmt or "", ...)
    msg = ok and msg or (fmt or "")
    print(string.format("[PZBitcoinMining][%s][%s] %s", tag or "INFO", _ts(), tostring(msg)))
end

----------------------------------------------------
-- Computer detection
----------------------------------------------------
BitcoinMining.DesktopSpriteHints = BitcoinMining.DesktopSpriteHints or {
    "appliances_com_01_",
    "appliances_com_02_",
    "desktop_computer",
    "computerdesk",
    "computertable",
}

-- Returns true only for placed desktop-computer furniture (not dropped items)
function BitcoinMining.isComputerObject(obj)
    if not obj or not obj.getSprite then return false end
    if instanceof(obj, "IsoWorldInventoryObject") then return false end -- dropped, not placed
    local spr = obj:getSprite(); if not spr then return false end
    local name = (spr:getName() or ""):lower()
    local props = spr:getProperties()

    -- Prefer moveables metadata: GroupName/CustomName
    if props then
        local group = props:Val("GroupName")
        local custom = props:Val("CustomName")
        group = group and group:lower() or ""
        custom = custom and custom:lower() or ""
        if group == "computer" then return true end
        if custom:find("computer", 1, true) or custom:find("desktop", 1, true) then return true end
    end

    local function nameHas(hint) return name:find(hint, 1, true) ~= nil end
    for _, hint in ipairs(BitcoinMining.DesktopSpriteHints) do
        if nameHas(hint:lower()) then return true end
    end
    if _G.BitcoinMiningSpriteHintsExtra and type(_G.BitcoinMiningSpriteHintsExtra) == "table" then
        for _, hint in ipairs(_G.BitcoinMiningSpriteHintsExtra) do
            if nameHas(tostring(hint):lower()) then return true end
        end
    end
    return false
end

-- Backwards compatibility: some modules call isDesktopComputer
BitcoinMining.isDesktopComputer = BitcoinMining.isDesktopComputer or BitcoinMining.isComputerObject

----------------------------------------------------
-- Power detection at an object's square
----------------------------------------------------
function BitcoinMining.hasPowerAt(obj)
    if not obj or not obj.getSquare then return false end
    local sq = obj:getSquare(); if not sq then return false end
    if sq.haveElectricity and sq:haveElectricity() then return true end
    if IsoGenerator and IsoGenerator.getFreeGeneratorForSquare then
        return IsoGenerator:getFreeGeneratorForSquare(sq) ~= nil
    end
    return false
end

----------------------------------------------------
-- Rig modData helpers
----------------------------------------------------
local function ensureRigTable(obj)
    if not obj or not obj.getModData then return nil end
    local md = obj:getModData()
    md.BitcoinMining = md.BitcoinMining or {}
    return md.BitcoinMining
end

function BitcoinMining.getRigData(obj)
    local rig = ensureRigTable(obj)
    if not rig then return {} end
    if rig.active == nil then rig.active = false end
    if rig.powerOn == nil then rig.powerOn = false end
    return rig
end

function BitcoinMining.setRigOwnerFromPlayer(obj, player)
    local rig = BitcoinMining.getRigData(obj)
    if not rig or not player then return end
    if player.getSteamID then rig.ownerSteam = player:getSteamID() end
    if player.getOnlineID then rig.ownerOnline = player:getOnlineID() end
    if player.getUsername then rig.ownerName = player:getUsername() end
end

----------------------------------------------------
-- (Keep the rest of your util functions below; we preserve other logic)
----------------------------------------------------
-- Random helpers
----------------------------------------------------
function Util.randIndex(n)
    if not n or n <= 0 then return nil end
    return (ZombRand(n) + 1) -- Convert to 1-based
end
