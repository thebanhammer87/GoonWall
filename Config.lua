--[[-----------------------------------------------------------------------

Imported Libraries

--]]-----------------------------------------------------------------------

local crc = LibStub:GetLibrary("Hash:CRC:16ccitt-1.0")
local semver = LibStub:GetLibrary("SemanticVersion-1.0")


--[[-----------------------------------------------------------------------

Class Variables

--]]-----------------------------------------------------------------------

GoonConfig = {}
GoonConfig.__index = GoonConfig


--- GoonConfig constructor function.
-- @return An initialized GoonConfig instance.
function GoonConfig:new()
    local self = {}
    setmetatable(self, GoonConfig)
    self:initialize_param()
    self:initialize_state()
    return self
end


--- Initialize a GoonConfig object with the default parameters.
-- @return The initialized GoonConfig instance.
function GoonConfig:initialize_param()
    self.valid = false
    self.cversion = 0
    self.minimum = ''
    self.guild_id = ''
    self.peer = {}
    return self
end


--- Initialize a GoonConfig object with the default state.
-- @return The initialized GoonConfig instance.
function GoonConfig:initialize_state()
    self.channel = {
        guild   = GoonChannel:new(),
    }
    self.timer = {
        channel = GoonHoldDown:new(goonwall.settings:get('joindelay')),
        config  = GoonHoldDown:new(GOON_TIMEOUT_CONFIG_HOLD),
        reload  = GoonHoldDown:new(GOON_TIMEOUT_RELOAD_HOLD),
    }
    self.comember_cache = GoonHoldDownCache:new(GOON_CACHE_COMEMBER_HOLD,
            GOON_CACHE_COMEMBER_SOFT_MAX, GOON_CACHE_COMEMBER_HARD_MAX)

    return self
end


--- Dump configuration attributes.
function GoonConfig:dump(keep)
    local function dump_tier(t, level)
        level = level == nil and 0 or level
        local indent = strrep('  ', level)
        local index = {}
        for i in pairs(t) do
            table.insert(index, i)
        end
        table.sort(index)
        for i, k in ipairs(index) do
            if type(t[k]) == 'table' then
                goonwall.Write("%s%s:", indent, k, tostring(t[k]))
                dump_tier(t[k], level + 1)
            else
                if type(t[k]) == 'string' then
                    if k == 'name' or k == 'password' then
                        goonwall.Write("%s%s = <<%04X>>", indent, k, crc.Hash(tostring(t[k])))
                    else
                        goonwall.Write("%s%s = '%s'", indent, k, tostring(t[k]))
                    end
                else
                    goonwall.Write("%s%s = %s", indent, k, tostring(t[k]))
                end
            end
        end
    end

    goonwall.Write('[Settings]')
    dump_tier(GoonWall, 0)
    goonwall.Write('[Configuration]')
    dump_tier(self, 0)
end

--- Dump a status summary.
function GoonConfig:dump_status()
    goonwall.Write('version=%s, cversion=%d, configured=%s', goonwall.version, self.cversion, tostring(self.valid))
    self.channel.guild:dump_status('guild bridge')
end


