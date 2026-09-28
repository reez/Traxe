"""Exercise capture orchestration without launching Xcode or producing real images."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


class ScreenshotCaptureTests(unittest.TestCase):
    def test_isolation_output_discovery_and_failures(self):
        repo = Path(__file__).resolve().parents[1]
        script = repo / "scripts/capture_app_store_screenshots.sh"
        with tempfile.TemporaryDirectory(prefix="traxe-capture-script-") as temporary:
            root = Path(temporary)
            binaries = root / "bin"
            binaries.mkdir()
            trace = root / "calls.jsonl"
            xcode = binaries / "xcodebuild"
            xcode.write_text("#!" + sys.executable + "\n" + textwrap.dedent('''\
                import json, os, pathlib, sys
                if sys.argv[1:] == ["-version"]:
                    print("Xcode 27.0")
                    raise SystemExit(0)
                args = sys.argv[1:]
                with open(os.environ["CAPTURE_TRACE"], "a") as trace:
                    trace.write(json.dumps({"tool": "xcode", "args": args}) + "\\n")
                output = pathlib.Path(os.environ["TEST_RUNNER_TRAXE_SCREENSHOT_OUTPUT_DIR"])
                derived = pathlib.Path(args[args.index("-derivedDataPath") + 1])
                derived.mkdir(parents=True, exist_ok=True)
                (derived / "build-marker").write_text("build")
                if os.environ.get("CAPTURE_FAIL"):
                    raise SystemExit(65)
                selected = next(a.split(":", 1)[1] for a in args if a.startswith("-only-testing:"))
                if not selected.endswith("testRenderLandscapeAndLiveResizeScreenshots"):
                    portrait = output / "Traxe-portrait"
                    portrait.mkdir()
                    (portrait / "01_fleet-dashboard.png").write_text("test fixture")
                    for index in range(2, 8):
                        (portrait / f"{index:02}_portrait.png").write_text("test fixture")
                if not selected.endswith("testRenderAppStoreScreenshots"):
                    layout = output / "Traxe-layout"
                    layout.mkdir()
                    for index in range(13):
                        (layout / f"layout-{index}.png").write_text("test fixture")
                '''))
            asc = binaries / "asc"
            asc.write_text("#!" + sys.executable + "\n" + textwrap.dedent('''\
                import json, os, sys
                with open(os.environ["CAPTURE_TRACE"], "a") as trace:
                    trace.write(json.dumps({"tool": "asc", "args": sys.argv[1:]}) + "\\n")
                '''))
            xcrun = binaries / "xcrun"
            xcrun.write_text("#!" + sys.executable + "\n" + textwrap.dedent('''\
                import json, os, sys
                args = sys.argv[1:]
                with open(os.environ["CAPTURE_TRACE"], "a") as trace:
                    trace.write(json.dumps({"tool": "xcrun", "args": args}) + "\\n")
                if args == ["simctl", "list", "-j"]:
                    print(json.dumps({"devicetypes": [{"name": "iPhone 17 Pro Max", "identifier": "device-type"}],
                        "runtimes": [{"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5", "version": "26.5", "buildversion": "23F77", "isAvailable": True},
                                     {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-28-0", "version": "28.0", "buildversion": "25A123", "isAvailable": True}]}))
                elif args[:2] == ["simctl", "create"]:
                    print("owned-simulator")
                '''))
            for executable in (xcode, asc, xcrun):
                executable.chmod(0o755)
            output = root / "existing captures"
            output.mkdir()
            sentinel = output / "original.png"
            sentinel.write_bytes(b"keep original")
            environment = os.environ.copy()
            for key in ("RAW_DIR", "FRAMED_DIR", "REVIEW_DIR", "DERIVED_DATA_PATH", "SOURCE_PACKAGES_DIR", "RENDER_TEST", "CAPTURE_FAIL"):
                environment.pop(key, None)
            environment.update(PATH=str(binaries) + os.pathsep + environment["PATH"],
                               RAW_DIR=str(output), UDID="task-simulator", FRAME_ENABLED="0",
                               VALIDATE="1", CAPTURE_TRACE=str(trace))
            for selection, expected in (("testRenderAppStoreScreenshots", 7),
                                        ("testRenderLandscapeAndLiveResizeScreenshots", 13), ("", 20)):
                selected = "TraxeTests/AppStoreScreenshotRenderTests" + ("/" + selection if selection else "")
                result = subprocess.run(["bash", str(script)], env={**environment, "RENDER_TEST": selected},
                                        capture_output=True, text=True, timeout=60)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                raw = Path(next(line.removeprefix("Raw screenshots: ") for line in result.stdout.splitlines()
                                if line.startswith("Raw screenshots: ")))
                self.assertEqual(len(list(raw.rglob("*.png"))), expected)
                self.assertFalse((raw.parent / "DerivedData").exists())
                self.assertEqual(sentinel.read_bytes(), b"keep original")
            self.assertEqual(len(list(output.glob("Traxe-screenshots.*"))), 3)
            calls = [json.loads(line) for line in trace.read_text().splitlines()]
            validations = [call for call in calls if call["tool"] == "asc"]
            self.assertEqual(len(validations), 2)
            for call in validations:
                validated = Path(call["args"][call["args"].index("--path") + 1])
                self.assertEqual(validated.name, "Traxe-portrait")
            self.assertFalse(any(call["tool"] == "xcrun" for call in calls))

            link = root / "repository-link"
            link.symlink_to(repo, target_is_directory=True)
            for path in (str(repo), str(link / "rejected-output"), "relative-output"):
                before = trace.read_bytes()
                result = subprocess.run(["bash", str(script)], env={**environment, "RAW_DIR": path},
                                        capture_output=True, text=True, timeout=60)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(trace.read_bytes(), before)
            self.assertFalse((repo / "rejected-output").exists())

            result = subprocess.run(["bash", str(script)],
                                    env={**environment, "UDID": "", "CAPTURE_FAIL": "1"},
                                    capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 65)
            self.assertEqual(sentinel.read_bytes(), b"keep original")
            calls = [json.loads(line) for line in trace.read_text().splitlines()]
            created = next(call for call in calls if call["tool"] == "xcrun" and call["args"][:2] == ["simctl", "create"])
            self.assertEqual(created["args"][-1], "com.apple.CoreSimulator.SimRuntime.iOS-26-5")
            self.assertEqual(calls[-1], {"tool": "xcrun", "args": ["simctl", "delete", "owned-simulator"]})
            self.assertFalse(list(output.glob("Traxe-screenshots.*/DerivedData")))


if __name__ == "__main__":
    unittest.main()
