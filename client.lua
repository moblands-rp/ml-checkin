-- =============================================
--   Hospital Check-In System | QBCore + ox_target
--   client.lua
-- =============================================

local QBCore = exports['qb-core']:GetCoreObject()

-- =============================================
-- CONFIG
-- =============================================
local Config = {
    CheckInCoords    = vector3(-436.04, -325.8, 34.91), -- adjust to your map
    BedSpawns = {
        { coords = vector4(-459.07, -279.75, 35.84, 206.76), label = "Bed 1" },
        { coords = vector4(-462.85, -281.22, 35.84, 208.42), label = "Bed 2" },
        { coords = vector4(-466.64, -282.78, 35.84, 205.14), label = "Bed 3" },
        { coords = vector4(-469.99, -284.07, 35.84, 205.09), label = "Bed 4" },
        { coords = vector4(-455.25, -277.98, 35.84, 207.69), label = "Bed 5" },
        { coords = vector4(-454.83, -286.53, 35.83, 28.74), label = "Bed 6" },
    },
    BlackoutDuration  = 3000, -- ms
    ReviveAnimation   = { dict = "amb@world_human_tourist_map@male@idle_a", clip = "idle_a" },
    NotificationCooldown = false,

    Crutch = {
        Duration   = 5 * 60,
        RemoveCost = 500,

        RemovePed = {
            model  = "s_m_m_doctor_01",
            coords = vector4(-444.77, -324.94, 34.91, 272.47),
        },

        PropModel    = "v_med_crutch01",  -- confirmed working GTA5 crutch model
        PropBone     = 70,              -- SKEL_L_Hand (left hand, matches crutch natural grip)
        PropOffset   = vector3(1.18, -0.36, -0.20),
        PropRotation = vector3(-20.0, -87.0, -20.0),

        LimpDict = "move_m@injured",
        LimpClip = "injured",
    },
}

-- =============================================
-- CRUTCH STATE
-- =============================================
local crutchActive    = false
local crutchProp      = nil
local crutchTimeLeft  = 0
local crutchEndTime   = 0
local removePedHandle = nil

-- =============================================
-- HELPERS
-- =============================================

local function Notify(msg, ntype, duration)
    QBCore.Functions.Notify(msg, ntype or "primary", duration or 5000)
end

local function FadeScreen(fadeOut, duration)
    if fadeOut then DoScreenFadeOut(duration) else DoScreenFadeIn(duration) end
end

local function LoadAnimDict(dict)
    RequestAnimDict(dict)
    local t = 0
    while not HasAnimDictLoaded(dict) and t < 100 do Wait(50); t = t + 1 end
end

local function LoadModel(model)
    local hash = type(model) == "number" and model or GetHashKey(model)
    RequestModel(hash)
    local t = 0
    while not HasModelLoaded(hash) and t < 100 do Wait(50); t = t + 1 end
    return hash
end

local function LoadInteriorAtCoords(x, y, z)
    local interior = GetInteriorAtCoords(x, y, z)
    if interior ~= 0 then RefreshInterior(interior) end
    Wait(1500)
end

local function FormatTime(seconds)
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%d:%02d", m, s)
end

-- =============================================
-- ELIGIBILITY CHECK
-- =============================================

local function IsPlayerEligible()
    local playerPed     = PlayerPedId()
    local playerData    = QBCore.Functions.GetPlayerData()
    local isDead        = playerData.metadata and playerData.metadata['isdead']
    local isInLastStand = playerData.metadata and playerData.metadata['inlaststand']
    local health        = GetEntityHealth(playerPed)

    if not isDead and not isInLastStand and health >= 200 then
        return false, "You are not injured. Only hurt or downed players can check in."
    end

    return true, nil
end

-- =============================================
-- CRUTCH SYSTEM
-- =============================================

local function RemoveCrutch(silent)
    if not crutchActive then return end
    crutchActive = false

    local playerPed = PlayerPedId()

    if crutchProp and DoesEntityExist(crutchProp) then
        DetachEntity(crutchProp, true, true)
        DeleteEntity(crutchProp)
    end
    crutchProp = nil

    ResetPedMovementClipset(playerPed, 0.0)
    SetPedCanRagdoll(playerPed, true)

    if removePedHandle and DoesEntityExist(removePedHandle) then
        exports.ox_target:removeLocalEntity(removePedHandle)
        DeleteEntity(removePedHandle)
    end
    removePedHandle = nil

    if not silent then
        Notify("Your crutch has been removed. Take it easy out there.", "success", 5000)
    end
end

