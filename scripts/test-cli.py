#!/usr/bin/env python3
"""Exercise the real CLI against synthetic files; never uses user browser data."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--bin-dir", type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parent.parent

with tempfile.TemporaryDirectory(prefix="cbc-cli-test-") as temporary:
    root = Path(temporary)
    for name in ["cbc", "ContainerReceiver"]:
        shutil.copy2(args.bin_dir / name, root / name)
    browser = root / "Brave Browser.app"
    (browser / "Contents/MacOS").mkdir(parents=True)
    shutil.copyfile("/usr/bin/true", browser / "Contents/MacOS/Brave Browser")
    (browser / "Contents/MacOS/Brave Browser").chmod(0o755)
    (browser / "Contents/Info.plist").write_bytes(plistlib.dumps({
        "CFBundleExecutable": "Brave Browser", "CFBundleShortVersionString": "153.1.95.101",
    }))
    data = root / "data"
    (data / "Default").mkdir(parents=True)
    fixtures = repo / "Tests/BraveDestinationsTests/Fixtures"
    (data / "Local State").write_text(json.dumps({"profile": {"info_cache": {"Default": {"name": "Test profile"}}}}))
    shutil.copy2(fixtures / "Preferences.json", data / "Default/Preferences")
    before = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [data / "Local State", data / "Default/Preferences"]}
    paths = ["--brave", str(browser), "--user-data-dir", str(data)]

    def run(arguments, success=True):
        result = subprocess.run([str(root / "cbc"), *arguments], capture_output=True, text=True, timeout=30)
        assert (result.returncode == 0) == success, result.stderr
        return result.stdout + result.stderr

    version, build = run(["version"]).split()
    listing = run(["list", *paths])
    assert "Default" in listing and "Test profile" in listing and "test-work" in listing
    assert "test-retained" not in listing
    run(["doctor", *paths, "--profile", "Default", "--temporary"])
    for arguments in [
        ["list", "--name", "ignored"], ["doctor", "--all"],
        ["generate", "--all"], ["install", "--all", "--name", "ignored"],
        ["list", "--profile", "Default", "--profile", "Default"],
        ["doctor", "--app", str(root / "missing.app"), "--profile", "Default"],
        ["version", "--icon", "work"], ["install", "--output", str(root / "unexpected")],
    ]:
        run(arguments, success=False)
    assert not (root / "unexpected").exists()
    output = root / "apps"
    generation = ["generate", *paths, "--profile", "Default", "--container-id", "test-work", "--output", str(output)]
    app = Path(run([*generation, "--name", "Work", "--icon", "work"]).strip())
    original_info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert original_info["CFBundleShortVersionString"] == version and original_info["CFBundleVersion"] == build
    # Omitted appearance options preserve the existing label and installed path.
    assert Path(run(generation).strip()) == app
    renamed = Path(run(["customize", "--app", str(app), "--name", "Renamed", "--icon", "personal"]).strip())
    assert not app.exists() and renamed.exists()
    assert plistlib.loads((renamed / "Contents/Info.plist").read_bytes())["CFBundleIdentifier"] == original_info["CFBundleIdentifier"]
    run(["doctor", "--app", str(renamed)])
    subprocess.run(["codesign", "--verify", "--strict", str(renamed)], check=True)
    # Remove only this test app's Launch Services registration.
    subprocess.run(["/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", "-u", str(renamed)], check=True)
    after = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [data / "Local State", data / "Default/Preferences"]}
    assert before == after, "CLI changed browser metadata"
    (data / "Default/Preferences").write_text("{ synthetic_private_value_DO_NOT_LOG")
    error = run(["list", *paths], success=False)
    assert "synthetic_private_value_DO_NOT_LOG" not in error
print("CLI checks passed: discovery, validation, generation, customization, signatures, read-only data and redacted errors")
