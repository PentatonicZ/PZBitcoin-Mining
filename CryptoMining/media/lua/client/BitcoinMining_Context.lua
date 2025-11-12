require("BitcoinMining_Sandbox")
require("BitcoinMining_Util")
require("BitcoinMining_Common")


BitcoinMining = BitcoinMining or {}
local Util = BitcoinMining.Util or { log = function() end }

local function findComputerInWorldObjects(worldobjects)
    if not worldobjects then return nil end
    for _, o in ipairs(worldobjects) do
        if o and instanceof(o, "IsoObject") and BitcoinMining.isDesktopComputer(o) then
            return o
        end
    end
    return nil
end

-- Translation helper with default fallback
local function L(key, default, ...)
    if getText then
        local ok, val = pcall(getText, key, ...)
        if ok and val and val ~= key then return val end
    end
    if select('#', ...) > 0 then
        local ok2, msg = pcall(string.format, default or "", ...)
        if ok2 and msg then return msg end
    end
    return default
end

-- Simple name truncation for compact HUD/status text
local function truncName(name, maxLen)
    local s = tostring(name or "")
    local n = tonumber(maxLen) or 16
    if #s <= n then return s end
    return s:sub(1, n - 3) .. "..."
end

local function getPlayerIds(player)
    if not player then return nil, nil, nil end
    local steamID  = player.getSteamID and player:getSteamID() or nil
    local onlineID = player.getOnlineID and player:getOnlineID() or nil
    local username = player.getUsername and player:getUsername() or nil
    return steamID, onlineID, username
end

local function onStartMining(data)
    local obj = data and data.obj or nil
    local player = data and data.player or getSpecificPlayer(0)
    if not obj or not player then return end

    local rig = BitcoinMining.getRigData(obj)
    -- Must be turned on
    if not BitcoinMining.getRigData(obj).powerOn then
        if HaloTextHelper then
            HaloTextHelper.addText(player, L("Tooltip_ComputerOff", "Computer is turned off."), 255, 180, 50)
        end
        return
    end

    -- Power gating
    if BitcoinMiningCfg.isPowerRequired() and not BitcoinMining.hasPowerAt(obj) then
        if HaloTextHelper then
            HaloTextHelper.addText(player, L("UI_Mining_NoPower", "No power at this computer"), 255, 50, 50)
        end
        return
    end

    -- Prevent multiple users on the same machine
    if rig.active then
        if HaloTextHelper then
            local owner = rig.ownerName or rig.ownerSteam or rig.ownerOnline or "unknown"
            owner = truncName(owner, 18)
            HaloTextHelper.addText(player, L("UI_Mining_AlreadyActive", "Mining already active (owner: %s)", tostring(owner)), 255, 180, 50)
        end
        return
    end

    -- Activate + record owner locally
    rig.active = true
    BitcoinMining.setRigOwnerFromPlayer(obj, player)
    obj:transmitModData()

    local sid, oid, uname = getPlayerIds(player)
    Util.log("CTX", "Start request at %d,%d,%d by %s", obj:getX(), obj:getY(), obj:getZ(), tostring(uname))
    sendClientCommand("PZBitcoinMining", "Start", {
        x = obj:getX(), y = obj:getY(), z = obj:getZ(),
        steamID = sid, onlineID = oid, username = uname,
    })
end

local function onStopMining(data)
    local obj = data and data.obj or nil
    local player = data and data.player or getSpecificPlayer(0)
    if not obj or not player then return end
    local rig = BitcoinMining.getRigData(obj)
    rig.active = false
    obj:transmitModData()

    local sid, oid, uname = getPlayerIds(player)
    Util.log("CTX", "Stop request at %d,%d,%d by %s", obj:getX(), obj:getY(), obj:getZ(), tostring(uname))
    sendClientCommand("PZBitcoinMining", "Stop", { x = obj:getX(), y = obj:getY(), z = obj:getZ(), steamID = sid, onlineID = oid, username = uname })
end

-- Expose handlers (referenced by context menu options)
BitcoinMining.startMining = onStartMining
BitcoinMining.stopMining  = onStopMining

-- Check mining status (simple HUD text for now)
local function onCheckMiningStatus(data)
    local obj = data and data.obj or nil
    local player = data and data.player or getSpecificPlayer(0)
    if not obj or not player then return end
    local rig = BitcoinMining.getRigData(obj)
    local status
    if rig.active then
        local owner = rig.ownerName or rig.ownerSteam or rig.ownerOnline or "unknown"
        owner = truncName(owner, 18)
        local pow = rig.powerOn and L("UI_Generic_On", "On") or L("UI_Generic_Off", "Off")
        status = L("UI_Mining_StatusActive", "Mining ACTIVE. Owner: %s. Power: %s", tostring(owner), tostring(pow))
    else
        status = L("UI_Mining_StatusInactive", "No mining job running on this computer")
    end
    if HaloTextHelper then
        HaloTextHelper.addText(player, status, 180, 220, 255)
    else
        print("[PZBitcoinMining] " .. tostring(status))
    end
end

BitcoinMining.checkMiningStatus = onCheckMiningStatus

-- Placeholder for hacking option
local function onHackComputer(data)
    local player = data and data.player or getSpecificPlayer(0)
    if HaloTextHelper then
        HaloTextHelper.addText(player, L("UI_Mining_HackNotImplemented", "Hacking is not implemented yet."), 255, 120, 120)
    end
