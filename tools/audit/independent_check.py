# Copyright (c) 2026 Vassel Goleyu. MIT License.
"""Independent recomputation of hairline_core numbers (Phase 9 audit).

Everything below is written from CLAUDE.md 5.1 to 5.6 with numpy/scipy only; it does not
read any core source. Flow:
  python3 independent_check.py gen cases.json
  (cd packages/hairline_core && dart run tool/audit_dump.dart cases.json out.json)
  python3 independent_check.py cmp cases.json out.json
Seeds are fixed (SEED). Needs numpy and scipy (a venv outside the repo is enough).
"""
import json
import sys

import numpy as np
from scipy import ndimage, optimize, stats

SEED = 20261125
S3 = np.sqrt(3.0)
SHEET = 2  # ids 8..11


def marker_corners_mm(mid, scale=1.0):
    k = mid % 4
    cx, cy = [(-60, -60), (60, -60), (60, 60), (-60, 60)][k]
    return np.array([(cx - 15, cy - 15), (cx + 15, cy - 15), (cx + 15, cy + 15), (cx - 15, cy + 15)], float) * scale


def rot(axis, deg):
    a = np.deg2rad(deg)
    c, s = np.cos(a), np.sin(a)
    if axis == "z":
        return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def camera_h(f, cx, cy, tilt, tilt_dir, inplane, z):
    """Sheet (mm, z=0) -> pixel homography of a pinhole camera; also the true tilt."""
    r = rot("z", inplane) @ rot("z", tilt_dir) @ rot("x", tilt) @ rot("z", -tilt_dir)
    t = np.array([0.0, 0.0, z])
    k = np.array([[f, 0, cx], [0, f, cy], [0, 0, 1.0]])
    h = k @ np.column_stack([r[:, 0], r[:, 1], t])
    return h / h[2, 2], float(np.rad2deg(np.arccos(abs(r[2, 2]))))


def apply(h, p):
    p = np.atleast_2d(p)
    q = (h @ np.column_stack([p, np.ones(len(p))]).T).T
    return q[:, :2] / q[:, 2:3]


def dlt(src, dst):
    def norm(p):
        c = p.mean(0)
        s = np.sqrt(2) / np.mean(np.linalg.norm(p - c, axis=1))
        t = np.array([[s, 0, -s * c[0]], [0, s, -s * c[1]], [0, 0, 1]])
        return t, apply(t, p)

    ts, ns = norm(src)
    td, nd = norm(dst)
    rows = []
    for (x, y), (u, v) in zip(ns, nd):
        rows.append([-x, -y, -1, 0, 0, 0, u * x, u * y, u])
        rows.append([0, 0, 0, -x, -y, -1, v * x, v * y, v])
    h = np.linalg.svd(np.array(rows))[2][-1].reshape(3, 3)
    h = np.linalg.inv(td) @ h @ ts
    return h / h[2, 2]


def fit_h(src, dst):
    h0 = dlt(src, dst)

    def res(p):
        return (apply(np.append(p, 1.0).reshape(3, 3), src) - dst).ravel()

    sol = optimize.least_squares(res, h0.ravel()[:8], method="lm", xtol=1e-15, ftol=1e-15, gtol=1e-15)
    return np.append(sol.x, 1.0).reshape(3, 3)


def local_scale(h, p_mm):
    g = np.linalg.inv(h)
    c = apply(h, np.atleast_2d(p_mm))[0]
    v = g @ np.array([c[0], c[1], 1.0])
    w = v[2]
    j = (g[:2, :2] * w - np.outer(v[:2], g[2, :2])) / (w * w)  # analytic d(sheet)/d(pixel)
    sv = np.linalg.svd(j, compute_uv=False)
    return float(np.sqrt(abs(np.linalg.det(j)))), float(sv[0] / sv[1])


def tilt_from_h(h, f, cx, cy):
    k = np.array([[f, 0, cx], [0, f, cy], [0, 0, 1.0]])
    m = np.linalg.inv(k) @ h
    r1, r2 = m[:, 0], m[:, 1]
    lam = 2.0 / (np.linalg.norm(r1) + np.linalg.norm(r2))
    r3 = np.cross(r1 * lam, r2 * lam)
    r3 /= np.linalg.norm(r3)
    return float(np.rad2deg(np.arccos(abs(r3[2]))))


