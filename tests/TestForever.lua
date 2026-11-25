lu = require('luaunit')
require('Loader')

local crc = LibStub:GetLibrary("Hash:CRC:16ccitt-1.0")

local SELF_GUID = 'Player-6934-0039FBF4'
local OTHER_GUID = 'Player-6924-005E7034'

local function snapshot(globals, fields)
    local saved = { g = {}, f = {} }
    for _, k in ipairs(globals) do saved.g[k] = { _G[k] } end
    for _, k in ipairs(fields) do saved.f[k] = { goonwall[k] } end
    return function()
        for k, v in pairs(saved.g) do _G[k] = v[1] end
        for k, v in pairs(saved.f) do goonwall[k] = v[1] end
    end
end

local GLOBALS = {
    'issecretvalue', 'WOW_PROJECT_ID', 'WOW_PROJECT_CAMELOT', 'UnitFullName', 'UnitName',
    'UnitGUID', 'GetNumGuildMembers', 'GetGuildRosterInfo', 'ChatFrame_RemoveChannel',
    'C_GuildInfo', 'GuildRoster', 'DEFAULT_CHAT_FRAME', 'NUM_CHAT_WINDOWS',
    'GetChatWindowMessages', 'ChatFrame1', 'ChatFrame3',
    'C_ChatInfo', 'C_Timer', 'GetTime', 'GetChannelName', 'SendChatMessage', 'debugstack',
}
local FIELDS = {
    'player', 'player_guid', 'player_name_confirmed', 'realm', 'config', 'settings',
    'ChatFrame_MessageEventHandler', 'APIDispatcher', 'Log', 'render_fallback',
}


-- Name normalization and secret values

TestNormalize = {}

function TestNormalize:setUp() self.restore = snapshot(GLOBALS, FIELDS) end
function TestNormalize:tearDown() self.restore() end

function TestNormalize:test_forever_names_pass_through()
    lu.assertEquals(goonwall.NormalizeName('The Ban'), 'The Ban')
    lu.assertEquals(goonwall.NormalizeName('  Nil Goat '), 'Nil Goat')
end

function TestNormalize:test_strips_local_realm_only()
    lu.assertEquals(goonwall.NormalizeName('Ralff-EarthenRing'), 'Ralff')
    lu.assertEquals(goonwall.NormalizeName('Ralff-earthenring'), 'Ralff')
    lu.assertEquals(goonwall.NormalizeName('Ralff-Stormrage'), 'Ralff-Stormrage')
end

function TestNormalize:test_unusable_values()
    lu.assertNil(goonwall.NormalizeName(nil))
    lu.assertNil(goonwall.NormalizeName(''))
    lu.assertNil(goonwall.NormalizeName('   '))
    lu.assertNil(goonwall.NormalizeName(42))
end

function TestNormalize:test_is_secret_without_api()
    issecretvalue = nil
    lu.assertFalse(goonwall.IsSecret('x'))
end

function TestNormalize:test_is_secret_with_api()
    issecretvalue = function(v) return v == 'SECRET' end
    lu.assertTrue(goonwall.IsSecret('SECRET'))
    lu.assertFalse(goonwall.IsSecret('plain'))
    lu.assertNil(goonwall.NormalizeName('SECRET'))
end

function TestNormalize:test_is_secret_api_error_counts_as_secret()
    issecretvalue = function() error('boom') end
    lu.assertTrue(goonwall.IsSecret('x'))
end


-- Player identity

TestIdentity = {}

function TestIdentity:setUp()
    self.restore = snapshot(GLOBALS, FIELDS)
    goonwall.player = 'Ralff'
    goonwall.player_guid = nil
    goonwall.player_name_confirmed = false
end

function TestIdentity:tearDown() self.restore() end

local function forever()
    WOW_PROJECT_CAMELOT = 18
    WOW_PROJECT_ID = 18
    UnitName = function() return 'The' end
    UnitFullName = function() return 'The', 'Ban' end
end

function TestIdentity:test_forever_detection()
    lu.assertFalse(goonwall.IsForever())
    forever()
    lu.assertTrue(goonwall.IsForever())
end

function TestIdentity:test_refresh_forever_joins_first_and_last()
    forever()
    goonwall.RefreshPlayerIdentity()
    lu.assertEquals(goonwall.player, 'The Ban')
    lu.assertEquals(goonwall.player_guid, SELF_GUID)
end

function TestIdentity:test_refresh_retail_uses_unit_name()
    goonwall.RefreshPlayerIdentity()
    lu.assertEquals(goonwall.player, 'Ralff')
end

function TestIdentity:test_refresh_does_not_override_confirmed_name()
    forever()
    goonwall.player = 'The Ban'
    goonwall.player_name_confirmed = true
    UnitFullName = function() return 'The', nil end
    goonwall.RefreshPlayerIdentity()
    lu.assertEquals(goonwall.player, 'The Ban')
end

function TestIdentity:test_learn_by_guid()
    lu.assertTrue(goonwall.LearnPlayerName('The Ban', SELF_GUID))
    lu.assertEquals(goonwall.player, 'The Ban')
    lu.assertTrue(goonwall.player_name_confirmed)
end

function TestIdentity:test_learn_ignores_other_guid()
    lu.assertFalse(goonwall.LearnPlayerName('Nil Goat', OTHER_GUID))
    lu.assertEquals(goonwall.player, 'Ralff')
    lu.assertFalse(goonwall.player_name_confirmed)
end

