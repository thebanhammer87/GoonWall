lu = require('luaunit')
require('Loader')

TestGoonWallChatSend = {}

function TestGoonWallChatSend:setUp()
    self.now = 100
    self.sent = {}
    self.deferred = {}
    GetTime = function() return self.now end
    C_Timer = {
        After = function(_, callback)
            table.insert(self.deferred, callback)
        end,
    }
    goonwall.compatibility = {
        name2chat = false,
        identity = false,
        incognito = false,
    }
    goonwall.config = {
        channel = {
            guild = {
                send = function(_, messageType, message)
                    table.insert(self.sent, { 'GUILD', messageType, message })
                end,
            },
        },
    }
end

function TestGoonWallChatSend:runDeferred()
    local deferred = self.deferred
    self.deferred = {}
    for _, callback in ipairs(deferred) do callback() end
end

function TestGoonWallChatSend:test_direct_guild_send_from_macro_is_forwarded()
    GoonWall_SendChatMessage('macro message', 'GUILD')

    lu.assertEquals(self.sent, {})
    self:runDeferred()

    lu.assertEquals(self.sent, {
        { 'GUILD', GOON_MTYPE_CHAT, 'macro message' },
    })
end

function TestGoonWallChatSend:test_typed_message_is_not_forwarded_twice()
    local editbox = {
        GetAttribute = function() return 'GUILD' end,
        GetText = function() return 'typed message' end,
    }

    GoonWall_ParseText(editbox, 1)
    GoonWall_SendChatMessage('typed message', 'GUILD')

    lu.assertEquals(self.sent, {
        { 'GUILD', GOON_MTYPE_CHAT, 'typed message' },
    })
end

function TestGoonWallChatSend:test_officer_chat_is_not_bridged()
    GoonWall_SendChatMessage('officer macro', 'OFFICER')
    GoonWall_ParseText({
        GetAttribute = function() return 'OFFICER' end,
        GetText = function() return 'typed officer' end,
    }, 1)
    self:runDeferred()
    lu.assertEquals(self.sent, {})
end

function TestGoonWallChatSend:test_other_channels_and_blank_messages_are_ignored()
    GoonWall_SendChatMessage('party message', 'PARTY')
    GoonWall_SendChatMessage('   ', 'GUILD')
    self:runDeferred()

    lu.assertEquals(self.sent, {})
end

os.exit(lu.run())