end

BitcoinMining.hackComputer = onHackComputer

local function onTurnOn(data)
    local obj = data and data.obj or nil
    local player = data and data.player or getSpecificPlayer(0)
    if not obj then return end
    local rig = BitcoinMining.getRigData(obj)
    if rig.powerOn then return end
    rig.powerOn = true
    obj:transmitModData()
    Util.log("CTX", "Turn ON @ %d,%d,%d", obj:getX(), obj:getY(), obj:getZ())
    sendClientCommand("PZBitcoinMining", "TogglePower", { x = obj:getX(), y = obj:getY(), z = obj:getZ(), powerOn = true })
end

local function onTurnOff(data)
    local obj = data and data.obj or nil
    if not obj then return end
    local rig = BitcoinMining.getRigData(obj)
    if not rig.powerOn then return end
    rig.powerOn = false
    obj:transmitModData()
    Util.log("CTX", "Turn OFF @ %d,%d,%d", obj:getX(), obj:getY(), obj:getZ())
    sendClientCommand("PZBitcoinMining", "TogglePower", { x = obj:getX(), y = obj:getY(), z = obj:getZ(), powerOn = false })
end

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if not BitcoinMiningCfg.isEnabled() then return end
    local player = getSpecificPlayer(playerNum)
    if not player then return end

    local computer = findComputerInWorldObjects(worldobjects)
    if not computer then return end
    if test then return true end

    local rig = BitcoinMining.getRigData(computer)
    local hasPower = BitcoinMining.hasPowerAt(computer)

    -- Always offer to check status
    context:addOption(L("StartStop_CheckMiningStatus", "Check Mining Status"), { player = player, obj = computer }, onCheckMiningStatus)

    -- Turn on/off options
    if rig.powerOn then
        context:addOption(L("StartStop_TurnOffComputer", "Turn Off Computer"), { player = player, obj = computer }, onTurnOff)
    else
        context:addOption(L("StartStop_TurnOnComputer", "Turn On Computer"), { player = player, obj = computer }, onTurnOn)
    end

    if not rig.active then
        local opt = context:addOption(L("StartStop_StartMining", "Start Cryptomining"), { player = player, obj = computer }, onStartMining)
        if BitcoinMiningCfg.isPowerRequired() and not hasPower then
            opt.notAvailable = true
            if ISToolTip and getText then
                local tt = ISToolTip:new()
                tt.description = L("Tooltip_NoPower", "Requires electricity to operate.")
                opt.toolTip = tt
            end
        elseif not rig.powerOn then
            opt.notAvailable = true
            if ISToolTip and getText then
                local tt = ISToolTip:new()
                tt.description = L("Tooltip_ComputerOff", "Computer is turned off.")
                opt.toolTip = tt
            end
        end
    else
        -- Mining active: only the owner can stop
        local sid, oid, uname = getPlayerIds(player)
        local isOwner = (rig.ownerSteam and sid and rig.ownerSteam == sid)
            or (rig.ownerOnline and oid and rig.ownerOnline == oid)
            or (rig.ownerName and uname and rig.ownerName == uname)
        if isOwner then
            context:addOption(L("StartStop_StopMining", "Stop Cryptomining"), { player = player, obj = computer }, onStopMining)
        else
            local opt = context:addOption(L("StartStop_StopMiningOwnerOnly", "Stop Mining (Owner Only)"), { player = player, obj = computer }, nil)
            opt.notAvailable = true
            if ISToolTip and getText then
                local tt = ISToolTip:new()
                tt.description = L("Tooltip_NotOwner", "Only the owner can stop this job.")
                opt.toolTip = tt
            end
        end
    end

    -- Admin submenu (client-side trigger)
    local isAdmin = (player.isAdmin and player:isAdmin())
        or (player.getAccessLevel and ((player:getAccessLevel() or ""):lower() == "admin" or (player:getAccessLevel() or ""):lower() == "moderator"))
    if isAdmin then
        local subMenu = ISContextMenu:getNew(context)
        context:addSubMenu(context:addOption(L("Admin_Mining", "Mining Admin")), subMenu)

        subMenu:addOption(L("Admin_Count", "Count Active Rigs"), {}, function()
            sendClientCommand("PZBitcoinMining", "AdminAction", { action = "count" })
        end)

        subMenu:addOption(L("Admin_List", "List Active Rigs (10)"), {}, function()
            sendClientCommand("PZBitcoinMining", "AdminAction", { action = "list", limit = 10 })
        end)

        subMenu:addOption(L("Admin_StatusHere", "Status For This Computer"), { obj = computer }, function(d)
            local o = d.obj; if not o then return end
            sendClientCommand("PZBitcoinMining", "AdminAction", { action = "status", x = o:getX(), y = o:getY(), z = o:getZ() })
        end)

        subMenu:addOption(L("Admin_PowerHere", "Power Check This Computer"), { obj = computer }, function(d)
            local o = d.obj; if not o then return end
            sendClientCommand("PZBitcoinMining", "AdminAction", { action = "power", x = o:getX(), y = o:getY(), z = o:getZ() })
        end)

        subMenu:addOption(L("Admin_StopHere", "Force Stop This Computer"), { obj = computer }, function(d)
            local o = d.obj; if not o then return end
            sendClientCommand("PZBitcoinMining", "AdminAction", { action = "stop", x = o:getX(), y = o:getY(), z = o:getZ() })
        end)
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
