-- ============================================================
-- FS25_VehicleInsurance.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

VehicleInsurance = {}

local Mod = VehicleInsurance

local unpackArgs = unpack or table.unpack

Mod.directory = g_currentModDirectory

Mod.config = {

    annualRates = {[2]=0.012, [3]=0.024},

    refunds = {[0]=0, [2]=0.50, [3]=1.00},

    minimumMonthlyPremium = 2

}

Mod.names = {[0]="Keine Versicherung", [2]="Teilkasko", [3]="Vollkasko"}

Mod.selected = 1

Mod.selectedTab = 1

Mod.listOffset = 1

Mod.notice = "Tarifwechsel gelten ab dem naechsten Spielmonat."

Mod.VISIBLE_ROWS = 8



local function clamp(value, low, high)

    return math.max(low, math.min(high, math.floor(tonumber(value) or low)))

end



local function drawText(x, y, size, text, r, g, b, a)

    setTextColor(r or 1, g or 1, b or 1, a or 1)

    setTextAlignment(RenderText.ALIGN_LEFT)

    renderText(x, y, size, text)

end



local function money(value)

    return g_i18n:formatMoney(value or 0, 0, true, true)

end



function Mod.isLeased(vehicle)

    return VehiclePropertyState ~= nil and vehicle.propertyState == VehiclePropertyState.LEASED

end



function Mod.isShopItem(vehicle)

    return VehiclePropertyState ~= nil and vehicle.propertyState == VehiclePropertyState.SHOP_CONFIG

end



function Mod.isOwnedState(vehicle)

    if vehicle == nil then return false end

    if VehiclePropertyState ~= nil and vehicle.propertyState == VehiclePropertyState.OWNED then return true end

    if vehicle.getPropertyState ~= nil and VehiclePropertyState ~= nil then

        return vehicle:getPropertyState() == VehiclePropertyState.OWNED

    end

    return false

end



function Mod.isPallet(vehicle)

    return vehicle.spec_pallet ~= nil

        or (vehicle.configFileName ~= nil and string.find(string.lower(tostring(vehicle.configFileName)), "/bigbag") ~= nil)

end

function Mod.isExcludedObject(vehicle)
    local configFile = string.lower(tostring(vehicle.configFileName or "")):gsub("\\", "/")
    local environment = string.lower(tostring(vehicle.customEnvironment or ""))
    local modName = string.lower(tostring(vehicle.modName or ""))
    local packName = "fs25_lsfmfarmequipmentpack"

    if environment == packName or modName == packName
        or string.find("/" .. configFile, "/" .. packName .. "/", 1, true) ~= nil
        or string.find(configFile, "$moddir$" .. packName .. "/", 1, true) == 1 then
        return true
    end

    if string.find(configFile, "/vehicles/mapvehicles/relaxingstation/relaxingstation.xml", 1, true) ~= nil then
        return true
    end

    return string.match(configFile, "/hds9184m%.xml$") ~= nil
        or configFile == "hds9184m.xml"
end


function Mod.isEligible(vehicle)

    if vehicle == nil or vehicle.isDeleted or vehicle.isDeleting then return false end

    if vehicle.spec_motorized == nil or Mod.isExcludedObject(vehicle) then return false end

    if Mod.isPallet(vehicle) or Mod.isLeased(vehicle) or Mod.isShopItem(vehicle) then return false end

    if vehicle.getOwnerFarmId == nil then return false end

    local farmId = vehicle:getOwnerFarmId()

    if farmId == nil or farmId <= 0 then return false end

    return Mod.isOwnedState(vehicle)

end



function Mod.getDisplayName(vehicle)

    if vehicle == nil then return "Fahrzeug" end

    if vehicle.getFullName ~= nil then

        local name = vehicle:getFullName()

        if name ~= nil and name ~= "" and name ~= "Unknown" then return name end

    end

    if vehicle.getName ~= nil then

        return vehicle:getName() or "Fahrzeug"

    end

    return "Fahrzeug"

