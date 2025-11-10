# File: workshop.txt
version=1
id=999999999
name=PZ Bitcoin Mining (BikiniTools)
description=Adds right-click crypto mining to existing computers and credits money via BikiniTools.

# File: mod.info
name=PZ Bitcoin Mining (BikiniTools)
id=PZBitcoinMining
poster=poster.png
url=
version=1.0
 
# File: media/lua/shared/BitcoinMining_Sandbox.lua
--[[
    BitcoinMining_Sandbox.lua
    ---------------------------------
    Declares and validates all Sandbox (tunable) options for the Bitcoin Mining mod.
    This file is intentionally lightweight and safe to run on both client and server.

    Server owners can override these in the save's SandboxVars.lua under the "BitcoinMining" table.
    We only set defaults if a value is missing, so explicit server values are respected.
--]]

BitcoinMiningCfg = BitcoinMiningCfg or {}

local function _ensure()
    SandboxVars.BitcoinMining = SandboxVars.BitcoinMining or {}
    local S = SandboxVars.BitcoinMining

    -- Defaults (only if missing)
    if S.Enabled == nil then S.Enabled = true end

    -- Treated as the block/batch reward rate per in-game hour (global, not per-rig).
    if S.CoinsPerGameHour == nil then S.CoinsPerGameHour = 100 end

    -- How often (real-time, in-game minutes) to choose a single lottery winner among active rigs.
    if S.PayoutIntervalMinutes == nil then S.PayoutIntervalMinutes = 60 end

    if S.PowerRequired == nil then S.PowerRequired = true end

    -- Optional flavor tunables for future expansion
    if S.GenFuelPerHour == nil then S.GenFuelPerHour = 0.02 end    -- extra generator fuel burn per hour while a rig is active
    if S.Heat == nil then S.Heat = 2 end                          -- additive room heat while mining
    if S.NoiseRadius == nil then S.NoiseRadius = 6 end             -- sound radius in tiles while mining

    -- If true, do not silently accrue pending currency when BikiniTools is missing
    if S.FailIfNoBikiniTools == nil then S.FailIfNoBikiniTools = false end

    -- Validation / clamping
    local function clamp(v, lo, hi)
        if v == nil then return nil end
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    S.CoinsPerGameHour     = clamp(tonumber(S.CoinsPerGameHour) or 100, 1, 100000)
    S.PayoutIntervalMinutes= clamp(tonumber(S.PayoutIntervalMinutes) or 60, 1, 24*60)
    S.GenFuelPerHour       = clamp(tonumber(S.GenFuelPerHour) or 0, 0, 10)
    S.Heat                 = clamp(tonumber(S.Heat) or 0, 0, 50)
    S.NoiseRadius          = clamp(tonumber(S.NoiseRadius) or 0, 0, 50)

    return S
end

-- Public getters used by other modules (avoid touching SandboxVars directly elsewhere)
function BitcoinMiningCfg.get()
    return _ensure()
end

function BitcoinMiningCfg.isEnabled()
    return _ensure().Enabled ~= false
end

function BitcoinMiningCfg.getCoinsPerGameHour()
    return _ensure().CoinsPerGameHour
end

function BitcoinMiningCfg.getPayoutIntervalMinutes()
    return _ensure().PayoutIntervalMinutes
end

function BitcoinMiningCfg.isPowerRequired()
    return _ensure().PowerRequired == true
end

function BitcoinMiningCfg.getBatchRewardForInterval()
    local S = _ensure()
    local perHour = S.CoinsPerGameHour
    local interval = S.PayoutIntervalMinutes
    local amount = math.floor((perHour * interval) / 60)
    if amount <= 0 then amount = 1 end
    return amount
end

-- Make sure defaults are applied on load
_ensure()

# File: media/lua/shared/BitcoinMining_Util.lua
BitcoinMining = BitcoinMining or {}

-- Known vanilla computer-like sprite name fragments to detect in-world computers.
BitcoinMining.ComputerSpriteHints = {
    "furniture_computer", "fixtures_computer", "office_01_", "office_02_",
}

function BitcoinMining.isComputerObject(obj)
    if not obj or not obj.getSprite then return false end
    local spr = obj:getSprite()
    if not spr then return false end
    local name = spr:getName() or ""
    name = string.lower(name)
    for _, hint in ipairs(BitcoinMining.ComputerSpriteHints) do
        if string.find(name, string.lower(hint), 1, true) then
            return true
        end
    end
    return false
end

function BitcoinMining.hasPowerAt(obj)
    if not obj then return false end
    local sq = obj:getSquare()
    if not sq then return false end
    -- Grid or generator power
    return sq:haveElectricity() or (sq:isOutside() == false and IsoGenerator and IsoGenerator.getFreeGeneratorForSquare and IsoGenerator:getFreeGeneratorForSquare(sq) ~= nil)
