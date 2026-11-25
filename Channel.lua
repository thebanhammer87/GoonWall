--[[-----------------------------------------------------------------------

Imported Libraries

--]]-----------------------------------------------------------------------

local crc = LibStub:GetLibrary("Hash:CRC:16ccitt-1.0")
local base64 = LibStub:GetLibrary("Encoding:Hash:Base64BCA-1.0")


--[[-----------------------------------------------------------------------

Class Variables

--]]-----------------------------------------------------------------------

GoonChannel = {}
GoonChannel.__index = GoonChannel


--- GoonChannel constructor function.
-- @return An initialized GoonChannel instance.
function GoonChannel:new()
    local self = {}
    setmetatable(self, GoonChannel)
    return self:initialize()
end

function GoonChannel:initialize()
    self.frame_table = {}
    self.cversion = 0
    self.name = ''
    self.password = ''
    self.number = 0
    self.stale = true
    self.join_pending = false
    self.joined_at = nil
    self.churning = false
    self.retry_join_pending = false
    self.fdelay = GoonHoldDown:new(GOON_CHANNEL_FAILURE_HOLD, GOON_CHANNEL_FAILURE_HOLD_MAX)
    self.tx_queue = {}
    self.tx_hash = {}
    self.rx_queue = {}
    self.stats = {
        txcnt = 0,
        rxcnt = 0,
        sconn = 0,
        fconn = 0,
        leave = 0,
        disco = 0,
        churn = 0,
    }
    return self
end


--[[-----------------------------------------------------------------------

Channel Management Methods

--]]-----------------------------------------------------------------------

--- Configure the channel.
-- @param cversion Configuration version.
-- @param name Name of the channel.
-- @param password Password for the channel. (optional)
function GoonChannel:configure(cversion, name, password)
    assert(cversion == 1)
    assert(name and name ~= '')
    self.cversion = cversion
    self.name = name
    self.password = password and password or ''
    self.stale = false
    goonwall.Debug(GOON_LOG_INFO, 'configured channel; channel=%s, password=%s, cversion=%d, stale=%s',
            goonwall.Redact(self.name), goonwall.Redact(self.password), self.cversion, tostring(self.stale));
end


--- Clear the channel configuration.
function GoonChannel:clear()
    goonwall.Debug(GOON_LOG_INFO, 'clearing channel; number=%d, channel=%s', self.number, goonwall.Redact(self.name))
    self:leave()
    self:initialize()
end


--- Mark the channel as stale.
function GoonChannel:age()
    self.stale = true
    goonwall.Debug(GOON_LOG_DEBUG, 'marked stale; number=%d, channel=%s', self.number, goonwall.Redact(self.name))
end


--- Test if the channel is configured.
-- @return True if configured, false otherwise.
function GoonChannel:is_configured()
    goonwall.Debug(GOON_LOG_DEBUG, 'number=%d, name=%s, password=%s, cversion=%d, stale=%s',
            self.number, goonwall.Redact(self.name), goonwall.Redact(self.password), self.cversion, tostring(self.stale))
    return self.name and self.name ~= ''
end

--- Check if a connection exists to the custom channel.
-- @return True if connected, otherwise false.
function GoonChannel:is_connected()
    goonwall.Debug(GOON_LOG_DEBUG, 'checking number=%d, name=%s', self.number, goonwall.Redact(self.name))
    if self:is_configured() then
        self.number = GetChannelName(self.name)
        goonwall.Debug(GOON_LOG_DEBUG, 'confirmed number=%d, name=%s', self.number, goonwall.Redact(self.name))
        if self.number == 0 then
            return false
        else
            return true
        end
    else
        return false
    end
end

--- Check if channel configuration is stale.
-- @return True if stale, false otherwise.
function GoonChannel:is_stale()
    goonwall.Debug(GOON_LOG_DEBUG, 'number=%d, name=%s, password=%s, cversion=%d, stale=%s',
            self.number, goonwall.Redact(self.name), goonwall.Redact(self.password), self.cversion, tostring(self.stale))
    return self.stale
end


