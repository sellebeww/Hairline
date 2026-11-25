# Copyright (c) 2026 Vassel Goleyu. MIT License.
"""Rasterizes the sheet layouts dumped by packages/hairline_core/tool/dump_sheet_layout.dart
and checks them with the real OpenCV ArUco detector (DICT_4X4_50): every sheet, both papers,
ids 4s..4s+3 found and the TL corner of each marker within 0.1 mm of the 5.1 position.

Run: (cd packages/hairline_core && dart run tool/dump_sheet_layout.dart) > /tmp/layouts.json
     v/bin/python tools/verify_sheet_raster.py /tmp/layouts.json
"""
import json
import sys

import cv2
import numpy as np

PPM = 10  # raster pixels per mm
D = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)
params = cv2.aruco.DetectorParameters()
params.cornerRefinementMethod = cv2.aruco.CORNER_REFINE_SUBPIX
detector = cv2.aruco.ArucoDetector(D, params)

worst = 0.0
for sheet in json.load(open(sys.argv[1])):
    w, h = round(sheet["w"] * PPM), round(sheet["h"] * PPM)
    img = np.full((h, w), 255, np.uint8)
    for x, y, rw, rh, black in sheet["rects"]:
        x0, y0, x1, y1 = (round(v * PPM) for v in (x, y, x + rw, y + rh))
        img[y0:y1, x0:x1] = 0 if black else 255
    corners, ids, _ = detector.detectMarkers(img)
    s = sheet["sheet"]
    found = sorted(int(i) for i in ids.ravel()) if ids is not None else []
    assert found == [4 * s + k for k in range(4)], (sheet["paper"], s, found)
    cx, cy = sheet["w"] / 2, 100.0
    for c, i in zip(corners, ids.ravel()):
        k = int(i) % 4
        sx, sy = [(-60, -60), (60, -60), (60, 60), (-60, 60)][k]
        truth = np.array([(cx + sx + dx, cy + sy + dy) for dx, dy in [(-15, -15), (15, -15), (15, 15), (-15, 15)]])
        err = np.abs(c.reshape(4, 2) / PPM - truth).max()
        worst = max(worst, float(err))
        assert err < 0.1, (sheet["paper"], s, int(i), err)
print(f"OK: {len(json.load(open(sys.argv[1])))} sheets, all ids detected, worst corner error {worst:.3f} mm, OpenCV {cv2.__version__}")
