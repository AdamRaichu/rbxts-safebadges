--[[
    SafeBadges - Developed by @erazias
    Last updated: August 20th 2024
--]]

local BadgeService = game:GetService("BadgeService")
local RunService = game:GetService("RunService")

local FastFlags = {
	ATTEMPT_LIMIT = 5 :: number,
	RETRY_DELAY = 1 :: number,
	BACKOFF_FACTOR = 2 :: number,
	DEBUG_PRINTS = true :: boolean,
}

local function log(level: (string) -> nil, message: string)
	if FastFlags.DEBUG_PRINTS then
		level(message)
	end
end

if RunService:IsClient() then
	return log(warn, "Please require SafeBadges from a server script.")
end

local function SetFastFlag(FastFlag: string, value: any)
	if FastFlags[FastFlag] ~= nil then
		FastFlags[FastFlag] = value
	else
		log(warn, "Invalid FastFlag: " .. tostring(FastFlag))
	end
end

local badgeCache: {[number]: {[number]: boolean}} = {}

local function HasBadges(player: Player, badgeIds: {number}): {[number]: boolean}
	if #badgeIds > 10 then
		log(warn, ("[SafeBadges | HasBadges()] Exceeded badge limit. Only 10 badges are allowed per request."))
		return {}
	elseif #badgeIds <= 0 then
		log(warn, ("[SafeBadges | HasBadges()] You must enter a valid badge ID."))
		return {}
	end

	local userId = player.UserId
	badgeCache[userId] = badgeCache[userId] or {}

	local badgesToCheck = {}
	for _, badgeId in ipairs(badgeIds) do
		if badgeCache[userId][badgeId] == nil then
			table.insert(badgesToCheck, badgeId)
		end
	end

	if #badgesToCheck == 0 then
		local cachedResults = {}
		for _, badgeId in ipairs(badgeIds) do
			cachedResults[badgeId] = badgeCache[userId][badgeId]
		end
		return cachedResults
	end

	log(print, ("[SafeBadges | HasBadges()] Checking if %s has badges %s"):format(player.Name, table.concat(badgesToCheck, ", ")))

	local attemptIndex: number = 0
	local success, ownedBadgeIds: {number} = false, {}

	while attemptIndex < FastFlags.ATTEMPT_LIMIT do
		attemptIndex += 1
		log(print, ("[SafeBadges | HasBadges()] Attempt %d to check if %s has badges %s"):format(attemptIndex, player.Name, table.concat(badgesToCheck, ", ")))

		success, ownedBadgeIds = pcall(function()
			return BadgeService:CheckUserBadgesAsync(player.UserId, badgesToCheck)
		end)

		if success then
			break
		else
			log(warn, ("[SafeBadges | HasBadges()] Attempt %d failed: %s"):format(attemptIndex, tostring(ownedBadgeIds)))
			task.wait(FastFlags.RETRY_DELAY)
			FastFlags.RETRY_DELAY *= FastFlags.BACKOFF_FACTOR
		end
	end

	if not success then
		log(warn, ("[SafeBadges | HasBadges()] Failed to check badges after %d attempts: %s"):format(FastFlags.ATTEMPT_LIMIT, tostring(ownedBadgeIds)))
		ownedBadgeIds = {}
	end

	for _, badgeId in ipairs(badgeIds) do
		badgeCache[userId][badgeId] = false
	end
	for _, ownedBadgeId in ipairs(ownedBadgeIds) do
		badgeCache[userId][ownedBadgeId] = true
	end

	local result: {[number]: boolean} = {}
	for _, badgeId in ipairs(badgeIds) do
		result[badgeId] = badgeCache[userId][badgeId] or false
	end

	return result
end

local function AwardBadges(player: Player, badgeIds: {number}): {[number]: {boolean | string}}
	if #badgeIds > 10 then
		log(warn, ("[SafeBadges | AwardBadges()] Exceeded badge limit. Only 10 badges are allowed per request."))
		return {}
	elseif #badgeIds <= 0 then
		log(warn, ("[SafeBadges | AwardBadges()] You must enter a valid badge ID."))
		return {}
	end

	local badgeOwnership = HasBadges(player, badgeIds)
	local badgesToAward: {number} = {}

	for _, badgeId in ipairs(badgeIds) do
		if not badgeOwnership[badgeId] then
			table.insert(badgesToAward, badgeId)
		end
	end

	local resultStatus: {[number]: {boolean | string}} = {}
	local retryDelay: number = FastFlags.RETRY_DELAY

	local function retryAwarding(badgeIds: {number}): {number}
		local failedBadges: {number} = {}
		for _, badgeId in ipairs(badgeIds) do
			if not badgeCache[player.UserId] then
				badgeCache[player.UserId] = {}
			end

			if not badgeCache[player.UserId][badgeId] then
				log(print, ("[SafeBadges | AwardBadges()] Attempting to award badge %d to player %s"):format(badgeId, player.Name))
				local success: boolean, awarded: {number} = pcall(function()
					BadgeService:AwardBadge(player.UserId, badgeId)
					return BadgeService:CheckUserBadgesAsync(player.UserId, {badgeId})
				end)

				if success and awarded[1] == badgeId then
					log(print, ("[SafeBadges | AwardBadges()] Badge %d successfully awarded to player %s"):format(badgeId, player.Name))
					badgeCache[player.UserId][badgeId] = true
					resultStatus[badgeId] = {true, "Badge awarded successfully."}
				elseif success then
					log(warn, ("[SafeBadges | AwardBadges()] Badge %d not awarded, retrying..."):format(badgeId))
					table.insert(failedBadges, badgeId)
				else
					log(warn, ("[SafeBadges | AwardBadges()] Error while awarding badge %d: %s"):format(badgeId, tostring(awarded)))
					table.insert(failedBadges, badgeId)
				end
			else
				log(print, ("[SafeBadges | AwardBadges()] Player %s already has badge %d."):format(player.Name, badgeId))
				resultStatus[badgeId] = {true, "Player already has the badge."}
			end
		end

		return failedBadges
	end

	local attemptIndex: number = 0
	local failedBadges: {number} = badgesToAward

	while attemptIndex < FastFlags.ATTEMPT_LIMIT and #failedBadges > 0 do
		attemptIndex += 1
		failedBadges = retryAwarding(failedBadges)
		if #failedBadges > 0 then
			log(print, ("[SafeBadges | AwardBadges()] Waiting for %f seconds before retrying..."):format(retryDelay))
			task.wait(retryDelay)
			retryDelay = retryDelay * FastFlags.BACKOFF_FACTOR
		end
	end

	for _, badgeId in ipairs(failedBadges) do
		if not badgeCache[player.UserId][badgeId] then
			log(error, ("[SafeBadges | AwardBadges()] Failed to award badge %d after %d attempts."):format(badgeId, FastFlags.ATTEMPT_LIMIT))
			resultStatus[badgeId] = {false, "Failed to award badge after multiple attempts."}
		end
	end

	return resultStatus
end

return {
	HasBadges = HasBadges,
	AwardBadges = AwardBadges,
	SetFastFlag = SetFastFlag
}