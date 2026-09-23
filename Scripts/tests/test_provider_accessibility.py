import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "provider_ax", Path(__file__).resolve().parents[1] / "test-provider-accessibility.py"
)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class ReportGateTests(unittest.TestCase):
    def success(self):
        return {"exitCode": 0, "status": "passed", "reason": "ok", "stage": "step_5",
                "steps": [{"index": i} for i in range(1, 6)],
                "cleanup": "terminated_owned_target"}

    def negative(self):
        return dict(self.success(), exitCode=1, status="failed", reason="wait_timeout", stage="step_6")

    def test_complete_success(self):
        gate.verify_report(self.success(), 0, 5, None)

    def test_result_failure_after_callback_is_expected(self):
        gate.verify_report(self.negative(), 1, 6, "step_6")

    def test_missing_steps_and_cleanup_are_failures(self):
        for change in [{"steps": []}, {"steps": [{"index": i} for i in [1, 2, 3, 4, 4]]},
                       {"cleanup": "target_refused_termination"}, {"exitCode": 1},
                       {"reason": "foreground_changed"}, {"status": "failed"}, {"stage": "target"}]:
            with self.subTest(change=change), self.assertRaises(RuntimeError):
                gate.verify_report(dict(self.success(), **change), 0, 5, None)

    def test_unexpected_process_exit_is_not_a_pass(self):
        with self.assertRaises(RuntimeError):
            gate.verify_report(self.success(), 1, 5, None)

    def test_negative_control_rejects_environment_or_earlier_failure(self):
        for change in [{"reason": "accessibility_permission_required"}, {"stage": "step_3"},
                       {"steps": []}, {"cleanup": "target_refused_termination"},
                       {"reason": "foreground_changed"}]:
            with self.subTest(change=change), self.assertRaises(RuntimeError):
                gate.verify_report(dict(self.negative(), **change), 1, 6, "step_6")

    def test_unexpected_green_negative_control_is_failure(self):
        with self.assertRaises(RuntimeError):
            gate.verify_report(dict(self.success(), stage="step_6"), 0, 6, "step_6")

    def test_every_positive_case_requires_business_result(self):
        scenarios = list(gate.cases())
        self.assertEqual(len(scenarios), len({case[0] for case in scenarios}))
        self.assertIn("history-image", {case[0] for case in scenarios})
        for name, arguments, steps, expected_failure in scenarios:
            with self.subTest(name=name):
                if expected_failure:
                    continue
                if name == "bilingual-descriptions":
                    self.assertEqual(steps, [
                        gate.wait({"AXIdentifier": "bilingual-source"}, "AXDescription", "Original"),
                        gate.wait({"AXIdentifier": "bilingual-translation"}, "AXDescription", "Translation"),
                    ])
                    continue
                if "--history-image" in arguments:
                    self.assertIn(gate.press("View original image"), steps)
                    self.assertIn(gate.press("100% actual size"), steps)
                    self.assertIn(gate.wait(gate.button("Fit to window")), steps)
                    self.assertEqual(steps.count(gate.press("Close")), 2)
                    self.assertEqual(steps[-1], gate.result("AX fixture ready"))
                    continue
                self.assertIn(gate.result(), steps)
                self.assertIn(gate.press("Validate"), steps)


if __name__ == "__main__":
    unittest.main()
