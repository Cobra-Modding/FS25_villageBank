-- ============================================================
-- FS25_VillageBankMenu.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

VillageBankFrame = {}
local VillageBankFrame_mt = Class(VillageBankFrame, TabbedMenuFrameElement)

function VillageBankFrame.new()
    local self = TabbedMenuFrameElement.new(nil, VillageBankFrame_mt)
    self.name = "VillageBankFrame"
    return self
end

function VillageBankFrame:initialize()
    VillageBankFrame:superClass().initialize(self)
    self.menuButtonInfo = {{inputAction=InputAction.MENU_BACK}}
    if self.subCategoryTabs~=nil then
        for i,tab in pairs(self.subCategoryTabs) do
            local background=tab:getDescendantByName("background")
            if background~=nil then background.getIsSelected=function() return g_villageBank~=nil and g_villageBank.selectedTab==i end end
            tab.getIsSelected=function() return g_villageBank~=nil and g_villageBank.selectedTab==i end
        end
    end
end

function VillageBankFrame:getMenuButtonInfo()
    return self.menuButtonInfo or {}
end

function VillageBankFrame:onFrameOpen()
    VillageBankFrame:superClass().onFrameOpen(self)
    local bank=g_villageBank
    if bank~=nil then
        bank.isMenuPageOpen=true
        bank.isOpen=true
        bank.openedFromShopContract=false
        bank:getFarmData(bank:getFarmId())
        if self.bankTitleText~=nil then
            local mapName=bank:getMapName()
            self.bankTitleText:setText(mapName~="" and ("DORFBANK · "..mapName) or "DORFBANK")
        end
        if self.currentBalanceText~=nil then self.currentBalanceText:setText(g_i18n:formatMoney(bank:getFarmMoney(bank:getFarmId()),0,true,true)) end
        if self.subCategoryPaging~=nil then
            self.subCategoryPaging:setTexts({"KONTEN","SPAREN","FINANZIERUNG","LEASING","KREDIT","BUCHUNGEN"})
            self.subCategoryPaging:setState(bank.selectedTab,true)
        end
    end
end

function VillageBankFrame:setBankTab(index)
    local bank=g_villageBank
    if bank~=nil then
        local lockedTab=bank:getShopContractLockedTab()
        if lockedTab~=nil and index~=lockedTab then
            index=lockedTab
            bank:setStatus("Bitte den Händlervertrag zuerst abschließen oder abbrechen.")
        elseif bank.selectedTab~=index then
            bank:closeBankSubMenus()
        end
        bank.selectedTab=index
    end
    if self.subCategoryPaging~=nil and self.subCategoryPaging:getState()~=index then self.subCategoryPaging:setState(index,true) end
end
function VillageBankFrame:onClickTabAccounts() self:setBankTab(1) end
function VillageBankFrame:onClickTabSavings() self:setBankTab(2) end
function VillageBankFrame:onClickTabFinancing() self:setBankTab(3) end
function VillageBankFrame:onClickTabLeasing() self:setBankTab(4) end
function VillageBankFrame:onClickTabCredit() self:setBankTab(5) end
function VillageBankFrame:onClickTabTransactions() self:setBankTab(6) end
function VillageBankFrame:onPagingChanged() if self.subCategoryPaging~=nil then self:setBankTab(self.subCategoryPaging:getState()) end end

function VillageBankFrame:onFrameClose()
    local bank=g_villageBank
    if bank~=nil then
        bank.isMenuPageOpen=false
        bank.isOpen=false
        bank.transferFormOpen=false; bank.savingsTransferFormOpen=false
        bank.financeFormOpen=false; bank.leaseFormOpen=false
        bank.renameFormOpen=false
        bank.activeTextField=nil
    end
    VillageBankFrame:superClass().onFrameClose(self)
end

function VillageBankFrame:draw()
    VillageBankFrame:superClass().draw(self)
    if g_villageBank~=nil then
        if self.currentBalanceText~=nil then self.currentBalanceText:setText(g_i18n:formatMoney(g_villageBank:getFarmMoney(g_villageBank:getFarmId()),0,true,true)) end
        g_villageBank:drawBankSurface()
    end
end

function VillageBankFrame:mouseEvent(posX,posY,isDown,isUp,button,eventUsed)
    return VillageBankFrame:superClass().mouseEvent(self,posX,posY,isDown,isUp,button,eventUsed)
end

function VillageBankFrame:keyEvent(unicode,sym,modifier,isDown,eventUsed)
    if g_villageBank~=nil and g_villageBank.activeTextField~=nil then
        return true
    end
    return VillageBankFrame:superClass().keyEvent(self,unicode,sym,modifier,isDown,eventUsed)
