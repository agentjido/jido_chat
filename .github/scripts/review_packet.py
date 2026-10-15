"""Build the deterministic review packet from the complete local Git diff."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

TITLE = re.compile(r"^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([A-Za-z0-9_.-]+\))?(!)?: .+")

def git(*args):
    return subprocess.check_output(["git", *args])

def build(base, head, title, max_lines=2000):
    revision = base + "..." + head
    raw_status = git("diff", "--name-status", "--no-renames", "-z", revision).split(b"\0")
    statuses = {raw_status[i + 1].decode(): raw_status[i].decode() for i in range(0, len(raw_status) - 1, 2)}
    files = []
    for entry in git("diff", "--numstat", "--no-renames", "-z", revision).split(b"\0"):
        if not entry:
            continue
        additions, deletions, filename = entry.split(b"\t", 2)
        name = filename.decode()
        added, deleted = (int(value) if value != b"-" else 0 for value in (additions, deletions))
        files.append({"filename": name, "status": {"A": "added", "D": "removed"}.get(statuses[name], "modified"), "additions": added, "deletions": deleted, "changes": added + deleted})
    names = [row["filename"] for row in files]
    summary = {
        "total_files": len(files),
        "workflow_files": sum(name.startswith(".github/workflows/") and name.endswith((".yml", ".yaml")) for name in names),
        "package_files": sum(name in ("mix.exs", "mix.lock") for name in names),
        "docs_files": sum(name.startswith("docs/") or "README" in name or name.endswith(".md") for name in names),
        "test_files": sum(name.startswith("test/") or name.endswith("_test.exs") or "/test/" in name for name in names),
        "source_files": sum(name.startswith(("lib/", "config/")) for name in names),
        "changelog_files": sum(name == "CHANGELOG.md" for name in names),
    }
    workflow_diff = git("diff", revision, "--", ".github/workflows").decode()
    patterns = [
        (r"^\+.*pull_request_target:", "Added pull_request_target trigger."),
        (r"^\+.*contents:\s*write", "Added contents: write permission."),
        (r"^\+.*pull-requests:\s*write", "Added pull-requests: write permission."),
        (r"^\+.*secrets:\s*inherit", "Added secrets: inherit."),
        (r"^\+.*uses: .+@[A-Za-z0-9_.-]+\s*$", "Added or changed action references; prefer full SHA pins."),
    ]
    risks = [message for pattern, message in patterns if re.search(pattern, workflow_diff, re.M)]
    missing = []
    if summary["source_files"] and not summary["test_files"]:
        missing.append("Source/config changed without test file changes.")
    if summary["source_files"] and not summary["docs_files"]:
        missing.append("Source/config changed without docs or README changes.")
    if summary["package_files"] and not summary["changelog_files"]:
        missing.append("Package metadata changed without CHANGELOG.md changes; git_ops can own changelog entries.")
    valid = bool(TITLE.match(title))
    packet = {"status": "ok" if valid else "error", "summary": summary, "pr_policy": {"conventional_commit": {"enabled": True, "title": title, "valid": "true" if valid else "false"}}, "workflow_risks": risks, "missing_signals": missing, "files": files, "source": "complete_local_git_diff", "base_sha": base, "head_sha": head}
    # A bounded packet is useful for review; the inventory above remains complete.
    patch = git("diff", revision, "--", ".github", "mix.exs", "mix.lock", "lib", "config", "test", "integration").decode()
    patch = "\n".join(patch.splitlines()[:max_lines]) + "\n"
    return packet, patch

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--pr-number", required=True, type=int)
    parser.add_argument("--output", default=".jido-review")
    args = parser.parse_args()
    packet, patch = build(args.base, args.head, args.title)
    packet.update(repository=args.repository, pull_request=args.pr_number, ci=[])
    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=True)
    (out / "jido-review.json").write_text(json.dumps(packet, indent=2) + "\n")
    (out / "diff.patch").write_text(patch)
    lines = ["## Jido Review", "", "Conventional commit title: " + ("pass" if packet["status"] == "ok" else "fail"), "", "Complete file inventory:"]
    lines.extend("- " + key + ": " + str(value) for key, value in packet["summary"].items())
    lines.extend(["", "Workflow risk signals:"] + ["- " + text for text in packet["workflow_risks"] or ["None detected."]])
    lines.extend(["", "Missing signals:"] + ["- " + text for text in packet["missing_signals"] or ["None detected."]])
    markdown = "\n".join(lines) + "\n"
    (out / "jido-review.md").write_text(markdown)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as stream:
            stream.write(markdown)
    print(json.dumps({"state": packet["status"], "files": packet["summary"]["total_files"], "head": args.head}))
    return 0 if packet["status"] == "ok" else 1

if __name__ == "__main__":
    raise SystemExit(main())
