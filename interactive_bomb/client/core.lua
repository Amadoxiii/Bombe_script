BombClient = { views = {}, bucket = nil, placing = false, stopping = false }
local C = BombClient
local warned, anchor, serial, pendingClock = {}, nil, 0, {}

function C.WarnOnce(key, message)
    if warned[key] then return end
    warned[key] = true
    print(('[ibomb] %s'):format(message))
end

function C.Now()
    return anchor and (anchor.epoch + ((GetGameTimer() - anchor.localTime) % 4294967296)) or nil
end

RegisterNetEvent('ibomb:clock', function(token, epoch, bucket)
    if source ~= 65535 or type(token) ~= 'number' then return end
    local sent = pendingClock[token]
    if not sent or type(epoch) ~= 'number' or epoch ~= epoch or epoch <= 0 or epoch > 1e15
        or type(bucket) ~= 'number' or bucket < 0 or bucket > 2147483647 or bucket % 1 ~= 0 then return end
    pendingClock[token] = nil
    local received = GetGameTimer()
    anchor = { epoch = epoch + ((received - sent) % 4294967296) / 2, localTime = received }
    C.bucket = bucket
end)

CreateThread(function()
    while not C.stopping do
        serial = serial + 1
        pendingClock = { [serial] = GetGameTimer() }
        TriggerServerEvent('ibomb:clock', serial)
        Wait(anchor and 15000 or 2000)
    end
end)

function C.LoadModel(name)
    local hash = joaat(name)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then
        C.WarnOnce(name, 'Modèle absent/invalide : ' .. name .. ' ; produire les assets stream/.')
        return nil
    end
    RequestModel(hash)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(hash) then
        SetModelAsNoLongerNeeded(hash)
        return nil
    end
    return hash
end

function C.Socket(view, name)
    view.bones = view.bones or {}
    if view.bones[name] == nil then
        view.bones[name] = GetEntityBoneIndexByName(view.entity, name)
        if view.bones[name] == -1 and Config.DebugSockets then
            C.WarnOnce(name, 'Socket absent : ' .. name .. ' ; repli coordonnées gabarit.')
        end
    end
    return view.bones[name]
end

function C.SocketWorld(view, name)
    local index = C.Socket(view, name)
    if index ~= -1 then return GetWorldPositionOfEntityBone(view.entity, index) end
    local p = Config.Sockets[name] or { 0, 0, 0 }
    return GetOffsetFromEntityInWorldCoords(view.entity, p[1], p[2], p[3])
end

