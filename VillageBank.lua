-- ============================================================
-- FS25_VillageBank.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

VillageBank = {}
local VillageBank_mt = Class(VillageBank)

VillageBank.MAX_ACCOUNTS = 10
VillageBank.MAX_ADDITIONAL_ACCOUNTS = 9
VillageBank.ACCOUNT_VISIBLE_ROWS = 8
VillageBank.TRANSACTION_VISIBLE_ROWS = 10
VillageBank.ACTION_BUTTON_Y = 0.172
VillageBank.ACTION_BUTTON_SECOND_Y = 0.131
VillageBank.SECONDS_PER_YEAR = 365 * 24 * 60 * 60

function VillageBank.new()
    local self = setmetatable({}, VillageBank_mt)
    self.isOpen = false
    self.isMenuPageOpen = false
    self.farms = {}
    self.selectedTab = 1
    self.selectedRow = 1
    self.accountScrollOffset = 0
    self.transactionScrollOffset = 0
    self.transferSourceIndex = nil
    self.transferTargetIndex = nil
    self.transferAmount = 0
    self.transferFormOpen = false
    self.previousMouseCursor = false
    self.pendingDeleteId = nil
    self.statusMessage = nil
    self.renameFormOpen = false
    self.activeTextField = nil
    self.textBuffer = ""
    self.inputContextActive = false
    self.pendingShopAbortMessage = nil
    self.shopContractContext = nil
    self.pendingShopContractOpen = nil
    self.pendingShopContractDelay = nil
    self.pendingVehicleContractBinding = nil
    self.pendingGameplayRestore = nil
    self.openedFromShopContract = false
    self.lastDay = nil
    self.actionEvents = {}
    self.keyState = {}
    self.suppressRawToggle = false
    self.modDirectory = g_currentModDirectory
    return self
end

function VillageBank:keyPressedOnce(key)
    if key == nil then return false end
    local down = Input.isKeyPressed(key)
    local pressed = down and not self.keyState[key]
    self.keyState[key] = down
    return pressed
end

function VillageBank:loadMap()
    if g_currentMission == nil then return end
    self:loadState()
    self.lastDay = g_currentMission.environment.currentDay
    self:installShopAccountDialog()
    print("[VillageBank] Bank system loaded")
end

function VillageBank:installShopAccountDialog()
    if BuyVehicleData == nil or OptionDialog == nil or VillageBank.shopAccountDialogInstalled then return end
    VillageBank.shopAccountDialogInstalled = true
    VillageBank.originalBuyVehicle = BuyVehicleData.buy
    BuyVehicleData.buy = function(buyData, ...)
        local bank = g_villageBank
        local data = bank ~= nil and bank:getFarmData(buyData.ownerFarmId) or nil
        if bank == nil or data == nil or buyData.leaseVehicle then
            return VillageBank.originalBuyVehicle(buyData, ...)
        end

        local arguments = {...}
        local price = math.floor(buyData.price or 0)
        local storeItem = buyData.storeItem or {}
        local vehicleName = storeItem.name or storeItem.customEnvironment or "Fahrzeug"
        local vehicleConfigFile = storeItem.xmlFilename
        local vehicleId = tostring(vehicleConfigFile or vehicleName).."#"..tostring(data.nextFinanceId or 1).."-"..tostring(data.nextLeaseId or 1)

        local function showAccountSelection()
            if #data.accounts <= 1 then return VillageBank.originalBuyVehicle(buyData, unpack(arguments)) end
            local options = {}
            for _, account in ipairs(data.accounts) do
                table.insert(options, string.format("%s  ·  %s", account.name,
                    g_i18n:formatMoney(bank:getAccountBalance(account, buyData.ownerFarmId), 0, true, true)))
            end
            local function accountSelected(index)
                index = tonumber(index)
                if index == nil or index < 1 or index > #data.accounts then bank.pendingShopAbortMessage=false; return end
                local account=data.accounts[index]
                if not account.isMain then
                    if bank:getAccountBalance(account,buyData.ownerFarmId)<price then bank.pendingShopAbortMessage="Das ausgewählte Konto ist nicht ausreichend gedeckt."; return end
                    if not bank:debitAccount(account,price,buyData.ownerFarmId) then return end
                    bank:creditAccount(data.accounts[1],price,buyData.ownerFarmId); bank:addTransaction(data,"Shopkauf",account.name,"Hofkonto",-price)
                    bank:saveState()
                end
                return VillageBank.originalBuyVehicle(buyData,unpack(arguments))
            end
            OptionDialog.show(accountSelected,"Dorfbank · Einkaufskonto","Von welchem Konto soll dieser Kauf bezahlt werden?",options)
        end

        local function paymentSelected(index)
            index=tonumber(index)
            if index==1 then return showAccountSelection() end
            if index~=2 and index~=3 then bank.pendingShopAbortMessage=false; return end
            local kind=index==2 and "finance" or "lease"
            bank.shopContractContext={kind=kind,buyData=buyData,arguments=arguments,price=price,vehicle={id=vehicleId,name=vehicleName,configFile=vehicleConfigFile}}
            bank.pendingShopContractOpen=kind
            bank.pendingShopContractDelay=nil
        end
        OptionDialog.show(paymentSelected,"Dorfbank · Zahlungsart","Wie soll "..vehicleName.." bezahlt werden?",{"Direktkauf","Finanzierung","Leasing"})
    end
end

function VillageBank:finishShopContractPurchase()
    local context=self.shopContractContext
    if context==nil then return false end
    local existing={}
    for _,vehicle in ipairs(self:getMissionVehicles()) do existing[vehicle]=true end
    if self.pendingVehicleContractBinding~=nil then
        self.pendingVehicleContractBinding.existing=existing
        self.pendingVehicleContractBinding.configFile=context.vehicle~=nil and context.vehicle.configFile or nil
    end
    self:closeShopContractOverlay()
    VillageBank.originalBuyVehicle(context.buyData,unpack(context.arguments or {}))
    return true
end

function VillageBank:getShopContractLockedTab()
    if self.shopContractContext==nil then return nil end
    return self.shopContractContext.kind=="finance" and 3 or 4
end

function VillageBank:closeBankSubMenus()
    self.transferFormOpen=false
    self.savingsTransferFormOpen=false
    self.financeFormOpen=false
    self.leaseFormOpen=false
    self.renameFormOpen=false
    self.activeTextField=nil
    self.textBuffer=""
    self.pendingDeleteId=nil
end

function VillageBank:getMissionVehicles()
    if g_currentMission==nil then return {} end
    if g_currentMission.vehicleSystem~=nil and g_currentMission.vehicleSystem.vehicles~=nil then return g_currentMission.vehicleSystem.vehicles end
    return g_currentMission.vehicles or {}
end

function VillageBank:getVehicleUniqueId(vehicle)
    if vehicle==nil then return nil end
    local id=vehicle.uniqueId
    if vehicle.getUniqueId~=nil then
        local ok,value=pcall(vehicle.getUniqueId,vehicle)
        if ok and value~=nil then id=value end
    end
    return id~=nil and tostring(id) or nil
end

local function normalizeConfigFile(filename)
    return string.lower(tostring(filename or "")):gsub("\\","/")
end

function VillageBank:bindPendingVehicleContract()
    local pending=self.pendingVehicleContractBinding
    if pending==nil then return end
    local wanted=normalizeConfigFile(pending.configFile)
    for _,vehicle in ipairs(self:getMissionVehicles()) do
        if not pending.existing[vehicle] then
            local owner=vehicle.getOwnerFarmId~=nil and vehicle:getOwnerFarmId() or vehicle.ownerFarmId
            local actual=normalizeConfigFile(vehicle.configFileName or (vehicle.xmlFile~=nil and vehicle.xmlFile.filename))
            if owner==self:getFarmId() and (wanted=="" or actual==wanted) then
                local id=self:getVehicleUniqueId(vehicle)
                if id~=nil then
                    pending.contract.vehicleId=id
                    pending.contract.vehicleConfigFile=pending.configFile
                    self.pendingVehicleContractBinding=nil
                    self:saveState()
                    return
                end
            end
        end
    end
end

function VillageBank:getVehicleContractLabel(vehicle)
    local id=self:getVehicleUniqueId(vehicle)
    if id==nil then return nil end
    local data=self:getFarmData()
    for _,loan in ipairs(data.loans or {}) do
        if (loan.monthsLeft or 0)>0 and tostring(loan.vehicleId or "")==id then return "Finanziert" end
    end
    for _,lease in ipairs(data.leases or {}) do
        if (lease.status=="active" or lease.status=="purchaseOption") and tostring(lease.vehicleId or "")==id then return "Leasing" end
    end
    return nil
