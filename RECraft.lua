local _G = _G
local _, RE = ...
local EVENT = LibStub("AceEvent-3.0")
local BUCKET = LibStub("AceBucket-3.0")
_G.RECraft = RE

local NewTicker = _G.C_Timer.NewTicker
local FlashClientIcon = _G.FlashClientIcon
local GetCrafterOrders = _G.C_CraftingOrders.GetCrafterOrders
local GetCrafterBuckets = _G.C_CraftingOrders.GetCrafterBuckets
local GetOrderClaimInfo = _G.C_CraftingOrders.GetOrderClaimInfo
local RequestCrafterOrders = _G.C_CraftingOrders.RequestCrafterOrders
local GetRecipeSchematic = _G.C_TradeSkillUI.GetRecipeSchematic
local GetChildProfessionInfo = _G.C_TradeSkillUI.GetChildProfessionInfo
local IsNearProfessionSpellFocus = _G.C_TradeSkillUI.IsNearProfessionSpellFocus
local GetRecipeInfoForSkillLineAbility = _G.C_TradeSkillUI.GetRecipeInfoForSkillLineAbility
local ElvUI = _G.ElvUI

RE.ScanQueue = {}
RE.BucketPayload = {}
RE.OrdersPayload = {}
RE.OrdersStatus = {}
RE.OrdersSeen = {[Enum.CraftingOrderType.Public] = {}, [Enum.CraftingOrderType.Guild] = {}}
RE.OrdersFound = {[Enum.CraftingOrderType.Public] = {}, [Enum.CraftingOrderType.Guild] = {}}
RE.RequestNext = Enum.CraftingOrderType.Public
RE.BucketsSeen = {}
RE.BucketsFound = {}
RE.RecipeInfo = {}
RE.RecipeSchematic = {}
RE.BucketScanInProgress = false

RE.AceConfig = {
	type = "group",
	args = {
		Guild = {
			name = "Check guild orders",
			desc = "Also monitor the changes in guild craft orders.",
			type = "toggle",
			width = "full",
			order = 1,
			set = function(_, val) RE.Settings.ScanGuildOrders = val; RE:ResetFilters() end,
			get = function(_) return RE.Settings.ScanGuildOrders end
		},
		SkillUp = {
			name = "Only first crafts and skill ups",
			desc = "Trigger notification only if detected order is first craft or provide skill up.",
			type = "toggle",
			width = "full",
			order = 2,
			set = function(_, val) RE.Settings.ShowOnlyFirstCraftAndSkillUp = val; RE:ResetFilters() end,
			get = function(_) return RE.Settings.ShowOnlyFirstCraftAndSkillUp end
		},
		Incomplete = {
			name = "Only orders with all reagents",
			desc = "Trigger notification only if detected order have all mandatory reagents provided.",
			type = "toggle",
			width = "full",
			order = 3,
			set = function(_, val) RE.Settings.ShowOnlyWithRegents = val; RE:ResetFilters() end,
			get = function(_) return RE.Settings.ShowOnlyWithRegents end
		},
		Tip = {
			name = "Smallest acceptable tip",
			desc = "Orders with a smaller tip will be ignored.",
			type = "input",
			width = "normal",
			order = 4,
			pattern = "%d",
			usage = "Enter the amount of gold.",
			set = function(_, val) RE.Settings.MinimumTipInCopper = val * 10000; RE:ResetFilters() end,
			get = function(_) return tostring(RE.Settings.MinimumTipInCopper / 10000) end
		},
		IgnoredItems = {
			name = "Ignored items",
			desc = "Comma-separated list of ItemIDs whose orders will be ignored.",
			type = "input",
			width = "double",
			order = 5,
			set = function(_, val)
				local input = {strsplit(",", val)}
				for k, v in pairs(input) do
					input[k] = tonumber(v)
				 end
				RE.Settings.IgnoredItemID = input
				RE:ResetFilters()
			end,
			get = function(_) return table.concat(RE.Settings.IgnoredItemID, ",") end
		}
	}
}
RE.DefaultConfig = {
	ShowOnlyFirstCraftAndSkillUp = false,
	ShowOnlyWithRegents = false,
	ScanGuildOrders = false,
	MinimumTipInCopper = 0,
	IgnoredItemID = {}
}

RECraftStatusTemplateMixin = CreateFromMixins(_G.TableBuilderCellMixin)

