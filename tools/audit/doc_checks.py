# Copyright (c) 2026 Vassel Goleyu. MIT License.
"""Text rules of CLAUDE.md checked over the repository (Phase 9 audit). Exit code 1 on any hit.

1. No em dash (U+2014) anywhere in tracked text.
2. The words "aman" and "tidak berbahaya" never appear in the app text, the README or the docs
   (CLAUDE.md quotes them as forbidden, tests contain them as negative assertions: both skipped).
3. An accuracy-like number (um, or a percent next to coverage/error/accuracy) in README or docs has a
   SINTETIS / SYNTHETIC / PERANGKAT / DEVICE / NOMINAL / SIMULASI label within 6 lines.
Usage: python3 tools/audit/doc_checks.py   (from the repository root)
"""
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[2]
tracked = subprocess.run(["git", "ls-files"], cwd=root, capture_output=True, text=True, check=True).stdout.split()
text_ext = {".dart", ".md", ".yaml", ".yml", ".kt", ".py", ".sh", ".xml", ".gradle", ".kts", ".csv", ".txt"}
files = [root / f for f in tracked if pathlib.Path(f).suffix in text_ext and "pubspec.lock" not in f]
bad = []

for f in files:
    for n, line in enumerate(f.read_text(errors="ignore").split("\n"), 1):
        if "—" in line:
            bad.append(f"{f.relative_to(root)}:{n}: em dash")

forbidden = re.compile(r"\b(aman|tidak berbahaya)\b", re.I)
for f in files:
    rel = str(f.relative_to(root))
    if rel == "CLAUDE.md" or "/test/" in rel or rel.startswith("tools/audit/"):
        continue
    if not (rel.startswith("app/lib") or rel.endswith(".md")):
        continue
    for n, line in enumerate(f.read_text(errors="ignore").split("\n"), 1):
        if forbidden.search(line):
            bad.append(f"{rel}:{n}: forbidden word: {line.strip()[:100]}")

label = re.compile(r"SINTETIS|SYNTHETIC|PERANGKAT|DEVICE|NOMINAL|SIMULASI", re.I)
number = re.compile(
    r"\d+[.,]?\d*\s*(um|µm)\b"
    r"|\d+[.,]?\d*\s*(persen|percent|%)[^.]{0,40}(cakupan|coverage|galat|error|akurasi|accuracy)"
    r"|(cakupan|coverage|galat|error|akurasi|accuracy)[^.]{0,40}\d+[.,]?\d*\s*(persen|percent|%)",
    re.I,
)
for f in files:
    rel = str(f.relative_to(root))
    if f.suffix != ".md" or rel == "CLAUDE.md":
        continue
    lines = f.read_text(errors="ignore").split("\n")
    if rel in ("docs/SYNTHETIC_VALIDATION.md", "docs/MEASUREMENT_NOTES.md") and label.search(" ".join(lines[:12])):
        continue  # whole document is labelled in its header
    for i, line in enumerate(lines):
        if number.search(line) and not label.search(" ".join(lines[max(0, i - 6): i + 7])):
            bad.append(f"{rel}:{i + 1}: accuracy-like number without a label: {line.strip()[:100]}")

print("\n".join(bad) if bad else f"OK: {len(files)} files, no em dash, no forbidden word, every accuracy-like number labelled")
sys.exit(1 if bad else 0)