end

function VillageBank:getVehicleLeaseStatus(vehicle)
    local id=self:getVehicleUniqueId(vehicle)
    local data=self:getFarmData()
    for _,lease in ipairs(data.leases or {}) do
        if id~=nil and tostring(lease.vehicleId or "")==id then return lease.status,lease end
    end
    if self.findVehicleForLease~=nil then
        for _,lease in ipairs(data.leases or {}) do
            if lease.status=="active" or lease.status=="purchaseOption" then
                local contractVehicle=self:findVehicleForLease(lease)
                if contractVehicle~=nil and self:isSameVehicle(vehicle,contractVehicle) then
                    if id~=nil and tostring(lease.vehicleId or "")~=id then
                        lease.vehicleId=id
                    end
                    return lease.status,lease
                end
            end
        end
    end
    return nil,nil
end

function VillageBank:isVehicleBlockedByLease(vehicle)
    local status=self:getVehicleLeaseStatus(vehicle)
    return status=="purchaseOption"
end

function VillageBank:isSameVehicle(a,b)
    if a==nil or b==nil then return false end
    if a==b then return true end
    local rootA=a.rootVehicle or (a.getRootVehicle~=nil and a:getRootVehicle()) or a
    local rootB=b.rootVehicle or (b.getRootVehicle~=nil and b:getRootVehicle()) or b
    return rootA==rootB
end

function VillageBank:decorateVehicleInfoBox(vehicle,box)
    local label=self:getVehicleContractLabel(vehicle)
    if label==nil or box==nil then return end
    local lines=box.lines or box.activeLines
    if lines==nil then return end
    for _,line in ipairs(lines) do
        local key=string.lower(tostring(line.key or ""))
        if key:find("gehört",1,true)~=nil or key:find("gehort",1,true)~=nil or key:find("owned",1,true)~=nil or key:find("belongs",1,true)~=nil then
            local value=tostring(line.value or "")
            if value:find("("..label..")",1,true)==nil then line.value=value.." ("..label..")" end
            return
        end
    end
end

function VillageBank:installVehicleInfoHooks()
    for _,vehicle in ipairs(self:getMissionVehicles()) do
        if vehicle.showInfo~=nil and not vehicle.villageBankInfoHooked then
            local original=vehicle.showInfo
            vehicle.showInfo=function(v,box,...)
                original(v,box,...)
                if g_villageBank~=nil then g_villageBank:decorateVehicleInfoBox(v,box) end
            end
            vehicle.villageBankInfoHooked=true
        end
        if vehicle.getIsEnterable~=nil and not vehicle.villageBankEnterHooked then
            local originalGetIsEnterable=vehicle.getIsEnterable
            vehicle.getIsEnterable=function(v,...)
                if g_villageBank~=nil and g_villageBank:isVehicleBlockedByLease(v) then return false end
                return originalGetIsEnterable(v,...)
            end
            vehicle.villageBankEnterHooked=true
        end
        if vehicle.getIsTabbable~=nil and not vehicle.villageBankTabHooked then
            local originalGetIsTabbable=vehicle.getIsTabbable
            vehicle.getIsTabbable=function(v,...)
                if g_villageBank~=nil and g_villageBank:isVehicleBlockedByLease(v) then return false end
                return originalGetIsTabbable(v,...)
            end
            vehicle.villageBankTabHooked=true
        end
        if vehicle.getDistanceToNode~=nil and not vehicle.villageBankInteractionDistanceHooked then
            local originalGetDistanceToNode=vehicle.getDistanceToNode
            vehicle.getDistanceToNode=function(v,node,...)
                if g_villageBank~=nil and g_villageBank:isVehicleBlockedByLease(v) then return math.huge end
                return originalGetDistanceToNode(v,node,...)
            end
            vehicle.villageBankInteractionDistanceHooked=true
        end
        if vehicle.interact~=nil and not vehicle.villageBankInteractHooked then
            local originalInteract=vehicle.interact
            vehicle.interact=function(v,player,...)
                if g_villageBank~=nil and g_villageBank:isVehicleBlockedByLease(v) then
                    g_villageBank:showBankNotification("Leasing abgelaufen: Fahrzeug zuerst übernehmen oder zurückgeben.",true,g_villageBank:getFarmId())
                    return
                end
                return originalInteract(v,player,...)
            end
            vehicle.villageBankInteractHooked=true
        end
    end
end

function VillageBank:enforceLeaseVehicleStates()
    local data=self:getFarmData()
    for _,lease in ipairs(data.leases or {}) do
        if lease.status=="purchaseOption" then
            local vehicle=self:findVehicleForLease(lease)
            if vehicle~=nil and g_currentMission~=nil and self:isSameVehicle(g_currentMission.controlledVehicle,vehicle) and g_localPlayer~=nil and g_localPlayer.leaveVehicle~=nil then
                g_localPlayer:leaveVehicle(nil,true)
                self:setStatus("Leasing abgelaufen: Bitte Fahrzeug übernehmen oder zurückgeben.")
            end
        elseif lease.status=="returned" and not lease.returnDeletionRequested then
            local vehicle=self:findVehicleForLease(lease)
            if vehicle~=nil then
                lease.returnDeletionRequested=true
                vehicle:delete()
            end
        end
    end
end

function VillageBank:closeShopContractOverlay()
    self.shopContractContext=nil
    self.pendingShopContractOpen=nil; self.pendingShopContractDelay=nil
    self.financeFormOpen=false; self.leaseFormOpen=false
    self.activeTextField=nil; self.textBuffer=""
    self.openedFromShopContract=false
    self.isOpen=self.isMenuPageOpen
end

function VillageBank:cancelShopContract()
    self:closeShopContractOverlay()
end

function VillageBank:restoreGameplayInput()
    if g_inputBinding==nil then return end
    local contextName=nil
    if g_currentMission~=nil and g_currentMission.controlledVehicle~=nil and Vehicle~=nil then contextName=Vehicle.INPUT_CONTEXT_NAME end
    if contextName==nil and PlayerInputComponent~=nil then contextName=PlayerInputComponent.INPUT_CONTEXT_NAME end
    if contextName~=nil then g_inputBinding:setContext(contextName,false,true) end
    if g_localPlayer~=nil and g_localPlayer.inputComponent~=nil and g_localPlayer.inputComponent.makeCurrent~=nil and (g_currentMission==nil or g_currentMission.controlledVehicle==nil) then
        g_localPlayer.inputComponent:makeCurrent()
    end
    g_inputBinding:setShowMouseCursor(false,true)
end

function VillageBank:deleteMap()
    if g_inputBinding ~= nil and self.isOpen then g_inputBinding:setShowMouseCursor(false) end
    self:unregisterActions()
    self.farms = {}
end

function VillageBank:registerActions()
    if g_inputBinding == nil then return end
    local inputAction = InputAction ~= nil and InputAction.VILLAGEBANK_TOGGLE or nil
    if inputAction == nil then
        Logging.warning("[VillageBank] InputAction.VILLAGEBANK_TOGGLE is missing; raw Alt+B fallback remains active")
        return
    end
    local _, eventId = g_inputBinding:registerActionEvent(inputAction, self, self.onToggle, false, true, false, true)
    if eventId ~= nil then
        g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_HIGH)
        g_inputBinding:setActionEventTextVisibility(eventId, true)
        table.insert(self.actionEvents, eventId)
        print("[VillageBank] Alt+B action registered")
    else
        Logging.warning("[VillageBank] Failed to register Alt+B action; raw fallback remains active")
    end

    local createAction = InputAction.VILLAGEBANK_CREATE_ACCOUNT
    if createAction ~= nil then
        local _, createEventId = g_inputBinding:registerActionEvent(createAction, self, self.onCreateAccountAction, false, true, false, true)
        if createEventId ~= nil then
            g_inputBinding:setActionEventTextVisibility(createEventId, false)
            table.insert(self.actionEvents, createEventId)
        end
    end
end

function VillageBank:unregisterActions()
    if g_inputBinding == nil then return end
    for _, eventId in ipairs(self.actionEvents) do
        g_inputBinding:removeActionEvent(eventId)
    end
    self.actionEvents = {}
end

function VillageBank:onToggle(_, inputValue)
    if inputValue == 0 then return end
    self.suppressRawToggle = true
    self:setOpen(not self.isOpen)
end