function RECraftStatusTemplateMixin:Populate(rowData, _)
	if rowData.option.numAvailable then
		if tContains(RE.BucketsSeen, rowData.option.skillLineAbilityID) then
			if tContains(RE.BucketsFound, rowData.option.skillLineAbilityID) then
				_G.ProfessionsTableCellTextMixin.SetText(self, "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t")
			else
				_G.ProfessionsTableCellTextMixin.SetText(self, "|TInterface\\RaidFrame\\ReadyCheck-NotReady:0|t")
			end
		else
			_G.ProfessionsTableCellTextMixin.SetText(self, "|TInterface\\RaidFrame\\ReadyCheck-Waiting:0|t")
		end
	else
		if rowData.option.orderType ~= Enum.CraftingOrderType.Personal then
			if tContains(RE.OrdersSeen[rowData.option.orderType], rowData.option.orderID) then
				if tContains(RE.OrdersFound[rowData.option.orderType], rowData.option.orderID) then
					_G.ProfessionsTableCellTextMixin.SetText(self, "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t")
				else
					_G.ProfessionsTableCellTextMixin.SetText(self, "|TInterface\\RaidFrame\\ReadyCheck-NotReady:0|t")
				end
			else
				_G.ProfessionsTableCellTextMixin.SetText(self, "|TInterface\\RaidFrame\\ReadyCheck-Waiting:0|t")
			end
		end
	end
end

function RE:OnLoad(self)
	self:RegisterEvent("ADDON_LOADED")
	self:RegisterEvent("CHAT_MSG_SYSTEM")
	self:RegisterEvent("TRADE_SKILL_SHOW")
	self:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
	self:RegisterEvent("CRAFTINGORDERS_CAN_REQUEST")

	BUCKET:RegisterBucketMessage("RECRAFT_NOTIFICATION", 1, RE.Notification)

	RE.Request = {
		searchFavorites = false,
		initialNonPublicSearch = false,
		primarySort = {
			sortType = Enum.CraftingOrderSortType.ItemName,
			reversed = false,
		},
		secondarySort = {
			sortType = Enum.CraftingOrderSortType.Tip,
			reversed = false,
		},
		forCrafter = true,
		offset = 0,
		callback = RE.RequestCallback
	}
end

function RE:OnEvent(self, event, ...)
	if event == "ADDON_LOADED" and ... == "RECraft" then
		self:UnregisterEvent("ADDON_LOADED")
		ProfessionsFrame_LoadUI()
		RE.OP = _G.ProfessionsFrame.OrdersPage
		if not _G.RECraftSettings then
			_G.RECraftSettings = RE.DefaultConfig
		end
		RE.Settings = _G.RECraftSettings
		for key, value in pairs(RE.DefaultConfig) do
			if RE.Settings[key] == nil then
				RE.Settings[key] = value
			end
		end
		_G.LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("RECraft", RE.AceConfig)
		_G.LibStub("AceConfigDialog-3.0"):AddToBlizOptions("RECraft", "RECraft")
	elseif event == "CHAT_MSG_SYSTEM" and ... == _G.ERR_CRAFTING_ORDER_RECEIVED then
		RE.NotificationType = Enum.CraftingOrderType.Personal
		EVENT:SendMessage("RECRAFT_NOTIFICATION")
	elseif event == "TRADE_SKILL_SHOW" then
		self:UnregisterEvent("TRADE_SKILL_SHOW")
		local button = CreateFrame("Button", nil, RE.OP.BrowseFrame.SearchButton, "RefreshButtonTemplate")
		if ElvUI then
			ElvUI[1]:GetModule("Skins"):HandleButton(button)
			button:Size(22)
		end
		button:SetPoint("LEFT", RE.OP.BrowseFrame.SearchButton, "RIGHT")
		button:SetScript("OnClick", RE.SearchToggle)
		RE.OP.BrowseFrame.BackButton:ClearAllPoints()
		RE.OP.BrowseFrame.BackButton:SetPoint("LEFT", button, "RIGHT")
		RE.StatusText = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		RE.StatusText:SetPoint("BOTTOM", RE.OP.BrowseFrame.SearchButton, "TOP", 0, 2)
		_G.ProfessionsFrame:HookScript("OnHide", function() RE:SearchToggle("override") end)
		RE.OP.OrderView:HookScript("OnHide", RE.RestartSpinner)
		hooksecurefunc(RE.OP, "ShowGeneric", RE.RestartSpinner)
		hooksecurefunc(RE.OP, "StartDefaultSearch", RE.RestartSpinner)
		hooksecurefunc(RE.OP, "SetupTable", function(self)
			if self.orderType ~= Enum.CraftingOrderType.Personal then
				self.tableBuilder:AddUnsortableFixedWidthColumn(self, 0, 60, 15, 0, "|cFF74D06CRE|rCraft", "RECraftStatusTemplate")
				self.tableBuilder:Arrange()
			end
		end)
	elseif event == "TRADE_SKILL_LIST_UPDATE" then
		local professionInfo = GetChildProfessionInfo()
		if professionInfo and professionInfo.profession then
			RE.Request.profession = professionInfo.profession
		end
	elseif event == "CRAFTINGORDERS_CAN_REQUEST" and RE.BucketScanInProgress then
		if #RE.ScanQueue > 0 then
			RE.Request.selectedSkillLineAbility = RE.ScanQueue[1]
			RequestCrafterOrders(RE.Request)
			table.remove(RE.ScanQueue, 1)
		else
			RE.BucketScanInProgress = false
		end
	end
