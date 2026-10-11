#!/usr/bin/env python3
"""Guard the build-only Xenia source repair against checkout writes."""

import tempfile
import unittest
from pathlib import Path

from repair_xobject_ref import TARGET, repair


class RepairXObjectRefTests(unittest.TestCase):
    def test_repairs_only_the_mirror_and_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            mirror = root / "mirror"
            for directory in (source, mirror):
                (directory / TARGET).parent.mkdir(parents=True)
                (directory / TARGET).write_text(
                    "explicit object_ref(const object_ref& right) noexcept {\n"
                    "object_ref(const object_ref<V>& right) noexcept {\n",
                    encoding="utf-8",
                )
            original = (source / TARGET).read_bytes()
            self.assertTrue(repair(source, mirror))
            self.assertFalse(repair(source, mirror))
            self.assertEqual(original, (source / TARGET).read_bytes())
            updated = (mirror / TARGET).read_text(encoding="utf-8")
            self.assertEqual(2, updated.count(": value_(nullptr) {"))
            with self.assertRaises(ValueError):
                repair(source, source)


if __name__ == "__main__":
    unittest.main()
