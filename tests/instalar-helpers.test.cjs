const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { loadInstallerHarness } = require("./support/instalar-harness.cjs");

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

test("package and Laravel flag helpers normalize installer input consistently", () => {
  const harness = loadInstallerHarness();

  assert.equal(harness.normalizeLaravelTestSuiteFlag("Pest"), "--pest");
  assert.equal(harness.normalizeLaravelTestSuiteFlag("--phpunit"), "--phpunit");
  assert.equal(harness.normalizeLaravelTestSuiteFlag("unknown"), null);

  assert.deepEqual(
    [...harness.normalizeLaravelFlags(
      ["--boost", "--npm", "phpunit", "--boost", "--pest"],
      ["--livewire", "--pest"],
      null,
    )],
    ["--boost", "--npm", "--phpunit"],
  );
  assert.deepEqual(
    [...harness.normalizeLaravelFlags([], ["--npm", "--livewire", "--boost", "--pest"], "phpunit")],
    ["--npm", "--livewire", "--boost", "--phpunit"],
  );

  assert.equal(harness.packageNameFromSpec("laravel/pulse:^1.0"), "laravel/pulse");
  assert.deepEqual(
    [...harness.mergePackageSpecs([
      "laravel/pulse:^1.0",
      "laravel/pail:^1.0",
      "laravel/pulse:^2.0",
      " ",
    ])],
    ["laravel/pulse:^2.0", "laravel/pail:^1.0"],
  );
  assert.deepEqual(
    [...harness.splitPackageInput(" laravel/pulse:^1, barryvdh/laravel-debugbar:^3  spatie/laravel-health:^1 ")],
    [
      "laravel/pulse:^1",
      "barryvdh/laravel-debugbar:^3",
      "spatie/laravel-health:^1",
    ],
  );
});

test("terminal row helpers account for ANSI escapes and wrapped prompt rows", () => {
  const harness = loadInstallerHarness();

  assert.equal(
    harness.terminalStringWidth("\u001b[36m›\u001b[0m \u001b[32m[x]\u001b[0m Package"),
    13,
  );
  assert.equal(
    harness.countRenderedTerminalRows(
      [
        "Optional packages",
        "  › [x] Telescope [Monitoring] - Debug requests, jobs, and exceptions.",
        "  Controls: ↑/↓ move, Space toggle, Enter confirm",
      ],
      32,
    ),
    6,
  );
  assert.equal(
    harness.countRenderedCursorRows(
      [
        "Optional packages",
        "  › [x] Telescope [Monitoring] - Debug requests, jobs, and exceptions.",
        "  Controls: ↑/↓ move, Space toggle, Enter confirm",
      ],
      32,
    ),
    5,
  );
});

test("environment helpers escape values and configure sqlite and mysql projects", () => {
  const harness = loadInstallerHarness();
  const sqliteProject = fs.mkdtempSync(path.join(os.tmpdir(), "instalar-sqlite-"));
  const mysqlProject = fs.mkdtempSync(path.join(os.tmpdir(), "instalar-mysql-"));

  assert.equal(harness.envSafeValue("simple-value"), "simple-value");
  assert.equal(harness.envSafeValue('quoted value "test"'), '"quoted value \\"test\\""');
  assert.equal(
    harness.setEnvValue("APP_NAME=Laravel\n", "APP_NAME", "Demo App"),
    'APP_NAME="Demo App"\n',
  );
  assert.equal(
    harness.setEnvValue("APP_NAME=Laravel\n", "DB_CONNECTION", "sqlite"),
    "APP_NAME=Laravel\nDB_CONNECTION=sqlite\n",
  );

  fs.writeFileSync(path.join(sqliteProject, ".env.example"), "APP_NAME=Laravel\n", "utf8");
  harness.applyEnvConfig(sqliteProject, {
    appName: "Demo App",
    database: { connection: "sqlite" },
  });

  const sqliteEnv = fs.readFileSync(path.join(sqliteProject, ".env"), "utf8");
  assert.match(sqliteEnv, /APP_NAME="Demo App"/);
  assert.match(sqliteEnv, /DB_CONNECTION=sqlite/);
  assert.match(sqliteEnv, /DB_DATABASE=database\/database\.sqlite/);
  assert.equal(fs.existsSync(path.join(sqliteProject, "database", "database.sqlite")), true);

  fs.writeFileSync(path.join(mysqlProject, ".env"), "APP_NAME=Laravel\n", "utf8");
  harness.applyEnvConfig(mysqlProject, {
    appName: "Demo App",
    database: {
      connection: "mysql",
      host: "127.0.0.1",
      port: "3307",
      database: "demo",
      username: "root",
      password: "secret phrase",
    },
  });

  const mysqlEnv = fs.readFileSync(path.join(mysqlProject, ".env"), "utf8");
  assert.match(mysqlEnv, /DB_CONNECTION=mysql/);
  assert.match(mysqlEnv, /DB_HOST=127\.0\.0\.1/);
  assert.match(mysqlEnv, /DB_PORT=3307/);
  assert.match(mysqlEnv, /DB_DATABASE=demo/);
  assert.match(mysqlEnv, /DB_USERNAME=root/);
  assert.match(mysqlEnv, /DB_PASSWORD="secret phrase"/);
});

