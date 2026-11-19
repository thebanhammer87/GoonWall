--[[-----------------------------------------------------------------------

Imported Libraries

--]]-----------------------------------------------------------------------

local crc = LibStub:GetLibrary("Hash:CRC:16ccitt-1.0")


---------------------------------------------------------------------------
-- Logic functions
---------------------------------------------------------------------------

--- Case insensitive string comparison.
-- @param a A string
-- @param b A string
-- @return True if the strings match in all respects except case, false otherwise.
function goonwall.iCmp(a, b)
    if string.lower(a) == string.lower(b) then
        return true
    else
        return false
    end
end


---------------------------------------------------------------------------
-- Logging functions
---------------------------------------------------------------------------

--- Add a message to the log file
-- @param msg A string to write to the log.
function goonwall.Log(msg)
    if goonwall.settings and goonwall.settings:get('log') then
        local ts = date('%Y-%m-%d %H:%M:%S')
        tinsert(GoonWallLog, format('%s -- %s', ts, msg))
        while #GoonWallLog > goonwall.settings:get('logsize') do
            tremove(GoonWallLog, 1)
        end
    end
end


--- Report verbose debug lines not shown while chat was restricted.
-- @return True if chat is no longer restricted, false otherwise.
function goonwall.ReportSuppressedDebug()
    if goonwall.InRestrictedChat() then
        return false
    end
    if goonwall.suppressed_debug > 0 then
        local n = goonwall.suppressed_debug
        goonwall.suppressed_debug = 0
        goonwall.Write('%d debug line(s) not shown during combat or battleground; see the log.', n)
    end
    return true
end


--- Write a message to the default chat frame.
-- @param ... A list of the string and arguments for substitution using the syntax of string.format.
function goonwall.Write(...)
    local msg = string.format(unpack({ ... }))
    DEFAULT_CHAT_FRAME:AddMessage('|cff0bda51GoonWall:|r ' .. msg)
    goonwall.Log(msg)
end


--- Write an error message to the default chat frame.
-- @param ... A list of the string and arguments for substitution using the syntax of string.format.
function goonwall.Error(...)
    local msg = string.format(unpack({ ... }))
    DEFAULT_CHAT_FRAME:AddMessage('|cffabd473GoonWall:|r |cffff6000[ERROR] ' .. msg)
    goonwall.Log('[ERROR] ' .. msg)
end


--- Write a debugging message to the default chat frame with a detail level.
-- Messages will be filtered with the "/goonwall debug <level>" command.
-- @param level A positive integer specifying the debug level to display this under.
-- @param ... A list of the string and arguments for substitution using the syntax of string.format.
function goonwall.Debug(level, ...)
    if not goonwall.settings or level > goonwall.settings:get('debug') then
        return
    end
    local trace = format('debug/%d [%s] %s', level, goonwall.Caller(3), goonwall.SafeFormat(...))
    goonwall.Log(trace)
    if goonwall.settings:get('verbose') then
        if goonwall.InRestrictedChat() then
            goonwall.suppressed_debug = goonwall.suppressed_debug + 1
        else
            DEFAULT_CHAT_FRAME:AddMessage(format('|cff009a7dGoonWall:|r |cff778899%s|r', trace))
        end
    end
end


--- Format a message, replacing secret values and never raising.
function goonwall.SafeFormat(fmt, ...)
    local args = { ... }
    for i = 1, select('#', ...) do
        if goonwall.IsSecret(args[i]) then
            args[i] = '<secret>'
        end
    end
    local ok, msg = pcall(string.format, tostring(fmt), unpack(args, 1, select('#', ...)))
    if ok then
        return msg
    end
    return tostring(fmt) .. ' <format error: ' .. tostring(msg) .. '>'
end


