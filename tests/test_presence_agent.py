"""Unit tests for px13-presence-agent's pure policy (decide) and config loading.

Run: python3 -m unittest discover -s tests -v   (from ~/px13-power-plugin)
"""

import importlib.machinery
import importlib.util
import os
import tempfile
import unittest
from dataclasses import replace

HERE = os.path.dirname(os.path.abspath(__file__))
_loader = importlib.machinery.SourceFileLoader(
    "agent", os.path.join(HERE, "..", "bin", "px13-presence-agent"))
_spec = importlib.util.spec_from_loader("agent", _loader)
agent = importlib.util.module_from_spec(_spec)
_loader.exec_module(agent)

Config, Memory, Sensor, decide = agent.Config, agent.Memory, agent.Sensor, agent.decide

CFG = Config(enabled=True, lock=True, lock_after=60, dim=True, dim_after=10,
             dim_level=30, wake_on_return=False)
ACTIVE = Memory(sensor_mode="active")
T0 = 1000.0


def sensor(present=True, attention=True, away_since=0.0, looking_away_since=0.0):
    return Sensor(ready=True, present=present, attention=attention, away_since=away_since,
                  looking_away_since=looking_away_since, mode="active")


class DimTests(unittest.TestCase):
    def test_no_dim_before_timeout_but_deadline_set(self):
        d = decide(T0 + 5, sensor(attention=False, looking_away_since=T0), False, CFG, ACTIVE)
        self.assertEqual(d.actions, [])
        self.assertEqual(d.wake_at, T0 + 10)

    def test_dims_after_timeout_once(self):
        s = sensor(attention=False, looking_away_since=T0)
        d = decide(T0 + 10, s, False, CFG, ACTIVE)
        self.assertEqual(d.actions, ["dim"])
        again = decide(T0 + 20, s, False, CFG, d.memory)
        self.assertEqual(again.actions, [])

    def test_restores_when_attention_returns(self):
        d = decide(T0 + 30, sensor(attention=True), False, CFG, replace(ACTIVE, dimmed=True))
        self.assertEqual(d.actions, ["restore"])
        self.assertFalse(d.memory.dimmed)

    def test_stays_dimmed_when_walking_away(self):
        d = decide(T0 + 30, sensor(present=False, attention=False, away_since=T0 + 25),
                   False, CFG, replace(ACTIVE, dimmed=True))
        self.assertNotIn("restore", d.actions)

    def test_dim_disabled(self):
        d = decide(T0 + 99, sensor(attention=False, looking_away_since=T0), False,
                   replace(CFG, dim=False), ACTIVE)
        self.assertEqual(d.actions, [])


class LockTests(unittest.TestCase):
    def test_locks_after_away_timeout_once_per_absence(self):
        s = sensor(present=False, attention=False, away_since=T0)
        self.assertEqual(decide(T0 + 59, s, False, CFG, ACTIVE).actions, [])
        d = decide(T0 + 60, s, False, CFG, ACTIVE)
        self.assertEqual(d.actions, ["lock"])
        # Still away (and e.g. the user unlocked remotely): don't lock again.
        self.assertEqual(decide(T0 + 200, s, False, CFG, d.memory).actions, [])
        # A new absence locks again.
        s2 = sensor(present=False, attention=False, away_since=T0 + 500)
        self.assertEqual(decide(T0 + 560, s2, False, CFG, d.memory).actions, ["lock"])

    def test_no_lock_while_present(self):
        d = decide(T0 + 999, sensor(present=True, attention=True), False, CFG, ACTIVE)
        self.assertNotIn("lock", d.actions)

    def test_inhibitor_postpones_lock(self):
        s = sensor(present=False, attention=False, away_since=T0)
        d = decide(T0 + 60, s, False, CFG, ACTIVE, inhibited=True)
        self.assertEqual(d.actions, [])
        self.assertEqual(d.wake_at, T0 + 60 + agent.INHIBIT_RETRY)
        later = decide(T0 + 60 + agent.INHIBIT_RETRY, s, False, CFG, d.memory, inhibited=False)
        self.assertEqual(later.actions, ["lock"])

    def test_sensor_not_ready_never_locks(self):
        d = decide(T0 + 999, Sensor(), False, CFG, ACTIVE)
        self.assertEqual(d.actions, [])


class LockedSessionTests(unittest.TestCase):
    def test_locked_puts_sensor_in_standby_and_restores_dim(self):
        d = decide(T0, sensor(), True, CFG, replace(ACTIVE, dimmed=True))
        self.assertIn("sensor:standby", d.actions)
        self.assertIn("restore", d.actions)

    def test_unlock_reactivates_sensor(self):
        d = decide(T0, Sensor(mode="standby"), False, CFG, Memory(sensor_mode="standby"))
        self.assertEqual(d.actions, ["sensor:active"])

    def test_wake_on_return_keeps_sensor_and_wakes_once(self):
        cfg = replace(CFG, wake_on_return=True)
        away = decide(T0, sensor(present=False, attention=False), True, cfg, ACTIVE)
        self.assertEqual(away.actions, [])
        back = decide(T0 + 5, sensor(present=True), True, cfg, away.memory)
        self.assertEqual(back.actions, ["wake"])
        self.assertEqual(decide(T0 + 6, sensor(present=True), True, cfg, back.memory).actions, [])


class DisabledTests(unittest.TestCase):
    def test_disabled_releases_everything(self):
        d = decide(T0, sensor(attention=False, looking_away_since=0), False,
                   replace(CFG, enabled=False), replace(ACTIVE, dimmed=True))
        self.assertEqual(d.actions, ["restore", "sensor:standby"])
        self.assertIsNone(d.wake_at)


class ConfigTests(unittest.TestCase):
    def load(self, text):
        with tempfile.NamedTemporaryFile("w", suffix=".conf", delete=False) as f:
            f.write(text)
        try:
            return agent.load_config(f.name, log=lambda m: None)
        finally:
            os.unlink(f.name)

    def test_defaults_when_missing(self):
        self.assertEqual(agent.load_config("/nonexistent", log=lambda m: None), Config())

    def test_values_clamped(self):
        c = self.load("[presence]\nlock_after = 1\ndim_level = 500\ndim_after = 30\n")
        self.assertEqual((c.lock_after, c.dim_level, c.dim_after), (10, 90, 30))

    def test_garbage_keeps_defaults(self):
        c = self.load("[presence]\nlock = maybe\nlock_after = soon\n")
        self.assertEqual((c.lock, c.lock_after), (Config().lock, Config().lock_after))


if __name__ == "__main__":
    unittest.main()
