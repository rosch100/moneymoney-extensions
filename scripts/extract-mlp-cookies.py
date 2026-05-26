#!/usr/bin/env python3
"""MLP-Cookies aus HAR für MoneyMoney. Usage: python3 extract-mlp-cookies.py datei.har"""

__version__ = "1.0.0"

import json
import subprocess  # nosec
import sys


PRIORITY = [
    "VUSESSIONID",  # ERFORDERLICH für Vue API (kann 2x vorkommen!)
    "BIGipServervue.mlp.de",  # Load-Balancer für Vue API
    # Folgende werden für Vue API NICHT benötigt (nur für Auth-Server):
    # "CAS_SESSION", "CAS_S_SESSION", "CAS_DEVICE_SESSION",
]


def parse_cookie_header(value):
    cookies = {}
    for pair in value.split(";"):
        pair = pair.strip()
        if "=" in pair:
            name, val = pair.split("=", 1)
            cookies[name.strip()] = val.strip()
    return cookies


def parse_set_cookie(value):
    first = value.split(";")[0].strip()
    if "=" not in first:
        return {}
    name, val = first.split("=", 1)
    return {name.strip(): val.strip()}


def collect_cookies(har_path):
    with open(har_path, encoding="utf-8") as f:
        entries = json.load(f)["log"]["entries"]

    cookies = {}
    vu_session_ids = []  # Speichere alle VUSESSIONID-Cookies (können 2x vorkommen!)

    for entry in entries:
        # Prüfe auf vue.mlp.de API-Aufruf mit Cookie-Header
        url = entry.get("request", {}).get("url", "")
        if "vue.mlp.de/vu/api" in url:
            for header in entry.get("request", {}).get("headers", []):
                if header.get("name", "").lower() == "cookie":
                    cookie_value = header.get("value", "")
                    # Extrahiere VUSESSIONID aus Cookie-Header (kann mehrfach vorkommen!)
                    for vusid in cookie_value.split(";"):
                        vusid = vusid.strip()
                        if vusid.startswith("VUSESSIONID="):
                            val = vusid.split("=", 1)[1]
                            if val not in vu_session_ids:
                                vu_session_ids.append(val)

        for header in entry.get("request", {}).get("headers", []):
            if header.get("name", "").lower() == "cookie":
                cookies.update(parse_cookie_header(header.get("value", "")))
        for header in entry.get("response", {}).get("headers", []):
            if header.get("name", "").lower() == "set-cookie":
                cookies.update(parse_set_cookie(header.get("value", "")))
        for item in entry.get("request", {}).get("cookies", []):
            cookies[item["name"]] = item["value"]

    # Wenn wir VUSESSIONIDs aus vue.mlp.de gefunden haben, diese bevorzugen
    if vu_session_ids:
        cookies["VUSESSIONID"] = vu_session_ids[0]
        if len(vu_session_ids) > 1:
            cookies["VUSESSIONID2"] = vu_session_ids[1]

    return cookies


def format_cookies(cookies):
    ordered = []
    used = set()

    # VUSESSIONID kann 2x vorkommen (aus HAR-Analyse)
    if "VUSESSIONID" in cookies:
        ordered.append(f"VUSESSIONID={cookies['VUSESSIONID']}")
        used.add("VUSESSIONID")
        if "VUSESSIONID2" in cookies:
            ordered.append(f"VUSESSIONID={cookies['VUSESSIONID2']}")
            used.add("VUSESSIONID2")

    for name in PRIORITY:
        if name in cookies and name not in used:
            ordered.append(f"{name}={cookies[name]}")
            used.add(name)
    for name in sorted(cookies):
        if name not in used:
            ordered.append(f"{name}={cookies[name]}")
    return "COOKIE:" + ";".join(ordered)


def main(har_path):
    cookies = collect_cookies(har_path)
    if not cookies:
        print("Keine Cookies in der HAR-Datei.", file=sys.stderr)
        sys.exit(1)

    # Prüfe auf kritische Cookies
    if "VUSESSIONID" not in cookies:
        print("Warnung: VUSESSIONID fehlt!", file=sys.stderr)
        print("Bitte stellen Sie sicher, dass Sie:", file=sys.stderr)
        print("1. Am MLP Kundenportal angemeldet sind", file=sys.stderr)
        print("2. Die Vertragsübersicht geöffnet haben (für vue.mlp.de)", file=sys.stderr)

    result = format_cookies(cookies)
    print(result)

    try:
        subprocess.run(["pbcopy"], input=result, text=True, check=True)  # nosec
        print("In Zwischenablage kopiert.", file=sys.stderr)
    except (FileNotFoundError, subprocess.CalledProcessError):
        pass


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <har>", file=sys.stderr)
        sys.exit(1)
    main(sys.argv[1])
