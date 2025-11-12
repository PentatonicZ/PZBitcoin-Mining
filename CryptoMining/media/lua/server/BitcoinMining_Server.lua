local ok_cfg, err_cfg = pcall(require, "BitcoinMining_Sandbox")
if not ok_cfg then
    print("[PZBitcoinMining] WARN: Sandbox config not loaded: "..tostring(err_cfg))
end
BitcoinMiningCfg = BitcoinMiningCfg or {}
if not BitcoinMiningCfg.isEnabled then function BitcoinMiningCfg.isEnabled() return true end end
if not BitcoinMiningCfg.getPayoutIntervalMinutes then function BitcoinMiningCfg.getPayoutIntervalMinutes() return 60 end end
if not BitcoinMiningCfg.getBatchRewardForInterval then function BitcoinMiningCfg.getBatchRewardForInterval() return 1 end end

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
    if not (BitcoinMiningCfg and BitcoinMiningCfg.isEnabled and BitcoinMiningCfg.isEnabled()) then return end
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
        if rig.active then
            Util.log("CMD", "Start: already active at %d,%d,%d (owner=%s)", obj:getX(), obj:getY(), obj:getZ(), tostring(rig.ownerName or rig.ownerSteam or rig.ownerOnline))
            return
        end
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
        -- Only the owner can stop
        local sid  = args.steamID
        local oid  = args.onlineID
        local name = args.username
        local isOwner = (rig.ownerSteam and sid and rig.ownerSteam == sid)
            or (rig.ownerOnline and oid and rig.ownerOnline == oid)
            or (rig.ownerName and name and rig.ownerName == name)
        if not isOwner then
            Util.log("CMD", "Stop: denied (not owner) at %d,%d,%d", obj:getX(), obj:getY(), obj:getZ())
            return
        end
        rig.active = false
        obj:transmitModData()
        Util.log("CMD", "Stop: cleared active at %d,%d,%d by %s", obj:getX(), obj:getY(), obj:getZ(), tostring(name or sid or oid))
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
    elseif command == "AdminAction" then
        args = args or {}
        local action = (args.action or ""):lower()
        if not isAdminPlayer(player) then
            adminSay(player, "Mining: admin only command")
            return
        end
        if action == "count" then
            local rigs = collectActiveRigs()
            adminSay(player, string.format("Active mining rigs: %d", #rigs))
            return
        elseif action == "list" then
            local limit = tonumber(args.limit) or 10
            local rigs = collectActiveRigs()
            adminSay(player, string.format("Active rigs: %d (showing up to %d)", #rigs, limit))
            for i = 1, math.min(#rigs, limit) do
                adminSay(player, summarizeRig(rigs[i]))
            end
            return
        elseif action == "status" then
            local obj = findObjectAt(args.x, args.y, args.z)
            if not obj then adminSay(player, "No computer at coordinates"); return end
            local rig = BitcoinMining.getRigData(obj)
            local s = {
                string.format("Coords=(%d,%d,%d)", obj:getX(), obj:getY(), obj:getZ()),
                string.format("Active=%s PowerOn=%s HasPower=%s", tostring(rig.active == true), tostring(rig.powerOn == true), tostring(BitcoinMining.hasPowerAt(obj))),
                string.format("Owner=%s", tostring(rig.ownerName or rig.ownerSteam or rig.ownerOnline or "unknown")),
            }
            for _, line in ipairs(s) do adminSay(player, line) end
            return
        elseif action == "power" then
            local obj = findObjectAt(args.x, args.y, args.z)
            if not obj then adminSay(player, "No computer at coordinates"); return end
            local sq = obj:getSquare()
            local grid = (sq and sq.haveElectricity and sq:haveElectricity()) and true or false
            local hydro = (getWorld and getWorld() and getWorld().isHydroPowerOn and getWorld():isHydroPowerOn()) and true or false
            local gen = false
            if IsoGenerator and IsoGenerator.getFreeGeneratorForSquare and sq then
                gen = IsoGenerator:getFreeGeneratorForSquare(sq) and true or false
            end
            adminSay(player, string.format("PowerCheck grid=%s hydro=%s generator=%s final=%s", tostring(grid), tostring(hydro), tostring(gen), tostring(BitcoinMining.hasPowerAt(obj))))
            return
        elseif action == "stop" then
            local obj = findObjectAt(args.x, args.y, args.z)
            if not obj then adminSay(player, "No computer at coordinates"); return end
            local rig = BitcoinMining.getRigData(obj)
            if rig.active then
                rig.active = false
                obj:transmitModData()
                adminSay(player, string.format("Stopped mining @ (%d,%d,%d)", obj:getX(), obj:getY(), obj:getZ()))
            else
                adminSay(player, "Rig not active")
            end
            return
        end
        return
    elseif command == "AdminChat" then
        -- Bridge from client chat -> server handler
        if args and args.raw then
            if handleAdminText then
                handleAdminText(player, tostring(args.raw))
            end
        end
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

-- Admin Chat Commands -------------------------------------------------------
-- Usage (admin only, typed into chat):
--   /mining help
--   /mining count
--   /mining list [limit]
--   /mining status <x> <y> <z>
--   /mining stop <x> <y> <z>

local function isAdminPlayer(p)
    if not p then return false end
    if p.isAdmin and p:isAdmin() then return true end
    if p.getAccessLevel then
        local lvl = (p:getAccessLevel() or ""):lower()
        if lvl == "admin" or lvl == "moderator" then return true end
    end
    return false
end

local function adminSay(p, msg)
    if not p or not msg then return end
    if BTSE and BTSE.Commands and BTSE.Commands.sendSuccessMessage then
        BTSE.Commands:sendSuccessMessage(p, { tostring(msg) })
        if BTSE.Commands.sendHaloMessage then
            BTSE.Commands:sendHaloMessage(p, "success", { tostring(msg) })
        end
        return
    end
    if p.Say then p:Say(tostring(msg)) else print("[PZBitcoinMining][ADMIN] "..tostring(msg)) end
end

local function summarizeRig(r)
    local rig = r.rig or {}
    local o = r.obj
    local owner = rig.ownerName or rig.ownerSteam or rig.ownerOnline or "unknown"
    local pow = rig.powerOn and "On" or "Off"
    return string.format("@(%d,%d,%d) active=%s power=%s owner=%s", o:getX(), o:getY(), o:getZ(), tostring(rig.active == true), pow, tostring(owner))
end

local function handleAdminText(player, msg)
    if type(msg) ~= "string" then return end
    local text = msg
    if not text or not text:find("^%s*/mining") then return end
    if not isAdminPlayer(player) then
        adminSay(player, "Mining: admin only command")
        return
    end

    local args = text:gsub("^%s*/mining%s*", "")
    args = args or ""
    local command, rest = args:match("^(%S+)%s*(.*)$")
    command = (command or ""):lower()

    if command == "" or command == "help" then
        adminSay(player, "/mining help | count | list [N] | status x y z | stop x y z")
        return
    elseif command == "count" then
        local rigs = collectActiveRigs()
        adminSay(player, string.format("Active mining rigs: %d", #rigs))
        return
    elseif command == "list" then
        local limit = tonumber(rest) or 10
        local rigs = collectActiveRigs()
        adminSay(player, string.format("Active rigs: %d (showing up to %d)", #rigs, limit))
        for i = 1, math.min(#rigs, limit) do
            adminSay(player, summarizeRig(rigs[i]))
        end
        return
    elseif command == "status" then
        local x,y,z = rest:match("^(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)")
        if not x then adminSay(player, "Usage: /mining status x y z"); return end
        local obj = findObjectAt(tonumber(x), tonumber(y), tonumber(z))
        if not obj then adminSay(player, "No computer at coordinates"); return end
        local rig = BitcoinMining.getRigData(obj)
        local s = {
            string.format("Coords=(%d,%d,%d)", obj:getX(), obj:getY(), obj:getZ()),
            string.format("Active=%s PowerOn=%s HasPower=%s", tostring(rig.active == true), tostring(rig.powerOn == true), tostring(BitcoinMining.hasPowerAt(obj))),
            string.format("Owner=%s", tostring(rig.ownerName or rig.ownerSteam or rig.ownerOnline or "unknown")),
        }
        for _, line in ipairs(s) do adminSay(player, line) end
        return
    elseif command == "power" then
        local x,y,z = rest:match("^(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)")
        if not x then adminSay(player, "Usage: /mining power x y z"); return end
        local obj = findObjectAt(tonumber(x), tonumber(y), tonumber(z))
        if not obj then adminSay(player, "No computer at coordinates"); return end
        local sq = obj:getSquare()
        local grid = (sq and sq.haveElectricity and sq:haveElectricity()) and true or false
        local hydro = (getWorld and getWorld() and getWorld().isHydroPowerOn and getWorld():isHydroPowerOn()) and true or false
        local gen = false
        if IsoGenerator and IsoGenerator.getFreeGeneratorForSquare and sq then
            gen = IsoGenerator:getFreeGeneratorForSquare(sq) and true or false
        end
        adminSay(player, string.format("PowerCheck grid=%s hydro=%s generator=%s final=%s", tostring(grid), tostring(hydro), tostring(gen), tostring(BitcoinMining.hasPowerAt(obj))))
        return
    elseif command == "stop" then
        local x,y,z = rest:match("^(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)")
        if not x then adminSay(player, "Usage: /mining stop x y z"); return end
        local obj = findObjectAt(tonumber(x), tonumber(y), tonumber(z))
        if not obj then adminSay(player, "No computer at coordinates"); return end
        local rig = BitcoinMining.getRigData(obj)
        if rig.active then
            rig.active = false
            obj:transmitModData()
            adminSay(player, string.format("Stopped mining @ (%d,%d,%d)", obj:getX(), obj:getY(), obj:getZ()))
        else
            adminSay(player, "Rig not active")
        end
        return
    else
        adminSay(player, "Unknown command. Use /mining help")
        return
    end
end

local function onPlayerChat(player, msg)
    handleAdminText(player, msg)
end

Events.OnPlayerChat.Add(onPlayerChat)

-- BTSE (PARP) chat integration ---------------------------------------------
BTSE = BTSE or {}
BTSE.Commands = BTSE.Commands or {}
BTSE.Commands.Mining = BTSE.Commands.Mining or {}

local function ensureAdmin(player)
    if not isAdminPlayer(player) then
        adminSay(player, "Mining: admin only command")
        return false
    end
    return true
end

function BTSE.Commands.Mining.count(player, args)
    if not ensureAdmin(player) then return end
    local rigs = collectActiveRigs()
    adminSay(player, string.format("Active mining rigs: %d", #rigs))
end

function BTSE.Commands.Mining.list(player, args)
    if not ensureAdmin(player) then return end
    local limit = tonumber(args and args.limit) or 10
    local rigs = collectActiveRigs()
    adminSay(player, string.format("Active rigs: %d (showing up to %d)", #rigs, limit))
    for i = 1, math.min(#rigs, limit) do
        adminSay(player, summarizeRig(rigs[i]))
    end
end

function BTSE.Commands.Mining.status(player, args)
    if not ensureAdmin(player) then return end
    if not args or not args.x then adminSay(player, "Usage: /mining status x y z"); return end
    local obj = findObjectAt(args.x, args.y, args.z)
    if not obj then adminSay(player, "No computer at coordinates"); return end
    local rig = BitcoinMining.getRigData(obj)
    local s = {
        string.format("Coords=(%d,%d,%d)", obj:getX(), obj:getY(), obj:getZ()),
        string.format("Active=%s PowerOn=%s HasPower=%s", tostring(rig.active == true), tostring(rig.powerOn == true), tostring(BitcoinMining.hasPowerAt(obj))),
        string.format("Owner=%s", tostring(rig.ownerName or rig.ownerSteam or rig.ownerOnline or "unknown")),
    }
    for _, line in ipairs(s) do adminSay(player, line) end
end

function BTSE.Commands.Mining.power(player, args)
    if not ensureAdmin(player) then return end
    if not args or not args.x then adminSay(player, "Usage: /mining power x y z"); return end
    local obj = findObjectAt(args.x, args.y, args.z)
    if not obj then adminSay(player, "No computer at coordinates"); return end
    local sq = obj:getSquare()
    local grid = (sq and sq.haveElectricity and sq:haveElectricity()) and true or false
    local hydro = (getWorld and getWorld() and getWorld().isHydroPowerOn and getWorld():isHydroPowerOn()) and true or false
    local gen = false
    if IsoGenerator and IsoGenerator.getFreeGeneratorForSquare and sq then
        gen = IsoGenerator:getFreeGeneratorForSquare(sq) and true or false
    end
    adminSay(player, string.format("PowerCheck grid=%s hydro=%s generator=%s final=%s", tostring(grid), tostring(hydro), tostring(gen), tostring(BitcoinMining.hasPowerAt(obj))))
end

function BTSE.Commands.Mining.stop(player, args)
    if not ensureAdmin(player) then return end
    if not args or not args.x then adminSay(player, "Usage: /mining stop x y z"); return end
    local obj = findObjectAt(args.x, args.y, args.z)
    if not obj then adminSay(player, "No computer at coordinates"); return end
    local rig = BitcoinMining.getRigData(obj)
    if rig.active then
        rig.active = false
        obj:transmitModData()
        adminSay(player, string.format("Stopped mining @ (%d,%d,%d)", obj:getX(), obj:getY(), obj:getZ()))
    else
        adminSay(player, "Rig not active")
    end
end

Events.OnClientCommand.Add(function(moduleName, command, playerObj, args)
    if moduleName == "btse_mining" and BTSE.Commands.Mining[command] then
        BTSE.Commands.Mining[command](playerObj, args or {})
    end
end)