local function AttachCrutchProp()
    local playerPed = PlayerPedId()
    local modelHash = LoadModel(Config.Crutch.PropModel)

    -- Spawn the prop at the player's position first
    local coords = GetEntityCoords(playerPed)
    crutchProp = CreateObject(modelHash, coords.x, coords.y, coords.z, true, true, false)

    if not DoesEntityExist(crutchProp) then
        print("[ml-checkin] ERROR: Failed to create crutch prop. Model may not exist: " .. Config.Crutch.PropModel)
        SetModelAsNoLongerNeeded(modelHash)
        return
    end

    SetEntityCollision(crutchProp, false, false)
    SetEntityVisible(crutchProp, true, false)

    -- GetPedBoneIndex converts the bone ID to an index for attachment
    local boneIndex = GetPedBoneIndex(playerPed, Config.Crutch.PropBone)

    AttachEntityToEntity(
        crutchProp,                         -- prop to attach
        playerPed,                          -- attach to player
        boneIndex,                          -- right hand bone index
        Config.Crutch.PropOffset.x,
        Config.Crutch.PropOffset.y,
        Config.Crutch.PropOffset.z,
        Config.Crutch.PropRotation.x,
        Config.Crutch.PropRotation.y,
        Config.Crutch.PropRotation.z,
        true,   -- p9
        true,   -- useSoftPinning
        false,  -- collision
        true,   -- isPed
        1,      -- vertexIndex
        true    -- fixedRot
    )

    SetModelAsNoLongerNeeded(modelHash)
    print("[ml-checkin] Crutch prop attached. Entity: " .. tostring(crutchProp) .. " | Bone index: " .. tostring(boneIndex))
end

local function ApplyLimp()
    local playerPed = PlayerPedId()
    LoadAnimDict(Config.Crutch.LimpDict)
    SetPedMovementClipset(playerPed, Config.Crutch.LimpDict, 0.25)
end

local function SpawnRemovePed()
    local pedCfg    = Config.Crutch.RemovePed
    local modelHash = LoadModel("s_m_m_doctor_01") -- UPDATED MODEL

    removePedHandle = CreatePed(0, modelHash,
        pedCfg.coords.x, pedCfg.coords.y, pedCfg.coords.z - 1.0,
        pedCfg.coords.w, false, false)

    if not DoesEntityExist(removePedHandle) then
        print("[ml-checkin] ERROR: Failed to spawn remove ped")
        return
    end

    SetEntityAsMissionEntity(removePedHandle, true, true)

    -- Ensure visibility + proper rendering
    SetEntityVisible(removePedHandle, true, false)
    SetPedDefaultComponentVariation(removePedHandle)

    -- Standard ped flags
    FreezeEntityPosition(removePedHandle, true)
    SetEntityInvincible(removePedHandle, true)
    SetBlockingOfNonTemporaryEvents(removePedHandle, true)
    SetPedCanRagdoll(removePedHandle, false)
    SetPedDiesWhenInjured(removePedHandle, false)

    SetModelAsNoLongerNeeded(modelHash)

    -- DEBUG
    print("[ml-checkin] Remove ped spawned:", removePedHandle)

    exports.ox_target:addLocalEntity(removePedHandle, {
        {
            label     = string.format("Pay $%s — Remove Crutch Early", Config.Crutch.RemoveCost),
            icon      = "fas fa-dollar-sign",
            distance  = 2.5,
            onSelect  = function()
                if not crutchActive then
                    Notify("You are not on a crutch.", "error")
                    return
                end
                TriggerServerEvent('hospital:crutch:payRemove', Config.Crutch.RemoveCost)
            end,
        },
        {
            label     = "Check Time Remaining",
            icon      = "fas fa-clock",
            distance  = 2.5,
            onSelect  = function()
                Notify(string.format("Crutch will be removed in %s.", FormatTime(crutchTimeLeft)), "primary", 4000)
            end,
        },
    })
end

local function StartCrutchTimer()
    crutchEndTime = GetGameTimer() + (Config.Crutch.Duration * 1000)

    CreateThread(function()
        while crutchActive do
            Wait(1000)

            local remaining = math.max(0, math.floor((crutchEndTime - GetGameTimer()) / 1000))
            crutchTimeLeft  = remaining

            if crutchActive then ApplyLimp() end

            if remaining <= 0 then
                RemoveCrutch(false)
                break
            end
        end
    end)
end

local function StartCrutch()
    if crutchActive then return end
    crutchActive   = true
    crutchTimeLeft = Config.Crutch.Duration

    AttachCrutchProp()
    ApplyLimp()
    SpawnRemovePed()
    StartCrutchTimer()

    Notify(string.format(
        "You have been given a crutch. It lasts 5 minutes, or visit the nurse nearby to pay $%s for early removal.",
        Config.Crutch.RemoveCost
    ), "primary", 8000)
end

-- =============================================
-- SERVER RESPONSES
-- =============================================

