--
-- Includes
--

lu = require('luaunit')
require('Loader')


--
-- Test Cases
--

TestAPI = {}

function TestAPI:test_get_channel_numbers()
    goonwall.config = {
        channel = {
            guild = { number = 5 },
        }
    }
    local c = GoonWallAPI.GetChannelNumbers()
    lu.assertEquals(c, { 5 })
end


--
-- Message-handler registration, removal, and dispatch.
--

local function noop() end

function TestAPI:setUp()
    goonwall.api_table = {}
    -- AddMessageHandler validates `addon == C_AddOns.GetAddOnInfo(addon)` for non-'*' ids.
    C_AddOns.GetAddOnInfo = function(addon) return addon end
    goonwall.player = 'Ralff'
    goonwall.config = { guild_id = 'G1' }
end

function TestAPI:test_add_and_remove_handler()
    local id = GoonWallAPI.AddMessageHandler(noop, '*', 0)
    lu.assertEquals(#goonwall.api_table, 1)
    lu.assertTrue(GoonWallAPI.RemoveMessageHandler(id))
    lu.assertEquals(#goonwall.api_table, 0)
    lu.assertFalse(GoonWallAPI.RemoveMessageHandler(id))     -- already gone
    lu.assertFalse(GoonWallAPI.RemoveMessageHandler('nope')) -- never existed
end

function TestAPI:test_remove_middle_handler_leaves_no_hole()
    local function h1() end
    local function h2() end
    local function h3() end
    local id1 = GoonWallAPI.AddMessageHandler(h1, '*', 0)
    local id2 = GoonWallAPI.AddMessageHandler(h2, '*', 0)
    local id3 = GoonWallAPI.AddMessageHandler(h3, '*', 0)
    lu.assertTrue(GoonWallAPI.RemoveMessageHandler(id2))     -- remove the middle entry
    -- A nil-hole would truncate ipairs; table.remove keeps the array dense.
    lu.assertEquals(#goonwall.api_table, 2)
    local seen = {}
    for _, e in ipairs(goonwall.api_table) do seen[e[1]] = true end
    lu.assertTrue(seen[id1])
    lu.assertTrue(seen[id3])
    lu.assertNil(seen[id2])
end

function TestAPI:test_clear_by_addon_removes_all_matching()
    GoonWallAPI.AddMessageHandler(noop, 'AddonA', 0)
    GoonWallAPI.AddMessageHandler(noop, 'AddonA', 0)
    GoonWallAPI.AddMessageHandler(noop, 'AddonB', 0)
    lu.assertEquals(#goonwall.api_table, 3)
    GoonWallAPI.ClearMessageHandlers('AddonA')  -- must remove BOTH AddonA entries
    lu.assertEquals(#goonwall.api_table, 1)
    lu.assertEquals(goonwall.api_table[1][2], 'AddonB')
end

function TestAPI:test_clear_all_handlers()
    GoonWallAPI.AddMessageHandler(noop, '*', 0)
    GoonWallAPI.AddMessageHandler(noop, 'AddonA', 0)
    GoonWallAPI.ClearMessageHandlers()          -- nil -> remove everything
    lu.assertEquals(#goonwall.api_table, 0)
end

function TestAPI:test_dispatch_matches_by_addon()
    local hits = {}
    GoonWallAPI.AddMessageHandler(function() hits.a = (hits.a or 0) + 1 end, 'AddonA', 0)
    GoonWallAPI.AddMessageHandler(function() hits.b = (hits.b or 0) + 1 end, 'AddonB', 0)
    goonwall.APIDispatcher('AddonA', 'Someone', 'G1', 'hello')
    lu.assertEquals(hits.a, 1)   -- addon-matched handler fires
    lu.assertNil(hits.b)         -- non-matching handler does not
end


--
-- Run the tests
--

os.exit(lu.run())
