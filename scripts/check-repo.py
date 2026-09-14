#!/usr/bin/env python3
"""Check repository structure without reading browser data or requiring packages."""
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit

root = Path(__file__).resolve().parent.parent
paths = subprocess.check_output(
    ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=root
).decode().split("\0")
errors = []
link = root / "CLAUDE.md"
if not link.is_symlink() or str(link.readlink()) != "AGENTS.md":
    errors.append("CLAUDE.md must be a relative symlink to AGENTS.md")
for name in sorted(set(filter(None, paths))):
    path = root / name
    if not path.exists():
        continue  # An unstaged deletion; Git handles it at commit time.
    if path.suffix in {".p12", ".p8", ".key", ".dmg", ".mobileprovision"} or ".app/" in name:
        errors.append(f"Distribution or signing artifact must not be tracked: {name}")
    if path.name.startswith(".env") or path.name in {"destination.json", "Preferences", "Local State", "Cookies", "History"}:
        errors.append(f"Local configuration or browser data must not be tracked: {name}")
    if path.suffix == ".sh":
        if subprocess.run(["bash", "-n", str(path)]).returncode:
            errors.append(f"Invalid shell syntax: {name}")
    if path.suffix != ".md" or path.is_symlink():
        continue
    content = re.sub(r"```.*?```", "", path.read_text(), flags=re.S)
    for target in re.findall(r"\[[^\]]*\]\(([^)]+)\)", content):
        target = target.strip().strip("<>")
        parsed = urlsplit(target)
        if parsed.scheme or not parsed.path:
            continue
        if not (path.parent / unquote(parsed.path)).exists():
            errors.append(f"Broken relative link in {name}: {target}")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print("Repository checks passed: links, instruction symlink, shell syntax, file hygiene")
