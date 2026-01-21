local _, RE = ...
local EVENT = LibStub("AceEvent-3.0")
local BUCKET = LibStub("AceBucket-3.0")
RECraft = RE

local NewTicker = C_Timer.NewTicker
local FlashClientIcon = FlashClientIcon
local GetCrafterOrders = C_CraftingOrders.GetCrafterOrders
local GetCrafterBuckets = C_CraftingOrders.GetCrafterBuckets
local GetOrderClaimInfo = C_CraftingOrders.GetOrderClaimInfo
local RequestCrafterOrders = C_CraftingOrders.RequestCrafterOrders
local GetRecipeSchematic = C_TradeSkillUI.GetRecipeSchematic
local GetChildProfessionInfo = C_TradeSkillUI.GetChildProfessionInfo
local IsNearProfessionSpellFocus = C_TradeSkillUI.IsNearProfessionSpellFocus
local GetRecipeInfoForSkillLineAbility = C_TradeSkillUI.GetRecipeInfoForSkillLineAbility
local ElvUI = ElvUI

RE.ScanQueue = {}
RE.ScanBucketQueue = {}
RE.BucketPayload = {}
RE.OrdersPayload = {}
RE.OrdersStatus = {}
RE.OrdersSeen = {[Enum.CraftingOrderType.Public] = {}, [Enum.CraftingOrderType.Guild] = {}, [Enum.CraftingOrderType.Npc] = {}}
RE.OrdersFound = {[Enum.CraftingOrderType.Public] = {}, [Enum.CraftingOrderType.Guild] = {}, [Enum.CraftingOrderType.Npc] = {}}
RE.BucketsSeen = {}
RE.BucketsFound = {}
RE.RecipeInfo = {}
RE.RecipeSchematic = {}
RE.BucketScanInProgress = false
RE.ClaimsRemaining = false

RE.AceConfig = {
	type = "group",
	args = {
		HeaderA = {
			name = "Public/Guild orders",
			type = "header",
			order = 1,
		},
		Claims = {
			name = "Scan Public orders without orders remaining",
			desc = "Do not stop Public order scanning when the daily limit is reached.",
			type = "toggle",
			width = "full",
			order = 2,
			set = function(_, val) RE.Settings.ScanWithoutClaimsRemaining = val end,
			get = function(_) return RE.Settings.ScanWithoutClaimsRemaining end
		},
		Guild = {
			name = "Check Guild orders",
			desc = "Also monitor the changes in Guild craft orders.",
			type = "toggle",
			width = "full",
			order = 3,
			set = function(_, val) RE.Settings.ScanGuildOrders = val; RE:ResetFilters(); RE:ResetSearchQueue() end,
			get = function(_) return RE.Settings.ScanGuildOrders end
		},
		SkillUp = {
			name = "Only first crafts and skill ups",
			desc = "Trigger notification only if detected order is first craft or provide skill up.",
			type = "toggle",
			width = "full",
			order = 4,
			set = function(_, val) RE.Settings.ShowOnlyFirstCraftAndSkillUp = val; RE:ResetFilters() end,
			get = function(_) return RE.Settings.ShowOnlyFirstCraftAndSkillUp end
		},
		Incomplete = {
			name = "Only orders with all reagents",
			desc = "Trigger notification only if detected order have all mandatory reagents provided.",
			type = "toggle",
			width = "full",
			order = 5,
			set = function(_, val) RE.Settings.ShowOnlyWithRegents = val; RE:ResetFilters() end,
			get = function(_) return RE.Settings.ShowOnlyWithRegents end
		},
		Tip = {
			name = "Smallest acceptable tip",
			desc = "Orders with a smaller tip will be ignored.",
			type = "input",
			width = "normal",
			order = 6,
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
			order = 7,
			set = function(_, val)
				local input = {strsplit(",", val)}
				for k, v in pairs(input) do
					input[k] = tonumber(v)
				end
				RE.Settings.IgnoredItemID = input
				RE:ResetFilters()
			end,
			get = function(_) return table.concat(RE.Settings.IgnoredItemID, ",") end
		},
		HeaderB = {
			name = "Patron orders",
			type = "header",
			order = 8,
		},
		Patron = {
			name = "Check Patron orders",
			desc = "Monitor the changes in Patron craft orders.",
			type = "toggle",
			width = "full",
			order = 9,
			set = function(_, val) RE.Settings.ScanNpcOrders = val; RE:ResetFilters(); RE:ResetSearchQueue() end,
			get = function(_) return RE.Settings.ScanNpcOrders end
		},
		SkillUpNpc = {
			name = "Only first crafts and skill ups",
			desc = "Trigger notification only if detected order is first craft or provide skill up.",
			type = "toggle",
			width = "full",
			order = 10,
			set = function(_, val) RE.Settings.ShowOnlyNpcOrderFirstCraftAndSkillUp = val; RE:ResetFilters() end,
			get = function(_) return RE.Settings.ShowOnlyNpcOrderFirstCraftAndSkillUp end
		},
		IncompleteNpc = {
			name = "Only orders with all reagents",
			desc = "Trigger notification only if detected order have all mandatory reagents provided.",
			type = "toggle",
			width = "full",
			order = 11,
			set = function(_, val) RE.Settings.ShowOnlyNpcOrderWithRegents = val; RE:ResetFilters() end,
			get = function(_) return RE.Settings.ShowOnlyNpcOrderWithRegents end
		},
		Glimmer = {
			name = "Only orders rewarding Flicker/Glimmer/Acuity",
			desc = "Trigger notification only if detected order reward contain Glimmer/Flicker of Knowledge and/or Artisan's Acuity/Moxie.",
			type = "toggle",
			width = "full",
			order = 12,
			set = function(_, val) RE.Settings.ShowOnlyNpcOrderWithGlimmer = val; RE:ResetFilters() end,
			get = function(_) return RE.Settings.ShowOnlyNpcOrderWithGlimmer end
		}
	}
}
RE.DefaultConfig = {
	ShowOnlyFirstCraftAndSkillUp = false,
	ShowOnlyNpcOrderFirstCraftAndSkillUp = false,
	ShowOnlyWithRegents = false,
	ShowOnlyNpcOrderWithRegents = false,
	ShowOnlyNpcOrderWithGlimmer = false,
	ScanGuildOrders = false,
	ScanNpcOrders = false,
	ScanWithoutClaimsRemaining = false,
	MinimumTipInCopper = 0,
	IgnoredItemID = {}
}
RE.GlimmerItems = {228724, 228726, 228728, 228730, 228732, 228734, 228736, 228738, -- TWW Flicker
	               228725, 228727, 228729, 228731, 228733, 228735, 228737, 228739, 210814, -- TWW Glimmer/Acuity
				   246320, 246322, 246324, 246326, 246328, 246330, 246332, 246334, -- MN Flicker
				   246321, 246323, 246325, 246327, 246329, 246331, 246333, 246335, 237505} -- MN Glimmer/Moxie

