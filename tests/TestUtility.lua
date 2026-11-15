--
-- Mocks
--

goonwall = { logmsg = '' }

function goonwall.Debug(level, format, ...)
    goonwall.logmsg = string.format(format, ...)
end


--
-- Includes
--

lu = require('luaunit')
require('Loader')


--
-- Test Cases
--

TestUtility = {}

function TestUtility:test_iCmp()
    lu.assertTrue(goonwall.iCmp("Foo", "FOO"))
    lu.assertTrue(goonwall.iCmp("Foo", "Foo"))
    lu.assertFalse(goonwall.iCmp("Foo", "FOOBAR"))
end

function TestUtility:test_GlobalName()
    lu.assertEquals(goonwall.GlobalName("Ralff", "EarthenRing"), "Ralff-EarthenRing")
    lu.assertEquals(goonwall.GlobalName("Ralff", "Earthen Ring"), "Ralff-EarthenRing")
    lu.assertEquals(goonwall.GlobalName("Ralff-EarthenRing"), "Ralff-EarthenRing")
    lu.assertEquals(goonwall.GlobalName("Ralff-EarthenRing", "EarthenRing"), "Ralff-EarthenRing")
    lu.assertEquals(goonwall.GlobalName("Ralff"), "Ralff-EarthenRing")
    lu.assertNil(goonwall.GlobalName(nil))
end

function TestUtility:test_GetItemString()
    local single = 'Testing |Hitem:6948::::::::80::::|h in a string.'
    local multi = 'Testing |Hitem:6948::::::::80::::|h and |Hitem:4388:0:0:0:0:0:0:210677200:80:0:0:0:0|h in a string.'
    lu.assertEquals(goonwall.GetItemString(single), 'item:6948::::::::80::::')
    lu.assertEquals(goonwall.GetItemString(multi), 'item:6948::::::::80::::')
    lu.assertEquals(goonwall.GetItemString('nothing here'), nil)
    lu.assertError(goonwall.GetItemString)
end


--
-- Run the tests
--

os.exit(lu.run())
