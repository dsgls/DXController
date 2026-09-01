// Test-runner entry point. doctest's main lives here; other test translation
// units just include doctest.h and declare TEST_CASEs.
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include "doctest.h"

TEST_CASE("test scaffold runs") {
    CHECK(1 + 1 == 2);
}
