#!/usr/bin/env python3
"""Renders Mac App Store screenshots (2880×1800) in English and Simplified Chinese.

The slides reuse the website's styles, strings and UI blocks (extracted from
website/src/index.html), so the screenshots always match the site and the app.

    python3 scripts/appstore-screenshots.py      # → marketing/appstore/screenshots/{en,zh-Hans}/
Needs Google Chrome (set CHROME to another Chromium binary if needed).
"""
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SITE = REPO / "website" / "src"
HERE = REPO / "marketing" / "appstore"
OUT = HERE / "screenshots"
CHROME = os.environ.get("CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
NAMES = ["01-panel", "02-menu-bar", "03-modes", "04-after-copy", "05-privacy"]
LANGS = {"en": "en", "zh": "zh-Hans"}


def element(html: str, opening: str) -> str:
    """The full element that starts with `opening`, matching nested <div>s."""
    start = html.index(opening)
    depth, i = 0, start
    for m in re.finditer(r"<div\b|</div>", html[start:]):
        depth += 1 if m.group() == "<div" else -1
        if depth == 0:
            return html[start:start + m.end()]
    raise ValueError(opening)


def inner(html: str, opening: str) -> str:
    whole = element(html, opening)
    return whole[whole.index(">") + 1:whole.rindex("</div>")]


site_template = (SITE / "index.html").read_text()
# The App Store build has no direct paste, so its screenshots must not show the ⌘↩ hint.
APP_STORE_ONLY = [('<span class="hint"><kbd>⌘↩</kbd>{{paste_into}}</span>', "")]


def for_app_store(fragment: str) -> str:
    for old, new in APP_STORE_ONLY:
        fragment = fragment.replace(old, new)
    return fragment


blocks = {
    "block_hero_visual": for_app_store(inner(site_template, '<div class="hero-visual"')),
    "block_quick": element(site_template, '<div class="quick">'),
    "block_modes": element(site_template, '<div class="grid-5">'),
    "block_features": element(site_template, '<div class="grid-3">'),
    "block_privacy": element(site_template, '<div class="grid-4">'),
}
slides_template = (HERE / "slides.html").read_text()
head, body = slides_template.split("<body>", 1)
sections = re.findall(r"<section.*?</section>", body, re.S)
assert len(sections) == len(NAMES), "slide count"

version = re.search(r"^\s+MARKETING_VERSION:\s*(\S+)", (REPO / "App/project.yml").read_text(), re.M).group(1)
common = {"version": version, "build": "0", "site": "", "repo": "https://github.com/08820048/hush", "download_url": "#"}


def fill(text: str, values: dict) -> str:
    for _ in range(3):  # blocks contain placeholders themselves
        text = re.sub(r"{{(\w+)}}", lambda m: values.get(m.group(1), m.group(0)), text)
    left = re.findall(r"{{(\w+)}}", text)
    if left:
        raise SystemExit(f"unfilled: {sorted(set(left))}")
    return text


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    shutil.copytree(SITE / "assets", root / "assets")
    shutil.copy(SITE / "styles.css", root / "styles.css")
    for short, lang in LANGS.items():
        values = {**common, **json.loads((SITE / "strings" / f"{short}.json").read_text()),
                  **json.loads((HERE / "strings" / f"{short}.json").read_text()), **blocks}
        (OUT / lang).mkdir(parents=True, exist_ok=True)
        for name, section in zip(NAMES, sections):
            page = fill(f"{head}<body style=\"margin:0\">{section}</body></html>", values)
            assert "⌘↩" not in page, f"{name}: App Store screenshots must not show direct paste"
            # Root-relative asset paths → files next to the page.
            page = page.replace('href="/', 'href="').replace('src="/', 'src="')
            html_file = root / f"{lang}-{name}.html"
            html_file.write_text(page)
            png = OUT / lang / f"{name}.png"
            profile = root / "chrome-profile"
            subprocess.run([
                CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                f"--user-data-dir={profile}", "--force-device-scale-factor=2",
                "--blink-settings=preferredColorScheme=1", "--window-size=1440,900",
                "--allow-file-access-from-files", f"--screenshot={png}", html_file.as_uri(),
            ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            size = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(png)], capture_output=True, text=True).stdout.split()
            print(f"{png.relative_to(REPO)}  {size[-3]}×{size[-1]}")
