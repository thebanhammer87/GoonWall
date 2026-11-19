lu = require('luaunit')
require('Loader')


--
-- GoonConfig:load() cleanup - self.channel is keyed by 'guild', so a
-- stale channel must be cleared via pairs(); an ipairs() cleanup would silently
-- skip the whole (hash-keyed) table and leave stale channels behind.
--

TestConfigCleanup = {}

local function stub_channel(stale)
    return {
        aged = false, configured = false, cleared = false,
        age       = function(self) self.aged = true end,
        configure = function(self) self.configured = true end,
        is_stale  = function(self) return stale end,
        clear     = function(self) self.cleared = true end,
    }
end

function TestConfigCleanup:setUp()
    self.saved = {
        GetGuildInfoText = GetGuildInfoText,
        GetGuildName = goonwall.GetGuildName,
        version = goonwall.version,
        settings = goonwall.settings,
        time = time,
    }
    goonwall.settings = GoonSettings:new()
    goonwall.version = '1.0.0'
    goonwall.GetGuildName = function() return 'TestGuild' end
    GetGuildInfoText = function() return 'GW:c:Chan:pass\nGW:v:1.0.0\n' end
    time = os.time   -- config timers call time(); any monotonic value is fine
end

function TestConfigCleanup:tearDown()
    GetGuildInfoText = self.saved.GetGuildInfoText
    goonwall.GetGuildName = self.saved.GetGuildName
    goonwall.version = self.saved.version
    goonwall.settings = self.saved.settings
    time = self.saved.time
end

function TestConfigCleanup:test_stale_channel_is_cleared()
    local config = GoonConfig:new()
    config.channel = { guild = stub_channel(true) }
    config:load()
    -- The stale guild channel (hash key 'guild') must be reached and cleared.
    lu.assertTrue(config.channel.guild.cleared)
end


--
-- GoonConfig:load() - guild info text should prefer the namespaced API
-- (C_GuildInfo.GetInfoText) and fall back to the deprecated global
-- (GetGuildInfoText).
--

TestConfigInfoText = {}

function TestConfigInfoText:setUp()
    self.saved = {
        C_GuildInfo = C_GuildInfo,
        GetGuildInfoText = GetGuildInfoText,
        GetGuildName = goonwall.GetGuildName,
        version = goonwall.version,
        settings = goonwall.settings,
        time = time,
    }
    goonwall.settings = GoonSettings:new()
    goonwall.version = '1.0.0'
    goonwall.GetGuildName = function() return 'TestGuild' end
    time = os.time
end

function TestConfigInfoText:tearDown()
    C_GuildInfo = self.saved.C_GuildInfo
    GetGuildInfoText = self.saved.GetGuildInfoText
    goonwall.GetGuildName = self.saved.GetGuildName
    goonwall.version = self.saved.version
    goonwall.settings = self.saved.settings
    time = self.saved.time
end

function TestConfigInfoText:test_prefers_C_GuildInfo()
    local source
    C_GuildInfo = { GetInfoText = function()
        source = 'namespaced'
        return 'GW:c:Chan:pass\nGW:v:1.0.0\n'
    end }
    GetGuildInfoText = function()
        source = 'global'
        return 'GW:c:Chan:pass\nGW:v:1.0.0\n'
    end
    GoonConfig:new():load()
    lu.assertEquals(source, 'namespaced')
end

function TestConfigInfoText:test_falls_back_to_global_when_absent()
    local source
    C_GuildInfo = nil
    GetGuildInfoText = function()
        source = 'global'
        return 'GW:c:Chan:pass\nGW:v:1.0.0\n'
    end
    GoonConfig:new():load()
    lu.assertEquals(source, 'global')
end

function TestConfigInfoText:test_falls_back_when_method_missing()
    local source
    C_GuildInfo = {}    -- table present, but no GetInfoText field
    GetGuildInfoText = function()
        source = 'global'
        return 'GW:c:Chan:pass\nGW:v:1.0.0\n'
    end
    GoonConfig:new():load()
    lu.assertEquals(source, 'global')
end

--
-- GoonConfig:load() - guild info text is protected in battlegrounds.
--

TestConfigRestricted = {}

function TestConfigRestricted:setUp()
    self.saved = {
        GetGuildInfoText = GetGuildInfoText,
        GetGuildName = goonwall.GetGuildName,
        settings = goonwall.settings,
        IsInInstance = IsInInstance,
    }
    goonwall.settings = GoonSettings:new()
    goonwall.GetGuildName = function() return 'TestGuild' end
    self.reads = 0
    self.instance = 'none'
    IsInInstance = function() return self.instance ~= 'none', self.instance end
    GetGuildInfoText = function() self.reads = self.reads + 1 return self.info end
end

function TestConfigRestricted:tearDown()
    GetGuildInfoText = self.saved.GetGuildInfoText
    goonwall.GetGuildName = self.saved.GetGuildName
    goonwall.settings = self.saved.settings
    IsInInstance = self.saved.IsInInstance
end

function TestConfigRestricted:test_not_read_in_battleground()
    self.instance = 'pvp'
    self.info = 'GW:c:Chan:pass\n'
    local config = GoonConfig:new()
    lu.assertFalse(config:load())
    lu.assertEquals(self.reads, 0)
    lu.assertFalse(config.valid)
end

function TestConfigRestricted:test_not_read_in_combat()
    local saved = InCombatLockdown
    InCombatLockdown = function() return true end
    self.info = 'GW:c:Chan:pass\n'
    local config = GoonConfig:new()
    lu.assertFalse(config:load())
    InCombatLockdown = saved
    lu.assertEquals(self.reads, 0)
end

function TestConfigRestricted:test_nil_info_is_not_available()
    self.info = nil
    local config = GoonConfig:new()
    lu.assertFalse(config:load())
    lu.assertFalse(config.valid)
end


--
-- Run the tests
--

os.exit(lu.run())
