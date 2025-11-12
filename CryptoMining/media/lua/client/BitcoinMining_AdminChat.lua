-- Client bridge for admin chat commands
-- Detects "/mining ..." typed by the local player and forwards
-- to the server via sendClientCommand so dedicated servers that
-- don't fire OnPlayerChat server-side still work.

local function onPlayerChatClient(player, msg)
    if not player or not msg or type(msg) ~= "string" then return end
    if not msg:find("^%s*/mining") then return end
    sendClientCommand("PZBitcoinMining", "AdminChat", { raw = msg })
end

if Events and Events.OnPlayerChat and Events.OnPlayerChat.Add then
    Events.OnPlayerChat.Add(onPlayerChatClient)
end
