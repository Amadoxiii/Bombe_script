-- OneSync requis. Ce registre privé est la seule autorité du puzzle.
-- Ne JAMAIS relire Entity(entity).state pour valider une action client.
local bombs, sessions, spawnLocks, actionLocks, rates = {}, {}, {}, {}, {}
local pendingEntities, stopping = {}, false
local reservations, serial = 0, 0
local epoch, lastTick, elapsed = os.time() * 1000, GetGameTimer(), 0

local function nowMs()
    local tick = GetGameTimer()
    elapsed = elapsed + ((tick - lastTick) % 4294967296)
    lastTick = tick
    return epoch + elapsed
end

local function finite(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end
local function integer(value) return finite(value) and value == math.floor(value) end
local function clone(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = clone(item) end
    return result
end
local function session(src)
    if not sessions[src] then sessions[src] = {} end
    return sessions[src]
end
local function rate(src, key, interval)
    rates[src] = rates[src] or {}
    local time = nowMs()
    if rates[src][key] and time - rates[src][key] < interval then return false end
    rates[src][key] = time
    return true
end
local function notify(src, message, kind) Bridge.Notify(src, message, kind or 'error') end
local function canSpawn(src)
    if not ServerConfig.StaffOnly then return true end
    return type(ServerConfig.StaffAce) == 'string' and ServerConfig.StaffAce ~= ''
        and IsPlayerAceAllowed(src, ServerConfig.StaffAce)
end
local function distanceSquared(a, b)
    return (a.x-b.x)^2 + (a.y-b.y)^2 + (a.z-b.z)^2
end
local function alivePed(src)
    if src <= 0 or not GetPlayerName(src) then return nil end
    local ped = GetPlayerPed(src)
    if ped == 0 or not DoesEntityExist(ped) or GetEntityHealth(ped) <= 100 then return nil end
    -- Les états de coma propres aux frameworks doivent être ajoutés ici si nécessaires.
    return ped
end
local function nearby(src, position, bucket, radius)
    local ped = alivePed(src)
    return ped and GetPlayerRoutingBucket(src) == bucket
        and distanceSquared(GetEntityCoords(ped), position) <= radius * radius
end
local function publish(record, state)
    -- Publication atomique d'un NOUVEAU snapshot ; aucune mutation de sous-table d'un bag.
    record.state = clone(state)
    if DoesEntityExist(record.entity) then
        Entity(record.entity).state:set(Config.StateKey, clone(state), true)
    end
end

local function exposure(record, damage)
    if damage <= 0 then return end
    local radius = Config.Effects[record.state.kind].radius
    for _, player in ipairs(GetPlayers()) do
        local src = tonumber(player)
        if nearby(src, record.position, record.bucket, radius) then
            -- Un envoi par joueur, depuis le serveur ; le client applique à son propre ped.
            TriggerClientEvent('ibomb:exposure', src, damage, record.state.kind)
        end
    end
end
local function detonate(record)
    if record.state.status ~= 'armed' then return end
    local state, time = clone(record.state), nowMs()
    state.status, state.rev = 'detonated', state.rev + 1
    state.detonatedAt = time
    state.fxUntil = time + Config.Effects[state.kind].duration * 1000
    state.stability = 0
    record.nextExposure = time + 1000
    publish(record, state)
    if state.kind == 'explosive' then
        -- Dégât instantané exactement une fois pour cette détonation.
        exposure(record, Config.Effects.explosive.damage)
    end
end
local function removeBomb(netId, record)
    if DoesEntityExist(record.entity) then DeleteEntity(record.entity) end
    bombs[netId] = nil
end

RegisterNetEvent('ibomb:clock', function(token)
    local src = source
    if src <= 0 or not GetPlayerName(src) or not rate(src, 'clock', 1000) then return end
    if not ((type(token) == 'string' and #token <= 64) or finite(token)) then return end
    TriggerClientEvent('ibomb:clock', src, token, nowMs(), GetPlayerRoutingBucket(src))
end)

RegisterNetEvent('ibomb:spawn', function(kind, position, heading)
    local src = source
    if stopping or src <= 0 or spawnLocks[src] or not rate(src, 'spawn', ServerConfig.SpawnCooldownMs) then return end
    if not canSpawn(src) then
        return notify(src, 'Le placement des bombes est réservé au staff.')
    end
    if type(kind) ~= 'string' or not Config.Types[kind] or not ServerConfig.Recipes[kind] then return end
    if type(position) ~= 'table' or not finite(position.x) or not finite(position.y) or not finite(position.z)
        or not finite(heading) or math.abs(position.x) > 20000 or math.abs(position.y) > 20000
        or position.z < -1000 or position.z > 3000 then return end
    local ped = alivePed(src)
    if not ped or distanceSquared(GetEntityCoords(ped), position) > Config.SpawnDistance^2 then
        return notify(src, 'Placement trop éloigné ou personnage indisponible.')
    end
    local ownerSession, count, owned = session(src), 0, 0
    for _, record in pairs(bombs) do
        count = count + 1
        if record.ownerSession == ownerSession then owned = owned + 1 end
    end
    if count + reservations >= Config.MaxBombs or owned >= ServerConfig.MaxPerPlayer then
        return notify(src, 'Limite de boîtiers atteinte.')
    end

    -- Réserver AVANT tout Wait : deux spawns ne peuvent pas dépasser la limite.
    spawnLocks[src], reservations = ownerSession, reservations + 1
    local entity, registered, createdNetId = 0, false, nil
    local ok, err = xpcall(function()
        local bucket = GetPlayerRoutingBucket(src)
        entity = CreateObjectNoOffset(joaat(Config.Model), position.x, position.y, position.z, true, true, false)
        if entity ~= 0 then pendingEntities[entity] = true end
        local deadline = nowMs() + 3000
        while not stopping and entity ~= 0 and not DoesEntityExist(entity) and nowMs() < deadline do Wait(0) end
        if entity == 0 or not DoesEntityExist(entity) then return notify(src, 'Création du modèle impossible.') end
        -- Revérification après attente : déconnexion, bucket, déplacement ou ACE modifié.
        if stopping or sessions[src] ~= ownerSession
            or not canSpawn(src)
            or not nearby(src, position, bucket, Config.SpawnDistance) then return end
        SetEntityRoutingBucket(entity, bucket)
        SetEntityOrphanMode(entity, 2) -- KeepEntity : conserve le root sans propriétaire à proximité.
        SetEntityHeading(entity, heading % 360)
        FreezeEntityPosition(entity, true)
        local netId = NetworkGetNetworkIdFromEntity(entity)
        if netId == 0 or bombs[netId] then return notify(src, 'Identifiant réseau indisponible.') end
        serial = serial + 1
        local state = {
            id = ('%x-%d'):format(nowMs(), serial), kind = kind, bucket = bucket,
            heading = heading % 360, rev = 1, status = 'armed',
            serverNow = nowMs(), endsAt = nowMs() + Config.DurationSeconds * 1000,
            wires = {}, switches = {}, knobs = {}, stability = 100,
            code = '', keySeq = 0, keyLast = '', keyAt = 0, detonatedAt = 0, fxUntil = 0
        }
        for _, color in ipairs(Config.WireColors) do state.wires[color] = false end
        for _, id in ipairs(Config.SwitchIds) do state.switches[id] = false end
        for _, id in ipairs(Config.KnobIds) do state.knobs[id] = 0 end
        local recipe = clone(ServerConfig.Recipes[kind])
        if ServerConfig.Randomized then
            local clues, generated, initial = BombPuzzle.Generate(kind)
            state.clues, recipe = clues, generated
            state.switches, state.knobs = initial.switches, initial.knobs
        end
        local record = { entity = entity, ownerSession = ownerSession, position = clone(position),
            heading = heading % 360, bucket = bucket, errors = 0, lastKeyAt = 0, state = state, recipe = recipe }
        createdNetId = netId
        bombs[netId] = record
        publish(record, state)
        registered = true
        notify(src, 'Boîtier placé et armé.', 'success')
    end, debug.traceback)
    pendingEntities[entity] = nil
    if not registered and createdNetId then bombs[createdNetId] = nil end
    reservations = reservations - 1
    if spawnLocks[src] == ownerSession then spawnLocks[src] = nil end
    if not registered and entity ~= 0 and DoesEntityExist(entity) then DeleteEntity(entity) end
    if not ok then
        print(('[ibomb] spawn : %s'):format(err))
        notify(src, 'Erreur serveur pendant le placement ; consulter la console FXServer.')
    end
end)

local function solved(state, recipe)
    if not state.wires[recipe.wire] or state.code ~= recipe.pin then return false end
    for id, wanted in pairs(recipe.switches) do if state.switches[id] ~= wanted then return false end end
    for id, wanted in pairs(recipe.knobs) do if state.knobs[id] ~= wanted then return false end end
    return true
end

RegisterNetEvent('ibomb:action', function(netId, bombId, expectedRev, action, value)
    local src = source
    if stopping or src <= 0 or actionLocks[src] or not rate(src, 'action', ServerConfig.ActionCooldownMs) then return end
    if not integer(netId) or netId <= 0 or type(bombId) ~= 'string' or #bombId > 96
        or not integer(expectedRev) or expectedRev < 1 or type(action) ~= 'string' then return end
    local record = bombs[netId]
    if not record or not DoesEntityExist(record.entity)
        or record.state.id ~= bombId or record.state.status ~= 'armed'
        or GetEntityModel(record.entity) ~= joaat(Config.Model) then return end
    if record.locked then return notify(src, 'Un autre joueur manipule ce boîtier ; réessayez.') end
    if record.state.rev ~= expectedRev then return notify(src, 'État modifié par un autre joueur ; réessayez.') end
    if not nearby(src, record.position, record.bucket, Config.InteractDistance) then
        return notify(src, 'Approchez-vous du boîtier pour le manipuler.')
    end
    if record.state.endsAt <= nowMs() then return detonate(record) end
    local ownerSession = session(src)
    actionLocks[src], record.locked = ownerSession, true
    local ok, err = xpcall(function()
        if ServerConfig.RequiredTool and not Bridge.HasItem(src, ServerConfig.RequiredTool, 1) then
            return notify(src, 'Outil requis absent ou inventaire indisponible.')
        end
        -- Un export d'inventaire peut yield : tout revalider avant la mutation.
        if sessions[src] ~= ownerSession or bombs[netId] ~= record or not DoesEntityExist(record.entity)
            or record.state.status ~= 'armed' or record.state.rev ~= expectedRev
            or not nearby(src, record.position, record.bucket, Config.InteractDistance) then return end
        if record.state.endsAt <= nowMs() then return detonate(record) end
        local state, recipe, time = clone(record.state), record.recipe, nowMs()

        if action == 'wire' then
            if type(value) ~= 'string' or state.wires[value] == nil or state.wires[value] then return end
            state.wires[value] = true
            if value ~= recipe.wire then
                -- Publier le fil coupé avant de publier la détonation, sans délai client.
                state.rev = state.rev + 1
                publish(record, state)
                return detonate(record)
            end
        elseif action == 'switch' then
            if type(value) ~= 'string' or state.switches[value] == nil then return end
            state.switches[value] = not state.switches[value]
        elseif action == 'knob' then
            if type(value) ~= 'table' or type(value.id) ~= 'string' or state.knobs[value.id] == nil
                or (value.delta ~= 15 and value.delta ~= -15) then return end
            state.knobs[value.id] = (state.knobs[value.id] + value.delta) % 360
        elseif action == 'keypad' then
            if type(value) ~= 'string' or not (value:match('^%d$') or value == '*' or value == '#') then return end
            if time - record.lastKeyAt < ServerConfig.KeyCooldownMs then return end
            record.lastKeyAt = time
            state.keySeq, state.keyLast, state.keyAt = state.keySeq + 1, value, time
            if value == '*' then
                state.code = ''
            elseif value == '#' then
                if solved(state, recipe) then
                    state.status = 'defused'
                    record.removeAt = time + ServerConfig.DefusedLifetimeMs
                    notify(src, 'Puzzle résolu ; boîtier désarmé.', 'success')
                else
                    record.errors = record.errors + 1
                    state.stability = math.max(0, 100 - record.errors * 25)
                    state.code = ''
                    notify(src, 'Configuration incorrecte : stabilité réduite de 25 %.')
                end
            elseif #state.code < 6 then
                state.code = state.code .. value
            end
        else
            return -- Aucune action « gauge », « detonate », « setState » ou montant arbitraire.
        end
        state.rev = state.rev + 1
        publish(record, state)
        if state.status == 'armed' and state.stability <= 0 then detonate(record) end
    end, debug.traceback)
    record.locked = nil
    if actionLocks[src] == ownerSession then actionLocks[src] = nil end
    if not ok then print(('[ibomb] action : %s'):format(err)) end
end)

CreateThread(function()
    while not stopping do
        Wait(200)
        local time = nowMs()
        for netId, record in pairs(bombs) do
            if not DoesEntityExist(record.entity) then
                bombs[netId] = nil
            else
                local state = record.state
                if state.status == 'armed' and time >= state.endsAt then
                    detonate(record)
                elseif state.status == 'defused' and time >= record.removeAt then
                    removeBomb(netId, record)
                elseif state.status == 'detonated' then
                    if time >= state.fxUntil + 5000 then
                        removeBomb(netId, record)
                    elseif time < state.fxUntil and time >= record.nextExposure then
                        record.nextExposure = time + 1000
                        if state.kind == 'bio' or state.kind == 'nuke' then
                            exposure(record, Config.Effects[state.kind].damage)
                        end
                    end
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    sessions[src], rates[src], spawnLocks[src], actionLocks[src] = nil, nil, nil, nil
    -- Les boîtiers déjà posés survivent à leur poseur jusqu'à leur propre expiration.
end)
AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    stopping = true
    local roots = {}
    for netId, record in pairs(bombs) do roots[#roots + 1] = { netId, record } end
    for _, entry in ipairs(roots) do removeBomb(entry[1], entry[2]) end
    for entity in pairs(pendingEntities) do
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
end)
