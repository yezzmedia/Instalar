const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { loadInstallerHarness } = require("./support/instalar-harness.cjs");
const { readInstallerMetadata } = require("./support/instalar-metadata.cjs");

test("runCommand writes plain-text run metadata to the runtime log", async () => {
  const harness = loadInstallerHarness();
  const metadata = readInstallerMetadata();
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "instalar-log-"));
  const logFile = path.join(tempDir, "instalar.log");
  const originalConsoleLog = console.log;

  harness.state.runtime.logFile = logFile;
  harness.state.runtime.logFileWriteFailed = false;
  harness.state.runtime.verbose = false;
  harness.state.runtime.debug = false;
  harness.state.warnings.length = 0;

  harness.initializeRuntimeLog();

  console.log = () => {};
  let success;
  let failure;
  try {
    success = await harness.runCommand("node", ["-e", "console.log('hello from stdout')"], {
      required: true,
    });
    failure = await harness.runCommand(
      "node",
      ["-e", "console.error('boom from stderr'); process.exit(3);"],
      {
        required: false,
        warnOnFailure: true,
      },
    );
  } finally {
    console.log = originalConsoleLog;
  }

  const logContent = fs.readFileSync(logFile, "utf8");

  assert.equal(success.success, true);
  assert.equal(failure.success, false);
  assert.equal(failure.exitCode, 3);
  assert.ok(
    harness.state.warnings.some((message) => message.includes("Command failed and will be skipped")),
  );
  assert.match(
    logContent,
    new RegExp(`INSTALAR ${metadata.version.replaceAll(".", "\\.")} \\(${metadata.codename}\\)`),
  );
  assert.match(logContent, /Run: node -e console\.log\('hello from stdout'\)/);
  assert.match(logContent, /Run: node -e console\.error\('boom from stderr'\); process\.exit\(3\);/);
  assert.match(logContent, /Command failed and will be skipped/);
  assert.equal(/\x1B\[[0-9;?]*[ -/]*[@-~]/.test(logContent), false);
});

test("buildCommandFailureSnippet keeps recent stdout and stderr context readable", () => {
  const harness = loadInstallerHarness();
  const snippet = harness.buildCommandFailureSnippet({
    stdout: "first line\nsecond line\nthird line\n",
    stderr: "broken state\ntrace line\n",
  });

  assert.match(snippet, /Last stdout:/);
  assert.match(snippet, /second line/);
  assert.match(snippet, /third line/);
  assert.match(snippet, /Last stderr:/);
  assert.match(snippet, /broken state/);
  assert.match(snippet, /trace line/);
});

test("shouldDisplayCommandOutput stays quiet by default and opens up for verbose/debug or the explicit flag", () => {
  const harness = loadInstallerHarness();

  assert.equal(
    harness.shouldDisplayCommandOutput(
      { interactive: false, displayCommandOutput: false },
      { displayCommandOutput: false, verbose: false, debug: false },
    ),
    false,
  );
  assert.equal(
    harness.shouldDisplayCommandOutput(
      { interactive: false, displayCommandOutput: false },
      { displayCommandOutput: true, verbose: false, debug: false },
    ),
    true,
  );
  assert.equal(
    harness.shouldDisplayCommandOutput(
      { interactive: false, displayCommandOutput: false },
      { displayCommandOutput: false, verbose: true, debug: false },
    ),
    true,
  );
  assert.equal(
    harness.shouldDisplayCommandOutput(
      { interactive: true, displayCommandOutput: false },
      { displayCommandOutput: false, verbose: false, debug: false },
    ),
    true,
  );
});

test("shouldAnimateCommandActivity only enables the moving bar for quiet TTY runs", () => {
  const harness = loadInstallerHarness();

  harness.process.stdout.isTTY = true;

  assert.equal(
    harness.shouldAnimateCommandActivity(
      { interactive: false, displayCommandOutput: false },
      { displayCommandOutput: false, verbose: false, debug: false },
    ),
    true,
  );
  assert.equal(
    harness.shouldAnimateCommandActivity(
      { interactive: false, displayCommandOutput: false },
      { displayCommandOutput: true, verbose: false, debug: false },
    ),
    false,
  );
  assert.equal(
    harness.shouldAnimateCommandActivity(
      { interactive: false, displayCommandOutput: false },
      { displayCommandOutput: false, verbose: true, debug: false },
    ),
    false,
  );
  assert.equal(
    harness.shouldAnimateCommandActivity(
      { interactive: true, displayCommandOutput: false },
      { displayCommandOutput: false, verbose: false, debug: false },
    ),
    false,
  );

  harness.process.stdout.isTTY = false;
});

test("runPotentiallyInteractiveArtisanCommand switches to visible interactive mode", async () => {
  const harness = loadInstallerHarness();
  const infos = [];
  const calls = [];

  harness.state.runtime.nonInteractive = false;
  harness.setInfo((message) => {
    infos.push(message);
  });
  harness.setRunArtisanIfAvailable(async (projectDir, commandName, args, messageIfMissing, options) => {
    calls.push({ projectDir, commandName, args, messageIfMissing, options });
    return true;
  });

  const result = await harness.runPotentiallyInteractiveArtisanCommand(
    "/tmp/demo-project",
    "reverb:install",
    [],
    "reverb:install not available, skipping.",
    {
      interactiveNotice: "Reverb install may ask interactive questions.",
      skipMessage: "should not be used",
    },
  );

  assert.equal(result, true);
  assert.deepEqual(infos, ["Reverb install may ask interactive questions."]);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].commandName, "reverb:install");
  assert.equal(calls[0].messageIfMissing, "reverb:install not available, skipping.");
  assert.equal(calls[0].options.interactive, true);
  assert.equal(calls[0].options.captureOutput, false);
  assert.equal(calls[0].options.displayCommandOutput, true);
});

test("runPotentiallyInteractiveArtisanCommand skips and records a manual step in non-interactive mode", async () => {
  const harness = loadInstallerHarness();
  const warnings = [];

  harness.state.runtime.nonInteractive = true;
  harness.state.finalWarnings = [];
  harness.setWarn((message) => {
    warnings.push(message);
  });
  harness.setRunArtisanIfAvailable(async () => {
    throw new Error("runArtisanIfAvailable should not be called in non-interactive mode");
  });

  const result = await harness.runPotentiallyInteractiveArtisanCommand(
    "/tmp/demo-project",
    "modules:install",
    [],
    "modules:install not available, skipping.",
    {
      skipMessage:
        "Skipping modules:install in non-interactive mode. Run 'php artisan modules:install' manually.",
    },
  );

  assert.equal(result, false);
  assert.deepEqual(warnings, [
    "Skipping modules:install in non-interactive mode. Run 'php artisan modules:install' manually.",
  ]);
  assert.deepEqual(harness.state.finalWarnings, [
    "Skipping modules:install in non-interactive mode. Run 'php artisan modules:install' manually.",
  ]);
});

test("runCommand attaches a recovery summary to required command failures", async () => {
  const harness = loadInstallerHarness();
  const originalConsoleLog = console.log;

  console.log = () => {};
  try {
    await assert.rejects(
      async () => {
        await harness.runCommand("npm", ["run", "build"], {
          required: true,
        });
      },
      (error) => {
        assert.equal(error.failureSummary.title, "npm Failure");
        assert.ok(error.failureSummary.nextSteps.includes("npm install"));
        assert.ok(error.failureSummary.nextSteps.includes("npm run build"));
        assert.match(error.message, /Command failed \(exit \d+\): npm run build/);
        return true;
      },
    );
  } finally {
    console.log = originalConsoleLog;
  }
});