function VillageBank:setOpen(open)
    if self.isOpen == open then return end
    self.isOpen = open
    if open then
        self:getFarmData(self:getFarmId())
        if g_inputBinding ~= nil then
            self.previousMouseCursor=g_inputBinding:getShowMouseCursor()
            g_inputBinding:setShowMouseCursor(true, true)
            if not self.openedFromShopContract then
                local context = Gui ~= nil and Gui.INPUT_CONTEXT_MENU or "MENU"
                g_inputBinding:setContext(context)
                self.inputContextActive = true
            end
        end
    else
        local wasShopContract=self.openedFromShopContract
        self.shopContractContext = nil
        self.transferFormOpen = false
        self.savingsTransferFormOpen = false
        self.financeFormOpen = false
        self.leaseFormOpen = false
        self.renameFormOpen = false
        self.activeTextField = nil
        if g_inputBinding ~= nil then
            if self.inputContextActive then g_inputBinding:revertContext(); self.inputContextActive = false end
            local restoreCursor=self.previousMouseCursor
            g_inputBinding:setShowMouseCursor(restoreCursor, true)
        end
        self.openedFromShopContract = false
        if wasShopContract then
            self.pendingGameplayRestore={delay=250}
        else
            self:restoreGameplayInput()
        end
    end
end

function VillageBank:onCreateAccountAction(_, inputValue)
    if inputValue ~= 0 and self.isOpen and self.selectedTab == 1 then
        self:createAccount()
    end
end

function VillageBank:getFarmId()
    if self.networkFarmId ~= nil then return self.networkFarmId end
    if g_currentMission ~= nil then
        return g_currentMission:getFarmId()
    end
    return FarmManager.SINGLEPLAYER_FARM_ID or 1
end

function VillageBank:getFarmData(farmId)
    farmId = farmId or self:getFarmId()
    if self.farms[farmId] == nil then
        self.farms[farmId] = {
            accounts = {},
            savings = 0,
            savingsTermYears = 0,
            savingsStartDay = 0,
            savingsMaturityDay = 0,
            loans = {},
            leases = {},
            nextId = 1,
            interestEarned = 0,
            interestPaid = 0,
            transactions = {}
        }
    end
    self:ensureSavingsData(self.farms[farmId])
    self:ensureMainAccount(self.farms[farmId], farmId)
    return self.farms[farmId]
end

function VillageBank:getMapName()
    if g_currentMission == nil then return "" end
    local info = g_currentMission.missionInfo
    return (info ~= nil and (info.mapTitle or info.mapName))
        or g_currentMission.mapTitle or ""
end

function VillageBank:addTransaction(data, transactionType, source, target, amount)
    data.transactions = data.transactions or {}
    self.transactionScrollOffset = 0
    table.insert(data.transactions, 1, {
        transactionType=transactionType,
        source=source or "-",
        target=target or "-",
        amount=amount or 0,
        day=g_currentMission ~= nil and g_currentMission.environment.currentDay or 0
    })
    while #data.transactions > 100 do table.remove(data.transactions) end
end

function VillageBank:createFakeIban(farmId, accountId)
    local seed = ((farmId or 1) * 7919 + (accountId or 1) * 104729) % 100000000
    return string.format("DE%02d 9000 0000 %04d %04d %02d", 10 + seed % 89,
        math.floor(seed / 10000) % 10000, seed % 10000, (farmId or 1) % 100)
end

function VillageBank:ensureMainAccount(data, farmId)
    for _, account in ipairs(data.accounts) do
        if account.isMain then
            if account.iban == nil or account.iban == "" then
                account.iban = self:createFakeIban(farmId, account.id)
            end
            return
        end
    end
    table.insert(data.accounts, 1, {
        id = 0,
        name = "Hofkonto",
        iban = self:createFakeIban(farmId, 0),
        balance = 0,
        isMain = true
    })
end

function VillageBank:getFarmMoney(farmId)
    local farm = g_farmManager ~= nil and g_farmManager:getFarmById(farmId) or nil
    return farm ~= nil and farm.money or 0
end

function VillageBank:changeFarmMoney(amount, farmId)
    if amount == 0 or g_currentMission == nil then return true end
    farmId = farmId or self:getFarmId()
    if amount < 0 and self:getFarmMoney(farmId) + amount < 0 then return false end

    if g_server == nil then
        local farm = g_farmManager ~= nil and g_farmManager:getFarmById(farmId) or nil
        if farm == nil then return false end
        farm.money = (tonumber(farm.money) or 0) + amount
        return true
    end

    g_currentMission:addMoney(amount, farmId, MoneyType.OTHER, true, true)
    return true
end

