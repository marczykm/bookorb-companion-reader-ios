#!/usr/bin/env python3
"""Writes altstore/apps.json (an AltStore source) for the IPA in build/BookOrb.ipa.

Usage: scripts/update-altstore-source.py OWNER/REPO [release-tag]

The IPA is expected as a release asset of the GitHub repository, e.g. at
https://github.com/OWNER/REPO/releases/download/v0.1.0/BookOrb.ipa
Existing versions in apps.json are kept, newest first.
"""
import datetime, json, os, plistlib, subprocess, sys, tempfile, zipfile

repo = sys.argv[1]
# Entitlements embedded in the IPA (see CompanionReader/CompanionReader.entitlements).
ENTITLEMENTS = ["com.apple.security.application-groups"]
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ipa = os.path.join(root, "build", "BookOrb.ipa")
out = os.path.join(root, "altstore", "apps.json")

with zipfile.ZipFile(ipa) as z:
    plist = plistlib.loads(z.read("Payload/CompanionReader.app/Info.plist"))
version, build = plist["CFBundleShortVersionString"], plist["CFBundleVersion"]
tag = sys.argv[2] if len(sys.argv) > 2 else f"v{version}"
raw = f"https://raw.githubusercontent.com/{repo}/main"

entry = {
    "version": version,
    "buildVersion": build,
    "date": datetime.date.today().isoformat(),
    "downloadURL": f"https://github.com/{repo}/releases/download/{tag}/BookOrb.ipa",
    "size": os.path.getsize(ipa),
    "minOSVersion": plist.get("MinimumOSVersion", "17.0"),
    "localizedDescription": "See the release notes on GitHub.",
}

old = json.load(open(out)) if os.path.exists(out) else None
versions = [v for v in (old["apps"][0]["versions"] if old else []) if v["version"] != version or v["buildVersion"] != build]

source = {
    "name": "BookOrb",
    "identifier": "app.bookorb.companion.source",
    "subtitle": "Unofficial companion app for BookOrbit",
    "description": "An unofficial iOS reader for a self-hosted BookOrbit server. Not affiliated with the BookOrbit project.",
    "iconURL": f"{raw}/CompanionReader/Sources/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
    "website": f"https://github.com/{repo}",
    "tintColor": "6750A4",
    "apps": [{
        "name": "BookOrb: Unofficial Companion App",
        "bundleIdentifier": "app.bookorb.companion.reader.ios",
        "developerName": "marcin",
        "subtitle": "Read and sync books from your BookOrbit server",
        "localizedDescription": (
            "An unofficial iOS companion reader for a self-hosted BookOrbit server. Library and Browse, an EPUB reader with "
            "highlights and progress sync, a reading companion, offline reading and Home Screen widgets.\n\n"
            "Not affiliated with or endorsed by the BookOrbit project. Free software under AGPL-3.0 with additional terms."),
        "iconURL": f"{raw}/CompanionReader/Sources/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
        "tintColor": "6750A4",
        "category": "other",
        "screenshots": [],
        "versions": [entry] + versions,
        # AltStore refuses apps whose IPA has entitlements the source does not declare.
        "appPermissions": {"entitlements": ENTITLEMENTS, "privacy": {}},
    }],
    "news": [],
}
os.makedirs(os.path.dirname(out), exist_ok=True)
json.dump(source, open(out, "w"), indent=2)
print(f"Wrote {out}\nSource URL for AltStore: {raw}/altstore/apps.json")