end

function RE:Notification()
	FlashClientIcon()
	PlaySoundFile("Interface\\AddOns\\RECraft\\Media\\TadaFanfare.ogg", "Master")
	if RE.NotificationType == Enum.CraftingOrderType.Public then
		_G.RaidNotice_AddMessage(_G.RaidWarningFrame, "|A:auctionhouse-icon-favorite:10:10|a "..strupper(_G.PROFESSIONS_CRAFTING_FORM_ORDER_RECIPIENT_PUBLIC).." |A:auctionhouse-icon-favorite:10:10|a", _G.ChatTypeInfo["RAID_WARNING"])
		RE.OP:RequestOrders(nil, false, false)
	elseif RE.NotificationType == Enum.CraftingOrderType.Guild then
		_G.RaidNotice_AddMessage(_G.RaidWarningFrame, "|A:auctionhouse-icon-favorite:10:10|a "..strupper(_G.PROFESSIONS_CRAFTING_FORM_ORDER_RECIPIENT_GUILD).." |A:auctionhouse-icon-favorite:10:10|a", _G.ChatTypeInfo["RAID_WARNING"])
		RE.OP.BrowseFrame.GuildOrdersButton:Click()
	elseif RE.NotificationType == Enum.CraftingOrderType.Personal then
		_G.RaidNotice_AddMessage(_G.RaidWarningFrame, "|A:auctionhouse-icon-favorite:10:10|a "..strupper(_G.PROFESSIONS_CRAFTING_FORM_ORDER_RECIPIENT_PRIVATE).." |A:auctionhouse-icon-favorite:10:10|a", _G.ChatTypeInfo["RAID_WARNING"])
	end
end

function RE:RestartSpinner()
	if RE.Timer then
		RE.OP.BrowseFrame.OrderList.LoadingSpinner:Show()
	end
end

function RE:GetOrderViability(order)
	if not RE.RecipeInfo.learned then
		return false
	end
	local lockedSlots = {}
	for _, v in pairs(RE.RecipeSchematic.reagentSlotSchematics) do
		if v.reagentType == Enum.CraftingReagentType.Optional and _G.Professions.GetReagentSlotStatus(v, RE.RecipeInfo) then
			table.insert(lockedSlots, v.slotIndex)
		end
	end
	if #lockedSlots > 0 then
		for _, v in pairs(order.reagents) do
			if tContains(lockedSlots, v.reagentSlot) then
				return false
			end
		end
	end
	return true
end

