-- ============================================================
-- FS25_VehicleInsuranceNetwork.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

local Mod = VehicleInsurance

local fields = {"policy", "pending", "months", "premiums", "taxes", "refunds", "lastDay"}



function Mod.writeState(streamId, state)

    for _, name in ipairs(fields) do streamWriteFloat32(streamId, state[name] or 0) end

end



function Mod.readState(streamId)

    local state = {}

    for _, name in ipairs(fields) do state[name] = streamReadFloat32(streamId) end

    return state

end



function Mod.applyState(vehicle, state)

    if vehicle.vitState ~= nil then vehicle.vitState = state

    else vehicle.viIncomingState = state end

end



function Mod.writeVehicleStream(vehicle, streamId, connection)

    if not connection:getIsServer() then

        Mod.initializeVehicle(vehicle)

        local state = vehicle.vitState

        streamWriteBool(streamId, state ~= nil)

        if state ~= nil then Mod.writeState(streamId, state) end

    end

end



function Mod.readVehicleStream(vehicle, streamId, connection)

    if connection:getIsServer() and streamReadBool(streamId) then

        Mod.applyState(vehicle, Mod.readState(streamId))

    end

end



function Mod.syncVehicle(vehicle)

    if g_server ~= nil and vehicle.vitState ~= nil then

        g_server:broadcastEvent(VillageBankInsuranceEvent.new(vehicle), nil, nil, vehicle)

    end

end



function Mod.canChangePolicy(vehicle, connection)

    if not Mod.enabled or not Mod.isEligible(vehicle) then return false end

    local mission = g_currentMission

    local farmId = mission:getFarmId()

    if connection ~= nil then

        local player = mission.playerSystem:getPlayerByConnection(connection)

        if player == nil then return false end

        farmId = player.farmId

    end

    return farmId == vehicle:getOwnerFarmId()

        and mission:getHasPlayerPermission(Farm.PERMISSION.BUY_VEHICLE, connection, farmId)

end



function Mod.setPolicy(vehicle, policy, connection)

    if not g_currentMission:getIsServer() or (policy ~= 0 and policy ~= 2 and policy ~= 3)

        or not Mod.canChangePolicy(vehicle, connection) then return false end

    Mod.initializeVehicle(vehicle)

    if vehicle.vitState == nil then return false end

    vehicle.vitState.pending = policy

    Mod.syncVehicle(vehicle)

    return true

end



function Mod:requestPolicy(vehicle, policy)

    if g_currentMission:getIsServer() then

        if not Mod.setPolicy(vehicle, policy, nil) then

            self.notice = "Keine Berechtigung fuer diesen Versicherungsvertrag."; return

        end

        self.notice = "Tarif vorgemerkt: gueltig ab dem naechsten Spielmonat."

    elseif g_client ~= nil then

        g_client:getServerConnection():sendEvent(VillageBankInsuranceEvent.new(vehicle, policy))

        self.notice = "Tarifwechsel angefragt. Der Server prueft die Berechtigung."

    end

end



VillageBankInsuranceEvent = {}

local VillageBankInsuranceEvent_mt = Class(VillageBankInsuranceEvent, Event)

InitEventClass(VillageBankInsuranceEvent, "VillageBankInsuranceEvent")

function VillageBankInsuranceEvent.emptyNew() return Event.new(VillageBankInsuranceEvent_mt) end

function VillageBankInsuranceEvent.new(vehicle, policy)

    local self = VillageBankInsuranceEvent.emptyNew()

    self.vehicle, self.policy = vehicle, policy

    self.state = vehicle.vitState

    return self

end

function VillageBankInsuranceEvent:writeStream(streamId, connection)

    NetworkUtil.writeNodeObject(streamId, self.vehicle)

    if connection:getIsServer() then streamWriteUIntN(streamId, self.policy, 2)

    else Mod.writeState(streamId, self.state) end

end

function VillageBankInsuranceEvent:readStream(streamId, connection)

    self.vehicle = NetworkUtil.readNodeObject(streamId)

    if connection:getIsServer() then self.state = Mod.readState(streamId)

    else self.policy = streamReadUIntN(streamId, 2) end

    self:run(connection)

end

function VillageBankInsuranceEvent:run(connection)

    if self.vehicle == nil or not Mod.enabled then return end

    if connection:getIsServer() then

        Mod.applyState(self.vehicle, self.state)

        if self.vehicle:getOwnerFarmId() == g_currentMission:getFarmId() then

            Mod.notice = "Server: Tarif ab naechstem Monat: " .. (Mod.names[self.state.pending] or "-")

        end

    else

        Mod.setPolicy(self.vehicle, self.policy, connection)

    end

end



