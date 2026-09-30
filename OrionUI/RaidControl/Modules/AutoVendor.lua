local _, ns = ...
local RC = ns.RC
if not RC then return end -- standalone RaidControl is enabled
local L = RC.L
local AutoVendor = RC:NewModule("AutoVendor", "AceEvent-3.0")

local function GetMoneyText(amount)
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(amount or 0)
    end
    return tostring(amount or 0)
end

function AutoVendor:OnInitialize()
    self.db = RC.db.profile
end

function AutoVendor:OnEnable()
    self:RegisterEvent("MERCHANT_SHOW")
end

function AutoVendor:MERCHANT_SHOW()
    -- 1. Auto Repair
    if self.db.enableAutoRepair and CanMerchantRepair() then
        local repairAllCost, canRepair = GetRepairAllCost()
        if canRepair and repairAllCost > 0 then
            local tryGuild = false
            if self.db.useGuildRepair and IsInGuild() and CanGuildBankRepair() then
                local amount = GetGuildBankWithdrawMoney()
                local guildBankMoney = GetGuildBankMoney()
                if amount == -1 then
                    amount = guildBankMoney
                else
                    amount = math.min(amount, guildBankMoney)
                end

                if amount >= repairAllCost then
                    tryGuild = true
                end
            end

            if tryGuild then
                RepairAllItems(true)
                RC:Printf(L["Auto-Repaired using Guild Bank: %s"], GetMoneyText(repairAllCost))
            else
                local playerMoney = GetMoney()
                if playerMoney >= repairAllCost then
                    RepairAllItems(false)
                    RC:Printf(L["Auto-Repaired: %s"], GetMoneyText(repairAllCost))
                else
                    RC:Printf(L["Not enough money to auto-repair. Cost: %s"], GetMoneyText(repairAllCost))
                end
            end
        end
    end

    -- 2. Auto Sell Junk
    if self.db.enableAutoSellJunk and C_Container and C_Item and C_Item.GetItemInfo then
        local soldTotal = 0
        local itemsSold = 0

        for bag = 0, 4 do
            for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
                local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
                if itemInfo and itemInfo.hyperlink then
                    local _, _, itemRarity, _, _, _, _, _, _, _, itemSellPrice = C_Item.GetItemInfo(itemInfo.hyperlink)
                    if itemRarity == 0 and itemSellPrice and itemSellPrice > 0 then
                        C_Container.UseContainerItem(bag, slot)
                        soldTotal = soldTotal + (itemSellPrice * (itemInfo.stackCount or 1))
                        itemsSold = itemsSold + 1
                    end
                end
            end
        end

        if soldTotal > 0 then
            RC:Printf(L["Sold %d junk item(s) for %s"], itemsSold, GetMoneyText(soldTotal))
        end
    end
end
