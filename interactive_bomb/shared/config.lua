Config = {}
Config.Model = 'ib_case'
Config.StateKey = 'ibomb:state'
Config.Types = { explosive = true, bio = true, nuke = true, emp = true }
Config.WireColors = { 'red', 'blue', 'green', 'yellow', 'white' }
Config.SwitchIds = { '1', '2' }
Config.KnobIds = { '1', '2' }
Config.SpawnDistance = 5.0
Config.InteractDistance = 2.2
Config.MaxBombs = 20
Config.DurationSeconds = 180
Config.StreamDistance = 220.0 -- garde les zones IEM dans le registre client
Config.PartsDistance = 45.0
Config.MaxRendered = 8
Config.ScreenDistance = 8.0
Config.MaxScreens = 4
Config.TargetRadius = 0.035
Config.DebugSockets = false
Config.EnableScriptFires = false -- opt-in : le feu natif peut brûler et se propager
Config.EffectVisuals = {
    maxParticles = 48, -- budget de boucles PTFX par client, toutes bombes confondues
    maxDistance = 200.0,
    flash = true,
    cameraShake = true,
    soundVolume = 0.7,
    explosive = { soundRadius = 90.0, lightRadius = 24.0, shake = 0.22 },
    bio = { soundRadius = 35.0, lightRadius = 9.0, shake = 0.04 },
    nuke = { soundRadius = 200.0, lightRadius = 70.0, shake = 0.65 },
    emp = { soundRadius = 120.0, lightRadius = 35.0, shake = 0.09 }
}
Config.Effects = {
    explosive = { radius = 12.0, duration = 20, damage = 70 },
    bio = { radius = 12.0, duration = 30, damage = 3 },
    nuke = { radius = 35.0, duration = 45, damage = 5 },
    emp = { radius = 120.0, duration = 25, damage = 0 }
}

-- Sons GTA de repli. Un vrai bruit de pince nécessite votre banque audio.
Config.Sounds = {
    cut = { name = 'NAV_UP_DOWN', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    key = { name = 'SELECT', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    switch = { name = 'NAV_UP_DOWN', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' }
}

-- Coordonnées locales en mètres, alignées sur le gabarit Blender.
-- Les os exportés sont utilisés en priorité. Ces coordonnées servent de
-- diagnostic/repli si un socket manque, avec avertissement dans F8.
Config.Sockets = {
    bone_switch_1 = { -0.230, 0.120, 0.170 },
    bone_switch_2 = { -0.155, 0.120, 0.170 },
    bone_knob_1 = { -0.065, 0.120, 0.170 },
    bone_knob_2 = { 0.015, 0.120, 0.170 },
    bone_gauge_needle = { 0.175, 0.065, 0.172 },
    bone_screen = { 0.140, 0.170, 0.166 },
    bone_vial_slot_1 = { -0.225, -0.160, 0.160 },
    bone_vial_slot_2 = { -0.130, -0.160, 0.160 }
}
for i, color in ipairs(Config.WireColors) do
    for _, suffix in ipairs({ 'intact', 'cut_a', 'cut_b' }) do
        Config.Sockets['bone_wire_' .. color .. '_' .. suffix] = {
            -0.230 + (i - 1) * 0.045,
            suffix == 'cut_a' and -0.065 or (suffix == 'cut_b' and 0.055 or -0.005), 0.170
        }
    end
end
Config.Keys = { '1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#' }
Config.KeyNames = { ['*'] = 'star', ['#'] = 'hash' }
for i, key in ipairs(Config.Keys) do
    local row, col = math.floor((i - 1) / 3), (i - 1) % 3
    Config.Sockets['bone_key_' .. (Config.KeyNames[key] or key)] = {
        0.09 + col * 0.055, -0.025 - row * 0.04, 0.170
    }
end
