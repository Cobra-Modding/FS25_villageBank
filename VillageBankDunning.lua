-- ============================================================
-- FS25_VillageBankDunning.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

function VillageBank:ensureDunningContract(contract)
    contract.arrearsCount=math.max(0,math.min(contract.monthsLeft or 0,math.floor(contract.arrearsCount or 0)))
end

function VillageBank:getContractArrears(contract,kind)
    if contract==nil then return 0,0 end
    self:ensureDunningContract(contract)
    local count=contract.arrearsCount
    local amount=count*(contract.monthlyRate or 0)
    if kind=="finance" and count>0 and count==contract.monthsLeft then amount=amount+(contract.balloon or 0) end
    return count,amount
end

function VillageBank:collectContractArrears(data,contract,kind,farmId)
    local account=self:getContractAccount(data,contract.paymentAccountId)
    self:ensureDunningContract(contract)
    local paid=0
    while contract.arrearsCount>0 do
        local due=contract.monthlyRate or 0
        if kind=="finance" and contract.monthsLeft==1 then due=due+(contract.balloon or 0) end
        if due<=0 or account==nil or not self:debitAccount(account,due,farmId) then break end
        contract.arrearsCount=contract.arrearsCount-1
        contract.monthsLeft=contract.monthsLeft-1
        paid=paid+due
        if kind=="finance" then contract.outstanding=math.max(0,(contract.outstanding or 0)-due) end
        self:addTransaction(data,kind=="lease" and "Leasingrate" or (contract.monthsLeft==0 and "Schlussrate" or "Finanzrate"),account.name,kind=="lease" and "Leasing" or "Finanzierung",-due)
    end
    if contract.monthsLeft==0 and contract.status~="settled" and contract.status~="purchaseOption" then
        if kind=="finance" then
            contract.status="settled"; contract.outstanding=0
            self:showBankNotification("Finanzierung für "..tostring(contract.vehicleName or "Fahrzeug").." vollständig beendet.",false,farmId)
        else
            contract.status="purchaseOption"
            self:showBankNotification("Leasing für "..tostring(contract.vehicleName or "Fahrzeug").." beendet. Bitte übernehmen oder zurückgeben.",true,farmId)
        end
    end
    return paid
end

function VillageBank:findDunningVehicle(contract,farmId)
    local id=tostring(contract.vehicleId or "")
    if id=="" then return nil end
    local match=nil
    for _,vehicle in ipairs(self:getMissionVehicles()) do
        local owner=vehicle.getOwnerFarmId~=nil and vehicle:getOwnerFarmId() or vehicle.ownerFarmId
        if owner==farmId and self:getVehicleUniqueId(vehicle)==id and not vehicle.isDeleted then
            if match~=nil then return nil end
            match=vehicle
        end
    end
    return match
end

function VillageBank:deleteDunningVehicle(vehicle)
    if g_server==nil or vehicle==nil or vehicle.markedForDeletion or vehicle.isDeleted then return end
    local spec=vehicle.spec_enterable
    local players=g_currentMission.playerSystem
    if spec~=nil and spec.isControlled and players~=nil then
        local player=players:getPlayerByUserId(spec.controllerUserId)
        if player~=nil then player:leaveVehicle(vehicle,true) end
    end
    if vehicle.getAttachedImplements~=nil and vehicle.detachImplementByObject~=nil then
        local children={}
        for _,implement in ipairs(vehicle:getAttachedImplements()) do table.insert(children,implement.object) end
        for _,child in ipairs(children) do vehicle:detachImplementByObject(child) end
    end
    local parent=vehicle.getAttacherVehicle~=nil and vehicle:getAttacherVehicle() or nil
    if parent~=nil and parent.detachImplementByObject~=nil then parent:detachImplementByObject(vehicle) end
    vehicle:delete()
end

function VillageBank:repossessContract(data,contract,kind,farmId)
    if g_server==nil then return end
    local vehicle=self:findDunningVehicle(contract,farmId)
    if vehicle==nil then
        self:showBankNotification("Einzug für "..tostring(contract.vehicleName or "Fahrzeug").." ausstehend: Fahrzeug-ID nicht eindeutig gefunden. Rückstand bleibt offen.",true,farmId)
        return
    end
    contract.status="repossessed"
    contract.monthsLeft=0; contract.arrearsCount=0; contract.outstanding=0
    self:addTransaction(data,"Fahrzeugeinzug",contract.vehicleName or "Fahrzeug","Dorfbank",0)
    self:saveState()
    self:deleteDunningVehicle(vehicle)
    self:showBankNotification("Drei offene Raten: "..tostring(contract.vehicleName or "Fahrzeug").." wurde eingezogen. Vertrag und Restschuld beendet; keine Erstattung.",true,farmId)
end