RECraftStatusTemplateMixin = CreateFromMixins(TableBuilderCellMixin)

function RECraftStatusTemplateMixin:Populate(rowData, _)
	if rowData.option.numAvailable then
		if tContains(RE.BucketsSeen, rowData.option.skillLineAbilityID) then
			if tContains(RE.BucketsFound, rowData.option.skillLineAbilityID) then
				ProfessionsTableCellTextMixin.SetText(self, "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t")
			else
				ProfessionsTableCellTextMixin.SetText(self, "|TInterface\\RaidFrame\\ReadyCheck-NotReady:0|t")
			end
		else
			ProfessionsTableCellTextMixin.SetText(self, "|TInterface\\RaidFrame\\ReadyCheck-Waiting:0|t")
		end
	else
		if rowData.option.orderType ~= Enum.CraftingOrderType.Personal then
			if tContains(RE.OrdersSeen[rowData.option.orderType], rowData.option.orderID) then
				if tContains(RE.OrdersFound[rowData.option.orderType], rowData.option.orderID) then
					ProfessionsTableCellTextMixin.SetText(self, "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t")
				else
					ProfessionsTableCellTextMixin.SetText(self, "|TInterface\\RaidFrame\\ReadyCheck-NotReady:0|t")
				end
			else
				ProfessionsTableCellTextMixin.SetText(self, "|TInterface\\RaidFrame\\ReadyCheck-Waiting:0|t")
			end
		end
	end
end

