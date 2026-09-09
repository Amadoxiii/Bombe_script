local C, ghost = BombClient, nil

local function cleanup()
    if ghost and DoesEntityExist(ghost) then DeleteEntity(ghost) end
    ghost, C.placing = nil, false
end

RegisterCommand('spawnbomb', function(_, args)
    if C.stopping or C.placing or C.inspect then return end
    local kind = (args[1] or 'explosive'):lower()
    if not Config.Types[kind] then
        Bridge.Notify('Usage : /spawnbomb [explosive|bio|nuke|emp]', 'error')
        return
    end
    C.placing = true
    CreateThread(function()
        local hash = C.LoadModel(Config.Model)
        if not hash then
            Bridge.Notify('Asset ib_case absent : voir la documentation Blender/Sollumz.', 'error')
            cleanup()
            return
        end
        local ped = PlayerPedId()
        if not C.placing then SetModelAsNoLongerNeeded(hash); return end
        local start = GetEntityCoords(ped)
        ghost = CreateObjectNoOffset(hash, start.x, start.y, start.z, false, false, false)
        SetModelAsNoLongerNeeded(hash)
        if ghost == 0 then cleanup(); return end
        SetEntityAsMissionEntity(ghost, true, true)
        SetEntityAlpha(ghost, 120, false)
        SetEntityCollision(ghost, false, false)
        FreezeEntityPosition(ghost, true)
        SetEntityInvincible(ghost, true)
        SetEntityVisible(ghost, false, false)
        local heading, height, ray = GetEntityHeading(ped), 0.0, nil
        local point, valid, sent = nil, false, false
        while C.placing and not IsEntityDead(ped) and not IsPedInAnyVehicle(ped, false) do
            for _, control in ipairs({ 14, 15, 10, 11, 24, 25, 201, 202 }) do
                DisableControlAction(0, control, true)
            end
            if not ray then ray = C.CameraRay(Config.SpawnDistance + 3.0, ped, 17) end
            local status, hit, coords, normal = GetShapeTestResult(ray)
            if status == 0 then ray, valid = nil, false end
            if status == 2 then
                ray = nil
                valid = (hit == 1 or hit == true) and normal.z >= 0.95
                    and #(coords - GetEntityCoords(ped)) <= Config.SpawnDistance
                point = valid and coords or nil
            end
            if IsDisabledControlJustPressed(0, 14) then heading = (heading + 5) % 360 end
            if IsDisabledControlJustPressed(0, 15) then heading = (heading - 5) % 360 end
            if IsDisabledControlPressed(0, 10) then height = math.min(0.5, height + GetFrameTime() * 0.15) end
            if IsDisabledControlPressed(0, 11) then height = math.max(0.0, height - GetFrameTime() * 0.15) end
            SetEntityVisible(ghost, valid, false)
            if valid and point then
                -- Le modèle a son origine sous la base : aucun offset Z implicite.
                SetEntityCoordsNoOffset(ghost, point.x, point.y, point.z + height, false, false, false)
                SetEntityHeading(ghost, heading)
            end
            C.Help(('Molette : tourner | Page Haut/Bas : hauteur %.2f m~n~Entrée : poser | Retour/Echap : annuler%s')
                :format(height, valid and '' or '~n~~r~Viser une surface presque horizontale à moins de 5 m'))
            if IsDisabledControlJustPressed(0, 202) then break end
            if valid and IsDisabledControlJustPressed(0, 201) then
                local p = GetEntityCoords(ghost)
                TriggerServerEvent('ibomb:spawn', kind, { x = p.x, y = p.y, z = p.z }, heading)
                sent = true
                break
            end
            Wait(0)
        end
        cleanup()
        if sent then Bridge.Notify('Placement envoyé au serveur.', 'inform') end
    end)
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then cleanup() end
end)
