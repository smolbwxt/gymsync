"""Catch Python unicode escapes that leaked into Swift source.

Run before pushing:  python tools/check_swift_escapes.py

WHY THIS EXISTS. Swift's unicode escape has braces - `\\u{2014}`. Python's
does not - `\\u2014`. Patch scripts that generate Swift emit the Python
form, Swift rejects it outright ("expected hexadecimal code in braces
after unicode escape"), and because CI is the only Swift compiler on this
machine each occurrence costs a ~30 minute round trip. It has cost three
so far on 2026-08-26 alone.

The obvious mitigation - never write an escape, paste the real character -
depends on remembering. This does not.

Written as a FILE and never as a `python -c` one-liner or a bash heredoc:
both collapse the doubled backslash in the pattern before Python parses
it, and the check then dies with "incomplete escape \\u at position 0"
having verified nothing. That failure mode also happened three times
today, which is its own argument for a file.

Exit 1 on any find, so it can gate a push.
"""
import glob
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PATTERNS = [
    # A backslash-u NOT followed by a brace. Swift's own \u{XXXX} is fine.
    ("bare unicode escape (Swift needs braces)", re.compile(r"\\u(?!\{)[0-9a-fA-F]{4}")),
    # Python's \N{NAME} form has no Swift equivalent at all.
    ("python named escape", re.compile(r"\\N\{[A-Z ]+\}")),
]


def main() -> int:
    roots = [os.path.join(ROOT, "GymSyncApp", "GymSync"),
             os.path.join(ROOT, "GymSyncApp", "GymSyncTests"),
             os.path.join(ROOT, "GymSyncApp", "GymSyncWatch")]
    files = []
    for r in roots:
        files += glob.glob(os.path.join(r, "**", "*.swift"), recursive=True)

    bad = 0
    for path in sorted(files):
        try:
            text = open(path, encoding="utf-8").read()
        except (UnicodeDecodeError, OSError):
            continue
        for label, pat in PATTERNS:
            for m in pat.finditer(text):
                line = text.count("\n", 0, m.start()) + 1
                rel = os.path.relpath(path, ROOT).replace("\\", "/")
                print("%s:%d  %s  -> %s" % (rel, line, label, m.group(0)))
                bad += 1

    print("\nscanned %d Swift files" % len(files))
    if bad:
        print("FOUND %d escape(s) Swift cannot parse." % bad)
        print("Replace each with the literal character, or use \\u{XXXX}.")
        return 1
    print("clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
