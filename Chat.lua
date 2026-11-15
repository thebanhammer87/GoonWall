--[[-----------------------------------------------------------------------

High-level chat functions.

--]]-----------------------------------------------------------------------

local semver = LibStub:GetLibrary("SemanticVersion-1.0")

--- Callback handler for guild chat messages.
-- @param type Message type received.
-- @param guild_id ID of the guild the message was received from.
-- @param content Message content as a table.
-- @param arglist API event arguments.
function goonwall.handlerGuildChat(type, guild_id, content, arglist)
    goonwall.Debug(GOON_LOG_DEBUG, 'type=%d, guild_id=%s, #content=%d, #arglist=%d', type, guild_id, #content, #arglist)
    local sender = arglist[2]
    if type == GOON_MTYPE_CHAT then
        goonwall.ReplicateMessage('GUILD', content[1], guild_id, arglist)
    elseif type == GOON_MTYPE_BROADCAST then
        local action, target, rank = unpack(content)
        if action == 'join' then
            if goonwall.settings:get('roster') then
                goonwall.ReplicateMessage('SYSTEM', format(ERR_GUILD_JOIN_S, sender), guild_id, arglist)
            end
        elseif action == 'leave' then
            if goonwall.settings:get('roster') then
                goonwall.ReplicateMessage('SYSTEM', format(ERR_GUILD_LEAVE_S, sender), guild_id, arglist)
            end
        elseif action == 'remove' then
            if goonwall.settings:get('roster') then
                goonwall.ReplicateMessage('SYSTEM', format(ERR_GUILD_REMOVE_SS, target, sender), guild_id, arglist)
            end
        end
    else
        goonwall.Debug(GOON_LOG_WARNING, 'unhandled message type: %d', type)
    end
end


-- Event types whose Blizzard handler failed this session; rendered directly.
goonwall.render_fallback = {}


--- Draw a line on a chat frame without the Blizzard event pipeline.
-- @param frame A chat frame.
-- @param event 'GUILD' or 'SYSTEM'.
-- @param message The message text.
-- @param sender The sender name ('' for system lines).
-- @param guid (optional) The sender GUID, for class colour.
function goonwall.RenderMessage(frame, event, message, sender, guid)
    local text = message
    if event ~= 'SYSTEM' and goonwall.IsUsableString(sender) then
        local name = sender
        if goonwall.IsUsableString(guid) and type(GetPlayerInfoByGUID) == 'function' and
                C_ClassColor and type(C_ClassColor.GetClassColor) == 'function' then
            local ok, _, class = pcall(GetPlayerInfoByGUID, guid)
            local color = ok and class and C_ClassColor.GetClassColor(class)
            if color and color.WrapTextInColorCode then
                name = color:WrapTextInColorCode(name)
            end
        end
        local link = format('|Hplayer:%s|h[%s]|h', sender, name)
        local prefix = _G['CHAT_' .. event .. '_GET']
        if type(prefix) == 'string' then
            text = format(prefix, link) .. message
        else
            text = link .. ': ' .. message
        end
    end
    local info = ChatTypeInfo and ChatTypeInfo[event]
    if info then
        frame:AddMessage(text, info.r, info.g, info.b, info.id)
    else
        frame:AddMessage(text)
    end
end


--- Copies a message received on a common channel to all chat window instances of a
-- target chat channel.
-- @param event Chat message event to generate.
-- Accepted values:
-- 'GUILD'
-- 'SYSTEM'
-- @param message The message to replicate.
-- @param guild_id (optional) Guild ID of the sender.
-- @param arglist (optional) API event arguments.
function goonwall.ReplicateMessage(event, message, guild_id, arglist)
    guild_id = guild_id and guild_id or '-'
    arglist = type(arglist) == 'table' and arglist or {}
    local sender = arglist[2] and arglist[2] or ''
    local language = arglist[3]
    local target = arglist[5]
    local flags = arglist[6]
    local line = arglist[11]
    local guid = arglist[12]
    -- 12.x handlers index a trailing table arg (Forever: ChatFrameOverrides 'discordInfo').
    local extra = type(arglist[18]) == 'table' and arglist[18] or {}

    goonwall.Debug(GOON_LOG_INFO, 'event=%s, guild_id=%s, message=%q', event, guild_id, message)

    if goonwall.settings:get('tag') and event ~= 'SYSTEM' then
        message = format('<%s> %s', guild_id, message)
    end

    for i = 1, NUM_CHAT_WINDOWS do
        if i ~= 2 then
            -- skip combat log
            goonwall.frame_table = { GetChatWindowMessages(i) }
            for _, v in ipairs(goonwall.frame_table) do
                if v == event then
                    local frame = _G['ChatFrame' .. i]
                    if frame then
                        goonwall.Debug(GOON_LOG_DEBUG, 'frame=ChatFrame%d, event=%s, sender=%s, message=%q',
                                i, event, sender, message)
                        local ok, err = false, 'fallback'
                        if not goonwall.render_fallback[event] then
                            ok, err = pcall(goonwall.ChatFrame_MessageEventHandler, frame,
                                    'CHAT_MSG_' .. event, message, sender, language, '', target, flags,
                                    0, 0, '', 0, line, guid, 0, false, false, false, false, extra)
                            if not ok then
                                goonwall.render_fallback[event] = true
                                goonwall.Debug(GOON_LOG_ERROR, 'chat injection failed, rendering directly; event=%s, error=%s',
                                        event, tostring(err))
                            end
                        end
                        if not ok then
                            local rok, rerr = pcall(goonwall.RenderMessage, frame, event, message, sender, guid)
                            if not rok then
                                goonwall.Debug(GOON_LOG_ERROR, 'render failed; error=%s', tostring(rerr))
                            end
                        end
                    end
                    break
                end
            end
        end
    end
end