test("plan and filesystem helpers describe sensitive values and protected paths correctly", () => {
  const harness = loadInstallerHarness();
  const protectedProject = fs.mkdtempSync(path.join(os.tmpdir(), "instalar-backup-"));
  const packageSet = harness.packageSetFromConfig({
    normalPackages: ["filament/filament:^5.0", "laravel/pulse:^1.0"],
    devPackages: ["laravel/dusk:^8.0"],
    laravelNewFlags: ["--npm", "--boost", "--pest"],
  });

  assert.equal(
    harness.describeAdminPasswordStrategy({
      createAdmin: true,
      admin: { passwordSource: "config" },
    }),
    "provided via config (hidden)",
  );
  assert.equal(
    harness.describeAdminPasswordStrategy({
      createAdmin: false,
      admin: { passwordSource: "generated" },
    }),
    "not created",
  );
  assert.equal(
    harness.configUsesSensitiveValues({
      database: { password: "db-secret" },
      admin: { passwordSource: "none", password: "" },
    }),
    true,
  );
  assert.equal(
    harness.configUsesSensitiveValues({
      database: { password: "" },
      admin: { passwordSource: "config", password: "admin-secret" },
    }),
    true,
  );
  assert.equal(
    harness.configUsesSensitiveValues({
      database: { password: "" },
      admin: { passwordSource: "default", password: "" },
    }),
    false,
  );
  assert.deepEqual([...packageSet].sort(), [
    "filament/filament",
    "laravel/boost",
    "laravel/dusk",
    "laravel/pulse",
  ]);

  const backupPath = harness.getBackupTargetPath(protectedProject);
  assert.match(backupPath, new RegExp(`^${escapeRegex(protectedProject)}\\.backup-`));
  assert.equal(
    harness.getProtectedPathReason(process.cwd()),
    "target path is the current working directory.",
  );
  assert.throws(
    () => harness.ensureSafeProjectTarget(process.cwd()),
    /Safety abort: target path is the current working directory/,
  );
});

test("source rewrite helpers extract nested blocks and preserve indentation", () => {
  const harness = loadInstallerHarness();
  const source = [
    "export default defineConfig({",
    "    server: {",
    "        host: '0.0.0.0',",
    "        hmr: {",
    "            host: 'localhost',",
    "        },",
    "    },",
    "    plugins: [],",
    "});",
    "",
  ].join("\n");

  assert.equal(
    harness.extractObjectPropertyBlock(source, "server"),
    [
      "server: {",
      "        host: '0.0.0.0',",
      "        hmr: {",
      "            host: 'localhost',",
      "        },",
      "    },",
    ].join("\n"),
  );
  assert.equal(harness.extractObjectPropertyBlock(source, "ssr"), "");
  assert.equal(harness.indentLines("alpha\nbeta", 4), "    alpha\n    beta");
});

test("printUpdatePlan reports runtime details without mutating project state", () => {
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

  harness.printUpdatePlan(
    "/tmp/demo-project",
    new Set(["laravel/pulse", "filament/filament"]),
    {
      printPlan: true,
      logFile: "/tmp/instalar.log",
      upgradeDependencies: false,
      skipBoostInstall: false,
      continueOnHealthCheckFailure: false,
    },
  );

  assert.deepEqual(events.sections, ["Update Review"]);
  assert.deepEqual(events.subsections, ["Project Snapshot", "Run Controls", "Detected Stack"]);
  assert.ok(
    events.details.includes(
      "Inspect the current project state before dependencies, migrations, and builds run.",
    ),
  );
  assert.ok(events.details.some((message) => /Project:\s+\/tmp\/demo-project$/.test(message)));
  assert.ok(events.details.some((message) => /Dry run:\s+yes$/.test(message)));
  assert.ok(events.details.some((message) => /Log file:\s+\/tmp\/instalar\.log$/.test(message)));
  assert.ok(
    events.details.some((message) => /Composer dependencies:\s+install \(lockfile-safe\)$/.test(message)),
  );
  assert.ok(events.details.some((message) => /Boost install:\s+run interactively$/.test(message)));
  assert.ok(events.details.some((message) => /Health-check failures:\s+abort$/.test(message)));
  assert.ok(events.details.includes("- filament/filament"));
  assert.ok(events.details.includes("- laravel/pulse"));
  assert.ok(events.oks.includes("Preview only. No project files will be modified."));
});

