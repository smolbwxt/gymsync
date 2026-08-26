"""The verifier has to make a distinction, not just say no a lot.

Rejecting everything unfamiliar would have "caught" this bug and also
thrown away 3D Muscle Journey and Biolayne, both of which resolved to a
correct channel under a different display name. These are the eight real
cases from the 2026-08-26 audit.
"""
import importlib.util
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
spec = importlib.util.spec_from_file_location(
    "enum_mod", "G:/Projects/GymSync/tools/youtube-research/enumerate.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

CASES = [
    # (intended label, what the resolver returned, should_accept)
    ("Chris Bumstead (5x Classic Physique Olympia)", "CHAMPION MENTALITY", False),
    ("Sam Sulek (high-volume physique training)", "Jeff Nippard", False),
    ("Eric Cressey (baseball S&C)", "Mike Robertson", False),
    ("3D Muscle Journey (Helms)", "Team3DMJ", True),
    ("Biolayne (Layne Norton)", "Dr. Layne Norton", True),
    ("Menno Henselmans", "Menno Henselmans", True),
    ("Flow High Performance", "Flow High Performance", True),
    ("Phil Daru (combat/wrestling S&C)", "Phil Daru", True),
    ("Eric Cressey (baseball S&C)", "Eric Cressey", True),
    ("Chris Bumstead (5x Classic Physique Olympia)", "Chris Bumstead", True),
    ("Sam Sulek (high-volume physique training)", "Sam Sulek", True),
]

fails = 0
for intended, resolved, want in CASES:
    got = m.looks_like(intended, resolved)
    ok = got == want
    fails += not ok
    print("%s  %-44s -> %-22s accept=%-5s want=%s"
          % ("ok  " if ok else "FAIL", intended[:44], resolved[:22], got, want))
print()
print("FAILURES: %d of %d" % (fails, len(CASES)))
sys.exit(1 if fails else 0)
