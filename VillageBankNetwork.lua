-- ============================================================
-- FS25_VillageBankNetwork.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

VillageBankNetwork = VillageBankNetwork or {}
VillageBankNetwork.MAX_NETWORK_FARMS = 64
VillageBankNetwork.MAX_NETWORK_ACCOUNTS = 10
VillageBankNetwork.MAX_NETWORK_SAVINGS = 8
VillageBankNetwork.MAX_NETWORK_FINANCINGS = 64
VillageBankNetwork.MAX_NETWORK_LEASES = 64
VillageBankNetwork.MAX_NETWORK_TRANSACTIONS = 100

local function writeNumber(streamId, value)
    streamWriteString(streamId, string.format("%.17g", tonumber(value) or 0))
end

local function readNumber(streamId, default)
    local value = tonumber(streamReadString(streamId))
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return default or 0
    end
    return value
end

local function safeString(value, maxLen)
    local text = tostring(value or "")
    if maxLen ~= nil and #text > maxLen then
        text = string.sub(text, 1, maxLen)
    end
    return text
end

local function writeFarmData(streamId, farmId, data)
    data = data or {}
    streamWriteInt32(streamId, math.floor(tonumber(farmId) or 0))
    streamWriteInt32(streamId, math.max(1, math.floor(tonumber(data.nextId) or 1)))
    writeNumber(streamId, data.interestEarned or 0)
    writeNumber(streamId, data.interestPaid or 0)

    streamWriteInt32(streamId, data.revision or 0)
    local accounts = data.accounts or {}
    local accountCount = math.min(#accounts, VillageBankNetwork.MAX_NETWORK_ACCOUNTS)
    streamWriteInt32(streamId, accountCount)
    for i = 1, accountCount do
        local account = accounts[i] or {}
        streamWriteInt32(streamId, math.floor(tonumber(account.id) or 0))
        streamWriteString(streamId, safeString(account.name, 64))
        streamWriteString(streamId, safeString(account.iban, 64))
        streamWriteBool(streamId, account.isMain == true)
        writeNumber(streamId, account.balance or 0)
    end

    local savings = data.savingsDeposits or {}
    streamWriteInt32(streamId, math.max(1, math.floor(tonumber(data.nextSavingsId) or 1)))
    local savingsCount = math.min(#savings, VillageBankNetwork.MAX_NETWORK_SAVINGS)
    streamWriteInt32(streamId, savingsCount)
    for i = 1, savingsCount do
        local deposit = savings[i] or {}
        streamWriteInt32(streamId, math.floor(tonumber(deposit.id) or i))
        writeNumber(streamId, deposit.balance or 0)
        writeNumber(streamId, deposit.principal or 0)
        streamWriteInt32(streamId, math.floor(tonumber(deposit.years) or 1))
        writeNumber(streamId, deposit.annualRate or 0.01)
        streamWriteInt32(streamId, math.floor(tonumber(deposit.startDay) or 0))
        streamWriteInt32(streamId, math.floor(tonumber(deposit.maturityDay) or 0))
    end

    local loans = data.loans or {}
    streamWriteInt32(streamId, math.max(1, math.floor(tonumber(data.nextFinanceId) or 1)))
    local loanCount = math.min(#loans, VillageBankNetwork.MAX_NETWORK_FINANCINGS)
    streamWriteInt32(streamId, loanCount)
    for i = 1, loanCount do
        local loan = loans[i] or {}
        streamWriteInt32(streamId, math.floor(tonumber(loan.id) or i))
        streamWriteString(streamId, safeString(loan.label, 96))
        streamWriteString(streamId, safeString(loan.vehicleId, 160))
        streamWriteString(streamId, safeString(loan.vehicleName, 128))
        streamWriteString(streamId, safeString(loan.vehicleConfigFile, 256))
        writeNumber(streamId, loan.price or 0)
        writeNumber(streamId, loan.annualRate or 0)
        writeNumber(streamId, loan.downPayment or 0)
        writeNumber(streamId, loan.balloon or 0)
        writeNumber(streamId, loan.monthlyRate or 0)
        streamWriteInt32(streamId, math.max(0, math.floor(tonumber(loan.monthsTotal) or 0)))
        streamWriteInt32(streamId, math.max(0, math.floor(tonumber(loan.monthsLeft) or 0)))
        writeNumber(streamId, loan.outstanding or 0)
        streamWriteInt32(streamId, math.floor(tonumber(loan.paymentAccountId) or 0))
        streamWriteString(streamId, safeString(loan.paymentAccountName, 64))
        streamWriteInt32(streamId, loan.arrearsCount or 0)
        streamWriteString(streamId, safeString(loan.status or "active",32))
    end

    local leases = data.leases or {}
    streamWriteInt32(streamId, math.max(1, math.floor(tonumber(data.nextLeaseId) or 1)))
    local leaseCount = math.min(#leases, VillageBankNetwork.MAX_NETWORK_LEASES)
    streamWriteInt32(streamId, leaseCount)
    for i = 1, leaseCount do
        local lease = leases[i] or {}
        streamWriteInt32(streamId, math.floor(tonumber(lease.id) or i))
        streamWriteString(streamId, safeString(lease.label, 96))
        streamWriteString(streamId, safeString(lease.vehicleId, 160))
        streamWriteString(streamId, safeString(lease.vehicleName, 128))
        streamWriteString(streamId, safeString(lease.vehicleConfigFile, 256))
        writeNumber(streamId, lease.price or 0)
        writeNumber(streamId, lease.downPayment or 0)
        writeNumber(streamId, lease.monthlyRate or 0)
        writeNumber(streamId, lease.residual or 0)
        streamWriteInt32(streamId, math.max(0, math.floor(tonumber(lease.monthsTotal) or 0)))
        streamWriteInt32(streamId, math.max(0, math.floor(tonumber(lease.monthsLeft) or 0)))
        streamWriteString(streamId, safeString(lease.status, 32))
        streamWriteInt32(streamId, math.floor(tonumber(lease.paymentAccountId) or 0))
        streamWriteString(streamId, safeString(lease.paymentAccountName, 64))
        streamWriteInt32(streamId, lease.arrearsCount or 0)
    end

    local transactions = data.transactions or {}
    local transactionCount = math.min(#transactions, VillageBankNetwork.MAX_NETWORK_TRANSACTIONS)
    streamWriteInt32(streamId, transactionCount)
    for i = 1, transactionCount do
        local transaction = transactions[i] or {}
        streamWriteString(streamId, safeString(transaction.transactionType, 64))
        streamWriteString(streamId, safeString(transaction.source, 96))
        streamWriteString(streamId, safeString(transaction.target, 96))
        writeNumber(streamId, transaction.amount or 0)
        streamWriteInt32(streamId, math.max(0, math.floor(tonumber(transaction.day) or 0)))
    end
end

local function readFarmData(streamId)
    local farmId = streamReadInt32(streamId)
    local data = {
        accounts = {}, savingsDeposits = {}, loans = {}, leases = {}, transactions = {},
        nextId = math.max(1, streamReadInt32(streamId)),
        interestEarned = readNumber(streamId, 0),
        interestPaid = readNumber(streamId, 0)
    }

    data.revision=streamReadInt32(streamId)
    local accountCount = math.max(0, math.min(streamReadInt32(streamId), VillageBankNetwork.MAX_NETWORK_ACCOUNTS))
    for i = 1, accountCount do
        local account = {
            id = streamReadInt32(streamId),
            name = safeString(streamReadString(streamId), 64),
            iban = safeString(streamReadString(streamId), 64),
            isMain = streamReadBool(streamId),
            balance = math.max(0, readNumber(streamId, 0))
        }
        table.insert(data.accounts, account)
    end

    data.nextSavingsId = math.max(1, streamReadInt32(streamId))
    local savingsCount = math.max(0, math.min(streamReadInt32(streamId), VillageBankNetwork.MAX_NETWORK_SAVINGS))
    for i = 1, savingsCount do
        table.insert(data.savingsDeposits, {
            id = streamReadInt32(streamId),
            balance = math.max(0, readNumber(streamId, 0)),
            principal = math.max(0, readNumber(streamId, 0)),
            years = math.max(1, streamReadInt32(streamId)),
            annualRate = math.max(0, readNumber(streamId, 0.01)),
            startDay = math.max(0, streamReadInt32(streamId)),
            maturityDay = math.max(0, streamReadInt32(streamId))
        })
    end

    data.nextFinanceId = math.max(1, streamReadInt32(streamId))
    local loanCount = math.max(0, math.min(streamReadInt32(streamId), VillageBankNetwork.MAX_NETWORK_FINANCINGS))
    for i = 1, loanCount do
        table.insert(data.loans, {
            id = streamReadInt32(streamId),
            label = safeString(streamReadString(streamId), 96),
            vehicleId = safeString(streamReadString(streamId), 160),
            vehicleName = safeString(streamReadString(streamId), 128),
            vehicleConfigFile = safeString(streamReadString(streamId), 256),
            price = math.max(0, readNumber(streamId, 0)),
            annualRate = math.max(0, readNumber(streamId, 0)),
            downPayment = math.max(0, readNumber(streamId, 0)),
            balloon = math.max(0, readNumber(streamId, 0)),
            monthlyRate = math.max(0, readNumber(streamId, 0)),
            monthsTotal = math.max(0, streamReadInt32(streamId)),
            monthsLeft = math.max(0, streamReadInt32(streamId)),
            outstanding = math.max(0, readNumber(streamId, 0)),
            paymentAccountId = streamReadInt32(streamId),
            paymentAccountName = safeString(streamReadString(streamId), 64),
            arrearsCount = math.max(0,streamReadInt32(streamId)),
            status = safeString(streamReadString(streamId),32)
        })
    end

    data.nextLeaseId = math.max(1, streamReadInt32(streamId))
    local leaseCount = math.max(0, math.min(streamReadInt32(streamId), VillageBankNetwork.MAX_NETWORK_LEASES))
    for i = 1, leaseCount do
        table.insert(data.leases, {
            id = streamReadInt32(streamId),
            label = safeString(streamReadString(streamId), 96),
            vehicleId = safeString(streamReadString(streamId), 160),
            vehicleName = safeString(streamReadString(streamId), 128),
            vehicleConfigFile = safeString(streamReadString(streamId), 256),
            price = math.max(0, readNumber(streamId, 0)),
            downPayment = math.max(0, readNumber(streamId, 0)),
            monthlyRate = math.max(0, readNumber(streamId, 0)),
            residual = math.max(0, readNumber(streamId, 0)),
            monthsTotal = math.max(0, streamReadInt32(streamId)),
            monthsLeft = math.max(0, streamReadInt32(streamId)),
            status = safeString(streamReadString(streamId), 32),
            paymentAccountId = streamReadInt32(streamId),
            paymentAccountName = safeString(streamReadString(streamId), 64),
            arrearsCount = math.max(0,streamReadInt32(streamId))
        })
    end

    local transactionCount = math.max(0, math.min(streamReadInt32(streamId), VillageBankNetwork.MAX_NETWORK_TRANSACTIONS))
    for i = 1, transactionCount do
        table.insert(data.transactions, {
            transactionType = safeString(streamReadString(streamId), 64),
            source = safeString(streamReadString(streamId), 96),
            target = safeString(streamReadString(streamId), 96),
            amount = readNumber(streamId, 0),
            day = math.max(0, streamReadInt32(streamId))
        })
    end

    data.savings = 0
    for _, deposit in ipairs(data.savingsDeposits) do
        data.savings = data.savings + (deposit.balance or 0)
    end
    return farmId, data
end

local function getConnectionFarmId(connection)
    if g_currentMission == nil or connection == nil then return nil end
    if g_currentMission.getPlayerByConnection ~= nil then
        local player = g_currentMission:getPlayerByConnection(connection)
        if player ~= nil and player.farmId ~= nil then return player.farmId end
    end
    if connection.farmId ~= nil then return connection.farmId end
    return nil
end

local function getFarmLoan(farmId)
    local farm = g_farmManager ~= nil and g_farmManager:getFarmById(farmId) or nil
    return farm ~= nil and math.max(0, tonumber(farm.loan) or 0) or 0
end

local function setFarmLoan(farmId, desiredLoan)
    local farm = g_farmManager ~= nil and g_farmManager:getFarmById(farmId) or nil
    if farm == nil then return end
    local maxLoan = 500000
    if farm.getLoanMax ~= nil then
        local ok, value = pcall(farm.getLoanMax, farm)
        if ok and tonumber(value) ~= nil then maxLoan = tonumber(value) end
    elseif tonumber(farm.loanMax or farm.maxLoan) ~= nil then
        maxLoan = tonumber(farm.loanMax or farm.maxLoan)
    end
    farm.loan = math.max(0, math.min(tonumber(desiredLoan) or 0, maxLoan))
end

local function getFarmMoney(farmId)
    local farm = g_farmManager ~= nil and g_farmManager:getFarmById(farmId) or nil
    return farm ~= nil and tonumber(farm.money) or 0
end

local function applyFarmMoney(farmId, desiredMoney)
    if g_currentMission == nil or g_currentMission.addMoney == nil then return end
    local currentMoney = getFarmMoney(farmId)
    local targetMoney = math.max(0, tonumber(desiredMoney) or currentMoney)
    local delta = targetMoney - currentMoney
    if math.abs(delta) >= 0.005 then
        g_currentMission:addMoney(delta, farmId, MoneyType.OTHER, true, true)
    end
end

local function processServerLeaseReturns(bank, farmId, oldData, newData)
    if bank == nil or oldData == nil or newData == nil then return end
    local oldStatuses = {}
    for _, lease in ipairs(oldData.leases or {}) do oldStatuses[tostring(lease.id)] = lease.status end
    local previousFarmId = bank.networkFarmId
    bank.networkFarmId = farmId
    for _, lease in ipairs(newData.leases or {}) do
        if lease.status == "returned" and oldStatuses[tostring(lease.id)] ~= "returned" then
            local vehicle = bank:findVehicleForLease(lease)
            if vehicle ~= nil and vehicle.delete ~= nil then vehicle:delete() end
        end
    end
    bank.networkFarmId = previousFarmId
end

local function hasUnchangedDunningState(oldData,newData)
    if oldData==nil then return true end
    for _,field in ipairs({"loans","leases"}) do
        local incoming={}
        for _,contract in ipairs(newData[field] or {}) do incoming[contract.id]=contract end
        for _,old in ipairs(oldData[field] or {}) do
            local current=incoming[old.id]
            if current==nil then return false end
            if (current.arrearsCount or 0)~=(old.arrearsCount or 0) or current.monthsLeft~=old.monthsLeft then return false end
            if old.status=="repossessed" and (current.status~="repossessed" or current.vehicleId~=old.vehicleId) then return false end
            if current.status=="repossessed" and old.status~="repossessed" then return false end
            if field=="leases" and old.status=="active" and current.status~="active" then return false end
        end
    end
    return true
end

VillageBankStateEvent = {}
local VillageBankStateEvent_mt = Class(VillageBankStateEvent, Event)
InitEventClass(VillageBankStateEvent, "VillageBankStateEvent")

function VillageBankStateEvent.emptyNew()
    return Event.new(VillageBankStateEvent_mt)
end

function VillageBankStateEvent.new()
    return VillageBankStateEvent.emptyNew()
end

function VillageBankStateEvent:writeStream(streamId, connection)
    local bank = g_villageBank
    local farms = bank ~= nil and bank.farms or {}
    local farmIds = {}
    for farmId in pairs(farms) do
        if #farmIds >= VillageBankNetwork.MAX_NETWORK_FARMS then break end
        table.insert(farmIds, farmId)
    end
    table.sort(farmIds)
    streamWriteInt32(streamId, #farmIds)
    for _, farmId in ipairs(farmIds) do
        writeFarmData(streamId, farmId, farms[farmId])
        writeNumber(streamId, getFarmLoan(farmId))
    end
end

function VillageBankStateEvent:readStream(streamId, connection)
    self.farms = {}
    self.loans = {}
    local count = math.max(0, math.min(streamReadInt32(streamId), VillageBankNetwork.MAX_NETWORK_FARMS))
    for _ = 1, count do
        local farmId, data = readFarmData(streamId)
        self.farms[farmId] = data
        self.loans[farmId] = readNumber(streamId, 0)
    end
    self:run(connection)
end

function VillageBankStateEvent:run(connection)
    if connection ~= nil and not connection:getIsServer() then return end
    if g_villageBank == nil then return end
    g_villageBank.farms = self.farms or {}
    for farmId, loan in pairs(self.loans or {}) do setFarmLoan(farmId, loan) end
end

VillageBankFarmUpdateEvent = {}
local VillageBankFarmUpdateEvent_mt = Class(VillageBankFarmUpdateEvent, Event)
InitEventClass(VillageBankFarmUpdateEvent, "VillageBankFarmUpdateEvent")

function VillageBankFarmUpdateEvent.emptyNew()
    return Event.new(VillageBankFarmUpdateEvent_mt)
end

function VillageBankFarmUpdateEvent.new(farmId, data, money, loan)
    local self = VillageBankFarmUpdateEvent.emptyNew()
    self.farmId = farmId
    self.data = data
    self.money = money
    self.loan = loan
    return self
end

function VillageBankFarmUpdateEvent:writeStream(streamId, connection)
    writeFarmData(streamId, self.farmId, self.data)
    writeNumber(streamId, self.money or 0)
    writeNumber(streamId, self.loan or 0)
end

function VillageBankFarmUpdateEvent:readStream(streamId, connection)
    self.farmId, self.data = readFarmData(streamId)
    self.money = readNumber(streamId, 0)
    self.loan = readNumber(streamId, 0)
    self:run(connection)
end

function VillageBankFarmUpdateEvent:run(connection)
    if connection == nil or connection:getIsServer() or g_server == nil or g_villageBank == nil then return end
    local connectionFarmId = getConnectionFarmId(connection)
    if connectionFarmId == nil or connectionFarmId <= 0 or connectionFarmId ~= self.farmId then
        Logging.warning("[VillageBank] Rejected multiplayer bank update for farm %s", tostring(self.farmId))
        connection:sendEvent(VillageBankStateEvent.new())
        return
    end
    if g_farmManager == nil or g_farmManager:getFarmById(self.farmId) == nil then return end

    local oldData = g_villageBank.farms[self.farmId]
    if (oldData~=nil and (self.data.revision or 0)~=(oldData.revision or 0)) or not hasUnchangedDunningState(oldData,self.data) then
        connection:sendEvent(VillageBankStateEvent.new())
        return
    end
    g_villageBank.farms[self.farmId] = self.data
    g_villageBank:ensureSavingsData(self.data)
    g_villageBank:ensureMainAccount(self.data, self.farmId)
    g_villageBank:ensureFinancingData(self.data)
    g_villageBank:ensureLeasingData(self.data)
    processServerLeaseReturns(g_villageBank, self.farmId, oldData, self.data)
    applyFarmMoney(self.farmId, self.money)
    setFarmLoan(self.farmId, self.loan)
    g_villageBank:saveState(nil, false)
end

function VillageBankNetwork.sendFarmUpdate(bank)
    if bank == nil or g_client == nil or g_server ~= nil then return end
    local farmId = bank:getFarmId()
    if farmId == nil or farmId <= 0 then return end
    local data = bank:getFarmData(farmId)
    local farm = g_farmManager ~= nil and g_farmManager:getFarmById(farmId) or nil
    local money = farm ~= nil and (tonumber(farm.money) or 0) or 0
    local loan = farm ~= nil and (tonumber(farm.loan) or 0) or 0
    local connection = g_client:getServerConnection()
    if connection ~= nil then connection:sendEvent(VillageBankFarmUpdateEvent.new(farmId, data, money, loan)) end
end

VillageBankArrearsPaymentEvent = {}
local VillageBankArrearsPaymentEvent_mt = Class(VillageBankArrearsPaymentEvent, Event)
InitEventClass(VillageBankArrearsPaymentEvent, "VillageBankArrearsPaymentEvent")

function VillageBankArrearsPaymentEvent.emptyNew()
    return Event.new(VillageBankArrearsPaymentEvent_mt)
end

function VillageBankArrearsPaymentEvent.new(kind,id,farmId)
    local self=VillageBankArrearsPaymentEvent.emptyNew()
    self.kind=kind; self.id=id; self.farmId=farmId
    return self
end

function VillageBankArrearsPaymentEvent:writeStream(streamId,connection)
    streamWriteBool(streamId,self.kind=="finance")
    streamWriteInt32(streamId,self.id)
    streamWriteInt32(streamId,self.farmId)
end

function VillageBankArrearsPaymentEvent:readStream(streamId,connection)
    self.kind=streamReadBool(streamId) and "finance" or "lease"
    self.id=streamReadInt32(streamId)
    self.farmId=streamReadInt32(streamId)
    self:run(connection)
end

function VillageBankArrearsPaymentEvent:run(connection)
    if connection==nil or connection:getIsServer() or g_server==nil or g_villageBank==nil then return end
    if self.farmId<=0 or getConnectionFarmId(connection)~=self.farmId then return end
    g_villageBank:settleContractArrears(self.kind,self.id,self.farmId)
end

function VillageBankNetwork.requestArrearsPayment(kind,id,farmId)
    if g_client~=nil and g_server==nil then
        local connection=g_client:getServerConnection()
        if connection~=nil then connection:sendEvent(VillageBankArrearsPaymentEvent.new(kind,id,farmId)) end
    end
end

function VillageBankNetwork.broadcastState()
    if g_server ~= nil then g_server:broadcastEvent(VillageBankStateEvent.new(), false) end
end

function VillageBankNetwork.sendInitialState(connection)
    if connection ~= nil and g_server ~= nil then connection:sendEvent(VillageBankStateEvent.new()) end
end

VillageBankNotificationEvent = {}
local VillageBankNotificationEvent_mt = Class(VillageBankNotificationEvent, Event)
InitEventClass(VillageBankNotificationEvent, "VillageBankNotificationEvent")

function VillageBankNotificationEvent.emptyNew()
    return Event.new(VillageBankNotificationEvent_mt)
end

function VillageBankNotificationEvent.new(message, isCritical, farmId)
    local self = VillageBankNotificationEvent.emptyNew()
    self.message = safeString(message, 768)
    self.isCritical = isCritical == true
    self.farmId = math.floor(tonumber(farmId) or 0)
    return self
end

function VillageBankNotificationEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.message or "")
    streamWriteBool(streamId, self.isCritical == true)
    streamWriteInt32(streamId, self.farmId or 0)
end

function VillageBankNotificationEvent:readStream(streamId, connection)
    self.message = safeString(streamReadString(streamId), 768)
    self.isCritical = streamReadBool(streamId)
    self.farmId = streamReadInt32(streamId)
    self:run(connection)
end

function VillageBankNotificationEvent:run(connection)
    if connection ~= nil and not connection:getIsServer() then return end
    local bank = g_villageBank
    if bank == nil or self.farmId <= 0 or bank:getFarmId() ~= self.farmId then return end
    bank:setStatus(self.message)
    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil and FSBaseMission ~= nil then
        local notificationType = self.isCritical and FSBaseMission.INGAME_NOTIFICATION_CRITICAL or FSBaseMission.INGAME_NOTIFICATION_INFO
        if notificationType ~= nil then
            g_currentMission:addIngameNotification(notificationType, "Dorfbank: " .. self.message)
        end
    end
end

function VillageBankNetwork.broadcastNotification(message, isCritical, farmId)
    if g_server ~= nil and farmId ~= nil and farmId > 0 then
        g_server:broadcastEvent(VillageBankNotificationEvent.new(message, isCritical, farmId), false)
    end
end

if FSBaseMission ~= nil and FSBaseMission.sendInitialClientState ~= nil and not VillageBankNetwork.initialStateHookInstalled then
    VillageBankNetwork.initialStateHookInstalled = true
    FSBaseMission.sendInitialClientState = Utils.appendedFunction(FSBaseMission.sendInitialClientState, function(mission, connection, ...)
        VillageBankNetwork.sendInitialState(connection)
    end)
end
