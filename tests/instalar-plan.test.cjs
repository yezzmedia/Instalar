const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { loadInstallerHarness } = require("./support/instalar-harness.cjs");

test("path helpers classify existing directories and enforce safer unattended replacement rules", () => {
  const harness = loadInstallerHarness();
  const targetPath = fs.mkdtempSync(path.join(os.tmpdir(), "instalar-plan-"));
  const gitPath = fs.mkdtempSync(path.join(os.tmpdir(), "instalar-plan-git-"));
  const laravelPath = fs.mkdtempSync(path.join(os.tmpdir(), "instalar-plan-laravel-"));
  const missingPath = path.join(os.tmpdir(), `instalar-plan-missing-${Date.now()}`);

  fs.mkdirSync(path.join(gitPath, ".git"));
  fs.writeFileSync(path.join(gitPath, "README.md"), "repo\n");
  fs.writeFileSync(path.join(laravelPath, "artisan"), "#!/usr/bin/env php\n");
  fs.mkdirSync(path.join(laravelPath, "bootstrap"), { recursive: true });
  fs.writeFileSync(path.join(laravelPath, "bootstrap", "app.php"), "<?php\n");
  fs.writeFileSync(path.join(laravelPath, "composer.json"), "{}\n");

  assert.equal(harness.classifyExistingPath(missingPath), "missing");
  assert.equal(harness.classifyExistingPath(targetPath), "empty");
  assert.equal(harness.classifyExistingPath(gitPath), "git-repo");
  assert.equal(harness.classifyExistingPath(laravelPath), "laravel-project");
  assert.equal(harness.describePathClassification("git-repo"), "Git-managed directory");
  assert.equal(
    harness.describeExistingPathStrategy(targetPath, { nonInteractive: false, backup: false }),
    "Prompt before reusing the empty directory",
  );
  assert.equal(
    harness.describeExistingPathStrategy(targetPath, { nonInteractive: true, allowDeleteExisting: false }),
    "Abort unless --allow-delete-existing is set",
  );
  assert.equal(
    harness.describeExistingPathStrategy(targetPath, {
      nonInteractive: true,
      allowDeleteExisting: true,
      backup: false,
    }),
    "Replace existing path",
  );
  assert.equal(
    harness.describeExistingPathStrategy(gitPath, {
      nonInteractive: true,
      allowDeleteExisting: true,
      allowDeleteAnyExisting: false,
      backup: false,
    }),
    "Abort unless --allow-delete-any-existing is set",
  );
  assert.equal(
    harness.canDeleteExistingPathNonInteractive("git-repo", {
      allowDeleteExisting: true,
      allowDeleteAnyExisting: false,
    }),
    false,
  );
  assert.equal(
    harness.canDeleteExistingPathNonInteractive("git-repo", {
      allowDeleteExisting: false,
      allowDeleteAnyExisting: true,
    }),
    true,
  );
  assert.equal(
    harness.describeExistingPathStrategy(targetPath, {
      nonInteractive: true,
      allowDeleteExisting: true,
      backup: true,
    }),
    "Replace existing path after backup",
  );
});

