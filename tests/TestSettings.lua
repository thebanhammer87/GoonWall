lu = require('luaunit')
require('Loader')


--
-- Mocks
--

goonwall = { logmsg = '' }

function goonwall.Debug(level, format, ...)
    goonwall.logmsg = string.format(format, ...)
end


--
-- Test Cases
--

TestSettingsCreate = {}

function TestSettingsCreate:setUp()
    GoonWallMeta = nil
    GoonWall = nil
    GoonWallAccount = nil
end

function TestSettingsCreate:test_new()
    local settings = GoonSettings:new()
    lu.assertEquals(type(GoonWallMeta), 'table')
    lu.assertEquals(type(GoonWall), 'table')
    lu.assertEquals(type(GoonWallAccount), 'table')
end

function TestSettingsCreate:test_meta()
    local settings = GoonSettings:new()
    lu.assertEquals(GoonWallMeta.mode, GOON_MODE_ACCOUNT)
    lu.assertStrMatches(GoonWallMeta.created, '%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d')
    lu.assertStrMatches(GoonWallMeta.updated, '%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d')
end

function TestSettingsCreate:test_initialize()
    local settings = GoonSettings:new()
    for i, tab in ipairs({GoonWall, GoonWallAccount}) do
        lu.assertStrMatches(tab.created, '%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d')
        lu.assertStrMatches(tab.updated, '%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d')
        lu.assertEquals(tab.tag, true)
        lu.assertEquals(tab.roster, true)
        lu.assertEquals(tab.debug, GOON_LOG_NONE)
        lu.assertEquals(tab.verbose, false)
        lu.assertEquals(tab.log, false)
        lu.assertEquals(tab.logsize, 2048)
        lu.assertEquals(tab.redact, true)
        lu.assertEquals(tab.joindelay, 30)
    end
end


TestSettingsLoad = {}

function TestSettingsLoad:setUp()
    GoonWallMeta = {
        mode = GOON_MODE_CHARACTER,
        created = "2018-01-01 17:28:47",
        updated = "2018-01-01 01:04:46",
    }
    GoonWall = {
        created = "2018-01-01 17:28:47",
        updated = "2018-01-01 01:04:46",
        roster = false,
    }
    GoonWallAccount = {
        created = "2018-01-01 17:28:47",
        updated = "2018-01-01 01:04:46",
        log = true,
        logsize = 1024,
        redact = false,
    }
end

function TestSettingsLoad:test_new()
    local settings = GoonSettings:new()
    lu.assertEquals(type(GoonWallMeta), 'table')
    lu.assertEquals(type(GoonWall), 'table')
    lu.assertEquals(type(GoonWallAccount), 'table')
end

function TestSettingsLoad:test_meta()
    local settings = GoonSettings:new()
    lu.assertEquals(GoonWallMeta.mode, GOON_MODE_CHARACTER)
end

function TestSettingsLoad:test_character()
    local settings = GoonSettings:new()
    lu.assertEquals(GoonWall.tag, true)
    lu.assertEquals(GoonWall.roster, false)
end

function TestSettingsLoad:test_account()
    local settings = GoonSettings:new()
    lu.assertEquals(GoonWallAccount.log, true)
    lu.assertEquals(GoonWallAccount.logsize, 1024)
    lu.assertEquals(GoonWallAccount.redact, false)
end


TestSettingsAccess = {}

function TestSettingsAccess:setUp()
    GoonWallMeta = {
        mode = GOON_MODE_ACCOUNT,
        created = "2018-01-01 17:28:47",
        updated = "2018-01-01 01:04:46",
    }
    GoonWall = {
        created = "2018-01-01 17:28:47",
        updated = "2018-01-01 01:04:46",
        tag = true,
        logsize = 1024,
    }
    GoonWallAccount = {
        created = "2018-01-01 17:28:47",
        updated = "2018-01-01 01:04:46",
        tag = false,
        logsize = 2048,
    }
end

function TestSettingsAccess:test_get()
    local settings = GoonSettings:new()

    lu.assertEquals(settings:get('mode'), GOON_MODE_ACCOUNT)

    lu.assertEquals(settings:get('tag'), false)
    lu.assertEquals(settings:get('logsize'), 2048)

    lu.assertEquals(settings:get('tag',GOON_MODE_CHARACTER), true)
    lu.assertEquals(settings:get('logsize', GOON_MODE_CHARACTER), 1024)

    settings:set('mode', GOON_MODE_CHARACTER)
    lu.assertEquals(settings:get('mode'), GOON_MODE_CHARACTER)

    lu.assertEquals(settings:get('tag'), true)
    lu.assertEquals(settings:get('logsize'), 1024)

    lu.assertEquals(settings:get('tag', GOON_MODE_ACCOUNT), false)
    lu.assertEquals(settings:get('logsize', GOON_MODE_ACCOUNT), 2048)
end

function TestSettingsAccess:test_set()
    local settings = GoonSettings:new()

    settings:set('mode', GOON_MODE_ACCOUNT)
    lu.assertEquals(settings:get('tag', GOON_MODE_ACCOUNT), false)
    lu.assertEquals(settings:get('tag', GOON_MODE_CHARACTER), true)

    settings:set('tag', true)
    lu.assertEquals(settings:get('tag', GOON_MODE_ACCOUNT), true)
    lu.assertEquals(settings:get('tag', GOON_MODE_CHARACTER), true)

    settings:set('mode', GOON_MODE_CHARACTER)
    settings:set('tag', false)
    lu.assertEquals(settings:get('tag', GOON_MODE_ACCOUNT), true)
    lu.assertEquals(settings:get('tag', GOON_MODE_CHARACTER), false)
end


TestSettingsUpgrade = {}

function TestSettingsUpgrade:setUp()
    GoonWallMeta = nil
    GoonWall = {
        created = "2018-01-01 17:28:47",
        updated = "2018-01-01 01:04:46",
        roster = false,
        redact = false,
    }
    GoonWallAccount = nil
end

function TestSettingsUpgrade:test_new()
    local settings = GoonSettings:new()
    lu.assertEquals(type(GoonWallMeta), 'table')
    lu.assertEquals(type(GoonWall), 'table')
    lu.assertEquals(type(GoonWallAccount), 'table')
end

function TestSettingsUpgrade:test_meta()
    local settings = GoonSettings:new()
    lu.assertEquals(GoonWallMeta.mode, GOON_MODE_CHARACTER)
end

function TestSettingsUpgrade:test_character()
    local settings = GoonSettings:new()
    lu.assertEquals(GoonWall.roster, false)
    lu.assertEquals(GoonWall.redact, false)
end

function TestSettingsUpgrade:test_account()
    local settings = GoonSettings:new()
    lu.assertEquals(GoonWallAccount.roster, true)
    lu.assertEquals(GoonWallAccount.redact, true)
end


--
-- Run the tests
--

os.exit(lu.run())
