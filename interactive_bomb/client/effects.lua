-- Effets GTA V fictifs. La décision de dégâts appartient exclusivement au serveur.
-- Ne jamais émettre AddExplosion/StartNetworkedParticleFx* depuis chaque observateur.
BombEffects = {}

local active, played, assets = {}, {}, {}
local particleCount = 0
local V = Config.EffectVisuals
local blackoutApplied, blurApplied = false, false
local nextGeiger, nextCough, coughWantedUntil = 0, 0, 0
local coughPed, coughRequestedAt
local coughDict, coughClip = 'timetable@gardener@smoking_joint', 'idle_cough'

-- Couples présents dans un dump de données GTA V; QA visuelle nécessaire sur le build cible.
-- Un dictionnaire chargé ne garantit pas que chaque effet peut boucler ou être recoloré.
local defaults = {
    explosive = { dict = 'core', burst = 'exp_grd_grenade', loop = 'ent_amb_beach_campfire', scale = 0.8 },
    bio = { dict = 'core', loop = 'exp_grd_bzgas_smoke', scale = 1.8, color = { 0.2, 0.8, 0.1 } },
    nuke = { dict = 'core', burst = 'exp_grd_grenade', loop = 'ent_amb_fbi_smoke_linger_hvy', scale = 3.0 },
    emp = { dict = 'core', burst = 'ent_dst_electrical', scale = 1.0 }
}

local function particleConfig(kind)
    return (Config.Particles and Config.Particles[kind]) or defaults[kind]
end

-- Chargement non bloquant, partagé entre les bombes; un échec ne bloque jamais le rendu.
local function assetReady(dict)
    if HasNamedPtfxAssetLoaded(dict) then return true end
    local request = assets[dict]
    if not request then
        assets[dict] = { requestedAt = GetGameTimer() }
        RequestNamedPtfxAsset(dict)
    elseif not request.failed and GetGameTimer() - request.requestedAt > 2000 then
        request.failed = true
        print(('[interactive_bomb] PTFX introuvable ou lent: %s; rendu ignoré.'):format(dict))
    end
    return false
end

