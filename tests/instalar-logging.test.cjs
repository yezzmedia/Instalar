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
