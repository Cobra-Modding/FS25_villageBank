-- ============================================================
-- FS25_VillageBankSavings.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

VillageBank.SAVINGS_TERMS = {{years=1,rate=0.01},{years=5,rate=0.05},{years=10,rate=0.10}}
VillageBank.MAX_SAVINGS_DEPOSITS = 8
VillageBank.SAVINGS_VISIBLE_ROWS = 6

local function savingsText(x,y,size,value,r,g,b,a)
    setTextColor(r or 1,g or 1,b or 1,a or 1); setTextAlignment(RenderText.ALIGN_LEFT); renderText(x,y,size,value)
end
local function savingsMoney(value) return g_i18n:formatMoney(value or 0,0,true,true) end

function VillageBank:initSavingsModule()
    self.savingsTransferFormOpen=false; self.savingsSourceIndex=1; self.savingsTermYears=1; self.selectedSavingsRow=1; self.savingsScrollOffset=0
end

function VillageBank:getSavingsDaysPerYear()
    local environment=g_currentMission~=nil and g_currentMission.environment or nil
    local daysPerPeriod=environment~=nil and environment.daysPerPeriod or nil
    if daysPerPeriod==nil and g_currentMission~=nil and g_currentMission.missionInfo~=nil then daysPerPeriod=g_currentMission.missionInfo.plannedDaysPerPeriod end
    return math.max(12,(daysPerPeriod or 1)*12)
end

function VillageBank:getSavingsRate(years)
    for _,term in ipairs(self.SAVINGS_TERMS) do if term.years==years then return term.rate end end
    return 0.01
end

function VillageBank:updateSavingsTotal(data)
    local total=0
    for _,deposit in ipairs(data.savingsDeposits or {}) do total=total+(deposit.balance or 0) end
    data.savings=total
end

function VillageBank:ensureSavingsData(data)
    data.savingsDeposits=data.savingsDeposits or {}; data.savings=data.savings or 0; data.nextSavingsId=data.nextSavingsId or 1
end

function VillageBank:isSavingsMature(deposit)
    if deposit==nil then return false end
    local day=g_currentMission~=nil and g_currentMission.environment.currentDay or 0
    return day>=(deposit.maturityDay or 0)
end

function VillageBank:getSavingsRemainingDays(deposit)
    local day=g_currentMission~=nil and g_currentMission.environment.currentDay or 0
    return math.max(0,(deposit.maturityDay or 0)-day)
end

function VillageBank:openSavingsTransferForm()
    if #self:getFarmData().savingsDeposits>=self.MAX_SAVINGS_DEPOSITS then return end
    self.savingsSourceIndex=1; self.savingsTermYears=1; self.savingsTransferFormOpen=true; self.activeTextField="savingsAmount"; self.textBuffer=""
end

function VillageBank:cycleSavingsSource(direction)
    local count=#self:getFarmData().accounts
    if count>0 then self.savingsSourceIndex=((self.savingsSourceIndex-1+direction)%count)+1 end
end

function VillageBank:confirmSavingsTransferForm()
    local amount=math.floor(tonumber(self.textBuffer) or 0)
    local data=self:getFarmData(); self:ensureSavingsData(data)
    local source=data.accounts[self.savingsSourceIndex]
    if amount<=0 or source==nil then return end
    if not self:debitAccount(source,amount,self:getFarmId()) then self:setStatus("Kontostand nicht ausreichend."); return end
    local day=g_currentMission.environment.currentDay; local years=self.savingsTermYears
    table.insert(data.savingsDeposits,{id=data.nextSavingsId,balance=amount,principal=amount,years=years,annualRate=self:getSavingsRate(years),startDay=day,maturityDay=day+years*self:getSavingsDaysPerYear()})
    data.nextSavingsId=data.nextSavingsId+1; self.selectedSavingsRow=#data.savingsDeposits; self:updateSavingsTotal(data)
    self:addTransaction(data,"Festgeld",source.name,string.format("%d Jahr(e)",years),-amount)
    self.savingsTransferFormOpen=false; self.activeTextField=nil; self.textBuffer=""
    self:saveState()
end

