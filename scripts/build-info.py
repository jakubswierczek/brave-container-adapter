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
if package["dependencies"]:
    sys.exit("Update the release dependency inventory before adding external packages.")
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
    "externalSwiftDependencies": [],
    "runtimeDependencies": "Apple system frameworks and Swift runtime",
    "byteReproducible": False,
}
Path(sys.argv[1]).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