function C.Help(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

function C.Request(view, action, value)
    if C.stopping or not view or view.state.status ~= 'armed' or C.placing then return false end
    if not DoesEntityExist(view.entity) or view.cancelled or
        #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(view.entity)) > Config.InteractDistance then return false end
    TriggerServerEvent('ibomb:action', NetworkGetNetworkIdFromEntity(view.entity),
        view.id, view.state.rev, action, value)
    return true
end

-- Raycast asynchrone : un résultat pending (1) ne contient pas de hit valide.
function C.CameraRay(distance, ignore, flags)
    local origin = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local direction = vector3(-math.sin(z) * math.cos(x), math.cos(z) * math.cos(x), math.sin(x))
    local target = origin + direction * distance
    return StartShapeTestLosProbe(origin.x, origin.y, origin.z,
        target.x, target.y, target.z, flags or 511, ignore or PlayerPedId(), 7)
end

local function forget(entity)
    local view = C.views[entity]
    if not view then return end
    view.wantsParts = false
    if C.inspect and C.inspect.view == view and BombInteraction then BombInteraction.Exit() end
    view.cancelled = true
    if BombInteraction then BombInteraction.Remove(view) end
    if BombScreen then BombScreen.Remove(view) end
    if BombModules then BombModules.Destroy(view) end
    if BombEffects then BombEffects.Remove(view.id) end
    C.views[entity] = nil
end

local function bounded(value, low, high, integer)
    return type(value) == 'number' and value == value and value >= low and value <= high
        and (not integer or value % 1 == 0)
end

function C.ValidSnapshot(s)
    if type(s) ~= 'table' or type(s.id) ~= 'string' or #s.id < 1 or #s.id > 96
        or type(s.kind) ~= 'string' or not Config.Types[s.kind]
        or not bounded(s.rev, 1, 2147483647, true)
        or (s.status ~= 'armed' and s.status ~= 'defused' and s.status ~= 'detonated')
        or not bounded(s.endsAt, 1, 1e15) or (s.serverNow ~= nil and not bounded(s.serverNow, 1, 1e15))
        or not bounded(s.stability, 0, 100)
        or not bounded(s.keySeq, 0, 2147483647, true)
        or not bounded(s.keyAt, 0, 1e15) or not bounded(s.detonatedAt, 0, 1e15)
        or not bounded(s.fxUntil, 0, 1e15)
        or type(s.code) ~= 'string' or #s.code > 6 or not s.code:match('^%d*$')
        or type(s.keyLast) ~= 'string' or not (s.keyLast == '' or s.keyLast:match('^%d$')
            or s.keyLast == '*' or s.keyLast == '#')
        or type(s.wires) ~= 'table' or type(s.switches) ~= 'table' or type(s.knobs) ~= 'table' then return false end
    if s.bucket ~= nil and not bounded(s.bucket, 0, 2147483647, true) then return false end
    if s.heading ~= nil and not bounded(s.heading, 0, 359.999999) then return false end
    if s.clues ~= nil then
        local q = s.clues
        if type(q) ~= 'table' or q.version ~= 1 or type(q.serial) ~= 'string'
            or not q.serial:match('^[A-Z][A-Z]%-%d%d%d%d$')
            or not bounded(q.cells, 1, 4, true) or (q.bus ~= 'A' and q.bus ~= 'B' and q.bus ~= 'C') then return false end
    end
    for _, color in ipairs(Config.WireColors) do if type(s.wires[color]) ~= 'boolean' then return false end end
    for _, id in ipairs(Config.SwitchIds) do if type(s.switches[id]) ~= 'boolean' then return false end end
    for _, id in ipairs(Config.KnobIds) do if not bounded(s.knobs[id], 0, 359.999) then return false end end
    return s.status ~= 'detonated' or (s.detonatedAt > 0 and s.fxUntil >= s.detonatedAt)
end

local function receive(entity, snapshot)
    if C.stopping or entity == 0 or not DoesEntityExist(entity) or type(snapshot) ~= 'table' then return end
    if GetEntityModel(entity) ~= joaat(Config.Model) or not C.ValidSnapshot(snapshot) then return end
    -- Les écritures Statebag propriétaire doivent être bloquées via strict mode.
    -- Ce client n'utilise jamais un bag comme preuve d'autorisation serveur.
    local view = C.views[entity]
    if view and view.id ~= snapshot.id then forget(entity); view = nil end
    if not view then
        view = { entity = entity, id = snapshot.id, state = snapshot, parts = {}, bones = {} }
        C.views[entity] = view
        -- Initialisation locale indispensable si les RPC de création serveur ont
        -- précédé l'arrivée d'un propriétaire réseau ; répétée à chaque stream-in.
        FreezeEntityPosition(entity, true)
        if snapshot.heading then SetEntityHeading(entity, snapshot.heading) end
    elseif snapshot.rev > view.state.rev then
        local previous = view.state
        view.state = snapshot
        if BombModules then BombModules.Apply(view, previous) end
    end
end

local handler = AddStateBagChangeHandler(Config.StateKey, nil, function(bagName, _, value)
    local entity = GetEntityFromStateBagName(bagName)
    if entity ~= 0 then receive(entity, value) end
    -- Si l'entité n'existe pas encore, le scan ci-dessous récupère le snapshot.
end)

CreateThread(function()
    while not C.stopping do
        local playerPosition = GetEntityCoords(PlayerPedId())
        for _, entity in ipairs(GetGamePool('CObject')) do
            if GetEntityModel(entity) == joaat(Config.Model)
                and #(GetEntityCoords(entity) - playerPosition) <= Config.StreamDistance
                and NetworkGetEntityIsNetworked(entity) then
                receive(entity, Entity(entity).state[Config.StateKey])
            end
        end
        local nearby = {}
        for entity, view in pairs(C.views) do
            if not DoesEntityExist(entity) or GetEntityModel(entity) ~= joaat(Config.Model)
                or #(GetEntityCoords(entity) - playerPosition) > Config.StreamDistance then
                forget(entity)
            else
                -- Relecture périodique : couvre entrée en scope/restart du client.
                local current = Entity(entity).state[Config.StateKey]
                if not current or current.id ~= view.id then
                    forget(entity)
                else
                    receive(entity, current)
                    nearby[#nearby + 1] = { view = view, distance = #(GetEntityCoords(entity) - playerPosition) }
                end
            end
        end
        table.sort(nearby, function(a, b) return a.distance < b.distance end)
        for i, entry in ipairs(nearby) do
            local view = entry.view
            if i <= Config.MaxRendered and entry.distance <= Config.PartsDistance then
                view.wantsParts = true
                if not view.built and not view.building then
                    view.building = true
                    CreateThread(function()
                        BombModules.Build(view)
                        view.building = false
                    end)
                end
                if BombInteraction then BombInteraction.Ensure(view) end
            else
                view.wantsParts = false
                if view.built or view.building then BombModules.Destroy(view) end
                if BombInteraction then BombInteraction.Remove(view) end
            end
        end
        Wait(1000)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    C.stopping = true
    C.placing = false
    if BombInteraction then BombInteraction.Exit() end
    RemoveStateBagChangeHandler(handler)
    if BombScreen then BombScreen.Shutdown() end
    local roots = {}
    for entity in pairs(C.views) do roots[#roots + 1] = entity end
    for _, entity in ipairs(roots) do forget(entity) end
end)
