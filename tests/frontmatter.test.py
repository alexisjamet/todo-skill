#!/usr/bin/env python3
"""Every YAML frontmatter and YAML file of the plugin parses with a strict parser.

Usage: python3 tests/frontmatter.test.py   (needs PyYAML)
"""
import glob
import os
import sys

try:
    import yaml
except ImportError:
    print("skipped: PyYAML is not installed")
    sys.exit(0)

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
files = sorted(
    glob.glob("skills/*/SKILL.md")
    + glob.glob("evals/*/prompt.md")
    + glob.glob("evals/*/graders/*.md")
    + glob.glob("evals/*/case.yaml")
)
failed = 0
for path in files:
    text = open(path, encoding="utf-8").read()
    if path.endswith(".md"):
        if not text.startswith("---\n"):
            continue
        text = text[4 : text.index("\n---", 4)]
    try:
        data = yaml.safe_load(text)
        if path.endswith("SKILL.md"):
            for key in ("name", "description"):
                assert isinstance(data.get(key), str) and data[key], f"{key} is missing"
            # claude.ai refuses XML-like tags in a description and caps it at 1024 characters.
            assert "<" not in data["description"] and ">" not in data["description"], "description holds angle brackets"
            assert len(data["description"]) <= 1024, "description is longer than 1024 characters"
            # The Agent Skills format wants allowed-tools as one space-separated string.
            assert isinstance(data.get("allowed-tools", ""), str), "allowed-tools is not a string"
    except (yaml.YAMLError, AssertionError) as error:
        failed += 1
        print("FAIL", path, "-", " ".join(str(error).split())[:200])
print(f"{len(files)} files checked, {failed} invalid")
sys.exit(1 if failed else 0)
