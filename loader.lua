local ENDPOINT = "https://uranium-api.maxbob-com.workers.dev/v1/boot"
local LoaderVersion   = 1

local HttpServ = game:GetService("HttpService")
local Plrs = game:GetService("Players")


local function try(fn, ...)
	local succ, res = pcall(fn, ...)
	if succ then return res end
	return nil
end

local function logWarning(msg)
    return warn(`[Uranium] {msg}`)
end

local httpRequest = (http and http.request) or http_request or request
if not httpRequest then return logWarning("no HTTP request function available") end

local function identity()
    local hwid = try(gethwid)
	if not hwid then
		return logWarning("failed to get hardware ID")
	end
	local place = try(function()
		return game:GetService("MarketplaceService"):GetProductInfoAsync(game.PlaceId).Name
	end)

	return {
		loader = LoaderVersion,
		hwid = tostring(hwid or "unknown"),
		place = tostring(game.PlaceId),
		job = tostring(game.JobId),
		name = place or "",
		executor = (identifyexecutor and try(identifyexecutor)) or "unknown",
		user = Plrs.LocalPlayer and Plrs.LocalPlayer.UserId or 0,
	}
end

local function boot()
	local payload = HttpServ:JSONEncode(identity())

	if httpRequest then
		local res = try(httpRequest, {
			Url = ENDPOINT,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = payload,
		})
		if res then
			return res.Body, res.StatusCode or res.Status or 0
		end
		return nil, nil
	end
    
    local url = `{ENDPOINT}?d={HttpServ:UrlEncode(payload)}`
	local body = try(function() return game:HttpGet(url, true) end)
	return body, body and 200 or nil
end

local body, status = boot()

if not status then
	return warn("Uranium offline, check discord for status updates.")
elseif status ~= 200 then
	if not body or #body == 0 then
		return logWarning(`refused by the server ("{tostring(status)})"`)
	end
end

local fn, err = loadstring(body)
if not fn then
	return logWarning(`payload didn't compile: {tostring(err)}`)
end

return fn()
