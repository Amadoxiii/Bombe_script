BombInteraction = {}
local I, C = BombInteraction, BombClient
local descriptors, options, optionNames = {}, {}, {}
local sequence, reopenAt, nextDetails = 0, 0, 0

local function eligible(view)
    if C.stopping or C.placing or not view or view.cancelled or not view.built
        or not DoesEntityExist(view.entity) or view.state.status ~= 'armed' then return false end
    local ped = PlayerPedId()
    return not IsEntityDead(ped) and not IsPedInAnyVehicle(ped, false)
        and #(GetEntityCoords(view.entity) - GetEntityCoords(ped)) <= Config.InteractDistance
end

local function available(view, d)
    return eligible(view) and not (d.action == 'wire' and view.state.wires[d.value])
end

local function add(bone, label, action, value, size)
    descriptors[#descriptors + 1] = { bone = bone, label = label, action = action,
        value = value, size = size }
end
for _, color in ipairs(Config.WireColors) do
    add('bone_wire_' .. color .. '_intact', 'Couper le fil ' .. color, 'wire', color, { .014, .06, .025 })
end
for _, id in ipairs(Config.SwitchIds) do
    add('bone_switch_' .. id, 'Interrupteur ' .. id, 'switch', id, { .020, .032, .055 })
end
for _, id in ipairs(Config.KnobIds) do
    add('bone_knob_' .. id, 'Molette ' .. id .. ' : clic +15°, clic droit / molette -15°',
        'knob', id, { .026, .026, .025 })
end
for _, key in ipairs(Config.Keys) do
    add('bone_key_' .. (Config.KeyNames[key] or key), 'Touche ' .. key, 'keypad', key, { .023, .016, .007 })
end
add('bone_gauge_needle', 'Lire la stabilité', 'gauge', nil, { .04, .04, .006 })
for i = 1, 2 do
    add('bone_vial_slot_' .. i, 'Lire la charge', 'vial', nil, { .025, .025, .09 })
end
Config.Sockets.bone_identity_plate = { -.005, -.140, .1615 }
add('bone_identity_plate', 'Lire la plaque', 'plate', nil, { .050, .030, .003 })

function I.Label(view, d)
    if d.action == 'knob' then
        return ('Molette %s : %03d° | gauche +15° / droit -15°'):format(d.value, view.state.knobs[d.value])
    elseif d.action == 'switch' then
        return ('Interrupteur %s : %s'):format(d.value, view.state.switches[d.value] and 'ON' or 'OFF')
    elseif d.action == 'plate' then
        local q = view.state.clues
        return q and ('Série %s | %d cellules | bus %s'):format(q.serial,q.cells,q.bus) or 'Mode fixe : recettes serveur'
    end
    return d.label
end

function I.Exit()
    local inspection = C.inspect
    C.inspect = nil -- aucune lecture de C.inspect après la fermeture
    if not inspection then return end
    reopenAt = GetGameTimer() + 300
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'inspect', visible = false, session = inspection.session })
    -- Arrêt immédiat : ne pas détruire une caméra encore utilisée par une interpolation.
    RenderScriptCams(false, false, 0, true, true)
    if DoesCamExist(inspection.camera) then DestroyCam(inspection.camera, false) end
end

function I.Enter(view)
    if C.inspect or GetGameTimer() < reopenAt or not eligible(view) then return false end
    local target = GetOffsetFromEntityInWorldCoords(view.entity, 0.0, 0.0, .16)
    local pos = GetOffsetFromEntityInWorldCoords(view.entity, 0.0, -.38, .86)
    local camera = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z,
        0.0, 0.0, GetEntityHeading(view.entity) + 0.0, 48.0, false, 2)
    if camera == 0 then return false end
    sequence = sequence + 1
    nextDetails = 0
    C.inspect = { view = view, camera = camera, session = sequence }
    PointCamAtCoord(camera, target.x, target.y, target.z)
    SetCamActive(camera, true)
    RenderScriptCams(true, false, 0, true, true)
    SetNuiFocusKeepInput(false)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'inspect', visible = true, session = sequence })
    return true
end

-- Les régions suivent la projection de volumes locaux des modules. La tolérance
-- reste proportionnelle à leur taille, y compris sur un écran ultra-large.
function I.Pick(view, x, y)
    local best, score
    for _, d in ipairs(descriptors) do
        if available(view, d) then
            local center = C.SocketWorld(view, d.bone)
            local origin = GetEntityCoords(view.entity)
            local minX, minY, maxX, maxY = 1.0, 1.0, 0.0, 0.0
            local any = false
            for _, dx in ipairs({ -d.size[1], d.size[1] }) do
                for _, dy in ipairs({ -d.size[2], d.size[2] }) do
                    for _, dz in ipairs({ 0.0, d.size[3] }) do
                        local p = center + GetOffsetFromEntityInWorldCoords(view.entity, dx, dy, dz) - origin
                        local visible, sx, sy = World3dToScreen2d(p.x, p.y, p.z)
                        if visible then
                            any = true
                            minX, minY = math.min(minX, sx), math.min(minY, sy)
                            maxX, maxY = math.max(maxX, sx), math.max(maxY, sy)
                        end
                    end
                end
            end
            if any and x >= minX and x <= maxX and y >= minY and y <= maxY then
                local dx = (x - (minX + maxX) / 2) / math.max(.001, (maxX - minX) / 2)
                local dy = (y - (minY + maxY) / 2) / math.max(.001, (maxY - minY) / 2)
                local s = dx * dx + dy * dy
                if not score or s < score then best, score = d, s end
            end
        end
    end
    return best
