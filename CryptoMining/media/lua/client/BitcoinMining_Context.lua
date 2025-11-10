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
        if HaloTextHelper and getText then
            HaloTextHelper.addText(player, getText("Tooltip_ComputerOff"), 255, 180, 50)
        end
        return
    end

    -- Power gating
    if BitcoinMiningCfg.isPowerRequired() and not BitcoinMining.hasPowerAt(obj) then
        if HaloTextHelper and getText then
            HaloTextHelper.addText(player, getText("UI_Mining_NoPower"), 255, 50, 50)
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
    if not obj then return end
    local rig = BitcoinMining.getRigData(obj)
    rig.active = false
    obj:transmitModData()

    Util.log("CTX", "Stop request at %d,%d,%d", obj:getX(), obj:getY(), obj:getZ())
    sendClientCommand("PZBitcoinMining", "Stop", { x = obj:getX(), y = obj:getY(), z = obj:getZ() })
end

-- Expose handlers (referenced by context menu options)
BitcoinMining.startMining = onStartMining
BitcoinMining.stopMining  = onStopMining

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

    -- Turn on/off options
    if rig.powerOn then
        context:addOption(getText("StartStop_TurnOffComputer"), { player = player, obj = computer }, onTurnOff)
    else
        context:addOption(getText("StartStop_TurnOnComputer"), { player = player, obj = computer }, onTurnOn)
    end

    if rig.active then
        context:addOption(getText("StartStop_StopMining"), { player = player, obj = computer }, onStopMining)
    else
        local opt = context:addOption(getText("StartStop_StartMining"), { player = player, obj = computer }, onStartMining)
        if BitcoinMiningCfg.isPowerRequired() and not hasPower then
            opt.notAvailable = true
            if ISToolTip and getText then
                local tt = ISToolTip:new()
                tt.description = getText("Tooltip_NoPower")
                opt.toolTip = tt
            end
        elseif not rig.powerOn then
            opt.notAvailable = true
            if ISToolTip and getText then
                local tt = ISToolTip:new()
                tt.description = getText("Tooltip_ComputerOff")
                opt.toolTip = tt
            end
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