local function stop(record)
    for _, handle in ipairs(record.particles) do
        if DoesParticleFxLoopedExist(handle) then StopParticleFxLooped(handle, false) end
    end
    for _, handle in ipairs(record.fires) do RemoveScriptFire(handle) end
    particleCount = math.max(0, particleCount - #record.particles)
    record.particles, record.fires = {}, {}
end

function BombEffects.Remove(id)
    if active[id] then stop(active[id]); active[id] = nil end
    -- Les tombstones "played" restent jusqu'à expiration: un re-stream ne rejoue pas le flash.
end

local function persistentParticles(record, fx)
    if record.loopsStarted or not fx.loop or not assetReady(fx.dict) then return end
    record.loopsStarted = true
    local radius = Config.Effects[record.kind].radius
    local layers = {}
    local function layer(name,x,y,z,scale,color)
        layers[#layers+1] = { name=name, x=x, y=y, z=z, scale=scale, color=color }
    end
    if record.kind == 'bio' then
        layer(fx.loop,0,0,.3,2.1,fx.color)
        for i=0,5 do
            local a=i*math.pi/3
            layer(fx.loop,math.cos(a)*radius*.48,math.sin(a)*radius*.48,.25,1.8,fx.color)
        end
    elseif record.kind == 'nuke' then
        -- Colonne et couronne de fumée : composition stylisée, pas un asset nucléaire natif.
        for i=0,2 do layer(fx.loop,0,0,1.0+i*3.0,2.5+i*.7) end
        for i=0,5 do
            local a=i*math.pi/3
            layer(fx.loop,math.cos(a)*5.5,math.sin(a)*5.5,10.0,3.6)
        end
    elseif record.kind == 'explosive' then
        for _,p in ipairs({{0,0},{1.5,.4},{-1.2,-.6}}) do layer(fx.loop,p[1],p[2],.1,.9) end
        layer('ent_amb_fbi_smoke_linger_hvy',0,0,1.2,1.3)
    else
        layer(fx.loop,0,0,.1,fx.scale or 1.0,fx.color)
    end
    for _, item in ipairs(layers) do
        if particleCount >= V.maxParticles then break end
        UseParticleFxAssetNextCall(fx.dict)
        local p = record.coords
        local handle = StartParticleFxLoopedAtCoord(item.name,
            p.x + item.x, p.y + item.y, p.z + item.z,
            0.0, 0.0, 0.0, item.scale, false, false, false, false)
        if handle and handle ~= 0 then
            record.particles[#record.particles + 1] = handle
            record.scales[handle] = item.scale
            particleCount = particleCount + 1
            if item.color then SetParticleFxLoopedColour(handle, item.color[1], item.color[2], item.color[3], false) end
        else
            print(('[interactive_bomb] PTFX non démarré: %s/%s'):format(fx.dict, fx.loop))
        end
    end
end

local function startSequence(record)
    local steps = {}
    local function burst(delay,name,x,y,z,scale)
        steps[#steps+1]={at=delay,name=name,x=x,y=y,z=z,scale=scale}
    end
    if record.kind == 'explosive' then
        burst(0,'exp_grd_rpg',0,0,.2,1.5)
        for i=0,3 do
            local a=i*math.pi/2
            burst(150,'ent_dst_concrete_large',math.cos(a)*1.2,math.sin(a)*1.2,.25,.8)
        end
    elseif record.kind == 'bio' then
        burst(0,'exp_grd_bzgas_smoke',0,0,.3,2.2)
    elseif record.kind == 'nuke' then
        burst(0,'exp_grd_rpg',0,0,1.2,5.0)
        for i=0,5 do
            local a=i*math.pi/3
            burst(300,'exp_grd_grenade',math.cos(a)*4.0,math.sin(a)*4.0,.5,1.8)
            burst(650,'ent_dst_concrete_large',math.cos(a)*8.0,math.sin(a)*8.0,.3,1.3)
        end
    elseif record.kind == 'emp' then
        for i=0,5 do
            local a=i*math.pi/3
            burst(i*100,'ent_dst_electrical',math.cos(a)*1.1,math.sin(a)*1.1,.6,1.5)
        end
    end
    record.steps = steps
    local spec=V[record.kind]
    local cam=GetGameplayCamCoord()
    local delta=record.coords-cam
    local distance=#delta
    local strength=math.max(0,1-distance/spec.soundRadius)
    if strength > 0 then
        local yaw=math.rad(GetGameplayCamRot(2).z)
        local pan=distance>.01 and (delta.x*math.cos(yaw)+delta.y*math.sin(yaw))/distance or 0
        SendNUIMessage({action='bomb_fx',kind=record.kind,volume=strength*strength*V.soundVolume,
            pan=math.max(-1,math.min(1,pan)),key=record.id..':'..record.detonatedAt})
        if V.cameraShake then ShakeGameplayCam('SMALL_EXPLOSION_SHAKE',spec.shake*strength) end
    end
end

local function advanceSequence(record,age)
    if not record.steps then return end
    for _,step in ipairs(record.steps) do
        if not step.done and age>=step.at then
            if age>step.at+1200 then step.done=true
            elseif assetReady('core') then
                step.done=true
                UseParticleFxAssetNextCall('core')
                local p=record.coords
                StartParticleFxNonLoopedAtCoord(step.name,p.x+step.x,p.y+step.y,p.z+step.z,
                    0.0,0.0,0.0,step.scale,false,false,false)
            end
        end
    end
end

local function scriptFires(record)
    if record.firesStarted or record.kind ~= 'explosive' or not Config.EnableScriptFires then return end
    record.firesStarted = true
    -- Option désactivée par défaut: le feu moteur peut brûler des entités indépendamment
    -- des dégâts contrôlés par le serveur. maxChildren=0 limite sa propagation.
    for _, offset in ipairs({ { 0.0, 0.0 }, { 1.4, 0.5 }, { -1.0, -0.8 } }) do
        local p = record.coords
        local handle = StartScriptFire(p.x + offset[1], p.y + offset[2], p.z, 0, false)
        if handle and handle ~= -1 then record.fires[#record.fires + 1] = handle end
    end
end

-- Appel possible depuis un renderer; la boucle interne suffit et aucun Wait n'est exécuté ici.
function BombEffects.Update(view)
    local now = BombClient.Now()
    local state = view.state
    if not now or not state or not state.id then return end
    if state.detonatedAt and now < state.detonatedAt then return end
    if state.status ~= 'detonated' or not state.fxUntil or now >= state.fxUntil
        or not DoesEntityExist(view.entity) then
        BombEffects.Remove(state.id)
        return
    end
    if state.bucket ~= nil and BombClient.bucket ~= nil and state.bucket ~= BombClient.bucket then
        BombEffects.Remove(state.id)
        return
    end
    if #(GetEntityCoords(view.entity)-GetEntityCoords(PlayerPedId())) > V.maxDistance then
        BombEffects.Remove(state.id); return
    end
    local record = active[state.id]
    if record and record.detonatedAt ~= state.detonatedAt then
        BombEffects.Remove(state.id)
        record = nil
    end
    if not record then
        record = { id = state.id, kind = state.kind, entity = view.entity,
            detonatedAt = state.detonatedAt, untilAt = state.fxUntil,
            coords = GetEntityCoords(view.entity), particles = {}, fires = {}, scales = {} }
        active[state.id] = record
    end
    local fx = particleConfig(record.kind)
    if not fx or not Config.Effects[record.kind] then return end
    local key = tostring(record.id) .. ':' .. tostring(record.detonatedAt)
    local age = now - (record.detonatedAt or 0)
    if not played[key] then
        played[key] = state.fxUntil + 60000
        record.fresh = age >= 0 and age < 1500
        if record.fresh then startSequence(record) end
    end
    advanceSequence(record,age)
    persistentParticles(record, fx)
    local fade = math.min(1.0,math.max(0.0,age/1500),math.max(0.0,(record.untilAt-now)/4000))
    for _,handle in ipairs(record.particles) do
        if DoesParticleFxLoopedExist(handle) then
            SetParticleFxLoopedAlpha(handle,fade)
            if record.kind=='bio' then SetParticleFxLoopedScale(handle,record.scales[handle]*(.45+.55*math.min(1.0,age/3500))) end
        end
    end
    scriptFires(record)
end

-- Lumières et impulsions dessinées localement : aucun dommage ni événement explosion réseau.
function BombEffects.RenderFrame()
    local now=BombClient.Now()
    if not now or BombClient.stopping then return false end
    local pos=GetEntityCoords(PlayerPedId())
    local lights,flash,tint=0,0,0
    local hasFrame=false
    for _,record in pairs(active) do
        local age=now-record.detonatedAt
        local distance=#(pos-record.coords)
        if now<record.untilAt and distance<V.maxDistance then
            local spec,p=V[record.kind],record.coords
            if record.fresh and age>=0 and age<1800 then
                hasFrame=true
                local decay=math.max(0,1-age/1800)
                local r,g,b=255,145,45
                if record.kind=='bio' then r,g,b=70,255,80
                elseif record.kind=='emp' then r,g,b=70,170,255
                elseif record.kind=='nuke' then r,g,b=255,235,180 end
                if lights<4 then
                    DrawLightWithRange(p.x,p.y,p.z+1.0,r,g,b,spec.lightRadius,decay*7.0)
                    lights=lights+1
                end
                if record.kind=='emp' then
                    local diameter=2.0+age/1800*65.0
                    DrawMarker(28,p.x,p.y,p.z+.2,0.0,0.0,0.0,0.0,0.0,0.0,
                        diameter,diameter,diameter*.12,80,180,255,math.floor(decay*95),
                        false,false,2,false,nil,nil,false)
                elseif record.kind=='nuke' and age<650 then
                    flash=math.max(flash,(1-age/650)*math.max(0,1-distance/spec.soundRadius))
                end
            end
            if record.kind=='nuke' and distance<Config.Effects.nuke.radius then
                tint=math.max(tint,1-distance/Config.Effects.nuke.radius);hasFrame=true
            end
        end
    end
    if V.flash and flash>0 then DrawRect(.5,.5,1.0,1.0,255,240,210,math.floor(flash*150)) end
    if tint>0 then DrawRect(.5,.5,1.0,1.0,80,110,35,math.floor(tint*18)) end
    return hasFrame
end

CreateThread(function()
    while not BombClient.stopping do Wait(BombEffects.RenderFrame() and 0 or 100) end
end)

-- Remplacer ce hook par un lecteur audio local / une banque audio autorisée pour un vrai
-- crépitement Geiger. Le son de base est volontairement un simple clic d'interface GTA.
function BombEffects.PlayGeigerTick(intensity)
    SendNUIMessage({action='bomb_geiger',volume=(.12+.2*intensity)*V.soundVolume})
end

local function applyEnvironment(empCount, radiationCount)
    local needBlackout = empCount > 0
    if needBlackout ~= blackoutApplied then
        SetArtificialLightsState(needBlackout)
        blackoutApplied = needBlackout
    end
    local needBlur = radiationCount > 0 and Config.EnableRadiationBlur ~= false
    if needBlur ~= blurApplied then
        if needBlur then TriggerScreenblurFadeIn(500.0) else TriggerScreenblurFadeOut(500.0) end
        blurApplied = needBlur
    end
    -- Ces natives ont un état global au client. Avec une ressource météo/hôpital,
    -- remplacer cette fonction par un arbitre partagé; il n'existe ici aucun "restore previous".
end

local function updateCough(timer)
    if coughWantedUntil <= timer then return end
    if not HasAnimDictLoaded(coughDict) then
        if not coughRequestedAt then
            RequestAnimDict(coughDict)
            coughRequestedAt = timer
        elseif timer - coughRequestedAt > 2000 then
            coughWantedUntil = 0
        end
        return
    end
    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) or IsPedRagdoll(ped) then return end
    TaskPlayAnim(ped, coughDict, coughClip, 2.0, 2.0, 1500, 49, 0.0, false, false, false)
    coughPed = ped
    coughWantedUntil = 0
end

-- Uniquement le serveur appelle cet événement après contrôle position/bucket/exposition.
-- La santé demeure appliquée par le client: ce n'est pas un anticheat serveur.
RegisterNetEvent('ibomb:exposure', function(damage, kind)
    if source ~= 65535 then return end
    if type(damage) ~= 'number' or damage ~= damage or damage < 0 or damage > 200 then return end
    if not Config.Effects[kind] then return end
    local ped = PlayerPedId()
    if IsEntityDead(ped) then return end
    if damage > 0 then ApplyDamageToPed(ped, math.floor(damage), false) end
    local timer = GetGameTimer()
    if kind == 'bio' and timer >= nextCough then
        nextCough, coughWantedUntil = timer + 6000, timer + 2500
    end
end)

CreateThread(function()
    while not BombClient.stopping do
        Wait(200)
        if BombClient.stopping then break end
        if BombClient and BombClient.views and BombClient.Now() then
            local now, timer = BombClient.Now(), GetGameTimer()
            local present = {}
            for _, view in pairs(BombClient.views) do
                if view.state and view.state.id then
                    present[view.state.id] = true
                    BombEffects.Update(view)
                end
            end
            local playerCoords = GetEntityCoords(PlayerPedId())
            local empCount, radiationCount, intensity = 0, 0, 0.0
            for id, record in pairs(active) do
                if not present[id] or now >= record.untilAt or not DoesEntityExist(record.entity) then
                    BombEffects.Remove(id)
                else
                    local cfg = Config.Effects[record.kind]
                    local distance = #(playerCoords - record.coords)
                    if cfg and distance <= cfg.radius then
                        if record.kind == 'emp' then empCount = empCount + 1 end
                        if record.kind == 'nuke' then
                            radiationCount = radiationCount + 1
                            intensity = math.max(intensity, 1.0 - distance / cfg.radius)
                        end
                    end
                end
            end
            applyEnvironment(empCount, radiationCount)
            if radiationCount > 0 and timer >= nextGeiger then
                BombEffects.PlayGeigerTick(intensity)
                nextGeiger = timer + math.floor(1400 - 1150 * intensity)
            end
            updateCough(timer)
            for key, expiry in pairs(played) do if now >= expiry then played[key] = nil end end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SendNUIMessage({action='bomb_fx_stop'})
    for _, record in pairs(active) do stop(record) end
    active,played={},{}
    if blackoutApplied then SetArtificialLightsState(false) end
    if blurApplied then TriggerScreenblurFadeOut(0.0) end
    if coughPed and DoesEntityExist(coughPed) then StopAnimTask(coughPed, coughDict, coughClip, 1.0) end
    if coughRequestedAt then RemoveAnimDict(coughDict) end
    for dict in pairs(assets) do RemoveNamedPtfxAsset(dict) end
end)
