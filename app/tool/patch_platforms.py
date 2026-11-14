"""Run once after `flutter create` (and again after updates):  python tool\\patch_platforms.py

* Android: app name, internet + location permissions, https link query (url_launcher),
  minSdk >= 23 (Firebase), launcher icons.
Safe to run again - every step checks before changing anything.
"""
from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

APP = Path(__file__).resolve().parents[1]
LABEL = "Kuch Toh Gadbad Hai"
PERMS = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.ACCESS_FINE_LOCATION",
]
HTTPS_QUERY = (
    '        <intent>\n'
    '            <action android:name="android.intent.action.VIEW" />\n'
    '            <data android:scheme="https" />\n'
    '        </intent>\n'
)


def patch_manifest() -> None:
    p = APP / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    if not p.exists():
        print("  ! AndroidManifest.xml not found - run `flutter create --platforms=android,web .` first")
        return
    s = p.read_text(encoding="utf-8")
    orig = s
    s = re.sub(r'android:label="[^"]*"', f'android:label="{LABEL}"', s, count=1)
    for perm in PERMS:
        if perm not in s:
            s = s.replace("<application", f'<uses-permission android:name="{perm}" />\n    <application', 1)
    if 'android:scheme="https"' not in s:
        if "<queries>" in s:
            s = s.replace("<queries>", "<queries>\n" + HTTPS_QUERY, 1)
        else:
            s = s.replace("</manifest>", "    <queries>\n" + HTTPS_QUERY + "    </queries>\n</manifest>", 1)
    if s != orig:
        p.write_text(s, encoding="utf-8")
        print("  patched AndroidManifest.xml (label, permissions, https query)")
    else:
        print("  AndroidManifest.xml already patched")


def patch_debug_cleartext() -> None:
    """Debug/profile builds may read live data from the laptop (http://<laptop-ip>:8090). Release stays https-only."""
    for flavour in ("debug", "profile"):
        p = APP / "android" / "app" / "src" / flavour / "AndroidManifest.xml"
        if not p.exists():
            continue
        s = p.read_text(encoding="utf-8")
        if "usesCleartextTraffic" in s:
            print(f"  {flavour} manifest already allows laptop data")
            continue
        if "<application" in s:
            s = s.replace("<application", '<application android:usesCleartextTraffic="true"', 1)
        else:
            s = s.replace("</manifest>", '    <application android:usesCleartextTraffic="true" />\n</manifest>', 1)
        p.write_text(s, encoding="utf-8")
        print(f"  patched {flavour} manifest (live data from laptop allowed)")


def patch_min_sdk() -> None:
    for name in ("build.gradle.kts", "build.gradle"):
        p = APP / "android" / "app" / name
        if not p.exists():
            continue
        s = p.read_text(encoding="utf-8")
        orig = s
        if name.endswith(".kts"):
            s = s.replace("minSdk = flutter.minSdkVersion", "minSdk = maxOf(flutter.minSdkVersion, 23)")
        else:
            s = s.replace("minSdkVersion flutter.minSdkVersion", "minSdkVersion Math.max(flutter.minSdkVersion, 23)")
            s = s.replace("minSdk = flutter.minSdkVersion", "minSdk = Math.max(flutter.minSdkVersion, 23)")
        if s != orig:
            p.write_text(s, encoding="utf-8")
            print(f"  patched {name} (minSdk >= 23 for Firebase)")
        else:
            print(f"  {name}: minSdk left as is")
        return


def copy_icons() -> None:
    res = APP / "android" / "app" / "src" / "main" / "res"
    src = APP / "tool" / "icons"
    if not res.exists():
        return
    n = 0
    for dens in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
        f = src / f"mipmap-{dens}.png"
        d = res / f"mipmap-{dens}"
        if f.exists() and d.exists():
            shutil.copyfile(f, d / "ic_launcher.png")
            n += 1
    print(f"  launcher icons copied ({n} sizes)")


def main() -> int:
    print("Patching platform folders ...")
    patch_manifest()
    patch_debug_cleartext()
    patch_min_sdk()
    copy_icons()
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
