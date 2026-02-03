#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import os
import re
import sys
import urllib.request

BREAKING_KEYS = [
    "breaking",
    "remove",
    "rename",
    "deprecat",
    "schema",
    "openapi",
    "api",
    "tls",
    "https",
    "auth",
    "config",
    "protocol",
    "migration",
]
FEATURE_KEYS = [
    "add ",
    "added",
    "feat",
    "feature",
    "support",
    "introduce",
    "new ",
    "bring back",
    "restore",
]


def fetch_releases(repo: str) -> list[dict]:
    url = f"https://api.github.com/repos/{repo}/releases?per_page=100"
    headers = {"User-Agent": "traxe-release-watch"}
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def parse_iso8601(value: str) -> dt.datetime:
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(dt.UTC)


def extract_items(body: str) -> list[str]:
    items: list[str] = []
    for line in body.splitlines():
        line = line.strip()
        if line.startswith("*") or line.startswith("-"):
            item = re.sub(r"^[\*-]+\s+", "", line).strip()
            if item:
                items.append(item)
    return items


def classify(items: list[str]) -> tuple[list[str], list[str], list[str]]:
    breaking: list[str] = []
    features: list[str] = []
    other: list[str] = []
    for item in items:
        lower = item.lower()
        if any(key in lower for key in BREAKING_KEYS):
            breaking.append(item)
        elif any(key in lower for key in FEATURE_KEYS):
            features.append(item)
        else:
            other.append(item)
    return breaking, features, other


def extract_changelog_url(body: str) -> str | None:
    for line in body.splitlines():
        if "Full Changelog" in line and "http" in line:
            match = re.search(r"https?://\S+", line)
            if match:
                return match.group(0).rstrip("\n\r")
    return None


def format_release(release: dict) -> str:
    tag = release.get("tag_name", "(unknown)")
    published_at = release.get("published_at") or release.get("created_at")
    published = parse_iso8601(published_at)
    prerelease = "prerelease" if release.get("prerelease") else "release"
    url = release.get("html_url")
    body = release.get("body") or ""
    items = extract_items(body)
    breaking, features, other = classify(items)
    changelog = extract_changelog_url(body)

    lines: list[str] = []
    lines.append(f"## {tag} ({published.date().isoformat()}, {prerelease})")
    if url:
        lines.append(f"Source: [Release]({url})")
    if changelog:
        lines.append(f"Full Changelog: [Compare]({changelog})")

    lines.append("")
    lines.append("### Potential breaking changes (heuristic)")
    if breaking:
        lines.extend([f"- {item}" for item in breaking])
    else:
        lines.append("- None detected from release notes")

    lines.append("")
    lines.append("### New features")
    if features:
        lines.extend([f"- {item}" for item in features])
    else:
        lines.append("- None detected from release notes")

    if other:
        lines.append("")
        lines.append("### Other changes")
        lines.extend([f"- {item}" for item in other])

    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--days", type=int, default=7)
    parser.add_argument("--include-prereleases", action="store_true")
    parser.add_argument("--output", default="report.md")
    args = parser.parse_args()

    releases = fetch_releases(args.repo)
    cutoff = dt.datetime.now(dt.UTC) - dt.timedelta(days=args.days)

    selected: list[dict] = []
    for release in releases:
        if release.get("draft"):
            continue
        if release.get("prerelease") and not args.include_prereleases:
            continue
        published_at = release.get("published_at") or release.get("created_at")
        if not published_at:
            continue
        published = parse_iso8601(published_at)
        if published >= cutoff:
            selected.append(release)

    selected.sort(key=lambda r: r.get("published_at") or r.get("created_at"), reverse=True)

    now = dt.datetime.now(dt.UTC)
    header = [
        "# Release Watch",
        f"Repo: {args.repo}",
        f"Checked: {now.date().isoformat()} (UTC)",
        f"Window: last {args.days} days",
        "",  # spacer
    ]

    if not selected:
        content = "\n".join(header + ["No releases published in this window."])
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(content)
        if "GITHUB_OUTPUT" in os.environ:
            with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as f:
                f.write("has_releases=0\n")
        return 0

    body_sections = [format_release(r) for r in selected]
    content = "\n".join(header + ["\n---\n".join(body_sections)])

    with open(args.output, "w", encoding="utf-8") as f:
        f.write(content)

    if "GITHUB_OUTPUT" in os.environ:
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as f:
            f.write("has_releases=1\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
