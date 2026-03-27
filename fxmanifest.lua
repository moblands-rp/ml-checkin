shared_script '@WaveShield/resource/include.lua'

-- =============================================
--   Hospital Check-In System | QBCore + ox_target
--   fxmanifest.lua
-- =============================================

fx_version  'cerulean'
game        'gta5'

name        'ml-checkin'
description 'QBCore hospital check-in system using ox_target with bed assignment and NLR notification'
author      'YourName'
version     '1.0.0'

shared_scripts {
    '@qb-core/shared/locale.lua',
}

client_scripts {
    'client.lua',
}

server_scripts {
    'server.lua',
}

dependencies {
    'qb-core',
    'ox_target',
}
