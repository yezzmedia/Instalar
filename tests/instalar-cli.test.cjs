const test = require("node:test");
const assert = require("node:assert/strict");

const { loadInstallerHarness } = require("./support/instalar-harness.cjs");

test("parseCliArgs accepts aliases, dry-run, and explicit assignment forms", () => {
  const harness = loadInstallerHarness();
  const options = harness.parseCliArgs([
    "-y",
    "--config=instalar.json",
    "--mode=manual",
    "--preset=full",
    "--dry-run",
    "--log-file=logs/instalar.log",
    "--display-command-output",
    "--skip-boost-install",
    "--allow-delete-any-existing",
    "--continue-on-health-check-failure",
    "--start-server",
    "--verbose",
    "--debug",
  ]);

  assert.equal(options.help, false);
  assert.equal(options.nonInteractive, true);
  assert.equal(options.printPlan, true);
  assert.equal(options.logFile, "logs/instalar.log");
  assert.equal(options.displayCommandOutput, true);
  assert.equal(options.preset, "full");
  assert.equal(options.skipBoostInstall, true);
  assert.equal(options.allowDeleteAnyExisting, true);
  assert.equal(options.continueOnHealthCheckFailure, true);
  assert.equal(options.configPath, "instalar.json");
  assert.equal(options.backup, false);
  assert.equal(options.adminGenerate, false);
  assert.equal(options.mode, "manual");
  assert.equal(options.allowDeleteExisting, false);
  assert.equal(options.startServer, true);
  assert.equal(options.verbose, true);
  assert.equal(options.debug, true);
});

test("parseCliArgs accepts doctor mode", () => {
  const harness = loadInstallerHarness();
  const options = harness.parseCliArgs(["--mode=doctor"]);

  assert.equal(options.mode, "doctor");
});

test("parseCliArgs accepts separated preset values", () => {
  const harness = loadInstallerHarness();
  const options = harness.parseCliArgs(["--preset", "minimal", "--log-file", "instalar.log"]);

  assert.equal(options.preset, "minimal");
  assert.equal(options.logFile, "instalar.log");
});

test("parseCliArgs accepts the display-info alias for command output", () => {
  const harness = loadInstallerHarness();
  const options = harness.parseCliArgs(["--display-info"]);

  assert.equal(options.displayCommandOutput, true);
});

test("parseCliArgs resets invalid modes and emits a warning", () => {
  const harness = loadInstallerHarness();
  const warnings = [];

  harness.setWarn((message) => {
    warnings.push(message);
  });

  const options = harness.parseCliArgs(["--mode=broken"]);

  assert.equal(options.mode, null);
  assert.deepEqual(warnings, ["Invalid --mode value: broken. Use auto, manual, update, or doctor."]);
});
