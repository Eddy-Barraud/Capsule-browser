#!/usr/bin/env python3
"""
update_rulesets.py
Capsule Browser / isowebapps

Updates the uBlock Origin Lite submodule (shared/uBOL-home), extracts:
1. Declarative Net Request rulesets into `isowebapps/rulesets/main/`
2. MAIN and ISOLATED world scriptlet files into `isowebapps/rulesets/scripting/`
3. Specific cosmetic CSS rules compiled into self-contained scripts in `isowebapps/rulesets/scripting/`

Sanitizes all entries to comply with Apple App Store guidelines and U.S. OFAC export sanctions
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
SOURCE_SCRIPTING_DIR = SUBMODULE_DIR / "chromium" / "rulesets" / "scripting"
DEST_RULESETS_DIR = REPO_ROOT / "isowebapps" / "rulesets" / "main"
DEST_SCRIPTING_DIR = REPO_ROOT / "isowebapps" / "rulesets" / "scripting"

# Target ruleset IDs actively loaded or optional in UBlockOriginExtensionManager
TARGET_RULESET_IDS = [
    "ublock-filters",
    "ublock-badware",
    "easylist",
    "easyprivacy",
    "urlhaus-full",
    "annoyances-cookies",
    "annoyances-overlays",
    "block-lan",
    "adguard-mobile",
    "fra-0"
]

# Regex to match embargoed TLDs: Iran (.ir), Cuba (.cu), Syria (.sy), North Korea (.kp)
EMBARGO_REGEX = re.compile(r'(\.ir|\.cu|\.sy|\.kp)([:/\'"\s,\?&^|*><()[\]{}$\\]|$)', re.IGNORECASE)


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
    """Updates git submodule 'shared/uBOL-home' to latest remote revision."""
    print("\n[Step 1/5] Updating git submodule 'shared/uBOL-home'...")
    try:
        run_command(["git", "submodule", "update", "--init", "--remote", "shared/uBOL-home"], cwd=REPO_ROOT)
        run_command(["git", "-C", str(SUBMODULE_DIR), "submodule", "update", "--init", "--recursive"], cwd=REPO_ROOT)
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
    If urlFilter or regexFilter targets an embargoed domain directly, or if
    requestDomains/initiatorDomains becomes empty after filtering, returns (None, count).
    """
    domains_removed = 0

    # 1. Check if urlFilter or regexFilter targets an embargoed domain directly
    for filter_key in ("urlFilter", "regexFilter"):
        filter_val = condition.get(filter_key)
        if isinstance(filter_val, str) and is_embargoed(filter_val):
            return None, 1

    # 2. Filter domain lists in-place
    required_domain_keys = ("requestDomains", "initiatorDomains")
    excluded_domain_keys = ("excludedRequestDomains", "excludedInitiatorDomains")

    for key in required_domain_keys:
        if key in condition and isinstance(condition[key], list):
            original_len = len(condition[key])
            condition[key] = [d for d in condition[key] if not is_embargoed(d)]
            domains_removed += (original_len - len(condition[key]))
            if original_len > 0 and len(condition[key]) == 0:
                return None, domains_removed

    for key in excluded_domain_keys:
        if key in condition and isinstance(condition[key], list):
            original_len = len(condition[key])
            condition[key] = [d for d in condition[key] if not is_embargoed(d)]
            domains_removed += (original_len - len(condition[key]))
            if original_len > 0 and len(condition[key]) == 0:
                del condition[key]

    return condition, domains_removed


