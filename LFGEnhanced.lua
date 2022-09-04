-- local _, namespace = ...

local frame = CreateFrame("Frame")
-- local LFGBrowseFrame = _G["LFGBrowseFrame"]
-- local WorldFrame = _G["WorldFrame"]

local AUTO_SEARCH_REFRESH_INTERVAL_SECONDS = 60.0

local auto_search_deadline = nil

local function ResetAutoSearchDeadline()
	auto_search_deadline = GetTimePreciseSec() + AUTO_SEARCH_REFRESH_INTERVAL_SECONDS
end

if C_LFGList.HasActiveEntryInfo() then
	ResetAutoSearchDeadline()
end

local function DeactivateEntryAutoSearch()
	SendSystemMessage("LFGEnhanced auto-search deactivated.")
	auto_search_deadline = nil
end

local function ActivateEntryAutoSearch()
	SendSystemMessage("LFGEnhanced auto-search activated.")
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

-- This function can only be called for HW execution contexts.
local function AutoSearchCurrentEntry()
	ResetAutoSearchDeadline()
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
		if category_id ~= nil then
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

	for _, v in ipairs(results) do
		local result_info = C_LFGList.GetSearchResultInfo(v)
		local result_members = result_info.numMembers
		local member_counts = C_LFGList.GetSearchResultMemberCounts(v)
		local group_needs_you = false

		if member_counts ~= nil and result_members < 5 then
			if your_roles.tank == true and member_counts.TANK == 0 then
				group_needs_you = true
			end

			if your_roles.healer == true and member_counts.HEALER == 0 then
				group_needs_you = true
			end

			if your_roles.dps == true and member_counts.DAMAGER < 3 then
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

	for _, v in ipairs(FilterSoloEntries(results)) do
		local member_counts = C_LFGList.GetSearchResultMemberCounts(v)
		local include_entry = false

		if need_tank > 0 and member_counts.TANK > 0 then
			include_entry = true
			available_tanks = available_tanks + 1
		end
		if need_healer > 0 and member_counts.HEALER > 0 then
			include_entry = true
			available_healers = available_healers + 1
		end
		if need_dps > 0 and member_counts.DAMAGER > 0 then
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

	["LFG_LIST_SEARCH_RESULT_UPDATED"] = function (...)
		local search_result_id = ...
		local result_info = C_LFGList.GetSearchResultInfo(search_result_id)
	end,

	["LFG_LIST_ACTIVE_ENTRY_UPDATE"] = function (...)
		local has_active_entry_info = C_LFGList.HasActiveEntryInfo()
		if not has_active_entry_info then
			DeactivateEntryAutoSearch()
			return
		end

		local active_entry_info = C_LFGList.GetActiveEntryInfo()

		-- Active entry contains multiple activity IDs in Classic.
		for _, v in ipairs(active_entry_info.activityIDs) do
			local activity_info = C_LFGList.GetActivityInfoTable(v)

			-- Only auto-search for activities which use dungeon role expectations.
			if not activity_info.useDungeonRoleExpectations then
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
		AutoSearchCurrentEntry()
	end
end

-- Hook all mouse scripts
WorldFrame:HookScript("OnMouseDown", HandleInputEvent)
WorldFrame:HookScript("OnMouseUp", HandleInputEvent)
WorldFrame:HookScript("OnGamePadStick", HandleInputEvent)