--- Describe a calling stack frame as "file:line:function".
-- Handles both the legacy ([string "..."], `fn') and 12.x (path, 'fn') formats.
function goonwall.Caller(depth)
    local s = type(debugstack) == 'function' and debugstack(depth, 1, 0) or ''
    -- In tainted execution (after touching a secret) debugstack() returns a
    -- secret string; any string op on it raises "string conversion" errors.
    if goonwall.IsSecret(s) or type(s) ~= 'string' then
        return '?'
    end
    local file, loc = strmatch(s, '([^/\\"%[%]]+%.lua)"?%]?:(%d+):')
    local f = strmatch(s, "in function [`']([^']+)'")
    return format('%s:%s:%s', file or '', loc or '', f or '?')
end


--- Print an obfuscated string if the redaction option is set.
-- @param msg The input string
-- @return The string with redaction applied, if necessary.
function goonwall.Redact(msg)
    if goonwall.settings:get('redact') then
        return string.format('<<%04X>>', crc.Hash(msg))
    else
        return msg
    end
end


---------------------------------------------------------------------------
-- Game functions
---------------------------------------------------------------------------

function goonwall.IsSecret(v)
    if type(issecretvalue) == 'function' then
        local ok, rv = pcall(issecretvalue, v)
        return not ok or rv and true or false
    end
    return false
end


function goonwall.IsUsableString(v)
    return not goonwall.IsSecret(v) and type(v) == 'string' and v ~= ''
end


--- Test for Midnight-style chat messaging lockdown (encounters, M+).
function goonwall.InChatLockdown()
    if C_ChatInfo and type(C_ChatInfo.InChatMessagingLockdown) == 'function' then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        return ok and not goonwall.IsSecret(locked) and locked == true
    end
    return false
end


local function safe_call(fn)
    if type(fn) ~= 'function' then
        return
    end
    local ok, a, b = pcall(fn)
    if not ok or goonwall.IsSecret(a) or goonwall.IsSecret(b) then
        return
    end
    return a, b
end


--- Inputs to the restricted chat test, for diagnostics.
-- @return lockdown, combat, instance type
function goonwall.RestrictionState()
    local _, instance = safe_call(IsInInstance)
    return goonwall.InChatLockdown(), safe_call(InCombatLockdown) == true, instance or 'none'
end


local function is_restricted_instance(instance)
    return instance == 'pvp' or instance == 'arena'
end


function goonwall.InRestrictedInstance()
    local _, instance = safe_call(IsInInstance)
    return is_restricted_instance(instance)
end


--- Test whether chat messages may be secret: chat lockdown, combat, battlegrounds and arenas.
function goonwall.InRestrictedChat()
    local lockdown, combat, instance = goonwall.RestrictionState()
    return lockdown or combat or is_restricted_instance(instance)
end


function goonwall.IsForever()
    return WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
end