function VillageBank:payoutSelectedSavings()
    local data=self:getFarmData(); local deposit=data.savingsDeposits[self.selectedSavingsRow]
    if not self:isSavingsMature(deposit) then return end
    self:creditAccount(data.accounts[1],deposit.balance,self:getFarmId())
    self:addTransaction(data,"Festgeld fällig","Anlage "..tostring(deposit.id),"Hofkonto",deposit.balance)
    table.remove(data.savingsDeposits,self.selectedSavingsRow)
    self.selectedSavingsRow=math.max(1,math.min(self.selectedSavingsRow,#data.savingsDeposits)); self:updateSavingsTotal(data)
    self:saveState()
end

function VillageBank:processSavingsDay(data,day)
    self:ensureSavingsData(data); local daysPerYear=self:getSavingsDaysPerYear()
    for _,deposit in ipairs(data.savingsDeposits) do
        if day<=deposit.maturityDay then
            local credit=deposit.balance*deposit.annualRate/daysPerYear
            deposit.balance=deposit.balance+credit; data.interestEarned=(data.interestEarned or 0)+credit
        end
    end
    self:updateSavingsTotal(data)
end


function VillageBank:getSavingsScrollOffset(data)
    self:ensureSavingsData(data)
    local count=#data.savingsDeposits
    local visible=self.SAVINGS_VISIBLE_ROWS or 6
    local maxOffset=math.max(0,count-visible)
    self.savingsScrollOffset=math.max(0,math.min(self.savingsScrollOffset or 0,maxOffset))
    if count>0 then
        self.selectedSavingsRow=math.max(1,math.min(self.selectedSavingsRow or 1,count))
        if self.selectedSavingsRow<self.savingsScrollOffset+1 then
            self.savingsScrollOffset=self.selectedSavingsRow-1
        elseif self.selectedSavingsRow>self.savingsScrollOffset+visible then
            self.savingsScrollOffset=math.min(maxOffset,self.selectedSavingsRow-visible)
        end
    end
    return self.savingsScrollOffset,maxOffset
end

function VillageBank:setSavingsScrollOffset(data,offset)
    local count=#(data.savingsDeposits or {})
    local visible=self.SAVINGS_VISIBLE_ROWS or 6
    local maxOffset=math.max(0,count-visible)
    self.savingsScrollOffset=math.max(0,math.min(math.floor((offset or 0)+0.5),maxOffset))
    if count>0 then
        local first=self.savingsScrollOffset+1
        local last=math.min(count,first+visible-1)
        if (self.selectedSavingsRow or 1)<first then self.selectedSavingsRow=first end
        if (self.selectedSavingsRow or 1)>last then self.selectedSavingsRow=last end
    end
end

function VillageBank:scrollSavings(data,direction)
    local _,maxOffset=self:getSavingsScrollOffset(data)
    if maxOffset<=0 then return end
    self:setSavingsScrollOffset(data,(self.savingsScrollOffset or 0)+(direction or 0))
end

function VillageBank:drawSavingsScrollbar(data)
    local count=#(data.savingsDeposits or {})
    local visible=self.SAVINGS_VISIBLE_ROWS or 6
    if count<=visible then return end
    local offset,maxOffset=self:getSavingsScrollOffset(data)
    local trackX,trackY,trackW,trackH=0.895,0.246,0.002,0.360
    self:drawPanel(trackX,trackY,trackW,trackH,0.33,0.35,0.35,1)
    local thumbH=math.max(0.050,trackH*math.min(1,visible/count))
    local travel=trackH-thumbH
    local ratio=maxOffset>0 and (offset/maxOffset) or 0
    local thumbY=trackY+travel*(1-ratio)
    self:drawPanel(trackX-0.002,thumbY,trackW+0.004,thumbH,0.60,0.77,0.22,1)
end

function VillageBank:drawSavings(data,x,y)
    self:ensureSavingsData(data)
    savingsText(x,y,0.019,"LANGZEITANLAGEN",0.88,0.90,0.89,1)
    savingsText(x+0.45,y,0.013,"1 JAHR 1%  ·  5 JAHRE 5%  ·  10 JAHRE 10%",0.62,0.66,0.64,1)
    y=y-0.048
    if #data.savingsDeposits==0 then savingsText(x,y,0.017,"Noch keine Festgeldanlage vorhanden.",0.68,0.72,0.69,1) end
    local offset=self:getSavingsScrollOffset(data)
    local visible=self.SAVINGS_VISIBLE_ROWS or 6
    for row=1,visible do
        local i=offset+row
        local deposit=data.savingsDeposits[i]
        if deposit==nil then break end
        local selected=i==self.selectedSavingsRow
        if selected then self:drawPanel(x-0.006,y-0.016,0.74,0.052,0.20,0.40,0.015,1) elseif row%2==0 then self:drawPanel(x-0.006,y-0.016,0.74,0.052,0.025,0.029,0.032,1) end
        local remaining=self:getSavingsRemainingDays(deposit); local state=remaining>0 and (tostring(remaining).." Tage verbleibend") or "FÄLLIG"
        savingsText(x,y+0.008,0.015,string.format("Anlage %02d  ·  %d Jahre  ·  %.0f%% p.a.",deposit.id,deposit.years,deposit.annualRate*100),0.95,0.95,0.95,1)
        savingsText(x,y-0.011,0.0115,string.format("Fälligkeit Tag %d  ·  %s",deposit.maturityDay,state),remaining>0 and 0.72 or 0.55,remaining>0 and 0.76 or 0.95,remaining>0 and 0.72 or 0.60,1)
        savingsText(x+0.63,y+0.004,0.016,savingsMoney(deposit.balance),0.32,0.55,0.04,1); y=y-0.061
    end
    self:drawSavingsScrollbar(data)
    self:drawButton(0.145,self.ACTION_BUTTON_Y or 0.172,0.165,0.035,"Neue Langzeitanlage",#data.accounts>0 and #data.savingsDeposits<self.MAX_SAVINGS_DEPOSITS)
    local selected=data.savingsDeposits[self.selectedSavingsRow]
    self:drawButton(0.320,self.ACTION_BUTTON_Y or 0.172,0.185,0.035,"Fällige Anlage auszahlen",self:isSavingsMature(selected))
    savingsText(0.665,0.131,0.015,"GESAMT: "..savingsMoney(data.savings),0.32,0.55,0.04,1)
end

function VillageBank:drawSavingsTransferForm(data)
    local x,y,w,h=0.28,0.285,0.44,0.40
    self:drawDialogShell(x,y,w,h,"NEUE LANGZEITANLAGE")
    local source=data.accounts[self.savingsSourceIndex]
    savingsText(x+0.03,y+0.255,0.014,"VON GIROKONTO",0.62,0.7,0.65,1)
    self:drawButton(x+0.03,y+0.208,0.04,0.04,"<",true); self:drawPanel(x+0.08,y+0.208,0.24,0.04,0.08,0.11,0.09,1)
    savingsText(x+0.095,y+0.220,0.015,source~=nil and source.name or "-"); self:drawButton(x+0.33,y+0.208,0.04,0.04,">",true)
    savingsText(x+0.03,y+0.17,0.014,"LAUFZEIT UND ZINSSATZ",0.62,0.7,0.65,1)
    for i,term in ipairs(self.SAVINGS_TERMS) do local bx=x+0.03+(i-1)*0.13; local years=term.years==1 and "1 Jahr" or (tostring(term.years).." Jahre"); self:drawButton(bx,y+0.123,0.12,0.038,string.format("%s - %.0f%%",years,term.rate*100),self.savingsTermYears==term.years) end
    savingsText(x+0.03,y+0.087,0.014,"ANLAGEBETRAG",0.72,0.76,0.74,1); self:drawPanel(x+0.03,y+0.048,0.34,0.034,0.08,0.09,0.09,1)
    savingsText(x+0.045,y+0.057,0.016,self.textBuffer=="" and "Betrag eingeben ..." or self.textBuffer.." €")
    self:drawButton(x+0.03,y+0.008,0.12,0.032,"Abbrechen",true); self:drawButton(x+0.22,y+0.008,0.15,0.032,"Fest anlegen",tonumber(self.textBuffer)~=nil and tonumber(self.textBuffer)>0)
end

function VillageBank:handleSavingsMouse(posX,posY)
    local data=self:getFarmData()
    if self.savingsTransferFormOpen then
        local x,y=0.28,0.285
        if self:isInside(posX,posY,x+0.03,y+0.208,0.04,0.04) then self:cycleSavingsSource(-1)
        elseif self:isInside(posX,posY,x+0.33,y+0.208,0.04,0.04) then self:cycleSavingsSource(1)
        elseif self:isInside(posX,posY,x+0.03,y+0.123,0.12,0.038) then self.savingsTermYears=1
        elseif self:isInside(posX,posY,x+0.16,y+0.123,0.12,0.038) then self.savingsTermYears=5
        elseif self:isInside(posX,posY,x+0.29,y+0.123,0.12,0.038) then self.savingsTermYears=10
        elseif self:isInside(posX,posY,x+0.03,y+0.048,0.34,0.034) then self.activeTextField="savingsAmount"
        elseif self:isInside(posX,posY,x+0.03,y+0.008,0.12,0.032) then self.savingsTransferFormOpen=false; self.activeTextField=nil
        elseif self:isInside(posX,posY,x+0.22,y+0.008,0.15,0.032) and tonumber(self.textBuffer)~=nil and tonumber(self.textBuffer)>0 then self:confirmSavingsTransferForm() end
        return true
    end
    if self.selectedTab~=2 then return false end
    local offset,maxOffset=self:getSavingsScrollOffset(data)
    local visible=self.SAVINGS_VISIBLE_ROWS or 6
    for row=1,visible do
        local i=offset+row
        if i>#data.savingsDeposits then break end
        local rowY=0.567-(row-1)*0.061
        if self:isInside(posX,posY,0.135,rowY-0.018,0.74,0.055) then self.selectedSavingsRow=i; return true end
    end
    if maxOffset>0 and self:isInside(posX,posY,0.888,0.246,0.016,0.360) then
        local ratio=math.max(0,math.min(1,(0.606-posY)/0.360))
        self:setSavingsScrollOffset(data,ratio*maxOffset); return true
    end
    if self:isInside(posX,posY,0.145,self.ACTION_BUTTON_Y or 0.172,0.165,0.035) then self:openSavingsTransferForm(); return true end
    if self:isInside(posX,posY,0.320,self.ACTION_BUTTON_Y or 0.172,0.185,0.035) then self:payoutSelectedSavings(); return true end
    return false
end

function VillageBank:saveSavingsState(xml,key,data)
    self:ensureSavingsData(data); self:updateSavingsTotal(data); setXMLFloat(xml,key.."#savings",data.savings); setXMLInt(xml,key.."#nextSavingsId",data.nextSavingsId)
    for i,deposit in ipairs(data.savingsDeposits) do
        local d=string.format("%s.savingsDeposits.deposit(%d)",key,i-1)
        setXMLInt(xml,d.."#id",deposit.id); setXMLFloat(xml,d.."#balance",deposit.balance); setXMLFloat(xml,d.."#principal",deposit.principal); setXMLInt(xml,d.."#years",deposit.years); setXMLFloat(xml,d.."#annualRate",deposit.annualRate); setXMLInt(xml,d.."#startDay",deposit.startDay); setXMLInt(xml,d.."#maturityDay",deposit.maturityDay)
    end
end

function VillageBank:loadSavingsState(xml,key,data)
    data.savingsDeposits={}; data.nextSavingsId=getXMLInt(xml,key.."#nextSavingsId") or 1; local i=0
    while hasXMLProperty(xml,string.format("%s.savingsDeposits.deposit(%d)",key,i)) do
        local d=string.format("%s.savingsDeposits.deposit(%d)",key,i)
        table.insert(data.savingsDeposits,{id=getXMLInt(xml,d.."#id") or i+1,balance=getXMLFloat(xml,d.."#balance") or 0,principal=getXMLFloat(xml,d.."#principal") or 0,years=getXMLInt(xml,d.."#years") or 1,annualRate=getXMLFloat(xml,d.."#annualRate") or 0.01,startDay=getXMLInt(xml,d.."#startDay") or 0,maturityDay=getXMLInt(xml,d.."#maturityDay") or 0}); i=i+1
    end
    local oldBalance=getXMLFloat(xml,key.."#savings") or 0
    if #data.savingsDeposits==0 and oldBalance>0 then
        local years=getXMLInt(xml,key.."#savingsTermYears") or 1; local day=g_currentMission.environment.currentDay; local maturity=getXMLInt(xml,key.."#savingsMaturityDay") or 0
        if maturity==0 then maturity=day+years*self:getSavingsDaysPerYear() end
        table.insert(data.savingsDeposits,{id=1,balance=oldBalance,principal=oldBalance,years=years,annualRate=self:getSavingsRate(years),startDay=getXMLInt(xml,key.."#savingsStartDay") or day,maturityDay=maturity}); data.nextSavingsId=2
    end
    self:updateSavingsTotal(data)
end

if g_villageBank~=nil then g_villageBank:initSavingsModule() end