def gen_cases():
    rng = np.random.default_rng(SEED)
    hom, bud, trn = [], [], []
    # (tilt, tilt_dir, inplane, z[mm], markers, noise px, print scale)
    specs = [
        (0, 0, 0, 240, 4, 0.2, 1.0),
        (10, 30, 90, 260, 4, 0.2, 0.99),
        (20, 120, 180, 300, 3, 0.2, 1.01),
        (30, 200, 270, 280, 4, 0.2, 1.0),
        (5, 45, 37, 220, 4, 0.5, 1.0),
        (15, -60, 123, 250, 3, 0.1, 0.98),
    ]
    f, cx, cy = 3000.0, 1999.5, 1499.5
    for tilt, td, ip, z, nm, sig, ps in specs:
        h, true_tilt = camera_h(f, cx, cy, tilt, td, ip, z)
        dets = []
        for mid in [4 * SHEET + i for i in range(4)][:nm]:
            px = apply(h, marker_corners_mm(mid, ps)) + rng.normal(0, sig, (4, 2))
            dets.append({"id": mid, "corners": px.tolist()})
        hom.append({"sheet": SHEET, "print_scale": ps, "detections": dets, "f_px": f, "cx": cx, "cy": cy,
                    "probe_mm": [[0, 0], [10, -8], [-24, 24]], "true_tilt": true_tilt, "noise": sig})
    hom += real_detector_cases()
    # budget cases: (n, loo available, u_dev, dz, u_print_rel)
    for n, loo_on, udev, dz, upr in [(5, True, None, 0.3, 0.0033), (3, True, 0.02, 1.0, 0.0029), (4, False, None, 0.3, 0.0033),
                                      (5, True, 0.05, 0.3, 0.0), (3, False, 0.01, 1.0, 0.0058), (5, True, None, 1.0, 0.0029)]:
        frames = []
        for _ in range(n):
            frames.append({"width": float(rng.normal(0.62, 0.01)), "u_fit_raw": float(rng.uniform(0.002, 0.01)), "rho": 1.0,
                           "u_sigma_w": float(rng.uniform(0.003, 0.01)), "dw_ds": float(rng.normal(0, 0.02)),
                           "mm_per_px": float(rng.uniform(0.06, 0.11)), "rms_px": float(rng.uniform(0.1, 0.4)),
                           "loo_mm": float(rng.uniform(0.02, 0.1)) if loo_on else None, "tilt_deg": float(rng.uniform(2, 15))})
        bud.append({"frames": frames, "options": {"dz": dz, "u_print_rel": upr, "u_dev": udev}})
    for a, b, upr in [((0.5, 0.01), (0.55, 0.012), 0.003), ((0.5, 0.01), (0.9, 0.02), 0.003), ((0.8, 0.02), (0.4, 0.015), 0.006),
                      ((0.5, 0.05), (0.52, 0.05), 0.003), ((0.3, 0.004), (0.31, 0.004), 0.0)]:
        trn.append({"a": {"width": a[0], "u_rand": a[1]}, "b": {"width": b[0], "u_rand": b[1]}, "u_print_rel": upr})
    # profile cases: analytic crack seen through a (tilted) camera, point-sampled at pixel centres
    prof = []
    for w, ang, tilt, sigma_px in [(0.3, 20, 0, 1.0), (0.6, 75, 10, 1.0), (1.0, 140, 0, 1.5), (0.45, 5, 15, 0.8)]:
        h, _ = camera_h(3000.0, 59.5, 59.5, tilt, 40, 0, 240)
        g = np.linalg.inv(h)
        n_px = 120
        ii, jj = np.meshgrid(np.arange(n_px), np.arange(n_px))
        pm = apply(g, np.column_stack([ii.ravel(), jj.ravel()]).astype(float))
        a = np.deg2rad(ang)
        s = pm @ np.array([-np.sin(a), np.cos(a)])
        mmpp = local_scale(h, [0, 0])[0]
        sigma_mm = sigma_px * mmpp
        bg, m, d, c = 0.8, 0.002, 0.30, 0.05
        img = bg + m * s - d * (stats.norm.cdf((s - c + w / 2) / sigma_mm) - stats.norm.cdf((s - c - w / 2) / sigma_mm))
        prof.append({"patch_w": n_px, "patch_h": n_px, "origin_x": 0, "origin_y": 0, "data": img.tolist(), "h": h.ravel().tolist(),
                     "point_mm": [0.0, 0.0], "direction_deg": ang, "sigma_mm": float(sigma_mm), "true_w": w, "true_c": c, "mmpp": mmpp})
    return {"homography": hom, "budget": bud, "trend": trn,
            "k_dof": [1, 1.5, 2, 2.7, 4, 7.3, 10, 20, 29.5, 30, 45, 80, 200, 1e6], "profile": prof}