--- Parse the guild information page to gather configuration information.
-- @return True if successful, false otherwise.
function GoonConfig:load()
    local function substitute(cstr, xlat)
        local estr, count = string.gsub(cstr, '%$(%a)', function(s) return xlat[s] end)
        if count > 0 then
            goonwall.Debug(GOON_LOG_DEBUG, "expanded '%s' to '%s'", cstr, estr)
        end
        return estr
    end
    
    local xlat = {}                     -- Translation table for string substitution.
    local seen_tags = {}

    -- Abort if current configuration is valid
    if self.valid then
        goonwall.Debug(GOON_LOG_DEBUG, 'configuration valid; skipping.')
        return false
    end

    -- Abort if not in a guild
    local guild_name = goonwall.GetGuildName()
    local guild_base = goonwall.GetGuildBaseName and goonwall.GetGuildBaseName()
    if guild_name then
        goonwall.Debug(GOON_LOG_INFO, 'co-guild is %s', guild_name)
    else
        goonwall.Debug(GOON_LOG_WARNING, 'not in a guild.')
        return false
    end

    -- Abort if configuration is not yet available
    local info                          -- Guild information text.
    if C_GuildInfo and C_GuildInfo.GetInfoText then
        info = C_GuildInfo.GetInfoText()
    else
        info = GetGuildInfoText()
    end
    if info == '' then
        goonwall.Debug(GOON_LOG_WARNING, 'guild configuration not available.')
        return false
    end

    goonwall.Debug(GOON_LOG_INFO, 'parsing guild configuration.')



    -- Soft reset of configuration
    self:initialize_param()
    for k, channel in pairs(self.channel) do
        channel:age()
    end

    -- Update the channel hold-down
    self.timer.channel:set(goonwall.settings:get('joindelay'))

    --
    -- Check configuration version
    --
    if strmatch(info, 'GWc=".*"') then
        goonwall.Error('Guild configuration uses a format not supported by this version.')
    end
    if strmatch(info, 'GW:?c:') then
        self.cversion = 1
    end

    if self.cversion == 1 then
        --
        -- Parse version 1 configuration
        --
        for buffer in gmatch(info, 'GW:?(%l:[^\n]*)') do

            if buffer ~= nil then

                self.cversion = 1
                
                -- Groom configuration entries.
                local field = {}
                for i, v in ipairs({ strsplit(':', buffer) }) do
                    field[i] = strtrim(v)
                end

                if field[1] == 'c' then
                    -- Guild channel configuration
                    if field[2] and field[2] ~= '' then
                        self.channel.guild:configure(1, field[2], field[3])
                    else
                        goonwall.Error('invalid common channel name specified')
                    end

                elseif field[1] == 'p' then
                    -- Peer guild
                    local peer_raw = substitute(field[2], xlat)
                    local peer_name = goonwall.GlobalName(peer_raw)
                    local peer_id = substitute(field[3], xlat)
                    if seen_tags[peer_id] then
                        goonwall.Error('Guild Info: tag "%s" is used by both "%s" and "%s"; each GWp tag must be unique.',
                                peer_id, seen_tags[peer_id], peer_raw)
                    end
                    seen_tags[peer_id] = peer_raw
                    if goonwall.iCmp(guild_name, peer_name) or
                            (guild_base and goonwall.iCmp(guild_base, peer_raw)) then
                        self.guild_id = peer_id
                        goonwall.Debug(GOON_LOG_DEBUG, 'guild=%s (%s)', guild_name, peer_id);
                    else
                        self.peer[peer_id] = peer_name
                        goonwall.Debug(GOON_LOG_DEBUG, 'peer=%s (%s)', peer_name, peer_id);
                    end
                elseif field[1] == 's' then
                    local key = field[3]
                    local val = field[2]
                    if string.len(key) == 1 then
                        xlat[key] = val
                        goonwall.Debug(GOON_LOG_DEBUG, "parser substitution added, '$%s' := '%s'", key, val)
                    else
                        goonwall.Debug(GOON_LOG_ERROR, "invalid parser substitution key, '$%s'", key)
                    end
                elseif field[1] == 'v' then
                    -- Minimum version
                    if strmatch(field[2], '^%d+%.%d+%.%d+%w*$') then
                        self.minimum = tostring(semver(field[2]));
                        goonwall.Debug(GOON_LOG_DEBUG, 'minimum version set to %s', self.minimum);
                    end
                elseif field[1] == 'o' then
                    -- Deprecated option list
                    local optlist = { strsplit(',', gsub(field[2], '%s+', '')) }
                    for i, opt in ipairs(optlist) do
                        local key, val = strsplit('=', opt)
                        key = strlower(key)
                        val = strlower(val)
                        if key == 'mv' then
                            if strmatch(val, '^%d+%.%d+%.%d+%w*$') then
                                self.minimum = tostring(semver(val));
                                goonwall.Debug(GOON_LOG_DEBUG, 'minimum version set to %s', self.minimum);
                            end
                        end
                    end
                end
            end
        end

        self.valid = true
    end

    --
    -- Version check
    --
    local min = semver(self.minimum)
    local cur = semver(goonwall.version)
    if min and cur then
        if cur < min then
            goonwall.Error('Guild configuration specifies a minimum version of %s (%s currently installed).', tostring(min), tostring(cur))
        end
    end

    --
    -- Clean up.  self.channel is a hash table keyed by 'guild',
    -- so ipairs() does not iterate it -- use pairs() so stale channels
    -- left over from a previous configuration actually get cleared.
    --
    for _, channel in pairs(self.channel) do
        if channel:is_stale() then
            channel:clear()
        end
    end
    if self.valid then
        self.timer.config:start()
    end

    return true;

end


--- Initiate a reload of the configuration.
-- @return True is refresh submitted, false otherwise.
function GoonConfig:reload()
    self.valid = false
    local request_roster = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster
    if type(request_roster) == 'function' then
        request_roster()
        goonwall.Debug(GOON_LOG_INFO, 'roster update requested.')
    else
        goonwall.Debug(GOON_LOG_WARNING, 'no guild roster API found.')
    end
    return true
end


--- Initiate a refresh of the configuration.
-- This is a reload protected by a hold-down timer.
-- @return True is refresh submitted, false otherwise.
function GoonConfig:refresh()
    if self.timer.config:hold() then
        goonwall.Debug(GOON_LOG_WARNING, 'skipping due to hold-down.')
        return false
    else
        return self:reload()
    end
end


--- Initiate a reset and reload of the configuration.
-- This is a disruptive reset of the configuration and state.
-- @return True is refresh submitted, false otherwise.
function GoonConfig:reset()
    self:initialize_param(true)
    for _, channel in pairs(self.channel) do
        channel:clear()
    end
    return self:reload()
end


--- Check a guild for peer status.
-- @param guild The name of the guild to check.
-- @return True if the target guild is a peer co-guild, false otherwise.
function GoonConfig:is_peer(guild)
    for i, v in pairs(self.peer) do
        if v == guild then
            return true
        end
    end
    return false
end


--- Refresh the channel state.
function GoonConfig:refresh_channels()
    if self.timer.channel:hold() then
        goonwall.Debug(GOON_LOG_INFO, 'channel join blocked.')
    else
        goonwall.Debug(GOON_LOG_INFO, 'refreshing channels.')
        self.channel.guild:join()
    end
end


--- Check a guild for membership within the confederation.
-- @param guild The name of the guild to check.
-- @return True if the target guild is in the confederation, false otherwise.
function GoonConfig:is_container(guild)
    if guild == goonwall.GetGuildName() then
        return self.guild_id ~= nil
    else
        return self:is_peer(guild)
    end
end