end

local function act(view, d, direction)
    if not available(view, d) then return false end
    if d.action == 'gauge' then
        Bridge.Notify(('Stabilité : %d %%'):format(view.state.stability), 'inform')
    elseif d.action == 'vial' then
        Bridge.Notify('Charge : ' .. view.state.kind, 'inform')
    elseif d.action == 'plate' then
        Bridge.Notify(I.Label(view,d), 'inform')
    elseif d.action == 'knob' then
        return C.Request(view, 'knob', { id = d.value, delta = direction * 15 })
    else
        return C.Request(view, d.action, d.value)
    end
    return true
end

local function selection(data)
    local inspection = C.inspect
    if type(data) ~= 'table' or not inspection or data.session ~= inspection.session
        or not eligible(inspection.view) then return end
    local x, y = data.x, data.y
    if type(x) ~= 'number' or type(y) ~= 'number' or x ~= x or y ~= y
        or x < 0 or x > 1 or y < 0 or y > 1 then return end
    return inspection.view, I.Pick(inspection.view, x, y)
end

RegisterNUICallback('ibomb_hover', function(data, cb)
    local view, d = selection(data)
    cb({ label = d and I.Label(view,d) or 'Visez un module', hit = d ~= nil })
end)
RegisterNUICallback('ibomb_click', function(data, cb)
    local view, d = selection(data)
    if not d then cb({ ok = false, message = 'Aucun module sous le curseur.' }); return end
    local direction = data.direction == -1 and -1 or 1
    if (data.wheel or direction == -1) and d.action ~= 'knob' then
        cb({ ok = false, message = d.label }); return
    end
    local ok = act(view, d, direction)
    cb({ ok = ok == true, message = ok and ('Demande envoyée : ' .. d.label) or 'Action indisponible.' })
end)
RegisterNUICallback('ibomb_close', function(data, cb)
    if C.inspect and type(data) == 'table' and data.session == C.inspect.session then I.Exit() end
    cb({ ok = true })
end)
RegisterNUICallback('ibomb_ready', function(_, cb)
    cb({ visible = C.inspect ~= nil, session = C.inspect and C.inspect.session or 0 })
end)

options[1] = {
    name = 'ibomb:inspect', label = 'Examiner la bombe', icon = 'fa-solid fa-microchip',
    distance = Config.InteractDistance,
    canInteract = function(entity) return not C.inspect and eligible(C.views[entity]) end,
    onSelect = function(data) I.Enter(C.views[data.entity]) end
}
for index, d in ipairs(descriptors) do
    for _, direction in ipairs(d.action == 'knob' and { 1, -1 } or { 1 }) do
        local option = {
            name = ('ibomb:%d:%d'):format(index, direction),
            label = d.label .. (d.action == 'knob' and (direction == 1 and ' +15°' or ' -15°') or ''),
            icon = 'fa-solid fa-microchip', distance = Config.InteractDistance,
            bones = { d.bone },
            canInteract = function(entity, _, coords)
                local view = C.views[entity]
                return not C.inspect and available(view, d) and coords
                    and #(coords - C.SocketWorld(view, d.bone)) <= Config.TargetRadius
            end,
            onSelect = function(data) act(C.views[data.entity], d, direction) end
        }
        options[#options + 1] = option
    end
end
for _, option in ipairs(options) do optionNames[#optionNames + 1] = option.name end

function I.Ensure(view)
    if C.stopping or GetResourceState('ox_target') ~= 'started' or view.targetAdded then return end
    view.targetAdded = pcall(function() exports.ox_target:addLocalEntity(view.entity, options) end)
end
function I.Remove(view)
    if C.inspect and C.inspect.view == view then I.Exit() end
    if view.targetAdded and GetResourceState('ox_target') == 'started' then
        pcall(function() exports.ox_target:removeLocalEntity(view.entity, optionNames) end)
    end
    view.targetAdded = false
end
AddEventHandler('onClientResourceStop', function(resource)
    if resource == 'ox_target' then
        for _, view in pairs(C.views) do view.targetAdded = false end
    end
end)

-- E ouvre uniquement l'inspection. Aucune action de module dans cette boucle.
CreateThread(function()
    while not C.stopping do
        local inspection = C.inspect
        if inspection then
            if GetGameTimer() >= nextDetails then
                local state = inspection.view.state
                SendNUIMessage({ action = 'details', session = inspection.session,
                    clues = state.clues, kind = state.kind, knobs = state.knobs, switches = state.switches,
                    timer = BombScreen.Payload(inspection.view,C.Now()).timer })
                nextDetails = GetGameTimer() + 100
            end
            DisablePlayerFiring(PlayerId(), true)
            for _, control in ipairs({ 1, 2, 24, 25, 30, 31, 38, 140, 141, 142, 257, 263, 264, 200, 202 }) do
                DisableControlAction(0, control, true)
            end
            if not eligible(inspection.view) then I.Exit() end
            Wait(0)
        else
            local nearest, distance
            for _, view in pairs(C.views) do
                if eligible(view) then
                    local d = #(GetEntityCoords(view.entity) - GetEntityCoords(PlayerPedId()))
                    if not distance or d < distance then nearest, distance = view, d end
                end
            end
            if nearest then
                C.Help('~INPUT_CONTEXT~ Examiner la bombe')
                if IsControlJustPressed(0, 38) then I.Enter(nearest) end
                Wait(0)
            else Wait(150) end
        end
    end
end)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then I.Exit() end
end)
