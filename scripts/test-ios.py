#!/usr/bin/env python3
"""Repeatable model tests and simulator UI tests.

No tap is simulated as a processor integration test. UI runs use the demo's
mock service and never submit payments.
"""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


def run(command, log):
    print(f"Running {command[0]} {command[1]}", flush=True)
    with log.open("a") as output:
        subprocess.run(command, check=True, stdout=output, stderr=subprocess.STDOUT)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--scheme", default="Koard Demo (UAT)")
    parser.add_argument("--simulator-id", required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--only-testing", help="Optional XCTest test identifier, for focused phone or tablet runs")
    args = parser.parse_args()
    repository = Path(__file__).resolve().parents[1]
    platform = repository / ("swift" if (repository / "swift").exists() else "ios")
    app_source = platform / "KoardMerchantSDK-Demo"
    output = args.output or Path(tempfile.mkdtemp(prefix="koard-ios-tests-"))
    output.mkdir(parents=True, exist_ok=True)
    os.chmod(output, 0o700)
    print(f"Test artifacts: {output}", flush=True)
    models = output / "models"
    (models / "Sources/RegisterModels").mkdir(parents=True, exist_ok=True)
    (models / "Tests/RegisterModelsTests").mkdir(parents=True, exist_ok=True)
    (models / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "RegisterModels", platforms: [.macOS(.v14)], targets: [
    .target(name: "RegisterModels"),
    .testTarget(name: "RegisterModelsTests", dependencies: ["RegisterModels"])
])
''')
    for source in [app_source / "Demo/POS/POSCart.swift", app_source / "Demo/PinPad/PinPadAmountFormatter.swift", app_source / "Demo/Transaction Details/TransactionAmountInput.swift"]:
        shutil.copy2(source, models / "Sources/RegisterModels" / source.name)
    shutil.copy2(platform / "Tests/POSCartTests.swift", models / "Tests/RegisterModelsTests/POSCartTests.swift")
    run(["swift", "test", "--package-path", str(models)], output / "models.log")
    destination = f"id={args.simulator_id}"
    run(["xcrun", "simctl", "bootstatus", args.simulator_id, "-b"], output / "build.log")
    derived = output / "build"
    run(["xcodebuild", "-project", str(platform / "KoardDemo.xcodeproj"), "-scheme", args.scheme,
         "-destination", destination, "-derivedDataPath", str(derived), "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "build"], output / "build.log")
    apps = list((derived / "Build/Products").glob("*-iphonesimulator/Koard Demo.app"))
    if len(apps) != 1:
        raise RuntimeError("Expected one built demo app")
    app = apps[0]
    with (app / "Info.plist").open("rb") as source:
        app_id = plistlib.load(source)["CFBundleIdentifier"]
    run(["xcrun", "simctl", "install", args.simulator_id, str(app)], output / "build.log")
    test_build = output / "ui-build"
    run(["xcodebuild", "-project", str(platform / "Tests/StandardDemoUITests.xcodeproj"),
         "-scheme", "StandardDemoUITests", "-destination", destination, "-derivedDataPath", str(test_build),
         "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "build-for-testing"], output / "build.log")
    environment = {"KOARD_TEST_APP_ID": app_id}
    xctestrun = next((test_build / "Build/Products").glob("*.xctestrun"))
    with xctestrun.open("rb") as source:
        settings = plistlib.load(source)

    def configure(value):
        if isinstance(value, dict):
            if "TestBundlePath" in value:
                value.setdefault("EnvironmentVariables", {}).update(environment)
                value.setdefault("TestEnvironmentVariables", {}).update(environment)
            for child in value.values():
                configure(child)
        elif isinstance(value, list):
            for child in value:
                configure(child)

    configure(settings)
    private_run = xctestrun.with_name("StandardDemo.private.xctestrun")
    with private_run.open("wb") as target:
        plistlib.dump(settings, target)
    os.chmod(private_run, 0o600)
    try:
        run(["xcodebuild", "-xctestrun", str(private_run), "-destination", destination,
             "-parallel-testing-enabled", "NO", "-resultBundlePath", str(output / "ui.xcresult"),
             "test-without-building"] + (["-only-testing:" + args.only_testing] if args.only_testing else []), output / "ui.log")
    finally:
        private_run.unlink(missing_ok=True)
    print("Model and simulator UI tests passed. NFC requires physical devices.", flush=True)


if __name__ == "__main__":
    main()
