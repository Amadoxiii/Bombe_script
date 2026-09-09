# B-07 · Interactive Bomb

Un puzzle de désamorçage directement dans le monde de GTA V. Examinez le boîtier, identifiez ses indices et manipulez ses modules en 3D avec la souris.

Pensé pour les scènes RP, les interventions et les événements coopératifs, B-07 associe une bombe visible par tous les joueurs proches à un manuel de résolution intégré.

## Fonctionnalités

- **Quatre variantes** : explosive, biologique, nucléaire et IEM, avec effets et sons distincts.
- **Modules animés** : fils à couper, interrupteurs, potentiomètres, touches enfoncées et aiguille de stabilité.
- **Écran DUI sur le prop** : chronomètre, saisie et angles des molettes.
- **Plaque d'identification** : numéro de série, cellules et bus générés à chaque placement.
- **Puzzles aléatoires** : indices et positions initiales variables, règles expliquées dans le manuel.
- **Vue d'inspection** : caméra rapprochée, curseur, valeurs au survol et manuel consultable en jeu.
- **Placement libre** : aperçu transparent, rotation et réglage de hauteur.
- **Synchronisation OneSync** : état partagé via Statebags, contrôles des actions côté serveur.
- **Accès configurable** : placement public ou réservé au staff par permission ACE.
- **Standalone** : aucun framework obligatoire ; intégrations facultatives ESX, QBCore et OX.

## Installation

Prérequis : FXServer avec **OneSync**, GTA V et les deux ressources fournies. Aucune base de données n'est requise.

Copiez ces deux dossiers dans les ressources de votre serveur :

```text
resources/
├── interactive_bomb/
└── interactive_bomb_assets/
```

Ajoutez dans votre `server.cfg`, après vos éventuels frameworks et ressources OX :

```cfg
set onesync on
ensure interactive_bomb_assets
ensure interactive_bomb
```

Conservez les noms des deux ressources. Lors de l'installation ou d'une mise à jour des modèles, déconnectez les joueurs puis redémarrez complètement le serveur. Pour les changements Lua uniquement, utilisez `restart interactive_bomb` et laissez la ressource d'assets démarrée.

## Placement réservé au staff

Dans `server/config.lua` :

```lua
StaffOnly = false,          -- false : placement ouvert à tous
StaffAce = 'ibomb.spawn',   -- permission exigée lorsque StaffOnly = true
```

Pour réserver le placement aux administrateurs, passez `StaffOnly` à `true` puis ajoutez :

```cfg
add_ace group.admin ibomb.spawn allow
```

Les membres du staff doivent être associés à ce groupe ACE dans votre serveur. Un grade ESX ou QBCore n'accorde pas automatiquement cette permission. Vous pouvez utiliser un autre groupe avec la même ACE.

Cette restriction concerne **le placement**. Les joueurs proches peuvent toujours examiner et désamorcer une bombe. Un outil d'inventaire peut être exigé séparément avec `RequiredTool`.

## Utilisation

```text
/spawnbomb explosive
/spawnbomb bio
/spawnbomb nuke
/spawnbomb emp
```

| Action | Commande |
|---|---|
| Tourner l'aperçu | Molette de souris |
| Régler la hauteur | Page Haut / Page Bas |
| Poser | Entrée |
| Annuler le placement | Retour / Échap |
| Examiner une bombe proche | E |
| Manipuler un module | Clic gauche |
| Régler une molette | Clic gauche +15° / clic droit −15°, ou molette |
| Effacer le code / valider | * / # |
| Consulter les règles | Bouton Manuel B-07 |
| Quitter l'inspection | Fermer, Retour ou Échap |

Lisez la plaque, utilisez le manuel pour déterminer le bon fil, les états, les angles et le code, puis validez avec **#**. Le chronomètre continue pendant la lecture.

## Personnalisation

| Fichier | Réglages |
|---|---|
| `shared/config.lua` | Durée, distances, limites d'affichage, effets, volume et sons |
| `server/config.lua` | Accès staff, limites de placement, outil requis, mode aléatoire et recettes fixes |
| `shared/bridge.lua` | Notifications et intégrations d'inventaire |

Ces trois fichiers figurent dans `escrow_ignore` pour rester modifiables lors d'une distribution via FiveM Asset Escrow. Cette déclaration ne chiffre pas la ressource à elle seule.

Les configurations livrées activent le mode aléatoire, autorisent le placement à tous et donnent trois minutes avant détonation. Les permissions, recettes et validations sensibles restent côté serveur.

## Compatibilité et fonctionnement

Le bridge détecte ESX, QBCore, ox_lib, ox_target et ox_inventory lorsqu'ils sont disponibles. La sélection à la souris et la commande de placement restent utilisables sans OX.

Le boîtier est une entité réseau ; ses petites pièces sont des props locaux animés à partir de l'état synchronisé. Les surfaces DUI utilisent des textures distinctes pour afficher plusieurs chronomètres. Le pool est limité à quatre écrans proches, avec priorité à la bombe inspectée.

Les explosions sont des compositions visuelles et sonores GTA ; les dégâts de gameplay sont décidés séparément par le serveur. L'IEM applique un blackout global aux clients présents dans sa zone. Les modules ont une animation cinématique, sans simulation physique individuelle des câbles. Les bombes ne sont pas persistées en base de données.

## Diagnostic

Utilisez `/ibombdiag` près du boîtier puis consultez F8 pour vérifier l'horloge, le modèle de surface et le DUI. En cas de problème, conservez également l'erreur F8, le type de bombe et les étapes de reproduction.

Les tests automatisés de logique et de nettoyage ont été exécutés avec des API simulées. Le rendu, l'audio, les performances et les intégrations doivent être validés sur votre build et votre configuration serveur ; aucun chiffre de performance n'est garanti.

## Contenu

Le pack de distribution contient uniquement les deux ressources nécessaires au jeu et ce README. Il inclut les modèles 3D, les pages d'interface, le manuel et quatre sons procéduraux originaux.
