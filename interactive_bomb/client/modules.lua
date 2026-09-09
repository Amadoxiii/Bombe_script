BombModules = {}
local M, C = BombModules, BombClient

local function sound(view, name)
    local spec = Config.Sounds[name]
    if not spec then return end
    local id = GetSoundId()
    -- Chaque observateur joue sa copie spatialisée, isNetwork=false.
    PlaySoundFromEntity(id, spec.name, view.entity, spec.set, false, 0)
    ReleaseSoundId(id)
end

local function attach(view, name, dz, rx, ry, rz)
    local part = view.parts[name]
    if not part or not DoesEntityExist(part) or not DoesEntityExist(view.entity) then return end
    local index = C.Socket(view, name)
    local x, y, z = 0.0, 0.0, dz or 0.0
    if index == -1 then
        local p = Config.Sockets[name] or { 0, 0, 0 }
        x, y, z = p[1], p[2], p[3] + z
    end
    -- isPed=true contourne la restriction pitch/roll documentée du native.
    -- Le child reste un object ; valider orientation/roll sur le build cible.
    AttachEntityToEntity(part, view.entity, index, x, y, z,
        rx or 0.0, ry or 0.0, rz or 0.0, false, false, false, true, 2, true)
end

local function createPart(view, bone, model, generation)
    if C.stopping or view.cancelled or not view.wantsParts or view.generation ~= generation then return end
    local hash = C.LoadModel(model)
    if not hash then return end
    if C.stopping or view.cancelled or not view.wantsParts or view.generation ~= generation or not DoesEntityExist(view.entity) then
        SetModelAsNoLongerNeeded(hash)
        return
    end
    local pos = GetEntityCoords(view.entity)
    -- Aucun net ID pour ces pièces : seule la racine utilise OneSync.
    local part = CreateObjectNoOffset(hash, pos.x, pos.y, pos.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if part == 0 then return end
    SetEntityAsMissionEntity(part, true, true)
    SetEntityCollision(part, false, false)
    SetEntityInvincible(part, true)
    SetEntityVisible(part, false, false)
    view.parts[bone] = part
    attach(view, bone)
end

local function visible(view, bone, enabled)
    local entity = view.parts[bone]
    if entity then SetEntityVisible(entity, enabled, false) end
end

-- Ces fonctions RENDENT un état accepté ; C.Request envoie une intention serveur.
function CutWire(entity, wireColor)
    local view = C.views[entity]
    if not view then return end
    local prefix = 'bone_wire_' .. wireColor .. '_'
    visible(view, prefix .. 'intact', false)
    visible(view, prefix .. 'cut_a', true)
    visible(view, prefix .. 'cut_b', true)
end

function ToggleSwitch(entity, switchId, state)
    local view = C.views[entity]
    if not view or not view.built then return end
    view.targets['bone_switch_' .. switchId] = state and 28.0 or -28.0
end

function RotateKnob(entity, knobId, angle)
    local view = C.views[entity]
    if not view or not view.built then return end
    view.targets['bone_knob_' .. knobId] = angle % 360.0
end

function PressKeypad(entity, key)
    local view = C.views[entity]
    if not view or not view.built then return end
    local bone = 'bone_key_' .. (Config.KeyNames[key] or key)
    if not Config.Sockets[bone] then return end
    view.presses[bone] = GetGameTimer() + 150
    sound(view, 'key')
    -- Le code saisi vient déjà de view.state.code, jamais d'un append local.
end

function UpdateGauge(entity, percentage)
    local view = C.views[entity]
    if not view or not view.built then return end
    local pct = math.max(0.0, math.min(100.0, percentage))
    view.targets.bone_gauge_needle = -120.0 + 240.0 * pct / 100.0
end

function M.Apply(view, previous)
    if not view.built then return end
    local state = view.state
    for _, color in ipairs(Config.WireColors) do
        local prefix = 'bone_wire_' .. color .. '_'
        if state.wires[color] then
            CutWire(view.entity, color)
            if previous and not previous.wires[color] then
                sound(view, 'cut')
                view.cutAt[color] = GetGameTimer()
            end
        else
            visible(view, prefix .. 'intact', true)
            visible(view, prefix .. 'cut_a', false)
            visible(view, prefix .. 'cut_b', false)
        end
    end
    for _, id in ipairs(Config.SwitchIds) do
        ToggleSwitch(view.entity, id, state.switches[id])
        if previous and previous.switches[id] ~= state.switches[id] then sound(view, 'switch') end
    end
    for _, id in ipairs(Config.KnobIds) do RotateKnob(view.entity, id, state.knobs[id]) end
    UpdateGauge(view.entity, state.stability)
    if not previous then
        for bone, target in pairs(view.targets) do view.angles[bone] = target end
    elseif state.keySeq ~= previous.keySeq then
        local now = C.Now()
        if now and now - state.keyAt < 600 then PressKeypad(view.entity, state.keyLast) end
    end
end

function M.Build(view)
    view.generation = (view.generation or 0) + 1
    local generation = view.generation
    local function part(bone, model) createPart(view, bone, model, generation) end
    view.targets, view.angles, view.presses, view.cutAt = {}, {}, {}, {}
    for _, color in ipairs(Config.WireColors) do
        for _, suffix in ipairs({ 'intact', 'cut_a', 'cut_b' }) do
            part('bone_wire_' .. color .. '_' .. suffix, 'ib_wire_' .. color .. '_' .. suffix)
        end
    end
    for _, id in ipairs(Config.SwitchIds) do part('bone_switch_' .. id, 'ib_switch') end
    for _, id in ipairs(Config.KnobIds) do part('bone_knob_' .. id, 'ib_knob') end
    part('bone_gauge_needle', 'ib_gauge_needle')
    for _, key in ipairs(Config.Keys) do
        local name = Config.KeyNames[key] or key
        part('bone_key_' .. name, 'ib_key_' .. name)
    end
    for i = 1, 2 do part('bone_vial_slot_' .. i, 'ib_vial_' .. view.state.kind) end
    if C.stopping or view.cancelled or not view.wantsParts or view.generation ~= generation then M.Destroy(view); return end
    for _, part in pairs(view.parts) do SetEntityVisible(part, true, false) end
    view.built = true
    M.Apply(view, nil)
end

function M.Destroy(view)
    view.generation = (view.generation or 0) + 1
    for _, part in pairs(view.parts or {}) do
        if DoesEntityExist(part) then
            DetachEntity(part, true, true)
            DeleteEntity(part)
        end
    end
    view.parts, view.built = {}, false
end

CreateThread(function()
    while not C.stopping do
        local active = false
        local dt = math.min(GetFrameTime(), 0.05)
        for _, view in pairs(C.views) do
            if view.built and DoesEntityExist(view.entity) then
                active = true
                for bone, target in pairs(view.targets) do
                    local current = view.angles[bone] or target
                    -- Plus court chemin uniquement pour une molette circulaire.
                    local delta = target - current
                    if bone:find('bone_knob_', 1, true) == 1 then delta = (delta + 180) % 360 - 180 end
                    current = current + delta * math.min(1.0, dt * 18.0)
                    if math.abs(delta) < 0.1 then current = target end
                    view.angles[bone] = current
                    if bone:find('bone_switch_', 1, true) == 1 then
                        attach(view, bone, 0, current, 0, 0)
                    else
                        attach(view, bone, 0, 0, 0, current)
                    end
                end
                local now = GetGameTimer()
                for bone, untilTime in pairs(view.presses) do
                    local remaining = untilTime - now
                    attach(view, bone, remaining > 0 and -0.003 or 0.0)
                    if remaining <= 0 then view.presses[bone] = nil end
                end
                for color, time in pairs(view.cutAt) do
                    local t = (now - time) / 350
                    local angle = t < 1 and math.sin(t * math.pi * 3) * (1 - t) * 12 or 0
                    attach(view, 'bone_wire_' .. color .. '_cut_a', 0, angle, 0, 0)
                    attach(view, 'bone_wire_' .. color .. '_cut_b', 0, -angle, 0, 0)
                    if t >= 1 then view.cutAt[color] = nil end
                end
                if view.state.kind == 'bio' or view.state.kind == 'nuke' then
                    for i = 1, 2 do
                        local p = C.SocketWorld(view, 'bone_vial_slot_' .. i)
                        DrawLightWithRange(p.x, p.y, p.z + 0.04, 70, 255, 90, 0.22, 0.5)
                    end
                end
            end
        end
        Wait(active and 0 or 200)
    end
end)
