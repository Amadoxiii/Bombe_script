-- Ce fichier doit figurer dans server_scripts, jamais dans shared_scripts/files.
ServerConfig = {
    Randomized = true, -- manuel révision 1 ; false conserve les recettes fixes ci-dessous
    -- true : placement réservé aux joueurs ayant cette permission ACE.
    -- false : tous les joueurs peuvent placer une bombe.
    StaffOnly = false,
    StaffAce = 'ibomb.spawn',
    MaxPerPlayer = 3,
    SpawnCooldownMs = 2000,
    ActionCooldownMs = 100,
    KeyCooldownMs = 180,
    DefusedLifetimeMs = 300000,
    -- Facultatif : item à détenir pour manipuler les modules, non consommé.
    -- Créer cet item dans VOTRE inventaire avant d'activer la contrainte.
    RequiredTool = false, -- exemple : 'bomb_tool'
    -- Règles de jeu fictives, aucun rapport avec un dispositif réel.
    -- Ne pas exposer ces valeurs dans les Statebags, NUI ou scripts partagés.
    Recipes = {
        explosive = { wire = 'green', switches = { ['1'] = true, ['2'] = false }, knobs = { ['1'] = 90, ['2'] = 270 }, pin = '481516' },
        bio       = { wire = 'blue', switches = { ['1'] = false, ['2'] = true }, knobs = { ['1'] = 180, ['2'] = 45 }, pin = '230810' },
        nuke      = { wire = 'white', switches = { ['1'] = true, ['2'] = true }, knobs = { ['1'] = 315, ['2'] = 135 }, pin = '091109' },
        emp       = { wire = 'yellow', switches = { ['1'] = false, ['2'] = false }, knobs = { ['1'] = 0, ['2'] = 180 }, pin = '120024' }
    }
}
