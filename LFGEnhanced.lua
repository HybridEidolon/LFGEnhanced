-- local _, namespace = ...

local frame = CreateFrame("Frame")
-- local LFGBrowseFrame = _G["LFGBrowseFrame"]
-- local WorldFrame = _G["WorldFrame"]

local AUTO_SEARCH_REFRESH_INTERVAL_SECONDS = 30.0
local GROUP_FINDER_CATEGORY_DUNGEONS = 2
local GROUP_FINDER_CATEGORY_HEROIC_DUNGEONS = 117
local GROUP_FINDER_CATEGORY_RAIDS = 114

local auto_search_deadline = nil

local function ResetAutoSearchDeadline()
	auto_search_deadline = GetTimePreciseSec() + AUTO_SEARCH_REFRESH_INTERVAL_SECONDS
end

if C_LFGList.HasActiveEntryInfo() then
	ResetAutoSearchDeadline()
end

local function DeactivateEntryAutoSearch()
	auto_search_deadline = nil
end

local function ActivateEntryAutoSearch()
	ResetAutoSearchDeadline()
end

-- Partially-applicable (curried) table filter function
local function filter(predicate)
	return function(table)
		local newtab = {}
		for _, v in ipairs(table) do
			if predicate(v) then
				newtab[#newtab+1] = v
			end
		end
		return newtab
	end
end

local FilterSoloEntries = filter(function (search_result_id)
	local result_info = C_LFGList.GetSearchResultInfo(search_result_id)
	if result_info == nil then
		return false
	end

	local result_members = result_info.numMembers
	return result_members == 1
end)

local FilterOutMyEntry = filter(function (search_result_id)
	local result_info = C_LFGList.GetSearchResultInfo(search_result_id)
	-- hasSelf is unique to classic
	return not result_info.hasSelf
end)

-- This function can only be called for HW execution contexts.
local function SearchLFGForActiveEntry()
	if not C_LFGList.HasActiveEntryInfo() then
		return
	end

	local active_entry = C_LFGList.GetActiveEntryInfo()
	local category_id = nil

	-- Just take the first category. Technically the active entry could be for
	-- any activities across multiple categories, but searches require the
	-- category. If this addon ever supports multi-category searches that can
	-- be handled elsewhere.
	for _, v in ipairs(active_entry.activityIDs) do
		local activity_info = C_LFGList.GetActivityInfoTable(v)
		if category_id == nil then
			category_id = activity_info.categoryID
		end
	end

	-- In the DBC, categories 2 and 117 are Dungeons and Heroic Dungeons.
	-- Raids are 114. Maybe for later...

	if type(category_id) == "number" then
		C_LFGList.Search(category_id, active_entry.activityIDs)
	end
end

-- Display system messages for a solo entry in the LFG List.
local function DisplaySoloEntryMessages()
	local _, results = C_LFGList.GetFilteredSearchResults()

	-- This assumes the standard Tank, Healer, 3 DPS party configuration
	local looking_for_your_roles = 0
	local your_roles = C_LFGList.GetRoles()

	for _, v in ipairs(FilterOutMyEntry(results)) do
		local result_info = C_LFGList.GetSearchResultInfo(v)
		local result_members = result_info.numMembers
		local member_counts = C_LFGList.GetSearchResultMemberCounts(v)
		local group_needs_you = false

		if result_members == 1 do
			-- Solo entries use LEADER_ROLE_<ROLE> keys
			local is_tank = member_counts.LEADER_ROLE_TANK
			local is_healer = member_counts.LEADER_ROLE_HEALER
			local is_dps = member_counts.LEADER_ROLE_DAMAGER
			if is_tank and (your_roles.healer or your_roles.dps) then
				group_needs_you = true
			end
			if is_healer and (your_roles.tank or your_roles.dps) then
				group_needs_you = true
			end
			if is_dps then
				group_needs_you = true
			end
		else
			if your_roles.tank == true and member_counts.TANK_REMAINING > 0 then
				group_needs_you = true
			end

			if your_roles.healer == true and member_counts.HEALER_REMAINING > 0 then
				group_needs_you = true
			end

			if your_roles.dps == true and member_counts.DAMAGE_REMAINING > 0 then
				group_needs_you = true
			end
		end

		if group_needs_you then
			looking_for_your_roles = looking_for_your_roles + 1
		end
	end

	if looking_for_your_roles > 0 then
		SendSystemMessage(format(
			"LFG: %d Results are looking for your selected roles.",
			looking_for_your_roles
		))
	else
		SendSystemMessage("LFG: No candidate Results.")
	end
end

-- Display system messages for a party entry in the LFG List.
-- Selects all solo entries matching the search criteria and checks their listed
-- roles. If your party needs one of their roles, it is included in the count.
local function DisplayPartyEntryMessages()
	local _, results = C_LFGList.GetFilteredSearchResults()

	-- {DAMAGER, TANK, HEALER, NOROLE}
	local member_counts = GetGroupMemberCounts()

	if member_counts == nil then
		-- blizzard api bug?
		error("member_counts = nil")
		return
	end

	-- PartyUtil GetGroupMemberCountsForDisplay says NOROLE = DAMAGER
	local need_tank = 1 - member_counts.TANK
	local need_healer = 1 - member_counts.HEALER
	local need_dps = 3 - (member_counts.DAMAGER + member_counts.NOROLE)

	local available_candidates = 0
	local available_tanks = 0
	local available_healers = 0
	local available_dps = 0

	for _, v in ipairs(FilterSoloEntries(FilterOutMyEntry(results))) do
		local result_info = C_LFGList.GetSearchResultInfo(v)
		local member_counts = C_LFGList.GetSearchResultMemberCounts(v)
		local include_entry = false

		if need_tank > 0 and member_counts["LEADER_ROLE_TANK"] then
			include_entry = true
			available_tanks = available_tanks + 1
		end

		if need_healer > 0 and member_counts["LEADER_ROLE_HEALER"] then
			include_entry = true
			available_healers = available_healers + 1
		end

		if need_dps > 0 and member_counts["LEADER_ROLE_DAMAGER"] then
			include_entry = true
			available_dps = available_dps + 1
		end

		if include_entry then
			available_candidates = available_candidates + 1
		end
	end

	if available_candidates > 0 then
		-- Maybe this should play a sound and highlight the LFG minimap eye?
		SendSystemMessage(format(
			"LFM: %d Results (%d T/%d H/%d D).",
			available_candidates,
			available_tanks,
			available_healers,
			available_dps
		))
	else
		SendSystemMessage("LFM: No candidate Results.")
	end
end

-- Process the current LFGList search results.
local function DisplayMessagesForCurrentSearchResults()
	if not C_LFGList.HasActiveEntryInfo() then
		-- Don't do anything if there is not an active LFG entry.
		return
	end

	local total_group_members = GetNumGroupMembers(LE_PARTY_CATEGORY_HOME)

	if total_group_members < 2 then
		DisplaySoloEntryMessages()
	else
		DisplayPartyEntryMessages()
	end
end

local function BindEvents(frame, event_handlers)
	local on_event_script = function (self, event, ...)
		local handler = event_handlers[event]
		if type(handler) == "function" then
			handler(...)
		end
	end

	for k, _ in pairs(event_handlers) do
		frame:RegisterEvent(k)
	end

	frame:SetScript("OnEvent", on_event_script)
end

BindEvents(frame, {
	["LFG_LIST_SEARCH_RESULTS_RECEIVED"] = function (...)
		if auto_search_deadline ~= nil then
			ResetAutoSearchDeadline()
		end

		DisplayMessagesForCurrentSearchResults()
	end,

	["LFG_LIST_ACTIVE_ENTRY_UPDATE"] = function (...)
		if not C_LFGList.HasActiveEntryInfo() then
			DeactivateEntryAutoSearch()
			return
		end

		local active_entry_info = C_LFGList.GetActiveEntryInfo()

		-- Active entry contains multiple activity IDs in Classic.
		for _, v in ipairs(active_entry_info.activityIDs) do
			local activity_info = C_LFGList.GetActivityInfoTable(v)

			-- Only auto-search for Dungeons and Heroics categories
			local category_id = activity_info.categoryID
			if category_id ~= GROUP_FINDER_CATEGORY_DUNGEONS and category_id ~= GROUP_FINDER_CATEGORY_HEROIC_DUNGEONS then
				return
			end
		end

		ActivateEntryAutoSearch()
	end,
})

local function HandleInputEvent(self)
	if not C_LFGList.HasActiveEntryInfo() then
		return
	end

	if GetTimePreciseSec() >= auto_search_deadline then
		ResetAutoSearchDeadline()
		SearchLFGForActiveEntry()
	end
end

-- Hook all mouse scripts
WorldFrame:HookScript("OnMouseDown", HandleInputEvent)
WorldFrame:HookScript("OnMouseUp", HandleInputEvent)
WorldFrame:HookScript("OnGamePadStick", HandleInputEvent)
