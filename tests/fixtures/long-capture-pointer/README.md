# Public pointer contamination frames

Captured locally with installed LibreShot 1.3.24 build 54 on 2026-10-14. Each contains only public row IDs and deterministic sample numbers from the AppKit fixture; no user chat content. These are ordinary region screenshot exports, not the raw rejected ScreenCaptureKit stream pair.

`probe-start.png` is the 0px viewport; `probe-wheel.png` is at 122px with a visible pointer halo; `probe-redraw.png` is at the same 122px position after repaint without the halo. All are 545×715. Tests crop 12px from each edge solely to remove screenshot export rounding, then call the actual matcher, seam verifier, accumulator and final renderer. The clean interior overlap is pixel-exact; the contaminated overlap must remain rejected. This fixture does not establish the cause of the user's Codex failures.