end



function Mod.getValue(vehicle)

    return math.max(0, vehicle.getPrice ~= nil and vehicle:getPrice() or vehicle.price or 0)

end



function Mod.premium(vehicle, policy)

    if policy == nil or policy == 0 or policy == 1 or Mod.config.annualRates[policy] == nil then return 0 end

    return math.max(Mod.config.minimumMonthlyPremium,

        math.floor(Mod.getValue(vehicle) * Mod.config.annualRates[policy] / 12 + 0.5))

end



function Mod:getMapName()

    if g_currentMission == nil then return "" end

    local info = g_currentMission.missionInfo

    return (info ~= nil and (info.mapTitle or info.mapName)) or g_currentMission.mapTitle or ""

end



function Mod:getFarmMoney()

    local farmId = g_currentMission ~= nil and g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() or 1

    local farm = g_farmManager ~= nil and g_farmManager:getFarmById(farmId) or nil

    return farm ~= nil and farm.money or 0

end



function Mod.initializeVehicle(vehicle)

    if not Mod.enabled or vehicle.vitState ~= nil or not Mod.isEligible(vehicle) then

        return

    end

    if VehicleLoadingState ~= nil and vehicle.loadingState ~= nil and vehicle.loadingState ~= VehicleLoadingState.OK then

        return

    end

    local state = vehicle.viIncomingState or {policy=0, pending=0, months=0, premiums=0, taxes=0, refunds=0, lastDay=-1}

    vehicle.viIncomingState = nil

    local savegame = vehicle.savegame

    if vehicle.isServer and savegame ~= nil and savegame.xmlFile ~= nil then

        local key = savegame.key .. ".vehicleInsurance"

        for name, default in pairs(state) do

            local legacy = savegame.xmlFile:getValue(savegame.key .. ".vehicleInsuranceTax#" .. name, default)

            state[name] = savegame.xmlFile:getValue(key .. "#" .. name, legacy)

        end

    end

    state.policy = clamp(state.policy, 0, 3)

    state.pending = clamp(state.pending, 0, 3)

    if state.policy == 1 then state.policy = 0 end

    if state.pending == 1 then state.pending = 0 end

    state.months = clamp(state.months, 0, 11)

    vehicle.vitState = state

    if vehicle.repairVehicle ~= nil then

        vehicle.repairVehicle = Utils.overwrittenFunction(vehicle.repairVehicle, Mod.repairVehicle)

    end

    if vehicle.repaintVehicle ~= nil then

        vehicle.repaintVehicle = Utils.overwrittenFunction(vehicle.repaintVehicle, Mod.repaintVehicle)

    end

end



function Mod.saveVehicle(vehicle, xmlFile, key)

    if not vehicle.isServer or vehicle.vitState == nil then return end

    for name, value in pairs(vehicle.vitState) do

        xmlFile:setValue(key .. ".vehicleInsurance#" .. name, value)

    end

end



function Mod.repairVehicle(vehicle, superFunc, ...)

    local state = vehicle.vitState

    local refund = 0

    if Mod.enabled and vehicle.isServer and Mod.isEligible(vehicle) and state ~= nil

        and vehicle.getDamageAmount ~= nil and vehicle:getDamageAmount() > 0 then

        refund = math.floor(vehicle:getRepairPrice() * Mod.config.refunds[state.policy] + 0.5)

    end

    local result = superFunc(vehicle, ...)

    if refund > 0 and vehicle:getDamageAmount() == 0 then

        Mod.bookMoney(vehicle, refund, MoneyType.VEHICLE_REPAIR, "Versicherungserstattung")

        state.refunds = state.refunds + refund

        Mod.syncVehicle(vehicle)

        Mod.notice = string.format("Versicherung: %s Reparaturkosten erstattet.", g_i18n:formatMoney(refund, 0, true, true))

    end

    return result

end



