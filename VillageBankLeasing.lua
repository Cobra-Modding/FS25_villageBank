-- ============================================================
-- FS25_VillageBankLeasing.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

VillageBank.LEASE_PROFILES={{months=24,residual=0.40},{months=36,residual=0.32},{months=48,residual=0.25},{months=60,residual=0.20}}
VillageBank.LEASE_RATE=0.04
VillageBank.LEASE_VISIBLE_ROWS=6
local function lText(x,y,s,t,r,g,b,a) setTextColor(r or 1,g or 1,b or 1,a or 1); setTextAlignment(RenderText.ALIGN_LEFT); renderText(x,y,s,t) end
local function lMoney(v) return g_i18n:formatMoney(v or 0,0,true,true) end
local function profileIndex(profiles,months) for i,p in ipairs(profiles) do if p.months==months then return i end end return 1 end

function VillageBank:initLeasingModule() self.leaseFormOpen=false; self.leaseMonths=36; self.leaseAccountIndex=1; self.leaseVehicleIndex=1; self.selectedLeaseRow=1; self.leaseScrollOffset=0; self.pendingLeaseReturnId=nil end
function VillageBank:ensureLeasingData(data) data.leases=data.leases or {}; data.nextLeaseId=data.nextLeaseId or 1 end
function VillageBank:getLeaseProfile(months) for _,p in ipairs(self.LEASE_PROFILES) do if p.months==months then return p end end return self.LEASE_PROFILES[2] end
function VillageBank:openLeaseForm() self.leaseFormOpen=true; self.leaseMonths=36; self.leaseAccountIndex=1; self.leaseVehicleIndex=1; self.activeTextField="leaseAmount"; self.textBuffer="" end
function VillageBank:cycleLeaseAccount() local count=#self:getFarmData().accounts; if count>0 then self.leaseAccountIndex=self.leaseAccountIndex%count+1 end end
function VillageBank:cycleLeaseVehicle(direction) local vehicles=self:getContractVehicles(); if #vehicles>0 then self.leaseVehicleIndex=((self.leaseVehicleIndex-1+direction)%#vehicles)+1 end end
function VillageBank:cycleLeaseMonths(direction) local i=profileIndex(self.LEASE_PROFILES,self.leaseMonths); self.leaseMonths=self.LEASE_PROFILES[((i-1+direction)%#self.LEASE_PROFILES)+1].months end

function VillageBank:calculateLease(price,months)
    local p=self:getLeaseProfile(months); local down=price*0.10; local residual=price*p.residual; local financed=price-down; local monthlyInterest=self.LEASE_RATE/12
    local rate=((financed-residual)/months)+(financed+residual)/2*monthlyInterest
    return down,residual,rate
end

function VillageBank:createVehicleLease()
    local shopContext=self.shopContractContext~=nil and self.shopContractContext.kind=="lease" and self.shopContractContext or nil
    if shopContext==nil then self:setStatus("Leasing bitte über den Fahrzeughändler abschließen."); return end
    local price=shopContext.price; if price<1000 then return end
    local vehicle=shopContext~=nil and shopContext.vehicle or self:getContractVehicles()[self.leaseVehicleIndex]; if vehicle==nil then self:setStatus("Leasing abgelehnt: Bitte zuerst ein Fahrzeug auswählen."); return end
    local data=self:getFarmData(); self:ensureLeasingData(data); local down,residual,rate=self:calculateLease(price,self.leaseMonths)
    local approved,reason=self:checkContractLiquidity(price,down,rate,residual,self.leaseAccountIndex)
    if not approved then self:setStatus("Leasing abgelehnt: "..reason); return end
    local paymentAccount=data.accounts[self.leaseAccountIndex]; self:debitAccount(paymentAccount,down,self:getFarmId()); if shopContext~=nil then self:creditAccount(data.accounts[1],price,self:getFarmId()) end
    local contract={id=data.nextLeaseId,label="Fahrzeugleasing",vehicleId=vehicle.id,vehicleName=vehicle.name,vehicleConfigFile=vehicle.configFile,price=price,downPayment=down,monthlyRate=rate,residual=residual,monthsTotal=self.leaseMonths,monthsLeft=self.leaseMonths,status="active",paymentAccountId=paymentAccount.id,paymentAccountName=paymentAccount.name}
    table.insert(data.leases,contract)
    data.nextLeaseId=data.nextLeaseId+1; self.selectedLeaseRow=#data.leases; self:addTransaction(data,"Leasingstart",paymentAccount.name,"Leasing",-down)
    self.leaseFormOpen=false; self.activeTextField=nil; self.textBuffer=""
    self:saveState()
    if shopContext~=nil then self.pendingVehicleContractBinding={kind="lease",contract=contract}; self:finishShopContractPurchase() end
end

function VillageBank:processLeasingMonth(data,farmId)
    self:ensureLeasingData(data)
    for _,lease in ipairs(data.leases) do
        if lease.status=="active" then self:processDunningMonth(data,lease,"lease",farmId) end
    end
end

function VillageBank:buySelectedLease()
    local data=self:getFarmData(); local lease=data.leases[self.selectedLeaseRow]
    local paymentAccount=lease~=nil and self:getContractAccount(data,lease.paymentAccountId) or nil
    if lease==nil or lease.status~="purchaseOption" or paymentAccount==nil or not self:debitAccount(paymentAccount,lease.residual,self:getFarmId()) then return end
    lease.status="purchased"; self:addTransaction(data,"Leasingkauf",paymentAccount.name,"Fahrzeugeigentum",-(lease.residual or 0))
    self:saveState()
end

function VillageBank:getVisibleLeases(data)
    local visible={}
    for index,lease in ipairs(data.leases or {}) do if lease.status~="purchased" and lease.status~="returned" and lease.status~="repossessed" then table.insert(visible,{index=index,lease=lease}) end end
    return visible
end

function VillageBank:findVehicleForLease(lease)
    return self:findDunningVehicle(lease,self:getFarmId())
end

function VillageBank:returnSelectedLease()
    local data=self:getFarmData(); local lease=data.leases[self.selectedLeaseRow]
    if lease==nil or lease.status~="purchaseOption" then return end
    if self.pendingLeaseReturnId~=lease.id then self.pendingLeaseReturnId=lease.id; self:setStatus("Zur Bestätigung erneut auf 'Zurückgeben' klicken."); return end
    local vehicle=self:findVehicleForLease(lease)
    if vehicle==nil then self.pendingLeaseReturnId=nil; self:setStatus("Rückgabe nicht möglich: Fahrzeug konnte nicht eindeutig zugeordnet werden."); return end
    if g_currentMission~=nil and g_currentMission.controlledVehicle==vehicle then self.pendingLeaseReturnId=nil; self:setStatus("Bitte das Fahrzeug vor der Rückgabe verlassen."); return end
    self.pendingLeaseReturnId=nil
    lease.status="returned"
    self:addTransaction(data,"Leasingrückgabe",lease.vehicleName or "Fahrzeug","Dorfbank",0)
    self:saveState()
    lease.returnDeletionRequested=true
    vehicle:delete()
end


function VillageBank:getLeaseScrollOffset(data,visibleLeases)
    local entries=visibleLeases or self:getVisibleLeases(data)
    local count=#entries; local visible=self.LEASE_VISIBLE_ROWS or 6; local maxOffset=math.max(0,count-visible)
    self.leaseScrollOffset=math.max(0,math.min(self.leaseScrollOffset or 0,maxOffset))
    local selectedPosition=nil
    for pos,entry in ipairs(entries) do if entry.index==self.selectedLeaseRow then selectedPosition=pos; break end end
    if selectedPosition==nil and entries[1]~=nil then self.selectedLeaseRow=entries[1].index; selectedPosition=1 end
    if selectedPosition~=nil then
        if selectedPosition<self.leaseScrollOffset+1 then self.leaseScrollOffset=selectedPosition-1
        elseif selectedPosition>self.leaseScrollOffset+visible then self.leaseScrollOffset=math.min(maxOffset,selectedPosition-visible) end
    end
    if count==0 then self.selectedLeaseRow=0 end
    return self.leaseScrollOffset,maxOffset
end

function VillageBank:setLeaseScrollOffset(data,offset)
    local entries=self:getVisibleLeases(data); local count=#entries; local visible=self.LEASE_VISIBLE_ROWS or 6; local maxOffset=math.max(0,count-visible)
    self.leaseScrollOffset=math.max(0,math.min(math.floor((offset or 0)+0.5),maxOffset))
    if count>0 then
        local first=self.leaseScrollOffset+1; local last=math.min(count,first+visible-1); local selectedPosition=nil
        for pos,entry in ipairs(entries) do if entry.index==self.selectedLeaseRow then selectedPosition=pos; break end end
        if selectedPosition==nil or selectedPosition<first then self.selectedLeaseRow=entries[first].index
        elseif selectedPosition>last then self.selectedLeaseRow=entries[last].index end
    end
end

function VillageBank:scrollLeases(data,direction)
    local _,maxOffset=self:getLeaseScrollOffset(data)
    if maxOffset<=0 then return end
    self:setLeaseScrollOffset(data,(self.leaseScrollOffset or 0)+(direction or 0))
end

function VillageBank:drawLeaseScrollbar(data,entries)
    local count=#(entries or self:getVisibleLeases(data)); local visible=self.LEASE_VISIBLE_ROWS or 6
    if count<=visible then return end
    local offset,maxOffset=self:getLeaseScrollOffset(data,entries)
    local trackX,trackY,trackW,trackH=0.895,0.231,0.002,0.375
    self:drawPanel(trackX,trackY,trackW,trackH,0.33,0.35,0.35,1)
    local thumbH=math.max(0.050,trackH*math.min(1,visible/count)); local travel=trackH-thumbH; local ratio=maxOffset>0 and (offset/maxOffset) or 0
    local thumbY=trackY+travel*(1-ratio); self:drawPanel(trackX-0.002,thumbY,trackW+0.004,thumbH,0.60,0.77,0.22,1)
end

function VillageBank:drawLeases(data,x,y)
    self:ensureLeasingData(data); lText(x,y,0.019,"FAHRZEUGLEASING",0.88,0.90,0.89,1); lText(x+0.48,y,0.013,"24–60 MONATE · KAUFOPTION ZUM RESTWERT",0.62,0.66,0.64,1); y=y-0.048
    local visible=self:getVisibleLeases(data); if #visible==0 then lText(x,y,0.017,"Keine laufenden Leasingverträge.",0.68,0.72,0.69,1) end
    local offset=self:getLeaseScrollOffset(data,visible); local rows=self.LEASE_VISIBLE_ROWS or 6
    for row=1,rows do local entry=visible[offset+row]; if entry==nil then break end; local i,lease=entry.index,entry.lease; if i==self.selectedLeaseRow then self:drawPanel(x-0.006,y-0.016,0.74,0.055,0.20,0.40,0.015,1) elseif row%2==0 then self:drawPanel(x-0.006,y-0.016,0.74,0.055,0.025,0.029,0.032,1) end
        local state=lease.status=="repossessed" and "EINGEZOGEN" or (lease.arrearsCount or 0)>0 and ("MAHNUNG "..lease.arrearsCount.." · "..lease.monthsLeft.." Raten offen") or lease.status=="purchaseOption" and "KAUFOPTION ODER RÜCKGABE" or tostring(lease.monthsLeft).." Monate"
        lText(x,y+0.009,0.015,string.format("%s · %s",lease.vehicleName or "Nicht zugeordnet",state),1,1,1,1); lText(x,y-0.011,0.0115,"Rate "..lMoney(lease.monthlyRate).." · Kaufpreis am Ende "..lMoney(lease.residual).." · Zahlkonto "..tostring(lease.paymentAccountName or "Hofkonto"),0.72,0.76,0.72,1); y=y-0.064
    end
    self:drawLeaseScrollbar(data,visible)
    self:drawDunningDetails(data.leases[self.selectedLeaseRow],"lease")
    lText(0.145,0.131,0.014,"LEASINGOPTION ÜBER DEN HÄNDLER VERFÜGBAR",0.62,0.66,0.64,1); local selected=data.leases[self.selectedLeaseRow]; local paymentAccount=selected~=nil and self:getContractAccount(data,selected.paymentAccountId) or nil; local canFinish=selected~=nil and selected.status=="purchaseOption"; self:drawButton(0.645,self.ACTION_BUTTON_Y or 0.172,0.115,0.035,"Übernehmen",canFinish and paymentAccount~=nil and self:getAccountBalance(paymentAccount,self:getFarmId())>=selected.residual); self:drawButton(0.770,self.ACTION_BUTTON_Y or 0.172,0.115,0.035,"Zurückgeben",canFinish)
end

function VillageBank:drawLeaseForm()
    local x,y,w,h=0.295,0.23,0.41,0.48; self:drawDialogShell(x,y,w,h,"FAHRZEUGLEASING")
    local shopContext=self.shopContractContext~=nil and self.shopContractContext.kind=="lease" and self.shopContractContext or nil
    local price=shopContext~=nil and shopContext.price or tonumber(self.textBuffer) or 0; local down,residual,rate=self:calculateLease(price,self.leaseMonths)
    local approved,reason,liquidity,reserve,totalMonthly=self:checkContractLiquidity(price,down,rate,residual,self.leaseAccountIndex); if price<1000 then approved=false; reason="Fahrzeugpreis eingeben" end
    local vehicles=self:getContractVehicles(); local vehicle=shopContext~=nil and shopContext.vehicle or vehicles[self.leaseVehicleIndex]; if vehicle==nil then approved=false; reason="Kein Fahrzeug ausgewählt" end
    local paymentAccount=self:getFarmData().accounts[self.leaseAccountIndex]
    lText(x+0.03,y+0.325,0.013,"FAHRZEUGPREIS",0.65,0.72,0.67,1); self:drawPanel(x+0.03,y+0.286,0.35,0.034,0.08,0.11,0.09,1); lText(x+0.045,y+0.295,0.016,self.textBuffer=="" and "Preis eingeben ..." or self.textBuffer.." €")
    lText(x+0.03,y+0.255,0.013,shopContext~=nil and "FAHRZEUG VOM HÄNDLER" or "FAHRZEUG",0.65,0.72,0.67,1); self:drawButton(x+0.03,y+0.215,0.04,0.034,"<",shopContext==nil and #vehicles>0); self:drawPanel(x+0.08,y+0.215,0.25,0.034,0.08,0.11,0.09,1); lText(x+0.095,y+0.224,0.013,vehicle~=nil and vehicle.name or "Kein Fahrzeug verfügbar"); self:drawButton(x+0.34,y+0.215,0.04,0.034,">",shopContext==nil and #vehicles>0)
    lText(x+0.03,y+0.180,0.013,"LAUFZEIT",0.65,0.72,0.67,1); self:drawButton(x+0.03,y+0.140,0.04,0.034,"<",true); self:drawPanel(x+0.08,y+0.140,0.10,0.034,0.08,0.11,0.09,1); lText(x+0.09,y+0.149,0.013,tostring(self.leaseMonths).." Monate"); self:drawButton(x+0.19,y+0.140,0.04,0.034,">",true)
    lText(x+0.255,y+0.180,0.013,"ZAHLKONTO",0.65,0.72,0.67,1); self:drawButton(x+0.255,y+0.140,0.125,0.034,paymentAccount~=nil and paymentAccount.name or "-",true)
    lText(x+0.03,y+0.108,0.0125,"Sonderzahlung "..lMoney(down).."  ·  Rate "..lMoney(rate).."/Monat",0.94,0.78,0.25,1); lText(x+0.03,y+0.083,0.0125,"Kaufoption nach Laufzeit: "..lMoney(residual),0.80,0.84,0.80,1)
    lText(x+0.03,y+0.058,0.0115,(approved and "GENEHMIGT · " or "ABGELEHNT · ")..reason,approved and 0.48 or 0.95,approved and 0.90 or 0.38,approved and 0.58 or 0.32,1)
    lText(x+0.03,y+0.038,0.0105,"Liquidität "..lMoney(liquidity).." · Reserve "..lMoney(reserve).." · Monatslast "..lMoney(totalMonthly),0.62,0.68,0.64,1)
    self:drawButton(x+0.03,y+0.006,0.12,0.028,"Abbrechen",true); self:drawButton(x+0.23,y+0.006,0.15,0.028,"Leasing starten",approved)
end

function VillageBank:handleLeasingMouse(px,py)
    if self.leaseFormOpen then local x,y=0.295,0.23
        if self:isInside(px,py,x+0.03,y+0.286,0.35,0.034) then self.activeTextField="leaseAmount"
        elseif self.shopContractContext==nil and self:isInside(px,py,x+0.03,y+0.215,0.04,0.034) then self:cycleLeaseVehicle(-1)
        elseif self.shopContractContext==nil and self:isInside(px,py,x+0.34,y+0.215,0.04,0.034) then self:cycleLeaseVehicle(1)
        elseif self:isInside(px,py,x+0.03,y+0.140,0.04,0.034) then self:cycleLeaseMonths(-1)
        elseif self:isInside(px,py,x+0.19,y+0.140,0.04,0.034) then self:cycleLeaseMonths(1)
        elseif self:isInside(px,py,x+0.255,y+0.140,0.125,0.034) then self:cycleLeaseAccount()
        elseif self:isInside(px,py,x+0.03,y+0.006,0.12,0.028) then if self.shopContractContext~=nil then self:cancelShopContract() else self.leaseFormOpen=false; self.activeTextField=nil end
        elseif self:isInside(px,py,x+0.23,y+0.006,0.15,0.028) then self:createVehicleLease() end; return true end
    if self.selectedTab~=4 then return false end
    local data=self:getFarmData(); self:getLeaseScrollOffset(data); if self:handleDunningMouse(px,py,data.leases[self.selectedLeaseRow],"lease") then return true end; local visible=self:getVisibleLeases(data); local offset,maxOffset=self:getLeaseScrollOffset(data,visible); local rows=self.LEASE_VISIBLE_ROWS or 6
    for row=1,rows do local entry=visible[offset+row]; if entry==nil then break end; local rowY=0.567-(row-1)*0.064; if self:isInside(px,py,0.135,rowY-0.018,0.74,0.057) then self.selectedLeaseRow=entry.index; self.pendingLeaseReturnId=nil; return true end end
    if maxOffset>0 and self:isInside(px,py,0.888,0.231,0.016,0.375) then local ratio=math.max(0,math.min(1,(0.606-py)/0.375)); self:setLeaseScrollOffset(data,ratio*maxOffset); self.pendingLeaseReturnId=nil; return true end
    if self:isInside(px,py,0.645,self.ACTION_BUTTON_Y or 0.172,0.115,0.035) then self:buySelectedLease(); return true end
    if self:isInside(px,py,0.770,self.ACTION_BUTTON_Y or 0.172,0.115,0.035) then self:returnSelectedLease(); return true end; return false
end

function VillageBank:saveLeasingState(xml,key,data)
    self:ensureLeasingData(data); setXMLInt(xml,key.."#nextLeaseId",data.nextLeaseId)
    for i,v in ipairs(data.leases) do local l=string.format("%s.leasingContracts.lease(%d)",key,i-1); setXMLInt(xml,l.."#id",v.id); setXMLString(xml,l.."#label",v.label); setXMLString(xml,l.."#vehicleId",v.vehicleId or ""); setXMLString(xml,l.."#vehicleName",v.vehicleName or "Nicht zugeordnet"); setXMLFloat(xml,l.."#price",v.price); setXMLFloat(xml,l.."#downPayment",v.downPayment); setXMLFloat(xml,l.."#monthlyRate",v.monthlyRate); setXMLFloat(xml,l.."#residual",v.residual); setXMLInt(xml,l.."#monthsTotal",v.monthsTotal); setXMLInt(xml,l.."#monthsLeft",v.monthsLeft); setXMLInt(xml,l.."#paymentAccountId",v.paymentAccountId or 1); setXMLString(xml,l.."#paymentAccountName",v.paymentAccountName or "Hofkonto"); setXMLInt(xml,l.."#arrearsCount",v.arrearsCount or 0); setXMLString(xml,l.."#status",v.status or "active"); setXMLString(xml,l.."#vehicleConfigFile",v.vehicleConfigFile or "") end
end
function VillageBank:loadLeasingState(xml,key,data)
    data.leases={}; data.nextLeaseId=getXMLInt(xml,key.."#nextLeaseId") or 1; local i=0
    while hasXMLProperty(xml,string.format("%s.leasingContracts.lease(%d)",key,i)) do local l=string.format("%s.leasingContracts.lease(%d)",key,i); table.insert(data.leases,{id=getXMLInt(xml,l.."#id") or i+1,label=getXMLString(xml,l.."#label") or "Fahrzeugleasing",vehicleId=getXMLString(xml,l.."#vehicleId") or "",vehicleName=getXMLString(xml,l.."#vehicleName") or "Nicht zugeordnet",price=getXMLFloat(xml,l.."#price") or 0,downPayment=getXMLFloat(xml,l.."#downPayment") or 0,monthlyRate=getXMLFloat(xml,l.."#monthlyRate") or 0,residual=getXMLFloat(xml,l.."#residual") or 0,monthsTotal=getXMLInt(xml,l.."#monthsTotal") or 36,monthsLeft=getXMLInt(xml,l.."#monthsLeft") or 0,paymentAccountId=getXMLInt(xml,l.."#paymentAccountId") or 1,paymentAccountName=getXMLString(xml,l.."#paymentAccountName") or "Hofkonto",arrearsCount=getXMLInt(xml,l.."#arrearsCount") or 0,vehicleConfigFile=getXMLString(xml,l.."#vehicleConfigFile") or "",status=getXMLString(xml,l.."#status") or "active"}); i=i+1 end
    if #data.leases==0 then
        i=0; while hasXMLProperty(xml,string.format("%s.leases.lease(%d)",key,i)) do local l=string.format("%s.leases.lease(%d)",key,i); local left=getXMLInt(xml,l.."#monthsLeft") or 0; local main=data.accounts[1]; table.insert(data.leases,{id=i+1,label=getXMLString(xml,l.."#label") or "Übernommenes Leasing",vehicleId="",vehicleName="Nicht zugeordnet",price=getXMLFloat(xml,l.."#price") or 0,downPayment=0,monthlyRate=getXMLFloat(xml,l.."#monthlyRate") or 0,residual=getXMLFloat(xml,l.."#residual") or 0,monthsTotal=math.max(1,left),monthsLeft=left,status=left>0 and "active" or "purchaseOption",paymentAccountId=main~=nil and main.id or 1,paymentAccountName=main~=nil and main.name or "Hofkonto"}); i=i+1 end; data.nextLeaseId=#data.leases+1
    end
end
if g_villageBank~=nil then g_villageBank:initLeasingModule() end
