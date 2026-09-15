-- ============================================================
-- FS25_VillageBankCredit.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

VillageBank.CREDIT_STEP = 5000
VillageBank.DEFAULT_MAX_CREDIT = 500000

local function creditText(x,y,size,value,r,g,b,a)
    setTextColor(r or 1,g or 1,b or 1,a or 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
    renderText(x,y,size,value)
end

local function creditMoney(value)
    return g_i18n:formatMoney(value or 0,0,true,true)
end

function VillageBank:getNativeFarm()
    return g_farmManager ~= nil and g_farmManager:getFarmById(self:getFarmId()) or nil
end

function VillageBank:getNativeCreditLimit(farm)
    if farm == nil then return self.DEFAULT_MAX_CREDIT end
    if farm.getLoanMax ~= nil then
        local ok,value=pcall(farm.getLoanMax,farm)
        if ok and tonumber(value)~=nil then return tonumber(value) end
    end
    local info=g_currentMission~=nil and g_currentMission.missionInfo or nil
    return tonumber(farm.loanMax or farm.maxLoan or (info~=nil and info.maxLoan)) or self.DEFAULT_MAX_CREDIT
end

function VillageBank:changeNativeCredit(delta)
    local farm=self:getNativeFarm()
    if farm==nil then self:setStatus("Kreditkonto nicht verfügbar."); return false end
    local step=self.CREDIT_STEP
    local loan=math.max(0,tonumber(farm.loan) or 0)
    local maxLoan=self:getNativeCreditLimit(farm)
    if delta>0 then
        if loan+step>maxLoan then self:setStatus("Der maximale Kreditrahmen ist erreicht."); return false end
        farm.loan=loan+step
        self:changeFarmMoney(step,self:getFarmId())
        self:addTransaction(self:getFarmData(),"Kreditaufnahme","Dorfbank","Hofkonto",step)
        self:setStatus("5.000 € Kredit wurden dem Hofkonto gutgeschrieben.")
    else
        if loan<step then self:setStatus("Es sind weniger als 5.000 € Kredit offen."); return false end
        if self:getFarmMoney(self:getFarmId())<step then self:setStatus("Das Hofkonto reicht für die Rückzahlung nicht aus."); return false end
        self:changeFarmMoney(-step,self:getFarmId())
        farm.loan=math.max(0,loan-step)
        self:addTransaction(self:getFarmData(),"Kredittilgung","Hofkonto","Dorfbank",-step)
        self:setStatus("5.000 € Kredit wurden zurückgezahlt.")
    end
    self:saveState()
    return true
end

function VillageBank:drawCredit(data,x,y)
    local farm=self:getNativeFarm()
    local loan=farm~=nil and (tonumber(farm.loan) or 0) or 0
    local limit=self:getNativeCreditLimit(farm)
    creditText(x,y,0.019,"BETRIEBSKREDIT",0.88,0.90,0.89,1)
    creditText(x+0.49,y,0.013,"LS25-STANDARDKREDIT",0.62,0.66,0.64,1)
    self:drawPanel(x-0.006,y-0.175,0.50,0.145,0.025,0.029,0.032,1)
    self:drawPanel(x-0.006,y-0.033,0.50,0.003,0.32,0.55,0.04,1)
    creditText(x+0.018,y-0.070,0.013,"OFFENER KREDIT",0.62,0.68,0.64,1)
    creditText(x+0.018,y-0.112,0.027,creditMoney(loan),0.55,0.78,0.18,1)
    creditText(x+0.275,y-0.070,0.013,"KREDITRAHMEN",0.62,0.68,0.64,1)
    creditText(x+0.275,y-0.108,0.020,creditMoney(limit),0.88,0.90,0.89,1)
    creditText(x,y-0.225,0.014,"Kreditaufnahme und Rückzahlung erfolgen in Schritten von 5.000 €.",0.68,0.72,0.69,1)
    self:drawButton(0.145,self.ACTION_BUTTON_Y or 0.172,0.165,0.035,"5.000 € leihen",loan+self.CREDIT_STEP<=limit)
    self:drawButton(0.320,self.ACTION_BUTTON_Y or 0.172,0.165,0.035,"5.000 € zurückzahlen",loan>=self.CREDIT_STEP and self:getFarmMoney(self:getFarmId())>=self.CREDIT_STEP)
end

function VillageBank:handleCreditMouse(px,py)
    if self.selectedTab~=5 then return false end
    if self:isInside(px,py,0.145,self.ACTION_BUTTON_Y or 0.172,0.165,0.035) then self:changeNativeCredit(self.CREDIT_STEP); return true end
    if self:isInside(px,py,0.320,self.ACTION_BUTTON_Y or 0.172,0.165,0.035) then self:changeNativeCredit(-self.CREDIT_STEP); return true end
    return false
end

local function installNativeCreditBridge()
    local frameClass=InGameMenuStatisticsFrame
    if frameClass==nil then return end
    local callbacks={"onClickBorrow","onClickRepay","onClickBorrowMoney","onClickRepayMoney","onBorrow","onRepay","onBorrowMoney","onRepayMoney"}
    for _,name in ipairs(callbacks) do
        if frameClass[name]~=nil then
            frameClass[name]=Utils.overwrittenFunction(frameClass[name],function(frame,superFunc,...)
                if VillageBankMenu~=nil and VillageBankMenu.openBankPage~=nil and VillageBankMenu:openBankPage(5) then return end
                return superFunc(frame,...)
            end)
        end
    end
end

installNativeCreditBridge()
