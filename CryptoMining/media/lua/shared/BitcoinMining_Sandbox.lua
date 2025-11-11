-- BitcoinMining_Sandbox.lua
-- Centralized SandboxVars handling for the Bitcoin Mining mod.

BitcoinMiningCfg = BitcoinMiningCfg or {}

local function ensure()
    SandboxVars = SandboxVars or {}
    SandboxVars.bitcoinmining = SandboxVars.bitcoinmining or {}
    local S = SandboxVars.bitcoinmining

    -- Defaults (only if missing)
    if S.Enabled == nil then S.Enabled = true end
    if S.CoinsPerGameHour == nil then S.CoinsPerGameHour = 100 end
    if S.PayoutIntervalMinutes == nil then S.PayoutIntervalMinutes = 60 end
    if S.PowerRequired == nil then S.PowerRequired = true end
    if S.RequireDesktopOnly == nil then S.RequireDesktopOnly = true end
    if S.RequireComputerOn == nil then S.RequireComputerOn = true end
    if S.AllowManualComputerPower == nil then S.AllowManualComputerPower = true end

    -- Clamp numeric values
    local function clamp(v, lo, hi)
        v = tonumber(v)
        if not v then return nil end
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    S.CoinsPerGameHour = clamp(S.CoinsPerGameHour, 1, 100000) or 100
    S.PayoutIntervalMinutes = clamp(S.PayoutIntervalMinutes, 1, 1440) or 60

    return S
end

function BitcoinMiningCfg.get()
    return ensure()
end

function BitcoinMiningCfg.isEnabled()
    return ensure().Enabled ~= false
end

function BitcoinMiningCfg.getCoinsPerGameHour()
    return ensure().CoinsPerGameHour
end

function BitcoinMiningCfg.getPayoutIntervalMinutes()
    return ensure().PayoutIntervalMinutes
end

function BitcoinMiningCfg.isPowerRequired()
    return ensure().PowerRequired == true
end

function BitcoinMiningCfg.getBatchRewardForInterval()
    local S = ensure()
    local perHour = tonumber(S.CoinsPerGameHour) or 100
    local interval = tonumber(S.PayoutIntervalMinutes) or 60
    local amount = math.floor((perHour * interval) / 60)
    if amount <= 0 then amount = 1 end
    return amount
end

return BitcoinMiningCfg
