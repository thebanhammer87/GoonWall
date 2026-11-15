--
-- Includes
--

lu = require('luaunit')
require('Loader')

--
-- Mocks
--
local MockChan = {}
MockChan.__index = MockChan

function MockChan:new()
    local self = {}
    setmetatable(self, MockChan)
    self.input = {}
    return self
end

function MockChan:send(mtype, ...)
    table.insert(self.input, { mtype, ... })
end

local MockCache = {}
MockCache.__index = MockCache

function MockCache:new(output)
    local self = {}
    setmetatable(self, MockCache)
    self.input = {}
    self.output = output and true or false
    return self
end

function MockCache:hold(s)
    table.insert(self.input, s)
    return self.output
end

local MockConfig = {}
MockConfig.__index = MockConfig

function MockConfig:new(holddown)
    local self = {}
    setmetatable(self, MockConfig)
    self.channel = { guild = MockChan:new() }
    self.comember_cache = MockCache:new(holddown)
    self.is_reset = false
    return self
end

function MockConfig:reset()
    self.is_reset = true
end


--
-- Test Cases
--

TestSystemEventHandler = {}

function TestSystemEventHandler:test_online_init()
    config = MockConfig:new()
    message = "|Hplayer:Eggolas|h[Eggolas]|h has come online."
    handler = GoonSystemEventHandler:factory(config, message)
    lu.assertEquals(getmetatable(handler), GoonOnlineSystemEventHandler)
    lu.assertEquals(handler.player, "Eggolas")
    lu.assertEquals(handler.config, config)
end

function TestSystemEventHandler:test_online_raw_init()
    config = MockConfig:new()
    message = "Eggolas has come |cff298F00online|r."
    handler = GoonSystemEventHandler:factory(config, message)
    lu.assertEquals(getmetatable(handler), GoonOnlineSystemEventHandler)
    lu.assertEquals(handler.player, "Eggolas")
end

function TestSystemEventHandler:test_online_run()
    config = MockConfig:new()
    message = "|Hplayer:Eggolas|h[Eggolas]|h has come online."
    handler = GoonSystemEventHandler:factory(config, message)
    handler:run()
    lu.assertEquals(config.comember_cache.input[1], "Eggolas")
end

function TestSystemEventHandler:test_online_run_cached()
    config = MockConfig:new(true)
    message = "|Hplayer:Eggolas|h[Eggolas]|h has come online."
    handler = GoonSystemEventHandler:factory(config, message)
    handler:run()
    lu.assertEquals(config.comember_cache.input[1], "Eggolas")
end

function TestSystemEventHandler:test_offline_init()
    config = MockConfig:new()
    message = "Eggolas has gone offline."
    handler = GoonSystemEventHandler:factory(config, message)
    lu.assertEquals(getmetatable(handler), GoonOfflineSystemEventHandler)
    lu.assertEquals(handler.player, "Eggolas")
end

function TestSystemEventHandler:test_offline_run()
    config = MockConfig:new()
    message = "Eggolas has gone offline."
    handler = GoonSystemEventHandler:factory(config, message)
    handler:run()
    lu.assertEquals(config.comember_cache.input[1], "Eggolas")
end

function TestSystemEventHandler:test_offline_run_cached()
    config = MockConfig:new(true)
    message = "Eggolas has gone offline."
    handler = GoonSystemEventHandler:factory(config, message)
    handler:run()
    lu.assertEquals(config.comember_cache.input[1], "Eggolas")
end

function TestSystemEventHandler:test_join_init()
    config = MockConfig:new()
    message = "Eggolas has joined the guild."
    handler = GoonSystemEventHandler:factory(config, message)
    lu.assertEquals(getmetatable(handler), GoonJoinSystemEventHandler)
    lu.assertEquals(handler.player, "Eggolas")
end

function TestSystemEventHandler:test_join_run()
    config = MockConfig:new()
    message = "Ralff has joined the guild."
    handler = GoonSystemEventHandler:factory(config, message)
    handler:run()
    lu.assertEquals(config.channel.guild.input[1], { GOON_MTYPE_BROADCAST, "join" })
end

function TestSystemEventHandler:test_join_run_skip()
    config = MockConfig:new()
    message = "Eggolas has joined the guild."
    handler = GoonSystemEventHandler:factory(config, message)
    handler:run()
    lu.assertNil(config.channel.guild.input[1])
end

function TestSystemEventHandler:test_leave_init()
    config = MockConfig:new()
    message = "Eggolas has left the guild."
    handler = GoonSystemEventHandler:factory(config, message)
    lu.assertEquals(getmetatable(handler), GoonLeaveSystemEventHandler)
    lu.assertEquals(handler.player, "Eggolas")
end

function TestSystemEventHandler:test_leave_run()
    config = MockConfig:new()
    message = "Ralff has left the guild."
    handler = GoonSystemEventHandler:factory(config, message)
    handler:run()
    lu.assertEquals(config.channel.guild.input[1], { GOON_MTYPE_BROADCAST, "leave" })
    lu.assertTrue(config.is_reset)
end

