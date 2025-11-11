-- File: media/lua/shared/BitcoinMining_Common.lua
-- Lightweight shared constants and helpers used across modules.
require("BitcoinMining_Sandbox")

BitcoinMining = BitcoinMining or {}
BitcoinMining.Common = BitcoinMining.Common or {}
local C = BitcoinMining.Common

C.VERSION = "1.0.0"
C.MODULE  = "PZBitcoinMining"

-- Translation helper with safe fallback
function C.T(key, ...)
    if not key or key == "" then return "" end
    if getText then
        local ok, str = pcall(getText, key, ...)
        if ok and str then return str end
    end
    return tostring(key)
end

-- Math helpers
function C.clamp(v, lo, hi)
    if v == nil then return nil end
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function C.round(n) return math.floor((n or 0) + 0.5) end

-- Ownership helper: stable ledger key from a rig's modData
function C.ownerKeyFromRig(rig)
    if not rig then return nil end
    return rig.ownerSteam or rig.ownerName or tostring(rig.ownerOnline)
end

-- Reward helper: single source of truth wrapper
function C.getRewardForInterval()
    if BitcoinMiningCfg and BitcoinMiningCfg.getBatchRewardForInterval then
        return BitcoinMiningCfg.getBatchRewardForInterval()
    end
    -- Fallback to SandboxVars if config module isn't available
    local perHour
    local minutes
    if SandboxVars then
        if SandboxVars.bitcoinmining then
            perHour = SandboxVars.bitcoinmining.CoinsPerGameHour or 100
            minutes = SandboxVars.bitcoinmining.PayoutIntervalMinutes or 60
        elseif SandboxVars.BitcoinMining then -- compatibility with old namespace
            perHour = SandboxVars.BitcoinMining.CoinsPerGameHour or 100
            minutes = SandboxVars.BitcoinMining.PayoutIntervalMinutes or 60
        end
    end
    perHour = perHour or 100
    minutes = minutes or 60
    local amt = math.floor((perHour * minutes) / 60)
    return (amt > 0) and amt or 1
end

return C
