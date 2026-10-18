#!/usr/bin/env python3
"""Cadence regressions: nominal FPS must not hide missing source frames."""
from pathlib import Path
import runpy
import unittest

measure = runpy.run_path(str(Path(__file__).with_name('check-recording-pacing.py')))['measure']


class RecordingPacingTests(unittest.TestCase):
    def test_continuous_sixty_hz_passes(self):
        self.assertTrue(measure([i / 60 for i in range(61)], [(0, 1)], .05)['passed'])

    def test_periodic_missing_frames_fail_even_with_fast_samples_between(self):
        times = [i / 60 for i in range(61) if not 21 <= i <= 28]
        report = measure(times, [(0, 1)], .05)
        self.assertFalse(report['passed'])
        self.assertEqual(report['gaps_over_limit'], 1)
        self.assertAlmostEqual(report['maximum_gap_ms'], 150)

    def test_idle_holds_outside_motion_are_excluded(self):
        times = [i / 60 for i in range(61)] + [10 + i / 60 for i in range(61)]
        self.assertTrue(measure(times, [(0, 1), (10, 11)], .05)['passed'])

    def test_empty_motion_interval_cannot_pass(self):
        with self.assertRaises(ValueError):
            measure([0, 1], [(2, 3)], .05)


if __name__ == '__main__':
    unittest.main()
