const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { loadInstallerHarness } = require("./support/instalar-harness.cjs");

test("runtime options merge the health-check override from CLI and JSON config", () => {
  const harness = loadInstallerHarness();

  const cliOptions = harness.parseCliArgs([
    "--non-interactive",
    "--print-plan",
    "--preset",
    "full",
    "--allow-delete-any-existing",
    "--continue-on-health-check-failure",
  ]);
  const cliRuntime = harness.resolveRuntime(cliOptions, {}, null);

  assert.equal(cliOptions.continueOnHealthCheckFailure, true);
  assert.equal(cliRuntime.nonInteractive, true);
  assert.equal(cliRuntime.printPlan, true);
  assert.equal(cliRuntime.preset, "full");
  assert.equal(cliRuntime.allowDeleteAnyExisting, true);
  assert.equal(cliRuntime.continueOnHealthCheckFailure, true);
  assert.equal(cliRuntime.skipBoostInstall, true);

  const configRuntime = harness.resolveRuntime(
    harness.parseCliArgs(["--non-interactive"]),
    {
      continueOnHealthCheckFailure: true,
      preset: "minimal",
      printPlan: true,
    },
    "/tmp/instalar.json",
  );

  assert.equal(configRuntime.continueOnHealthCheckFailure, true);
  assert.equal(configRuntime.printPlan, true);
  assert.equal(configRuntime.preset, "minimal");
  assert.equal(configRuntime.skipBoostInstall, true);
  assert.equal(configRuntime.configPath, "/tmp/instalar.json");
});

test("runtime resolves dry-run aliases and log files from CLI and config", () => {
  const harness = loadInstallerHarness();

  const cliRuntime = harness.resolveRuntime(
    harness.parseCliArgs(["--dry-run", "--log-file", "logs/installer.log"]),
    {},
    null,
  );

  assert.equal(cliRuntime.printPlan, true);
  assert.equal(cliRuntime.logFile, path.resolve(process.cwd(), "logs/installer.log"));

  const configRuntime = harness.resolveRuntime(
    harness.parseCliArgs([]),
    {
      dryRun: true,
      logFile: "./logs/config-instalar.log",
    },
    "/tmp/instalar/config/instalar.json",
  );

  assert.equal(configRuntime.printPlan, true);
  assert.equal(
    configRuntime.logFile,
    path.resolve("/tmp/instalar/config", "logs/config-instalar.log"),
  );
});

test("runtime prefers explicit CLI mode and preserves other config flags", () => {
  const harness = loadInstallerHarness();

  const runtime = harness.resolveRuntime(
    harness.parseCliArgs(["--mode", "update", "--verbose"]),
    {
      mode: "manual",
      debug: true,
      backup: true,
    },
    "/tmp/instalar.json",
  );

  assert.equal(runtime.mode, "update");
  assert.equal(runtime.verbose, true);
  assert.equal(runtime.debug, true);
  assert.equal(runtime.backup, true);
});

test("runtime accepts doctor mode from config and preserves supported runtime flags", () => {
  const harness = loadInstallerHarness();

  const runtime = harness.resolveRuntime(
    harness.parseCliArgs(["--log-file", "doctor.log"]),
    {
      mode: "doctor",
      dryRun: true,
      verbose: true,
    },
    "/tmp/instalar.json",
  );

  assert.equal(runtime.mode, "doctor");
  assert.equal(runtime.printPlan, true);
  assert.equal(runtime.verbose, true);
  assert.equal(runtime.logFile, path.resolve(process.cwd(), "doctor.log"));
});

test("runtime falls back to the standard preset when config requests an invalid preset", () => {
  const harness = loadInstallerHarness();
  const warnings = [];

  harness.setWarn((message) => {
    warnings.push(message);
  });

  const runtime = harness.resolveRuntime(
    harness.parseCliArgs([]),
    { preset: "enterprise" },
    null,
  );

  assert.equal(runtime.preset, "standard");
  assert.deepEqual(warnings, ["Invalid package preset: enterprise. Falling back to standard."]);
});