--- Join a bridge channel.
-- @return True if connection success, false otherwise.
function GoonChannel:join()


    if not self:is_configured() then

        -- Only join if we have the channel details
        return false

    elseif self.fdelay:hold() then

        -- Hold down in effect.
        return false

    elseif self:is_connected() then

        -- Already connected; once a churning connection holds, lift the backoff.
        if self.churning and self.joined_at and time() - self.joined_at >= GOON_CHANNEL_CHURN_WINDOW then
            self.churning = false
            self.fdelay:clear()
            goonwall.Debug(GOON_LOG_NOTICE, 'channel stable; number=%d, name=%s', self.number, goonwall.Redact(self.name))
        end
        return true

    elseif self.joined_at and time() - self.joined_at < GOON_CHANNEL_CHURN_WINDOW then

        -- Dropped right after joining: something keeps removing the channel.
        -- Back off instead of rejoining in a tight loop.
        self.stats.churn = self.stats.churn + 1
        self.joined_at = nil
        self.churning = true
        local expiry = self.fdelay:continue()
        goonwall.Debug(GOON_LOG_WARNING, 'channel dropped right after joining; rejoin held until %d; name=%s, churn=%d',
                expiry, goonwall.Redact(self.name), self.stats.churn)
        if type(GetChannelList) == 'function' then
            local list = { GetChannelList() }
            local slots = {}
            for i = 1, #list, 3 do
                local id, cname = list[i], list[i + 1]
                if goonwall.IsSecret(id) or goonwall.IsSecret(cname) then
                    tinsert(slots, '?')
                elseif cname == self.name then
                    tinsert(slots, format('%s=%s', tostring(id), goonwall.Redact(cname)))
                else
                    tinsert(slots, format('%s=%s', tostring(id), tostring(cname)))
                end
            end
            goonwall.Debug(GOON_LOG_WARNING, 'channel list at drop: %s', table.concat(slots, ', '))
        end
        self:schedule_join(expiry)
        return false

    elseif goonwall.InRestrictedInstance() then

        -- JoinTemporaryChannel is blocked in battlegrounds
        local lockdown, combat, instance = goonwall.RestrictionState()
        goonwall.Debug(GOON_LOG_DEBUG, 'join deferred; lockdown=%s, combat=%s, instance=%s',
                tostring(lockdown), tostring(combat), tostring(instance))
        self.join_pending = true
        return false

    else

        self.join_pending = false
        goonwall.Debug(GOON_LOG_INFO, 'joining channel; channel=%s, password=%s',
                goonwall.Redact(self.name), goonwall.Redact(self.password))
        JoinTemporaryChannel(self.name, self.password)
        local number = GetChannelName(self.name)

        if number == 0 then

            goonwall.Error('cannot create communication channel: %s', goonwall.Redact(self.name))
            self.stats.fconn = self.stats.fconn + 1
            self.fdelay:continue()
            return false

        else

            self.number = number
            self.joined_at = time()
            self.stats.sconn = self.stats.sconn + 1
            if not self.churning then
                self.fdelay:clear()
            end
            goonwall.Debug(GOON_LOG_NOTICE, 'joined channel; number=%d, name=%s, password=%s',
                    self.number, goonwall.Redact(self.name), goonwall.Redact(self.password))
            goonwall.Write('Connected to confederation on channel %d.', self.number)

            --
            -- Hide the channel
            --
            for i = 1, (type(GetChatWindowChannels) == 'function' and (NUM_CHAT_WINDOWS or 10) or 0) do
                GoonChannel.frame_table = { GetChatWindowChannels(i) }
                for j, v in ipairs(GoonChannel.frame_table) do
                    if v == self.name then
                        local frame = format('ChatFrame%d', i)
                        if _G[frame] then
                            goonwall.Debug(GOON_LOG_INFO, 'hiding channel: number=%d, name=%s, frame=%s',
                                    self.number, goonwall.Redact(self.name), frame)
                            GoonChannel.hide(_G[frame], self.name)
                        end
                    end
                end
            end

            return true

        end

    end

end

--- Retry the join once a hold-down expires.
-- @param expiry The time at which the hold-down ends.
function GoonChannel:schedule_join(expiry)
    if self.retry_join_pending or not (C_Timer and type(C_Timer.After) == 'function') then
        return
    end
    self.retry_join_pending = true
    C_Timer.After(math.max(1, expiry - time() + 1), function()
        self.retry_join_pending = false
        if self:is_configured() then
            goonwall.QueueChannelRefresh()
        end
    end)
end

