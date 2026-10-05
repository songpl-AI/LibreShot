# Finder numbered rows

`finder-numbered-rows.png` is a native macOS Finder list screenshot captured on 2026-10-05 from a dedicated public test directory containing `LibreShot-QA-row-001.txt` through `120.txt`. The crop contains only test-file rows and Finder column labels. It contains no private documents or desktop background.

`Issue4RegressionChecks.swift` replays overlapping viewports from these actual pixels and compares the stitched result pixel-for-pixel. Alternating row backgrounds and small numeric differences reproduce motion incorrectly discarded by the former thumbnail tolerance. Run from the repository root with `LIBRESHOT_OPTIMIZE=1 bash tests/run-issue4-checks.sh`.
