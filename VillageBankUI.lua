-- ============================================================
-- FS25_VillageBankUI.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

VillageBankUI = {directory=g_currentModDirectory}
local UI = VillageBankUI
local unpackValues = unpack or table.unpack
local C = {
    bg={0.016,0.016,0.016,1}, row={0.044,0.044,0.044,1}, alternate={0.027,0.027,0.027,1},
    line={0.105,0.105,0.100,1}, text={0.88,0.88,0.83,1}, muted={0.49,0.49,0.47,1},
    green={0.30,0.47,0.001,1}, black={0.005,0.006,0.003,1}, red={0.86,0.035,0.025,1}
}
UI.tabs={"KONTEN","SPAREN","FINANZIERUNG","LEASING","KREDIT","VERSICHERUNGEN","BUCHUNGEN"}
local function rect(x,y,w,h,c)
    drawFilledRect(x,1-y-h,w,h,unpackValues(c or C.bg))
end
local function line(x,y,w) rect(x,y,w,0.001,C.line) end
local function money(v)
    local formatted=g_i18n:formatMoney(v or 0,0,true,true)
    if formatted:find("€",1,true)~=nil then
        return (formatted:gsub("€",""):gsub("^%s+",""):gsub("%s+$","")).." €"
    end
    return formatted
end
UI.formatMoney=money
local function trimLast(s)
    local i=#s
    while i>0 and s:byte(i)>=128 and s:byte(i)<192 do i=i-1 end
    return s:sub(1,i-1)
end
local function text(x,y,size,value,c,width,bold,align)
    local value=tostring(value or "–")
    setTextBold(bold==true)
    if width~=nil and getTextWidth~=nil then
        if getTextWidth(size,value)>width then
            repeat value=trimLast(value) until value=="" or getTextWidth(size,value.."…")<=width
            value=value.."…"
        end
    end
    setTextColor(unpackValues(c or C.text))
    setTextAlignment(align or RenderText.ALIGN_LEFT)
    renderText(x,1-y-size,size,value)
    setTextAlignment(RenderText.ALIGN_LEFT); setTextBold(false)
end
local function right(x,y,size,value,c,width) text(x,y,size,value,c,width,false,RenderText.ALIGN_RIGHT) end
local function panel(x,y,w,h,c,rounded)
    if rounded then UI:icon("panelRounded",x,y,w,h,c)
    else rect(x,y,w,h,c) end
end
local function border(x,y,w,h,c)
    c=c or C.line
    rect(x,y,w,0.001,c); rect(x,y+h-0.001,w,0.001,c)
    rect(x,y,0.0006,h,c); rect(x+w-0.0006,y,0.0006,h,c)
end
function UI:icon(name,x,y,w,h,c)
    self.icons=self.icons or {}
    if self.icons[name]==nil then self.icons[name]=Overlay.new(self.directory.."gui/icons/"..name..".dds",0,0,1,1) end
    local overlay=self.icons[name]
    overlay:setPosition(x,1-y-h); overlay:setDimension(w,h); overlay:setColor(unpackValues(c or C.text)); overlay:render()
end
function UI:hit(id,x,y,w,h,fn,enabled)
    local item={id=id,x=x,y=y,w=w,h=h,fn=fn,enabled=enabled~=false}
    table.insert(self.hits,item)
    return item
end
function UI:button(id,x,y,w,h,label,fn,enabled,icon,selected)
    selected=selected and enabled~=false
    local hover=self.mouseX~=nil and self.mouseX>=x and self.mouseX<=x+w and self.mouseY>=y and self.mouseY<=y+h
    local edge=(self.focus==id or hover or selected) and C.green or C.line
    panel(x,y,w,h,edge,true)
    panel(x+0.0005,y+0.0009,w-0.001,h-0.0018,selected and C.green or (hover and {0.073,0.073,0.069,1} or C.row),true)
    local col=enabled==false and C.muted or (selected and C.black or C.text)
    if icon~=nil then self:icon(icon,x+0.014,y+h*0.26,0.016,h*0.48,col) end
    if w<=0.05 then
        text(x+w*0.5,y+(h-0.021)*0.5,0.021,label,col,w-0.006,false,RenderText.ALIGN_CENTER)
    else
        text(x+(icon~=nil and 0.044 or 0.012),y+(h-0.017)*0.5,0.017,label,col,w-(icon~=nil and 0.054 or 0.022))
    end
    self:hit(id,x,y,w,h,fn,enabled)
end
function UI:heading(x,label,w) text(x,0.218,0.019,label,C.text,w,true) end
function UI:detail(label,value,y,col)
    text(0.782,y,0.0155,label,C.text,0.096)
    right(0.980,y,0.0155,value,col or C.text,0.103)
end
function UI:scroll(id,x,y,w,h,count,visible,fn)
    local max=math.max(0,count-visible)
    self.offsets=self.offsets or {}; local off=math.max(0,math.min(self.offsets[id] or 0,max)); self.offsets[id]=off
    table.insert(self.scrolls,{x=x,y=y,w=w,h=h,fn=function(delta)
        self.offsets[id]=math.max(0,math.min((self.offsets[id] or 0)+delta,max))
        if fn~=nil then fn(self.offsets[id]) end
    end})
    if max>0 then
        rect(x+w-0.003,y,0.002,h,C.alternate)
        local thumb=h*visible/count
        rect(x+w-0.003,y+(h-thumb)*off/max,0.002,thumb,C.muted)
        self:hit("scroll-"..id,x+w-0.009,y,0.012,h,function()
            self.offsets[id]=math.floor(math.max(0,math.min(1,(self.mouseY-y)/h))*max+0.5)
        end)
    end
    return off
end
function UI:empty(x,y,w,label)
    text(x+0.012,y,0.017,label,C.muted,w-0.024)
