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

  harness.state.runtime = {
    ...harness.state.runtime,
    nonInteractive: false,
    preset: "standard",
    adminGenerate: true,
  };
  harness.setSection(() => {});
  harness.setInfo(() => {});
  harness.setWarn(() => {});
  harness.setAskRequired(async (question, defaultValue) => {
    if (question === "Project name") {
      return "Demo App";
    }

    return defaultValue;
  });
  harness.setAskChoice(async (question) => {
    if (question === "Choose package preset") {
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
  assert.ok(config.normalPackages.includes("filament/filament:^5.0"));
  assert.ok(config.normalPackages.includes("laravel/fortify"));
  assert.ok(config.normalPackages.includes("laravel/pennant"));
  assert.ok(config.devPackages.includes("laravel/dusk:^8.0"));
  assert.ok(config.devPackages.includes("barryvdh/laravel-debugbar"));
});

test("collectManualConfig combines prompt answers, preset packages, and configured admin secrets", async () => {
  const harness = loadInstallerHarness();

  harness.state.runtime = {
    ...harness.state.runtime,
    nonInteractive: false,
    preset: "minimal",
    adminGenerate: false,
  };
  harness.setSection(() => {});
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
    if (question === "Custom Composer packages (normal, optional)") {
      return "laravel/socialite:^5.0 spatie/laravel-health:^1.0";
    }
    if (question === "Custom Composer packages (dev, optional)") {
      return "laravel/dusk:^8.0";
    }

    return defaultValue;
  });
  harness.setAskSecret(async () => "manual-secret");
  harness.setAskChoice(async (question) => {
    if (question === "Choose package preset") {
      return harness.PACKAGE_PRESETS.findIndex((preset) => preset.id === "full");
    }
    if (question === "Choose database") {
      return 2;
    }
    if (question === "Choose Laravel test suite") {
      return 1;
    }

    throw new Error(`Unexpected choice prompt: ${question}`);
  });
  harness.setAskMultiChoiceWithAll(async (question) => {
    if (question === "Choose Laravel startup flags") {
      return [0, 2];
    }
    if (question === "Choose optional packages (Filament + Boost are always active)") {
      return harness.getOptionIndexesByIds(["fortify", "modules_bundle"], []);
    }

    throw new Error(`Unexpected multiselect prompt: ${question}`);
  });
  harness.setAskYesNo(async (question) => {
    if (question === "Create Filament admin user") {
      return true;
    }
    if (question === "Run git init") {
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
});
