#!/usr/bin/env python3
"""Write public-safe build provenance. Never serialize the host environment."""
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
if "DEVELOPER_DIR" not in os.environ and Path("/Applications/Xcode.app/Contents/Developer").is_dir():
    os.environ["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
    # Apple's Python launcher may have selected the Command Line Tools SDK first.
    os.environ.pop("SDKROOT", None)


def output(*args):
    return subprocess.check_output(args, cwd=root, text=True).strip()


if len(sys.argv) != 2:
    sys.exit("Usage: scripts/build-info.py OUTPUT.json")
package = json.loads(output("xcrun", "swift", "package", "dump-package"))
pins = json.loads((root / "Package.resolved").read_text())["pins"]
expected = [{"sourceControl": [{
    "identity": "sparkle",
    "location": {"remote": [{"urlString": "https://github.com/sparkle-project/Sparkle"}]},
    "requirement": {"exact": ["2.10.0"]},
}]}]
# Ignore SwiftPM presentation fields, but reject undeclared or changed dependencies.
if len(package["dependencies"]) != 1 or len(pins) != 1:
    sys.exit("Update the release dependency inventory for changed dependencies.")
actual = package["dependencies"][0].get("sourceControl", [{}])[0]
for field, value in expected[0]["sourceControl"][0].items():
    if actual.get(field) != value:
        sys.exit("Unexpected dependency declaration: " + field)
pin = pins[0]
if (pin["identity"], pin["location"], pin["state"]) != (
    "sparkle", "https://github.com/sparkle-project/Sparkle",
    {"revision": "eef1a539a373c1f1a320624b1130fc5de7b2e100", "version": "2.10.0"},
):
    sys.exit("Unexpected Sparkle lockfile pin.")
artifact_checksum = "17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959"
manifest = {
    "schemaVersion": 1,
    "sourceRepository": "https://github.com/jakubswierczek/brave-container-adapter",
    "sourceCommit": output("git", "rev-parse", "HEAD"),
    "sourceTree": output("git", "rev-parse", "HEAD^{tree}"),
    "uncommittedChanges": bool(output("git", "status", "--porcelain")),
    "xcode": output("xcodebuild", "-version").splitlines(),
    "swift": output("xcrun", "swift", "--version").splitlines(),
    "buildOS": output("sw_vers", "-productVersion"),
    "buildOSVersion": output("sw_vers", "-buildVersion"),
    "minimumMacOS": "14.0",
    "architectures": ["arm64", "x86_64"],
    "externalSwiftDependencies": [{
        "name": "Sparkle", "version": pin["state"]["version"],
        "revision": pin["state"]["revision"], "repository": pin["location"],
        "binaryArtifactSHA256": artifact_checksum,
        "license": "MIT (see Sparkle-LICENSE for bundled third-party notices)",
        "linkedProducts": ["ContainerSetup"],
    }],
    "runtimeDependencies": "Apple system frameworks, Swift runtime and bundled Sparkle framework/helpers",
    "byteReproducible": False,
}
Path(sys.argv[1]).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