function Mod.repaintVehicle(vehicle, superFunc, ...)

    local state = vehicle.vitState

    local refund = 0

    if Mod.enabled and vehicle.isServer and Mod.isEligible(vehicle) and state ~= nil

        and vehicle.getWearTotalAmount ~= nil

        and vehicle:getWearTotalAmount() > 0 and vehicle.getRepaintPrice ~= nil then

        refund = math.floor(vehicle:getRepaintPrice() * (Mod.config.refunds[state.policy] or 0) + 0.5)

    end

    local result = superFunc(vehicle, ...)

    if refund > 0 and vehicle:getWearTotalAmount() == 0 then

        Mod.bookMoney(vehicle, refund, MoneyType.VEHICLE_REPAIR, "Versicherungserstattung")

        state.refunds = state.refunds + refund

        Mod.syncVehicle(vehicle)

        Mod.notice = string.format("Versicherung: %s Lackierkosten erstattet.", g_i18n:formatMoney(refund, 0, true, true))

    end

    return result

end



function Mod:loadMap()

    self.enabled = g_currentMission ~= nil

    if not self.enabled then return end

    self.isMenuPageOpen = false

    self.selected = 1

    self.listOffset = 1

    self.selectedTab = 1

    if not self.hooksInstalled then

        local schema = Vehicle.xmlSchemaSavegame

        for _, name in ipairs({"policy", "pending", "months", "lastDay"}) do

            schema:register(XMLValueType.INT, "vehicles.vehicle(?).vehicleInsurance#" .. name, "Insurance " .. name)

            schema:register(XMLValueType.INT, "vehicles.vehicle(?).vehicleInsuranceTax#" .. name, "Legacy insurance " .. name)

        end

        for _, name in ipairs({"premiums", "taxes", "refunds"}) do

            schema:register(XMLValueType.FLOAT, "vehicles.vehicle(?).vehicleInsurance#" .. name, "Insurance total " .. name)

            schema:register(XMLValueType.FLOAT, "vehicles.vehicle(?).vehicleInsuranceTax#" .. name, "Legacy insurance total " .. name)

        end

        Vehicle.loadCallback = Utils.prependedFunction(Vehicle.loadCallback, Mod.initializeVehicle)

        Vehicle.saveToXMLFile = Utils.appendedFunction(Vehicle.saveToXMLFile, Mod.saveVehicle)

        Vehicle.writeStream = Utils.appendedFunction(Vehicle.writeStream, Mod.writeVehicleStream)

        Vehicle.readStream = Utils.appendedFunction(Vehicle.readStream, Mod.readVehicleStream)

        self.hooksInstalled = true

    end

    g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.periodChanged, self)

    if g_currentMission:getIsClient() then

        self.background = Overlay.new(self.directory .. "gui/pixel.dds", 0, 0, 1, 1)

    end


end




function Mod:update(dt)

    if not self.enabled then return end

    if g_currentMission:getIsClient() and VehicleInsuranceMenu ~= nil then VehicleInsuranceMenu:ensurePage() end

    if g_currentMission ~= nil and g_currentMission.vehicleSystem ~= nil then

        for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles or {}) do

            if vehicle.vitState == nil then Mod.initializeVehicle(vehicle) end

        end

    end


end



function Mod:periodChanged()

    if not self.enabled or not g_currentMission:getIsServer() then return end

    local vehicles = g_currentMission.vehicleSystem.vehicles

    local day = g_currentMission.environment.currentDay

    for _, vehicle in pairs(vehicles) do

        local state = vehicle.vitState

        if Mod.isEligible(vehicle) and state ~= nil and state.lastDay ~= day then

            state.lastDay = day

            state.policy = state.pending

            local premium = Mod.premium(vehicle, state.policy)

            if premium > 0 then

                Mod.bookMoney(vehicle, -premium, MoneyType.VEHICLE_RUNNING_COSTS, "Versicherungsbeitrag")

                state.premiums = state.premiums + premium

            end

            Mod.syncVehicle(vehicle)

        end

    end

