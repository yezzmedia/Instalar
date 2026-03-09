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
    infos: [],
    oks: [],
    sections: [],
  };

  harness.setSection((title) => {
    events.sections.push(title);
  });
  harness.setInfo((message) => {
    events.infos.push(message);
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

  assert.deepEqual(events.sections, ["Installation Plan"]);
  assert.ok(events.infos.includes("Mode: manual"));
  assert.ok(events.infos.includes("Preset: Full"));
  assert.ok(events.infos.includes("Database: pgsql"));
  assert.ok(events.infos.includes("Dry run: yes"));
  assert.ok(events.infos.includes("Log file: /tmp/demo-instalar.log"));
  assert.ok(events.infos.includes("Boost install: skip"));
  assert.ok(events.infos.some((message) => message.startsWith("Path type: ")));
  assert.ok(events.infos.includes("Admin password: provided via config (hidden)"));
  assert.ok(events.infos.includes("Configured secrets: yes"));
  assert.ok(events.infos.includes("Health-check failure override: continue"));
  assert.ok(events.oks.includes("Plan preview only. No project files will be modified."));
  assert.equal(events.infos.join("\n").includes("super-secret"), false);
  assert.equal(packageSet.has("laravel/boost"), true);
  assert.equal(packageSet.has("laravel/fortify"), true);
  assert.equal(packageSet.has("laravel/pulse"), true);
  assert.equal(packageSet.has("barryvdh/laravel-debugbar"), true);
});