def copy_and_sanitize_rulesets():
    """Copies and sanitizes Declarative Net Request rulesets to `rulesets/main/`."""
    print(f"\n[Step 2/5] Sanitizing and copying DNR rulesets to {DEST_RULESETS_DIR}...")

    if not SOURCE_RULESETS_DIR.exists():
        raise FileNotFoundError(f"Source rulesets folder not found: {SOURCE_RULESETS_DIR}")

    DEST_RULESETS_DIR.mkdir(parents=True, exist_ok=True)

    total_rules_in = 0
    total_rules_out = 0
    total_domains_dropped = 0
    total_rules_dropped = 0
    expected_files = set()

    for rid in TARGET_RULESET_IDS:
        filename = f"{rid}.json"
        expected_files.add(filename)
        src_file = SOURCE_RULESETS_DIR / filename
        dst_file = DEST_RULESETS_DIR / filename

        if not src_file.exists():
            print(f"  Warning: {src_file.name} does not exist. Skipping.", file=sys.stderr)
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

        with open(dst_file, "w", encoding="utf-8") as f:
            json.dump(data, f, separators=(",", ":"))

        print(
            f"  - {filename:26} : {rules_in} rules -> {rules_out} rules "
            f"({file_rules_dropped} dropped, {file_domains_dropped} domains filtered)"
        )

    for existing in DEST_RULESETS_DIR.glob("*.json"):
        if existing.name not in expected_files:
            existing.unlink()
            print(f"  - Removed stale ruleset: {existing.name}")

    print(
        f"DNR summary: {total_rules_in} rules in, {total_rules_dropped} dropped, {total_domains_dropped} domains removed."
    )


def extract_const_json_var(code: str, var_name: str):
    """Parses `const <var_name> = /* N */ <json>;` structurally via JSONDecoder.raw_decode."""
    pattern = re.compile(rf"(const {re.escape(var_name)} = /\* )\d+( \*/ )")
    m = pattern.search(code)
    if not m:
        return None
    decoder = json.JSONDecoder()
    value, end_idx = decoder.raw_decode(code, m.end())
    semi_idx = end_idx
    while semi_idx < len(code) and code[semi_idx].isspace():
        semi_idx += 1
    if semi_idx >= len(code) or code[semi_idx] != ";":
        raise ValueError(f"Expected ';' after JSON payload for {var_name}")
    return m.start(), m.group(1), m.group(2), value, semi_idx + 1


def replace_const_json_var(code: str, var_name: str, new_count: int, new_value) -> str:
    """Replaces `const <var_name> = /* N */ <json>;` using structural JSON parsing."""
    parsed = extract_const_json_var(code, var_name)
    if parsed is None:
        raise ValueError(f"Missing expected variable '{var_name}' during scriptlet sanitization")
    start, prefix_a, prefix_b, _, end_with_semi = parsed
    serialized = json.dumps(new_value, separators=(",", ":"))
    return f"{code[:start]}{prefix_a}{new_count}{prefix_b}{serialized};{code[end_with_semi:]}"


