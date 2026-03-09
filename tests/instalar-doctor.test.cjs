const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const {
  createProjectFixture,
  loadInstallerHarness,
} = require("./support/instalar-harness.cjs");

function createDoctorHarness(runtimeOverrides = {}) {
  const harness = loadInstallerHarness();
  const events = {
    details: [],
    failures: [],
    infos: [],
    oks: [],
    prompts: [],
    sections: [],
    subsections: [],
    warnings: [],
  };

  harness.state.runtime = {
    nonInteractive: false,
    printPlan: false,
    logFile: null,
    ...runtimeOverrides,
  };
  harness.state.warnings.length = 0;
  harness.setSection((title) => {
    events.sections.push(title);
  });
  harness.setSubsection((title) => {
    events.subsections.push(title);
  });
  harness.setDetail((message) => {
    events.details.push(message);
  });
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

test("warnDoctorModeIgnoredOptions reports install-only CLI options and config keys", () => {
  const { events, harness } = createDoctorHarness();

  harness.warnDoctorModeIgnoredOptions(
    {
      preset: "full",
      skipBoostInstall: true,
      continueOnHealthCheckFailure: true,
      startServer: true,
    },
    {
      projectPath: "./demo-app",
      optionalPackageIds: ["fortify"],
      admin: { email: "admin@example.com" },
      update: { preset: "minimal" },
    },
  );

  assert.deepEqual(events.warnings, [
    "Doctor mode ignores install-only CLI options: --preset, --skip-boost-install, --continue-on-health-check-failure, --start-server.",
    "Doctor mode ignores install-only config keys: projectPath, optionalPackageIds, admin, update.",
  ]);
});

test("runDoctorFlow rejects non-Laravel directories", async () => {
  const { harness } = createDoctorHarness();
  const projectPath = fs.mkdtempSync(path.join(os.tmpdir(), "instalar-doctor-empty-"));

  await assert.rejects(
    harness.runDoctorFlow(projectPath, harness.state.runtime),
    /Doctor mode requires a Laravel project in the current directory/,
  );
});

test("runDoctorFlow succeeds when health and permission checks pass", async () => {
  const { events, harness } = createDoctorHarness();
  const projectPath = createProjectFixture();

  harness.setAskYesNo(async () => {
    throw new Error("askYesNo should not be called for a clean doctor run");
  });
  harness.setRunCommand(async () => ({ exitCode: 0, success: true }));

  const success = await harness.runDoctorFlow(projectPath, harness.state.runtime);

  assert.equal(success, true);
  assert.deepEqual(events.failures, []);
  assert.ok(events.oks.includes("Doctor found no remaining issues."));
  assert.ok(events.details.includes("Inspect the current Laravel project and only offer narrow, safe repairs."));
  assert.ok(events.details.some((message) => message.endsWith(projectPath)));
  assert.ok(events.details.includes("- laravel/framework"));
  assert.ok(events.details.some((message) => /Repair prompts:\s+enabled for safe fixes$/.test(message)));
});

test("runDoctorFlow repairs a missing storage link interactively", async () => {
  const { events, harness } = createDoctorHarness();
  const projectPath = createProjectFixture();
  const storageLinkPath = path.join(projectPath, "public", "storage");

  fs.unlinkSync(storageLinkPath);

  harness.setAskYesNo(async (question, defaultYes) => {
    events.prompts.push({ question, defaultYes });
    return true;
  });
  harness.setRunCommand(async (command, args) => {
    if (command === "php" && args[0] === "artisan" && args[1] === "storage:link") {
      fs.symlinkSync(
        path.join(projectPath, "storage", "app", "public"),
        storageLinkPath,
      );

      return { exitCode: 0, success: true };
    }

    return { exitCode: 0, success: true };
  });

  const success = await harness.runDoctorFlow(projectPath, harness.state.runtime);

  assert.equal(success, true);
  assert.deepEqual(events.prompts, [{ question: "Create storage link now?", defaultYes: true }]);
  assert.ok(events.oks.includes("Storage link created successfully"));
  assert.ok(events.details.some((message) => /Repairs applied:\s+1$/.test(message)));
});

test("runDoctorFlow stays report-only in dry-run mode and returns false when issues remain", async () => {
  const { events, harness } = createDoctorHarness({ printPlan: true });
  const projectPath = createProjectFixture();
  const storageLinkPath = path.join(projectPath, "public", "storage");

  fs.unlinkSync(storageLinkPath);

  harness.setAskYesNo(async () => {
    throw new Error("askYesNo should not be called in doctor dry-run mode");
  });
  harness.setRunCommand(async (command, args) => {
    if (command === "php" && args[0] === "artisan" && args[1] === "storage:link") {
      throw new Error("storage:link should not be attempted in doctor dry-run mode");
    }

    return { exitCode: 0, success: true };
  });

  const success = await harness.runDoctorFlow(projectPath, harness.state.runtime);

  assert.equal(success, false);
  assert.ok(events.warnings.includes("Storage link missing"));
  assert.ok(events.failures.includes("Doctor found unresolved issues: Storage link"));
  assert.ok(events.details.some((message) => /Repair prompts:\s+disabled$/.test(message)));
  assert.ok(events.subsections.includes("Unresolved Issues"));
});

test("runDoctorFlow prints nwidart status only when the package is installed", async () => {
  const { events, harness } = createDoctorHarness();
  const projectPath = createProjectFixture();
  const composerPath = path.join(projectPath, "composer.json");
  const composerJson = JSON.parse(fs.readFileSync(composerPath, "utf8"));

  composerJson.require["nwidart/laravel-modules"] = "^12.0";
  fs.writeFileSync(composerPath, `${JSON.stringify(composerJson, null, 4)}\n`, "utf8");

  harness.setRunCommand(async () => ({ exitCode: 0, success: true }));

  const success = await harness.runDoctorFlow(projectPath, harness.state.runtime);

  assert.equal(success, true);
  assert.ok(events.sections.includes("Nwidart Status"));
  assert.ok(events.warnings.some((message) => message.startsWith("Nwidart setup incomplete:")));
});