function GoonChannel.hide(frame, name)
    local fn
    if type(ChatFrame_RemoveChannel) == 'function' then
        fn = function() ChatFrame_RemoveChannel(frame, name) end
    elseif frame and type(frame.RemoveChannel) == 'function' then
        fn = function() frame:RemoveChannel(name) end
    else
        goonwall.Debug(GOON_LOG_WARNING, 'no channel removal API found; channel stays visible.')
        return false
    end
    local ok, err = pcall(fn)
    if not ok then
        goonwall.Debug(GOON_LOG_WARNING, 'channel hide failed: %s', tostring(err))
    end
    return ok
end


--- Leave a bridge channel.
-- @return True if a disconnection occurred, false otherwise.
function GoonChannel:leave()
    if self:is_connected() then
        goonwall.Debug(GOON_LOG_INFO, 'leaving channel; number=%d, channel=%s, password=%s',
                self.number, goonwall.Redact(self.name), goonwall.Redact(self.password))
        LeaveChannelByName(self.name)
        self.stats.leave = self.stats.leave + 1
        self.number = 0
        return true
    else
        return false
    end
end


--[[-----------------------------------------------------------------------

Informational Methods

--]]-----------------------------------------------------------------------

--- Dump the channel status.
-- @param label An identifier for the channel.
function GoonChannel:dump_status(label)
    label = label or 'channel'
    goonwall.Write('%s: connected=%s, number=%d, channel=%s, password=%s, stale=%s (sconn=%d, fconn=%d, leave=%d, disco=%d, churn=%d)',
                label, tostring(self:is_connected()), self.number, goonwall.Redact(self.name),
                goonwall.Redact(self.password), tostring(self:is_stale()),
                self.stats.sconn, self.stats.fconn, self.stats.leave, self.stats.disco, self.stats.churn)
end


--[[-----------------------------------------------------------------------

Transmit Methods

--]]-----------------------------------------------------------------------

--- Sends an encoded message on the shared channel.
-- @param type The message type.
--   Accepted values are:
--     GOON_MTYPE_CHAT
--     GOON_MTYPE_BROADCAST
--     GOON_MTYPE_NOTICE
--     GOON_MTYPE_REQUEST
--     GOON_MTYPE_ADDON
--     GOON_MTYPE_EXTERNAL
-- @param ... Text of the message.
function GoonChannel:send(type, ...)
    -- Apply adaptation layer encoding
    local message = self:al_encode(type, ...)
    if not message:match('%S') then
        goonwall.Debug(GOON_LOG_WARNING, 'sending a blank message on channel %d', self.number)
    end
    goonwall.Debug(GOON_LOG_NOTICE, 'channel=%d, type=%d, message=%q', self.number, type, message)
    return self:tl_send(type, message)
end

