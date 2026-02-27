#!/usr/bin/env python3
import argparse
import json
import re
import urllib.request
from pathlib import Path

TXT_URL = "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/privacy-removeparam.txt"
JSON_URL = "https://gitlab.com/ClearURLs/rules/-/raw/master/data.min.json"

REMOVE_PARAM_PREFIX = "$removeparam="
REGEX_META_RE = re.compile(r"[\\^$.*+?()\[\]{}|]")


def fetch_text(url: str) -> str:
    with urllib.request.urlopen(url, timeout=30) as response:
        return response.read().decode("utf-8")


def fetch_json(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def normalize_token(raw_token: str):
    token = raw_token.strip()
    if not token:
        return None, None

    if token.startswith("/") and token.endswith("/") and len(token) > 2:
        token = token[1:-1]

    if "=" in token or REGEX_META_RE.search(token):
        return None, token
    return token.lower(), None


def parse_general_rules(txt_content: str):
    exact = set()
    regex_patterns = []

    for raw_line in txt_content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("!") or line.startswith("#"):
            continue
        if not line.startswith(REMOVE_PARAM_PREFIX):
            continue

        token = line[len(REMOVE_PARAM_PREFIX):]
        token = token.split(",", 1)[0]

        exact_token, regex_token = normalize_token(token)
        if exact_token:
            exact.add(exact_token)
        elif regex_token:
            regex_patterns.append(regex_token)

    return sorted(exact), regex_patterns


def parse_provider_rules(json_root: dict):
    providers = []
    provider_map = json_root.get("providers", {})

    for provider_name in sorted(provider_map.keys()):
        provider = provider_map[provider_name]
        url_pattern = provider.get("urlPattern")
        if not url_pattern:
            continue

        exact = set()
        regex_patterns = []

        for key in ("rules", "referralMarketing", "rawRules"):
            for token in provider.get(key, []) or []:
                exact_token, regex_token = normalize_token(str(token))
                if exact_token:
                    exact.add(exact_token)
                elif regex_token:
                    regex_patterns.append(regex_token)

        providers.append(
            {
                "name": provider_name,
                "urlPattern": url_pattern,
                "exactParams": sorted(exact),
                "regexParams": regex_patterns,
            }
        )

    return providers


def build_parsed_rules(txt_content: str, json_root: dict):
    general_exact, general_regex = parse_general_rules(txt_content)
    providers = parse_provider_rules(json_root)

    return {
        "generalExact": general_exact,
        "generalRegex": general_regex,
        "providers": providers,
    }


def main():
    parser = argparse.ArgumentParser(description="Fetch upstream rules and generate assets/parsedRules.json")
    parser.add_argument("--output", default="assets/parsedRules.json", help="Output path for parsed rules")
    parser.add_argument("--offline", action="store_true", help="Use local assets/privacy-removeparam.txt and assets/data.min.json")
    args = parser.parse_args()

    root = Path(__file__).resolve().parent
    assets_dir = root / "assets"

    txt_local_path = assets_dir / "privacy-removeparam.txt"
    json_local_path = assets_dir / "data.min.json"

    if args.offline:
        txt_content = txt_local_path.read_text(encoding="utf-8")
        json_root = json.loads(json_local_path.read_text(encoding="utf-8"))
    else:
        try:
            txt_content = fetch_text(TXT_URL)
            json_root = fetch_json(JSON_URL)
        except Exception as error:
            print(f"Remote fetch failed ({error}); using local assets fallback.")
            if txt_local_path.exists() and json_local_path.exists():
                txt_content = txt_local_path.read_text(encoding="utf-8")
                json_root = json.loads(json_local_path.read_text(encoding="utf-8"))
            else:
                existing_parsed = assets_dir / "parsedRules.json"
                if existing_parsed.exists():
                    print("Local raw source files are missing; keeping existing assets/parsedRules.json.")
                    return
                raise RuntimeError(
                    "Local fallback files assets/privacy-removeparam.txt and assets/data.min.json are missing."
                )

    parsed = build_parsed_rules(txt_content, json_root)

    output_path = Path(args.output)
    if not output_path.is_absolute():
        output_path = root / output_path
    output_path.parent.mkdir(parents=True, exist_ok=True)

    output_path.write_text(json.dumps(parsed, separators=(",", ":"), ensure_ascii=True), encoding="utf-8")
    print(f"Wrote parsed rules: {output_path}")


if __name__ == "__main__":
    main()
