BombScreen = {}
local S, C = BombScreen, BombClient
local pool = {}
local MAX_SLOTS = math.min(Config.MaxScreens, 4) -- quatre modèles à textures indépendantes

function S.Payload(view, now)
    local state = view.state
    local remaining = now and math.max(0, math.ceil((state.endsAt - now) / 1000))
    if state.status ~= 'armed' then remaining = 0 end
    return { status = now and state.status or 'sync',
        timer = remaining and ('T-%02d:%02d'):format(remaining // 60, remaining % 60) or 'T--:--',
        code = state.code, stability = state.stability, kind = state.kind,
        clues = state.clues, knobs = state.knobs, switches = state.switches }
end

function S.Remove(view)
    local slot = view.screen
    view.screen = nil
    if slot and slot.owner == view.id then
        slot.owner, slot.sentAt = nil, nil
        if slot.part and DoesEntityExist(slot.part) then
            SetEntityVisible(slot.part, false, false)
            DetachEntity(slot.part, true, true)
        end
    end
end

RegisterNUICallback('ibomb_screen_ready', function(data, cb)
    local index = type(data) == 'table' and tonumber(data.slot)
    local slot = index and pool[index]
    local ready = slot ~= nil and data.token == slot.token
    if ready then slot.pageReady = true end
    cb({ ok = ready })
end)

local function acquire(view)
    for i = 1, MAX_SLOTS do
        local slot = pool[i]
        if not slot then
            local resource = GetCurrentResourceName()
            slot = { name = ('ibomb_dui_%s_%d'):format(resource, i),
                model = 'ib_display_' .. i, token = ('%s:%d'):format(GetGameTimer(), i),
                started = GetGameTimer() }
            pool[i] = slot
            slot.txd = CreateRuntimeTxd(slot.name)
            -- Un DUI n'est pas la page NUI principale : transmettre explicitement la ressource.
            local url = ('https://cfx-nui-%s/web/screen.html?resource=%s&slot=%d&token=%s'):format(
                resource, resource, i, slot.token)
            slot.dui = CreateDui(url, 1024, 1024)
        end
        if not slot.owner then
            slot.owner, slot.sentAt = view.id, nil
            view.screen = slot
            if not slot.part or not DoesEntityExist(slot.part) then
                local hash = C.LoadModel(slot.model)
                if C.stopping or view.cancelled or view.screen ~= slot or slot.owner ~= view.id
                    or not DoesEntityExist(view.entity) then
                    if hash then SetModelAsNoLongerNeeded(hash) end
                    S.Remove(view)
                    return
                end
                if not hash then S.Remove(view); return end
                local p = GetEntityCoords(view.entity)
                slot.part = CreateObjectNoOffset(hash, p.x, p.y, p.z, false, false, false)
                SetModelAsNoLongerNeeded(hash)
                if slot.part == 0 then slot.part = nil; S.Remove(view); return end
                SetEntityAsMissionEntity(slot.part, true, true)
                SetEntityCollision(slot.part, false, false)
                SetEntityInvincible(slot.part, true)
            end
            SetEntityVisible(slot.part, false, false)
            -- La géométrie écran + plaque est déjà définie dans le repère du boîtier.
            AttachEntityToEntity(slot.part, view.entity, -1, 0.0, 0.0, 0.0,
                0.0, 0.0, 0.0, false, false, false, true, 2, true)
            return
        end
    end
end

CreateThread(function()
    while not C.stopping do
        local nearby, pos = {}, GetEntityCoords(PlayerPedId())
        for _, view in pairs(C.views) do
            if view.built and not view.cancelled and DoesEntityExist(view.entity) then
                local distance = #(GetEntityCoords(view.entity) - pos)
                if distance < Config.ScreenDistance then
                    nearby[#nearby + 1] = { view = view, distance = distance,
                        priority = C.inspect and C.inspect.view == view and 0 or 1 }
                else S.Remove(view) end
            else S.Remove(view) end
        end
        table.sort(nearby, function(a,b)
            if a.priority ~= b.priority then return a.priority < b.priority end
            return a.distance < b.distance
        end)
        for i, entry in ipairs(nearby) do if i > MAX_SLOTS then S.Remove(entry.view) end end
        for i = 1, math.min(#nearby, MAX_SLOTS) do
            if not C.stopping and not nearby[i].view.screen then acquire(nearby[i].view) end
        end
        Wait(500)
    end
end)

-- Le moteur dessine la surface du prop : aucune primitive dessinée à chaque frame.
CreateThread(function()
    while not C.stopping do
        for _, view in pairs(C.views) do
            local slot = view.screen
            if slot and view.built and not view.cancelled and DoesEntityExist(view.entity)
                and slot.dui and slot.dui ~= 0 and IsDuiAvailable(slot.dui) then
                if not slot.ready then
                    CreateRuntimeTextureFromDuiHandle(slot.txd, 'screen', GetDuiHandle(slot.dui))
                    -- Une texture source unique par slot évite le même chrono sur toutes les bombes.
                    AddReplaceTexture(slot.model, slot.model, slot.name, 'screen')
                    slot.ready = true
                end
                -- Ne pas bloquer l'envoi sur l'accusé HTTP : il est diagnostique seulement.
                SendDuiMessage(slot.dui, json.encode(S.Payload(view, C.Now())))
                slot.sentAt = GetGameTimer()
                if slot.part and DoesEntityExist(slot.part) then SetEntityVisible(slot.part, true, false) end
                if not slot.pageReady and GetGameTimer() - slot.started > 5000 then
                    C.WarnOnce('dui:' .. slot.name, 'Accusé de page écran absent ; /ibombdiag pour le diagnostic.')
                end
            end
        end
        Wait(100)
    end
end)

function S.Shutdown()
    for _, view in pairs(C.views) do S.Remove(view) end
    for _, slot in pairs(pool) do
        if slot.part and DoesEntityExist(slot.part) then
            DetachEntity(slot.part, true, true); DeleteEntity(slot.part)
        end
        if slot.ready then RemoveReplaceTexture(slot.model, slot.model) end
        if slot.dui and slot.dui ~= 0 then DestroyDui(slot.dui) end
    end
    pool = {}
end

RegisterCommand('ibombdiag', function()
    local nearest, distance
    for _, view in pairs(C.views) do
        if DoesEntityExist(view.entity) then
            local d = #(GetEntityCoords(view.entity) - GetEntityCoords(PlayerPedId()))
            if not distance or d < distance then nearest, distance = view, d end
        end
    end
    local slot = nearest and nearest.screen
    print(('[ibomb] renderer=material clock=%s nearest=%.2f model=%s part=%s dui=%s page=%s texture=%s timer=%s'):format(
        tostring(C.Now()), distance or -1, tostring(slot and slot.model), tostring(slot and slot.part),
        tostring(slot and slot.dui), tostring(slot and slot.pageReady), tostring(slot and slot.ready),
        nearest and S.Payload(nearest,C.Now()).timer or 'none'))
end, false)
