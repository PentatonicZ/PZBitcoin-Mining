-- File: media/lua/shared/BitcoinMining_Util.lua
--[[
    BitcoinMining_Util.lua
    ------------------------------------------------
    Shared helpers used by both client and server.
    - Object detection (computer identification)
    - Power checks (grid/generator)
    - Ownership tagging on rigs
    - BikiniTools currency integration (shim)
    - Logging and small utilities
--]]

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
-- Known vanilla/mapping sprite fragments. Server owners can extend with global table `BitcoinMiningSpriteHintsExtra`.
BitcoinMining.ComputerSpriteHints = BitcoinMining.ComputerSpriteHints or {
    "furniture_computer", "fixtures_computer", "office_01_", "office_02_",
    "computertable", "desktop_computer", "terminal",
}

-- Desktop-only hints: stricter than generic computer hints
BitcoinMining.DesktopSpriteHints = BitcoinMining.DesktopSpriteHints or {
    "desktop_computer",    -- explicit desktop naming when present
    "furniture_computer",  -- vanilla desks with tower/monitor
}

local function _spriteHasComputerKeyword(name)
    name = string.lower(name or "")
    for _, hint in ipairs(BitcoinMining.ComputerSpriteHints) do
        if string.find(name, string.lower(hint), 1, true) then return true end
    end
    if _G.BitcoinMiningSpriteHintsExtra and type(_G.BitcoinMiningSpriteHintsExtra) == "table" then
        for _, hint in ipairs(_G.BitcoinMiningSpriteHintsExtra) do
            if string.find(name, string.lower(tostring(hint)), 1, true) then return true end
        end
    end
    return false
end

function BitcoinMining.isComputerObject(obj)
    if not obj or not obj.getSprite then return false end
    local spr = obj:getSprite(); if not spr then return false end
    local name = spr:getName() or ""

    -- Fast path by sprite name
    if _spriteHasComputerKeyword(name) then return true end

    -- Try properties on the sprite (mappers sometimes tag props)
    local props = spr:getProperties()
    if props then
        local propName = tostring(props:Is("Computer"))
        if propName == "true" then return true end
    end

    return false
end

-- Restrictive detection for desktop computers only
function BitcoinMining.isDesktopComputer(obj)
    if not obj or not obj.getSprite then return false end
    local spr = obj:getSprite(); if not spr then return false end
    local name = string.lower(spr:getName() or "")
    for _, hint in ipairs(BitcoinMining.DesktopSpriteHints) do
        if string.find(name, string.lower(hint), 1, true) then return true end
    end
    -- Optional extension via global list
    if _G.BitcoinMiningDesktopHintsExtra and type(_G.BitcoinMiningDesktopHintsExtra) == "table" then
        for _, hint in ipairs(_G.BitcoinMiningDesktopHintsExtra) do
            if string.find(name, string.lower(tostring(hint)), 1, true) then return true end
        end
    end
    return false
end

----------------------------------------------------
-- Power checks
----------------------------------------------------
local function _hasGridPowerAtSquare(sq)
    return sq and sq.haveElectricity and sq:haveElectricity() == true
end

local function _generatorProvidesPower(sq)
    if not sq then return false end
    -- Best-effort: try vanilla generator query if available
    if IsoGenerator and IsoGenerator.getFreeGeneratorForSquare then
        if IsoGenerator:getFreeGeneratorForSquare(sq) ~= nil then return true end
    end
    -- Fallback heuristic: search 5x5 around for an active generator flagged for this building
    if not IsoGenerator or not _G.getWorld then return false end
    local r = 2
    for x = sq:getX() - r, sq:getX() + r do
        for y = sq:getY() - r, sq:getY() + r do
            local nsq = getCell():getGridSquare(x, y, sq:getZ())
            if nsq then
                local objs = nsq:getObjects(); if objs then
                    for i=0, objs:size()-1 do
                        local o = objs:get(i)
                        if instanceof(o, "IsoGenerator") then
                            -- Try some common flags
                            if o:isActivated() then return true end
                        end
                    end
                end
            end
        end
    end
    return false
end

function BitcoinMining.hasPowerAt(obj)
    local sq = obj and obj.getSquare and obj:getSquare() or nil
    if not sq then return false end
    if _hasGridPowerAtSquare(sq) then return true end
    return _generatorProvidesPower(sq)
end

----------------------------------------------------
-- Rig modData helpers
----------------------------------------------------
function BitcoinMining.getRigData(obj)
    local md = obj:getModData()
    md.BitcoinMining = md.BitcoinMining or {
        active=false,
        lastTick=nil,
        accrued=0,
        ownerSteam=nil,
        ownerOnline=nil,
        ownerName=nil,
        powerOn=false,
    }
    return md.BitcoinMining
end

function BitcoinMining.clearRigOwner(obj)
    local rig = BitcoinMining.getRigData(obj)
    rig.ownerSteam, rig.ownerOnline, rig.ownerName = nil, nil, nil
    obj:transmitModData()
end

function BitcoinMining.setRigOwnerFromPlayer(obj, player)
    if not player then return end
    local rig = BitcoinMining.getRigData(obj)
    rig.ownerSteam  = player.getSteamID and player:getSteamID() or rig.ownerSteam
    rig.ownerOnline = player.getOnlineID and player:getOnlineID() or rig.ownerOnline
    rig.ownerName   = player.getUsername and player:getUsername() or rig.ownerName
    obj:transmitModData()
end

----------------------------------------------------
-- BikiniTools currency integration (shim)
----------------------------------------------------
BitcoinMining.Bikini = BitcoinMining.Bikini or {}

-- Adds money to a player's BikiniTools balance. Returns true if dispatched.
function BitcoinMining.Bikini.addMoney(player, amount, reason)
    reason = reason or "Crypto Mining"
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end

    -- 1) Direct global call pattern
    if _G.BikiniTools and type(_G.BikiniTools.AddMoney) == "function" then
        Util.log("$", "BikiniTools.AddMoney direct: %s", tostring(amount))
        local ok = _G.BikiniTools.AddMoney(player, amount, reason)
        return ok ~= false
    end

    -- 2) Client->Server command (module/command names are guesses; adjust to your server)
    if isClient() then
        Util.log("$", "sendClientCommand BikiniTools:AddMoney %s", tostring(amount))
        sendClientCommand("BikiniTools", "AddMoney", { amount = amount, reason = reason })
        return true
    end

    -- 3) Server-side dispatch (if server-only API exists)
    if isServer() and _G.BikiniTools and type(_G.BikiniTools.ServerAddMoney) == "function" then
        Util.log("$", "BikiniTools.ServerAddMoney: %s", tostring(amount))
        local ok = _G.BikiniTools.ServerAddMoney(player, amount, reason)
        return ok ~= false
    end

    -- 4) Fallback: store pending on player modData so we can grant later when API is available
    local S = BitcoinMiningCfg.get()
    if S.FailIfNoBikiniTools then
        Util.log("$", "BikiniTools missing and FailIfNoBikiniTools=true; not crediting")
        return false
    end
    local pmd = player and player.getModData and player:getModData() or nil
    if pmd then
        pmd.BikiniToolsPending = (pmd.BikiniToolsPending or 0) + amount
        Util.log("$", "Queued pending %s to player modData", tostring(amount))
        return true
    end
    return false
end

----------------------------------------------------
-- Random helpers
----------------------------------------------------
function Util.randIndex(n)
    if not n or n <= 0 then return nil end
    return (ZombRand(n) + 1) -- Convert to 1-based
end
