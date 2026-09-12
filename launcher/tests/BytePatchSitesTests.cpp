#include "doctest.h"

#include "BytePatchSites.h"

#include <cstring>
#include <set>
#include <string>
#include <utility>
#include <vector>

//Checks the real kPatchModules table, not a fixture. A byte-patch site is data
//that cannot be exercised without the stock DLL loaded, so these are the
//invariants that hold without it: the table is self-consistent, each site
//actually changes something, and the fingerprints match what the RE notes
//recorded. A site whose bytes drift silently is the failure mode -- it would
//just stop matching at runtime and log a mismatch the user has to interpret.

namespace
{
    //Every site in the table, flattened, so the invariants below need no nesting.
    std::vector<std::pair<const SPatchModule*, const SPatchSite*>> AllSites()
    {
        std::vector<std::pair<const SPatchModule*, const SPatchSite*>> Sites;
        for (const SPatchModule& Module : kPatchModules)
        {
            for (size_t i = 0; i < Module.iSiteCount; ++i)
            {
                Sites.emplace_back(&Module, &Module.pSites[i]);
            }
        }
        return Sites;
    }
}

TEST_CASE("Every byte-patch module is well formed")
{
    std::set<std::wstring> Names;
    for (const SPatchModule& Module : kPatchModules)
    {
        CHECK(Module.pszModule != nullptr);
        CHECK(std::wstring(Module.pszModule).length() > 0);
        CHECK(Module.iPreferredBase != 0);
        CHECK(Module.pSites != nullptr);
        CHECK(Module.iSiteCount > 0);
        //One row per module: CBytePatch resolves and logs each module once.
        CHECK(Names.insert(Module.pszModule).second);
    }
}

TEST_CASE("Every byte-patch site actually changes bytes")
{
    for (const auto& Entry : AllSites())
    {
        const SPatchSite& Site = *Entry.second;
        CHECK(Site.iLen > 0);
        CHECK(Site.pExpected != nullptr);
        CHECK(Site.pReplacement != nullptr);
        //A site whose replacement equals its fingerprint patches nothing, which
        //is always a mistake rather than a deliberate no-op.
        CHECK(memcmp(Site.pExpected, Site.pReplacement, Site.iLen) != 0);
    }
}

TEST_CASE("Every byte-patch site carries a description and a consequence")
{
    //Both are user-facing: the description names the site in the log, the
    //startup header and the mismatch dialog; the consequence is what the dialog
    //tells the user they lose by continuing.
    for (const auto& Entry : AllSites())
    {
        const SPatchSite& Site = *Entry.second;
        REQUIRE(Site.pszDescription != nullptr);
        REQUIRE(Site.pszConsequence != nullptr);
        CHECK(std::wstring(Site.pszDescription).length() > 0);
        CHECK(std::wstring(Site.pszConsequence).length() > 0);
    }
}

TEST_CASE("Byte-patch sites within a module do not overlap")
{
    //Overlapping runs would make the second site's fingerprint depend on
    //whether the first was already written.
    for (const SPatchModule& Module : kPatchModules)
    {
        for (size_t i = 0; i < Module.iSiteCount; ++i)
        {
            for (size_t j = i + 1; j < Module.iSiteCount; ++j)
            {
                const SPatchSite& A = Module.pSites[i];
                const SPatchSite& B = Module.pSites[j];
                const bool bDisjoint = (A.iPreferredVA + A.iLen <= B.iPreferredVA)
                                    || (B.iPreferredVA + B.iLen <= A.iPreferredVA);
                CHECK(bDisjoint);
            }
        }
    }
}

TEST_CASE("Byte-patch site addresses lie above their module's preferred base")
{
    for (const auto& Entry : AllSites())
    {
        CHECK(Entry.second->iPreferredVA > Entry.first->iPreferredBase);
    }
}

TEST_CASE("WinDrv joy-loop sites retarget the button bitmap from 0xeb0 to 0xf78")
{
    //CMP byte [ECX+EAX+0xeb0], BL -> [ECX+EAX+0xf78], BL, at both the press and
    //release branches. See ../deusex-native-re/docs/windrv-input.md.
    const BYTE aExpected[]    = { 0x38, 0x9C, 0x01, 0xB0, 0x0E, 0x00, 0x00 };
    const BYTE aReplacement[] = { 0x38, 0x9C, 0x01, 0x78, 0x0F, 0x00, 0x00 };

    REQUIRE(_countof(kWinDrvSites) >= 2);
    for (size_t i = 0; i < 2; ++i)
    {
        REQUIRE(kWinDrvSites[i].iLen == _countof(aExpected));
        CHECK(memcmp(kWinDrvSites[i].pExpected, aExpected, sizeof(aExpected)) == 0);
        CHECK(memcmp(kWinDrvSites[i].pReplacement, aReplacement, sizeof(aReplacement)) == 0);
    }
    CHECK(kWinDrvSites[0].iPreferredVA == 0x11109341);
    CHECK(kWinDrvSites[1].iPreferredVA == 0x11109372);
}

TEST_CASE("WinDrv trailer site lowers the outer-loop bound from 0x100 to 0xc8")
{
    const BYTE aExpected[]    = { 0x81, 0xFF, 0x00, 0x01, 0x00, 0x00 };
    const BYTE aReplacement[] = { 0x81, 0xFF, 0xC8, 0x00, 0x00, 0x00 };

    REQUIRE(_countof(kWinDrvSites) == 3);
    REQUIRE(kWinDrvSites[2].iLen == _countof(aExpected));
    CHECK(kWinDrvSites[2].iPreferredVA == 0x11109881);
    CHECK(memcmp(kWinDrvSites[2].pExpected, aExpected, sizeof(aExpected)) == 0);
    CHECK(memcmp(kWinDrvSites[2].pReplacement, aReplacement, sizeof(aReplacement)) == 0);
}