function TestIdentity:test_learn_without_player_guid()
    UnitGUID = function() return nil end
    lu.assertFalse(goonwall.LearnPlayerName('The Ban', SELF_GUID))
end

function TestIdentity:test_is_self_guid_is_authoritative()
    goonwall.player = 'The Ban'
    lu.assertTrue(goonwall.IsSelf('The Ban', SELF_GUID))
    lu.assertTrue(goonwall.IsSelf('anything', SELF_GUID))
    lu.assertFalse(goonwall.IsSelf('The Ban', OTHER_GUID))
end

function TestIdentity:test_is_self_name_fallback()
    goonwall.player = 'The Ban'
    lu.assertTrue(goonwall.IsSelf('The Ban'))
    lu.assertFalse(goonwall.IsSelf('The'))
    lu.assertFalse(goonwall.IsSelf('The Other'))
    lu.assertFalse(goonwall.IsSelf(nil))
end

function TestIdentity:test_roster_scan()
    local roster = {
        { 'Kyashi Blacksling', [17] = 'Player-6926-03793C06' },
        { 'The Ban', [17] = SELF_GUID },
    }
    GetNumGuildMembers = function() return #roster end
    GetGuildRosterInfo = function(i)
        local r = roster[i]
        return r[1], 'Goon', 6, 60, 'Mage', '', '', '', true, 0, 'MAGE',
                0, 0, false, false, 0, r[17]
    end
    lu.assertTrue(goonwall.ScanRosterForPlayer())
    lu.assertEquals(goonwall.player, 'The Ban')
    lu.assertFalse(goonwall.ScanRosterForPlayer())
end

function TestIdentity:test_roster_scan_without_api()
    GetNumGuildMembers = nil
    lu.assertFalse(goonwall.ScanRosterForPlayer())
end


-- Channel receive path

TestChannelReceive = {}

local function channel_args(text, sender, guid)
    return text, sender, '', '1. gwtest', sender, '', 0, 7, 'gwtest', 0, 1145, guid, 0
end

function TestChannelReceive:setUp()
    self.restore = snapshot(GLOBALS, FIELDS)
    goonwall.player = 'The'
    goonwall.player_guid = nil
    goonwall.player_name_confirmed = false
    goonwall.config = { guild_id = 'Goon' }
    self.errors = {}
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(self.errors, m) end }
    goonwall.Log = function() end
    self.chan = GoonChannel:new()
    self.chan.number = 7
end

function TestChannelReceive:tearDown() self.restore() end

function TestChannelReceive:test_self_echo_matches_hash_by_guid()
    local segment = 'C#Goon##hello'
    self.chan.tx_hash[crc.Hash(segment)] = 1
    local sender, guild_id, mtype, message, is_self =
            self.chan:tl_receive(channel_args(segment, 'The Ban', SELF_GUID))
    lu.assertTrue(is_self)
    lu.assertEquals(sender, 'The Ban')
    lu.assertEquals(guild_id, 'Goon')
    lu.assertEquals(mtype, GOON_MTYPE_CHAT)
    lu.assertEquals(message, 'hello')
    lu.assertNil(self.chan.tx_hash[crc.Hash(segment)])
    lu.assertEquals(self.errors, {})
    lu.assertEquals(goonwall.player, 'The Ban')
end

function TestChannelReceive:test_other_player_is_not_self()
    local _, _, _, _, is_self = self.chan:tl_receive(channel_args('C#Alt1##hi', 'The Other', OTHER_GUID))
    lu.assertFalse(is_self)
    lu.assertEquals(self.errors, {})
end

function TestChannelReceive:test_namesake_on_other_realm_is_not_self()
    goonwall.player = 'The Ban'
    goonwall.player_name_confirmed = true
    local got
    self.chan:receive(function(_, guild_id, content) got = { guild_id, content[1] } end,
            channel_args('C#Alt1##hi', 'The Ban', OTHER_GUID))
    lu.assertEquals(got, { 'Alt1', 'hi' })
    lu.assertEquals(self.errors, {})
end

function TestChannelReceive:test_secret_segment_is_dropped()
    issecretvalue = function(v) return v == 'C#Alt1##hi' end
    lu.assertNil(self.chan:tl_receive(channel_args('C#Alt1##hi', 'Nil Goat', OTHER_GUID)))
    lu.assertEquals(self.chan.stats.rxcnt, 0)
end

function TestChannelReceive:test_secret_sender_is_dropped()
    issecretvalue = function(v) return v == 'Nil Goat' end
    lu.assertNil(self.chan:tl_receive(channel_args('C#Alt1##hi', 'Nil Goat', OTHER_GUID)))
end

function TestChannelReceive:test_receive_delivers_other_guild()
    local got
    self.chan:receive(function(mtype, guild_id, content) got = { mtype, guild_id, content[1] } end,
            channel_args('C#Alt1##hi', 'Nil Goat', OTHER_GUID))
    lu.assertEquals(got, { GOON_MTYPE_CHAT, 'Alt1', 'hi' })
end

function TestChannelReceive:test_receive_drops_own_guild()
    local called = false
    self.chan:receive(function() called = true end,
            channel_args('C#Goon##hi', 'Dresh Demonhand', OTHER_GUID))
    lu.assertFalse(called)
end

function TestChannelReceive:test_receive_drops_self_even_with_foreign_tag()
    local called = false
    self.chan.tx_hash[crc.Hash('C#Alt1##hi')] = 1
    self.chan:receive(function() called = true end, channel_args('C#Alt1##hi', 'The Ban', SELF_GUID))
    lu.assertFalse(called)