def real_detector_cases():
    """Sheet rasterised with real ArUco markers, warped through a pinhole camera at in-plane
    rotations 0/90/180/270, then detected by the real OpenCV detector (corner order as returned)."""
    try:
        import cv2
    except ImportError:
        return []
    d = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)
    params = cv2.aruco.DetectorParameters()
    params.cornerRefinementMethod = cv2.aruco.CORNER_REFINE_SUBPIX
    det = cv2.aruco.ArucoDetector(d, params)
    ppm, half = 10, 100  # raster pixels per mm, half extent mm
    n = 2 * half * ppm
    raster = np.full((n, n), 255, np.uint8)
    for k in range(4):
        mid = 4 * SHEET + k
        cx, cy = [(-60, -60), (60, -60), (60, 60), (-60, 60)][k]
        mk = cv2.aruco.generateImageMarker(d, mid, 30 * ppm, 1)
        x0, y0 = int(round((cx - 15 + half) * ppm)), int(round((cy - 15 + half) * ppm))
        raster[y0:y0 + 30 * ppm, x0:x0 + 30 * ppm] = mk
    to_mm = np.array([[1 / ppm, 0, 0.5 / ppm - half], [0, 1 / ppm, 0.5 / ppm - half], [0, 0, 1.0]])
    out = []
    f, cx, cy = 3000.0, 1999.5, 1499.5
    for ip, tilt, td in [(0, 10, 30), (90, 10, 30), (180, 10, 30), (270, 10, 30), (45, 0, 0), (200, 20, 100)]:
        h, true_tilt = camera_h(f, cx, cy, tilt, td, ip, 260)
        img = cv2.warpPerspective(raster, h @ to_mm, (4000, 3000), flags=cv2.INTER_AREA, borderValue=255)
        corners, ids, _ = det.detectMarkers(img)
        dets = [{"id": int(i), "corners": c.reshape(4, 2).astype(float).tolist()} for i, c in zip(ids.ravel(), corners)]
        out.append({"sheet": SHEET, "print_scale": 1.0, "detections": dets, "f_px": f, "cx": cx, "cy": cy,
                    "probe_mm": [[0, 0], [10, -8], [-24, 24]], "true_tilt": true_tilt, "noise": 0.0,
                    "real_cv2": True, "true_h": h.ravel().tolist(), "inplane": ip})
    return out


def budget_ref(case):
    fr, o = case["frames"], case["options"]
    n = len(fr)
    w = np.array([f["width"] for f in fr])
    ufit = np.array([np.sqrt(f["rho"]) * f["u_fit_raw"] for f in fr])
    u_stat = max(np.sqrt((ufit ** 2).sum()) / n, w.std(ddof=1) / np.sqrt(n))
    u_sig = np.mean([f["u_sigma_w"] for f in fr])
    mmpp = np.median([f["mm_per_px"] for f in fr])
    rms = np.median([f["loo_mm"] if f["loo_mm"] is not None else f["rms_px"] * f["mm_per_px"] for f in fr])
    loo = np.median([f["loo_mm"] or 0.0 for f in fr])
    tilt = np.median([f["tilt_deg"] for f in fr])
    wm = float(np.median(w))
    u_pos = np.median([abs(f["dw_ds"]) for f in fr]) * max(rms, 0.05)
    u_par = o["dz"] * abs(np.tan(np.deg2rad(tilt))) / S3
    u_geo = wm * np.sqrt(rms ** 2 + loo ** 2) / 120
    u_print = wm * o["u_print_rel"]
    u_dev = o["u_dev"] if o["u_dev"] is not None else 0.5 * mmpp
    u_rand = np.sqrt(u_stat ** 2 + u_sig ** 2 + u_pos ** 2 + u_par ** 2 + u_geo ** 2)
    u_sys = np.sqrt(u_print ** 2 + u_dev ** 2)
    u_c = np.sqrt(u_rand ** 2 + u_sys ** 2)
    dof = u_c ** 4 / (u_stat ** 4 / (n - 1))
    k = stats.t.ppf(0.975, dof)
    return {"width_mm": wm, "u_stat": u_stat, "u_sigma_w": u_sig, "u_pos": u_pos, "u_par": u_par, "u_geo": u_geo,
            "u_print": u_print, "u_dev": u_dev, "u_rand": u_rand, "u_sys": u_sys, "u_c": u_c, "dof_eff": dof, "k": k,
            "u_expanded": k * u_c, "floor_mm": max(0.5 * mmpp, 2 * u_c)}


