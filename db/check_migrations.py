#!/usr/bin/env python3
"""Check unique contiguous numeric IDs for the disposable greenfield SQL sequence."""
from pathlib import Path
import re
import sys
import unittest

NAME = re.compile(r"([0-9]{4})_[a-z0-9]+(?:_[a-z0-9]+)*\.sql\Z")

def validate(names, label):
    if not names:
        raise ValueError(f"{label}: no SQL files")
    ids = {}
    for name in sorted(names):
        match = NAME.fullmatch(name)
        if not match:
            raise ValueError(f"{label}: invalid filename {name}")
        ident = int(match.group(1))
        if ident in ids:
            raise ValueError(f"{label}: duplicate migration ID {ident:04d}: {ids[ident]} and {name}")
        ids[ident] = name
    if sorted(ids) != list(range(1, len(ids) + 1)):
        raise ValueError(f"{label}: IDs must be contiguous from 0001")
    return ids

def validate_pair(migrations, tests):
    m = validate(migrations, "migrations")
    t = validate(tests, "SQL tests")
    if m.keys() != t.keys():
        raise ValueError("Every migration must have exactly one SQL acceptance test with the same numeric ID")
    return len(m)

class GuardTests(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(validate_pair(["0002_b.sql", "0001_a.sql"], ["0001_a_test.sql", "0002_b.sql"]), 2)

    def test_duplicates(self):
        with self.assertRaisesRegex(ValueError, "duplicate migration ID"):
            validate_pair(["0001_a.sql", "0001_b.sql"], ["0001_a.sql"])
        with self.assertRaisesRegex(ValueError, "duplicate migration ID"):
            validate_pair(["0001_a.sql"], ["0001_a.sql", "0001_b.sql"])

    def test_missing_or_invalid(self):
        for bad in ([], ["0000_a.sql"], ["0002_a.sql"], ["0001_a.sql", "0003_b.sql"], ["1_a.sql"], ["0001_A.sql"]):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                validate(bad, "fixture")

    def test_pair_mismatch(self):
        with self.assertRaisesRegex(ValueError, "same numeric ID"):
            validate_pair(["0001_a.sql", "0002_b.sql"], ["0001_a.sql"])

if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(GuardTests)
    if not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful():
        sys.exit(1)
    root = Path(__file__).resolve().parent
    try:
        count = validate_pair(
            [p.name for p in (root / "migrations").iterdir() if p.is_file() and p.suffix.lower() == ".sql"],
            [p.name for p in (root / "tests").iterdir() if p.is_file() and p.suffix.lower() == ".sql"],
        )
    except ValueError as error:
        sys.exit(str(error))
    print(f"Migration ID guard: {count} unique contiguous migration/test pairs")
