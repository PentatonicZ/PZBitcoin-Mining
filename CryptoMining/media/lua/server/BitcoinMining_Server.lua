require("BitcoinMining_Sandbox")
require("BitcoinMining_Util")
require("BitcoinMining_Common")

BitcoinMining = BitcoinMining or {}
local Util = BitcoinMining.Util or { log = function() end }

-- Time helpers
local function worldMinutes()
    local hrs = getGameTime() and getGameTime():getWorldAgeHours() or 0
    return math.floor((hrs or 0) * 60)
end

-- Persistent world state
local function getServerState()
    local md = getWorld() and getWorld():getModData() or {}
    md.BitcoinMining = md.BitcoinMining or { lastPayoutMinutes = nil, pendingBySteamID = {} }
    return md.BitcoinMining
end

-- Object finder
local function findObjectAt(x, y, z)
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    local sq = cell:getGridSquare(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
    if not sq or not sq.getObjects then return nil end
    local list = sq:getObjects()
    for i = 0, (list:size() - 1) do
        local o = list:get(i)
        if o and BitcoinMining.isDesktopComputer(o) then return o end
    end
    return nil
end

-- Active rig predicate (active flag + power requirement)
local function isRigActive(obj)
    if not obj then return false end
    local rig = BitcoinMining.getRigData(obj)
    if not rig or rig.active ~= true then return false end
    if not rig.powerOn then return false end
    if BitcoinMiningCfg.isPowerRequired() and not BitcoinMining.hasPowerAt(obj) then return false end
    return true
end

-- Collect all currently active rigs (loaded objects only)
local function collectActiveRigs()
    local rigs = {}
    local cell = getCell and getCell() or nil
    if not cell or not cell.getObjectList then return rigs end
    local objs = cell:getObjectList()
    if not objs then return rigs end
    for i = 0, (objs:size() - 1) do
        local o = objs:get(i)
        if o and BitcoinMining.isDesktopComputer(o) and isRigActive(o) then
            table.insert(rigs, { obj = o, rig = BitcoinMining.getRigData(o) })
        end
    end
    return rigs
end

local function getRewardForInterval()
    -- Single source of truth for reward computation
    if BitcoinMiningCfg and BitcoinMiningCfg.getBatchRewardForInterval then
        return tonumber(BitcoinMiningCfg.getBatchRewardForInterval()) or 1
    end
    -- Fallback conservative
    return 1
end

-- Try to find an online player by any of the owner IDs
local function findOnlinePlayer(steamID, onlineID, username)
    local list = getOnlinePlayers and getOnlinePlayers() or nil
    if list and list.size and list:size() > 0 then
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            if p then
                local ps = p.getSteamID and p:getSteamID() or nil
                local po = p.getOnlineID and p:getOnlineID() or nil
                local pn = p.getUsername and p:getUsername() or nil
                if (steamID and ps == steamID) or (onlineID and po == onlineID) or (username and pn == username) then
                    return p
                end
            end
        end
    end
    return nil
end

-- Credit currency, or queue if offline
local function creditByOwner(steamID, onlineID, username, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end

    local p = findOnlinePlayer(steamID, onlineID, username)
    if p then
        Util.log("PAY", "Online payout %s to %s", tostring(amount), tostring(p:getUsername()))
        return BitcoinMining.Bikini.addMoney(p, amount, "Crypto Mining Lottery")
    end

    local key = steamID or username or (onlineID and tostring(onlineID)) or nil
    if not key then return false end
    local S = getServerState()
    S.pendingBySteamID[key] = (S.pendingBySteamID[key] or 0) + amount
    Util.log("PAY", "Queued %s for key=%s", tostring(amount), tostring(key))
    return true
end

-- Perform one lottery payout among active rigs
local function performLotteryPayout()
    local rigs = collectActiveRigs()
    if #rigs == 0 then
        Util.log("LOT", "No active rigs; skipping payout")
        return false
    end
    local idx = (BitcoinMining.Util and BitcoinMining.Util.randIndex and BitcoinMining.Util.randIndex(#rigs)) or (ZombRand(#rigs) + 1)
    local winner = rigs[idx]
    if not winner or not winner.obj or not winner.rig then return false end

    local amt = getRewardForInterval()
    local r = winner.rig
    Util.log("LOT", "Winner @ (%d,%d,%d) owner=%s amount=%s", winner.obj:getX(), winner.obj:getY(), winner.obj:getZ(), tostring(r.ownerName or r.ownerSteam or r.ownerOnline), tostring(amt))
    creditByOwner(r.ownerSteam, r.ownerOnline, r.ownerName, amt)
    return true
end

-- Scheduler: EveryTenMinutes, check if an interval elapsed and payout accordingly
local function onEveryTenMinutes()
    if not BitcoinMiningCfg.isEnabled() then return end
    local S = getServerState()
    local now = worldMinutes()
    local interval = tonumber(BitcoinMiningCfg.getPayoutIntervalMinutes()) or 60
    if interval < 1 then interval = 1 end

    if not S.lastPayoutMinutes then
        S.lastPayoutMinutes = now
        Util.log("SCH", "Init lastPayout=%d interval=%d", S.lastPayoutMinutes, interval)
        return
    end

    local elapsed = now - (S.lastPayoutMinutes or now)
    if elapsed >= interval then
        local times = math.floor(elapsed / interval)
        Util.log("SCH", "Payout tick times=%d (elapsed=%d, interval=%d)", times, elapsed, interval)
        for _ = 1, times do
            performLotteryPayout()
        end
        S.lastPayoutMinutes = S.lastPayoutMinutes + (times * interval)
    end
end

Events.EveryTenMinutes.Add(onEveryTenMinutes)

-- Client command handling for start/stop
local function onClientCommand(module, command, player, args)
    if module ~= "PZBitcoinMining" then return end
    args = args or {}
    if command == "Start" then
        local x,y,z = args.x, args.y, args.z
        local obj = findObjectAt(x,y,z)
        if not obj then
            Util.log("CMD", "Start: no object at %s,%s,%s", tostring(x), tostring(y), tostring(z))
            return
        end
        local rig = BitcoinMining.getRigData(obj)
        rig.active = true
        rig.ownerSteam  = args.steamID or rig.ownerSteam
        rig.ownerOnline = args.onlineID or rig.ownerOnline
        rig.ownerName   = args.username or rig.ownerName
        obj:transmitModData()
        Util.log("CMD", "Start: set active at %d,%d,%d owner=%s", obj:getX(), obj:getY(), obj:getZ(), tostring(rig.ownerName or rig.ownerSteam or rig.ownerOnline))
        return
    elseif command == "Stop" then
        local x,y,z = args.x, args.y, args.z
        local obj = findObjectAt(x,y,z)
        if not obj then
            Util.log("CMD", "Stop: no object at %s,%s,%s", tostring(x), tostring(y), tostring(z))
            return
        end
        local rig = BitcoinMining.getRigData(obj)
        rig.active = false
        obj:transmitModData()
        Util.log("CMD", "Stop: cleared active at %d,%d,%d", obj:getX(), obj:getY(), obj:getZ())
        return
    elseif command == "TogglePower" then
        local x,y,z = args.x, args.y, args.z
        local obj = findObjectAt(x,y,z)
        if not obj then
            Util.log("CMD", "TogglePower: no object at %s,%s,%s", tostring(x), tostring(y), tostring(z))
            return
        end
        local rig = BitcoinMining.getRigData(obj)
        local p = args.powerOn == true
        rig.powerOn = p
        obj:transmitModData()
        Util.log("CMD", "TogglePower: %s at %d,%d,%d", p and "ON" or "OFF", obj:getX(), obj:getY(), obj:getZ())
        return
    end
end

Events.OnClientCommand.Add(onClientCommand)

-- Pending payout on login
local function onPlayerConnect(player)
    if not player then return end
    local sid = player.getSteamID and player:getSteamID() or nil
    local oid = player.getOnlineID and player:getOnlineID() or nil
    local name = player.getUsername and player:getUsername() or nil
    local S = getServerState()

    -- Resolve keys we might have used
    local keys = {}
    if sid then table.insert(keys, sid) end
    if name then table.insert(keys, name) end
    if oid then table.insert(keys, tostring(oid)) end

    local total = 0
    for _, k in ipairs(keys) do
        local amt = S.pendingBySteamID[k]
        if amt and amt > 0 then
            total = total + amt
            S.pendingBySteamID[k] = 0
        end
    end

    if total > 0 then
        Util.log("PEND", "Paying pending %s to %s", tostring(total), tostring(name or sid or oid))
        BitcoinMining.Bikini.addMoney(player, total, "Crypto Mining Lottery (Pending)")
    end
end

Events.OnPlayerConnect.Add(onPlayerConnect)