test("resolveUpdateDependencyStrategy defaults to lockfile-safe installs and supports explicit upgrades", () => {
  const harness = loadInstallerHarness();
  const defaultStrategy = harness.resolveUpdateDependencyStrategy({ upgradeDependencies: false });
  const upgradeStrategy = harness.resolveUpdateDependencyStrategy({ upgradeDependencies: true });

  assert.equal(defaultStrategy.label, "install (lockfile-safe)");
  assert.equal(defaultStrategy.command, "composer");
  assert.deepEqual([...defaultStrategy.args], ["install", "--no-interaction"]);

  assert.equal(upgradeStrategy.label, "update (--upgrade-dependencies)");
  assert.equal(upgradeStrategy.command, "composer");
  assert.deepEqual([...upgradeStrategy.args], ["update", "--no-interaction"]);
});

test("failure summary helpers describe recovery steps for command and permission issues", () => {
  const harness = loadInstallerHarness();
  const events = {
    details: [],
    subsections: [],
  };

  harness.setSubsection((title) => {
    events.subsections.push(title);
  });
  harness.setDetail((message) => {
    events.details.push(message);
  });

  const composerSummary = harness.buildCommandFailureSummary(
    "composer",
    ["update", "--no-interaction"],
    {
      cwd: "/tmp/demo-project",
      exitCode: 2,
    },
  );
  const npmSummary = harness.buildCommandFailureSummary(
    "npm",
    ["run", "build"],
    {
      cwd: "/tmp/demo-project",
      exitCode: 1,
    },
  );
  const artisanSummary = harness.buildCommandFailureSummary(
    "php",
    ["artisan", "migrate", "--force", "--no-interaction"],
    {
      cwd: "/tmp/demo-project",
      exitCode: 255,
    },
  );
  const permissionSummary = harness.buildPermissionFailureSummary("/tmp/demo-project", {
    failedChecks: ["storage", ".env"],
  });

  assert.equal(composerSummary.title, "Composer Failure");
  assert.equal(composerSummary.details[0][0], "Failed step");
  assert.equal(composerSummary.details[0][1], "Composer dependency update");
  assert.ok(composerSummary.nextSteps.includes("composer validate"));
  assert.ok(composerSummary.nextSteps.includes("composer diagnose"));

  assert.equal(npmSummary.title, "npm Failure");
  assert.equal(npmSummary.details[0][0], "Failed step");
  assert.equal(npmSummary.details[0][1], "Frontend asset build");
  assert.ok(npmSummary.nextSteps.includes("npm install"));
  assert.ok(npmSummary.nextSteps.includes("npm run build"));

  assert.equal(artisanSummary.title, "Artisan Failure");
  assert.equal(artisanSummary.details[0][0], "Failed step");
  assert.equal(artisanSummary.details[0][1], "Artisan migrate");
  assert.ok(artisanSummary.nextSteps.includes("php artisan migrate"));
  assert.ok(artisanSummary.nextSteps.includes("php artisan optimize:clear && php artisan optimize"));

  assert.equal(permissionSummary.title, "Permission Attention Needed");
  assert.ok(permissionSummary.nextSteps.includes("chmod -R ug+rw storage bootstrap/cache"));
  assert.ok(permissionSummary.nextSteps.includes("chmod ug+rw .env"));

  harness.printFailureSummary(permissionSummary);

  assert.deepEqual(events.subsections, ["Permission Attention Needed"]);
  assert.ok(events.details.some((message) => /Project:\s+\/tmp\/demo-project$/.test(message)));
  assert.ok(events.details.some((message) => /Failed checks:\s+storage, \.env$/.test(message)));
  assert.ok(events.details.includes("Next steps:"));
  assert.ok(events.details.includes("- chmod -R ug+rw storage bootstrap/cache"));
});
