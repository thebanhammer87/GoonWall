--[[-----------------------------------------------------------------------

An API for guild chat bridging as a transport

--]]-----------------------------------------------------------------------

--
-- Global to expose API
--
GoonWallAPI = {
    version = 1,
}


--- Send a message to the guild confederation.
-- @param addon The addon name (the same one used for the name of the TOC
--  file).
-- @param message The message to send. Accepts 8-bit data.
function GoonWallAPI.SendMessage(addon, message)
    -- Validate addon id
    assert(addon == C_AddOns.GetAddOnInfo(addon))
    goonwall.config.channel.guild:send(GOON_MTYPE_EXTERNAL, addon, message)
end


--- Insert a handler for addon messages from the guild confederation.
-- @param handler A callback function.
-- @param addon The name of the addon that you want to receive messages from
--  (the same one used for the name of the TOC file).  If the value '*' is
--  supplied, messages from all addons will be handled.
-- @param priority A signed integer indicating relative priority, lower value
--  is handled first.  The default is 0.
-- @return The ID that can be used to remove the handler.
function GoonWallAPI.AddMessageHandler(handler, addon, priority)
    local function generate_id(handler)
        local count = 0
        for _, e in ipairs(goonwall.api_table) do
            if handler == e[4] then
                count = count + 1
            end
        end
        return string.format('%s:%04X', tostring(handler), count)
    end

    -- Validate the arguments
    assert(priority % 1 == 0)
    if addon ~= '*' then
        assert(addon == C_AddOns.GetAddOnInfo(addon))
    end

    local id = generate_id(handler)
    goonwall.Debug(GOON_LOG_INFO, 'add API handler; id=%s, addon=%s, priority=%d', id, addon, priority)

    table.insert(goonwall.api_table, { id, addon, priority, handler })
    table.sort(goonwall.api_table, function(a, b)
        return a[2] < b[2]
    end)

    return id
end


--- Remove an addon message handler.
-- @param id The ID of the callback function to remove.
-- @return True if a matching handler is found, false otherwise.
function GoonWallAPI.RemoveMessageHandler(id)
    for i, e in ipairs(goonwall.api_table) do
        if id == e[1] then
            goonwall.Debug(GOON_LOG_INFO, 'remove API handler; id=%s, addon=%s, priority=%d', e[1], e[2], e[3])
            table.remove(goonwall.api_table, i)
            return true
        end
    end
    return false
end


--- Clear our portions or all of the dispatch table entries.
-- @param addon Optional identifier for the addon or '*'.  If nil,
--  all table entries will be removed.
--
-- Note: A '*' value passed as addon is not a wildcard in this context,
-- it will only match instances where the handler was installed with
-- '*' as the addon.
function GoonWallAPI.ClearMessageHandlers(addon)
    if addon == nil then
        goonwall.Debug(GOON_LOG_INFO, 'remove all API handlers')
        goonwall.api_table = {}
    else
        if addon ~= '*' then
            assert(addon == C_AddOns.GetAddOnInfo(addon))
        end
        for i = #goonwall.api_table, 1, -1 do
            local e = goonwall.api_table[i]
            if addon == e[2] then
                goonwall.Debug(GOON_LOG_INFO, 'remove API handler; id=%s, addon=%s, priority=%d', e[1], e[2], e[3])
                table.remove(goonwall.api_table, i)
            end
        end
    end
end


--- Query the hidden channels used by GoonWall.
-- @return An array of integer values for the channels in use.
function GoonWallAPI.GetChannelNumbers()
    local rv = {}
    if goonwall.config.channel.guild ~= nil then
        table.insert(rv, goonwall.config.channel.guild.number)
    end
    return rv
end

--- The API handler dispatcher
-- @param addon The sending addon
-- @param sender The sending player
-- @param guild_id Originating co-guild
-- @param message The message contents
function goonwall.APIDispatcher(addon, sender, guild_id, message, is_self)
    local echo = is_self
    if echo == nil then
        echo = goonwall.IsSelf(sender)
    end
    local guild = guild_id == goonwall.config.guild_id
    for _, e in ipairs(goonwall.api_table) do
        if addon == e[2] or addon == '*' then
            goonwall.Debug(GOON_LOG_INFO, 'dispatch API handler; id=%s, addon=%s, priority=%d', e[1], e[2], e[3])
            e[4](addon, sender, message, echo, guild)
        end
    end
end


