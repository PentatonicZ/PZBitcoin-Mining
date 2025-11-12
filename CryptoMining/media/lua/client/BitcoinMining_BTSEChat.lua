-- Integrate /mining commands with BTSE (PARP) chat framework.
-- This registers a custom command that forwards actions to the server
-- via BTSE.CommandQueue using module "btse_mining".

local function register()
    if not PARP or not PARP.Chat or not PARP.Chat.registerCommand then return end
    if not BTSE or not BTSE.CommandQueue or not BTSE.CommandQueue.addToQueue then return end

    local function send(action, args)
        args = args or {}
        args.action = action
        BTSE.CommandQueue:addToQueue(PARP:getPlayer(), "btse_mining", action, args)
    end

    local function onMining(message, cmd)
        message = tostring(message or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if message == "" then
            return getText and getText("IGUI_PZBM_MiningHelp") or "/mining help | count | list [N] | status x y z | power x y z | stop x y z"
        end

        local a,b,c,d = message:match("^(%S+)%s*(%S*)%s*(%S*)%s*(%S*)")
        local sub = (a or ""):lower()

        if sub == "help" then
            return getText and getText("IGUI_PZBM_MiningHelp") or "/mining help | count | list [N] | status x y z | power x y z | stop x y z"
        elseif sub == "count" then
            send("count", {})
            return true
        elseif sub == "list" then
            local limit = tonumber(b) or 10
            send("list", { limit = limit })
            return true
        elseif sub == "status" then
            local x,y,z = tonumber(b), tonumber(c), tonumber(d)
            if not x or not y or not z then return "Usage: /mining status x y z" end
            send("status", { x = x, y = y, z = z })
            return true
        elseif sub == "power" then
            local x,y,z = tonumber(b), tonumber(c), tonumber(d)
            if not x or not y or not z then return "Usage: /mining power x y z" end
            send("power", { x = x, y = y, z = z })
            return true
        elseif sub == "stop" then
            local x,y,z = tonumber(b), tonumber(c), tonumber(d)
            if not x or not y or not z then return "Usage: /mining stop x y z" end
            send("stop", { x = x, y = y, z = z })
            return true
        else
            return "Unknown subcommand. Try /mining help"
        end
    end

    PARP.Chat:registerCommand({"mining","crypto","cryptomining"}, onMining, {
        useCase = "Admin mining controls",
        needsPayload = false,
        group = "admin",
        restrict = "admin",
        tabSwitch = false,
    })
end

Events.OnGameBoot.Add(register)