end

VillageBankMenu = {modDirectory=g_currentModDirectory}

function VillageBankMenu:openBankPage(tabIndex)
    local menu=self.inGameMenu
    if menu==nil or self.frame==nil or menu.pagingElement==nil then return false end
    if g_villageBank~=nil then g_villageBank.selectedTab=tabIndex or 1 end
    if g_gui~=nil and g_gui.showGui~=nil then g_gui:showGui("InGameMenu") end
    local paging=menu.pagingElement
    if menu.goToPage~=nil then
        menu:goToPage(self.frame,true)
    elseif paging.setPage~=nil and self.pagePosition~=nil then
        paging:setPage(self.pagePosition)
    else
        return false
    end
    if self.frame.setBankTab~=nil then self.frame:setBankTab(tabIndex or 1) end
    return true
end

function VillageBankMenu:addPage(inGameMenu)
    if inGameMenu==nil or inGameMenu.pageVillageBank~=nil then return end
    if inGameMenu.registerPage==nil or inGameMenu.addPageTab==nil or inGameMenu.pagingElement==nil then
        Logging.warning("[VillageBank] ESC menu page API unavailable")
        return
    end

    if not self.profilesLoaded then g_gui:loadProfiles(self.modDirectory.."gui/VillageBankProfiles.xml"); self.profilesLoaded=true end
    local template=VillageBankFrame.new()
    g_gui:loadGui(self.modDirectory.."gui/VillageBankFrame.xml","VillageBankFrame",template,true)

    local xml=loadXMLFile("VillageBankFrameRefXML",self.modDirectory.."gui/VillageBankFrameRef.xml")
    if xml==nil or xml==0 then Logging.error("[VillageBank] VillageBankFrameRef.xml could not be loaded"); return end
    inGameMenu.controlIDs.pageVillageBank=nil
    g_gui:loadGuiRec(xml,"FrameReferences",inGameMenu.pagingElement,inGameMenu)
    inGameMenu:exposeControlsAsFields("pageVillageBank")
    inGameMenu.pagingElement:updatePageMapping()
    delete(xml)

    local frame=g_gui:resolveFrameReference(inGameMenu.pageVillageBank)
    if frame==nil or frame.elements==nil or frame.elements[1]==nil then
        Logging.error("[VillageBank] Dorfbank ESC frame could not be resolved")
        return
    end
    frame.elements[1].title="Dorfbank"
    inGameMenu.pageVillageBank=frame
    inGameMenu.pagingElement:removePageByElement(frame)

    local position=#(inGameMenu.pageFrames or {})+1
    for i,page in ipairs(inGameMenu.pageFrames or {}) do
        if page==inGameMenu.pageStatistics then position=i; break end
    end
    local _,actualPosition=inGameMenu:registerPage(frame,position,function() return true end)
    inGameMenu:addPageTab(frame,self.modDirectory.."gui/villageBankTab.dds",{0,0,0,1,1,0,1,1},nil)
    inGameMenu.pagingElement:addPage("PAGEVILLAGEBANK",frame,"Dorfbank",actualPosition)
    frame:onGuiSetupFinished(); frame:initialize()
    inGameMenu.pagingElement:updateAbsolutePosition(); inGameMenu.pagingElement:updatePageMapping()
    if inGameMenu.rebuildTabList~=nil then inGameMenu:rebuildTabList() end
    self.inGameMenu=inGameMenu
    self.frame=frame
    self.pagePosition=actualPosition
    if not inGameMenu.villageBankTextNavigationGuard then
        local navigationCallbacks={
            "onButtonPreviousPage","onButtonNextPage",
            "onPagePrevious","onPageNext",
            "onButtonPrevious","onButtonNext"
        }
        for _,callbackName in ipairs(navigationCallbacks) do
            local original=inGameMenu[callbackName]
            if original~=nil then
                inGameMenu[callbackName]=function(menu,...)
                    if g_villageBank~=nil and g_villageBank.isMenuPageOpen and g_villageBank.activeTextField~=nil then
                        return
                    end
                    return original(menu,...)
                end
            end
        end
        inGameMenu.villageBankTextNavigationGuard=true
    end
    print("[VillageBank] Dorfbank page added to ESC menu")
end

if InGameMenu~=nil and InGameMenu.onLoadMapFinished~=nil then
    InGameMenu.onLoadMapFinished=Utils.appendedFunction(InGameMenu.onLoadMapFinished,function(inGameMenu)
        VillageBankMenu:addPage(inGameMenu)
    end)
end