end

function TestChannelReceive:test_receive_passes_echo_flag_to_api()
    local echo
    goonwall.APIDispatcher = function(_, _, _, _, is_self) echo = is_self end
    local base64 = LibStub:GetLibrary("Encoding:Hash:Base64BCA-1.0")
    local segment = 'E#Goon##Addon:' .. base64.encode('payload')
    self.chan.tx_hash[crc.Hash(segment)] = 1
    self.chan:receive(function() end, channel_args(segment, 'The Ban', SELF_GUID))
    lu.assertTrue(echo)
end

function TestChannelReceive:test_receive_ignores_dropped_segment()
    issecretvalue = function() return true end
    lu.assertNil(self.chan:receive(function() error('must not run') end,
            channel_args('C#Alt1##hi', 'Nil Goat', OTHER_GUID)))
end


-- Channel hide fallbacks (risk #6)

TestChannelHide = {}

function TestChannelHide:setUp() self.restore = snapshot(GLOBALS, FIELDS) end
function TestChannelHide:tearDown() self.restore() end

function TestChannelHide:test_uses_global_with_frame_object()
    local got
    local frame = {}
    ChatFrame_RemoveChannel = function(f, name) got = { f, name } end
    lu.assertTrue(GoonChannel.hide(frame, 'gwtest'))
    lu.assertIs(got[1], frame)
    lu.assertEquals(got[2], 'gwtest')
end

function TestChannelHide:test_falls_back_to_method()
    ChatFrame_RemoveChannel = nil
    local got
    local frame = { RemoveChannel = function(self, name) got = name end }
    lu.assertTrue(GoonChannel.hide(frame, 'gwtest'))
    lu.assertEquals(got, 'gwtest')
end

function TestChannelHide:test_no_api()
    ChatFrame_RemoveChannel = nil
    lu.assertFalse(GoonChannel.hide({}, 'gwtest'))
end

function TestChannelHide:test_error_is_contained()
    ChatFrame_RemoveChannel = function() error('blocked') end
    lu.assertFalse(GoonChannel.hide({}, 'gwtest'))
end


-- Guild roster request fallbacks (risk #7)

TestRosterRequest = {}

function TestRosterRequest:setUp()
    self.restore = snapshot(GLOBALS, FIELDS)
    goonwall.settings = GoonSettings:new()
end

function TestRosterRequest:tearDown() self.restore() end

function TestRosterRequest:test_prefers_namespaced()
    local called
    C_GuildInfo = { GuildRoster = function() called = 'C_GuildInfo' end }
    GuildRoster = function() called = 'global' end
    GoonConfig:new():reload()
    lu.assertEquals(called, 'C_GuildInfo')
end

function TestRosterRequest:test_falls_back_to_global()
    local called
    C_GuildInfo = {}
    GuildRoster = function() called = 'global' end
    GoonConfig:new():reload()
    lu.assertEquals(called, 'global')
end

function TestRosterRequest:test_no_api_does_not_error()
    C_GuildInfo = nil
    GuildRoster = nil
    lu.assertTrue(GoonConfig:new():reload())
end


-- Own-guild matching when GetGuildInfo reports a guild realm (risk #5)

TestGuildMatch = {}

function TestGuildMatch:setUp()
    self.restore = snapshot(GLOBALS, FIELDS)
    self.saved = { GetGuildInfo = GetGuildInfo, GetGuildInfoText = GetGuildInfoText, time = time,
                   version = goonwall.version }
    goonwall.settings = GoonSettings:new()
    goonwall.version = '1.13.0'
    time = os.time
    C_GuildInfo = nil
    GetGuildInfoText = function()
        return 'GW:c:gwtest:pw\nGW:p:Goon Squad:Goon\nGW:p:Goon Squad Two:Alt1\n'
    end
end

function TestGuildMatch:tearDown()
    self.restore()
    GetGuildInfo = self.saved.GetGuildInfo
    GetGuildInfoText = self.saved.GetGuildInfoText
    time = self.saved.time
    goonwall.version = self.saved.version
end

function TestGuildMatch:test_same_realm()
    GetGuildInfo = function() return 'Goon Squad', 'Goon', 6, nil end
    local config = GoonConfig:new()
    config:load()
    lu.assertEquals(config.guild_id, 'Goon')
    lu.assertEquals(config.peer['Alt1'], 'Goon Squad Two-EarthenRing')
end

function TestGuildMatch:test_guild_on_other_realm()
    GetGuildInfo = function() return 'Goon Squad Two', 'Uninviter', 2, 'CAMWOWUS2Realm8PvP' end
    local config = GoonConfig:new()
    config:load()
    lu.assertEquals(config.guild_id, 'Alt1')
    lu.assertNil(config.peer['Alt1'])
end


function TestGuildMatch:test_duplicate_tag_is_reported()
    local errors = {}
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(errors, m) end }
    goonwall.Log = function() end
    GetGuildInfo = function() return 'Goon Squad', 'Goon', 6, nil end
    GetGuildInfoText = function()
        return 'GW:c:goonbridge:pw\nGWp:Goon Squad:Goon\nGWp:Goon Squab:Goon\n'
    end
    GoonConfig:new():load()
    lu.assertEquals(#errors, 1)
    lu.assertStrContains(errors[1], 'tag "Goon" is used by both "Goon Squad" and "Goon Squab"')
end

function TestGuildMatch:test_unique_tags_no_error()
    local errors = {}
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(errors, m) end }
    goonwall.Log = function() end
    GetGuildInfo = function() return 'Goon Squad', 'Goon', 6, nil end
    GetGuildInfoText = function()
        return 'GWc:goonbridge:pw\nGWp:Goon Squad:Goon\nGWp:Goon Squab:GoonSquab\n'
    end
    local config = GoonConfig:new()
    config:load()
    lu.assertEquals(errors, {})
    lu.assertEquals(config.guild_id, 'Goon')
    lu.assertEquals(config.peer['GoonSquab'], 'Goon Squab-EarthenRing')
end


-- Guild status ignores the shard realm label

TestGuildStatus = {}

function TestGuildStatus:setUp() self.saved = GetGuildInfo end
function TestGuildStatus:tearDown() GetGuildInfo = self.saved end

function TestGuildStatus:test_realm_change_does_not_change_status()
    GetGuildInfo = function() return 'Goon Squad', 'Uninviter', 2, 'CAMWOWUS2Realm8PvP' end
    local a = goonwall.GetGuildStatus()
    GetGuildInfo = function() return 'Goon Squad', 'Uninviter', 2, nil end
    lu.assertEquals(goonwall.GetGuildStatus(), a)
    lu.assertEquals(a, 'Goon Squad-2')
end

function TestGuildStatus:test_rank_change_changes_status()
    GetGuildInfo = function() return 'Goon Squad', 'Goon', 6, nil end
    lu.assertEquals(goonwall.GetGuildStatus(), 'Goon Squad-6')
end

function TestGuildStatus:test_no_guild()
    GetGuildInfo = function() return nil end
    lu.assertEquals(goonwall.GetGuildStatus(), '')
end


-- Chat-frame injection is contained (risk #3)

TestReplicate = {}

local function chat_frame(name, lines)
    return { name = name, AddMessage = function(_, text, r, g, b) table.insert(lines, { name, text, r }) end }
end

function TestReplicate:setUp()
    self.restore = snapshot(GLOBALS, FIELDS)
    goonwall.settings = GoonSettings:new()
    goonwall.settings:set('tag', false)
    goonwall.render_fallback = {}
    self.lines = {}
    NUM_CHAT_WINDOWS = 3
    GetChatWindowMessages = function(i) if i == 1 or i == 3 then return 'SAY', 'GUILD', 'SYSTEM' end end
    ChatFrame1 = chat_frame('ChatFrame1', self.lines)
    ChatFrame3 = chat_frame('ChatFrame3', self.lines)
    ChatTypeInfo = { GUILD = { r = 0.25, g = 1, b = 0.25, id = 4 }, SYSTEM = { r = 1, g = 1, b = 0, id = 1 } }
    CHAT_GUILD_GET = '|Hchannel:GUILD|h[Guild]|h %s: '
end

function TestReplicate:tearDown()
    self.restore()
    ChatTypeInfo = nil
    CHAT_GUILD_GET = nil
end

function TestReplicate:test_handler_success_does_not_render()
    local calls = 0
    goonwall.ChatFrame_MessageEventHandler = function(frame, event, message, sender, ...)
        calls = calls + 1
        lu.assertEquals(event, 'CHAT_MSG_GUILD')
        lu.assertEquals(sender, 'Nil Goat')
        lu.assertEquals(type(select(16, ...)), 'table')
    end
    goonwall.ReplicateMessage('GUILD', 'hi', 'Alt1', { 'hi', 'Nil Goat', [12] = OTHER_GUID })
    lu.assertEquals(calls, 2)
    lu.assertEquals(self.lines, {})
end

function TestReplicate:test_passes_original_trailing_table()
    local extra = { x = 1 }
    local got
    goonwall.ChatFrame_MessageEventHandler = function(frame, event, ...) got = select(18, ...) end
    goonwall.ReplicateMessage('GUILD', 'hi', 'Alt1', { 'hi', 'Nil Goat', [12] = OTHER_GUID, [18] = extra })
    lu.assertIs(got, extra)
end

function TestReplicate:test_failure_falls_back_to_render_for_session()
    local calls = 0
    goonwall.ChatFrame_MessageEventHandler = function() calls = calls + 1; error("attempt to index local 'discordInfo'") end
    goonwall.ReplicateMessage('GUILD', 'hi', 'Alt1', { 'hi', 'Nil Goat', [12] = OTHER_GUID })
    lu.assertEquals(calls, 1)
    lu.assertEquals(#self.lines, 2)
    lu.assertEquals(self.lines[1][2], '|Hchannel:GUILD|h[Guild]|h |Hplayer:Nil Goat|h[Nil Goat]|h: hi')
    lu.assertEquals(self.lines[1][3], 0.25)
    goonwall.ReplicateMessage('GUILD', 'again', 'Alt1', { 'again', 'Nil Goat' })
    lu.assertEquals(calls, 1)
    lu.assertEquals(#self.lines, 4)
end

function TestReplicate:test_system_line_renders_plain()
    goonwall.ChatFrame_MessageEventHandler = function() error('boom') end
    goonwall.ReplicateMessage('SYSTEM', '[Not Oats] has come online.')
    lu.assertEquals(self.lines[1][2], '[Not Oats] has come online.')
    lu.assertEquals(self.lines[1][3], 1)
end

function TestReplicate:test_tag_and_percent_in_message()
    goonwall.settings:set('tag', true)
    goonwall.render_fallback = { GUILD = true }
    goonwall.ReplicateMessage('GUILD', '100% goon', 'Alt1', { '100% goon', 'Nil Goat' })
    lu.assertEquals(self.lines[1][2], '|Hchannel:GUILD|h[Guild]|h |Hplayer:Nil Goat|h[Nil Goat]|h: <Alt1> 100% goon')
end

function TestReplicate:test_render_class_colour()
    GetPlayerInfoByGUID = function() return 'Mage', 'MAGE' end
    C_ClassColor = { GetClassColor = function() return { WrapTextInColorCode = function(_, t) return '|cff3fc7eb' .. t .. '|r' end } end }
    goonwall.render_fallback = { GUILD = true }
    goonwall.ReplicateMessage('GUILD', 'hi', 'Alt1', { 'hi', 'Nil Goat', [12] = OTHER_GUID })
    GetPlayerInfoByGUID = nil
    C_ClassColor = nil
    lu.assertEquals(self.lines[1][2], '|Hchannel:GUILD|h[Guild]|h |Hplayer:Nil Goat|h[|cff3fc7ebNil Goat|r]|h: hi')
end


-- Transmit queue and chat lockdown (risk #4)

TestSendQueue = {}

function TestSendQueue:setUp()
    self.restore = snapshot(GLOBALS, FIELDS)
    self.t = 100
    self.sent = {}
    self.timers = {}
    self.locked = false
    self.fail = false
    GetTime = function() return self.t end
    GetChannelName = function() return 7 end
    C_Timer = { After = function(_, cb) table.insert(self.timers, cb) end }
    C_ChatInfo = {
        InChatMessagingLockdown = function() return self.locked end,
        SendChatMessage = function(msg, kind, _, num)
            if self.fail then error('blocked') end
            table.insert(self.sent, { msg, kind, num })
        end,
    }
    goonwall.settings = GoonSettings:new()
    goonwall.config = { guild_id = 'Goon', valid = true }
    self.chan = GoonChannel:new()
    self.chan:configure(1, 'goonbridge', 'pw')
end

function TestSendQueue:tearDown() self.restore() end

function TestSendQueue:fire_timers()
    local timers = self.timers
    self.timers = {}
    for _, cb in ipairs(timers) do cb() end
end

function TestSendQueue:test_sends_immediately()
    self.chan:send(GOON_MTYPE_CHAT, 'hi')
    lu.assertEquals(self.sent, { { 'C#Goon##hi', 'CHANNEL', 7 } })
    lu.assertEquals(self.chan.tx_hash[crc.Hash('C#Goon##hi')], 1)
    lu.assertEquals(#self.timers, 0)
end

function TestSendQueue:test_lockdown_holds_then_retries()
    self.locked = true
    self.chan:send(GOON_MTYPE_CHAT, 'one')
    self.chan:send(GOON_MTYPE_CHAT, 'two')
    lu.assertEquals(self.sent, {})
    lu.assertEquals(#self.timers, 1)
    self:fire_timers()
    lu.assertEquals(self.sent, {})
    lu.assertEquals(#self.timers, 1)
    self.locked = false
    self:fire_timers()
    lu.assertEquals(#self.sent, 2)
    lu.assertEquals(self.sent[1][1], 'C#Goon##one')
    lu.assertEquals(#self.timers, 0)
end

function TestSendQueue:test_lockdown_api_absent()
    C_ChatInfo.InChatMessagingLockdown = nil
    self.chan:send(GOON_MTYPE_CHAT, 'hi')
    lu.assertEquals(#self.sent, 1)
end

function TestSendQueue:test_expired_segments_dropped()
    self.locked = true
    self.chan:send(GOON_MTYPE_CHAT, 'old')
    self.t = self.t + GOON_TX_MAX_AGE + 1
    self.chan:send(GOON_MTYPE_CHAT, 'new')
    self.locked = false
    self:fire_timers()
    lu.assertEquals(self.sent, { { 'C#Goon##new', 'CHANNEL', 7 } })
end

function TestSendQueue:test_queue_cap()
    self.locked = true
    for i = 1, GOON_TX_QUEUE_MAX + 5 do
        self.chan:send(GOON_MTYPE_CHAT, 'm' .. i)
    end
    lu.assertEquals(#self.chan.tx_queue, GOON_TX_QUEUE_MAX)
    lu.assertEquals(self.chan.tx_queue[1].message, 'm6')
end

function TestSendQueue:test_send_error_requeues_and_rolls_back_hash()
    self.fail = true
    self.chan:send(GOON_MTYPE_CHAT, 'hi')
    lu.assertEquals(#self.chan.tx_queue, 1)
    lu.assertNil(self.chan.tx_hash[crc.Hash('C#Goon##hi')])
    self.fail = false
    self:fire_timers()
    lu.assertEquals(#self.sent, 1)
    lu.assertEquals(#self.chan.tx_queue, 0)
end

function TestSendQueue:test_not_connected_holds()
    GetChannelName = function() return 0 end
    self.chan:send(GOON_MTYPE_CHAT, 'hi')
    lu.assertEquals(#self.chan.tx_queue, 1)
    GetChannelName = function() return 7 end
    self:fire_timers()
    lu.assertEquals(#self.sent, 1)
end

function TestSendQueue:test_regen_event_flushes()
    self.locked = true
    self.chan:send(GOON_MTYPE_CHAT, 'hi')
    self.locked = false
    goonwall.addon_loaded = true
    goonwall.config.channel = { guild = self.chan }
    goonwall.config.valid = true
    GoonWall_OnEvent(nil, 'PLAYER_REGEN_ENABLED')
    lu.assertEquals(#self.sent, 1)
end

function TestSendQueue:test_message_before_config_load_gets_tag_when_sent()
    goonwall.config = { guild_id = '', valid = false }
    self.chan:send(GOON_MTYPE_CHAT, 'early')
    lu.assertEquals(self.sent, {})
    goonwall.config = { guild_id = 'Goon', valid = true }
    self:fire_timers()
    lu.assertEquals(self.sent, { { 'C#Goon##early', 'CHANNEL', 7 } })
end

function TestSendQueue:test_lockdown_secret_or_error_is_unlocked()
    issecretvalue = function(v) return v == true end
    self.locked = true
    lu.assertFalse(goonwall.InChatLockdown())
    issecretvalue = nil
    C_ChatInfo.InChatMessagingLockdown = function() error('nope') end
    lu.assertFalse(goonwall.InChatLockdown())
end


-- Debug logging

TestDebugFormat = {}

function TestDebugFormat:setUp() self.restore = snapshot(GLOBALS, FIELDS) end
function TestDebugFormat:tearDown() self.restore() end

function TestDebugFormat:test_secret_args_replaced()
    issecretvalue = function(v) return v == 'hidden' end
    lu.assertEquals(goonwall.SafeFormat('a=%s b=%s', 'hidden', 'shown'), 'a=<secret> b=shown')
end

function TestDebugFormat:test_bad_format_does_not_raise()
    lu.assertStrContains(goonwall.SafeFormat('n=%d', 'x'), 'format error')
end

function TestDebugFormat:test_caller_formats()
    debugstack = function() return [[Interface/AddOns/GoonWall/Channel.lua:412: in function 'GoonChannel:receive']] end
    lu.assertEquals(goonwall.Caller(3), 'Channel.lua:412:GoonChannel:receive')
    debugstack = function() return [[[string "@Interface\AddOns\GoonWall\Channel.lua"]:9: in function `receive']] end
    lu.assertEquals(goonwall.Caller(3), 'Channel.lua:9:receive')
    debugstack = nil
    lu.assertEquals(goonwall.Caller(3), '::?')
    local secret = {}
    issecretvalue = function(v) return v == secret end
    debugstack = function() return secret end
    lu.assertEquals(goonwall.Caller(3), '?')
    debugstack = nil
    issecretvalue = nil
end


-- Outbound hook ignores secret values

TestOutboundSecret = {}

function TestOutboundSecret:setUp() self.restore = snapshot(GLOBALS, FIELDS) end
function TestOutboundSecret:tearDown() self.restore() end

function TestOutboundSecret:test_secret_message_not_forwarded()
    local deferred = 0
    C_Timer = { After = function() deferred = deferred + 1 end }
    issecretvalue = function(v) return v == 'secret text' end
    GoonWall_SendChatMessage('secret text', 'GUILD')
    lu.assertEquals(deferred, 0)
end


-- Restricted chat: combat, lockdown, battlegrounds

local RESTRICT_GLOBALS = {
    'IsInInstance', 'InCombatLockdown', 'IsInGuild', 'GetGuildInfo', 'JoinTemporaryChannel', 'time', 'GetChannelList',
    'GoonWall', 'GoonWallAccount', 'GoonWallMeta', 'GoonWallLog',
}
local RESTRICT_FIELDS = {
    'suppressed_debug', 'guild_status', 'guild_check_pending',
    'refresh_queued', 'addon_loaded',
}

local function append(a, b)
    local t = {}
    for _, v in ipairs(a) do table.insert(t, v) end
    for _, v in ipairs(b) do table.insert(t, v) end
    return t
end

TestRestricted = {}

function TestRestricted:setUp()
    self.restore = snapshot(append(GLOBALS, RESTRICT_GLOBALS), append(FIELDS, RESTRICT_FIELDS))
    self.instance = 'none'
    self.combat = false
    self.lines = {}
    self.timers = {}
    self.joins = 0
    time = os.time
    IsInInstance = function() return self.instance ~= 'none', self.instance end
    InCombatLockdown = function() return self.combat end
    IsInGuild = function() return true end
    GetGuildInfo = function() return 'Goon Squad', 'Goon', 2, nil end
    JoinTemporaryChannel = function() self.joins = self.joins + 1 end
    GetChannelName = function() return self.joins > 0 and 7 or 0 end
    C_ChatInfo = {
        InChatMessagingLockdown = function() return false end,
        RegisterAddonMessagePrefix = function() end,
    }
    C_Timer = { After = function(_, cb) table.insert(self.timers, cb) end }
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(self.lines, m) end }
    goonwall.Log = function() end
    goonwall.suppressed_debug = 0
    goonwall.guild_status = 'Goon Squad-2'
    goonwall.guild_check_pending = false
    goonwall.refresh_queued = false
    goonwall.addon_loaded = true
    GoonWall, GoonWallAccount, GoonWallMeta, GoonWallLog = nil, nil, nil, nil
    goonwall.settings = GoonSettings:new()
    self.resets = 0
    self.chan = GoonChannel:new()
    self.chan:configure(1, 'goonbridge', 'pw')
    goonwall.config = {
        guild_id = 'Goon',
        valid = true,
        channel = { guild = self.chan },
        timer = { channel = { hold = function() return false end } },
        reset = function() self.resets = self.resets + 1 end,
        refresh_channels = function() self.chan:join() end,
    }
end

function TestRestricted:tearDown() self.restore() end

function TestRestricted:fire_timers()
    local timers = self.timers
    self.timers = {}
    for _, cb in ipairs(timers) do cb() end
end

function TestRestricted:test_restriction_sources()
    lu.assertFalse(goonwall.InRestrictedChat())
    self.instance = 'pvp'
    lu.assertTrue(goonwall.InRestrictedChat())
    self.instance = 'arena'
    lu.assertTrue(goonwall.InRestrictedChat())
    self.instance = 'party'
    lu.assertFalse(goonwall.InRestrictedChat())
    self.combat = true
    lu.assertTrue(goonwall.InRestrictedChat())
    self.combat = false
    C_ChatInfo.InChatMessagingLockdown = function() return true end
    lu.assertTrue(goonwall.InRestrictedChat())
end

function TestRestricted:test_secret_or_failing_apis_are_unrestricted()
    issecretvalue = function(v) return v == 'pvp' end
    self.instance = 'pvp'
    lu.assertFalse(goonwall.InRestrictedChat())
    issecretvalue = nil
    IsInInstance = function() error('nope') end
    InCombatLockdown = function() error('nope') end
    lu.assertFalse(goonwall.InRestrictedChat())
end

function TestRestricted:test_verbose_debug_not_printed_while_restricted()
    goonwall.settings:set('debug', GOON_LOG_DEBUG)
    goonwall.settings:set('verbose', true)
    self.lines = {}
    self.instance = 'pvp'
    goonwall.Debug(GOON_LOG_DEBUG, 'one')
    goonwall.Debug(GOON_LOG_DEBUG, 'two')
    lu.assertEquals(self.lines, {})
    lu.assertEquals(goonwall.suppressed_debug, 2)
    self.instance = 'none'
    goonwall.Debug(GOON_LOG_DEBUG, 'three')
    lu.assertEquals(#self.lines, 1)
end

function TestRestricted:test_suppressed_debug_reported_once_unrestricted()
    goonwall.suppressed_debug = 3
    self.combat = true
    lu.assertFalse(goonwall.ReportSuppressedDebug())
    lu.assertEquals(self.lines, {})
    self.combat = false
    lu.assertTrue(goonwall.ReportSuppressedDebug())
    lu.assertEquals(#self.lines, 1)
    lu.assertStrContains(self.lines[1], '3 debug line(s) not shown')
    goonwall.ReportSuppressedDebug()
    lu.assertEquals(#self.lines, 1)
end

function TestRestricted:test_write_error_and_replication_stay_live_in_battleground()
    local calls = 0
    goonwall.ChatFrame_MessageEventHandler = function() calls = calls + 1 end
    goonwall.render_fallback = {}
    NUM_CHAT_WINDOWS = 1
    GetChatWindowMessages = function() return 'GUILD' end
    ChatFrame1 = { AddMessage = function() end }
    self.instance = 'pvp'
    self.combat = true
    goonwall.Write('hello')
    goonwall.Error('oops')
    goonwall.ReplicateMessage('GUILD', 'hi', 'Alt1', { 'hi', 'Nil Goat' })
    lu.assertEquals(#self.lines, 2)
    lu.assertEquals(calls, 1)
end

function TestRestricted:test_join_not_deferred_in_open_world_combat()
    self.combat = true
    lu.assertTrue(self.chan:join())
    lu.assertEquals(self.joins, 1)
end

function TestRestricted:test_join_deferred_while_restricted()
    self.instance = 'pvp'
    lu.assertFalse(self.chan:join())
    lu.assertEquals(self.joins, 0)
    lu.assertTrue(self.chan.join_pending)
    lu.assertEquals(self.chan.stats.fconn, 0)
    self.instance = 'none'
    GoonWall_OnEvent(nil, 'PLAYER_ENTERING_WORLD')
    lu.assertEquals(self.joins, 0)
    self:fire_timers()
    lu.assertEquals(self.joins, 1)
    lu.assertFalse(self.chan.join_pending)
    lu.assertEquals(self.chan.number, 7)
end

function TestRestricted:test_invalid_config_refreshed_after_battleground()
    local refreshes = 0
    goonwall.config.refresh = function() refreshes = refreshes + 1 end
    goonwall.config.valid = false
    self.instance = 'pvp'
    GoonWall_OnEvent(nil, 'PLAYER_ENTERING_WORLD')
    lu.assertEquals(refreshes, 0)
    self.instance = 'none'
    GoonWall_OnEvent(nil, 'PLAYER_ENTERING_WORLD')
    lu.assertEquals(refreshes, 1)
    self.combat = true
    GoonWall_OnEvent(nil, 'ZONE_CHANGED_NEW_AREA')
    lu.assertEquals(refreshes, 1)
    self.combat = false
    GoonWall_OnEvent(nil, 'PLAYER_REGEN_ENABLED')
    lu.assertEquals(refreshes, 2)
    goonwall.config.valid = true
    GoonWall_OnEvent(nil, 'ZONE_CHANGED_NEW_AREA')
    lu.assertEquals(refreshes, 2)
end

function TestRestricted:test_channel_ui_update_never_rejoins()
    GetChannelList = function() return end
    for _ = 1, 10 do
        GoonWall_OnEvent(nil, 'CHANNEL_UI_UPDATE')
    end
    self:fire_timers()
    lu.assertEquals(self.joins, 0)
end

function TestRestricted:test_bridge_left_or_kicked_rejoins()
    local connected = true
    local clock = 1000
    time = function() return clock end
    JoinTemporaryChannel = function() self.joins = self.joins + 1; connected = true end
    GetChannelName = function() return connected and 7 or 0 end
    self.chan.number = 7
    for _, action in ipairs({ 'YOU_LEFT', 'YOU_KICKED' }) do
        connected = false
        clock = clock + GOON_CHANNEL_CHURN_WINDOW
        GoonWall_OnEvent(nil, 'CHAT_MSG_CHANNEL_NOTICE', action, '', '', '7. goonbridge', '', '', 0, 7, 'goonbridge')
    end
    lu.assertEquals(self.joins, 2)
    lu.assertEquals(self.chan.stats.disco, 2)
end

function TestRestricted:test_other_channel_notice_does_not_rejoin()
    self.chan.number = 7
    GoonWall_OnEvent(nil, 'CHAT_MSG_CHANNEL_NOTICE', 'YOU_LEFT', '', '', '3. other', '', '', 0, 3, 'other')
    lu.assertEquals(self.joins, 0)
end

function TestRestricted:test_guild_update_ignored_while_restricted()
    self.instance = 'pvp'
    GetGuildInfo = function() return nil end
    GoonWall_OnEvent(nil, 'PLAYER_GUILD_UPDATE')
    lu.assertEquals(self.resets, 0)
    lu.assertTrue(goonwall.guild_check_pending)
    GetGuildInfo = function() return 'Goon Squad', 'Goon', 2, nil end
    self.instance = 'none'
    GoonWall_OnEvent(nil, 'ZONE_CHANGED_NEW_AREA')
    lu.assertEquals(self.resets, 0)
    lu.assertFalse(goonwall.guild_check_pending)
end

function TestRestricted:test_unreadable_guild_status_does_not_reset()
    GetGuildInfo = function() return nil end
    lu.assertFalse(goonwall.CheckGuildStatus())
    issecretvalue = function(v) return v == 'Goon Squad' end
    GetGuildInfo = function() return 'Goon Squad', 'Goon', 2, nil end
    lu.assertFalse(goonwall.CheckGuildStatus())
    lu.assertEquals(self.resets, 0)
    lu.assertTrue(goonwall.guild_check_pending)
end

function TestRestricted:test_real_guild_changes_reset()
    GetGuildInfo = function() return 'Goon Squad', 'Goon', 5, nil end
    lu.assertTrue(goonwall.CheckGuildStatus())
    lu.assertEquals(goonwall.guild_status, 'Goon Squad-5')
    IsInGuild = function() return false end
    GetGuildInfo = function() return nil end
    lu.assertTrue(goonwall.CheckGuildStatus())
    lu.assertEquals(goonwall.guild_status, '')
    lu.assertEquals(self.resets, 2)
end

function TestRestricted:test_flush_sends_in_battleground_and_combat()
    local sent = 0
    self.joins = 1
    C_ChatInfo.SendChatMessage = function() sent = sent + 1 end
    self.chan.number = 7
    self.instance = 'pvp'
    self.combat = true
    self.chan:send(GOON_MTYPE_CHAT, 'a')
    lu.assertEquals(sent, 1)
end

function TestRestricted:test_channel_churn_backs_off()
    local clock = 1000
    local connected = false
    time = function() return clock end
    JoinTemporaryChannel = function() self.joins = self.joins + 1; connected = true end
    GetChannelName = function() return connected and 1 or 0 end
    GetChannelList = function() return 1, 'General', false, 2, 'goonbridge', false end

    lu.assertTrue(self.chan:join())
    lu.assertEquals(self.joins, 1)

    -- Kicked a second later: no immediate rejoin, a retry is scheduled.
    clock = clock + 1
    connected = false
    lu.assertFalse(self.chan:join())
    lu.assertFalse(self.chan:join())
    lu.assertEquals(self.joins, 1)
    lu.assertEquals(self.chan.stats.churn, 1)
    lu.assertEquals(#self.timers, 1)

    -- Hold expires: rejoins once.
    clock = clock + GOON_CHANNEL_FAILURE_HOLD
    lu.assertTrue(self.chan:join())
    lu.assertEquals(self.joins, 2)

    -- Kicked again: the hold doubles.
    clock = clock + 1
    connected = false
    lu.assertFalse(self.chan:join())
    clock = clock + GOON_CHANNEL_FAILURE_HOLD
    lu.assertFalse(self.chan:join())
    lu.assertEquals(self.joins, 2)
    clock = clock + GOON_CHANNEL_FAILURE_HOLD
    lu.assertTrue(self.chan:join())
    lu.assertEquals(self.joins, 3)

    -- Holds for the churn window: backoff lifted.
    clock = clock + GOON_CHANNEL_CHURN_WINDOW
    lu.assertTrue(self.chan:join())
    lu.assertFalse(self.chan.churning)
    lu.assertFalse(self.chan.fdelay:hold())
    lu.assertEquals(self.chan.fdelay.scale, 0)
end

function TestRestricted:test_channel_dropped_after_window_rejoins_immediately()
    local clock = 1000
    local connected = false
    time = function() return clock end
    JoinTemporaryChannel = function() self.joins = self.joins + 1; connected = true end
    GetChannelName = function() return connected and 1 or 0 end

    lu.assertTrue(self.chan:join())
    clock = clock + GOON_CHANNEL_CHURN_WINDOW
    connected = false
    lu.assertTrue(self.chan:join())
    lu.assertEquals(self.joins, 2)
    lu.assertEquals(self.chan.stats.churn, 0)
end


os.exit(lu.run())
