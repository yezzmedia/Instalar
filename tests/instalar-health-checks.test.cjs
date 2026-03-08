const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {
  createProjectFixture,
  loadInstallerHarness,
} = require("./support/instalar-harness.cjs");

function createHealthCheckHarness(runtimeOverrides = {}) {
  const harness = loadInstallerHarness();
  const events = {
    failures: [],
    infos: [],
    oks: [],
    prompts: [],
    warnings: [],
  };

  harness.state.runtime = {
    nonInteractive: false,
    continueOnHealthCheckFailure: false,
    ...runtimeOverrides,
  };
  harness.setSection(() => {});
  harness.setInfo((message) => {
    events.infos.push(message);
  });
  harness.setWarn((message) => {
    events.warnings.push(message);
  });
  harness.setOk((message) => {
    events.oks.push(message);
  });
  harness.setFail((message) => {
    events.failures.push(message);
  });

  return { events, harness };
}

test("runHealthChecks aborts non-interactive runs when a final artisan check fails", async () => {
  const { events, harness } = createHealthCheckHarness({ nonInteractive: true });
  const projectPath = createProjectFixture();

  harness.setAskYesNo(async () => {
    throw new Error("askYesNo should not be called in non-interactive mode");
  });
  harness.setRunCommand(async (command, args) => {
    if (command === "composer" && args[0] === "validate") {
      return { exitCode: 0, success: true };
    }

    if (command === "php" && args[0] === "artisan" && args[1] === "about") {
      return { exitCode: 1, success: false };
    }

    return { exitCode: 0, success: true };
  });

  await assert.rejects(harness.runHealthChecks(projectPath, harness.state.runtime), /EXIT:1/);
  assert.deepEqual(events.failures, [
    "Health check failed for: php artisan about",
    "Installation aborted because health checks failed in non-interactive mode.",
  ]);
});

test("runHealthChecks can continue a non-interactive run when the override is enabled", async () => {
  const { events, harness } = createHealthCheckHarness({
    nonInteractive: true,
    continueOnHealthCheckFailure: true,
  });
  const projectPath = createProjectFixture();

  harness.setAskYesNo(async () => {
    throw new Error("askYesNo should not be called when the override is enabled");
  });
  harness.setRunCommand(async (command, args) => {
    if (command === "composer" && args[0] === "validate") {
      return { exitCode: 0, success: true };
    }

    if (command === "php" && args[0] === "artisan" && args[1] === "route:list") {
      return { exitCode: 1, success: false };
    }

    return { exitCode: 0, success: true };
  });

  await harness.runHealthChecks(projectPath, harness.state.runtime);

  assert.deepEqual(events.failures, ["Health check failed for: php artisan route:list"]);
  assert.deepEqual(events.warnings, [
    "Route list check failed",
    "Continuing because health-check override is enabled for non-interactive mode.",
  ]);
});

test("runHealthChecks prompts interactively when a final artisan check fails", async () => {
  const { events, harness } = createHealthCheckHarness();
  const projectPath = createProjectFixture();

  harness.setAskYesNo(async (question, defaultYes) => {
    events.prompts.push({ question, defaultYes });
    return true;
  });
  harness.setRunCommand(async (command, args) => {
    if (command === "composer" && args[0] === "validate") {
      return { exitCode: 0, success: true };
    }

    if (command === "php" && args[0] === "artisan" && args[1] === "route:list") {
      return { exitCode: 1, success: false };
    }

    return { exitCode: 0, success: true };
  });

  await harness.runHealthChecks(projectPath, harness.state.runtime);

  assert.deepEqual(events.failures, ["Health check failed for: php artisan route:list"]);
  assert.deepEqual(events.prompts, [
    { question: "Do you want to continue anyway?", defaultYes: false },
  ]);
});

test("runHealthChecks succeeds cleanly when all checks pass", async () => {
  const { events, harness } = createHealthCheckHarness({ nonInteractive: true });
  const projectPath = createProjectFixture();

  harness.setAskYesNo(async () => {
    throw new Error("askYesNo should not be called for a clean run");
  });
  harness.setRunCommand(async () => ({ exitCode: 0, success: true }));

  await harness.runHealthChecks(projectPath, harness.state.runtime);

  assert.deepEqual(events.failures, []);
  assert.deepEqual(events.warnings, []);
  assert.ok(events.oks.includes("APP_KEY is set"));
  assert.ok(events.oks.includes("Storage link exists"));
  assert.ok(events.oks.includes("Composer.json is valid"));
});

test("runHealthChecks retries storage:link interactively before succeeding", async () => {
  const { events, harness } = createHealthCheckHarness();
  const projectPath = createProjectFixture();
  const storageLinkPath = path.join(projectPath, "public", "storage");
  const calls = [];
  let storageAttempts = 0;

  fs.unlinkSync(storageLinkPath);

  harness.setAskYesNo(async (question, defaultYes) => {
    events.prompts.push({ question, defaultYes });
    return true;
  });
  harness.setRunCommand(async (command, args) => {
    calls.push([command, ...args].join(" "));

    if (command === "composer" && args[0] === "validate") {
      return { exitCode: 0, success: true };
    }

    if (command === "php" && args[0] === "artisan" && args[1] === "storage:link") {
      storageAttempts += 1;
      if (storageAttempts === 1) {
        return { exitCode: 1, success: false };
      }

      fs.symlinkSync(
        path.join(projectPath, "storage", "app", "public"),
        storageLinkPath,
      );

      return { exitCode: 0, success: true };
    }

    return { exitCode: 0, success: true };
  });

  await harness.runHealthChecks(projectPath, harness.state.runtime);

  assert.equal(storageAttempts, 2);
  assert.deepEqual(events.failures, []);
  assert.deepEqual(events.prompts, [{ question: "Try again?", defaultYes: false }]);
  assert.ok(calls.includes("php artisan storage:link --no-interaction"));
  assert.ok(events.oks.includes("Storage link created successfully"));
});
