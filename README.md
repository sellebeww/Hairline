# Hairline

Longitudinal crack-width monitoring for non-professionals, Android first (Flutter). A printed ArUco marker frame is glued around a crack. On each visit the app guides the phone pose, rectifies the image to the sheet plane with a homography, measures the crack width at one marked point with a sub-pixel profile model, computes an uncertainty budget, and compares the result with earlier visits. A change is flagged only when it exceeds the measurement uncertainty.

Status: Phase 7 (sheet PDF, guided setup, screens, trend) done on synthetic data; real camera, OpenCV detection on device and plate validation are not yet verified (docs/DEVICE_TEST.md). See [docs/PROGRESS.md](docs/PROGRESS.md).

## Layout

- `packages/hairline_core`: pure Dart geometry and measurement core (no Flutter, no OpenCV).
- `app`: Flutter app (Riverpod, go_router, Drift, camera, pdf, printing). `opencv_dart` joins in Phase 5.
- `tools`: spikes and helper scripts. `docs`: progress, decisions, backlog, blockers.

Run `make verify` for the standard checks.

## Honest statements

- Results are INDICATIVE and do not replace inspection by a structural engineer. The app does not assess building safety and never shows the words "safe" or "harmless". If a crack appears to widen, lengthen, or a new crack appears, contact an engineer or the authorities.
- "No change detected" means any change is smaller than the measurement uncertainty. It is not proof that the crack did not change.
- Accuracy numbers may only be reported with their origin label: `SYNTHETIC` (from simulation) or `DEVICE` (from plate validation on a real phone by the owner). No unlabeled accuracy figure is allowed, and none exists yet.
- Claims about literature and competitors in the original specification (a Witteveen+Bos app, a 5 mm camera-shift error, an add-on lens for 0.3 to 1 mm at 2 m) are reported, not verified.
- Hairline does not accurately measure cracks that are not coplanar with the marker sheet, and is not suitable for regulatory decisions.

## License and ownership

MIT. Copyright (c) 2026 Vassel Goleyu.
