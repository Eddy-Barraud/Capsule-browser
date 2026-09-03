#!/usr/bin/env python3
"""
update_rulesets.py
Capsule Browser / isowebapps

Updates the uBlock Origin Lite submodule (shared/uBOL-home), extracts only the 8
necessary ruleset files used by the application into `isowebapps/rulesets/main/`,
and sanitizes all entries to comply with Apple App Store and U.S. OFAC export sanctions
by removing references to embargoed territories (.ir, .cu, .sy, .kp).
"""

import os
import sys
import json
import re
import subprocess
from pathlib import Path

# Paths
REPO_ROOT = Path(__file__).resolve().parent.parent
SUBMODULE_DIR = REPO_ROOT / "shared" / "uBOL-home"
SOURCE_RULESETS_DIR = SUBMODULE_DIR / "chromium" / "rulesets" / "main"
DEST_RULESETS_DIR = REPO_ROOT / "isowebapps" / "rulesets" / "main"

# The 8 target rulesets actively loaded by UBlockOriginExtensionManager
TARGET_RULESET_FILES = [
    "ublock-filters.json",
    "ublock-badware.json",
    "easylist.json",
    "easyprivacy.json",
    "urlhaus-full.json",
    "annoyances-cookies.json",
    "annoyances-overlays.json",
    "block-lan.json"
]

# Regex to match embargoed TLDs: Iran (.ir), Cuba (.cu), Syria (.sy), North Korea (.kp)
EMBARGO_REGEX = re.compile(r'(\.ir|\.cu|\.sy|\.kp)([:/\'"\s,\?&]|$)', re.IGNORECASE)


def run_command(cmd, cwd=None):
    """Executes a shell command and prints output."""
    print(f"==> Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True)
    if result.returncode != 0:
        print(f"Error (exit code {result.returncode}):\n{result.stderr}", file=sys.stderr)
        raise RuntimeError(f"Command failed: {' '.join(cmd)}")
    if result.stdout.strip():
        print(result.stdout.strip())
    return result.stdout


def update_git_submodule():
    """Updates git submodule to latest remote revision."""
    print("\n[Step 1/4] Updating git submodule 'shared/uBOL-home'...")
    try:
        run_command(["git", "submodule", "update", "--init", "--recursive", "--remote", "shared/uBOL-home"], cwd=REPO_ROOT)
        print("Submodule updated successfully.")
    except Exception as e:
        print(f"Warning updating submodule: {e}")
        print("Continuing with existing submodule files...")


def is_embargoed(text: str) -> bool:
    """Checks if a string contains an embargoed domain/link."""
    return bool(EMBARGO_REGEX.search(text))


def sanitize_rule_condition(condition: dict) -> tuple[dict | None, int]:
    """
    Sanitizes condition dictionaries in Declarative Net Request rules.
    Returns (sanitized_condition, count_of_domains_removed).
    If urlFilter itself points directly to an embargoed domain, returns (None, 1).
    """
    domains_removed = 0

    # 1. Check if urlFilter targets an embargoed domain directly
    url_filter = condition.get("urlFilter")
    if isinstance(url_filter, str) and is_embargoed(url_filter):
        return None, 1

    # 2. Filter domain lists in-place
    domain_keys = ["requestDomains", "initiatorDomains", "excludedRequestDomains", "excludedInitiatorDomains"]
    for key in domain_keys:
        if key in condition and isinstance(condition[key], list):
            original_len = len(condition[key])
            condition[key] = [d for d in condition[key] if not is_embargoed(d)]
            domains_removed += (original_len - len(condition[key]))

    return condition, domains_removed


def copy_and_sanitize_rulesets():
    """Copies and sanitizes the 8 target ruleset files."""
    print(f"\n[Step 2/4] Sanitizing and copying rulesets to {DEST_RULESETS_DIR}...")

    if not SOURCE_RULESETS_DIR.exists():
        raise FileNotFoundError(f"Source rulesets folder not found: {SOURCE_RULESETS_DIR}")

    DEST_RULESETS_DIR.mkdir(parents=True, exist_ok=True)

    total_rules_in = 0
    total_rules_out = 0
    total_domains_dropped = 0
    total_rules_dropped = 0

    for filename in TARGET_RULESET_FILES:
        src_file = SOURCE_RULESETS_DIR / filename
        dst_file = DEST_RULESETS_DIR / filename

        if not src_file.exists():
            print(f"Warning: {src_file} does not exist. Skipping.", file=sys.stderr)
            continue

        with open(src_file, "r", encoding="utf-8") as f:
            data = json.load(f)

        rules_in = len(data) if isinstance(data, list) else 1
        total_rules_in += rules_in

        file_rules_dropped = 0
        file_domains_dropped = 0

        if isinstance(data, list):
            sanitized_list = []
            for item in data:
                if isinstance(item, dict) and "condition" in item:
                    cond, dropped_domains = sanitize_rule_condition(item["condition"])
                    file_domains_dropped += dropped_domains
                    if cond is not None:
                        item["condition"] = cond
                        sanitized_list.append(item)
                    else:
                        file_rules_dropped += 1
                else:
                    sanitized_list.append(item)
            data = sanitized_list

        rules_out = len(data) if isinstance(data, list) else 1
        total_rules_out += rules_out
        total_rules_dropped += file_rules_dropped
        total_domains_dropped += file_domains_dropped

        # Write minified JSON
        with open(dst_file, "w", encoding="utf-8") as f:
            json.dump(data, f, separators=(",", ":"))

        print(
            f"  - {filename:24} : {rules_in} rules -> {rules_out} rules "
            f"({file_rules_dropped} embargoed rules dropped, {file_domains_dropped} domains filtered)"
        )

    print(
        f"\nSanitization summary: {total_rules_in} rules processed, "
        f"{total_rules_dropped} rules dropped, {total_domains_dropped} domains removed."
    )


def verify_sanitization():
    """Double checks the destination directory to verify 0 embargoed domains remain."""
    print("\n[Step 3/4] Verifying destination rulesets for embargoed patterns...")
    violations = []

    for path in DEST_RULESETS_DIR.glob("*.json"):
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
            matches = EMBARGO_REGEX.findall(content)
            if matches:
                violations.append((path.name, matches))

    if violations:
        print("ERROR: Embargoed patterns detected after sanitization!", file=sys.stderr)
        for name, m in violations:
            print(f"  {name}: {m[:5]}", file=sys.stderr)
        sys.exit(1)
    else:
        print("Verification PASSED: 0 embargoed domains or URLs found in rulesets.")


def print_completion():
    print("\n[Step 4/4] Done! The rulesets in 'isowebapps/rulesets/main/' are updated and App Store compliant.")


def main():
    try:
        update_git_submodule()
        copy_and_sanitize_rulesets()
        verify_sanitization()
        print_completion()
    except Exception as err:
        print(f"\nFATAL ERROR: {err}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