function GoonChannel:al_encode(type, ...)
    local arg = {...}
    if type == GOON_MTYPE_BROADCAST then
        assert(#arg >= 1)
        assert(#arg <= 3)
        return strjoin(':', arg[1], arg[2] or '', arg[3] or '')
    elseif type == GOON_MTYPE_EXTERNAL then
        assert(#arg == 2)
        return strjoin(':', arg[1], base64.encode(arg[2]))
    else
        assert(#arg == 1)
        return arg[1]
    end
end

function GoonChannel:tl_send(type, message)
    local opcode
    if type == GOON_MTYPE_CHAT then
        opcode = 'C'
    elseif type == GOON_MTYPE_BROADCAST then
        opcode = 'B'
    elseif type == GOON_MTYPE_NOTICE then
        opcode = 'N'
    elseif type == GOON_MTYPE_REQUEST then
        opcode = 'R'
    elseif type == GOON_MTYPE_ADDON then
        opcode = 'M'
    elseif type == GOON_MTYPE_EXTERNAL then
        opcode = 'E'
    else
        goonwall.Debug(GOON_LOG_ERROR, 'unknown message type: %d', type)
        return
    end

    -- The guild tag is added at transmit time; it is unknown until the configuration loads.
    self:tl_enqueue(opcode, message)
    self:tl_flush()
end

local function format_segment(entry)
    return strsub(strjoin('#', entry.opcode, goonwall.config.guild_id, '', entry.message), 1, GOON_MAX_MESSAGE_LENGTH)
end

local function now()
    return type(GetTime) == 'function' and GetTime() or 0
end


local function send_segment(segment, number)
    if C_ChatInfo and type(C_ChatInfo.SendChatMessage) == 'function' then
        C_ChatInfo.SendChatMessage(segment, 'CHANNEL', nil, number)
    else
        SendChatMessage(segment, 'CHANNEL', nil, number)
    end
end


--- Add a message to the channel transmit queue, dropping the oldest when full.
-- @param opcode Segment opcode.
-- @param message Message content.
-- @return Number of messages in queue after the insertion.
function GoonChannel:tl_enqueue(opcode, message)
    while #self.tx_queue >= GOON_TX_QUEUE_MAX do
        local dropped = tremove(self.tx_queue, 1)
        goonwall.Debug(GOON_LOG_WARNING, 'transmit queue full; dropped message: %q', dropped.message)
    end
    tinsert(self.tx_queue, { opcode = opcode, message = message, time = now() })
    goonwall.Debug(GOON_LOG_DEBUG, 'enqueued message: %q', message)
    return #self.tx_queue
end

--- Remove a message from the channel transmit queue, skipping expired ones.
-- @return Queue entry removed or nil if queue is empty.
function GoonChannel:tl_dequeue()
    while true do
        local entry = tremove(self.tx_queue, 1)
        if not entry then
            return
        elseif now() - entry.time > GOON_TX_MAX_AGE then
            goonwall.Debug(GOON_LOG_WARNING, 'expired message dropped: %q', entry.message)
        else
            goonwall.Debug(GOON_LOG_DEBUG, 'dequeued message: %q', entry.message)
            return entry
        end
    end
end

--- Schedule one retry of the transmit queue.
function GoonChannel:tl_schedule()
    if self.retry_pending or not (C_Timer and type(C_Timer.After) == 'function') then
        return
    end
    self.retry_pending = true
    C_Timer.After(GOON_TX_RETRY, function()
        self.retry_pending = false
        if self:is_configured() then
            self:tl_flush()
        end
    end)
end

--- Transmit all messages in the channel transmit queue.
-- Segments stay queued while disconnected or in chat lockdown (risk #4).
-- @return Number of messages flushed.
function GoonChannel:tl_flush()
    if #self.tx_queue == 0 then
        return 0
    end
    goonwall.Debug(GOON_LOG_DEBUG, 'servicing transmit queue; channel=%d, %d message(s) queued.', self.number, #self.tx_queue)
    if not self:is_connected() then
        goonwall.Debug(GOON_LOG_WARNING, 'channel=%d, not connected.', self.number)
        self:tl_schedule()
        return 0
    end
    if goonwall.InChatLockdown() then
        goonwall.Debug(GOON_LOG_NOTICE, 'chat messaging lockdown; %d segment(s) held.', #self.tx_queue)
        self:tl_schedule()
        return 0
    end
    if not goonwall.config.valid then
        goonwall.Debug(GOON_LOG_NOTICE, 'guild configuration not loaded; %d segment(s) held.', #self.tx_queue)
        self:tl_schedule()
        return 0
    end
    local count = 0
    while true do
        local entry = self:tl_dequeue()
        if not entry then
            break
        end
        local segment = format_segment(entry)
        local hash = crc.Hash(segment)
        self.tx_hash[hash] = (self.tx_hash[hash] or 0) + 1
        goonwall.Debug(GOON_LOG_INFO, 'channel=%d, segment=%q', self.number, segment)
        local ok, err = pcall(send_segment, segment, self.number)
        if not ok then
            goonwall.Debug(GOON_LOG_WARNING, 'send failed; requeued: %s', tostring(err))
            self.tx_hash[hash] = self.tx_hash[hash] > 1 and self.tx_hash[hash] - 1 or nil
            tinsert(self.tx_queue, 1, entry)
            self:tl_schedule()
            break
        end
        self.stats.txcnt = self.stats.txcnt + 1
        count = count + 1
    end
    return count
end


--[[-----------------------------------------------------------------------

Receive Methods

--]]-----------------------------------------------------------------------

--- Handler for data received on a channel.
-- @param f A callback function.
-- @param ... The API event arguments.
-- @return The return value of f applied to the data.
function GoonChannel:receive(f, ...)
    local sender, guild_id, mtype, message, is_self = self:tl_receive(...)
    if message ~= nil then
        local content = self:al_decode(mtype, message)
        if mtype == GOON_MTYPE_EXTERNAL then
            -- API traffic is handled regardless of the sender.
            if content ~= nil then
                local addon, api_message = unpack(content)
                if addon ~= nil and api_message ~= nil then
                    goonwall.APIDispatcher(addon, sender, guild_id, api_message, is_self)
                end
            end
        elseif not is_self and guild_id ~= goonwall.config.guild_id then
            -- Process the chat message if it from another co-guild.
            goonwall.Debug(GOON_LOG_NOTICE, 'channel=%d, type=%d, sender=%s, guild=%s, message=%q',
                    self.number, mtype, sender, guild_id, message)
            return f(mtype, guild_id, content, {...})
        end
    end
end

--- Adaptation layer decoding.
-- @param mtype message type
-- @param message message content
-- @return A table of message strings. Returns nil on error.
function GoonChannel:al_decode(mtype, message)
    local function expand(message, n)
        assert(type(n) == 'number' and n > 0)
        message = type(message) == 'string' and message or ''
        local t = { strsplit(':', message, n) }
        for i = 1, n do
            t[i] = t[i] ~= nil and t[i] or ''
        end
        return t
    end

    goonwall.Debug(GOON_LOG_DEBUG, 'type=%d, message=%q', mtype, message)
    if mtype == GOON_MTYPE_BROADCAST then
        return expand(message, 3)
    elseif mtype == GOON_MTYPE_EXTERNAL then
        local tag, data = unpack(expand(message, 2))
        local rv, result = pcall(base64.decode, data)
        if (rv) then
            return { tag, result }
        else
            goonwall.Debug(GOON_LOG_DEBUG, 'API error: %s', result)
            return
        end
    else
        return { message }
    end
end

function GoonChannel:tl_receive(...)
    local segment, sender = select(1, ...)
    local guid = select(12, ...)

    if not goonwall.IsUsableString(segment) or goonwall.IsSecret(sender) or goonwall.IsSecret(guid) then
        goonwall.Debug(GOON_LOG_DEBUG, 'channel=%d, dropped unusable or secret segment; secret segment=%s, sender=%s, guid=%s',
                self.number, tostring(goonwall.IsSecret(segment)), tostring(goonwall.IsSecret(sender)),
                tostring(goonwall.IsSecret(guid)))
        return
    end

    -- Forever senders are "First Last" with no realm; never split them.
    sender = goonwall.NormalizeName(sender)
    local is_self = goonwall.LearnPlayerName(sender, guid) or goonwall.IsSelf(sender, guid)
    goonwall.Debug(GOON_LOG_INFO, 'channel=%d, sender=%s, self=%s, segment=%q',
            self.number, tostring(sender), tostring(is_self), segment)
    self.stats.rxcnt = self.stats.rxcnt + 1

    -- Check the segment hash
    if is_self then
        local hash = crc.Hash(segment)
        if self.tx_hash[hash] and self.tx_hash[hash] > 0 then
            goonwall.Debug(GOON_LOG_DEBUG, 'channel=%d, tx_hash[0x%04X] == %d', self.number, hash, self.tx_hash[hash])
            self.tx_hash[hash] = self.tx_hash[hash] - 1
            if self.tx_hash[hash] <= 0 then
                self.tx_hash[hash] = nil
            end
        else
            goonwall.Debug(GOON_LOG_WARNING, 'channel=%d, tx_hash[0x%04X] not found', self.number, hash)
            goonwall.Error('Message corruption detected.  Please disable add-ons that might modify messages on channel %d.', self.number)
        end
    end

    -- Process the segment
    local opcode, guild_id, _, message = strsplit('#', segment, 4)
    guild_id = guild_id or '-'
    message = message or ''
    goonwall.Debug(GOON_LOG_DEBUG, 'opcode=%s, guild_id=%s, message=%q', opcode, guild_id, message)

    local type = GOON_MTYPE_NONE
    if opcode == 'C' then
        type = GOON_MTYPE_CHAT
    elseif opcode == 'B' then
        type = GOON_MTYPE_BROADCAST
    elseif opcode == 'N' then
        type = GOON_MTYPE_NOTICE
    elseif opcode == 'R' then
        type = GOON_MTYPE_REQUEST
    elseif opcode == 'M' then
        type = GOON_MTYPE_ADDON
    elseif opcode == 'E' then
        type = GOON_MTYPE_EXTERNAL
    else
        goonwall.Debug(GOON_LOG_WARNING, 'unknown segment opcode: %s', opcode)
    end
    return sender, guild_id, type, message, is_self
end