end

function BitcoinMining.getRigData(obj)
    local md = obj:getModData()
    md.BitcoinMining = md.BitcoinMining or {active=false, lastTick=nil, accrued=0}
    return md.BitcoinMining
end

function BitcoinMining.getCoinsPerHour()
    -- Interpreted as the batch reward per in-game hour (not per rig).
    return SandboxVars.BitcoinMining and SandboxVars.BitcoinMining.CoinsPerGameHour or 100
end

-- BikiniTools integration shim. Adjust to your server's API if needed.
BitcoinMining.Bikini = {}

-- Try a few common patterns. Replace with your exact server API if different.
function BitcoinMining.Bikini.addMoney(player, amount, reason)
    reason = reason or "Crypto Mining"
    -- 1) Direct global call pattern
    if _G.BikiniTools and type(_G.BikiniTools.AddMoney) == "function" then
        return _G.BikiniTools.AddMoney(player, amount, reason)
    end
    -- 2) Client->Server command pattern
    if isClient() then
        sendClientCommand("BikiniTools", "AddMoney", { amount = amount, reason = reason })
        return true
    end
    -- 3) Server-side dispatch (if server-only API exists)
    if isServer() and _G.BikiniTools and type(_G.BikiniTools.ServerAddMoney) == "function" then
        return _G.BikiniTools.ServerAddMoney(player, amount, reason)
    end
    if SandboxVars.BitcoinMining and SandboxVars.BitcoinMining.FailIfNoBikiniTools then
        return false
    end
    -- Fallback: store on player modData to grant later when BikiniTools loads
    local pmd = player:getModData()
    pmd.BikiniToolsPending = (pmd.BikiniToolsPending or 0) + amount
    return true
end

# File: media/lua/client/BitcoinMining_Context.lua
require("BitcoinMining_Util")

local function addMiningOptions(playerNum, context, worldobjects, test)
    local player = getSpecificPlayer(playerNum)
    if not player then return end

    local computer
    for _, o in ipairs(worldobjects) do
        if instanceof(o, "IsoObject") and BitcoinMining.isComputerObject(o) then
            computer = o; break
        end
    end
    if not computer then return end

    if test then return true end -- context scan phase

    local rig = BitcoinMining.getRigData(computer)
    local hasPower = BitcoinMining.hasPowerAt(computer)

    if rig.active then
        context:addOption(getText("StartStop_StopMining"), {player=player, obj=computer}, BitcoinMining.stopMining)
    else
        local opt = context:addOption(getText("StartStop_StartMining"), {player=player, obj=computer}, BitcoinMining.startMining)
        if SandboxVars.BitcoinMining.PowerRequired and not hasPower then
            opt.notAvailable = true
            opt.toolTip = ISToolTip:new()
            opt.toolTip.description = getText("Tooltip_NoPower")
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(addMiningOptions)

local function getPlayerSteamOrOnlineID(p)
    local sid = p.getSteamID and p:getSteamID() or nil
    local oid = p.getOnlineID and p:getOnlineID() or nil
    return sid, oid
end

function BitcoinMining.startMining(data)
    local obj = data.obj
    local rig = BitcoinMining.getRigData(obj)
    if SandboxVars.BitcoinMining.PowerRequired and not BitcoinMining.hasPowerAt(obj) then
        HaloTextHelper.addText(getSpecificPlayer(0), getText("UI_Mining_NoPower"), 255,50,50)
        return
    end
    local player = data.player or getSpecificPlayer(0)
    local sid, oid = getPlayerSteamOrOnlineID(player)

    rig.active = true
    rig.lastTick = getGameTime():getWorldAgeHours()
    obj:transmitModData()
    sendClientCommand("PZBitcoinMining", "Start", { x=obj:getX(), y=obj:getY(), z=obj:getZ(), steamID=sid, onlineID=oid, username=player:getUsername() })
end

function BitcoinMining.stopMining(data)
    local obj = data.obj
    local rig = BitcoinMining.getRigData(obj)
    rig.active = false
    obj:transmitModData()
    sendClientCommand("PZBitcoinMining", "Stop", { x=obj:getX(), y=obj:getY(), z=obj:getZ() })
end

# File: media/lua/server/BitcoinMining_Server.lua
require("BitcoinMining_Util")

local function findObjectAt(x,y,z)
    local sq = getCell():getGridSquare(x,y,z)
    if not sq then return nil end
    for i=0, sq:getObjects():size()-1 do
        local o = sq:getObjects():get(i)
        if BitcoinMining.isComputerObject(o) then return o end
    end
    return nil
end

local function getServerState()
    local md = getWorld():getModData()
    md.BitcoinMining = md.BitcoinMining or { lastPayoutMinutes=nil, pendingBySteamID={} }
    return md.BitcoinMining
end