test("runtime keeps boost install enabled for interactive runs unless explicitly skipped", () => {
  const harness = loadInstallerHarness();

  const defaultRuntime = harness.resolveRuntime(harness.parseCliArgs([]), {}, null);
  const configRuntime = harness.resolveRuntime(
    harness.parseCliArgs([]),
    { skipBoostInstall: true },
    null,
  );

  assert.equal(defaultRuntime.nonInteractive, false);
  assert.equal(defaultRuntime.skipBoostInstall, false);
  assert.equal(configRuntime.skipBoostInstall, true);
});

test("validateInstallerConfig rejects unknown keys and invalid nested values", () => {
  const harness = loadInstallerHarness();

  assert.throws(
    () => harness.validateInstallerConfig({ mysteryFlag: true }),
    /Unknown configuration key: config\.mysteryFlag/,
  );
  assert.throws(
    () => harness.validateInstallerConfig({ database: { connection: "mongo" } }),
    /config\.database\.connection must be sqlite, mysql, or pgsql/,
  );
  assert.doesNotThrow(() => harness.validateInstallerConfig({ mode: "doctor" }));
  assert.throws(
    () => harness.validateInstallerConfig({ manual: { preset: "enterprise" } }),
    /config\(?.*?\.manual\.preset must be minimal, standard, or full|config\.manual\.preset must be minimal, standard, or full/,
  );
  assert.throws(
    () => harness.validateInstallerConfig({ logFile: "" }),
    /config\.logFile must not be empty/,
  );
  assert.throws(
    () => harness.validateInstallerConfig({ dryRun: "yes" }),
    /config\.dryRun must be a boolean/,
  );
});

test("embedded node phase receives release metadata from the bash entrypoint", () => {
  const installerPath = path.join(__dirname, "..", "instalar.sh");
  const installerSource = fs.readFileSync(installerPath, "utf8");

  assert.match(
    installerSource,
    /const SCRIPT_VERSION = process\.env\.INSTALAR_SCRIPT_VERSION \|\| "0\.0\.0";/,
  );
  assert.match(
    installerSource,
    /const SCRIPT_CODENAME = process\.env\.INSTALAR_SCRIPT_CODENAME \|\| "Unknown";/,
  );
  assert.match(
    installerSource,
    /INSTALAR_SCRIPT_VERSION="\$\{SCRIPT_VERSION\}" INSTALAR_SCRIPT_CODENAME="\$\{SCRIPT_CODENAME\}"[^\n]*\\\n\s*node "\$\{NODE_TMP\}"/,
  );
});

test("main prints the grouped manual dry-run review from config in non-interactive mode", async () => {
  const harness = loadInstallerHarness();
  const configDir = fs.mkdtempSync(path.join(os.tmpdir(), "instalar-main-"));
  const configPath = path.join(configDir, "instalar.json");
  const sections = [];
  const subsections = [];
  const details = [];
  const oks = [];

  fs.writeFileSync(
    configPath,
    `${JSON.stringify(
      {
        mode: "manual",
        projectName: "CLI Review App",
        projectPath: "./cli-review-app",
        database: {
          connection: "sqlite",
        },
        preset: "standard",
        createAdmin: false,
        gitInit: false,
      },
      null,
      2,
    )}\n`,
    "utf8",
  );

  harness.process.argv = [
    "node",
    "instalar.sh",
    "--mode",
    "manual",
    "--non-interactive",
    "--dry-run",
    "--config",
    configPath,
  ];
  harness.setSection((title) => {
    sections.push(title);
  });
  harness.setSubsection((title) => {
    subsections.push(title);
  });
  harness.setDetail((message) => {
    details.push(message);
  });
  harness.setInfo(() => {});
  harness.setOk((message) => {
    oks.push(message);
  });

  await harness.main();

  assert.deepEqual(sections, [
    "Step 1/6 - Project Basics",
    "Step 2/6 - Database",
    "Step 3/6 - Laravel Starter",
    "Step 4/6 - Packages",
    "Step 5/6 - Admin and Git",
    "Installation Plan",
  ]);
  assert.deepEqual(subsections, [
    "Project",
    "Database",
    "Starter",
    "Packages",
    "Normal Packages",
    "Dev Packages",
    "Admin and Git",
    "Runtime",
  ]);
  assert.ok(details.some((message) => /Name:\s+CLI Review App$/.test(message)));
  assert.ok(oks.includes("Plan preview only. No project files will be modified."));
});