test("printInstallPlan reports preset, boost behavior, and preview-only mode", () => {
  const harness = loadInstallerHarness();
  const events = {
    details: [],
    oks: [],
    sections: [],
    subsections: [],
  };

  harness.setSection((title) => {
    events.sections.push(title);
  });
  harness.setSubsection((title) => {
    events.subsections.push(title);
  });
  harness.setDetail((message) => {
    events.details.push(message);
  });
  harness.setOk((message) => {
    events.oks.push(message);
  });

  const packageSet = harness.printInstallPlan(
    {
      mode: "manual",
      presetId: "full",
      appName: "Demo App",
      projectPath: "/tmp/demo-app",
      database: { connection: "pgsql" },
      laravelNewFlags: ["--npm", "--boost", "--pest"],
      normalPackages: ["laravel/fortify", "laravel/pulse"],
      devPackages: ["barryvdh/laravel-debugbar"],
      createAdmin: true,
      admin: {
        name: "Admin",
        email: "admin@example.com",
        password: "super-secret",
        passwordSource: "config",
        revealPassword: false,
      },
      gitInit: true,
    },
    {
      nonInteractive: true,
      printPlan: true,
      preset: "full",
      logFile: "/tmp/demo-instalar.log",
      skipBoostInstall: true,
      continueOnHealthCheckFailure: true,
      allowDeleteExisting: false,
      backup: false,
    },
  );

  assert.deepEqual(events.sections, ["Installation Review"]);
  assert.deepEqual(events.subsections, [
    "Run Profile",
    "Database Profile",
    "Starter Stack",
    "Package Stack",
    "Normal Packages",
    "Dev Packages",
    "Identity and Git",
    "Run Controls",
  ]);
  assert.ok(
    events.details.includes(
      "Nothing is created or replaced until this run is approved.",
    ),
  );
  assert.ok(events.details.some((message) => /Mode:\s+manual$/.test(message)));
  assert.ok(events.details.some((message) => /Preset:\s+Full$/.test(message)));
  assert.ok(events.details.some((message) => /Connection:\s+pgsql$/.test(message)));
  assert.ok(events.details.some((message) => /Dry run:\s+yes$/.test(message)));
  assert.ok(
    events.details.some((message) => /Log file:\s+\/tmp\/demo-instalar\.log$/.test(message)),
  );
  assert.ok(events.details.some((message) => /Boost install:\s+skip$/.test(message)));
  assert.ok(events.details.some((message) => message.startsWith("Path type:")));
  assert.ok(
    events.details.some((message) => /Admin password:\s+provided via config \(hidden\)$/.test(message)),
  );
  assert.ok(events.details.some((message) => /Configured secrets:\s+yes$/.test(message)));
  assert.ok(events.details.some((message) => /Health-check failures:\s+continue$/.test(message)));
  assert.equal(events.details.join("\n").includes("super-secret"), false);
  assert.ok(events.oks.includes("Preview only. No project files will be modified."));
  assert.equal(packageSet.has("laravel/boost"), true);
  assert.equal(packageSet.has("laravel/fortify"), true);
  assert.equal(packageSet.has("laravel/pulse"), true);
  assert.equal(packageSet.has("barryvdh/laravel-debugbar"), true);
});

test("printFinalNotes groups project details, next steps, admin details, and warnings", () => {
  const harness = loadInstallerHarness();
  const events = {
    details: [],
    oks: [],
    sections: [],
    subsections: [],
  };

  harness.state.boostInstallSkipped = true;
  harness.state.createdAdmin = {
    name: "Jane Admin",
    email: "jane@example.com",
    password: "generated-secret",
    revealPassword: true,
    passwordSource: "generated",
  };
  harness.state.warnings = ["Storage link missing", "Boost install skipped"];

  harness.setSection((title) => {
    events.sections.push(title);
  });
  harness.setSubsection((title) => {
    events.subsections.push(title);
  });
  harness.setDetail((message) => {
    events.details.push(message);
  });
  harness.setOk((message) => {
    events.oks.push(message);
  });

  harness.printFinalNotes("/tmp/demo-app", {
    logFile: "/tmp/demo-instalar.log",
    startServer: false,
  });

  assert.deepEqual(events.sections, ["Run Complete"]);
  assert.deepEqual(events.subsections, ["Project Ready", "Run Next", "Admin Access", "Open Warnings"]);
  assert.ok(events.oks.includes("INSTALAR finished successfully."));
  assert.ok(events.details.some((message) => /Project path:\s+\/tmp\/demo-app$/.test(message)));
  assert.ok(
    events.details.some((message) => /Log file:\s+\/tmp\/demo-instalar\.log$/.test(message)),
  );
  assert.ok(events.details.includes("- cd /tmp/demo-app"));
  assert.ok(events.details.includes("- php artisan serve"));
  assert.ok(events.details.includes("- composer run dev"));
  assert.ok(events.details.includes("- php artisan boost:install"));
  assert.ok(events.details.some((message) => /Email:\s+jane@example\.com$/.test(message)));
  assert.ok(events.details.some((message) => /Password:\s+generated-secret$/.test(message)));
  assert.ok(events.details.includes("- Storage link missing"));
  assert.ok(events.details.includes("- Boost install skipped"));
});
