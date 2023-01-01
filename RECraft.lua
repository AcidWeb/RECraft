local _G = _G
local _, RE = ...
_G.RECraft = RE

local Timer = _G.C_Timer
local FlashClientIcon = _G.FlashClientIcon
local GetCrafterOrders = _G.C_CraftingOrders.GetCrafterOrders
local GetOrderClaimInfo = _G.C_CraftingOrders.GetOrderClaimInfo
local RequestCrafterOrders = _G.C_CraftingOrders.RequestCrafterOrders
local RaidNotice_AddMessage = _G.RaidNotice_AddMessage
local IsNearProfessionSpellFocus = _G.C_TradeSkillUI.IsNearProfessionSpellFocus
local GetRecipeInfoForSkillLineAbility = _G.C_TradeSkillUI.GetRecipeInfoForSkillLineAbility
local OP = _G.ProfessionsFrame.OrdersPage
local ElvUI = _G.ElvUI

RE.OrdersPayload = {}
RE.OrdersStatus = {}
RE.OrdersSeen = {[Enum.CraftingOrderType.Public] = {}, [Enum.CraftingOrderType.Guild] = {}}
RE.RequestNext = Enum.CraftingOrderType.Public
RE.RecipeInfo = {}
RE.Initialized = false

RE.AceConfig = {
	type = "group",
	args = {
		Guild = {
			name = "Check guild orders",
			desc = "Also monitor the changes in guild craft orders.",
			type = "toggle",
			width = "full",
			order = 1,
			set = function(_, val) RE.Settings.ScanGuildOrders = val end,
			get = function(_) return RE.Settings.ScanGuildOrders end
		},
		SkillUp = {
			name = "Only first crafts and skill ups",
			desc = "Trigger notification only if detected order is first craft or provide skill up.",
			type = "toggle",
			width = "full",
			order = 2,
			set = function(_, val) RE.Settings.ShowOnlyFirstCraftAndSkillUp = val end,
			get = function(_) return RE.Settings.ShowOnlyFirstCraftAndSkillUp end
		},
		Tip = {
			name = "Smallest acceptable tip",
			desc = "Orders with a smaller tip will be ignored.",
			type = "input",
			width = "normal",
			order = 3,
			pattern = "%d",
			usage = "Enter the amount of gold.",
			set = function(_, val) RE.Settings.MinimumTipInCopper = val * 10000 end,
			get = function(_) return tostring(RE.Settings.MinimumTipInCopper / 10000) end
		},
		IgnoredItems = {
			name = "Ignored items",
			desc = "Comma-separated list of ItemIDs whose orders will be ignored.",
			type = "input",
			width = "double",
			order = 4,
			set = function(_, val)
				local input = {strsplit(",", val)}
				for k, v in pairs(input) do
					input[k] = tonumber(v)
				 end
				RE.Settings.IgnoredItemID = input
			end,
			get = function(_) return table.concat(RE.Settings.IgnoredItemID, ",") end
		}
	}
}
RE.DefaultConfig = {
	ShowOnlyFirstCraftAndSkillUp = false,
	ScanGuildOrders = false,
	MinimumTipInCopper = 0,
	IgnoredItemID = {}
}