function goonwall.NormalizeName(name)
    if not goonwall.IsUsableString(name) then
        return
    end
    name = strtrim(name)
    if name == '' then
        return
    end
    local realm = goonwall.realm
    if type(realm) == 'string' and realm ~= '' then
        local suffix = '-' .. realm
        if #name > #suffix and strlower(strsub(name, -#suffix)) == strlower(suffix) then
            name = strsub(name, 1, #name - #suffix)
        end
    end
    return name
end


function goonwall.PlayerGUID()
    if not goonwall.player_guid and type(UnitGUID) == 'function' then
        local guid = UnitGUID('player')
        if goonwall.IsUsableString(guid) then
            goonwall.player_guid = guid
        end
    end
    return goonwall.player_guid
end


local function set_player_name(name, source)
    if name and name ~= goonwall.player then
        goonwall.Debug(GOON_LOG_NOTICE, 'player name resolved; name=%s, was=%s, source=%s',
                name, tostring(goonwall.player), source)
        goonwall.player = name
    end
end


-- Forever: UnitFullName('player') returns the last name in the realm slot.
function goonwall.RefreshPlayerIdentity()
    goonwall.PlayerGUID()
    if goonwall.player_name_confirmed then
        return
    end
    local name
    if goonwall.IsForever() and type(UnitFullName) == 'function' then
        local first, second = UnitFullName('player')
        if goonwall.IsUsableString(first) then
            if goonwall.IsUsableString(second) and second ~= goonwall.realm then
                name = first .. ' ' .. second
            else
                name = first
            end
        end
    end
    if not name and type(UnitName) == 'function' then
        name = UnitName('player')
    end
    set_player_name(goonwall.NormalizeName(name), 'unit')
end


function goonwall.LearnPlayerName(name, guid)
    local pguid = goonwall.PlayerGUID()
    if not pguid or not goonwall.IsUsableString(guid) or guid ~= pguid then
        return false
    end
    local normalized = goonwall.NormalizeName(name)
    if normalized then
        set_player_name(normalized, 'guid')
        goonwall.player_name_confirmed = true
    end
    return true
end


function goonwall.ScanRosterForPlayer()
    if goonwall.player_name_confirmed or not goonwall.PlayerGUID() then
        return false
    end
    if type(GetNumGuildMembers) ~= 'function' or type(GetGuildRosterInfo) ~= 'function' then
        return false
    end
    for i = 1, GetNumGuildMembers() or 0 do
        local info = { GetGuildRosterInfo(i) }
        if goonwall.LearnPlayerName(info[1], info[17]) then
            return true
        end
    end
    return false
end


-- GUID wins when present; names only for GUID-less sources (system messages).
function goonwall.IsSelf(name, guid)
    local pguid = goonwall.PlayerGUID()
    if pguid and goonwall.IsUsableString(guid) then
        return guid == pguid
    end
    local normalized = goonwall.NormalizeName(name)
    return normalized ~= nil and normalized == goonwall.NormalizeName(goonwall.player)
end


--- Format name for cross-realm addressing.
-- @param name Character name or guild name.
-- @param realm Name of the realm.
-- @return A formatted cross-realm address.
function goonwall.GlobalName(name, realm)
    if name == nil then
        return
    end

    -- Pass formatted names without modification.
    if name:match("[^-]+-[^-]+$") then
        return name
    end

    -- Use local realm as the default.
    if realm == nil then
        realm = GetRealmName()
    end

    return name .. '-' .. realm:gsub("%s+", "")

end


--- Get the player's fully-qualified guild name.
-- @param target (optional) unit ID, default is 'Player'.
-- @return A qualified guild name or nil if the player is not in a guild.
function goonwall.GetGuildName(target)
    if target == nil then
        target = 'Player'
    end
    local name, _, _, realm = GetGuildInfo(target)
    if not goonwall.IsUsableString(name) or goonwall.IsSecret(realm) then
        return
    end
    return goonwall.GlobalName(name, realm)
end


function goonwall.GetGuildBaseName()
    if type(GetGuildInfo) ~= 'function' then
        return
    end
    local name = GetGuildInfo('Player')
    if goonwall.IsUsableString(name) then
        return name
    end
end


--- Get a string with the player's fully-qualified guild name and numeric rank.
-- @return A string identifier, the empty string if not in a guild, nil if unreadable.
function goonwall.GetGuildStatus()
    -- Realm omitted: on Forever it is a shard label that can change between sessions.
    local name, _, rank = GetGuildInfo('Player')
    if goonwall.IsSecret(name) or goonwall.IsSecret(rank) then
        return
    elseif not goonwall.IsUsableString(name) then
        return ''
    else
        return string.format('%s-%d', name, rank or 0)
    end
end


---------------------------------------------------------------------------
-- Item functions
---------------------------------------------------------------------------

--- Extract an embedded itemString from a chat message.
-- @param message A chat message.
-- @return An itemString.
function goonwall.GetItemString(message)
    return string.match(message, '|H(item[0-9:]+)|h')
end


--[[-----------------------------------------------------------------------

END

--]]-----------------------------------------------------------------------