function RECraftPOFFIntegration(event, row, _, orderID)
	if event == "POFF_ORDER_INIT" then
		if not row.ProductIcon.RECraftState then
			row.ProductIcon.RECraftState = row.ProductIcon:CreateFontString(nil, "ARTWORK", "NumberFontNormal")
			row.ProductIcon.RECraftState:SetJustifyH("CENTER")
			row.ProductIcon.RECraftState:SetPoint("CENTER")
		end
		if tContains(RE.OrdersSeen[Enum.CraftingOrderType.Npc], orderID) then
			if tContains(RE.OrdersFound[Enum.CraftingOrderType.Npc], orderID) then
				row.ProductIcon.RECraftState:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:32|t")
			else
				row.ProductIcon.RECraftState:SetText("|TInterface\\RaidFrame\\ReadyCheck-NotReady:32|t")
			end
		else
			row.ProductIcon.RECraftState:SetText("|TInterface\\RaidFrame\\ReadyCheck-Waiting:32|t")
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
		ProfessionsFrame_LoadUI()
		RE.OP = ProfessionsFrame.OrdersPage
		if not RECraftSettings then
			RECraftSettings = RE.DefaultConfig
		end
		RE.Settings = RECraftSettings
		for key, value in pairs(RE.DefaultConfig) do
			if RE.Settings[key] == nil then
				RE.Settings[key] = value
			end
		end
		RE:ResetSearchQueue()
		LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("RECraft", RE.AceConfig)
		LibStub("AceConfigDialog-3.0"):AddToBlizOptions("RECraft", "RECraft")
	elseif event == "ADDON_LOADED" and ... == "PatronOffers" then
		PatronOffersRoot:RegisterOrderCallback(RECraftPOFFIntegration, false)
		PatronOffersRoot:HookScript("OnShow", function ()
			RE.OP.BrowseFrame.SearchButton:Show()
		end)
	elseif event == "CHAT_MSG_SYSTEM" and ... == ERR_CRAFTING_ORDER_RECEIVED then
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
		ProfessionsFrame:HookScript("OnHide", function() RE:SearchToggle("override") end)
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
		if #RE.ScanBucketQueue > 0 then
			RE.Request.selectedSkillLineAbility = RE.ScanBucketQueue[1]
			RequestCrafterOrders(RE.Request)
			table.remove(RE.ScanBucketQueue, 1)
		else
			RE.BucketScanInProgress = false
		end
	end
end

function RE:Notification()
	FlashClientIcon()
	PlaySoundFile("Interface\\AddOns\\RECraft\\Media\\TadaFanfare.ogg", "Master")
	if RE.NotificationType == Enum.CraftingOrderType.Public then
		RaidNotice_AddMessage(RaidWarningFrame, "|A:auctionhouse-icon-favorite:10:10|a "..strupper(PROFESSIONS_CRAFTING_FORM_ORDER_RECIPIENT_PUBLIC).." |A:auctionhouse-icon-favorite:10:10|a", ChatTypeInfo["RAID_WARNING"])
		RE.OP:RequestOrders(nil, false, false)
	elseif RE.NotificationType == Enum.CraftingOrderType.Guild then
		RaidNotice_AddMessage(RaidWarningFrame, "|A:auctionhouse-icon-favorite:10:10|a "..strupper(PROFESSIONS_CRAFTING_FORM_ORDER_RECIPIENT_GUILD).." |A:auctionhouse-icon-favorite:10:10|a", ChatTypeInfo["RAID_WARNING"])
		RE.OP.BrowseFrame.GuildOrdersButton:Click()
	elseif RE.NotificationType == Enum.CraftingOrderType.Personal then
		RaidNotice_AddMessage(RaidWarningFrame, "|A:auctionhouse-icon-favorite:10:10|a "..strupper(PROFESSIONS_CRAFTING_FORM_ORDER_RECIPIENT_PRIVATE).." |A:auctionhouse-icon-favorite:10:10|a", ChatTypeInfo["RAID_WARNING"])
	elseif RE.NotificationType == Enum.CraftingOrderType.Npc then
		RaidNotice_AddMessage(RaidWarningFrame, "|A:auctionhouse-icon-favorite:10:10|a "..strupper(PROFESSIONS_CRAFTER_ORDER_TAB_NPC.." "..HUD_EDIT_MODE_SETTING_MICRO_MENU_ORDER).." |A:auctionhouse-icon-favorite:10:10|a", ChatTypeInfo["RAID_WARNING"])
		RE.OP.BrowseFrame.NpcOrdersButton:Click()
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
		if Professions.GetReagentSlotStatus(v, RE.RecipeInfo) then
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

function RE:GetOrderReward(order)
	for _, v in pairs(order.npcOrderRewards) do
		if v.itemLink then
			local itemID = tonumber(select(3, string.find(v.itemLink, "item:(%d+)")))
			if tContains(RE.GlimmerItems, itemID) then
				return true
			end
		end
	end
	return false
end

