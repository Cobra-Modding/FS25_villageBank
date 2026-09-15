-- ============================================================
-- FS25_VillageBankFinancing.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

VillageBank.FINANCE_TERMS={12,24,36,48,60,72,84,96}
VillageBank.FINANCE_DOWNPAYMENTS={10,20,30}
VillageBank.FINANCE_BALLOONS={10,20,30}
VillageBank.FINANCE_RATE=0.055
VillageBank.FINANCE_VISIBLE_ROWS=6

local function fText(x,y,s,t,r,g,b,a) setTextColor(r or 1,g or 1,b or 1,a or 1); setTextAlignment(RenderText.ALIGN_LEFT); renderText(x,y,s,t) end
local function fMoney(v) return g_i18n:formatMoney(v or 0,0,true,true) end
local function cycle(values,current,direction)
    local index=1; for i,v in ipairs(values) do if v==current then index=i break end end
    return values[((index-1+direction)%#values)+1]
end

function VillageBank:initFinancingModule() self.financeFormOpen=false; self.financeMonths=60; self.financeDownPercent=20; self.financeBalloonPercent=20; self.financeAccountIndex=1; self.financeVehicleIndex=1; self.selectedFinanceRow=1; self.financeScrollOffset=0 end
function VillageBank:ensureFinancingData(data)
    data.loans=data.loans or {}
    data.nextFinanceId=data.nextFinanceId or 1
    for index=#data.loans,1,-1 do
        if (data.loans[index].monthsLeft or 0)<=0 and data.loans[index].status~="repossessed" then table.remove(data.loans,index) end
    end
end

function VillageBank:getAvailableLiquidity(data,farmId)
    local liquidity=0
    for _,account in ipairs(data.accounts or {}) do liquidity=liquidity+self:getAccountBalance(account,farmId) end
    return math.max(0,liquidity)
end

function VillageBank:getMonthlyDebtService(data)
    local monthly=0
    for _,loan in ipairs(data.loans or {}) do if (loan.monthsLeft or 0)>0 then monthly=monthly+(loan.monthlyRate or 0) end end
    for _,lease in ipairs(data.leases or {}) do if lease.status=="active" and (lease.monthsLeft or 0)>0 then monthly=monthly+(lease.monthlyRate or 0) end end
    return monthly
end

function VillageBank:checkContractLiquidity(price,upfront,newMonthly,finalPayment,accountIndex)
    local data=self:getFarmData(); local farmId=self:getFarmId(); local liquidity=self:getAvailableLiquidity(data,farmId)
    local paymentAccount=data.accounts[accountIndex or 1]; local accountBalance=self:getAccountBalance(paymentAccount,farmId)
    local totalMonthly=self:getMonthlyDebtService(data)+(newMonthly or 0)
    local reserve=math.max(price*0.05,(finalPayment or 0)*0.10,totalMonthly*3)
    if paymentAccount==nil then return false,"Kein gültiges Zahlkonto gewählt",liquidity,reserve,totalMonthly end
    if accountBalance<upfront then return false,"Zahlkonto deckt die Sofortzahlung nicht",liquidity,reserve,totalMonthly end
    if liquidity<upfront+reserve then return false,"Liquiditätsreserve nach Sofortzahlung zu gering",liquidity,reserve,totalMonthly end
    return true,"Liquidität und Ratenreserve ausreichend",liquidity,reserve,totalMonthly
end

function VillageBank:getContractVehicles()
    local result={}; local seen={}; local source=g_currentMission~=nil and ((g_currentMission.vehicleSystem~=nil and g_currentMission.vehicleSystem.vehicles) or g_currentMission.vehicles) or {}
    for _,vehicle in ipairs(source or {}) do
        local owner=vehicle.getOwnerFarmId~=nil and vehicle:getOwnerFarmId() or vehicle.ownerFarmId
        local visible=vehicle.getShowInVehiclesOverview==nil or vehicle:getShowInVehiclesOverview()
        if owner==self:getFarmId() and visible then
            local id=vehicle.uniqueId
            if vehicle.getUniqueId~=nil then local ok,value=pcall(vehicle.getUniqueId,vehicle); if ok and value~=nil then id=value end end
            id=tostring(id or vehicle.configFileName or vehicle.rootNode)
            if not seen[id] then
                local name=vehicle.getName~=nil and vehicle:getName() or vehicle.configFileNameClean or "Fahrzeug"
                table.insert(result,{id=id,name=name}); seen[id]=true
            end
        end
    end
    return result
end
function VillageBank:openFinanceForm() self.financeFormOpen=true; self.financeMonths=60; self.financeDownPercent=20; self.financeBalloonPercent=20; self.financeAccountIndex=1; self.financeVehicleIndex=1; self.activeTextField="financeAmount"; self.textBuffer="" end
function VillageBank:cycleFinanceAccount() local count=#self:getFarmData().accounts; if count>0 then self.financeAccountIndex=self.financeAccountIndex%count+1 end end
function VillageBank:cycleFinanceVehicle(direction) local vehicles=self:getContractVehicles(); if #vehicles>0 then self.financeVehicleIndex=((self.financeVehicleIndex-1+direction)%#vehicles)+1 end end
function VillageBank:getContractAccount(data,accountId) for _,account in ipairs(data.accounts or {}) do if account.id==accountId then return account end end return nil end

function VillageBank:calculateFinance(price,months,downPercent,balloonPercent)
    local down=price*downPercent/100; local balloon=price*balloonPercent/100; local financed=price-down
    local monthlyRate=self.FINANCE_RATE/12
    local principalForRates=math.max(0,financed-balloon/(1+monthlyRate)^months)
    local payment=principalForRates*monthlyRate/(1-(1+monthlyRate)^(-months))
    return down,balloon,payment,financed
end

function VillageBank:createVehicleFinance()
    local shopContext=self.shopContractContext~=nil and self.shopContractContext.kind=="finance" and self.shopContractContext or nil
    if shopContext==nil then self:setStatus("Finanzierung bitte über den Fahrzeughändler abschließen."); return end
    local price=shopContext.price; if price<1000 then return end
    local data=self:getFarmData(); self:ensureFinancingData(data)
    local vehicle=shopContext~=nil and shopContext.vehicle or self:getContractVehicles()[self.financeVehicleIndex]; if vehicle==nil then self:setStatus("Finanzierung abgelehnt: Kein Fahrzeug ausgewählt."); return end
    local down,balloon,payment,financed=self:calculateFinance(price,self.financeMonths,self.financeDownPercent,self.financeBalloonPercent)
    local approved,reason=self:checkContractLiquidity(price,down,payment,balloon,self.financeAccountIndex)
    if not approved then self:setStatus("Finanzierung abgelehnt: "..reason); return end
    local paymentAccount=data.accounts[self.financeAccountIndex]; self:debitAccount(paymentAccount,down,self:getFarmId())
    self:creditAccount(data.accounts[1],price,self:getFarmId())
    local contract={id=data.nextFinanceId,label="Fahrzeugfinanzierung",vehicleId=vehicle.id,vehicleName=vehicle.name,vehicleConfigFile=vehicle.configFile,price=price,annualRate=self.FINANCE_RATE,downPayment=down,balloon=balloon,monthlyRate=payment,monthsTotal=self.financeMonths,monthsLeft=self.financeMonths,outstanding=financed,paymentAccountId=paymentAccount.id,paymentAccountName=paymentAccount.name}
    table.insert(data.loans,contract)
    data.nextFinanceId=data.nextFinanceId+1; self.selectedFinanceRow=#self:getVisibleFinanceData(data).loans
    self:addTransaction(data,"Finanzierungssumme","Dorfbank","Händler",financed); self:addTransaction(data,"Anzahlung",paymentAccount.name,"Finanzierung",-down)
    self.financeFormOpen=false; self.activeTextField=nil; self.textBuffer=""
    self:saveState()
    if shopContext~=nil then self.pendingVehicleContractBinding={kind="finance",contract=contract}; self:finishShopContractPurchase() end
end

function VillageBank:processFinancingMonth(data,farmId)
    self:ensureFinancingData(data)
    for index=#data.loans,1,-1 do self:processDunningMonth(data,data.loans[index],"finance",farmId) end
    self:ensureFinancingData(data)
    self.selectedFinanceRow=math.min(self.selectedFinanceRow or 1,math.max(1,#data.loans))
end

function VillageBank:getVisibleFinanceData(data)
    local view={loans={}}
    for _,loan in ipairs(data.loans or {}) do
        if loan.status~="repossessed" and (loan.monthsLeft or 0)>0 then table.insert(view.loans,loan) end
    end
    return view
end

function VillageBank:getFinanceScrollOffset(data)
    data=self:getVisibleFinanceData(data)
    self:ensureFinancingData(data)
    local count=#data.loans
    local visible=self.FINANCE_VISIBLE_ROWS or 6
    local maxOffset=math.max(0,count-visible)
    self.financeScrollOffset=math.max(0,math.min(self.financeScrollOffset or 0,maxOffset))
    if count>0 then
        self.selectedFinanceRow=math.max(1,math.min(self.selectedFinanceRow or 1,count))
        if self.selectedFinanceRow<self.financeScrollOffset+1 then self.financeScrollOffset=self.selectedFinanceRow-1
        elseif self.selectedFinanceRow>self.financeScrollOffset+visible then self.financeScrollOffset=math.min(maxOffset,self.selectedFinanceRow-visible) end
    end
    if count==0 then self.selectedFinanceRow=0 end
    return self.financeScrollOffset,maxOffset
end

function VillageBank:setFinanceScrollOffset(data,offset)
    data=self:getVisibleFinanceData(data)
    local count=#(data.loans or {})
    local visible=self.FINANCE_VISIBLE_ROWS or 6
    local maxOffset=math.max(0,count-visible)
    self.financeScrollOffset=math.max(0,math.min(math.floor((offset or 0)+0.5),maxOffset))
    if count>0 then
        local first=self.financeScrollOffset+1; local last=math.min(count,first+visible-1)
        if (self.selectedFinanceRow or 1)<first then self.selectedFinanceRow=first end
        if (self.selectedFinanceRow or 1)>last then self.selectedFinanceRow=last end
    end
end

function VillageBank:scrollFinancing(data,direction)
    local _,maxOffset=self:getFinanceScrollOffset(data)
    if maxOffset<=0 then return end
    self:setFinanceScrollOffset(data,(self.financeScrollOffset or 0)+(direction or 0))
end

function VillageBank:drawFinanceScrollbar(data)
    data=self:getVisibleFinanceData(data)
    local count=#(data.loans or {})
    local visible=self.FINANCE_VISIBLE_ROWS or 6
    if count<=visible then return end
    local offset,maxOffset=self:getFinanceScrollOffset(data)
    local trackX,trackY,trackW,trackH=0.895,0.231,0.002,0.375
    self:drawPanel(trackX,trackY,trackW,trackH,0.33,0.35,0.35,1)
    local thumbH=math.max(0.050,trackH*math.min(1,visible/count))
    local travel=trackH-thumbH; local ratio=maxOffset>0 and (offset/maxOffset) or 0
    local thumbY=trackY+travel*(1-ratio)
    self:drawPanel(trackX-0.002,thumbY,trackW+0.004,thumbH,0.60,0.77,0.22,1)
end

function VillageBank:drawLoans(data,x,y)
    data=self:getVisibleFinanceData(data)
    self:ensureFinancingData(data); fText(x,y,0.019,"FAHRZEUGFINANZIERUNGEN",0.88,0.90,0.89,1); fText(x+0.50,y,0.013,"12–96 MONATE · 5,5% SOLLZINS",0.62,0.66,0.64,1); y=y-0.048
    if #data.loans==0 then fText(x,y,0.017,"Keine laufende Fahrzeugfinanzierung.",0.68,0.72,0.69,1) end
    local offset=self:getFinanceScrollOffset(data); local visible=self.FINANCE_VISIBLE_ROWS or 6
    for row=1,visible do local i=offset+row; local loan=data.loans[i]; if loan==nil then break end; local selected=i==self.selectedFinanceRow; if selected then self:drawPanel(x-0.006,y-0.016,0.74,0.055,0.20,0.40,0.015,1) elseif row%2==0 then self:drawPanel(x-0.006,y-0.016,0.74,0.055,0.025,0.029,0.032,1) end
        fText(x,y+0.009,0.015,string.format("%s · %d/%d Monate",(loan.vehicleName or ("Vertrag "..tostring(loan.id)))..(loan.status=="repossessed" and " [EINGEZOGEN]" or ((loan.arrearsCount or 0)>0 and " [MAHNUNG "..loan.arrearsCount.."]" or "")),loan.monthsLeft,loan.monthsTotal),1,1,1,1)
        fText(x,y-0.011,0.0115,"Rate "..fMoney(loan.monthlyRate).." · Schlussrate "..fMoney(loan.balloon).." · Zahlkonto "..tostring(loan.paymentAccountName or "Hofkonto"),0.72,0.76,0.72,1); fText(x+0.63,y+0.005,0.015,fMoney(loan.outstanding),0.32,0.55,0.04,1); y=y-0.064
    end
    self:drawFinanceScrollbar(data)
    self:drawDunningDetails(data.loans[self.selectedFinanceRow],"finance")
end

function VillageBank:drawFinanceForm()
    local x,y,w,h=0.295,0.20,0.41,0.52; self:drawDialogShell(x,y,w,h,"FAHRZEUGFINANZIERUNG")
    local shopContext=self.shopContractContext~=nil and self.shopContractContext.kind=="finance" and self.shopContractContext or nil
    local price=shopContext~=nil and shopContext.price or tonumber(self.textBuffer) or 0; local down,balloon,payment=self:calculateFinance(price,self.financeMonths,self.financeDownPercent,self.financeBalloonPercent)
    local approved,reason,liquidity,reserve,totalMonthly=self:checkContractLiquidity(price,down,payment,balloon,self.financeAccountIndex); if price<1000 then approved=false; reason="Fahrzeugpreis eingeben" end
    local paymentAccount=self:getFarmData().accounts[self.financeAccountIndex]
    local vehicles=self:getContractVehicles(); local vehicle=shopContext~=nil and shopContext.vehicle or vehicles[self.financeVehicleIndex]; if vehicle==nil then approved=false; reason="Kein Fahrzeug verfügbar" end
    fText(x+0.03,y+0.385,0.013,"FAHRZEUGPREIS",0.65,0.72,0.67,1); self:drawPanel(x+0.03,y+0.347,0.35,0.034,0.08,0.11,0.09,1); fText(x+0.045,y+0.356,0.016,self.textBuffer=="" and "Preis eingeben ..." or self.textBuffer.." €")
    fText(x+0.03,y+0.315,0.013,shopContext~=nil and "FAHRZEUG VOM HÄNDLER" or "FAHRZEUG",0.65,0.72,0.67,1); self:drawButton(x+0.03,y+0.277,0.04,0.034,"<",shopContext==nil and #vehicles>0); self:drawPanel(x+0.08,y+0.277,0.22,0.034,0.08,0.11,0.09,1); fText(x+0.095,y+0.286,0.014,vehicle~=nil and vehicle.name or "Kein Fahrzeug"); self:drawButton(x+0.31,y+0.277,0.04,0.034,">",shopContext==nil and #vehicles>0)
    fText(x+0.03,y+0.245,0.013,"LAUFZEIT",0.65,0.72,0.67,1); self:drawButton(x+0.03,y+0.207,0.04,0.034,"<",true); self:drawPanel(x+0.08,y+0.207,0.22,0.034,0.08,0.11,0.09,1); fText(x+0.105,y+0.216,0.015,tostring(self.financeMonths).." Monate"); self:drawButton(x+0.31,y+0.207,0.04,0.034,">",true)
    fText(x+0.03,y+0.17,0.013,"ANZAHLUNG",0.65,0.72,0.67,1); self:drawButton(x+0.03,y+0.132,0.10,0.034,tostring(self.financeDownPercent).."%",true)
    fText(x+0.16,y+0.17,0.013,"SCHLUSSRATE",0.65,0.72,0.67,1); self:drawButton(x+0.16,y+0.132,0.10,0.034,tostring(self.financeBalloonPercent).."%",true)
    fText(x+0.28,y+0.17,0.013,"ZAHLKONTO",0.65,0.72,0.67,1); self:drawButton(x+0.28,y+0.132,0.10,0.034,paymentAccount~=nil and paymentAccount.name or "-",true)
    fText(x+0.03,y+0.095,0.0125,"Anzahlung "..fMoney(down).."  ·  Rate "..fMoney(payment).."/Monat  ·  Schluss "..fMoney(balloon),0.94,0.78,0.25,1)
    fText(x+0.03,y+0.071,0.0115,(approved and "GENEHMIGT · " or "ABGELEHNT · ")..reason,approved and 0.48 or 0.95,approved and 0.90 or 0.38,approved and 0.58 or 0.32,1)
    fText(x+0.03,y+0.052,0.0105,"Liquidität "..fMoney(liquidity).." · Reserve "..fMoney(reserve).." · Monatslast "..fMoney(totalMonthly),0.62,0.68,0.64,1)
    self:drawButton(x+0.03,y+0.012,0.12,0.03,"Abbrechen",true); self:drawButton(x+0.23,y+0.012,0.15,0.03,"Vertrag abschließen",approved)
end

function VillageBank:handleFinancingMouse(px,py)
    if self.financeFormOpen then local x,y=0.295,0.20
        if self:isInside(px,py,x+0.03,y+0.347,0.35,0.034) then self.activeTextField="financeAmount"
        elseif self.shopContractContext==nil and self:isInside(px,py,x+0.03,y+0.277,0.04,0.034) then self:cycleFinanceVehicle(-1)
        elseif self.shopContractContext==nil and self:isInside(px,py,x+0.31,y+0.277,0.04,0.034) then self:cycleFinanceVehicle(1)
        elseif self:isInside(px,py,x+0.03,y+0.207,0.04,0.034) then self.financeMonths=cycle(self.FINANCE_TERMS,self.financeMonths,-1)
        elseif self:isInside(px,py,x+0.31,y+0.207,0.04,0.034) then self.financeMonths=cycle(self.FINANCE_TERMS,self.financeMonths,1)
        elseif self:isInside(px,py,x+0.03,y+0.132,0.10,0.034) then self.financeDownPercent=cycle(self.FINANCE_DOWNPAYMENTS,self.financeDownPercent,1)
        elseif self:isInside(px,py,x+0.16,y+0.132,0.10,0.034) then self.financeBalloonPercent=cycle(self.FINANCE_BALLOONS,self.financeBalloonPercent,1)
        elseif self:isInside(px,py,x+0.28,y+0.132,0.10,0.034) then self:cycleFinanceAccount()
        elseif self:isInside(px,py,x+0.03,y+0.012,0.12,0.03) then if self.shopContractContext~=nil then self:cancelShopContract() else self.financeFormOpen=false; self.activeTextField=nil end
        elseif self:isInside(px,py,x+0.23,y+0.012,0.15,0.03) then self:createVehicleFinance() end; return true end
    if self.selectedTab~=3 then return false end
    local data=self:getVisibleFinanceData(self:getFarmData()); self:getFinanceScrollOffset(data); if self:handleDunningMouse(px,py,data.loans[self.selectedFinanceRow],"finance") then return true end; local offset,maxOffset=self:getFinanceScrollOffset(data); local visible=self.FINANCE_VISIBLE_ROWS or 6
    for row=1,visible do local i=offset+row; if i>#data.loans then break end; local rowY=0.567-(row-1)*0.064; if self:isInside(px,py,0.135,rowY-0.018,0.74,0.057) then self.selectedFinanceRow=i; return true end end
    if maxOffset>0 and self:isInside(px,py,0.888,0.231,0.016,0.375) then local ratio=math.max(0,math.min(1,(0.606-py)/0.375)); self:setFinanceScrollOffset(data,ratio*maxOffset); return true end
    return false
end

function VillageBank:saveFinancingState(xml,key,data)
    self:ensureFinancingData(data); setXMLInt(xml,key.."#nextFinanceId",data.nextFinanceId)
    for i,v in ipairs(data.loans) do local l=string.format("%s.financings.finance(%d)",key,i-1); setXMLInt(xml,l.."#id",v.id); setXMLString(xml,l.."#label",v.label); setXMLString(xml,l.."#vehicleId",v.vehicleId or ""); setXMLString(xml,l.."#vehicleName",v.vehicleName or "Nicht zugeordnet"); setXMLFloat(xml,l.."#price",v.price); setXMLFloat(xml,l.."#annualRate",v.annualRate); setXMLFloat(xml,l.."#downPayment",v.downPayment); setXMLFloat(xml,l.."#balloon",v.balloon); setXMLFloat(xml,l.."#monthlyRate",v.monthlyRate); setXMLInt(xml,l.."#monthsTotal",v.monthsTotal); setXMLInt(xml,l.."#monthsLeft",v.monthsLeft); setXMLFloat(xml,l.."#outstanding",v.outstanding); setXMLInt(xml,l.."#paymentAccountId",v.paymentAccountId or 1); setXMLString(xml,l.."#paymentAccountName",v.paymentAccountName or "Hofkonto"); setXMLInt(xml,l.."#arrearsCount",v.arrearsCount or 0); setXMLString(xml,l.."#status",v.status or "active"); setXMLString(xml,l.."#vehicleConfigFile",v.vehicleConfigFile or "") end
end
function VillageBank:loadFinancingState(xml,key,data)
    data.loans={}; data.nextFinanceId=getXMLInt(xml,key.."#nextFinanceId") or 1; local i=0
    while hasXMLProperty(xml,string.format("%s.financings.finance(%d)",key,i)) do local l=string.format("%s.financings.finance(%d)",key,i); table.insert(data.loans,{id=getXMLInt(xml,l.."#id") or i+1,label=getXMLString(xml,l.."#label") or "Fahrzeugfinanzierung",vehicleId=getXMLString(xml,l.."#vehicleId") or "",vehicleName=getXMLString(xml,l.."#vehicleName") or "Nicht zugeordnet",price=getXMLFloat(xml,l.."#price") or 0,annualRate=getXMLFloat(xml,l.."#annualRate") or self.FINANCE_RATE,downPayment=getXMLFloat(xml,l.."#downPayment") or 0,balloon=getXMLFloat(xml,l.."#balloon") or 0,monthlyRate=getXMLFloat(xml,l.."#monthlyRate") or 0,monthsTotal=getXMLInt(xml,l.."#monthsTotal") or 60,monthsLeft=getXMLInt(xml,l.."#monthsLeft") or 60,outstanding=getXMLFloat(xml,l.."#outstanding") or 0,paymentAccountId=getXMLInt(xml,l.."#paymentAccountId") or 1,paymentAccountName=getXMLString(xml,l.."#paymentAccountName") or "Hofkonto",arrearsCount=getXMLInt(xml,l.."#arrearsCount") or 0,vehicleConfigFile=getXMLString(xml,l.."#vehicleConfigFile") or "",status=getXMLString(xml,l.."#status") or "active"}); i=i+1 end
    if #data.loans==0 then
        i=0; while hasXMLProperty(xml,string.format("%s.loans.loan(%d)",key,i)) do local l=string.format("%s.loans.loan(%d)",key,i); local outstanding=getXMLFloat(xml,l.."#outstanding") or 0; local years=getXMLInt(xml,l.."#years") or 5; local months=years*12; local main=data.accounts[1]; table.insert(data.loans,{id=i+1,label="Übernommene Finanzierung",vehicleId="",vehicleName="Nicht zugeordnet",price=outstanding,annualRate=getXMLFloat(xml,l.."#annualRate") or self.FINANCE_RATE,downPayment=0,balloon=0,monthlyRate=months>0 and outstanding/months or 0,monthsTotal=months,monthsLeft=months,outstanding=outstanding,paymentAccountId=main~=nil and main.id or 1,paymentAccountName=main~=nil and main.name or "Hofkonto"}); i=i+1 end; data.nextFinanceId=#data.loans+1
    end
end
if g_villageBank~=nil then g_villageBank:initFinancingModule() end
