const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const { loadInstallerHarness } = require("./support/instalar-harness.cjs");

test("askYesNo accepts only English aliases in interactive mode", async () => {
  const harness = loadInstallerHarness();
  const answers = ["maybe", "yes"];
  const warnings = [];

  harness.state.runtime.nonInteractive = false;
  harness.setAsk(async () => answers.shift() || "");
  harness.setWarn((message) => {
    warnings.push(message);
  });

  const accepted = await harness.askYesNo("Continue", true);

  assert.equal(accepted, true);
  assert.deepEqual(warnings, ["Please answer with y or n."]);
});

test("collectAutoConfig resolves presets, database defaults, and generated admin credentials", async () => {
  const harness = loadInstallerHarness();
  const sections = [];
  const details = [];

  harness.state.runtime = {
    ...harness.state.runtime,
    nonInteractive: false,
    preset: "standard",
    adminGenerate: true,
  };
  harness.setSection((title) => {
    sections.push(title);
  });
  harness.setDetail((message) => {
    details.push(message);
  });
  harness.setInfo(() => {});
  harness.setWarn(() => {});
  harness.setAskRequired(async (question, defaultValue) => {
    if (question === "Project name") {
      return "Demo App";
    }

    return defaultValue;
  });
  harness.setAskChoice(async (question) => {
    if (question === "Package preset") {
      return harness.PACKAGE_PRESETS.findIndex((preset) => preset.id === "full");
    }

    throw new Error(`Unexpected choice prompt: ${question}`);
  });

  const config = await harness.collectAutoConfig({
    preset: "minimal",
    normalPackages: ["laravel/pennant"],
    devPackages: ["laravel/dusk:^8.0"],
    database: {
      connection: "mysql",
      host: "db",
      port: "3307",
      database: "demo",
      username: "root",
      password: "db-secret",
    },
  });

  assert.equal(config.mode, "auto");
  assert.equal(config.presetId, "full");
  assert.equal(config.appName, "Demo App");
  assert.equal(config.projectPath, path.resolve(process.cwd(), "demo-app"));
  assert.deepEqual({ ...config.database }, {
    connection: "mysql",
    host: "db",
    port: "3307",
    database: "demo",
    username: "root",
    password: "db-secret",
  });
  assert.deepEqual([...config.laravelNewFlags], ["--npm", "--livewire", "--boost", "--pest"]);
  assert.equal(config.createAdmin, true);
  assert.equal(config.admin.passwordSource, "generated");
  assert.equal(config.admin.revealPassword, true);
  assert.ok(config.admin.password.length >= 20);
  assert.deepEqual(sections, ["Automatic Setup"]);
  assert.ok(
    details.includes(
      "Resolve a project name, apply a preset, and use opinionated defaults.",
    ),
  );
  assert.ok(config.normalPackages.includes("filament/filament:^5.0"));
  assert.ok(config.normalPackages.includes("laravel/fortify"));
  assert.ok(config.normalPackages.includes("laravel/pennant"));
  assert.ok(config.devPackages.includes("laravel/dusk:^8.0"));
  assert.ok(config.devPackages.includes("barryvdh/laravel-debugbar"));
});