end
function UI:header(bank)
    rect(0.065,0,0.935,0.958,C.bg)
    self:icon("bank",0.094,0.054,0.034,0.052,C.green)
    text(0.141,0.052,0.033,"DORFBANK · "..string.upper(bank:getMapName()),C.text,0.54,true)
    text(0.142,0.094,0.011,"REGIONAL. VERLÄSSLICH. FÜR DEINE ZUKUNFT.",C.muted,0.45)
    panel(0.713,0.054,0.180,0.053,C.black,true)
    text(0.726,0.071,0.017,"KONTOSTAND:",C.text,0.082)
    right(0.882,0.069,0.020,money(bank:getFarmMoney(bank:getFarmId())),C.green,0.091)
    text(0.909,0.057,0.010,"GEMEINSAM",C.muted,0.08)
    text(0.909,0.073,0.010,"LANDWIRTSCHAFT",C.muted,0.08)
    text(0.909,0.089,0.010,"STÄRKER MACHEN.",C.muted,0.08)
    for i,label in ipairs(self.tabs) do
        local x=0.078+(i-1)*0.129
        panel(x,0.133,0.129,0.050,bank.selectedTab==i and C.green or C.row)
        border(x,0.133,0.129,0.050)
        text(x+0.0645,0.151,0.015,label,C.text,0.120,bank.selectedTab==i,RenderText.ALIGN_CENTER)
        self:hit("tab"..i,x,0.133,0.129,0.050,function() self:setTab(bank,i) end)
    end
    line(0.065,0.183,0.935)
    rect(0.299,0.211,0.0007,0.686,C.line); rect(0.758,0.211,0.0007,0.686,C.line)
end
function UI:setTab(bank,i)
    local locked=bank:getShopContractLockedTab()
    if locked~=nil and locked~=i then bank:setStatus("Bitte den Händlervertrag abschließen oder abbrechen."); return end
    bank:closeBankSubMenus(); bank.selectedTab=i; self.focus=nil; self.hits={}; self.draggingSlider=nil
    bank.statusMessage=nil
end
function UI:footer(bank)
    rect(0.065,0.941,0.935,0.059,C.bg)
    text(0.077,0.946,0.011,"FARMING SIMULATOR 25",C.muted,0.14)
    text(0.222,0.946,0.011,"FS25_VILLAGEBANK",C.green,0.17)
    if bank.statusMessage~=nil then text(0.080,0.913,0.014,bank.statusMessage,C.text,0.90) end
end
function UI:listRow(id,index,selected,title,subtitle,amount,icon,fn)
    local y=0.263+(index-1)*0.081
    panel(0.077,y,0.216,0.080,selected and C.green or C.row)
    local c=selected and C.black or C.text
    self:icon(icon or "bank",0.087,y+0.024,0.019,0.034,c)
    text(0.119,y+0.015,0.019,title,c,0.161,true)
    text(0.119,y+0.047,0.013,subtitle,selected and C.black or C.muted,0.096)
    right(0.283,y+0.048,0.014,amount,c,0.090)
    line(0.078,y+0.080,0.214)
    self:hit(id,0.077,y,0.216,0.080,fn)