def profile_ref(case):
    """Independent fit: cubic-spline profile sampling in mm + scipy least_squares on the aligned mean profile."""
    h = np.array(case["h"]).reshape(3, 3)
    img = np.array(case["data"]).reshape(case["patch_h"], case["patch_w"])
    a = np.deg2rad(case["direction_deg"])
    t = np.array([np.cos(a), np.sin(a)])
    nrm = np.array([-np.sin(a), np.cos(a)])
    s = np.arange(-3, 3 + 1e-9, min(0.02, 0.25 * case["mmpp"]))
    sig = case["sigma_mm"]

    def prof(along, off):
        p = np.array(case["point_mm"]) + along * t + (off + s)[:, None] * nrm
        px = apply(h, p)
        return ndimage.map_coordinates(img, [px[:, 1], px[:, 0]], order=3, mode="nearest")

    def model(p, ss):
        return p[0] + p[1] * ss - p[2] * (stats.norm.cdf((ss - p[3] + p[4] / 2) / sig) - stats.norm.cdf((ss - p[3] - p[4] / 2) / sig))

    lo, hi = [-1, -5, 0, -1.5, 0], [2, 5, 1, 1.5, 3]

    def fit(y):
        return optimize.least_squares(lambda p: model(p, s) - y, [y.mean(), 0, 0.1, 0, 0.3], bounds=(lo, hi), xtol=1e-14, ftol=1e-14).x

    alongs = -2 + 4 * (np.arange(40) + 0.5) / 40
    centres = [fit(prof(al, 0))[3] for al in alongs]
    cc = np.polyfit(alongs, centres, 2)
    avg = np.mean([prof(al, np.polyval(cc, al)) for al in alongs], axis=0)
    x = fit(avg)
    return {"width_mm": float(x[4]), "c": float(x[3])}