function RE:ParseOrders(orderType)
	local newFound = false
	for _, v in pairs(RE.OrdersPayload) do
		if not tContains(RE.OrdersSeen[orderType], v.orderID) then
			RE.RecipeInfo = GetRecipeInfoForSkillLineAbility(v.skillLineAbilityID)
			RE.RecipeSchematic = GetRecipeSchematic(RE.RecipeInfo.recipeID, v.isRecraft)
			if (not RE.Settings.ShowOnlyFirstCraftAndSkillUp or (RE.RecipeInfo.firstCraft or (RE.RecipeInfo.canSkillUp and RE.RecipeInfo.relativeDifficulty < Enum.TradeskillRelativeDifficulty.Trivial)))
			and (not RE.Settings.ShowOnlyWithRegents or (v.reagentState == Enum.CraftingOrderReagentsType.All))
			and v.tipAmount >= RE.Settings.MinimumTipInCopper
			and not tContains(RE.Settings.IgnoredItemID, v.itemID)
			and RE:GetOrderViability(v) then
				newFound = true
				table.insert(RE.OrdersFound[orderType], v.orderID)
				if not tContains(RE.BucketsFound, v.skillLineAbilityID) then
					table.insert(RE.BucketsFound, v.skillLineAbilityID)
				end
			end
			table.insert(RE.OrdersSeen[orderType], v.orderID)
		else
			if not tContains(RE.BucketsFound, v.skillLineAbilityID) and tContains(RE.OrdersFound[orderType], v.orderID) then
				table.insert(RE.BucketsFound, v.skillLineAbilityID)
			end
		end
	end
	return newFound
end

function RE:ParseBucket()
	RE.BucketScanInProgress = true
	for _, v in pairs(RE.BucketPayload) do
		if v.numAvailable > 0 and not tContains(RE.Settings.IgnoredItemID, v.itemID) then
			table.insert(RE.ScanQueue, v.skillLineAbilityID)
			if not tContains(RE.BucketsSeen, v.skillLineAbilityID) then
				table.insert(RE.BucketsSeen, v.skillLineAbilityID)
			end
		end
	end
	if #RE.ScanQueue > 0 then
		RE.Request.selectedSkillLineAbility = RE.ScanQueue[1]
		RequestCrafterOrders(RE.Request)
		table.remove(RE.ScanQueue, 1)
	end
end

function RE:RequestCallback(orderType, displayBuckets)
	if displayBuckets then
		wipe(RE.BucketsFound)
		RE.BucketPayload = GetCrafterBuckets()
		RE:ParseBucket()
	else
		RE.OrdersPayload = GetCrafterOrders()
		if RE:ParseOrders(orderType) then
			RE.NotificationType = orderType
			EVENT:SendMessage("RECRAFT_NOTIFICATION")
		end
		RE.StatusText:SetText("Parsed: "..(#RE.OrdersSeen[Enum.CraftingOrderType.Public] + #RE.OrdersSeen[Enum.CraftingOrderType.Guild]))
	end
end

function RE:SearchRequest()
	if not RE.OP.OrderView:IsShown() and not RE.BucketScanInProgress then
		RE.Request.selectedSkillLineAbility = nil
		if RE.RequestNext == Enum.CraftingOrderType.Public or not RE.Settings.ScanGuildOrders then
			RE.RequestNext = Enum.CraftingOrderType.Guild
			RE.OrdersStatus = GetOrderClaimInfo(RE.Request.profession)
			if IsNearProfessionSpellFocus(RE.Request.profession) and RE.OrdersStatus.claimsRemaining > 0 then
				RE.Request.orderType = Enum.CraftingOrderType.Public
				RequestCrafterOrders(RE.Request)
			elseif not RE.Settings.ScanGuildOrders then
				RE:SearchToggle()
			end
		elseif RE.RequestNext == Enum.CraftingOrderType.Guild then
			RE.RequestNext = Enum.CraftingOrderType.Public
			if IsNearProfessionSpellFocus(RE.Request.profession) then
				RE.Request.orderType = Enum.CraftingOrderType.Guild
				RequestCrafterOrders(RE.Request)
			else
				RE:SearchToggle()
			end
		end
	end
end

function RE:SearchToggle(button)
	if not RE.Timer and button ~= "override" then
		RE.Timer = NewTicker(10, RE.SearchRequest)
		RE:SearchRequest()
		RE:RestartSpinner()
	elseif RE.Timer then
		RE.Timer:Cancel()
		RE.Timer = nil
		RE.OP.BrowseFrame.OrderList.LoadingSpinner:Hide()
		RE.ScanQueue = {}
		RE.BucketScanInProgress = false
	end
end

function RE:ResetFilters()
	RE.OrdersSeen = {[Enum.CraftingOrderType.Public] = {}, [Enum.CraftingOrderType.Guild] = {}}
	RE.OrdersFound = {[Enum.CraftingOrderType.Public] = {}, [Enum.CraftingOrderType.Guild] = {}}
	RE.BucketsSeen = {}
	RE.BucketsFound = {}
	if RE.StatusText then
		RE.StatusText:SetText("Parsed: 0")
	end
end