end
function UI:ledger(bank,data,x,w,account,kind)
    local entries={}
    local function signedAmount(t)
        if account~=nil and t.transactionType=="Überweisung" and t.target==account.name then return math.abs(t.amount or 0) end
        return bank:getSignedTransactionAmount(t)
    end
    for _,t in ipairs(data.transactions or {}) do
        local signed=signedAmount(t)
        local accountMatches=account==nil or t.source==account.name or t.target==account.name
        if accountMatches and ((self.filter or 0)==0 or (self.filter==1 and signed>0) or (self.filter==2 and signed<0))
            and (kind==nil or (t.transactionType or ""):find(kind,1,true)~=nil) then table.insert(entries,t) end
    end
    text(x,0.219,0.018,account~=nil and ("LETZTE BUCHUNGEN · "..string.upper(account.name)) or "BUCHUNGEN",C.text,w-0.125,true)
    local labels={[0]="Alle Buchungen",[1]="Einnahmen",[2]="Ausgaben"}
    self:button("filter",x+w-0.112,0.218,0.112,0.030,labels[self.filter or 0],function() self.filter=((self.filter or 0)+1)%3; self.offsets.ledger=0 end)
    rect(x,0.259,w,0.038,C.row)
    text(x+0.012,0.269,0.013,"TAG",C.text,0.065)
    text(x+0.102,0.269,0.013,"BUCHUNG",C.text,w-0.22)
    right(x+w-0.012,0.269,0.013,"BETRAG",C.text,0.09)
    local off=self:scroll("ledger",x,0.297,w,0.562,#entries,15)
    for row=1,15 do
        local t=entries[off+row]; if t==nil then break end
        local y=0.297+(row-1)*0.0374
        rect(x,y,w-0.005,0.0374,row%2==0 and C.row or C.alternate)
        text(x+0.012,y+0.010,0.015,"Tag "..tostring(t.day or 0),C.text,0.079)
        local name=t.transactionType or "Buchung"
        local partner=t.target==((account or {}).name) and t.source or t.target
        text(x+0.102,y+0.010,0.015,name.." · "..tostring(partner or ""),C.text,w-0.218)
        local amount=signedAmount(t)
        local neutral=name=="Finanzierungssumme" or name=="Finanzierung" or amount==0
        right(x+w-0.012,y+0.010,0.015,(neutral and "" or (amount<0 and "− " or "+ "))..money(math.abs(amount)),neutral and C.muted or (amount<0 and C.red or C.green),0.105)
    end
    border(x,0.259,w,0.600)
    if #entries==0 then self:empty(x,0.332,w,"Keine passenden Buchungen vorhanden.") end
end
function UI:accounts(bank,data)
    self:heading(0.082,"MEINE KONTEN",0.16)
    local create=function() bank:openCreateAccountForm() end
    self:button("add-small",0.244,0.213,0.025,0.036,"+",create,#data.accounts<bank.MAX_ACCOUNTS)
    bank.selectedRow=math.max(1,math.min(bank.selectedRow,#data.accounts))
    local off=self:scroll("accounts",0.077,0.263,0.218,0.567,#data.accounts,7)
    for row=1,7 do
        local index=off+row; local a=data.accounts[index]; if a==nil then break end
        self:listRow("account"..index,row,index==bank.selectedRow,a.name,a.isMain and "Hauptkonto" or "Betriebskonto",money(bank:getAccountBalance(a,bank:getFarmId())),a.icon,function() bank.selectedRow=index; bank.pendingDeleteId=nil; self.offsets.ledger=0 end)
    end
    local a=data.accounts[bank.selectedRow]
    self:ledger(bank,data,0.319,0.426,a)
    self:heading(0.782,"KONTODETAILS",0.195); line(0.782,0.254,0.199)
    if a~=nil then
        self:icon(a.icon,0.784,0.279,0.033,0.049)
        text(0.830,0.278,0.023,a.name,C.text,0.150,true)
        text(0.830,0.308,0.016,a.isMain and "Hauptkonto" or "Betriebskonto",C.muted,0.150)
        line(0.782,0.346,0.199)
        text(0.782,0.375,0.0155,"IBAN",C.text,0.072)
        right(0.980,0.375,0.0135,a.iban or "-",C.text,0.145)
        self:detail("Kontostand",money(bank:getAccountBalance(a,bank:getFarmId())),0.411,C.green)
        self:detail("Verfügbare Mittel",money(bank:getAccountBalance(a,bank:getFarmId())),0.447,C.green)
        self:detail("Zinssatz (p. a.)","0,00 %",0.483)
        self:detail("Kontoart",a.isMain and "Hauptkonto" or "Girokonto",0.519)

    end
    line(0.782,0.612,0.199)
    self:button("add",0.782,0.644,0.199,0.067,"Konto hinzufügen",create,#data.accounts<bank.MAX_ACCOUNTS,"plus")
    self:button("rename",0.782,0.724,0.199,0.067,"Umbenennen",function() bank:openRenameForm() end,a~=nil,"pencil")
    self:button("transfer",0.782,0.804,0.199,0.067,"Überweisen",function() bank:openTransferForm() end,#data.accounts>=2,"transfer")
    self:button("delete",0.080,0.849,0.210,0.040,bank.pendingDeleteId~=nil and "Löschen bestätigen" or "Konto löschen",function() bank:deleteSelectedAccount() end,a~=nil and not a.isMain)
end
function UI:summaryTitle(title,subtitle,icon)
    self:heading(0.782,"DETAILS",0.195); line(0.782,0.254,0.199)
    self:icon(icon or "bank",0.784,0.279,0.033,0.049)
    text(0.830,0.279,0.020,title,C.text,0.151,true)
    text(0.830,0.310,0.014,subtitle,C.muted,0.150); line(0.782,0.346,0.199)
end
function UI:infoTable(title,rows)
    self:heading(0.320,title,0.421)
    for i,pair in ipairs(rows) do
        local y=0.263+(i-1)*0.047
        rect(0.319,y,0.426,0.047,i%2==0 and C.alternate or C.row)
        text(0.332,y+0.014,0.016,pair[1],C.text,0.200)
        right(0.731,y+0.014,0.016,pair[2],pair[3] or C.text,0.19)
    end
end
function UI:savings(bank,data)
    self:heading(0.082,"MEINE SPARANLAGEN",0.208)
    local entries=data.savingsDeposits or {}; bank.selectedSavingsRow=math.max(1,math.min(bank.selectedSavingsRow or 1,#entries))
    local off=self:scroll("savings",0.077,0.263,0.218,0.567,#entries,7)
    for row=1,7 do local index=off+row; local d=entries[index]; if d==nil then break end
        self:listRow("saving"..index,row,index==bank.selectedSavingsRow,"Festgeld "..d.id,tostring(d.years).." Jahre",money(d.balance),"bank",function() bank.selectedSavingsRow=index end)
    end
    if #entries==0 then self:empty(0.077,0.287,0.215,"Noch keine Sparanlage.") end
    local d=entries[bank.selectedSavingsRow]
    self:infoTable("LAUFZEITEN UND KONDITIONEN",{{"Laufzeit","Zinssatz pro Jahr"},{"1 Jahr","1,00 %",C.green},{"5 Jahre","5,00 %",C.green},{"10 Jahre","10,00 %",C.green},{"Verzinsung","Täglich"},{"Auszahlung","Ab Fälligkeit"},{"Gesamtguthaben",money(data.savings),C.green}})
    self:summaryTitle(d and ("Festgeld "..d.id) or "Festgeld","Langzeitanlage","bank")
    if d then
        self:detail("Einlage",money(d.principal),0.375); self:detail("Aktueller Wert",money(d.balance),0.411,C.green)
        self:detail("Zinssatz",(string.format("%.2f %%",d.annualRate*100):gsub("%.",",")),0.447)
        self:detail("Restlaufzeit",bank:getSavingsRemainingDays(d).." Tage",0.483)
        self:detail("Fälligkeit","Tag "..d.maturityDay,0.519)
    end
    self:button("newSaving",0.782,0.644,0.199,0.067,"Festgeld anlegen",function() bank:openSavingsTransferForm() end,#entries<bank.MAX_SAVINGS_DEPOSITS,"plus")
    self:button("payout",0.782,0.724,0.199,0.067,"Anlage auszahlen",function() bank:payoutSelectedSavings() end,bank:isSavingsMature(d),"transfer")
end
function UI:contracts(bank,data,lease)
    bank:ensureFinancingData(data); bank:ensureLeasingData(data)
    local entries=lease and bank:getVisibleLeases(data) or bank:getVisibleFinanceData(data).loans
    local key=lease and "leases" or "loans"
    self:heading(0.082,lease and "LEASINGVERTRÄGE" or "FINANZIERUNGEN",0.208)
    local off=self:scroll(key,0.077,0.263,0.218,0.567,#entries,7)
    local selected
    for row=1,7 do
        local index=off+row; local entry=entries[index]; if entry==nil then break end
        local d=lease and entry.lease or entry; local selectedIndex=lease and entry.index or index
        local active=selectedIndex==(lease and bank.selectedLeaseRow or bank.selectedFinanceRow)
        self:listRow(key..index,row,active,d.vehicleName or d.label,tostring(d.monthsLeft).." Monate",money(d.monthlyRate),"tractor",function() if lease then bank.selectedLeaseRow=selectedIndex else bank.selectedFinanceRow=selectedIndex end end)
    end
    if lease then
        for _,entry in ipairs(entries) do if entry.index==bank.selectedLeaseRow then selected=entry.lease end end
        if selected==nil and #entries>0 then bank.selectedLeaseRow=entries[1].index; selected=entries[1].lease end
    else
        bank.selectedFinanceRow=math.max(1,math.min(bank.selectedFinanceRow or 1,#entries)); selected=entries[bank.selectedFinanceRow]
    end
    if #entries==0 then self:empty(0.077,0.287,0.215,"Keine laufenden Verträge.") end
    local rows={{"Abschluss","Beim Fahrzeughändler"},{"Zahlweise","Monatlich"}}
    if selected then rows={{"Fahrzeug",selected.vehicleName},{"Fahrzeugpreis",money(selected.price)},{"Anzahlung",money(selected.downPayment)},{"Monatliche Rate",money(selected.monthlyRate),C.green},{"Restlaufzeit",tostring(selected.monthsLeft).." Monate"},{"Gesamtlaufzeit",tostring(selected.monthsTotal).." Monate"},{lease and "Kaufoption" or "Schlussrate",money(lease and selected.residual or selected.balloon)},{"Zahlkonto",selected.paymentAccountName or "Hofkonto"}} end
    self:infoTable(lease and "LEASINGÜBERSICHT" or "VERTRAGSÜBERSICHT",rows)
    self:summaryTitle(selected and ("Vertrag "..selected.id) or "Kein Vertrag",lease and "Fahrzeugleasing" or "Finanzierung","tractor")
    local count,amount=bank:getContractArrears(selected,lease and "lease" or "finance")
    if selected then
        self:detail("Monatsrate",money(selected.monthlyRate),0.375,C.green)
        self:detail(lease and "Kaufoption" or "Restschuld",money(lease and selected.residual or selected.outstanding),0.411)
        self:detail("Offene Raten",tostring(count),0.447,count>0 and C.red or C.text)
        self:detail("Rückstand",money(amount),0.483,count>0 and C.red or C.text)
        self:detail("Status",selected.status=="purchaseOption" and "Kaufoption" or (count>0 and "Mahnung" or "Aktiv"),0.519)
    end
    text(0.332,0.708,0.015,"Neue Verträge schließt du beim Fahrzeugkauf ab.",C.muted,0.400)
    text(0.332,0.743,0.014,"Bei drei offenen Raten wird das Fahrzeug eingezogen.",C.muted,0.400)
    self:button("arrears",0.782,0.644,0.199,0.067,"Rückstand begleichen",function() bank:settleContractArrears(lease and "lease" or "finance",selected.id) end,count>0,"transfer")
    if lease then
        local account=selected and bank:getContractAccount(data,selected.paymentAccountId)
        local canFinish=selected~=nil and selected.status=="purchaseOption"
        self:button("buyLease",0.782,0.724,0.199,0.067,"Fahrzeug übernehmen",function() bank:buySelectedLease() end,canFinish and account~=nil and bank:getAccountBalance(account,bank:getFarmId())>=selected.residual,"plus")
        self:button("returnLease",0.782,0.804,0.199,0.067,"Fahrzeug zurückgeben",function() bank:returnSelectedLease() end,canFinish,"transfer")
    end
end
function UI:credit(bank,data)
    self:heading(0.082,"BETRIEBSKREDIT",0.208)
    local farm=bank:getNativeFarm(); local loan=farm and farm.loan or 0; local limit=bank:getNativeCreditLimit(farm)
    self:listRow("creditMain",1,true,"Hofkredit","LS25-Standardkredit",money(loan),"bank",function() end)
    self:ledger(bank,data,0.319,0.426,nil,"Kredit")
    self:summaryTitle("Betriebskredit","Hofkonto","bank")
    self:detail("Offener Kredit",money(loan),0.375); self:detail("Kreditrahmen",money(limit),0.411)
    self:detail("Noch verfügbar",money(math.max(0,limit-loan)),0.447,C.green)
    self:detail("Schrittweite",money(bank.CREDIT_STEP),0.483)
    self:button("borrow",0.782,0.644,0.199,0.067,"5.000 € leihen",function() bank:changeNativeCredit(bank.CREDIT_STEP) end,loan+bank.CREDIT_STEP<=limit,"plus")
    self:button("repay",0.782,0.724,0.199,0.067,"5.000 € zurückzahlen",function() bank:changeNativeCredit(-bank.CREDIT_STEP) end,loan>=bank.CREDIT_STEP and bank:getFarmMoney(bank:getFarmId())>=bank.CREDIT_STEP,"transfer")
end
function UI:transactions(bank,data)
    self:heading(0.082,"BUCHUNGSFILTER",0.208)
    self:listRow("allAccounts",1,self.historyAccount==nil,"Alle Konten","Dorfbank","","bank",function() self.historyAccount=nil; self.offsets.ledger=0 end)
    local off=self:scroll("historyAccounts",0.077,0.344,0.218,0.486,#data.accounts,6)
    for row=1,6 do local index=off+row; local a=data.accounts[index]; if a==nil then break end
        self:listRow("history"..index,row+1,self.historyAccount==a.id,a.name,a.isMain and "Hauptkonto" or "Girokonto","",a.icon,function() self.historyAccount=a.id; self.offsets.ledger=0 end)
    end
    local selected
    for _,a in ipairs(data.accounts) do if a.id==self.historyAccount then selected=a end end
    self:ledger(bank,data,0.319,0.426,selected)
    self:summaryTitle("Buchungsjournal","Bank und Versicherung","bank")
    self:detail("Gespeicherte Einträge",tostring(#(data.transactions or {})),0.375)
    self:detail("Konto",selected and selected.name or "Alle Konten",0.411)
    text(0.782,0.487,0.015,"Prämien und Erstattungen erscheinen",C.muted,0.199)
    text(0.782,0.515,0.015,"automatisch im Buchungsjournal.",C.muted,0.199)
    text(0.782,0.571,0.014,"Die letzten 100 Buchungen bleiben",C.muted,0.199)
    text(0.782,0.597,0.014,"im bestehenden Spielstand gespeichert.",C.muted,0.199)
end
function UI:insurance(bank)
    local mod=g_vehicleInsurance
    self:heading(0.082,"MEINE FAHRZEUGE",0.208)
    if mod==nil or not mod.enabled then
        self:infoTable("FAHRZEUGVERSICHERUNG",{{"Status","Nicht verfügbar"}})
        text(0.320,0.355,0.016,mod and mod.integrationConflict and "FS25_VehicleInsurance deaktivieren und Spielstand neu laden." or "Versicherung wird geladen.",C.text,0.422)
        return
    end
    local vehicles=mod:getVehicles(); mod.selected=math.max(1,math.min(mod.selected or 1,#vehicles))
    local off=self:scroll("insurance",0.077,0.263,0.218,0.567,#vehicles,7)
    for row=1,7 do local index=off+row; local v=vehicles[index]; if v==nil then break end
        self:listRow("vehicle"..index,row,index==mod.selected,mod.getDisplayName(v),mod.names[v.vitState.policy],money(mod.premium(v,v.vitState.policy)),"tractor",function() mod.selected=index end)
    end
    local v=vehicles[mod.selected]; local state=v and v.vitState
    if #vehicles==0 then self:empty(0.077,0.287,0.215,"Keine eigenen Fahrzeuge.") end
    self:heading(0.320,"VERSICHERUNG UND TARIFE",0.421)
    local rows={{"Leistung","Teilkasko","Vollkasko"},{"Reparaturkosten","50 %","100 %"},{"Lackierkosten","50 %","100 %"},{"Jahresbeitrag","1,2 %","2,4 %"},{"Mindestbeitrag / Monat","2 €","2 €"},{"Tarifwechsel","Nächster Monat","Nächster Monat"}}
    for i,r in ipairs(rows) do local y=0.263+(i-1)*0.052
        rect(0.319,y,0.426,0.052,i%2==0 and C.alternate or C.row)
        text(0.332,y+0.016,0.015,r[1],C.text,0.19,i==1)
        text(0.539,y+0.016,0.015,r[2],i==1 and C.text or C.green,0.09,i==1)
        text(0.644,y+0.016,0.015,r[3],i==1 and C.text or C.green,0.09,i==1)
    end
    text(0.332,0.631,0.015,"Beiträge richten sich nach dem Fahrzeugwert.",C.muted,0.40)
    text(0.332,0.664,0.015,"Normale Fahrzeug-Unterhaltskosten bleiben bestehen.",C.muted,0.40)
    text(0.332,0.730,0.015,mod.notice,C.text,0.40)
    self:summaryTitle(v and mod.getDisplayName(v) or "Kein Fahrzeug","Schadensversicherung","tractor")
    if v then
        self:detail("Aktueller Tarif",mod.names[state.policy],0.375)
        self:detail("Ab nächstem Monat",mod.names[state.pending],0.411,C.green)
        self:detail("Monatsbeitrag",money(mod.premium(v,state.policy)),0.447)
        self:detail("Beiträge gesamt",money(state.premiums),0.483)
        self:detail("Erstattungen",money(state.refunds),0.519,C.green)
        self:detail("Kennzeichen",mod:getLicensePlate(v),0.555)
    end
    local enabled=v~=nil and mod.canChangePolicy(v,nil)
    for i,policy in ipairs({0,2,3}) do
        self:button("policy"..policy,0.782,0.644+(i-1)*0.080,0.199,0.067,mod.names[policy],function() mod:requestPolicy(v,policy) end,enabled,"shield",state~=nil and state.pending==policy)
    end
end

function UI:hasModal(bank)
    return bank.uiOptions~=nil or bank.createAccountFormOpen or bank.transferFormOpen or bank.renameFormOpen or bank.savingsTransferFormOpen or bank.financeFormOpen or bank.leaseFormOpen
end
function UI:cancel(bank)
    local options=bank.uiOptions
    bank.uiOptions=nil; bank.leaseReturnDialogOpen=false
    if bank.shopContractContext~=nil then bank:cancelShopContract() else bank:closeBankSubMenus() end
    if options~=nil and options.callback~=nil then options.callback(nil) end
    self.focus=nil; self.hits={}; self.draggingSlider=nil
end
function UI:field(bank,label,y,field,locked)
    text(0.351,y,0.013,label,C.muted,0.30)
    rect(0.351,y+0.026,0.300,0.045,C.row)
    border(0.351,y+0.026,0.300,0.045,bank.activeTextField==field and C.green or C.line)
    text(0.363,y+0.039,0.019,(bank.textBuffer=="" and "Eingeben …" or bank.textBuffer)..(bank.activeTextField==field and "|" or ""),C.text,0.275)
    self:hit("field-"..field,0.351,y+0.026,0.300,0.045,function() bank.activeTextField=field end,not locked)
end
function UI:selector(id,label,value,y,previous,nextValue)
    text(0.351,y,0.013,label,C.muted,0.30)
    self:button(id.."Prev",0.351,y+0.026,0.030,0.042,"<",previous,previous~=nil)
    rect(0.386,y+0.026,0.230,0.042,C.row)
    text(0.397,y+0.038,0.016,value,C.text,0.210)
    self:button(id.."Next",0.621,y+0.026,0.030,0.042,">",nextValue,nextValue~=nil)
end
function UI:slider(bank,id,label,x,y,w,values,current,onChange,suffix)
    local index=1
    for i,value in ipairs(values) do if math.abs(value-current)<math.abs(values[index]-current) then index=i end end
    local left=x+0.006; local width=w-0.012
    local ratio=#values>1 and (index-1)/(#values-1) or 0
    text(x,y,0.012,label,C.muted,w-0.065)
    right(x+w,y-0.001,0.016,tostring(values[index])..suffix,C.text,0.090)
    rect(left,y+0.038,width,0.005,C.line)
    if ratio>0 then rect(left,y+0.038,width*ratio,0.005,C.green) end
    rect(left+width*ratio-0.005,y+0.029,0.010,0.023,C.green)
    text(x,y+0.059,0.010,tostring(values[1]),C.muted,w*0.4)
    right(x+w,y+0.059,0.010,tostring(values[#values]),C.muted,w*0.4)
    local function select(nextIndex)
        index=math.max(1,math.min(#values,nextIndex))
        onChange(values[index])
    end
    local slider={bank=bank,tab=bank.selectedTab,form=bank.financeFormOpen and "finance" or "lease"}
    slider.setFromX=function(pointerX)
        local position=math.max(0,math.min(1,(pointerX-left)/width))
        select(math.floor(position*(#values-1)+0.5)+1)
    end
    self:hit(id,x,y+0.020,w,0.038,function()
        self.draggingSlider=slider
        slider.setFromX(self.mouseX)
    end)
    table.insert(self.scrolls,{x=x,y=y+0.020,w=w,h=0.052,fn=function(delta) select(index-delta) end})
end
function UI:accountIconPicker(bank)
    local labels={"Hof","Pflanzen","Tiere","Forst","Maschinen","Fahrzeuge","Bank","Versicherung"}
    text(0.351,0.430,0.013,"KONTOSYMBOL AUSWÄHLEN",C.muted,0.30)
    for i,name in ipairs(bank.ACCOUNT_ICONS) do
        local x=0.351+((i-1)%4)*0.077
        local y=0.461+math.floor((i-1)/4)*0.143
        local selected=bank.selectedAccountIcon==name
        self:button("accountIcon-"..name,x,y,0.069,0.084,"",function() bank.selectedAccountIcon=name end,true,nil,selected)
        self:icon(name,x+0.021,y+0.018,0.027,0.048,selected and C.black or C.text)
        text(x+0.0345,y+0.096,0.013,labels[i],C.text,0.073,false,RenderText.ALIGN_CENTER)
    end
end
function UI:modal(bank,data)
    self.hits={}; self.scrolls={}
    rect(0.065,0.184,0.935,0.757,C.bg)
    local finance=bank.financeFormOpen; local lease=bank.leaseFormOpen
    local title=bank.uiOptions~=nil and bank.uiOptions.title or (bank.renameFormOpen and "KONTO UMBENENNEN" or (bank.transferFormOpen and "ÜBERWEISUNG" or (bank.savingsTransferFormOpen and "FESTGELD ANLEGEN" or (finance and "FAHRZEUGFINANZIERUNG" or "FAHRZEUGLEASING"))))
    if bank.createAccountFormOpen then title="KONTO ERÖFFNEN" end
    panel(0.329,0.210,0.344,0.676,C.alternate); border(0.329,0.210,0.344,0.676)
    rect(0.329,0.210,0.344,0.004,C.green)
    text(0.351,0.237,0.023,title,C.text,0.30,true); line(0.351,0.280,0.300)
    local confirm,valid,label
    if bank.uiOptions~=nil then
        local options=bank.uiOptions
        text(0.351,0.310,0.015,options.message,C.muted,0.30)
        local off=self:scroll("options",0.351,0.362,0.303,0.420,#options.options,7)
        for row=1,7 do local index=off+row; local value=options.options[index]; if value==nil then break end
            self:button("option"..index,0.351,0.363+(row-1)*0.057,0.300,0.048,value,function()
                bank.uiOptions=nil; bank.leaseReturnDialogOpen=false; self.focus=nil; options.callback(index)
            end)
        end
        self:button("cancel",0.351,0.818,0.133,0.043,"Abbrechen",function() self:cancel(bank) end)
        return
    elseif bank.createAccountFormOpen then
        self:field(bank,"KONTONAME (OPTIONAL)",0.321,"accountName")
        self:accountIconPicker(bank)
        text(0.351,0.756,0.013,"Ohne Namen: Geschäftskonto "..tostring(#data.accounts),C.muted,0.30)
        confirm=function()
            bank:confirmCreateAccountForm()
            if not bank.createAccountFormOpen then self.offsets.accounts=math.max(0,#bank:getFarmData().accounts-7) end
        end
        valid=#data.accounts<bank.MAX_ACCOUNTS; label="Konto eröffnen"
    elseif bank.renameFormOpen then
        self:field(bank,"KONTONAME",0.321,"rename")
        self:accountIconPicker(bank)
        confirm=function() bank:confirmRenameForm() end; valid=(bank.textBuffer or ""):match("%S")~=nil; label="Speichern"
    elseif bank.transferFormOpen then
        local source=data.accounts[bank.transferSourceIndex]; local target=data.accounts[bank.transferTargetIndex]
        self:selector("source","VON KONTO",source and source.name or "–",0.310,function() bank:cycleTransferAccount("source",-1) end,function() bank:cycleTransferAccount("source",1) end)
        self:selector("target","AN KONTO",target and target.name or "–",0.405,function() bank:cycleTransferAccount("target",-1) end,function() bank:cycleTransferAccount("target",1) end)
        self:field(bank,"BETRAG IN EURO",0.505,"amount")
        local amount=tonumber(bank.textBuffer) or 0
        valid=source~=nil and target~=nil and source~=target and amount>0 and amount<=bank:getAccountBalance(source,bank:getFarmId())
        if source then text(0.351,0.616,0.015,"Verfügbar: "..money(bank:getAccountBalance(source,bank:getFarmId())),C.green,0.30) end
        confirm=function() bank:confirmTransferForm() end; label="Überweisen"
    elseif bank.savingsTransferFormOpen then
        local source=data.accounts[bank.savingsSourceIndex]
        self:selector("savingSource","VON KONTO",source and source.name or "–",0.310,function() bank:cycleSavingsSource(-1) end,function() bank:cycleSavingsSource(1) end)
        text(0.351,0.410,0.013,"LAUFZEIT UND ZINSSATZ",C.muted,0.30)
        for i,term in ipairs(bank.SAVINGS_TERMS) do
            self:button("term"..i,0.351+(i-1)*0.102,0.438,0.096,0.052,term.years.." J. / "..math.floor(term.rate*100).." %",function() bank.savingsTermYears=term.years end,true,nil,bank.savingsTermYears==term.years)
        end
        self:field(bank,"ANLAGEBETRAG IN EURO",0.517,"savingsAmount")
        local amount=tonumber(bank.textBuffer) or 0
        valid=source~=nil and amount>0 and amount<=bank:getAccountBalance(source,bank:getFarmId())
        text(0.351,0.629,0.015,"Auszahlung nach Ende der Laufzeit.",C.muted,0.30)
        confirm=function() bank:confirmSavingsTransferForm() end; label="Fest anlegen"
    elseif finance or lease then
        local context=bank.shopContractContext
        local price=context and context.price or tonumber(bank.textBuffer) or 0
        local vehicle=context and context.vehicle
        text(0.351,0.302,0.013,"FAHRZEUG VOM HÄNDLER",C.muted,0.30)
        text(0.351,0.328,0.019,vehicle and vehicle.name or "Kein Händlerfahrzeug",C.text,0.30,true)
        text(0.351,0.361,0.017,"Kaufpreis: "..money(price),C.green,0.30)
        bank.activeTextField=nil 
        local terms=bank.FINANCE_TERMS
        if lease then terms={}; for _,profile in ipairs(bank.LEASE_PROFILES) do table.insert(terms,profile.months) end end
        self:slider(bank,"duration","LAUFZEIT",0.351,0.408,0.300,terms,finance and bank.financeMonths or bank.leaseMonths,
            function(value) if finance then bank.financeMonths=value else bank.leaseMonths=value end end," Monate")
        local accountIndex=finance and bank.financeAccountIndex or bank.leaseAccountIndex
        local account=data.accounts[accountIndex]
        if finance then
            self:slider(bank,"down","ANZAHLUNG",0.351,0.498,0.145,bank.FINANCE_DOWNPAYMENTS,bank.financeDownPercent,function(value) bank.financeDownPercent=value end," %")
            self:slider(bank,"balloon","SCHLUSSRATE",0.506,0.498,0.145,bank.FINANCE_BALLOONS,bank.financeBalloonPercent,function(value) bank.financeBalloonPercent=value end," %")
        end
        self:selector("payment","ZAHLKONTO",account and account.name or "–",0.576,
            function() if finance then bank.financeAccountIndex=(bank.financeAccountIndex-2)%#data.accounts+1 else bank.leaseAccountIndex=(bank.leaseAccountIndex-2)%#data.accounts+1 end end,
            function() if finance then bank:cycleFinanceAccount() else bank:cycleLeaseAccount() end end)
        local down,final,payment
        if finance then down,final,payment=bank:calculateFinance(price,bank.financeMonths,bank.financeDownPercent,bank.financeBalloonPercent)
        else down,final,payment=bank:calculateLease(price,bank.leaseMonths) end
        local approved,reason=bank:checkContractLiquidity(price,down,payment,final,accountIndex)
        valid=context~=nil and vehicle~=nil and price>=1000 and approved
        text(0.351,0.686,0.014,"Anzahlung "..money(down).." · Rate "..money(payment),C.text,0.30)
        text(0.351,0.715,0.014,(finance and "Schlussrate: " or "Kaufoption: ")..money(final),C.text,0.30)
        text(0.351,0.753,0.013,valid and "GENEHMIGT" or (reason or "Kein Händlervertrag"),valid and C.green or C.red,0.30)
        confirm=function() if finance then bank:createVehicleFinance() else bank:createVehicleLease() end end
        label=finance and "Finanzieren" or "Leasing starten"
    end
    self:button("cancel",0.351,0.818,0.133,0.043,"Abbrechen",function() self:cancel(bank) end)
    self:button("confirm",0.505,0.818,0.146,0.043,label or "Bestätigen",confirm,valid,nil,true)
    if bank.statusMessage then text(0.351,0.782,0.012,bank.statusMessage,C.red,0.30) end
end
function UI:draw(bank)
    if not bank.isOpen or g_currentMission==nil then return end
    local drag=self.draggingSlider
    if drag~=nil and (drag.bank~=bank or drag.tab~=bank.selectedTab
        or (drag.form=="finance" and not bank.financeFormOpen) or (drag.form=="lease" and not bank.leaseFormOpen)) then self.draggingSlider=nil end
    if self:hasModal(bank) and not self.renderedModal then self.focus=nil end
    self.hits={}; self.scrolls={}; self.offsets=self.offsets or {}
    self:header(bank)
    local data=bank:getFarmData()
    local tab=bank.selectedTab
    if not self:hasModal(bank) then
        if tab==1 then self:accounts(bank,data)
        elseif tab==2 then self:savings(bank,data)
        elseif tab==3 then self:contracts(bank,data,false)
        elseif tab==4 then self:contracts(bank,data,true)
        elseif tab==5 then self:credit(bank,data)
        elseif tab==6 then self:insurance(bank)
        elseif tab==7 then self:transactions(bank,data) end
    end
    self:footer(bank)
    if self:hasModal(bank) then self:modal(bank,data) end
    self.renderedTab=bank.selectedTab; self.renderedModal=self:hasModal(bank)
    setTextBold(false); setTextAlignment(RenderText.ALIGN_LEFT); setTextColor(1,1,1,1)
end
function UI:mouse(bank,x,y,isDown,isUp,button)
    if not bank.isOpen or (bank.leaseReturnDialogOpen and bank.uiOptions==nil) then self.draggingSlider=nil; return false end
    self.mouseX=x; self.mouseY=1-y
    local key=string.format("%s:%s:%.6f:%.6f:%s:%s",g_time or 0,button or 0,x,y,tostring(isDown),tostring(isUp))
    if self.lastMouse==key then return true end
    self.lastMouse=key
    if self.renderedTab~=bank.selectedTab or self.renderedModal~=self:hasModal(bank) then self.draggingSlider=nil; return true end
    local drag=self.draggingSlider
    if drag~=nil then
        if drag.bank~=bank or drag.tab~=bank.selectedTab
            or (drag.form=="finance" and not bank.financeFormOpen) or (drag.form=="lease" and not bank.leaseFormOpen) then
            self.draggingSlider=nil
        else
            drag.setFromX(x)
            if isUp then self.draggingSlider=nil end
            return true
        end
    end
    local wheelUp=button==4 or (Input.MOUSE_BUTTON_WHEEL_UP~=nil and button==Input.MOUSE_BUTTON_WHEEL_UP)
    local wheelDown=button==5 or (Input.MOUSE_BUTTON_WHEEL_DOWN~=nil and button==Input.MOUSE_BUTTON_WHEEL_DOWN)
    if isDown and (wheelUp or wheelDown) then
        for _,s in ipairs(self.scrolls or {}) do
            if x>=s.x and x<=s.x+s.w and self.mouseY>=s.y and self.mouseY<=s.y+s.h then s.fn(wheelUp and -1 or 1); return true end
        end
    end
    if isDown and (button==1 or (Input.MOUSE_BUTTON_LEFT~=nil and button==Input.MOUSE_BUTTON_LEFT)) then
        for i=#(self.hits or {}),1,-1 do local h=self.hits[i]
            if x>=h.x and x<=h.x+h.w and self.mouseY>=h.y and self.mouseY<=h.y+h.h then
                if h.enabled and h.fn~=nil then self.focus=h.id; h.fn(); self.hits={} end
                return true
            end
        end
    end
    return x>=0.065
end
local oldKeyEvent=VillageBank.keyEvent
function VillageBank:keyEvent(unicode,sym,modifier,isDown)
    if not self.isOpen or self.activeTextField==nil or (self.leaseReturnDialogOpen and self.uiOptions==nil) then return false end
    if sym==Input.KEY_esc or sym==Input.KEY_tab or sym==Input.KEY_return
        or (Input.KEY_KP_enter~=nil and sym==Input.KEY_KP_enter)
        or sym==Input.KEY_left or sym==Input.KEY_right then return false end
    if not isDown then return self.activeTextField~=nil end
    local key=table.concat({tostring(g_time),tostring(unicode),tostring(sym),tostring(modifier)},":")
    if UI.lastKey==key then return true end; UI.lastKey=key
    if self.activeTextField~=nil then
        UI.focus="field-"..self.activeTextField
        if sym==Input.KEY_backspace then self.textBuffer=trimLast(self.textBuffer or ""); return true end
        if unicode~=nil and unicode>=128 and unicodeToUtf8~=nil and (self.activeTextField=="rename" or self.activeTextField=="accountName") then
            if #(self.textBuffer or "")<112 then self.textBuffer=self.textBuffer..unicodeToUtf8(unicode) end
            return true
        end
        return oldKeyEvent(self,unicode,sym,modifier,isDown)
    end
    return false
end
function VillageBank:mouseEvent(...) return UI:mouse(self,...) end
function VillageBank:drawBankSurface() UI:draw(self) end
function VillageBank:drawEscBankSurface() UI:draw(self) end
function VillageBankFrame:mouseEvent(x,y,isDown,isUp,button,eventUsed)
    if g_villageBank~=nil and g_villageBank.isMenuPageOpen and UI:mouse(g_villageBank,x,y,isDown,isUp,button) then return true end
    return VillageBankFrame:superClass().mouseEvent(self,x,y,isDown,isUp,button,eventUsed)
end
function VillageBankFrame:keyEvent(unicode,sym,modifier,isDown,eventUsed)
    if g_villageBank~=nil and g_villageBank:keyEvent(unicode,sym,modifier,isDown) then return true end
    return VillageBankFrame:superClass().keyEvent(self,unicode,sym,modifier,isDown,eventUsed)
end
function VillageBankFrame:setBankTab(index)
    if g_villageBank~=nil then UI:setTab(g_villageBank,index) end
end
function VillageBank:confirmRenameForm()
    local data=self:getFarmData(); local account=data.accounts[self.selectedRow]
    local oldName=account and account.name
    local name=tostring(self.textBuffer or ""):match("^%s*(.-)%s*$")
    if account==nil or name=="" then return end
    account.name=name
    account.icon=self.normalizeAccountIcon(self.selectedAccountIcon,account.icon)
    if oldName~=account.name then
        for _,t in ipairs(data.transactions or {}) do
            if t.source==oldName then t.source=account.name end
            if t.target==oldName then t.target=account.name end
        end
        for _,items in ipairs({data.loans or {},data.leases or {}}) do
            for _,contract in ipairs(items) do if contract.paymentAccountId==account.id then contract.paymentAccountName=account.name end end
        end
    end
    self:saveState()
    self.renameFormOpen=false; self.activeTextField=nil
end
local oldFrameClose=VillageBankFrame.onFrameClose
function VillageBankFrame:onFrameClose()
    UI.hits={}; UI.scrolls={}; UI.focus=nil; UI.draggingSlider=nil
    if g_villageBank~=nil then
        if UI:hasModal(g_villageBank) then UI:cancel(g_villageBank) end
        g_villageBank:closeBankSubMenus(); g_villageBank.uiOptions=nil; g_villageBank.leaseReturnDialogOpen=false
    end
    return oldFrameClose(self)
end
local oldDeleteMap=VillageBank.deleteMap
function VillageBank:deleteMap(...)
    for _,overlay in pairs(UI.icons or {}) do overlay:delete() end
    UI.icons=nil; UI.hits={}; UI.scrolls={}; UI.offsets={}; UI.lastKey=nil; UI.lastMouse=nil; UI.draggingSlider=nil
    return oldDeleteMap(self,...)
end

function VillageBank:showStyledOptions(callback,title,message,options)
    local dialog={callback=callback,title=title,message=message,options=options}
    UI.focus=nil; UI.offsets=UI.offsets or {}; UI.offsets.options=0
    if self.isMenuPageOpen then self.uiOptions=dialog; return end
    self.pendingStyledOptions=dialog; self.pendingStyledOptionsDelay=nil
end
local oldUpdate=VillageBank.update
function VillageBank:update(dt)
    oldUpdate(self,dt)
    if self.pendingStyledOptions==nil then return end
    if self.pendingStyledOptionsDelay==nil then
        if g_gui~=nil and g_gui.closeAllDialogs~=nil then g_gui:closeAllDialogs() end
        self.pendingStyledOptionsDelay=180
        return
    end
    self.pendingStyledOptionsDelay=self.pendingStyledOptionsDelay-(dt or 0)
    if self.pendingStyledOptionsDelay>0 then return end
    local dialog=self.pendingStyledOptions
    self.pendingStyledOptions=nil; self.pendingStyledOptionsDelay=nil
    if VillageBankMenu:openBankPage(1) then
        self.uiOptions=dialog; self.activeTextField=nil
    else
        self:setStatus("Dorfbank konnte nicht geöffnet werden.")
        dialog.callback(nil)
    end
end
function VillageBank:returnSelectedLease()
    local lease=self:getFarmData().leases[self.selectedLeaseRow]
    if lease==nil or lease.status~="purchaseOption" or self.leaseReturnDialogOpen then return end
    self.leaseReturnDialogOpen=true
    self:showStyledOptions(function(index)
        self.leaseReturnDialogOpen=false
        if index==1 then self:confirmLeaseReturn(lease.id) end
    end,"FAHRZEUG ZURÜCKGEBEN",lease.vehicleName or "Leasingfahrzeug",{"Rückgabe bestätigen","Fahrzeug behalten"})
end
