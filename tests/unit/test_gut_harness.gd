extends GutTest

# Proves the GUT harness itself runs: not project coverage, disposable once
# a real P2 test exists. See docs/KNOWN_ISSUES.md ## Environment.

func test_harness_runs():
	assert_eq(1 + 1, 2, "arithmetic should still work")
