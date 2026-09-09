fx_version 'cerulean'
game 'gta5'

author 'Interactive Bomb'
description 'B-07 — Bombe interactive 3D, puzzles aléatoires et manuel intégré'
version '1.3.1'

-- OneSync est nécessaire, aucun framework ne l'est.
dependencies { '/onesync', 'interactive_bomb_assets' }

shared_scripts { 'shared/config.lua', 'shared/bridge.lua' }
client_scripts {
    'client/core.lua', 'client/modules.lua', 'client/screen.lua',
    'client/spawn.lua', 'client/interaction.lua', 'client/effects.lua'
}
server_scripts { 'server/config.lua', 'server/puzzle.lua', 'server/main.lua' }

-- Pas de @ox_lib/init.lua : son inclusion fixe rendrait la ressource dépendante
-- d'un fichier absent en standalone. Bridge utilise les exports disponibles.
ui_page 'web/interaction.html'
files { 'web/screen.html', 'web/interaction.html', 'web/manual.html', 'web/effects-audio.js', 'web/audio/*.wav' }
escrow_ignore {
    'shared/config.lua',
    'server/config.lua',
    'shared/bridge.lua'
}
-- Le YTYP appartient à interactive_bomb_assets et reste chargé au restart Lua.
