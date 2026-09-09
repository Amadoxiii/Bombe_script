-- Les dépendances sont facultatives. Aucun import @ox_lib/init.lua n'est requis.
Bridge = Bridge or {}
local server = IsDuplicityVersion()
local memory = {}

local function started(name) return GetResourceState(name) == 'started' end
function Bridge.Detect()
    return {
        framework = started('qb-core') and 'qb' or (started('es_extended') and 'esx' or 'standalone'),
        oxLib = started('ox_lib'), oxTarget = started('ox_target'),
        inventory = started('ox_inventory') and 'ox' or
            (started('qb-core') and 'qb' or (started('es_extended') and 'esx' or 'standalone'))
    }
end

-- Relire l'export permet de survivre au redémarrage du framework.
local function corePlayer(src, framework)
    if framework == 'qb' then return exports['qb-core']:GetCoreObject().Functions.GetPlayer(src) end
    if framework == 'esx' then return exports['es_extended']:getSharedObject().GetPlayerFromId(src) end
end

function Bridge.Notify(a, b, c)
    if server then
        TriggerClientEvent('ibomb:notify', a, tostring(b), c or 'inform')
        return
    end
    local message, kind = tostring(a), b or 'inform'
    local detected = Bridge.Detect()
    if detected.oxLib then
        local ok = pcall(function()
            -- 'inform' est accepté par les versions v3 ; omettre le type par défaut
            -- fonctionne aussi avec les versions récentes qui l'appellent 'info'.
            exports.ox_lib:notify({ title = 'Module interactif', description = message,
                type = (kind ~= 'inform' and kind ~= 'info') and kind or nil })
        end)
        if ok then return end
    end
    if detected.framework == 'qb' then
        local ok = pcall(function()
            exports['qb-core']:GetCoreObject().Functions.Notify(message,
                (kind == 'inform' or kind == 'info') and 'primary' or kind)
        end)
        if ok then return end
    elseif detected.framework == 'esx' then
        local ok = pcall(function() exports['es_extended']:getSharedObject().ShowNotification(message) end)
        if ok then return end
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, false)
end

if not server then
    RegisterNetEvent('ibomb:notify', function(message, kind)
        if source ~= 65535 then return end -- uniquement l'événement reçu du serveur
        Bridge.Notify(message, kind)
    end)
    return
end

local function valid(src, item, amount)
    return type(src) == 'number' and src > 0 and GetPlayerName(src) ~= nil
        and type(item) == 'string' and #item > 0 and #item <= 64
        and type(amount) == 'number' and amount == math.floor(amount) and amount > 0 and amount <= 1000000
end

local function countItem(src, item, backend)
    if backend == 'ox' then return exports.ox_inventory:Search(src, 'count', item) or 0 end
    if backend == 'standalone' then return memory[src] and memory[src][item] or 0 end
    local player = corePlayer(src, backend)
    if not player then return 0 end
    if backend == 'esx' then
        local entry = player.getInventoryItem(item)
        return entry and entry.count or 0
    end
    -- Additionner toutes les piles, et non uniquement la première case.
    local total = 0
    for _, entry in pairs(player.PlayerData.items or {}) do
        if entry.name == item then total = total + (tonumber(entry.amount) or 0) end
    end
    return total
end

function Bridge.HasItem(src, item, amount)
    amount = amount or 1
    if not valid(src, item, amount) then return false end
    local ok, count = pcall(countItem, src, item, Bridge.Detect().inventory)
    return ok and type(count) == 'number' and count >= amount
end

function Bridge.CanCarryItem(src, item, amount)
    amount = amount or 1
    if not valid(src, item, amount) then return false end
    local backend = Bridge.Detect().inventory
    local ok, result = pcall(function()
        if backend == 'ox' then return exports.ox_inventory:CanCarryItem(src, item, amount) end
        if backend == 'qb' then
            if not started('qb-inventory') then return false end
            return exports['qb-inventory']:CanAddItem(src, item, amount)
        end
        if backend == 'esx' then
            local player = corePlayer(src, backend)
            return player and player.canCarryItem and player.canCarryItem(item, amount) or false
        end
        return countItem(src, item, backend) + amount <= 1000000
    end)
    return ok and result == true
end

function Bridge.RemoveItem(src, item, amount)
    amount = amount or 1
    if not valid(src, item, amount) then return false end
    local backend = Bridge.Detect().inventory
    local ok, result = pcall(function()
        local before = countItem(src, item, backend)
        if type(before) ~= 'number' or before < amount then return false end
        if backend == 'ox' then return exports.ox_inventory:RemoveItem(src, item, amount) == true end
        if backend == 'qb' then
            local player = corePlayer(src, backend)
            return player and player.Functions.RemoveItem
                and player.Functions.RemoveItem(item, amount, nil, 'interactive_bomb') == true or false
        end
        if backend == 'esx' then
            corePlayer(src, backend).removeInventoryItem(item, amount)
            -- ESX retourne souvent nil : vérifier l'effet réel de l'opération.
            return countItem(src, item, backend) == before - amount
        end
        memory[src][item] = before - amount
        return true
    end)
    -- Un export absent/en erreur ne donne jamais un succès ni un autre inventaire.
    return ok and result == true
end

function Bridge.AddItem(src, item, amount)
    amount = amount or 1
    if not valid(src, item, amount) or not Bridge.CanCarryItem(src, item, amount) then return false end
    local backend = Bridge.Detect().inventory
    local ok, result = pcall(function()
        if backend == 'ox' then return exports.ox_inventory:AddItem(src, item, amount) == true end
        if backend == 'qb' then
            local player = corePlayer(src, backend)
            return player and player.Functions.AddItem
                and player.Functions.AddItem(item, amount, false, false, 'interactive_bomb') == true or false
        end
        if backend == 'esx' then
            local before = countItem(src, item, backend)
            corePlayer(src, backend).addInventoryItem(item, amount)
            return countItem(src, item, backend) == before + amount
        end
        memory[src] = memory[src] or {}
        memory[src][item] = (memory[src][item] or 0) + amount
        return true
    end)
    return ok and result == true
end

-- Export SERVEUR uniquement, destiné à une ressource de confiance.
-- Stock de démonstration perdu à la déconnexion/au redémarrage ; jamais un item fictivement possédé.
exports('SetStandaloneItem', function(src, item, count)
    if Bridge.Detect().inventory ~= 'standalone' then return false end
    if count == 0 then
        if not valid(src, item, 1) then return false end
    elseif not valid(src, item, count) then return false end
    memory[src] = memory[src] or {}
    memory[src][item] = count
    return true
end)
AddEventHandler('playerDropped', function() memory[source] = nil end)
