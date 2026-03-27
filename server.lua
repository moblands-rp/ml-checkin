-- =============================================
--   Hospital Check-In System | QBCore + ox_target
--   server.lua
-- =============================================

local QBCore = exports['qb-core']:GetCoreObject()

-- =============================================
-- BED STATE TRACKING
-- =============================================
local BedOccupancy = { false, false, false, false, false, false }

local function GetFreeBed()
    for i, occupied in ipairs(BedOccupancy) do
        if not occupied then return i end
    end
    return nil
end

local function FreeBed(bedIndex)
    if bedIndex and BedOccupancy[bedIndex] then
        BedOccupancy[bedIndex] = false
    end
end

-- =============================================
-- CALLBACK — assign a bed
-- =============================================

QBCore.Functions.CreateCallback('hospital:getBedAssignment', function(source, cb)
    local bedIndex = GetFreeBed()
    if not bedIndex then cb(nil); return end
    BedOccupancy[bedIndex] = source
    cb(bedIndex)
end)

-- =============================================
-- EVENT — full revive using qb-ambulancejob's
-- own client event: hospital:client:Revive
-- This is the same event the /revive admin command
-- and txAdmin heal use — it properly clears the
-- bleedout timer, death screen, and all metadata.
-- =============================================

RegisterNetEvent('hospital:revivePlayer', function(bedIndex)
    local src    = source
    local Player = QBCore.Functions.GetPlayer(src)

    if not Player then return end

    -- Restore all stats
    Player.Functions.SetMetaData('hunger',       100)
    Player.Functions.SetMetaData('thirst',       100)
    Player.Functions.SetMetaData('stress',       0)
    Player.Functions.SetMetaData('armor',        100)
    Player.Functions.SetMetaData('isdead',       false)
    Player.Functions.SetMetaData('inlaststand',  false)

    -- Trigger qb-ambulancejob's own revive client event directly on the player.
    -- This clears the bleedout timer, death UI, and ragdoll state properly.
    TriggerClientEvent('hospital:client:Revive', src)

    -- Also trigger our own client event for health/armour top-up
    TriggerClientEvent('hospital:clientRevive', src)

    print(string.format(
        "[ml-checkin] Player %s (src: %d) revived on Bed %d",
        Player.PlayerData.charinfo and Player.PlayerData.charinfo.firstname or "Unknown",
        src, bedIndex
    ))

    -- Auto-free bed after 30 seconds
    SetTimeout(30000, function()
        if BedOccupancy[bedIndex] == src then
            FreeBed(bedIndex)
        end
    end)
end)

-- =============================================
-- SAFETY — free bed on disconnect
-- =============================================

AddEventHandler('playerDropped', function()
    local src = source
    for i, occupant in ipairs(BedOccupancy) do
        if occupant == src then
            FreeBed(i)
        end
    end
end)

-- =============================================
-- ADMIN: clear all beds
-- =============================================

QBCore.Commands.Add('clearbeds', 'Clear all hospital bed occupancy (Admin)', {}, false, function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    if not QBCore.Functions.HasPermission(source, 'admin') then
        TriggerClientEvent('QBCore:Notify', source, "No permission.", "error")
        return
    end
    for i = 1, #BedOccupancy do BedOccupancy[i] = false end
    TriggerClientEvent('QBCore:Notify', source, "All hospital beds cleared.", "success")
end, 'admin')

-- =============================================
-- CRUTCH — pay to remove
-- =============================================

RegisterNetEvent('hospital:crutch:payRemove', function(cost)
    local src    = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local cash = Player.PlayerData.money['cash']
    local bank = Player.PlayerData.money['bank']

    -- Try cash first, then bank
    if cash >= cost then
        Player.Functions.RemoveMoney('cash', cost, 'crutch-removal')
        TriggerClientEvent('hospital:crutch:removed', src)
        TriggerClientEvent('QBCore:Notify', src, "Paid $" .. cost .. " cash to remove crutch.", "success")
    elseif bank >= cost then
        Player.Functions.RemoveMoney('bank', cost, 'crutch-removal')
        TriggerClientEvent('hospital:crutch:removed', src)
        TriggerClientEvent('QBCore:Notify', src, "Paid $" .. cost .. " from bank to remove crutch.", "success")
    else
        TriggerClientEvent('hospital:crutch:insufficientFunds', src)
    end
end)
