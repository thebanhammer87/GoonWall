local pat_online = ERR_FRIEND_ONLINE_SS:format('(.+)', '(.+)'):gsub('([%[%]])', '%%%1')
local pat_online_raw = "(.+) has come online."
local pat_offline = ERR_FRIEND_OFFLINE_S:format('(.+)')
local pat_join = ERR_GUILD_JOIN_S:format('(.+)')
local pat_leave = ERR_GUILD_LEAVE_S:format('(.+)')
local pat_quit = ERR_GUILD_QUIT_S:format('(.+)')
local pat_removed = ERR_GUILD_REMOVE_SS:format('(.+)', '(.+)')
local pat_kick = ERR_GUILD_REMOVE_SELF

GoonSystemEventHandler = { config = nil, player = nil }

function GoonSystemEventHandler:new(obj)
    obj = obj or {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function GoonSystemEventHandler:run()
end

GoonOnlineSystemEventHandler = GoonSystemEventHandler:new()

function GoonOnlineSystemEventHandler:run()
    self.config.comember_cache:hold(self.player)
    goonwall.Debug(GOON_LOG_DEBUG, 'comember_cache: updated %s', self.player)
end

GoonOfflineSystemEventHandler = GoonSystemEventHandler:new()

function GoonOfflineSystemEventHandler:run()
    self.config.comember_cache:hold(self.player)
    goonwall.Debug(GOON_LOG_DEBUG, 'comember_cache: updated %s', self.player)
end

GoonJoinSystemEventHandler = GoonSystemEventHandler:new()

function GoonJoinSystemEventHandler:run()
    if goonwall.IsSelf(self.player) then
        goonwall.Debug(GOON_LOG_NOTICE, 'guild join detected.')
        self.config.channel.guild:send(GOON_MTYPE_BROADCAST, 'join')
    end
end

GoonLeaveSystemEventHandler = GoonSystemEventHandler:new()

function GoonLeaveSystemEventHandler:run()
    if goonwall.IsSelf(self.player) then
        goonwall.Debug(GOON_LOG_NOTICE, 'guild quit detected.')
        self.config.channel.guild:send(GOON_MTYPE_BROADCAST, 'leave')
        self.config:reset()
    end
end

GoonQuitSystemEventHandler = GoonSystemEventHandler:new()

function GoonQuitSystemEventHandler:run()
    goonwall.Debug(GOON_LOG_NOTICE, 'guild quit detected.')
    self.config.channel.guild:send(GOON_MTYPE_BROADCAST, 'leave')
    self.config:reset()
end

GoonRemoveSystemEventHandler = GoonSystemEventHandler:new()

function GoonRemoveSystemEventHandler:run()
    if goonwall.IsSelf(self.player) then
        goonwall.Debug(GOON_LOG_NOTICE, 'guild kick detected.')
        self.config.channel.guild:send(GOON_MTYPE_BROADCAST, 'remove')
        self.config:reset()
    end
end

GoonKickSystemEventHandler = GoonSystemEventHandler:new()

function GoonKickSystemEventHandler:run()
    goonwall.Debug(GOON_LOG_NOTICE, 'guild kick detected.')
    self.config.channel.guild:send(GOON_MTYPE_BROADCAST, 'leave')
    self.config:reset()
end

GoonPromoteSystemEventHandler = GoonSystemEventHandler:new()

function GoonSystemEventHandler:factory(config, message)
    if not goonwall.IsUsableString(message) then
        return GoonSystemEventHandler:new({ config = config })
    end

    -- Remove coloring
    message = string.gsub(message, "|c%w%w%w%w%w%w%w%w([^|]*)|r", "%1")

    if message:match(pat_online) then

        local _, player = message:match(pat_online)
        player = goonwall.NormalizeName(player)
        goonwall.Debug(GOON_LOG_NOTICE, 'player online: %s', player)
        return GoonOnlineSystemEventHandler:new({ config = config, player = player })

    elseif message:match(pat_online_raw) then

        local player = message:match(pat_online_raw)
        player = goonwall.NormalizeName(player)
        goonwall.Debug(GOON_LOG_NOTICE, 'player online: %s', player)
        return GoonOnlineSystemEventHandler:new({ config = config, player = player })

    elseif message:match(pat_offline) then

        local player = message:match(pat_offline)
        player = goonwall.NormalizeName(player)
        goonwall.Debug(GOON_LOG_NOTICE, 'player offline: %s', player)
        return GoonOfflineSystemEventHandler:new({ config = config, player = player })

    elseif message:match(pat_join) then

        local player = message:match(pat_join)
        player = goonwall.NormalizeName(player)
        goonwall.Debug(GOON_LOG_NOTICE, 'player join: %s', player)
        return GoonJoinSystemEventHandler:new({ config = config, player = player })

    elseif message:match(pat_leave) then

        local player = message:match(pat_leave)
        player = goonwall.NormalizeName(player)
        goonwall.Debug(GOON_LOG_NOTICE, 'player leave: %s', player)
        return GoonLeaveSystemEventHandler:new({ config = config, player = player })

    elseif message:match(pat_quit) then

        local player = goonwall.player
        player = goonwall.NormalizeName(player)
        goonwall.Debug(GOON_LOG_NOTICE, 'player leave: %s', player)
        return GoonQuitSystemEventHandler:new({ config = config, player = player })

    elseif message:match(pat_removed) then

        local player = message:match(pat_removed)
        player = goonwall.NormalizeName(player)
        goonwall.Debug(GOON_LOG_NOTICE, 'player removed: %s', player)
        return GoonRemoveSystemEventHandler:new({ config = config, player = player })

    elseif message:match(pat_kick) then

        local player = goonwall.player
        player = goonwall.NormalizeName(player)
        goonwall.Debug(GOON_LOG_NOTICE, 'player removed: %s', player)
        return GoonKickSystemEventHandler:new({ config = config, player = player })

    else

        -- Unhandled system message
        return GoonSystemEventHandler:new({ config = config })

    end

end