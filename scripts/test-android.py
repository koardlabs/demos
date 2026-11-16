#!/usr/bin/env python3
"""Run Android unit tests and the non-NFC UI tests on an emulator."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile


def execute(command, log, environment=None):
    with log.open("a") as output:
        result = subprocess.run(command, env=environment, stdout=output, stderr=subprocess.STDOUT, timeout=900 if "gradlew" in command[0] else 180)
    if result.returncode:
        raise RuntimeError(f"{command[0]} failed. See {log}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--serial", required=True)
    parser.add_argument("--variant", default="UatDebug")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    repository = Path(__file__).resolve().parents[1]
    internal = (repository / "kotlin").exists()
    platform = repository / ("kotlin" if internal else "android")
    sdk = Path(os.environ.get("ANDROID_HOME", Path.home() / "Library/Android/sdk"))
    adb = str(sdk / "platform-tools/adb")
    environment = os.environ.copy()
    environment.setdefault("JAVA_HOME", "/Applications/Android Studio.app/Contents/jbr/Contents/Home")
    output = args.output or Path(tempfile.mkdtemp(prefix="koard-android-tests-"))
    output.mkdir(parents=True, exist_ok=True)
    os.chmod(output, 0o700)
    print(f"Test artifacts: {output}", flush=True)
    module = ":app:" if internal else ":"
    execute([str(platform / "gradlew"), "-p", str(platform), module + "test" + args.variant + "UnitTest",
             module + "assemble" + args.variant, module + "assemble" + args.variant + "AndroidTest",
             "--no-daemon", "--console=plain"], output / "build.log", environment)
    build = platform / ("app/build" if internal else "build")
    flavor = args.variant[:-5].lower()
    metadata = json.loads((build / f"outputs/apk/{flavor}/debug/output-metadata.json").read_text())
    test_metadata_path = build / f"outputs/apk/androidTest/{flavor}/debug/output-metadata.json"
    test_metadata = json.loads(test_metadata_path.read_text())
    package = metadata["applicationId"]
    apk = build / f"outputs/apk/{flavor}/debug" / metadata["elements"][0]["outputFile"]
    test_apk = test_metadata_path.parent / test_metadata["elements"][0]["outputFile"]
    prefix = [adb, "-s", args.serial]
    execute(prefix + ["wait-for-device"], output / "ui.log")
    execute(prefix + ["install", "-r", str(apk)], output / "ui.log")
    execute(prefix + ["install", "-r", str(test_apk)], output / "ui.log")
    test_package = test_metadata["applicationId"]
    namespace = "com.koard.demo" if internal else "com.koard.android"

    def instrument(test_class, extras=()):
        command = prefix + ["shell", "am", "instrument", "-w", "-r", "-e", "class", test_class]
        command.extend(extras)
        command.append(test_package + "/androidx.test.runner.AndroidJUnitRunner")
        log = output / (test_class.rsplit(".", 1)[-1] + ".log")
        execute(command, log)
        result = log.read_text()
        if "FAILURES!!!" in result or "INSTRUMENTATION_FAILED" in result or "OK (" not in result:
            raise RuntimeError(f"Instrumentation did not pass. See {log}")

    instrument(namespace + ".StandardDemoUiTest")
    if not internal:
        execute(prefix + ["shell", "pm", "clear", package], output / "ui.log")
        instrument(namespace + ".StandardDemoStartupTest")
    print("Android unit and non-NFC UI tests passed.", flush=True)


if __name__ == "__main__":
    main()