function VillageBank:createAccount(name)
    local now = g_time or 0
    if self.lastAccountCreateTime ~= nil and now - self.lastAccountCreateTime < 350 then
        return false, "Konto wird bereits erstellt"
    end
    self.lastAccountCreateTime = now
    local data = self:getFarmData()
    if #data.accounts >= self.MAX_ACCOUNTS then return false, "Maximal 10 Konten" end
    local id = data.nextId
    data.nextId = id + 1
    table.insert(data.accounts, {
        id=id,
        name=name or ("Geschäftskonto " .. tostring(#data.accounts)),
        iban=self:createFakeIban(self:getFarmId(), id),
        balance=0,
        isMain=false
    })
    self:saveState()
    return true
end

function VillageBank:getAccountBalance(account, farmId)
    if account == nil then return 0 end
    return account.isMain and self:getFarmMoney(farmId or self:getFarmId()) or account.balance
end

function VillageBank:debitAccount(account, amount, farmId)
    if account == nil or amount <= 0 or self:getAccountBalance(account, farmId) < amount then return false end
    if account.isMain then
        return self:changeFarmMoney(-amount, farmId or self:getFarmId())
    end
    account.balance = account.balance - amount
    return true
end

function VillageBank:creditAccount(account, amount, farmId)
    if account == nil or amount <= 0 then return false end
    if account.isMain then
        return self:changeFarmMoney(amount, farmId or self:getFarmId())
    end
    account.balance = account.balance + amount
    return true
end

function VillageBank:transferMoney(sourceIndex, targetIndex, amount)
    local data = self:getFarmData()
    local source = data.accounts[sourceIndex]
    local target = data.accounts[targetIndex]
    amount = math.floor(tonumber(amount) or 0)
    if source == nil or target == nil or source == target or amount <= 0 then return false, "Ungültige Überweisung" end
    if not self:debitAccount(source, amount, self:getFarmId()) then return false, "Kontostand nicht ausreichend" end
    if not self:creditAccount(target, amount, self:getFarmId()) then
        self:creditAccount(source, amount, self:getFarmId())
        return false, "Überweisung fehlgeschlagen"
    end
    self:addTransaction(data, "Überweisung", source.name, target.name, -amount)
    self:saveState()
    return true
end

function VillageBank:cycleAccountName()
    local account = self:getFarmData().accounts[self.selectedRow]
    if account == nil then return end
    local names = {"Hofkonto", "Betriebsmittel", "Fuhrpark", "Rücklagen", "Steuern", "Lohn & Gehalt", "Ackerbau", "Tierhaltung", "Geschäftskonto"}
    local index = 0
    for i, name in ipairs(names) do if name == account.name then index = i; break end end
    account.name = names[index % #names + 1]
    self:saveState()
end

function VillageBank:openRenameForm()
    local account = self:getFarmData().accounts[self.selectedRow]
    if account == nil then return end
    self.renameFormOpen = true
    self.activeTextField = "rename"
    self.textBuffer = account.name
end

function VillageBank:confirmRenameForm()
    local account = self:getFarmData().accounts[self.selectedRow]
    local name = tostring(self.textBuffer or ""):match("^%s*(.-)%s*$")
    if account ~= nil and name ~= "" then account.name = name; self:saveState() end
    self.renameFormOpen = false
    self.activeTextField = nil
end

function VillageBank:setStatus(message)
    self.statusMessage = message
end

function VillageBank:showBankNotification(message,isCritical,farmId)
    self:setStatus(message)
    if g_server~=nil and VillageBankNetwork~=nil and farmId~=nil then
        VillageBankNetwork.broadcastNotification(message,isCritical,farmId)
    end
    if farmId~=nil and farmId~=self:getFarmId() then return end
    if g_currentMission~=nil and g_currentMission.addIngameNotification~=nil then
        local notificationType=nil
        if FSBaseMission~=nil then
            notificationType=isCritical and FSBaseMission.INGAME_NOTIFICATION_CRITICAL or FSBaseMission.INGAME_NOTIFICATION_INFO
        end
        if notificationType~=nil then
            g_currentMission:addIngameNotification(notificationType,"Dorfbank: "..message)
        end
    end
end

function VillageBank:deleteSelectedAccount()
    local data = self:getFarmData()
    local account = data.accounts[self.selectedRow]
    if account == nil then return end
    if account.isMain then
        self.pendingDeleteId = nil
        self:setStatus("Das Hofkonto kann nicht gelöscht werden.")
        return
    end
    for _, loan in ipairs(data.loans or {}) do
        if loan.paymentAccountId == account.id and (loan.monthsLeft or 0) > 0 then
            self.pendingDeleteId=nil; self:setStatus("Konto ist Zahlkonto einer laufenden Finanzierung."); return
        end
    end
    for _, lease in ipairs(data.leases or {}) do
        if lease.paymentAccountId == account.id and lease.status ~= "purchased" and lease.status ~= "returned" then
            self.pendingDeleteId=nil; self:setStatus("Konto ist Zahlkonto eines Leasingvertrags."); return
        end
    end
    if math.abs(self:getAccountBalance(account, self:getFarmId())) >= 0.01 then
        self.pendingDeleteId = nil
        self:setStatus("Konto hat noch Guthaben. Bitte zuerst vollständig überweisen.")
        return
    end
    if self.pendingDeleteId ~= account.id then
        self.pendingDeleteId = account.id
        self:setStatus("Zum endgültigen Löschen erneut auf 'Konto löschen' klicken.")
        return
    end
    table.remove(data.accounts, self.selectedRow)
    self.selectedRow = math.min(self.selectedRow, #data.accounts)
    self.pendingDeleteId = nil
    self:setStatus("Konto wurde gelöscht.")
    self:saveState()
end

function VillageBank:openTransferForm()
    local data = self:getFarmData()
    if #data.accounts < 2 then return end
    self.transferSourceIndex = 1
    self.transferTargetIndex = self.selectedRow ~= 1 and self.selectedRow or 2
    self.transferAmount = 0
    self.transferFormOpen = true
    self.activeTextField = "amount"
    self.textBuffer = ""
end

function VillageBank:cycleTransferAccount(field, direction)
    local count = #self:getFarmData().accounts
    if count < 2 then return end
    local value = field == "source" and self.transferSourceIndex or self.transferTargetIndex
    value = ((value - 1 + direction) % count) + 1
    if field == "source" then
        self.transferSourceIndex = value
        if self.transferTargetIndex == value then self.transferTargetIndex = value % count + 1 end
    else
        self.transferTargetIndex = value
        if self.transferSourceIndex == value then self.transferSourceIndex = value % count + 1 end
    end
end


function VillageBank:confirmTransferForm()
    self.transferAmount = math.floor(tonumber(self.textBuffer) or 0)
    local ok = self:transferMoney(self.transferSourceIndex, self.transferTargetIndex, self.transferAmount)
    if ok then
        self.transferFormOpen = false
        self.transferAmount = 0
        self.textBuffer = ""
        self.activeTextField = nil
    end
end

function VillageBank:keyEvent(unicode, sym, modifier, isDown)
    if not self.isOpen or self.activeTextField == nil then return false end
    if not isDown then return true end
    local isBackspace = Input.KEY_backspace ~= nil and sym == Input.KEY_backspace
    local isEnter = (Input.KEY_return ~= nil and sym == Input.KEY_return)
        or (Input.KEY_KP_enter ~= nil and sym == Input.KEY_KP_enter)
    if isBackspace then
        self.textBuffer = self.textBuffer:sub(1, math.max(0, #self.textBuffer - 1))
        return true
    elseif isEnter then
        if self.activeTextField == "rename" then
            self:confirmRenameForm()
        elseif self.activeTextField == "savingsAmount" then
            self:confirmSavingsTransferForm()
        elseif self.activeTextField == "financeAmount" then
            self:createVehicleFinance()
        elseif self.activeTextField == "leaseAmount" then
            self:createVehicleLease()
        else
            self:confirmTransferForm()
        end
        return true
    end
    if unicode == nil or unicode < 32 then return true end
    local char = nil
    if unicode <= 255 then char = string.char(unicode)
    elseif unicodeToUtf8 ~= nil then char = unicodeToUtf8(unicode) end
    if char == nil then return true end
    if self.activeTextField == "amount" or self.activeTextField == "savingsAmount" or self.activeTextField == "financeAmount" or self.activeTextField == "leaseAmount" then
        if not char:match("%d") or #self.textBuffer >= 12 then return true end
    elseif #self.textBuffer >= 28 then return true end
    self.textBuffer = self.textBuffer .. char
    return true
end

function VillageBank:processDay(processedDay)
    for farmId, data in pairs(self.farms) do
        local day = processedDay or g_currentMission.environment.currentDay
        self:processSavingsDay(data, day)
        local daysPerMonth = math.max(1, self:getSavingsDaysPerYear() / 12)
        if day % daysPerMonth == 0 then
            self:processFinancingMonth(data, farmId)
            self:processLeasingMonth(data, farmId)
        end
    end
end

function VillageBank:update(dt)
    if g_currentMission == nil or g_currentMission.environment == nil then return end
    if self.pendingShopAbortMessage ~= nil then
        local message = self.pendingShopAbortMessage
        self.pendingShopAbortMessage = nil
        if g_gui ~= nil and g_gui.closeAllDialogs ~= nil then g_gui:closeAllDialogs() end
        if message ~= false and InfoDialog ~= nil then InfoDialog.show(message) end
    end
    if self.pendingShopContractOpen~=nil then
        if self.pendingShopContractDelay==nil then
            if g_gui~=nil and g_gui.closeAllDialogs~=nil then g_gui:closeAllDialogs() end
            self.pendingShopContractDelay=180
        else
            self.pendingShopContractDelay=self.pendingShopContractDelay-dt
            if self.pendingShopContractDelay<=0 then
                local kind=self.pendingShopContractOpen
                self.pendingShopContractOpen=nil; self.pendingShopContractDelay=nil
                local opened=VillageBankMenu~=nil and VillageBankMenu.openBankPage~=nil and VillageBankMenu:openBankPage(kind=="finance" and 3 or 4)
                if opened then
                    self.selectedTab=kind=="finance" and 3 or 4
                    if kind=="finance" then self:openFinanceForm() else self:openLeaseForm() end
                    self.textBuffer=tostring(self.shopContractContext~=nil and self.shopContractContext.price or 0)
                else
                    self:setStatus("Dorfbank konnte nicht geöffnet werden. Bitte im ESC-Menü erneut versuchen.")
                    self.shopContractContext=nil
                end
            end
        end
    end
    local day = g_currentMission.environment.currentDay
    local processedBankDay = false
    if self.lastDay ~= nil and day > self.lastDay and g_server ~= nil then
        for processedDay = self.lastDay + 1, day do self:processDay(processedDay) end
        processedBankDay = true
    end
    self.lastDay = day
    if processedBankDay then self:saveState() end

    self:bindPendingVehicleContract()
    self:installVehicleInfoHooks()
    self:enforceLeaseVehicleStates()
    self:enforceDunningStates(dt)
    
    if self.isMenuPageOpen then return end

    if not self.isOpen then return end
    if g_inputBinding~=nil then g_inputBinding:setShowMouseCursor(true,true) end
    if self:keyPressedOnce(Input.KEY_esc) then
        if self.transferFormOpen then self.transferFormOpen = false; self.activeTextField=nil
        elseif self.savingsTransferFormOpen then self.savingsTransferFormOpen=false; self.activeTextField=nil
        elseif self.financeFormOpen then if self.shopContractContext~=nil then self:cancelShopContract() else self.financeFormOpen=false; self.activeTextField=nil end
        elseif self.leaseFormOpen then if self.shopContractContext~=nil then self:cancelShopContract() else self.leaseFormOpen=false; self.activeTextField=nil end
        elseif self.renameFormOpen then self.renameFormOpen=false; self.activeTextField=nil
        else self:setOpen(false) end
    end
    if not self.isOpen then return end
    if self.transferFormOpen or self.savingsTransferFormOpen or self.financeFormOpen or self.leaseFormOpen or self.renameFormOpen then return end
    if self:keyPressedOnce(Input.KEY_1) then self.selectedTab = 1 end
    if self:keyPressedOnce(Input.KEY_2) then self.selectedTab = 2 end
    if self:keyPressedOnce(Input.KEY_3) then self.selectedTab = 3 end
    if self:keyPressedOnce(Input.KEY_4) then self.selectedTab = 4 end
    if self:keyPressedOnce(Input.KEY_5) then self.selectedTab = 5 end
    local createWithPlus = self:keyPressedOnce(Input.KEY_plus)
        or self:keyPressedOnce(Input.KEY_KP_plus)
    if self.selectedTab == 1 then
        local data = self:getFarmData()
        if self:keyPressedOnce(Input.KEY_up) then self.selectedRow = math.max(1, self.selectedRow - 1) end
        if self:keyPressedOnce(Input.KEY_down) then self.selectedRow = math.min(#data.accounts, self.selectedRow + 1) end
        if createWithPlus then
            if self:createAccount() then self.selectedRow = #data.accounts end
        end
        if self:keyPressedOnce(Input.KEY_r) then self:cycleAccountName() end
        if self:keyPressedOnce(Input.KEY_t) then self:openTransferForm() end
    end
end

local function drawText(x, y, size, text, r, g, b, a)
    setTextColor(r or 1, g or 1, b or 1, a or 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
    renderText(x, y, size, text)
end

local function money(value)
    return g_i18n:formatMoney(value or 0, 0, true, true)
end

function VillageBank:drawPanel(x, y, w, h, r, g, b, a)
    drawFilledRect(x, y, w, h, r, g, b, a)
end

function VillageBank:drawButton(x, y, w, h, label, active)
    if active == false then
        self:drawPanel(x, y, w, h, 0.030, 0.035, 0.038, 1)
        self:drawPanel(x, y, 0.003, h, 0.09, 0.10, 0.10, 1)
        drawText(x + 0.012, y + h * 0.29, 0.014, label, 0.43, 0.46, 0.45, 1)
    else
        self:drawPanel(x, y, w, h, 0.045, 0.052, 0.056, 1)
        self:drawPanel(x, y + h - 0.003, w, 0.003, 0.20, 0.40, 0.015, 1)
        self:drawPanel(x, y, 0.004, h, 0.20, 0.40, 0.015, 1)
        drawText(x + 0.012, y + h * 0.29, 0.014, label, 0.95, 0.95, 0.95, 1)
    end
end

function VillageBank:isInside(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

function VillageBank:getAccountScrollOffset(data)
    local count=#(data.accounts or {})
    local visible=self.ACCOUNT_VISIBLE_ROWS or 8
    local maxOffset=math.max(0,count-visible)
    self.accountScrollOffset=math.max(0,math.min(self.accountScrollOffset or 0,maxOffset))

    if self.selectedRow < self.accountScrollOffset+1 then
        self.accountScrollOffset=math.max(0,self.selectedRow-1)
    elseif self.selectedRow > self.accountScrollOffset+visible then
        self.accountScrollOffset=math.min(maxOffset,self.selectedRow-visible)
    end
    return self.accountScrollOffset,maxOffset
end

function VillageBank:setAccountScrollOffset(data,offset)
    local count=#(data.accounts or {})
    local visible=self.ACCOUNT_VISIBLE_ROWS or 8
    local maxOffset=math.max(0,count-visible)
    self.accountScrollOffset=math.max(0,math.min(math.floor((offset or 0)+0.5),maxOffset))

    local first=self.accountScrollOffset+1
    local last=math.min(count,first+visible-1)
    if count>0 then
        if self.selectedRow<first then self.selectedRow=first end
        if self.selectedRow>last then self.selectedRow=last end
    end
end

function VillageBank:scrollAccounts(data,direction)
    local _,maxOffset=self:getAccountScrollOffset(data)
    if maxOffset<=0 then return end
    self:setAccountScrollOffset(data,(self.accountScrollOffset or 0)+(direction or 0))
    self.pendingDeleteId=nil
    self.statusMessage=nil
end

function VillageBank:drawAccountScrollbar(data)
    local count=#(data.accounts or {})
    local visible=self.ACCOUNT_VISIBLE_ROWS or 8
    if count<=visible then return end

    local offset,maxOffset=self:getAccountScrollOffset(data)
    local trackX,trackY,trackW,trackH=0.496,0.298,0.002,0.291
    self:drawPanel(trackX,trackY,trackW,trackH,0.33,0.35,0.35,1)

    local thumbH=math.max(0.050,trackH*math.min(1,visible/count))
    local travel=trackH-thumbH
    local ratio=maxOffset>0 and (offset/maxOffset) or 0
    local thumbY=trackY+travel*(1-ratio)
    self:drawPanel(trackX-0.002,thumbY,trackW+0.004,thumbH,0.60,0.77,0.22,1)
end

function VillageBank:drawAccounts(data, x, y)
    drawText(x, y, 0.019, "GIROKONTEN", 0.88, 0.90, 0.89, 1)
    drawText(x+0.255, y, 0.013, "SALDO", 0.62, 0.66, 0.64, 1)
    y = y - 0.040

    local offset=self:getAccountScrollOffset(data)
    local visible=self.ACCOUNT_VISIBLE_ROWS or 8
    for row=1,visible do
        local i=offset+row
        local account=data.accounts[i]
        if account==nil then break end
        local balance = account.isMain and self:getFarmMoney(self:getFarmId()) or account.balance
        local selected = i == self.selectedRow
        local color = selected and 0.08 or 0.94
        if selected then
            self:drawPanel(x - 0.006, y - 0.018, 0.35, 0.035, 0.20, 0.40, 0.015, 1)
        elseif row % 2 == 0 then self:drawPanel(x - 0.006, y - 0.018, 0.35, 0.035, 0.025, 0.029, 0.032, 1) end
        drawText(x, y, 0.0145, string.format("%02d  %s", i, account.name), color, color, color, 1)
        drawText(x + 0.255, y, 0.0145, money(balance), selected and 0.08 or 0.92, selected and 0.08 or 0.94, selected and 0.08 or 0.92, 1)
        drawText(x + 0.035, y - 0.015, 0.010, account.iban or "", selected and 0.13 or 0.55, selected and 0.16 or 0.59, selected and 0.10 or 0.57, 1)
        y = y - 0.037
    end
    self:drawAccountScrollbar(data)

    if self.statusMessage ~= nil then drawText(0.145, 0.078, 0.0125, self.statusMessage, 0.95, 0.72, 0.30, 1) end
    local topY=self.ACTION_BUTTON_Y or 0.172
    local bottomY=self.ACTION_BUTTON_SECOND_Y or 0.131
    self:drawButton(0.145, topY, 0.165, 0.035, "Konto hinzufügen", #data.accounts < self.MAX_ACCOUNTS)
    self:drawButton(0.320, topY, 0.165, 0.035, "Name wechseln", true)
    self:drawButton(0.145, bottomY, 0.165, 0.035, "Überweisung", #data.accounts >= 2)
    local selected = data.accounts[self.selectedRow]
    local canDelete = selected ~= nil and not selected.isMain
    self:drawButton(0.320, bottomY, 0.165, 0.035, "Konto löschen", canDelete)
end

function VillageBank:drawEscAccountDetails(data)
    local account=data.accounts[self.selectedRow]
    if account==nil then return end
    local balance=self:getAccountBalance(account,self:getFarmId())
    self:drawPanel(0.515,0.180,0.0015,0.450,0.08,0.10,0.10,1)
    drawText(0.545,0.615,0.014,"KONTODETAILS",0.67,0.72,0.70,1)
    self:drawPanel(0.535,0.430,0.365,0.155,0.030,0.036,0.035,1)
    self:drawPanel(0.535,0.582,0.365,0.003,0.20,0.40,0.015,1)
    drawText(0.555,0.545,0.022,account.name,0.95,0.96,0.95,1)
    drawText(0.555,0.515,0.012,account.isMain and "HAUPTKONTO" or "GIROKONTO",0.58,0.63,0.61,1)
    drawText(0.555,0.475,0.011,"AKTUELLER SALDO",0.58,0.63,0.61,1)
    drawText(0.555,0.446,0.023,money(balance),0.32,0.55,0.04,1)
    drawText(0.545,0.390,0.014,"KONTOVERBINDUNG",0.67,0.72,0.70,1)
    self:drawPanel(0.535,0.320,0.365,0.052,0.030,0.036,0.035,1)
    drawText(0.555,0.339,0.013,account.iban or "-",0.88,0.90,0.89,1)
end

function VillageBank:drawTransferForm(data)
    local x, y, w, h = 0.285, 0.265, 0.43, 0.43
    self:drawDialogShell(x,y,w,h,"ÜBERWEISUNG")
    local source = data.accounts[self.transferSourceIndex]
    local target = data.accounts[self.transferTargetIndex]
    drawText(x + 0.03, y + 0.295, 0.014, "VON KONTO", 0.62, 0.7, 0.65, 1)
    self:drawButton(x + 0.03, y + 0.245, 0.04, 0.04, "<", true)
    self:drawPanel(x + 0.08, y + 0.245, 0.27, 0.04, 0.08, 0.11, 0.09, 1)
    drawText(x + 0.095, y + 0.257, 0.015, source ~= nil and source.name or "-")
    self:drawButton(x + 0.36, y + 0.245, 0.04, 0.04, ">", true)
    drawText(x + 0.03, y + 0.205, 0.014, "AN KONTO", 0.62, 0.7, 0.65, 1)
    self:drawButton(x + 0.03, y + 0.155, 0.04, 0.04, "<", true)
    self:drawPanel(x + 0.08, y + 0.155, 0.27, 0.04, 0.08, 0.11, 0.09, 1)
    drawText(x + 0.095, y + 0.167, 0.015, target ~= nil and target.name or "-")
    self:drawButton(x + 0.36, y + 0.155, 0.04, 0.04, ">", true)
    drawText(x + 0.03, y + 0.115, 0.014, "BETRAG", 0.72, 0.76, 0.74, 1)
    self:drawPanel(x + 0.03, y + 0.065, 0.37, 0.042, 0.08, 0.11, 0.09, 1)
    drawText(x + 0.045, y + 0.078, 0.017, self.textBuffer == "" and "Betrag eingeben ..." or self.textBuffer .. " €", self.textBuffer == "" and 0.45 or 1, 1, 1, 1)
    self:drawButton(x + 0.03, y + 0.015, 0.12, 0.038, "Abbrechen", true)
    self:drawButton(x + 0.25, y + 0.015, 0.15, 0.038, "Jetzt überweisen", tonumber(self.textBuffer) ~= nil and tonumber(self.textBuffer) > 0)
end

function VillageBank:drawDialogShell(x,y,w,h,title)
    self:drawPanel(x,y,w,h,0.012,0.015,0.016,1)
    self:drawPanel(x,y+h-0.07,w,0.07,0.030,0.036,0.038,1)
    self:drawPanel(x,y+h-0.003,w,0.003,0.32,0.55,0.04,1)
    drawText(x+0.025,y+h-0.045,0.021,title,0.92,0.94,0.93,1)
end

function VillageBank:drawRenameForm()
    local x, y, w, h = 0.33, 0.36, 0.34, 0.22
    self:drawDialogShell(x,y,w,h,"KONTO UMBENENNEN")
    self:drawPanel(x+0.025,y+0.095,w-0.05,0.045,0.08,0.11,0.09,1)
    drawText(x+0.04,y+0.109,0.017,self.textBuffer .. "|",1,1,1,1)
    self:drawButton(x+0.025,y+0.025,0.11,0.04,"Abbrechen",true)
    self:drawButton(x+w-0.145,y+0.025,0.12,0.04,"Speichern",self.textBuffer~="")
end

function VillageBank:mouseEvent(posX, posY, isDown, isUp, button)
    if self.openedFromShopContract or self.isMenuPageOpen then
        local eventKey=string.format("%.5f:%.5f:%s:%s:%s",posX or 0,posY or 0,tostring(isDown),tostring(isUp),tostring(button))
        local eventTime=g_time or 0
        if self.lastShopMouseEventKey==eventKey and self.lastShopMouseEventTime==eventTime then return end
        self.lastShopMouseEventKey=eventKey; self.lastShopMouseEventTime=eventTime
    end
    local isLeftButton = button == 1 or (Input.MOUSE_BUTTON_LEFT ~= nil and button == Input.MOUSE_BUTTON_LEFT)
    if not self.isOpen then return end
    local data = self:getFarmData()

    local wheelUp = button == 4 or (Input.MOUSE_BUTTON_WHEEL_UP ~= nil and button == Input.MOUSE_BUTTON_WHEEL_UP)
    local wheelDown = button == 5 or (Input.MOUSE_BUTTON_WHEEL_DOWN ~= nil and button == Input.MOUSE_BUTTON_WHEEL_DOWN)
    if isDown then
        if self.selectedTab==1 and not (self.transferFormOpen or self.renameFormOpen) and self:isInside(posX,posY,0.135,0.298,0.368,0.291) then
            if wheelUp then self:scrollAccounts(data,-1); return
            elseif wheelDown then self:scrollAccounts(data,1); return end
        elseif self.selectedTab==2 and not self.savingsTransferFormOpen and self:isInside(posX,posY,0.135,0.246,0.770,0.360) then
            if wheelUp then self:scrollSavings(data,-1); return
            elseif wheelDown then self:scrollSavings(data,1); return end
        elseif self.selectedTab==3 and not self.financeFormOpen and self:isInside(posX,posY,0.135,0.231,0.770,0.375) then
            if wheelUp then self:scrollFinancing(data,-1); return
            elseif wheelDown then self:scrollFinancing(data,1); return end
        elseif self.selectedTab==4 and not self.leaseFormOpen and self:isInside(posX,posY,0.135,0.231,0.770,0.375) then
            if wheelUp then self:scrollLeases(data,-1); return
            elseif wheelDown then self:scrollLeases(data,1); return end
        elseif self.selectedTab==6 and self:isInside(posX,posY,0.135,0.227,0.770,0.334) then
            if wheelUp then self:scrollTransactions(data,-1); return
            elseif wheelDown then self:scrollTransactions(data,1); return end
        end
    end

    if not isUp or not isLeftButton then return end
    if self.transferFormOpen then
        local x, y = 0.285, 0.265
        if self:isInside(posX,posY,x+0.03,y+0.245,0.04,0.04) then self:cycleTransferAccount("source",-1)
        elseif self:isInside(posX,posY,x+0.36,y+0.245,0.04,0.04) then self:cycleTransferAccount("source",1)
        elseif self:isInside(posX,posY,x+0.03,y+0.155,0.04,0.04) then self:cycleTransferAccount("target",-1)
        elseif self:isInside(posX,posY,x+0.36,y+0.155,0.04,0.04) then self:cycleTransferAccount("target",1)
        elseif self:isInside(posX,posY,x+0.03,y+0.065,0.37,0.042) then self.activeTextField="amount"
        elseif self:isInside(posX,posY,x+0.03,y+0.015,0.12,0.038) then self.transferFormOpen=false; self.activeTextField=nil
        elseif self:isInside(posX,posY,x+0.25,y+0.015,0.15,0.038) and tonumber(self.textBuffer) ~= nil and tonumber(self.textBuffer)>0 then self:confirmTransferForm() end
        return
    end
    if self:handleSavingsMouse(posX, posY) then return end
    if self:handleFinancingMouse(posX, posY) then return end
    if self:handleLeasingMouse(posX, posY) then return end
    if self:handleTransactionMouse(posX, posY) then return end
    if self.renameFormOpen then
        local x,y,w=0.33,0.36,0.34
        if self:isInside(posX,posY,x+0.025,y+0.095,w-0.05,0.045) then self.activeTextField="rename"
        elseif self:isInside(posX,posY,x+0.025,y+0.025,0.11,0.04) then self.renameFormOpen=false; self.activeTextField=nil
        elseif self:isInside(posX,posY,x+w-0.145,y+0.025,0.12,0.04) then self:confirmRenameForm() end
        return
    end
    if not self.isMenuPageOpen then
        local tabX = {0.205,0.325,0.445,0.565,0.685}
        for i=1,5 do if self:isInside(posX,posY,tabX[i],0.69,0.115,0.045) then self.selectedTab=i; return end end
    end
    if self.selectedTab == 2 then return end
    if self.selectedTab == 5 then self:handleCreditMouse(posX,posY); return end
    if self.selectedTab ~= 1 then return end
    local offset,maxOffset=self:getAccountScrollOffset(data)
    local visible=self.ACCOUNT_VISIBLE_ROWS or 8
    for row=1,visible do
        local i=offset+row
        if i>#data.accounts then break end
        local rowY = 0.575 - (row-1)*0.037
        if self:isInside(posX,posY,0.135,rowY-0.019,0.35,0.036) then
            self.selectedRow=i; self.pendingDeleteId=nil; self.statusMessage=nil; return
        end
    end
    if maxOffset>0 and self:isInside(posX,posY,0.489,0.298,0.014,0.291) then
        local ratio=math.max(0,math.min(1,(0.589-posY)/0.291))
        self:setAccountScrollOffset(data,ratio*maxOffset)
        self.pendingDeleteId=nil; self.statusMessage=nil; return
    end
    local topY=self.ACTION_BUTTON_Y or 0.172
    local bottomY=self.ACTION_BUTTON_SECOND_Y or 0.131
    if self:isInside(posX,posY,0.145,topY,0.165,0.035) and #data.accounts<self.MAX_ACCOUNTS then
        if self:createAccount() then self.selectedRow=#data.accounts; self:getAccountScrollOffset(data) end
        self.pendingDeleteId=nil; self.statusMessage=nil
    elseif self:isInside(posX,posY,0.320,topY,0.165,0.035) then self:openRenameForm(); self.pendingDeleteId=nil
    elseif self:isInside(posX,posY,0.145,bottomY,0.165,0.035) and #data.accounts>=2 then self:openTransferForm(); self.pendingDeleteId=nil
    elseif self:isInside(posX,posY,0.320,bottomY,0.165,0.035) then self:deleteSelectedAccount() end
end

VillageBank.NEGATIVE_TRANSACTION_TYPES = {
    ["Überweisung"]=true, ["Festgeld"]=true, ["Anzahlung"]=true,
    ["Finanzrate"]=true, ["Schlussrate"]=true, ["Kredittilgung"]=true,
    ["Leasingstart"]=true, ["Leasingrate"]=true, ["Leasingkauf"]=true,
    ["Shopkauf"]=true
}

function VillageBank:getSignedTransactionAmount(transaction)
    local amount=transaction~=nil and (transaction.amount or 0) or 0
    if amount<0 then return amount end
    if transaction~=nil and self.NEGATIVE_TRANSACTION_TYPES[transaction.transactionType or ""] then return -math.abs(amount) end
    return amount
end

function VillageBank:getTransactionScrollOffset(data)
    local count=#(data.transactions or {})
    local visible=self.TRANSACTION_VISIBLE_ROWS or 10
    local maxOffset=math.max(0,count-visible)
    self.transactionScrollOffset=math.max(0,math.min(self.transactionScrollOffset or 0,maxOffset))
    return self.transactionScrollOffset,maxOffset
end

function VillageBank:setTransactionScrollOffset(data,offset)
    local count=#(data.transactions or {})
    local visible=self.TRANSACTION_VISIBLE_ROWS or 10
    local maxOffset=math.max(0,count-visible)
    self.transactionScrollOffset=math.max(0,math.min(math.floor((offset or 0)+0.5),maxOffset))
end

function VillageBank:scrollTransactions(data,direction)
    local _,maxOffset=self:getTransactionScrollOffset(data)
    if maxOffset<=0 then return end
    self:setTransactionScrollOffset(data,(self.transactionScrollOffset or 0)+(direction or 0))
end

function VillageBank:drawTransactionScrollbar(data)
    local count=#(data.transactions or {})
    local visible=self.TRANSACTION_VISIBLE_ROWS or 10
    if count<=visible then return end
    local offset,maxOffset=self:getTransactionScrollOffset(data)
    local trackX,trackY,trackW,trackH=0.895,0.227,0.002,0.334
    self:drawPanel(trackX,trackY,trackW,trackH,0.33,0.35,0.35,1)
    local thumbH=math.max(0.050,trackH*math.min(1,visible/count))
    local travel=trackH-thumbH
    local ratio=maxOffset>0 and (offset/maxOffset) or 0
    local thumbY=trackY+travel*(1-ratio)
    self:drawPanel(trackX-0.002,thumbY,trackW+0.004,thumbH,0.60,0.77,0.22,1)
end

function VillageBank:handleTransactionMouse(posX,posY)
    if self.selectedTab~=6 then return false end
    local data=self:getFarmData()
    local _,maxOffset=self:getTransactionScrollOffset(data)
    if maxOffset>0 and self:isInside(posX,posY,0.888,0.227,0.016,0.334) then
        local ratio=math.max(0,math.min(1,(0.561-posY)/0.334))
        self:setTransactionScrollOffset(data,ratio*maxOffset)
        return true
    end
    return false
end

function VillageBank:drawTransactions(data, x, y)
    drawText(x, y, 0.019, "BUCHUNGEN", 0.88, 0.90, 0.89, 1)
    y = y - 0.045
    drawText(x, y, 0.0135, "TAG     ART                 VON → AN                                      BETRAG", 0.55, 0.65, 0.58, 1)
    y = y - 0.027
    local transactions=data.transactions or {}
    local offset=self:getTransactionScrollOffset(data)
    local visible=self.TRANSACTION_VISIBLE_ROWS or 10
    for row=1,visible do
        local i=offset+row
        local transaction=transactions[i]
        if transaction==nil then break end
        if row%2==0 then self:drawPanel(x-0.006,y-0.010,0.74,0.028,0.025,0.029,0.032,1) end
        drawText(x, y, 0.014, string.format("%03d     %-18s %s → %s", transaction.day or 0, transaction.transactionType=="Finanzierung" and "Finanzierungssumme" or transaction.transactionType or "", transaction.source or "-", transaction.target or "-"))
        local signedAmount=self:getSignedTransactionAmount(transaction)
        if transaction.transactionType=="Finanzierung" or transaction.transactionType=="Finanzierungssumme" or signedAmount==0 then
            drawText(x + 0.63, y, 0.014, signedAmount==0 and "–" or money(math.abs(signedAmount)), 0.68, 0.72, 0.69, 1)
        elseif signedAmount<0 then
            drawText(x + 0.63, y, 0.014, money(math.abs(signedAmount)), 0.88, 0.22, 0.18, 1)
        else
            drawText(x + 0.63, y, 0.014, money(signedAmount), 0.32, 0.55, 0.04, 1)
        end
        y = y - 0.034
    end
    self:drawTransactionScrollbar(data)
    if #transactions == 0 then drawText(x, y, 0.016, "Noch keine Dorfbank-Transaktionen vorhanden.", 0.7, 0.7, 0.7, 1) end
end

function VillageBank:draw()
    if self.isMenuPageOpen then return end
    self:drawBankSurface()
end

function VillageBank:drawBankSurface()
    if not self.isOpen or g_currentMission == nil then return end
    if self.isMenuPageOpen then self:drawEscBankSurface(); return end
    if self.openedFromShopContract then return end
    local x, y, w, h = 0.18, 0.16, 0.64, 0.68
    self:drawPanel(x - 0.006, y - 0.008, w + 0.012, h + 0.016, 0.006, 0.010, 0.009, 0.92)
    self:drawPanel(x - 0.002, y - 0.002, w + 0.004, h + 0.004, 0.38, 0.52, 0.25, 1)
    self:drawPanel(x, y, w, h, 0.022, 0.031, 0.029, 0.992)
    self:drawPanel(x, y + h - 0.09, w, 0.09, 0.035, 0.052, 0.047, 1)
    self:drawPanel(x, y + h - 0.004, w, 0.004, 0.66, 0.86, 0.35, 1)
    self:drawPanel(x, y + h - 0.094, w, 0.004, 0.66, 0.86, 0.35, 1)
    self:drawPanel(x, y, w, 0.055, 0.030, 0.044, 0.040, 1)
    self:drawPanel(x + 0.018, y + h - 0.075, 0.044, 0.050, 0.105, 0.255, 0.190, 1)
    self:drawPanel(x + 0.018, y + h - 0.028, 0.044, 0.003, 0.66, 0.86, 0.35, 1)
    drawText(x + 0.028, y + h - 0.059, 0.019, "DB", 0.90, 0.96, 0.83, 1)
    local mapName = self:getMapName()
    local bankTitle = mapName ~= "" and ("DORFBANK · " .. mapName) or "DORFBANK"
    drawText(x + 0.076, y + h - 0.049, 0.023, bankTitle, 0.94, 0.96, 0.94, 1)
    drawText(x + 0.077, y + h - 0.069, 0.0105, "DIGITALE FILIALE", 0.55, 0.66, 0.59, 1)
    self:drawPanel(x + 0.465, y + h - 0.067, 0.15, 0.043, 0.008, 0.014, 0.012, 1)
    self:drawPanel(x + 0.465, y + h - 0.067, 0.004, 0.043, 0.66, 0.86, 0.35, 1)
    drawText(x + 0.479, y + h - 0.041, 0.0095, "HOFKONTO", 0.53, 0.61, 0.56, 1)
    drawText(x + 0.479, y + h - 0.059, 0.016, money(self:getFarmMoney(self:getFarmId())), 0.78, 0.92, 0.55, 1)

    self:drawPanel(x + 0.018, y + h - 0.151, w - 0.036, 0.055, 0.030, 0.043, 0.039, 1)

    local tabs = {"KONTEN", "SPAREN", "FINANZIERUNG", "LEASING", "KREDIT", "BUCHUNGEN"}
    for i, label in ipairs(tabs) do
        local tx = x + 0.020 + (i - 1) * 0.099
        if i == self.selectedTab then
            self:drawPanel(tx - 0.008, y + h - 0.145, 0.094, 0.045, 0.105, 0.255, 0.190, 1)
            self:drawPanel(tx - 0.008, y + h - 0.103, 0.094, 0.003, 0.66, 0.86, 0.35, 1)
        end
        local c = i == self.selectedTab and 0.95 or 0.58
        drawText(tx, y + h - 0.13, 0.014, label, c, c, c, 1)
    end

    local data = self:getFarmData()
    local contentX, contentY = x + 0.035, y + h - 0.19
    local modalOpen = self.transferFormOpen or self.savingsTransferFormOpen or self.financeFormOpen or self.leaseFormOpen or self.renameFormOpen
    if not modalOpen then
        self:drawPanel(x + 0.020, y + 0.070, w - 0.040, h - 0.235, 0.030, 0.043, 0.039, 0.96)
        self:drawPanel(x + 0.020, y + h - 0.169, w - 0.040, 0.003, 0.30, 0.39, 0.31, 1)
        if self.selectedTab == 1 then self:drawAccounts(data, contentX, contentY)
        elseif self.selectedTab == 2 then self:drawSavings(data, contentX, contentY)
        elseif self.selectedTab == 3 then self:drawLoans(data, contentX, contentY)
        elseif self.selectedTab == 4 then self:drawLeases(data, contentX, contentY)
        elseif self.selectedTab == 5 then self:drawCredit(data, contentX, contentY)
        else self:drawTransactions(data, contentX, contentY) end
    end
    if self.transferFormOpen then self:drawTransferForm(data) end
    if self.savingsTransferFormOpen then self:drawSavingsTransferForm(data) end
    if self.financeFormOpen then self:drawFinanceForm() end
    if self.leaseFormOpen then self:drawLeaseForm() end
    if self.renameFormOpen then self:drawRenameForm() end
    drawText(x + 0.025, y + 0.015, 0.014, "ALT+B / ESC: Schließen", 0.55, 0.55, 0.55, 1)
end

function VillageBank:drawEscBankSurface()
    self:drawPanel(0.125,0.130,0.805,0.535,0.012,0.015,0.016,1)
    self:drawPanel(0.125,0.650,0.805,0.002,0.27,0.30,0.29,1)
    local data=self:getFarmData()
    local modalOpen=self.transferFormOpen or self.savingsTransferFormOpen or self.financeFormOpen or self.leaseFormOpen or self.renameFormOpen
    if not modalOpen then
        if self.selectedTab==1 then self:drawAccounts(data,0.145,0.615); self:drawEscAccountDetails(data)
        elseif self.selectedTab==2 then self:drawSavings(data,0.145,0.615)
        elseif self.selectedTab==3 then self:drawLoans(data,0.145,0.615)
        elseif self.selectedTab==4 then self:drawLeases(data,0.145,0.615)
        elseif self.selectedTab==5 then self:drawCredit(data,0.145,0.615)
        else self:drawTransactions(data,0.145,0.615) end
    end
    if self.transferFormOpen then self:drawTransferForm(data) end
    if self.savingsTransferFormOpen then self:drawSavingsTransferForm(data) end
    if self.financeFormOpen then self:drawFinanceForm() end
    if self.leaseFormOpen then self:drawLeaseForm() end
    if self.renameFormOpen then self:drawRenameForm() end
end

function VillageBank:getSaveFilename(savegameDirectory,legacy)
    if g_currentMission == nil or g_currentMission.missionInfo == nil then return nil end
    local dir = savegameDirectory or g_currentMission.missionInfo.savegameDirectory
    if dir == nil and g_currentMission.missionInfo.savegameIndex ~= nil and getUserProfileAppPath ~= nil then
        dir = getUserProfileAppPath() .. "savegame" .. tostring(g_currentMission.missionInfo.savegameIndex)
    end
    if dir == nil then return nil end
    return dir .. (legacy and "/lsBank.xml" or "/villageBank.xml")
end

function VillageBank:saveState(savegameDirectory, suppressNetwork)
    if g_server == nil then
        if not suppressNetwork and savegameDirectory == nil and VillageBankNetwork ~= nil then
            VillageBankNetwork.sendFarmUpdate(self)
        end
        return
    end
    local filename = self:getSaveFilename(savegameDirectory,false)
    if filename == nil then return end
    local xml = createXMLFile("villageBank", filename, "villageBank")
    if xml == 0 then return end
    local farmIndex = 0
    for farmId, data in pairs(self.farms) do
        if not suppressNetwork then data.revision=(data.revision or 0)+1 end
        local key = string.format("villageBank.farm(%d)", farmIndex)
        setXMLInt(xml, key .. "#id", farmId)
        setXMLInt(xml, key .. "#nextId", data.nextId)
        self:saveSavingsState(xml, key, data)
        setXMLFloat(xml, key .. "#interestEarned", data.interestEarned)
        setXMLFloat(xml, key .. "#interestPaid", data.interestPaid)
        for i, account in ipairs(data.accounts) do
            local a = string.format("%s.accounts.account(%d)", key, i - 1)
            setXMLInt(xml, a .. "#id", account.id); setXMLString(xml, a .. "#name", account.name); setXMLString(xml, a .. "#iban", account.iban or ""); setXMLBool(xml, a .. "#isMain", account.isMain == true); setXMLFloat(xml, a .. "#balance", account.balance)
        end
        self:saveFinancingState(xml, key, data)
        self:saveLeasingState(xml, key, data)
        for i, transaction in ipairs(data.transactions or {}) do
            local t = string.format("%s.transactions.transaction(%d)", key, i - 1)
            setXMLString(xml, t .. "#type", transaction.transactionType or "")
            setXMLString(xml, t .. "#source", transaction.source or "")
            setXMLString(xml, t .. "#target", transaction.target or "")
            setXMLFloat(xml, t .. "#amount", transaction.amount or 0)
            setXMLInt(xml, t .. "#day", transaction.day or 0)
        end
        farmIndex = farmIndex + 1
    end
    saveXMLFile(xml); delete(xml)
    if not suppressNetwork and VillageBankNetwork ~= nil then
        VillageBankNetwork.broadcastState()
    end
end

function VillageBank:loadState()
    if g_server == nil then return end
    local filename = self:getSaveFilename(nil,false)
    local rootName="villageBank"
    local xmlHandleName="villageBank"
    if filename == nil then return end
    if not fileExists(filename) then
        filename=self:getSaveFilename(nil,true)
        rootName="lsBank"
        xmlHandleName="lsBank"
    end
    if filename == nil or not fileExists(filename) then return end
    local xml = loadXMLFile(xmlHandleName, filename)
    if xml == 0 then return end
    local fi = 0
    while true do
        local key = string.format(rootName..".farm(%d)", fi)
        local farmId = getXMLInt(xml, key .. "#id")
        if farmId == nil then break end
        local data = self:getFarmData(farmId)
        data.accounts = {}
        data.nextId = getXMLInt(xml, key .. "#nextId") or 1
        self:loadSavingsState(xml, key, data)
        data.interestEarned = getXMLFloat(xml, key .. "#interestEarned") or 0
        data.interestPaid = getXMLFloat(xml, key .. "#interestPaid") or 0
        data.transactions = {}
        local i = 0
        while hasXMLProperty(xml, string.format("%s.accounts.account(%d)", key, i)) do
            local a = string.format("%s.accounts.account(%d)", key, i)
            table.insert(data.accounts, {id=getXMLInt(xml,a.."#id") or i+1, name=getXMLString(xml,a.."#name") or "Konto", iban=getXMLString(xml,a.."#iban"), isMain=getXMLBool(xml,a.."#isMain") or false, balance=getXMLFloat(xml,a.."#balance") or 0}); i=i+1
        end
        self:ensureMainAccount(data, farmId)
        self:loadFinancingState(xml, key, data)
        self:loadLeasingState(xml, key, data)
        i = 0
        while hasXMLProperty(xml, string.format("%s.transactions.transaction(%d)", key, i)) do
            local t=string.format("%s.transactions.transaction(%d)",key,i)
            table.insert(data.transactions,{transactionType=getXMLString(xml,t.."#type") or "",source=getXMLString(xml,t.."#source") or "",target=getXMLString(xml,t.."#target") or "",amount=getXMLFloat(xml,t.."#amount") or 0,day=getXMLInt(xml,t.."#day") or 0}); i=i+1
        end
        fi = fi + 1
    end
    delete(xml)
end

function VillageBank:saveSavegame(savegameDirectory)
    self:saveState(savegameDirectory, true)
end

g_villageBank = VillageBank.new()
addModEventListener(g_villageBank)

if FSBaseMission ~= nil and FSBaseMission.saveSavegame ~= nil and not VillageBank.missionSaveHookInstalled then
    VillageBank.missionSaveHookInstalled = true
    FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, function(mission)
        if g_villageBank ~= nil then
            local directory = mission ~= nil and mission.missionInfo ~= nil and mission.missionInfo.savegameDirectory or nil
            g_villageBank:saveState(directory, true)
        end
    end)
end