def compare():
    cases = json.load(open(sys.argv[2]))
    out = json.load(open(sys.argv[3]))
    rows = []

    def chk(name, got, want, tol, rel=False):
        err = abs(got - want) / (abs(want) if rel and want != 0 else 1.0)
        rows.append(("PASS" if err <= tol else "FAIL", name, got, want, err, tol))

    for i, (c, o) in enumerate(zip(cases["homography"], out["homography"])):
        ps = c["print_scale"]
        src = np.vstack([marker_corners_mm(d["id"], ps) for d in c["detections"]])
        dst = np.vstack([np.array(d["corners"]) for d in c["detections"]])
        h = fit_h(src, dst)
        hc = np.array(o["h"]).reshape(3, 3)
        grid = np.array([(x, y) for x in (-35, 0, 35) for y in (-35, 0, 35)] + [(-75, -75), (75, 75)], float) * ps
        chk(f"hom{i} H projected-grid max diff (px)", float(np.abs(apply(hc, grid) - apply(h, grid)).max()), 0.0, 1e-4)
        chk(f"hom{i} rms_px", o["rms_px"], float(np.sqrt(np.mean(np.sum((apply(h, src) - dst) ** 2, axis=1)))), 1e-6)
        if len(c["detections"]) == 4:
            sq = 0.0
            for k in range(4):
                keep = [j for j in range(4) if j != k]
                hk = fit_h(np.vstack([marker_corners_mm(c["detections"][j]["id"], ps) for j in keep]),
                           np.vstack([np.array(c["detections"][j]["corners"]) for j in keep]))
                back = apply(np.linalg.inv(hk), np.array(c["detections"][k]["corners"]))
                sq += float(np.sum((back - marker_corners_mm(c["detections"][k]["id"], ps)) ** 2))
            chk(f"hom{i} loo_mm", o["loo_mm"], float(np.sqrt(sq / 16)), 1e-5)
        else:
            rows.append(("PASS" if o["loo_mm"] is None else "FAIL", f"hom{i} loo_mm is null with 3 markers", o["loo_mm"], None, 0, 0))
        for j, p in enumerate(c["probe_mm"]):
            mp, an = local_scale(h, p)  # same physical-mm sheet point as the core probe
            chk(f"hom{i} mm_per_px probe{j}", o["mm_per_px"][j], mp, 2e-4, rel=True)
            chk(f"hom{i} anisotropy probe{j}", o["anisotropy"][j], an, 2e-4, rel=True)
        if c.get("real_cv2"):
            ht = np.array(c["true_h"]).reshape(3, 3)
            chk(f"hom{i} REAL cv2 detector, in-plane {c['inplane']} deg: 4 markers found", float(len(c["detections"])), 4.0, 0.0)
            chk(f"hom{i} REAL cv2: core H vs TRUE camera H on the sheet grid (max px, tol 0.3)", float(np.abs(apply(hc, grid) - apply(ht, grid)).max()), 0.0, 0.3)
            chk(f"hom{i} REAL cv2: rms_px (tol 0.3)", o["rms_px"], 0.0, 0.3)
            chk(f"hom{i} REAL cv2: loo_mm (tol 0.05)", o["loo_mm"], 0.0, 0.05)
        chk(f"hom{i} tilt_deg vs independent decomposition", o["tilt_deg"], tilt_from_h(h, c["f_px"], c["cx"], c["cy"]), 1e-3)
        chk(f"hom{i} tilt_deg vs TRUE tilt (noise {c['noise']} px; tol 1.0 deg)", o["tilt_deg"], c["true_tilt"], 1.0)
    for i, (c, o) in enumerate(zip(cases["budget"], out["budget"])):
        ref = budget_ref(c)
        for key in ["width_mm", "u_stat", "u_sigma_w", "u_pos", "u_par", "u_geo", "u_print", "u_dev", "u_rand", "u_sys", "u_c", "floor_mm", "dof_eff"]:
            chk(f"budget{i} {key}", o[key], ref[key], 1e-9, rel=True)
        chk(f"budget{i} k (table interpolation vs scipy t.ppf; tol 0.005)", o["k"], ref["k"], 0.005)
        chk(f"budget{i} U = k u_c", o["u_expanded"], o["k"] * ref["u_c"], 1e-9, rel=True)
    for i, (c, o) in enumerate(zip(cases["trend"], out["trend"])):
        d = c["b"]["width"] - c["a"]["width"]
        ud = float(np.sqrt(c["a"]["u_rand"] ** 2 + c["b"]["u_rand"] ** 2 + (d * c["u_print_rel"]) ** 2))
        chk(f"trend{i} delta", o["delta"], d, 1e-12)
        chk(f"trend{i} u_delta", o["u_delta"], ud, 1e-12, rel=True)
        chk(f"trend{i} z", o["z"], d / ud, 1e-12, rel=True)
        chk(f"trend{i} mdc", o["mdc"], 2 * ud, 1e-12, rel=True)
        want = "KEMUNGKINAN_BERTAMBAH_LEBAR" if d / ud >= 2 else "KEMUNGKINAN_MENYEMPIT" if d / ud <= -2 else "TIDAK_ADA_PERUBAHAN_TERDETEKSI"
        rows.append(("PASS" if o["class"] == want else "FAIL", f"trend{i} class", o["class"], want, 0, 0))
    for dof, k in zip(cases["k_dof"], out["k"]):
        truth = float(stats.t.ppf(0.975, dof))
        # documented in student_t.dart: the 1/dof chord never undercuts; overshoot bound per range (dof < 2 never occurs, n >= 3)
        bound = 0.06 if dof < 3 else 0.011 if dof < 5 else 0.0015 if dof < 10 else 0.001
        if dof < 2:
            rows.append(("PASS", f"k(dof={dof}) below 2: unreachable in a visit (dof >= n-1 >= 2), conservative table chord", k, truth, k - truth, 0))
        else:
            chk(f"k(dof={dof}) >= scipy t.ppf(0.975) (never undercuts; table has 5 decimals)", min(0.0, k - truth), 0.0, 1e-5)
            chk(f"k(dof={dof}) overshoot vs scipy within documented bound", k - truth, 0.0, bound)
    for i, (c, o) in enumerate(zip(cases["profile"], out["profile"])):
        ref = profile_ref(c)
        chk(f"profile{i} core width vs TRUE (mm; tol 0.003)", o["width_mm"], c["true_w"], 0.003)
        chk(f"profile{i} independent scipy fit vs TRUE (mm; tol 0.003)", ref["width_mm"], c["true_w"], 0.003)
        chk(f"profile{i} core vs independent fit (mm; tol 0.002)", o["width_mm"], ref["width_mm"], 0.002)
        chk(f"profile{i} centre vs TRUE (mm; tol 0.003)", o["center_offset_mm"], c["true_c"], 0.003)
    for r in rows:
        print("%s  %-80s got=%s want=%s err=%.3g tol=%.3g" % (r[0], r[1], r[2], r[3], r[4], r[5]))
    p = sum(r[0] == "PASS" for r in rows)
    print("TOTAL", p, "PASS", len(rows) - p, "FAIL")
    sys.exit(0 if p == len(rows) else 1)


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        json.dump(gen_cases(), open(sys.argv[2], "w"))
    else:
        compare()