function RE:ParseOrders(orderType)
	local newFound = false
	for _, v in pairs(RE.OrdersPayload) do
		if not tContains(RE.OrdersSeen[orderType], v.orderID) then
			wipe(RE.RecipeInfo)
			wipe(RE.RecipeSchematic)
			RE.RecipeInfo = GetRecipeInfoForSkillLineAbility(v.skillLineAbilityID)
			RE.RecipeSchematic = GetRecipeSchematic(RE.RecipeInfo.recipeID, v.isRecraft)
			if orderType == Enum.CraftingOrderType.Npc then
				-- Patron Filter
				if (not RE.Settings.ShowOnlyNpcOrderFirstCraftAndSkillUp or (RE.RecipeInfo.firstCraft or (RE.RecipeInfo.canSkillUp and RE.RecipeInfo.relativeDifficulty < Enum.TradeskillRelativeDifficulty.Trivial)))
				and (not RE.Settings.ShowOnlyNpcOrderWithRegents or (v.reagentState == Enum.CraftingOrderReagentsType.All))
				and (not RE.Settings.ShowOnlyNpcOrderWithGlimmer or RE:GetOrderReward(v))
				and RE:GetOrderViability(v) then
					newFound = true
					table.insert(RE.OrdersFound[orderType], v.orderID)
					if not tContains(RE.BucketsFound, v.skillLineAbilityID) then
						table.insert(RE.BucketsFound, v.skillLineAbilityID)
					end
				end
			else
				-- Public/Guild Filter
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
			table.insert(RE.ScanBucketQueue, v.skillLineAbilityID)
			if not tContains(RE.BucketsSeen, v.skillLineAbilityID) then
				table.insert(RE.BucketsSeen, v.skillLineAbilityID)
			end
		end
	end
	if #RE.ScanBucketQueue > 0 then
		RE.Request.selectedSkillLineAbility = RE.ScanBucketQueue[1]
		RequestCrafterOrders(RE.Request)
		table.remove(RE.ScanBucketQueue, 1)
	end
end

function RE:RequestCallback(orderType, displayBuckets)
	if displayBuckets then
		wipe(RE.BucketsFound)
		wipe(RE.BucketPayload)
		RE.BucketPayload = GetCrafterBuckets()
		RE:ParseBucket()
	else
		wipe(RE.OrdersPayload)
		RE.OrdersPayload = GetCrafterOrders()
		if RE:ParseOrders(orderType) then
			RE.NotificationType = orderType
			EVENT:SendMessage("RECRAFT_NOTIFICATION")
		end
		RE.StatusText:SetText("Parsed: "..(#RE.OrdersSeen[Enum.CraftingOrderType.Public] + #RE.OrdersSeen[Enum.CraftingOrderType.Guild] + #RE.OrdersSeen[Enum.CraftingOrderType.Npc]))
	end
end

function RE:SearchRequest()
	if not RE.OP.OrderView:IsShown() and not RE.BucketScanInProgress then
		RE.Request.selectedSkillLineAbility = nil
		if RE.ScanQueue[1] == Enum.CraftingOrderType.Public then
			RE.OrdersStatus = GetOrderClaimInfo(RE.Request.profession)
			RE.ClaimsRemaining = RE.Settings.ScanWithoutClaimsRemaining or RE.OrdersStatus.claimsRemaining > 0
		else
			RE.ClaimsRemaining = true
		end
		if IsNearProfessionSpellFocus(RE.Request.profession) then
			if RE.ClaimsRemaining then
				RE.Request.orderType = RE.ScanQueue[1]
				RequestCrafterOrders(RE.Request)
			elseif not RE.ClaimsRemaining and not RE.Settings.ScanGuildOrders and not RE.Settings.ScanNpcOrders then
				RE:SearchToggle()
			end
		else
			RE:SearchToggle()
		end
		table.remove(RE.ScanQueue, 1)
		if #RE.ScanQueue == 0 then
			RE:ResetSearchQueue()
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
		RE.ScanBucketQueue = {}
		RE.BucketScanInProgress = false
	end
end

function RE:ResetFilters()
	RE.OrdersSeen = {[Enum.CraftingOrderType.Public] = {}, [Enum.CraftingOrderType.Guild] = {}, [Enum.CraftingOrderType.Npc] = {}}
	RE.OrdersFound = {[Enum.CraftingOrderType.Public] = {}, [Enum.CraftingOrderType.Guild] = {}, [Enum.CraftingOrderType.Npc] = {}}
	RE.BucketsSeen = {}
	RE.BucketsFound = {}
	if RE.StatusText then
		RE.StatusText:SetText("Parsed: 0")
	end
end

function RE:ResetSearchQueue()
	RE.ScanQueue = {
		Enum.CraftingOrderType.Public,
		Enum.CraftingOrderType.Public,
		Enum.CraftingOrderType.Public,
		Enum.CraftingOrderType.Public,
		Enum.CraftingOrderType.Public,
		Enum.CraftingOrderType.Public
	}
	if RE.Settings.ScanGuildOrders and RE.Settings.ScanNpcOrders then
		RE.ScanQueue[2] = Enum.CraftingOrderType.Npc
		RE.ScanQueue[3] = Enum.CraftingOrderType.Guild
	elseif RE.Settings.ScanGuildOrders then
		RE.ScanQueue[2] = Enum.CraftingOrderType.Guild
	elseif RE.Settings.ScanNpcOrders then
		RE.ScanQueue[2] = Enum.CraftingOrderType.Npc
	end
end