function RE:OnLoad(self)
	self:RegisterEvent("ADDON_LOADED")
	self:RegisterEvent("CHAT_MSG_SYSTEM")
	self:RegisterEvent("TRADE_SKILL_SHOW")

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
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "CHAT_MSG_SYSTEM" and ... == _G.ERR_CRAFTING_ORDER_RECEIVED then
		FlashClientIcon()
		RaidNotice_AddMessage(_G.RaidWarningFrame, "|A:Vehicle-HammerGold:20:20|a  "..strupper(_G.PROFESSIONS_CRAFTING_FORM_ORDER_RECIPIENT_PRIVATE).."  |A:Vehicle-HammerGold:20:20|a", _G.ChatTypeInfo["RAID_WARNING"])
		PlaySoundFile("Interface\\AddOns\\RECraft\\Media\\TadaFanfare.ogg")
	elseif event == "TRADE_SKILL_SHOW" then
		RE.Request.profession = OP.professionInfo.profession

		if not RE.Initialized then
			RE.Initialized = true
			local button = CreateFrame("Button", nil, OP.BrowseFrame.SearchButton, "RefreshButtonTemplate")
			if ElvUI then
				ElvUI[1]:GetModule("Skins"):HandleButton(button)
				button:Size(22)
			end
			button:SetPoint("LEFT", OP.BrowseFrame.SearchButton, "RIGHT")
			button:SetScript("OnClick", RE.SearchToggle)

			RE.StatusText = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
			RE.StatusText:SetPoint("BOTTOM", OP.BrowseFrame.SearchButton, "TOP", 0, 2)

			_G.ProfessionsFrame:HookScript("OnHide", function() RE:SearchToggle("override") end)
			OP.OrderView:HookScript("OnHide", RE.RestartSpinner)
			hooksecurefunc(OP, "ShowGeneric", RE.RestartSpinner)
		end
	end
end

function RE:RestartSpinner()
	if RE.Timer then
		OP.BrowseFrame.OrderList.LoadingSpinner:Show()
		OP.BrowseFrame.OrderList.SpinnerAnim:Restart()
	end
end

function RE:ParseOrders(orderType)
	local newFound = false
	for _, v in pairs(RE.OrdersPayload) do
		if not tContains(RE.OrdersSeen[orderType], v.orderID) then
			RE.RecipeInfo = GetRecipeInfoForSkillLineAbility(v.skillLineAbilityID)
			if RE.RecipeInfo.learned and not tContains(RE.Settings.IgnoredItemID, v.itemID) and v.tipAmount >= RE.Settings.MinimumTipInCopper and (not RE.Settings.ShowOnlyFirstCraftAndSkillUp or (RE.RecipeInfo.firstCraft or RE.RecipeInfo.canSkillUp)) then
				newFound = true
			end
			tinsert(RE.OrdersSeen[orderType], v.orderID)
		end
	end
	return newFound
end

function RE:RequestCallback(orderType)
	RE.OrdersPayload = GetCrafterOrders()
	if RE:ParseOrders(orderType) then
		FlashClientIcon()
		PlaySoundFile("Interface\\AddOns\\RECraft\\Media\\TadaFanfare.ogg")
		if orderType == Enum.CraftingOrderType.Public then
			RaidNotice_AddMessage(_G.RaidWarningFrame, "|A:Vehicle-HammerGold:20:20|a  "..strupper(_G.PROFESSIONS_CRAFTING_FORM_ORDER_RECIPIENT_PUBLIC).."  |A:Vehicle-HammerGold:20:20|a", _G.ChatTypeInfo["RAID_WARNING"])
			OP:RequestOrders(nil, false, false)
		elseif orderType == Enum.CraftingOrderType.Guild then
			RaidNotice_AddMessage(_G.RaidWarningFrame, "|A:Vehicle-HammerGold:20:20|a  "..strupper(_G.PROFESSIONS_CRAFTING_FORM_ORDER_RECIPIENT_GUILD).."  |A:Vehicle-HammerGold:20:20|a", _G.ChatTypeInfo["RAID_WARNING"])
		end
	end
	RE.StatusText:SetText("Parsed: "..(#RE.OrdersSeen[Enum.CraftingOrderType.Public] + #RE.OrdersSeen[Enum.CraftingOrderType.Guild]))
end

function RE:SearchRequest()
	if not OP.OrderView:IsShown() then
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
		RE.Timer = Timer.NewTicker(15, RE.SearchRequest)
		RE:SearchRequest()
		RE:RestartSpinner()
	elseif RE.Timer then
		RE.Timer:Cancel()
		RE.Timer = nil
		OP.BrowseFrame.OrderList.LoadingSpinner:Hide()
		OP.BrowseFrame.OrderList.SpinnerAnim:Stop()
	end
end