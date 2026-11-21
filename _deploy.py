#!/usr/bin/env python3
"""部署 decks/ 去 Vercel（pipeline-decks / pipeline-ppt.vercel.app）。
用法：python3 decks/_deploy.py
上 html + md + assets/ 圖片（base64），跳過 goman-1117 嘅大圖；需要 $DSH_SECRET_VERCEL_TOKEN。
"""
import json, os, sys, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.abspath(__file__))
DECKS = ["one-video-pipeline", "ai-pipeline-flow", "material-to-content", "replace-paid-tools",
         "event-pipeline", "platform-features", "content-pipeline-text", "youtube-pipeline-flow", "one-person-army", "text-deck"]

paths = ["index.html", "intro.html", "play.html", "copy.html", "presentation.html", "vercel.json"]
ASSETS = os.path.join(ROOT, "assets")
for f in sorted(os.listdir(ASSETS)) if os.path.isdir(ASSETS) else []:
    paths.append(os.path.join("assets", f))
for d in DECKS:
    for f in sorted(os.listdir(os.path.join(ROOT, d))):
        if f.endswith(".html") or f.endswith(".md"):
            paths.append(os.path.join(d, f))

files = []
for p in paths:
    fp = os.path.join(ROOT, p)
    if not os.path.exists(fp):
        sys.exit("MISSING " + p)
    if p.startswith("assets/"):
        import base64
        files.append({"file": p, "data": base64.b64encode(open(fp, "rb").read()).decode(), "encoding": "base64"})
    else:
        files.append({"file": p, "data": open(fp, encoding="utf-8").read()})

print("files:", len(files), "bytes:", sum(len(f["data"]) for f in files))
body = json.dumps({"name": "pipeline-decks", "files": files, "target": "production",
                   "projectSettings": {"framework": None, "buildCommand": None,
                                       "outputDirectory": None}}).encode()
req = urllib.request.Request(
    "https://api.vercel.com/v13/deployments?forceNew=1", data=body,
    headers={"Authorization": "Bearer " + os.environ["DSH_SECRET_VERCEL_TOKEN"],
             "Content-Type": "application/json"})
try:
    out = json.load(urllib.request.urlopen(req, timeout=180))
    print("OK", out.get("id"), out.get("url"), out.get("readyState"))
except urllib.error.HTTPError as e:
    sys.exit("HTTP %s %s" % (e.code, e.read().decode()[:1500]))
