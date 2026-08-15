--[[
	Uranium loader.

	This file is the loadstring. It holds no features and almost never changes —
	everything a user runs comes back from the API at boot, so shipping a new
	build means uploading to the VPS, not pushing here.

	Publish it as `loader.lua` in the public repo alongside `Assets/`:

		loadstring(game:HttpGet("https://raw.githubusercontent.com/<you>/yellowcake/main/loader.lua"))()

	LOADER is the contract version. Bump it when this file changes in a way the
	server cares about; the server refuses anything below its MIN_LOADER, which
	is how a mirrored copy of an old loader gets turned off.
]]

-- CHANGE THIS ONE LINE: paste your Worker URL, keep the /v1/boot on the end.
local ENDPOINT = "https://uranium-api.maxbob-com.workers.dev/v1/boot"

local LOADER   = 1

-- Deliberately empty. On a VPS this pointed at a copy of the build on GitHub,
-- so an outage wasn't a total outage — but that copy was also the one thing
-- somebody could take without ever going through the API. Workers doesn't fall
-- over the way a single box does, so there's nothing left to buy with it.
local FALLBACK = ""

local HttpService = game:GetService("HttpService")
local Players     = game:GetService("Players")

-- Executors disagree on where the POST-capable http function lives, and a few
-- only have HttpGet. Everything below is guarded because none of it exists in
-- Studio.
local httpRequest = (syn and syn.request)
	or (http and http.request)
	or http_request
	or request

local function try(fn, ...)
	local ok, res = pcall(fn, ...)
	if ok then return res end
	return nil
end

local function identity()
	local hwid = try(function()
		return game:GetService("RbxAnalyticsService"):GetClientId()
	end)
	if not hwid and gethwid then
		hwid = try(gethwid)
	end

	local place = try(function()
		return game:GetService("MarketplaceService")
			:GetProductInfo(game.PlaceId).Name
	end)

	return {
		loader   = LOADER,
		hwid     = tostring(hwid or "unknown"),
		place    = tostring(game.PlaceId),
		job      = tostring(game.JobId),
		name     = place or "",
		executor = (identifyexecutor and try(identifyexecutor)) or "unknown",
		user     = Players.LocalPlayer and Players.LocalPlayer.UserId or 0,
	}
end

-- Returns (body, status). status is nil when the request never landed, which is
-- the only case the GitHub fallback is allowed to cover — a server that answered
-- "revoked" has answered, and falling through to a mirror would undo it.
local function boot()
	local payload = HttpService:JSONEncode(identity())

	if httpRequest then
		local res = try(httpRequest, {
			Url     = ENDPOINT,
			Method  = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body    = payload,
		})
		if res then
			return res.Body, res.StatusCode or res.Status or 0
		end
		return nil, nil
	end

	-- No request(): degrade to GET with the identity in the query string.
	local url = ENDPOINT .. "?d=" .. HttpService:UrlEncode(payload)
	local body = try(function() return game:HttpGet(url, true) end)
	return body, body and 200 or nil
end

local body, status = boot()

if not status then
	-- API unreachable. With FALLBACK set this would fetch a copy off GitHub so
	-- an outage isn't a total outage; empty, there's simply nothing to run.
	body = FALLBACK ~= "" and try(function() return game:HttpGet(FALLBACK, true) end) or nil
	if not body or #body == 0 then
		return warn("[Uranium] can't reach the server — try again in a minute.")
	end
elseif status ~= 200 then
	-- A non-200 body is still Lua: the server hands back a stub that explains
	-- itself (out of date, banned, hub disabled) rather than a bare error.
	if not body or #body == 0 then
		return warn("[Uranium] refused by the server (" .. tostring(status) .. ").")
	end
end

local fn, err = loadstring(body)
if not fn then
	return warn("[Uranium] payload didn't compile: " .. tostring(err))
end

return fn()