test("collectManualConfig combines prompt answers, preset packages, and configured admin secrets", async () => {
  const harness = loadInstallerHarness();
  const sections = [];

  harness.state.runtime = {
    ...harness.state.runtime,
    nonInteractive: false,
    preset: "minimal",
    adminGenerate: false,
  };
  harness.setSection((title) => {
    sections.push(title);
  });
  harness.setDetail(() => {});
  harness.setInfo(() => {});
  harness.setWarn(() => {});
  harness.setAskRequired(async (question, defaultValue) => {
    if (question === "Project name") {
      return "Manual App";
    }
    if (question === "Project directory") {
      return "./manual-app";
    }
    if (question === "DB Name") {
      return "manual_db";
    }
    if (question === "DB User") {
      return "manual_user";
    }

    return defaultValue;
  });
  harness.setAsk(async (question, defaultValue) => {
    if (question === "DB Host") {
      return "db.internal";
    }
    if (question === "DB Port") {
      return "5433";
    }
    if (question === "Additional Composer packages") {
      return "laravel/socialite:^5.0 spatie/laravel-health:^1.0";
    }
    if (question === "Additional dev Composer packages") {
      return "laravel/dusk:^8.0";
    }

    return defaultValue;
  });
  harness.setAskSecret(async () => "manual-secret");
  harness.setAskChoice(async (question) => {
    if (question === "Database engine") {
      return 2;
    }
    if (question === "Default test suite") {
      return 1;
    }
    if (question === "Package preset") {
      return harness.PACKAGE_PRESETS.findIndex((preset) => preset.id === "full");
    }

    throw new Error(`Unexpected choice prompt: ${question}`);
  });
  harness.setAskMultiChoiceWithAll(async (question) => {
    if (question === "Starter features") {
      return [0, 2];
    }
    if (question === "Optional packages") {
      return harness.getOptionIndexesByIds(["fortify", "modules_bundle"], []);
    }

    throw new Error(`Unexpected multiselect prompt: ${question}`);
  });
  harness.setAskYesNo(async (question) => {
    if (question === "Create a Filament admin user") {
      return true;
    }
    if (question === "Initialize a Git repository") {
      return true;
    }

    throw new Error(`Unexpected yes/no prompt: ${question}`);
  });

  const config = await harness.collectManualConfig({
    admin: {
      name: "Jane Admin",
      email: "jane@example.com",
      password: "stored-secret",
    },
  });

  assert.equal(config.mode, "manual");
  assert.equal(config.presetId, "full");
  assert.equal(config.appName, "Manual App");
  assert.equal(config.projectPath, path.resolve(process.cwd(), "manual-app"));
  assert.deepEqual({ ...config.database }, {
    connection: "pgsql",
    host: "db.internal",
    port: "5433",
    database: "manual_db",
    username: "manual_user",
    password: "manual-secret",
  });
  assert.deepEqual([...config.laravelNewFlags], ["--npm", "--boost", "--phpunit"]);
  assert.ok(config.normalPackages.includes("filament/filament:^5.0"));
  assert.ok(config.normalPackages.includes("laravel/boost"));
  assert.ok(config.normalPackages.includes("laravel/fortify"));
  assert.ok(config.normalPackages.includes("nwidart/laravel-modules"));
  assert.ok(config.normalPackages.includes("coolsam/modules"));
  assert.ok(config.normalPackages.includes("laravel/socialite:^5.0"));
  assert.ok(config.normalPackages.includes("spatie/laravel-health:^1.0"));
  assert.ok(config.devPackages.includes("laravel/dusk:^8.0"));
  assert.equal(config.createAdmin, true);
  assert.equal(config.admin.name, "Jane Admin");
  assert.equal(config.admin.email, "jane@example.com");
  assert.equal(config.admin.passwordSource, "config");
  assert.equal(config.admin.revealPassword, false);
  assert.equal(config.gitInit, true);
  assert.deepEqual(sections, [
    "Step 1/6 - Project Basics",
    "Step 2/6 - Database",
    "Step 3/6 - Laravel Starter",
    "Step 4/6 - Packages",
    "Step 5/6 - Admin and Git",
  ]);
});

test("reviewManualConfig offers start, retry, or cancel after the grouped review screen", async () => {
  const harness = loadInstallerHarness();
  const sections = [];
  const askedQuestions = [];

  harness.state.runtime = {
    ...harness.state.runtime,
    nonInteractive: false,
    printPlan: false,
    logFile: null,
    skipBoostInstall: false,
    continueOnHealthCheckFailure: false,
  };
  harness.setSection((title) => {
    sections.push(title);
  });
  harness.setSubsection(() => {});
  harness.setDetail(() => {});
  harness.setOk(() => {});
  harness.setInfo(() => {});
  harness.setAskChoice(async (question) => {
    askedQuestions.push(question);
    return 1;
  });

  const action = await harness.reviewManualConfig({
    mode: "manual",
    presetId: "standard",
    appName: "Manual App",
    projectPath: "/tmp/manual-app",
    database: { connection: "sqlite" },
    laravelNewFlags: ["--npm", "--boost", "--pest"],
    normalPackages: ["filament/filament:^5.0", "laravel/boost"],
    devPackages: [],
    createAdmin: true,
    admin: {
      name: "Admin",
      email: "admin@example.com",
      password: "hidden",
      passwordSource: "config",
      revealPassword: false,
    },
    gitInit: false,
  });

  assert.equal(action, "retry");
  assert.deepEqual(sections, ["Step 6/6 - Review", "Installation Plan"]);
  assert.deepEqual(askedQuestions, ["Review action"]);
});