end



function Mod:getVehicles()

    local result = {}

    if g_currentMission == nil or g_currentMission.vehicleSystem == nil then return result end

    local farmId = g_currentMission:getFarmId()

    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do

        if vehicle.vitState == nil then Mod.initializeVehicle(vehicle) end

        if Mod.isEligible(vehicle) and vehicle.vitState ~= nil and vehicle:getOwnerFarmId() == farmId then

            table.insert(result, vehicle)

        end

    end

    table.sort(result, function(a, b)

        local nameA, nameB = Mod.getDisplayName(a), Mod.getDisplayName(b)

        if nameA == nameB then return tostring(a.uniqueId or "") < tostring(b.uniqueId or "") end

        return nameA < nameB

    end)

    return result

end



function Mod:getLicensePlate(vehicle)

    if vehicle == nil or vehicle.spec_licensePlates == nil

        or vehicle.getHasLicensePlates == nil or not vehicle:getHasLicensePlates() then

        return "-"

    end

    local plates = vehicle.spec_licensePlates.licensePlates

    for i, plate in ipairs(plates) do

        if plate.data ~= nil and plate.data.getFormattedString ~= nil

            and (plate.position == LicensePlateManager.PLATE_POSITION.BACK or i == #plates) then

            local value = plate.data:getFormattedString()

            if value ~= nil and value ~= "" then return value end

        end

    end

    local data = vehicle.spec_licensePlates.licensePlateData

    if data ~= nil and data.characters ~= nil then

        return table.concat(data.characters, "")

    end

    return "-"

end



function Mod:drawPanel(x, y, w, h, r, g, b, a)

    if drawFilledRect ~= nil then

        drawFilledRect(x, y, w, h, r, g, b, a or 1)

    elseif self.background ~= nil then

        self.background:setPosition(x, y)

        self.background:setDimension(w, h)

        self.background:setColor(r, g, b, a or 1)

        self.background:render()

    end

end



function Mod:drawButton(x, y, w, h, label, active, selected)

    if selected then

        self:drawPanel(x, y, w, h, 0.20, 0.40, 0.015, 1)

        drawText(x + 0.012, y + h * 0.29, 0.014, label, 0.08, 0.08, 0.08, 1)

    elseif active == false then

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



function Mod:isInside(px, py, x, y, w, h)

    return px >= x and px <= x + w and py >= y and py <= y + h

end



function Mod:clipName(name, maxLen)

    maxLen = maxLen or 28

    if utf8 ~= nil and utf8.len ~= nil and utf8.sub ~= nil then

        if utf8.len(name) > maxLen then return utf8.sub(name, 1, maxLen - 3) .. "..." end

        return name

    end

    if #name > maxLen then return string.sub(name, 1, maxLen - 3) .. "..." end

    return name

end



function Mod:keyEvent(unicode, sym, modifier, isDown)

end



function Mod:getScrollGeometry(count)

    local height = 0.292

    local thumb = math.max(0.035, height * math.min(1, self.VISIBLE_ROWS / math.max(1, count)))

    local maxOffset = math.max(1, count - self.VISIBLE_ROWS + 1)

    local fraction = (clamp(self.listOffset or 1, 1, maxOffset) - 1) / math.max(1, maxOffset - 1)

    return 0.494, 0.297, height, thumb, 0.297 + (height - thumb) * (1 - fraction)

end



function Mod:mouseEvent(posX, posY, isDown, isUp, button)

    if not self.enabled or not self.isMenuPageOpen then self.scrollDrag = nil; return end

    local leftButton = Input.MOUSE_BUTTON_LEFT or 1

    if (self.selectedTab or 1) ~= 1 then self.scrollDrag = nil; return end

    local vehicles = self:getVehicles()

    local visible = self.VISIBLE_ROWS

    local maxOffset = math.max(1, #vehicles - visible + 1)

    self.listOffset = clamp(self.listOffset or 1, 1, maxOffset)

    local sx, sy, sh, th, ty = self:getScrollGeometry(#vehicles)

    if maxOffset > 1 then

        if isDown and self:isInside(posX, posY, 0.135, sy, 0.369, sh) then

            if button == Input.MOUSE_BUTTON_WHEEL_UP then

                self.listOffset = math.max(1, self.listOffset - 1); return

            elseif button == Input.MOUSE_BUTTON_WHEEL_DOWN then

                self.listOffset = math.min(maxOffset, self.listOffset + 1); return

            end

        end

        if isDown and button == leftButton and self:isInside(posX, posY, sx - 0.003, sy, 0.014, sh) then

            self.scrollDrag = self:isInside(posX, posY, sx - 0.003, ty, 0.014, th) and (posY - ty) or th / 2

        end

        if self.scrollDrag ~= nil then

            local fraction = 1 - (posY - self.scrollDrag - sy) / (sh - th)

            self.listOffset = clamp(1 + fraction * (maxOffset - 1) + 0.5, 1, maxOffset)

            if isUp and button == leftButton then self.scrollDrag = nil end

            return

        end

    else

        self.scrollDrag = nil

    end

    if not isUp or button ~= leftButton then return end

    if #vehicles > 0 then

        self.selected = clamp(self.selected, 1, #vehicles)

        for row = 0, visible - 1 do

            local y = 0.575 - row * 0.037

            local index = self.listOffset + row

            if index <= #vehicles and self:isInside(posX, posY, 0.135, y - 0.019, 0.35, 0.036) then

                self.selected = index

                return

            end

        end

        local vehicle = vehicles[self.selected]

        if vehicle ~= nil and vehicle.vitState ~= nil then

            local buttons = {

                {policy=0, x=0.145, y=0.172},

                {policy=2, x=0.320, y=0.172},

                {policy=3, x=0.145, y=0.132}

            }

            for _, item in ipairs(buttons) do

                if self:isInside(posX, posY, item.x, item.y, 0.165, 0.035) then

                    self:requestPolicy(vehicle, item.policy)

                    return

                end

            end

        end

    end

end



function Mod:drawTariffPage()

    drawText(0.145, 0.615, 0.019, "TARIFE", 0.88, 0.90, 0.89, 1)

    self:drawPanel(0.145, 0.430, 0.365, 0.155, 0.030, 0.036, 0.035, 1)

    self:drawPanel(0.145, 0.582, 0.365, 0.003, 0.20, 0.40, 0.015, 1)

    drawText(0.165, 0.545, 0.018, "Keine Versicherung", 0.95, 0.96, 0.95, 1)

    drawText(0.165, 0.515, 0.012, "NUR STANDARD-UNTERHALT", 0.58, 0.63, 0.61, 1)

    drawText(0.165, 0.455, 0.014, "0 % Erstattung  |  kein Zusatzbeitrag", 0.88, 0.90, 0.89, 1)



    self:drawPanel(0.535, 0.430, 0.365, 0.155, 0.030, 0.036, 0.035, 1)

    self:drawPanel(0.535, 0.582, 0.365, 0.003, 0.20, 0.40, 0.015, 1)

    drawText(0.555, 0.545, 0.018, "Teilkasko", 0.95, 0.96, 0.95, 1)

    drawText(0.555, 0.515, 0.012, "ZUSAETZLICHER SCHADENSCHUTZ", 0.58, 0.63, 0.61, 1)

    drawText(0.555, 0.475, 0.014, "50 % Reparatur und Lackierung", 0.88, 0.90, 0.89, 1)

    drawText(0.555, 0.450, 0.012, "Standard-Unterhalt bleibt", 0.62, 0.66, 0.64, 1)



    self:drawPanel(0.145, 0.230, 0.755, 0.155, 0.030, 0.036, 0.035, 1)

    self:drawPanel(0.145, 0.382, 0.755, 0.003, 0.20, 0.40, 0.015, 1)

    drawText(0.165, 0.345, 0.018, "Vollkasko", 0.95, 0.96, 0.95, 1)

    drawText(0.165, 0.315, 0.012, "ZUSAETZLICHER SCHADENSCHUTZ", 0.58, 0.63, 0.61, 1)

    drawText(0.165, 0.270, 0.014, "100 % Reparatur und Lackierung  |  Standard-Unterhalt bleibt", 0.88, 0.90, 0.89, 1)

    drawText(0.145, 0.175, 0.012, "Haftpflicht und Kfz-Steuer gibt es nicht. Dieser Mod ersetzt keine Spielkosten.", 0.62, 0.66, 0.64, 1)

end



function Mod:drawVehicleStoreImage(vehicle)

    local filename = vehicle.getImageFilename ~= nil and vehicle:getImageFilename() or nil

    if (filename == nil or filename == "") and g_storeManager ~= nil and vehicle.configFileName ~= nil then

        local item = g_storeManager:getItemByXMLFilename(vehicle.configFileName)

        filename = item ~= nil and item.imageFilename or nil

    end

    if filename ~= self.storeImageFilename then

        if self.storeImage ~= nil then self.storeImage:delete(); self.storeImage = nil end

        self.storeImageFilename = filename

        if filename ~= nil and filename ~= "" then

            self.storeImage = Overlay.new(filename, 0, 0, 1, 1)

        end

    end

    if self.storeImage ~= nil then

        local aspect = g_screenAspectRatio or (16 / 9)

        local height = math.min(0.135, 0.130 * aspect)

        local width = height / aspect

        self.storeImage:setPosition(0.765 + (0.130 - width) / 2, 0.440 + (0.135 - height) / 2)

        self.storeImage:setDimension(width, height)

        self.storeImage:render()

    end

end



function Mod:drawVehiclePage(vehicles)

    local visible = self.VISIBLE_ROWS

    local maxOffset = math.max(1, #vehicles - visible + 1)

    self.listOffset = clamp(self.listOffset or 1, 1, maxOffset)

    local monthly = 0

    for _, vehicle in ipairs(vehicles) do

        monthly = monthly + Mod.premium(vehicle, vehicle.vitState.pending)

    end



    drawText(0.145, 0.615, 0.019, "FAHRZEUGE", 0.88, 0.90, 0.89, 1)

    drawText(0.400, 0.615, 0.013, "KENNZEICHEN", 0.62, 0.66, 0.64, 1)

    local first = self.listOffset

    local last = math.min(#vehicles, first + visible - 1)

    for i = first, last do

        local y = 0.575 - (i - first) * 0.037

        local selected = i == self.selected

        local color = selected and 0.08 or 0.94

        if selected then

            self:drawPanel(0.139, y - 0.018, 0.35, 0.035, 0.20, 0.40, 0.015, 1)

        elseif i % 2 == 0 then

            self:drawPanel(0.139, y - 0.018, 0.35, 0.035, 0.025, 0.029, 0.032, 1)

        end

        drawText(0.145, y, 0.0145, string.format("%02d  %s", i, self:clipName(Mod.getDisplayName(vehicles[i]), 22)), color, color, color, 1)

        drawText(0.400, y, 0.0145, self:getLicensePlate(vehicles[i]), selected and 0.08 or 0.92, selected and 0.08 or 0.94, selected and 0.08 or 0.92, 1)

    end

    if #vehicles > visible then

        local sx, sy, sh, th, ty = self:getScrollGeometry(#vehicles)

        self:drawPanel(sx + 0.002, sy, 0.002, sh, 0.09, 0.10, 0.10, 1)

        self:drawPanel(sx, ty, 0.006, th, 0.32, 0.55, 0.04, 1)

    end



    self:drawPanel(0.515, 0.180, 0.0015, 0.450, 0.08, 0.10, 0.10, 1)

    drawText(0.545, 0.615, 0.014, "TARIFDETAILS", 0.67, 0.72, 0.70, 1)

    local vehicle = vehicles[self.selected]

    if vehicle ~= nil then

        local state = vehicle.vitState

        self:drawPanel(0.535, 0.430, 0.365, 0.155, 0.030, 0.036, 0.035, 1)

        self:drawPanel(0.535, 0.582, 0.365, 0.003, 0.20, 0.40, 0.015, 1)

        drawText(0.555, 0.545, 0.020, self:clipName(Mod.getDisplayName(vehicle), 26), 0.95, 0.96, 0.95, 1)

        drawText(0.555, 0.515, 0.012, string.upper(Mod.names[state.policy] or ""), 0.58, 0.63, 0.61, 1)

        drawText(0.555, 0.475, 0.011, "ZUSATZBEITRAG / MONAT", 0.58, 0.63, 0.61, 1)

        drawText(0.555, 0.446, 0.023, money(Mod.premium(vehicle, state.pending)), 0.32, 0.55, 0.04, 1)

        self:drawVehicleStoreImage(vehicle)



        drawText(0.545, 0.390, 0.014, "SCHUTZ", 0.67, 0.72, 0.70, 1)

        self:drawPanel(0.535, 0.255, 0.365, 0.120, 0.030, 0.036, 0.035, 1)

        drawText(0.555, 0.345, 0.013, "Ab naechstem Monat: " .. Mod.names[state.pending], 0.88, 0.90, 0.89, 1)

        drawText(0.555, 0.320, 0.013, "Standard-Unterhalt: immer aktiv", 0.88, 0.90, 0.89, 1)

        drawText(0.555, 0.295, 0.013, "Reparatur und Lackierung: " .. tostring(math.floor((Mod.config.refunds[state.policy] or 0) * 100)) .. " %", 0.88, 0.90, 0.89, 1)

        drawText(0.555, 0.270, 0.012, "Erstattungen: " .. money(state.refunds) .. "  |  Beitraege: " .. money(state.premiums), 0.62, 0.66, 0.64, 1)



        self:drawButton(0.145, 0.172, 0.165, 0.035, "Keine Versicherung", true, state.pending == 0)

        self:drawButton(0.320, 0.172, 0.165, 0.035, "Teilkasko", true, state.pending == 2)

        self:drawButton(0.145, 0.132, 0.165, 0.035, "Vollkasko", true, state.pending == 3)

        drawText(0.320, 0.142, 0.012, "Fuhrpark: " .. money(monthly) .. " / Monat", 0.62, 0.66, 0.64, 1)

    else

        drawText(0.545, 0.500, 0.017, "Keine eigenen Fahrzeuge vorhanden.", 0.7, 0.7, 0.7, 1)

    end

    if self.notice ~= nil then drawText(0.145, 0.078, 0.0125, self.notice, 0.95, 0.72, 0.30, 1) end

end



function Mod:drawMenuSurface()

    if not self.enabled or not self.isMenuPageOpen then return end

    local vehicles = self:getVehicles()

    self.selected = clamp(self.selected, 1, math.max(1, #vehicles))

    self:drawPanel(0.125, 0.130, 0.805, 0.535, 0.012, 0.015, 0.016, 1)

    self:drawPanel(0.125, 0.650, 0.805, 0.002, 0.27, 0.30, 0.29, 1)

    if (self.selectedTab or 1) == 2 then

        self:drawTariffPage()

    else

        self:drawVehiclePage(vehicles)

    end

    setTextColor(1, 1, 1, 1)

    setTextBold(false)

end



function Mod:draw()

end



function Mod:deleteMap()

    self.scrollDrag = nil

    if self.storeImage ~= nil then self.storeImage:delete(); self.storeImage = nil end

    self.storeImageFilename = nil

    g_messageCenter:unsubscribeAll(self)

    if self.background ~= nil then self.background:delete(); self.background = nil end

    self.enabled = false

    self.isMenuPageOpen = false

end



g_vehicleInsurance = Mod

addModEventListener(Mod)

