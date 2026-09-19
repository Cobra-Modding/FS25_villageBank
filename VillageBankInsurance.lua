-- ============================================================
-- FS25_VillageBankInsurance.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

function VehicleInsurance.bookMoney(vehicle, amount, moneyType, label)
    local mission = g_currentMission
    if mission == nil or not mission:getIsServer() then return end
    local farmId = vehicle:getOwnerFarmId()
    mission:addMoney(amount, farmId, moneyType, true, true)
    local bank = g_villageBank
    if bank ~= nil then
        local data = bank:getFarmData(farmId)
        local mainName = "Hofkonto"
        for _, account in ipairs(data.accounts) do
            if account.isMain then mainName = account.name; break end
        end
        bank:addTransaction(data, label,
            amount < 0 and mainName or VehicleInsurance.getDisplayName(vehicle),
            amount < 0 and VehicleInsurance.getDisplayName(vehicle) or mainName, amount)
        data.revision=(data.revision or 0)+1
        VehicleInsurance.bankJournalDirty = true
    end
end

function VehicleInsurance:mouseEvent() end
function VehicleInsurance:draw() end

local originalInsuranceUpdate = VehicleInsurance.update
function VehicleInsurance:update(dt)
    originalInsuranceUpdate(self,dt)
    if self.bankJournalDirty and g_currentMission~=nil and g_currentMission:getIsServer() and g_villageBank~=nil then
        self.bankJournalDirty=false
        g_villageBank:saveState(nil,true)
        if VillageBankNetwork~=nil then VillageBankNetwork.broadcastState() end
    end
end

local originalInsuranceLoadMap = VehicleInsurance.loadMap
function VehicleInsurance:loadMap(...)
    if g_modIsLoaded ~= nil and g_modIsLoaded.FS25_VehicleInsurance then
        self.enabled = false
        self.integrationConflict = true
        Logging.error("[VillageBank] Disable FS25_VehicleInsurance: insurance is included in FS25_villageBank.")
        return
    end
    self.integrationConflict = false
    return originalInsuranceLoadMap(self, ...)
end