function TestSystemEventHandler:test_leave_run_skip()
    config = MockConfig:new()
    message = "Eggolas has left the guild."
    handler = GoonSystemEventHandler:factory(config, message)
    handler:run()
    lu.assertNil(config.channel.guild.input[1])
    lu.assertFalse(config.is_reset)
end

function TestSystemEventHandler:test_quit_init()
    config = MockConfig:new()
    message = "You are no longer a member of SparkleMotion."
    handler = GoonSystemEventHandler:factory(config, message)
    lu.assertEquals(getmetatable(handler), GoonQuitSystemEventHandler)
    lu.assertEquals(handler.player, "Ralff")
end

function TestSystemEventHandler:test_quit_run()
    config = MockConfig:new()
    message = "You are no longer a member of SparkleMotion."
    handler = GoonSystemEventHandler:factory(config, message)
    handler:run()
    lu.assertEquals(config.channel.guild.input[1], { GOON_MTYPE_BROADCAST, "leave" })
    lu.assertTrue(config.is_reset)
end

function TestSystemEventHandler:test_remove_init()
    config = MockConfig:new()
    message = "Eggolas has been kicked out of the guild by Ralff."
    handler = GoonSystemEventHandler:factory(config, message)
    lu.assertEquals(getmetatable(handler), GoonRemoveSystemEventHandler)
    lu.assertEquals(handler.player, "Eggolas")
end

function TestSystemEventHandler:test_remove_run()
    config = MockConfig:new()
    message = "Ralff has been kicked out of the guild by Eggolas."
    handler = GoonSystemEventHandler:factory(config, message)
    handler:run()
    lu.assertEquals(config.channel.guild.input[1], { GOON_MTYPE_BROADCAST, "remove" })
    lu.assertTrue(config.is_reset)
end

function TestSystemEventHandler:test_remove_run_skip()
    config = MockConfig:new()
    message = "Eggolas has been kicked out of the guild by Ralff."
    handler = GoonSystemEventHandler:factory(config, message)
    handler:run()
    lu.assertNil(config.channel.guild.input[1])
    lu.assertFalse(config.is_reset)
end

function TestSystemEventHandler:test_kick_init()
    config = MockConfig:new()
    message = "You have been kicked out of the guild."
    handler = GoonSystemEventHandler:factory(config, message)
    lu.assertEquals(getmetatable(handler), GoonKickSystemEventHandler)
    lu.assertEquals(handler.player, "Ralff")
end

function TestSystemEventHandler:test_kick_run()
    config = MockConfig:new()
    message = "You have been kicked out of the guild."
    handler = GoonSystemEventHandler:factory(config, message)
    handler:run()
    lu.assertEquals(config.channel.guild.input[1], { GOON_MTYPE_BROADCAST, "leave" })
    lu.assertTrue(config.is_reset)
end

function TestSystemEventHandler:test_no_match()
    config = MockConfig:new()
    message = "Don't panic."
    handler = GoonSystemEventHandler:factory(config, message)
    lu.assertEquals(getmetatable(handler), GoonSystemEventHandler)
    lu.assertNil(handler.player)
end


-- Forever: "First Last" names, no realm suffix.

TestSystemEventHandlerForever = {}

function TestSystemEventHandlerForever:setUp()
    self.saved_player = goonwall.player
    goonwall.player = 'The Ban'
end

function TestSystemEventHandlerForever:tearDown()
    goonwall.player = self.saved_player
end

function TestSystemEventHandlerForever:test_offline_keeps_full_name()
    local handler = GoonSystemEventHandler:factory(MockConfig:new(), "Dresh Demonhand has gone offline.")
    lu.assertEquals(getmetatable(handler), GoonOfflineSystemEventHandler)
    lu.assertEquals(handler.player, "Dresh Demonhand")
end

function TestSystemEventHandlerForever:test_join_self_broadcasts()
    local config = MockConfig:new()
    GoonSystemEventHandler:factory(config, "The Ban has joined the guild."):run()
    lu.assertEquals(config.channel.guild.input[1], { GOON_MTYPE_BROADCAST, "join" })
end

function TestSystemEventHandlerForever:test_join_same_first_name_skips()
    local config = MockConfig:new()
    GoonSystemEventHandler:factory(config, "The Other has joined the guild."):run()
    lu.assertNil(config.channel.guild.input[1])
end

function TestSystemEventHandlerForever:test_quit_uses_full_name()
    local handler = GoonSystemEventHandler:factory(MockConfig:new(), "You are no longer a member of Goon Squad.")
    lu.assertEquals(handler.player, "The Ban")
end

function TestSystemEventHandlerForever:test_secret_message_is_ignored()
    local saved = issecretvalue
    issecretvalue = function() return true end
    local handler = GoonSystemEventHandler:factory(MockConfig:new(), "The Ban has joined the guild.")
    issecretvalue = saved
    lu.assertEquals(getmetatable(handler), GoonSystemEventHandler)
    lu.assertNil(handler.player)
end

function TestSystemEventHandlerForever:test_nil_message_is_ignored()
    local handler = GoonSystemEventHandler:factory(MockConfig:new(), nil)
    lu.assertEquals(getmetatable(handler), GoonSystemEventHandler)
end


--
-- Run the tests
--

os.exit(lu.run())