def copy_and_sanitize_scriptlets() -> set[str]:
    """Extracts, sanitizes, and writes MAIN and ISOLATED scriptlet files to `rulesets/scripting/`."""
    print(f"\n[Step 3/5] Sanitizing and extracting scriptlets to {DEST_SCRIPTING_DIR}...")
    DEST_SCRIPTING_DIR.mkdir(parents=True, exist_ok=True)
    generated_files: set[str] = set()

    for world in ["main", "isolated"]:
        src_dir = SOURCE_SCRIPTING_DIR / "scriptlet" / world
        if not src_dir.exists():
            continue

        for boundary in ("begin", "end"):
            boundary_src = src_dir / f"scriptlet-{boundary}.js"
            if boundary_src.exists():
                boundary_dst = DEST_SCRIPTING_DIR / f"scriptlet-{world}-{boundary}.js"
                generated_files.add(boundary_dst.name)
                boundary_dst.write_text(boundary_src.read_text(encoding="utf-8"), encoding="utf-8")
                print(f"  - {boundary_dst.name:36} : (framework {boundary})")

        for rid in TARGET_RULESET_IDS:
            src_file = src_dir / f"{rid}.js"
            if not src_file.exists():
                continue

            with open(src_file, "r", encoding="utf-8") as f:
                code = f.read()

            dropped_hns = 0

            # Format A (uBOL 2026.1124+):
            #   const scriptletHostnames = /* N */ [...];
            #   const arglistRefs = /* N */ ["...",...];
            #   const scriptletFromRegexes = /* N */ [{needle,hn,...},"refs", ...]; (stride 2)
            p_hns_new = extract_const_json_var(code, "scriptletHostnames")
            p_refs_new = extract_const_json_var(code, "arglistRefs")

            # Format B (legacy uBOL):
            #   const $scriptletHostnames$ = /* N */ [...];
            #   const $scriptletArglistRefs$ = /* N */ "r0;r1;...";
            #   const $scriptletFromRegexes$ = /* N */ [needle,hn,"refs", ...]; (stride 3)
            p_hns_old = extract_const_json_var(code, "$scriptletHostnames$")
            p_refs_old = extract_const_json_var(code, "$scriptletArglistRefs$")

            if p_hns_new and p_refs_new:
                hns = p_hns_new[3]
                refs = p_refs_new[3]
                if not isinstance(hns, list) or not isinstance(refs, list) or len(hns) != len(refs):
                    raise ValueError(f"Mismatched scriptletHostnames/arglistRefs in {src_file}")
                new_hns = []
                new_refs = []
                for h, r in zip(hns, refs):
                    if isinstance(h, str) and is_embargoed(h):
                        dropped_hns += 1
                    else:
                        new_hns.append(h)
                        new_refs.append(r)

                if len(new_hns) != len(hns):
                    code = replace_const_json_var(code, "scriptletHostnames", len(new_hns), new_hns)
                    code = replace_const_json_var(code, "arglistRefs", len(new_refs), new_refs)
            elif p_hns_old and p_refs_old:
                hns = p_hns_old[3]
                raw_refs = p_refs_old[3]
                if not isinstance(hns, list) or not isinstance(raw_refs, str):
                    raise ValueError(f"Invalid legacy $scriptletHostnames$/$scriptletArglistRefs$ in {src_file}")
                refs = raw_refs.split(";")
                if len(hns) != len(refs):
                    raise ValueError(f"Mismatched legacy $scriptletHostnames$/$scriptletArglistRefs$ in {src_file}")
                new_hns = []
                new_refs = []
                for h, r in zip(hns, refs):
                    if isinstance(h, str) and is_embargoed(h):
                        dropped_hns += 1
                    else:
                        new_hns.append(h)
                        new_refs.append(r)

                if len(new_hns) != len(hns):
                    code = replace_const_json_var(code, "$scriptletHostnames$", len(new_hns), new_hns)
                    code = replace_const_json_var(code, "$scriptletArglistRefs$", len(new_refs), ";".join(new_refs))

            p_regexes_new = extract_const_json_var(code, "scriptletFromRegexes")
            p_regexes_old = extract_const_json_var(code, "$scriptletFromRegexes$")
            if p_regexes_new:
                regexes = p_regexes_new[3]
                if not isinstance(regexes, list) or len(regexes) % 2 != 0:
                    raise ValueError(f"Invalid scriptletFromRegexes stride in {src_file}")
                new_regexes = []
                for i in range(0, len(regexes), 2):
                    entry, ref = regexes[i], regexes[i + 1]
                    needle = entry.get("needle", "") if isinstance(entry, dict) else ""
                    hn = entry.get("hn", "") if isinstance(entry, dict) else ""
                    pn = entry.get("pn", "") if isinstance(entry, dict) else ""
                    if any(isinstance(v, str) and is_embargoed(v) for v in (needle, hn, pn)):
                        dropped_hns += 1
                    else:
                        new_regexes.extend([entry, ref])
                if len(new_regexes) != len(regexes):
                    code = replace_const_json_var(code, "scriptletFromRegexes", len(new_regexes) // 2, new_regexes)
            elif p_regexes_old:
                regexes = p_regexes_old[3]
                if not isinstance(regexes, list) or len(regexes) % 3 != 0:
                    raise ValueError(f"Invalid legacy $scriptletFromRegexes$ stride in {src_file}")
                new_regexes = []
                for i in range(0, len(regexes), 3):
                    needle, pattern, ref = regexes[i], regexes[i + 1], regexes[i + 2]
                    if (isinstance(needle, str) and is_embargoed(needle)) or (isinstance(pattern, str) and is_embargoed(pattern)):
                        dropped_hns += 1
                    else:
                        new_regexes.extend([needle, pattern, ref])
                if len(new_regexes) != len(regexes):
                    code = replace_const_json_var(code, "$scriptletFromRegexes$", len(new_regexes) // 3, new_regexes)

            # Output filename with distinct world prefix to avoid flat-bundle collisions
            dst_file = DEST_SCRIPTING_DIR / f"scriptlet-{world}-{rid}.js"
            generated_files.add(dst_file.name)
            with open(dst_file, "w", encoding="utf-8") as f:
                f.write(code)

            status = f"({dropped_hns} embargoed hostnames dropped)" if dropped_hns else "(clean)"
            print(f"  - {dst_file.name:36} : {status}")

    return generated_files


def compile_and_sanitize_cosmetics() -> set[str]:
    """Compiles specific cosmetic CSS JSON rulesets into self-contained scripts in `rulesets/scripting/`."""
    print(f"\n[Step 4/5] Compiling and sanitizing cosmetic CSS scripts to {DEST_SCRIPTING_DIR}...")
    DEST_SCRIPTING_DIR.mkdir(parents=True, exist_ok=True)
    generated_files: set[str] = set()

    src_dir = SOURCE_SCRIPTING_DIR / "specific"
    if not src_dir.exists():
        return generated_files

    for rid in TARGET_RULESET_IDS:
        src_file = src_dir / f"{rid}.json"
        if not src_file.exists():
            continue

        with open(src_file, "r", encoding="utf-8") as f:
            data = json.load(f)

        data.setdefault("rulesetId", rid)

        hns = data.get("hostnames", [])
        refs = data.get("selectorListRefs", [])
        dropped_hns = 0

        if len(hns) == len(refs):
            new_hns = []
            new_refs = []
            for h, r in zip(hns, refs):
                if is_embargoed(h):
                    dropped_hns += 1
                else:
                    new_hns.append(h)
                    new_refs.append(r)
            data["hostnames"] = new_hns
            data["selectorListRefs"] = new_refs

        regexes = data.get("regexes", [])
        if isinstance(regexes, list) and len(regexes) % 3 == 0:
            new_regexes = []
            for i in range(0, len(regexes), 3):
                prefix, pattern, ref = regexes[i], regexes[i + 1], regexes[i + 2]
                if (isinstance(prefix, str) and is_embargoed(prefix)) or (isinstance(pattern, str) and is_embargoed(pattern)):
                    dropped_hns += 1
                else:
                    new_regexes.extend([prefix, pattern, ref])
            data["regexes"] = new_regexes

        # Minify JSON payload embedded inside the script
        json_payload = json.dumps(data, separators=(",", ":"))

        # Self-contained content script for ISOLATED world (WKContentWorld.defaultClient)
        script_code = f"""// ruleset cosmetic: {rid}
(function uBOL_cosmeticSpecific_{rid.replace('-', '_')}() {{
    'use strict';
    const data = {json_payload};

    const binarySearch = (haystack, needle, r) => {{
        let l = 0, i = 0, d = 0, candidate;
        r = r >= 0 ? r : haystack.length;
        while ( l < r ) {{
            i = l + r >>> 1;
            candidate = haystack[i];
            d = needle.length - candidate.length;
            if ( d === 0 ) {{
                if ( needle === candidate ) {{ return i; }}
                d = needle < candidate ? -1 : 1;
            }}
            if ( d < 0 ) {{
                r = i;
            }} else {{
                l = i + 1;
            }}
        }}
        return ~i;
    }};

    const docloc = document.location;
    if ( !docloc ) {{ return; }}
    const origins = [ docloc.origin ];
    if ( docloc.ancestorOrigins ) {{
        origins.push(...docloc.ancestorOrigins);
    }}
    const entries = origins.map((origin, i) => {{
        const beg = origin.indexOf('://');
        if ( beg === -1 ) {{ return; }}
        const hn1 = origin.slice(beg + 3);
        const end = hn1.indexOf(':');
        const hn2 = end === -1 ? hn1 : hn1.slice(0, end);
        if ( hn2.length === 0 ) {{ return; }}
        const hns = [ hn2 ];
        for ( let pos = 0; ; ) {{
            pos = hn2.indexOf('.', pos) + 1;
            if ( pos === 0 ) {{ break; }}
            hns.push(hn2.slice(pos));
        }}
        return {{ hns, i }};
    }}).filter(a => a);
    if ( entries.length === 0 ) {{ return; }}
    entries[0].hns.push('*');

    const hostnames = entries[0].hns;
    let entities = undefined;
    if ( data.hasEntities ) {{
        const ens = [];
        for ( let hn of hostnames ) {{
            for (;;) {{
                const pos = hn.lastIndexOf('.');
                if ( pos === -1 ) {{ break; }}
                hn = hn.slice(0, pos);
                ens.push(`${{hn}}.*`);
            }}
        }}
        ens.sort((a, b) => {{
            const d = b.length - a.length;
            if ( d !== 0 ) {{ return d; }}
            return a > b ? -1 : 1;
        }});
        entities = ens;
    }}

    const selectors = new Set();
    const exceptions = new Set();

    const selectorsFromListIndex = (ilist) => {{
        if ( ilist < 0 || ilist >= data.selectorLists.length ) {{ return; }}
        const list = JSON.parse(`[${{data.selectorLists[ilist]}}]`);
        for ( const iselector of list ) {{
            if ( iselector >= 0 ) {{
                selectors.add(data.selectors[iselector]);
            }} else {{
                exceptions.add(data.selectors[~iselector]);
            }}
        }}
    }};

    const selectorsFromHostnames = (haystack, needles) => {{
        let listref = -1;
        for ( const needle of needles ) {{
            listref = binarySearch(haystack, needle, listref);
            if ( listref >= 0 ) {{
                selectorsFromListIndex(data.selectorListRefs[listref]);
            }} else {{
                listref = ~listref + 1;
            }}
        }}
    }};

    if ( data.hostnames && data.hostnames.length ) {{
        selectorsFromHostnames(data.hostnames, hostnames);
        if ( entities ) {{
            selectorsFromHostnames(data.hostnames, entities);
        }}
    }}

    if ( data.regexes && data.regexes.length ) {{
        const thisHostname = docloc.hostname || '';
        for ( let i = 0, n = data.regexes.length; i < n; i += 3 ) {{
            if ( thisHostname.includes(data.regexes[i]) === false ) {{ continue; }}
            try {{
                const re = new RegExp(data.regexes[i+1]);
                if ( re.test(thisHostname) === false ) {{ continue; }}
                selectorsFromListIndex(data.regexes[i+2]);
            }} catch(e) {{}}
        }}
    }}

    for ( const exc of exceptions ) {{
        selectors.delete(exc);
    }}

    if ( selectors.size === 0 ) {{ return; }}

    const s = [];
    const p = [];
    for ( const sel of selectors ) {{
        if ( sel.startsWith('{{') ) {{
            try {{ p.push(JSON.parse(sel)); }} catch(e) {{}}
        }} else {{
            s.push(sel);
        }}
    }}

    let css = '';
    if ( s.length !== 0 ) {{
        css += s.join(',\\n') + ' {{ display: none !important; }}\\n';
    }}
    for ( const item of p ) {{
        if ( item.cssable && Array.isArray(item.action) && item.action[0] === 'style' ) {{
            css += `${{item.selector}} {{ ${{item.action[1]}} }}\\n`;
        }}
    }}

    if ( !css ) {{ return; }}

    const applyCSS = () => {{
        try {{
            if ( document.adoptedStyleSheets ) {{
                const sheet = new CSSStyleSheet();
                sheet.replaceSync(css);
                document.adoptedStyleSheets.push(sheet);
                return;
            }}
        }} catch(e) {{}}
        try {{
            const style = document.createElement('style');
            style.type = 'text/css';
            style.setAttribute('data-ubol-cosmetic', data.rulesetId);
            style.textContent = css;
            (document.head || document.documentElement).appendChild(style);
        }} catch(e) {{}}
    }};

    if ( document.documentElement ) {{
        applyCSS();
    }} else {{
        document.addEventListener('DOMContentLoaded', applyCSS, {{ once: true }});
    }}
}})();
"""

        dst_file = DEST_SCRIPTING_DIR / f"cosmetic-specific-{rid}.js"
        generated_files.add(dst_file.name)
        with open(dst_file, "w", encoding="utf-8") as f:
            f.write(script_code)

        status = f"({dropped_hns} embargoed hostnames dropped)" if dropped_hns else "(clean)"
        print(f"  - {dst_file.name:36} : {status}")

    return generated_files


def clean_stale_scripting_files(expected_files: set[str]):
    """Removes any stale JS files in DEST_SCRIPTING_DIR no longer generated by Steps 3-4."""
    for existing in DEST_SCRIPTING_DIR.glob("*.js"):
        if existing.name not in expected_files:
            existing.unlink()
            print(f"  - Removed stale scripting file: {existing.name}")


def verify_sanitization():
    """Double checks all output files for embargoed patterns and JavaScript syntax validity."""
    print("\n[Step 5/5] Verifying output files for embargoed patterns & JS syntax...")
    violations = []

    # 1. Check all JSON files
    for path in sorted(DEST_RULESETS_DIR.glob("*.json")):
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
            matches = EMBARGO_REGEX.findall(content)
            if matches:
                violations.append((path.name, matches))

    # 2. Check all JS files for embargoed patterns first
    js_files = sorted(DEST_SCRIPTING_DIR.glob("*.js"))
    for path in js_files:
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

    # 3. Check JS syntax & execution with JSC if available
    jsc_bin = "/System/Library/Frameworks/JavaScriptCore.framework/Versions/Current/Helpers/jsc"
    has_jsc = os.path.exists(jsc_bin)
    jsc_stub = (
        "const window = globalThis; const self = globalThis; "
        "const document = { location: { origin: 'https://example.com', hostname: 'example.com', pathname: '/' }, "
        "adoptedStyleSheets: [], documentElement: null, addEventListener: () => {}, "
        "createElement: () => ({ setAttribute: () => {}, style: {} }) };"
    )

    if has_jsc:
        for path in js_files:
            cmd = [jsc_bin, "-e", jsc_stub]
            if path.name.startswith("scriptlet-main-") and path.name != "scriptlet-main-begin.js":
                begin_file = DEST_SCRIPTING_DIR / "scriptlet-main-begin.js"
                end_file = DEST_SCRIPTING_DIR / "scriptlet-main-end.js"
                if begin_file.exists():
                    cmd.append(str(begin_file))
                cmd.append(str(path))
                if path.name != "scriptlet-main-end.js" and end_file.exists():
                    cmd.append(str(end_file))
            elif path.name.startswith("scriptlet-isolated-") and path.name != "scriptlet-isolated-begin.js":
                begin_file = DEST_SCRIPTING_DIR / "scriptlet-isolated-begin.js"
                end_file = DEST_SCRIPTING_DIR / "scriptlet-isolated-end.js"
                if begin_file.exists():
                    cmd.append(str(begin_file))
                cmd.append(str(path))
                if path.name != "scriptlet-isolated-end.js" and end_file.exists():
                    cmd.append(str(end_file))
            else:
                cmd.append(str(path))

            res = subprocess.run(cmd, capture_output=True, text=True)
            if res.returncode != 0:
                detail = (res.stderr or res.stdout).strip()
                print(f"ERROR: Syntax/execution error in {path.name}:\n{detail}", file=sys.stderr)
                sys.exit(1)

    print("Verification PASSED: 0 embargoed domains found, all JS scripts verified.")


def print_completion():
    print("\nDone! Rulesets and scriptlets are successfully extracted, sanitized, and ready for WKWebView injection.")


def main():
    try:
        update_git_submodule()
        copy_and_sanitize_rulesets()
        generated_scripts = copy_and_sanitize_scriptlets()
        generated_scripts |= compile_and_sanitize_cosmetics()
        clean_stale_scripting_files(generated_scripts)
        verify_sanitization()
        print_completion()
    except Exception as err:
        print(f"\nFATAL ERROR: {err}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
