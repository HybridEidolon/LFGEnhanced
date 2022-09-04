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

	if type(category_id) == "number" then
		C_LFGList.Search(category_id, active_entry.activityIDs)
	end
end

-- Process the current LFGList search results.
local function DisplayMessagesForCurrentSearchResults()
	local result_count, results = C_LFGList.GetFilteredSearchResults()

	if not C_LFGList.HasActiveEntryInfo() then
		-- Don't do anything unless there is an active LFG entry.
		return
	end

	local active_entry = C_LFGList.GetActiveEntryInfo()

	local group_member_counts = GetGroupMemberCounts()

	local looking_for_your_roles = 0
	local greater_than_1 = 0
	local your_roles = C_LFGList.GetRoles()
	for _, v in ipairs(results) do
		local result_info = C_LFGList.GetSearchResultInfo(v)
		local result_members = result_info.numMembers
		local member_counts = C_LFGList.GetSearchResultMemberCounts(v)
		local group_needs_you = false

		if member_counts ~= nil then
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

		if result_members > 1 then
			greater_than_1 = greater_than_1 + 1
		end
	end

	if looking_for_your_roles > 0 then
		SendSystemMessage(format("LFG: %d Groups. %d need your roles. %d have more than 1 member.", result_count, looking_for_your_roles, greater_than_1))
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