local function worldMinutes()
    return math.floor(getGameTime():getWorldAgeHours() * 60)
end

local function isRigActive(obj)
    local rig = BitcoinMining.getRigData(obj)
    if not rig.active then return false end
    if SandboxVars.BitcoinMining.PowerRequired and not BitcoinMining.hasPowerAt(obj) then return false end
    return true
end

local function collectActiveRigs()
    local rigs = {}
    local cells = getWorld():getCell(); if not cells then return rigs end
    local list = cells:getObjectList(); if not list then return rigs end
    for i=0, list:size()-1 do
        local o = list:get(i)
        if BitcoinMining.isComputerObject(o) and isRigActive(o) then
            local md = BitcoinMining.getRigData(o)
            table.insert(rigs, {obj=o, ownerSteam=md.ownerSteam, ownerOnline=md.ownerOnline, ownerName=md.ownerName})
        end
    end
    return rigs
end

local function findOnlinePlayerByOwner(ownerSteam, ownerOnline, ownerName)
    for i=0, getOnlinePlayers():size()-1 do
        local p = getOnlinePlayers():get(i)
        if ownerSteam and p.getSteamID and p:getSteamID() == ownerSteam then return p end
        if ownerOnline and p.getOnlineID and p:getOnlineID() == ownerOnline then return p end
        if ownerName and p.getUsername and p:getUsername() == ownerName then return p end
    end
    return nil
end

local function creditByOwner(ownerSteam, ownerOnline, ownerName, amount)
    local p = findOnlinePlayerByOwner(ownerSteam, ownerOnline, ownerName)
    if p then
        return BitcoinMining.Bikini.addMoney(p, amount, "Crypto Mining Lottery")
    end
    -- Not online: hold it in a pending ledger keyed by steamID or name
    local state = getServerState()
    local key = ownerSteam or ownerName or tostring(ownerOnline)
    if not key then return false end
    state.pendingBySteamID[key] = (state.pendingBySteamID[key] or 0) + amount
    return true
end

local function payPendingIfAny(player)
    local state = getServerState()
    local key = (player.getSteamID and player:getSteamID()) or player:getUsername()
    local pending = key and state.pendingBySteamID[key] or 0
    if pending and pending > 0 then
        BitcoinMining.Bikini.addMoney(player, pending, "Crypto Mining Lottery (Pending)")
        state.pendingBySteamID[key] = 0
    end
end

if Events.OnPlayerConnect then
    Events.OnPlayerConnect.Add(function(player)
        payPendingIfAny(player)
    end)
end

local function performLotteryPayout()
    local rigs = collectActiveRigs()
    if #rigs == 0 then return end

    -- Choose one random winner uniformly among active rigs
    local idx = ZombRand(#rigs) + 1 -- ZombRand is 0-based
    local winner = rigs[idx]

    local intervalMin = SandboxVars.BitcoinMining.PayoutIntervalMinutes or 60
    local rewardPerHour = BitcoinMining.getCoinsPerHour()
    local amount = math.floor((rewardPerHour * intervalMin) / 60)
    if amount <= 0 then amount = 1 end

    creditByOwner(winner.ownerSteam, winner.ownerOnline, winner.ownerName, amount)
end

Events.EveryTenMinutes.Add(function()
    local state = getServerState()
    local now = worldMinutes()
    local intervalMin = SandboxVars.BitcoinMining.PayoutIntervalMinutes or 60
    local last = state.lastPayoutMinutes or now
    if now - last >= intervalMin then
        performLotteryPayout()
        -- Advance last payout by one or more full intervals to catch up
        local intervals = math.floor((now - last) / intervalMin)
        state.lastPayoutMinutes = last + intervals * intervalMin
    end
end)

-- Client commands: record ownership to award correctly
Events.OnClientCommand.Add(function(module, command, args)
    if module ~= "PZBitcoinMining" then return end
    if command == "Start" then
        local obj = findObjectAt(args.x,args.y,args.z); if not obj then return end
        local rig = BitcoinMining.getRigData(obj)
        rig.active = true
        rig.ownerSteam = args.steamID
        rig.ownerOnline = args.onlineID
        rig.ownerName = args.username
        obj:transmitModData()
    elseif command == "Stop" then
        local obj = findObjectAt(args.x,args.y,args.z); if not obj then return end
        local rig = BitcoinMining.getRigData(obj)
        rig.active = false
        obj:transmitModData()
    end
end)

# File: media/lua/client/BitcoinMining_Translations_EN.txt
UI_Mining_NoPower = No power at this computer
StartStop_StartMining = Start Cryptomining (BikiniTools)
StartStop_StopMining = Stop Cryptomining
Tooltip_NoPower = Requires electricity to operate.
UI_Mining_PayoutInterval = Payout interval (minutes)
UI_Mining_BatchPerHour = Batch reward coins per in-game hour