RegisterNetEvent('hospital:crutch:removed', function()
    RemoveCrutch(false)
end)

RegisterNetEvent('hospital:crutch:insufficientFunds', function()
    Notify(string.format("You need $%s to remove your crutch early.", Config.Crutch.RemoveCost), "error")
end)

-- =============================================
-- CHECK-IN LOGIC
-- =============================================

local function PerformCheckIn()
    if Config.NotificationCooldown then return end

    local eligible, reason = IsPlayerEligible()
    if not eligible then
        Notify(reason, "error")
        return
    end

    Config.NotificationCooldown = true

    QBCore.Functions.TriggerCallback('hospital:getBedAssignment', function(bedIndex)
        if not bedIndex then
            Notify("All hospital beds are currently occupied. Please wait.", "error")
            Config.NotificationCooldown = false
            return
        end

        local bed       = Config.BedSpawns[bedIndex]
        local playerPed = PlayerPedId()

        FadeScreen(true, Config.BlackoutDuration)
        Wait(Config.BlackoutDuration)

        ClearPedTasksImmediately(playerPed)
        SetPedCanRagdoll(playerPed, false)

        SetEntityCoords(playerPed, bed.coords.x, bed.coords.y, bed.coords.z, false, false, false, true)
        SetEntityHeading(playerPed, bed.coords.w)

        LoadInteriorAtCoords(bed.coords.x, bed.coords.y, bed.coords.z)

        TriggerServerEvent('hospital:revivePlayer', bedIndex)

        Wait(300)
        SetPedCanRagdoll(playerPed, true)

        LoadAnimDict(Config.ReviveAnimation.dict)
        TaskPlayAnim(playerPed, Config.ReviveAnimation.dict, Config.ReviveAnimation.clip,
            8.0, -8.0, -1, 1, 0, false, false, false)

        Wait(1000)
        FadeScreen(false, 1500)
        Wait(1500)

        ClearPedTasks(playerPed)

        Wait(500)
        Notify("You have been admitted to " .. bed.label .. ". NLR applies — forget the last 15 minutes.", "success", 8000)

        Wait(2000)
        StartCrutch()

        SetTimeout(10000, function()
            Config.NotificationCooldown = false
        end)
    end)
end

-- =============================================
-- OX_TARGET — CHECK-IN ZONE
-- =============================================

CreateThread(function()
    Wait(0)

    exports.ox_target:addSphereZone({
        coords  = Config.CheckInCoords,
        radius  = 1.5,
        debug   = false,
        options = {
            {
                label     = "Check In",
                icon      = "fas fa-hospital-alt",
                iconColor = "#4fc3f7",
                distance  = 2.5,
                onSelect  = function()
                    PerformCheckIn()
                end,
            },
        },
    })
end)

-- =============================================
-- DEV: live crutch adjustment command
-- Usage: /crutchadj <offsetX> <offsetY> <offsetZ> <rotX> <rotY> <rotZ>
-- Remove this block before going to production
-- =============================================

RegisterCommand('crutchadj', function(source, args)
    if not crutchActive or not crutchProp or not DoesEntityExist(crutchProp) then
        Notify("No active crutch to adjust.", "error")
        return
    end

    local ox = tonumber(args[1]) or 0.0
    local oy = tonumber(args[2]) or 0.0
    local oz = tonumber(args[3]) or 0.0
    local rx = tonumber(args[4]) or 0.0
    local ry = tonumber(args[5]) or 0.0
    local rz = tonumber(args[6]) or 0.0

    local playerPed = PlayerPedId()
    local boneIndex = GetPedBoneIndex(playerPed, Config.Crutch.PropBone)

    DetachEntity(crutchProp, true, true)
    AttachEntityToEntity(
        crutchProp, playerPed, boneIndex,
        ox, oy, oz, rx, ry, rz,
        true, true, false, true, 1, true
    )

    Notify(string.format("Crutch adjusted — Offset: %.2f %.2f %.2f | Rot: %.2f %.2f %.2f", ox, oy, oz, rx, ry, rz), "primary", 4000)
    print(string.format("[ml-checkin] PropOffset = vector3(%.2f, %.2f, %.2f), PropRotation = vector3(%.2f, %.2f, %.2f)", ox, oy, oz, rx, ry, rz))
end, false)

-- =============================================
-- EVENTS FROM SERVER
-- =============================================

RegisterNetEvent('hospital:clientRevive', function()
    local playerPed = PlayerPedId()
    SetEntityHealth(playerPed, 200)
    SetPedArmour(playerPed, 100)
    ClearPedTasksImmediately(playerPed)
    SetPedCanRagdoll(playerPed, false)
    Wait(100)
    SetPedCanRagdoll(playerPed, true)
end)
