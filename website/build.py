#!/usr/bin/env python3
"""Builds the Hush website into website/dist: one HTML template, one strings file per language.

    python3 website/build.py            # SITE_URL defaults to the production address
    SITE_URL=http://localhost:8000 python3 website/build.py
"""
import html
import json
import os
import re
import shutil
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
SRC = ROOT / "src"
DIST = ROOT / "dist"
SITE = os.environ.get("SITE_URL", "https://hushpass.fyi").rstrip("/")
REPO_URL = "https://github.com/08820048/hush"

# The published release the download button points at. CI passes the latest GitHub release
# (HUSH_VERSION), so the site never links to a release that is still being built.
version = os.environ.get("HUSH_VERSION", "").lstrip("v") or re.search(
    r"^\s+MARKETING_VERSION:\s*(\S+)", (REPO / "App/project.yml").read_text(), re.M
).group(1)
common = {
    "site": SITE,
    "repo": REPO_URL,
    "version": version,
    "download_url": f"{REPO_URL}/releases/latest/download/Hush-{version}.zip",
    "build": str(int(time.time())),
}

template = (SRC / "index.html").read_text()
keys = set(re.findall(r"{{(\w+)}}", template))

shutil.rmtree(DIST, ignore_errors=True)
shutil.copytree(SRC / "assets", DIST / "assets")
for name in ("styles.css", "demo.js"):
    shutil.copy(SRC / name, DIST / name)

for strings_file in sorted((SRC / "strings").glob("*.json")):
    values = {**common, **json.loads(strings_file.read_text())}
    missing = keys - values.keys()
    if missing:
        raise SystemExit(f"{strings_file.name}: missing {sorted(missing)}")
    # Values may contain <br> and links; attributes get escaped versions.
    page = template
    for key in keys:
        value = values[key]
        page = re.sub(r'(=")({{%s}})' % key, lambda m: m.group(1) + html.escape(re.sub("<[^>]+>", " ", value), quote=True), page)
        page = page.replace("{{%s}}" % key, value)
    out = DIST / values["path"].strip("/") / "index.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(page)
    print(f"{out.relative_to(ROOT)}  ({strings_file.stem}, v{version})")

# Cloudflare Pages: security headers and caching. Everything is first-party, so the policy is strict.
(DIST / "_headers").write_text("""/*
  Content-Security-Policy: default-src 'none'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'
  Referrer-Policy: no-referrer
  X-Content-Type-Options: nosniff
  Permissions-Policy: interest-cohort=()
/assets/*
  Cache-Control: public, max-age=604800
""")
(DIST / "404.html").write_text('<!doctype html><meta charset="utf-8"><meta http-equiv="refresh" content="0; url=/"><title>Hush</title><a href="/">Hush</a>\n')
(DIST / "robots.txt").write_text(f"User-agent: *\nAllow: /\nSitemap: {SITE}/sitemap.xml\n")
(DIST / "sitemap.xml").write_text(
    '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
    f"  <url><loc>{SITE}/</loc></url>\n  <url><loc>{SITE}/en/</loc></url>\n</urlset>\n"
)
