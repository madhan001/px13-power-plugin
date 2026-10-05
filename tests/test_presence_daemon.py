"""Unit tests for px13-presence's sample smoothing (no sensor needed).

Run: python3 -m unittest discover -s tests -v   (from ~/px13-power-plugin)
"""

import importlib.machinery
import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
_loader = importlib.machinery.SourceFileLoader(
    "daemon", os.path.join(HERE, "..", "bin", "px13-presence"))
_spec = importlib.util.spec_from_loader("daemon", _loader)
daemon = importlib.util.module_from_spec(_spec)
_loader.exec_module(daemon)

T0 = 1000.0
STEP = 0.5   # 2 Hz


def sample(present, attention=None, distance=600):
    return {"in_proximity0": int(present), "in_proximity1": distance if present else 0,
            "in_attention": 100 if (present if attention is None else attention) else 0}


def feed(p, samples, start=T0):
    for i, vals in enumerate(samples):
        p.update(vals, start + i * STEP)
    return start + len(samples) * STEP


class DebouncedTests(unittest.TestCase):
    def test_single_blip_ignored(self):
        d = daemon.Debounced(False, samples=2)
        self.assertIsNone(d.feed(True, 1.0))
        self.assertIsNone(d.feed(False, 1.5))
        self.assertIsNone(d.feed(True, 2.0))
        self.assertFalse(d.value)

    def test_change_dated_to_first_sample(self):
        d = daemon.Debounced(False, samples=2)
        d.feed(True, 1.0)
        self.assertEqual(d.feed(True, 1.5), 1.0)
        self.assertTrue(d.value)


class PresenceTests(unittest.TestCase):
    def setUp(self):
        self.p = daemon.Presence()
        self.s = self.p.state

    def test_not_ready_until_warm(self):
        self.p.update(sample(False), T0)
        self.assertFalse(self.s["sensor_ready"])
        self.p.update(sample(False), T0 + STEP)
        self.assertTrue(self.s["sensor_ready"])

    def test_away_clock_restarts_on_reset(self):
        # Time with the sensor off (standby while locked) is not time away.
        self.p.reset()
        self.assertGreater(self.s["away_since"], T0)

    def test_arrival_confirmed_and_dated(self):
        feed(self.p, [sample(True)] * 2)
        self.assertTrue(self.s["present"])
        self.assertTrue(self.s["attention"])
        self.assertEqual(self.s["present_since"], T0)

    def test_attention_blip_while_looking_away(self):
        t = feed(self.p, [sample(True, attention=False)] * 4)
        since = self.s["looking_away_since"]
        t = feed(self.p, [sample(True, attention=True), sample(True, attention=False)], t)
        self.assertFalse(self.s["attention"])
        self.assertEqual(self.s["looking_away_since"], since)

    def test_leaving_clears_attention(self):
        t = feed(self.p, [sample(True)] * 4)
        feed(self.p, [sample(False)] * 2, t)
        self.assertFalse(self.s["present"])
        self.assertFalse(self.s["attention"])
        self.assertEqual(self.s["away_since"], t)
        self.assertIsNone(self.s["distance_mm"])

    def test_distance_hysteresis(self):
        t = feed(self.p, [sample(True, distance=640)] * 2)
        self.assertEqual(self.s["distance_mm"], 650)
        t = feed(self.p, [sample(True, distance=680), sample(True, distance=600)], t)
        self.assertEqual(self.s["distance_mm"], 650)       # jitter: unchanged
        feed(self.p, [sample(True, distance=900)], t)
        self.assertEqual(self.s["distance_mm"], 900)


if __name__ == "__main__":
    unittest.main()
