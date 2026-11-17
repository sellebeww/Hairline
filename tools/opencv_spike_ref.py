# Copyright (c) 2026 Vassel Goleyu. MIT License.
"""Independent reference for the Phase 1 opencv_dart spike (mirrors app/test/spike).

Run: python3 -m venv v && v/bin/pip install opencv-contrib-python-headless numpy
     v/bin/python tools/opencv_spike_ref.py
"""
import cv2
import numpy as np

SIDE = 120
ORIGINS = [(100, 100), (580, 100), (580, 580), (100, 580)]
D = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)

img = np.full((800, 800), 255, np.uint8)
for i, (x, y) in enumerate(ORIGINS):
    img[y:y + SIDE, x:x + SIDE] = cv2.aruco.generateImageMarker(D, i, SIDE, borderBits=1)


def detect(image, refine):
    p = cv2.aruco.DetectorParameters()
    p.cornerRefinementMethod = refine
    corners, ids, _ = cv2.aruco.ArucoDetector(D, p).detectMarkers(image)
    worst = {"dx": 0.0, "dy": 0.0}
    for c, i in zip(corners, ids.ravel()):
        x, y = ORIGINS[i]
        truth = np.array([(x, y), (x + SIDE, y), (x + SIDE, y + SIDE), (x, y + SIDE)], float)
        d = c.reshape(4, 2) - truth
        worst["dx"] = max(worst["dx"], float(np.abs(d[:, 0]).max()))
        worst["dy"] = max(worst["dy"], float(np.abs(d[:, 1]).max()))
    return len(ids), worst, corners[0].reshape(4, 2).tolist()


for name, m in [("NONE", cv2.aruco.CORNER_REFINE_NONE), ("SUBPIX", cv2.aruco.CORNER_REFINE_SUBPIX)]:
    n, w, c0 = detect(img, m)
    print(name, "n=", n, "max|err| vs integer pixel-edge truth:", w, "marker0 corners:", c0)

ok, jpg = cv2.imencode(".jpg", img)
gray = cv2.imdecode(jpg, cv2.IMREAD_GRAYSCALE)
roi = gray[300:348, 300:364]
print("jpeg bytes", len(jpg), "gray", gray.shape, "roi", roi.shape, "roi min", int(roi.min()))
n, w, _ = detect(gray, cv2.aruco.CORNER_REFINE_SUBPIX)
print("after JPEG, SUBPIX n=", n, w)