function VillageBank:processDunningMonth(data,contract,kind,farmId)
    if g_server==nil or contract.status=="repossessed" or (contract.monthsLeft or 0)<=0 then return end
    self:ensureDunningContract(contract)
    contract.arrearsCount=math.min(contract.monthsLeft,contract.arrearsCount+1)
    self:collectContractArrears(data,contract,kind,farmId)
    local count,amount=self:getContractArrears(contract,kind)
    if count>=3 then
        self:repossessContract(data,contract,kind,farmId)
    elseif count>0 then
        local stage=count==1 and "Erste Mahnung" or "Letzte Mahnung"
        local warning=count==2 and " Bei einer weiteren offenen Rate wird das Fahrzeug eingezogen." or " Einzug bei drei offenen Raten."
        self:showBankNotification(stage..": "..tostring(contract.vehicleName or "Fahrzeug").." – "..count.." Rate(n), "..g_i18n:formatMoney(amount,0,true,true).." offen. Zahlkonto: "..tostring(contract.paymentAccountName or "Hofkonto").."."..warning,true,farmId)
    end
end

function VillageBank:settleContractArrears(kind,contractId,farmId)
    farmId=farmId or self:getFarmId()
    if g_server==nil then
        VillageBankNetwork.requestArrearsPayment(kind,contractId,farmId)
        return
    end
    local data=self:getFarmData(farmId)
    for _,contract in ipairs(kind=="finance" and data.loans or data.leases) do
        if contract.id==contractId and contract.status~="repossessed" then
            local paid=self:collectContractArrears(data,contract,kind,farmId)
            local count=self:getContractArrears(contract,kind)
            self:showBankNotification(paid>0 and (count==0 and "Rückstand vollständig beglichen." or "Rückstand teilweise beglichen; "..count.." Rate(n) bleiben offen.") or "Zahlkonto deckt die älteste offene Rate nicht.",count>0,farmId)
            self:ensureFinancingData(data)
            self:saveState()
            return
        end
    end
end

function VillageBank:drawDunningDetails(contract,kind)
    local count,amount=self:getContractArrears(contract,kind)
    if contract~=nil and contract.status=="repossessed" then
        setTextColor(0.95,0.45,0.30,1); setTextAlignment(RenderText.ALIGN_LEFT)
        renderText(0.145,0.207,0.012,"Fahrzeug eingezogen – Vertrag und Restschuld beendet.")
        return
    end
    if count>0 then
        setTextColor(1,0.65,0.25,1); setTextAlignment(RenderText.ALIGN_LEFT)
        renderText(0.145,0.207,0.012,"Rückstand: "..count.." Rate(n) – "..g_i18n:formatMoney(amount,0,true,true).." | Einzug bei 3 offenen Raten")
    end
    self:drawButton(0.145,self.ACTION_BUTTON_Y or 0.172,0.245,0.035,"Rückstand begleichen",count>0)
end

function VillageBank:handleDunningMouse(px,py,contract,kind)
    if contract~=nil and (contract.arrearsCount or 0)>0 and self:isInside(px,py,0.145,self.ACTION_BUTTON_Y or 0.172,0.245,0.035) then
        self:settleContractArrears(kind,contract.id)
        return true
    end
    return false
end

function VillageBank:enforceDunningStates(dt)
    self.dunningTimer=(self.dunningTimer or 0)-(dt or 0)
    if self.dunningTimer>0 then return end
    self.dunningTimer=1000
    for farmId,data in pairs(self.farms) do
        for _,contracts in ipairs({data.loans or {},data.leases or {}}) do
            for _,contract in ipairs(contracts) do
                if contract.status=="repossessed" and g_server~=nil then
                    self:deleteDunningVehicle(self:findDunningVehicle(contract,farmId))
                end
            end
        end
    end
    for _,vehicle in ipairs(self:getMissionVehicles()) do
        if vehicle.getCanBeSold~=nil and not vehicle.villageBankSaleHooked then
            local original=vehicle.getCanBeSold
            vehicle.getCanBeSold=function(v,...)
                if g_villageBank~=nil and g_villageBank:hasOpenVehicleContract(v) then return false end
                return original(v,...)
            end
            vehicle.villageBankSaleHooked=true
        end
    end
end

function VillageBank:hasOpenVehicleContract(vehicle)
    local owner=vehicle.getOwnerFarmId~=nil and vehicle:getOwnerFarmId() or vehicle.ownerFarmId
    local data=self.farms[owner]
    local id=self:getVehicleUniqueId(vehicle)
    if data==nil or id==nil then return false end
    for _,contracts in ipairs({data.loans or {},data.leases or {}}) do
        for _,contract in ipairs(contracts) do
            if tostring(contract.vehicleId or "")==id and contract.status~="purchased" and contract.status~="returned" and contract.status~="settled" then return true end
        end
    end
    return false
end
