const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { loadInstallerHarness } = require("./support/instalar-harness.cjs");

function createNwidartProjectFixture() {
  const projectPath = fs.mkdtempSync(path.join(os.tmpdir(), "instalar-nwidart-"));

  fs.writeFileSync(
    path.join(projectPath, "composer.json"),
    JSON.stringify(
      {
        autoload: {
          "psr-4": {
            "App\\": "app/",
            "Modules\\": "modules/",
          },
        },
      },
      null,
      4,
    ),
    "utf8",
  );
  fs.writeFileSync(
    path.join(projectPath, "vite.config.js"),
    [
      "import { defineConfig } from 'vite';",
      "import laravel from 'laravel-vite-plugin';",
      "",
      "export default defineConfig({",
      "    plugins: [",
      "        laravel({",
      "            input: ['resources/css/app.css', 'resources/js/app.js'],",
      "            refresh: true,",
      "        }),",
      "    ],",
      "    server: {",
      "        host: '0.0.0.0',",
      "    },",
      "});",
      "",
    ].join("\n"),
    "utf8",
  );

  return projectPath;
}

test("ensureComposerPluginAllowList updates composer config and triggers composer config command", async () => {
  const harness = loadInstallerHarness();
  const projectPath = fs.mkdtempSync(path.join(os.tmpdir(), "instalar-allow-plugins-"));
  const commands = [];

  fs.writeFileSync(path.join(projectPath, "composer.json"), "{}\n", "utf8");
  harness.setInfo(() => {});
  harness.setWarn(() => {});
  harness.setOk(() => {});
  harness.setSection(() => {});
  harness.setRunCommand(async (command, args, options) => {
    commands.push({ command, args, options });
    return { success: true, exitCode: 0 };
  });

  await harness.ensureComposerPluginAllowList(
    projectPath,
    new Set(["nwidart/laravel-modules"]),
  );

  const composerJson = JSON.parse(fs.readFileSync(path.join(projectPath, "composer.json"), "utf8"));
  assert.equal(commands.length, 1);
  assert.equal(commands[0].command, "composer");
  assert.deepEqual([...commands[0].args], [
    "config",
    "--no-plugins",
    "allow-plugins.wikimedia/composer-merge-plugin",
    "true",
    "--no-interaction",
  ]);
  assert.equal(composerJson.config["allow-plugins"]["wikimedia/composer-merge-plugin"], true);
});

test("ensureNwidartComposerMergeConfig removes legacy autoload and is idempotent", async () => {
  const harness = loadInstallerHarness();
  const projectPath = fs.mkdtempSync(path.join(os.tmpdir(), "instalar-merge-config-"));

  fs.writeFileSync(
    path.join(projectPath, "composer.json"),
    JSON.stringify(
      {
        autoload: {
          "psr-4": {
            "App\\": "app/",
            "Modules\\": "modules/",
          },
        },
        extra: {},
      },
      null,
      4,
    ),
    "utf8",
  );
  harness.setWarn(() => {});
  harness.setOk(() => {});
  harness.setSection(() => {});
  harness.setInfo(() => {});

  const firstRun = await harness.ensureNwidartComposerMergeConfig(
    projectPath,
    new Set(["nwidart/laravel-modules"]),
  );
  const secondRun = await harness.ensureNwidartComposerMergeConfig(
    projectPath,
    new Set(["nwidart/laravel-modules"]),
  );

  const composerJson = JSON.parse(fs.readFileSync(path.join(projectPath, "composer.json"), "utf8"));
  assert.equal(firstRun, true);
  assert.equal(secondRun, false);
  assert.equal(Object.hasOwn(composerJson.autoload["psr-4"], "Modules\\"), false);
  assert.deepEqual(composerJson.extra["merge-plugin"].include, ["Modules/*/composer.json"]);
});

test("ensureNwidartViteMainConfig rewrites a default vite config and preserves server settings", async () => {
  const harness = loadInstallerHarness();
  const projectPath = createNwidartProjectFixture();

  harness.setWarn(() => {});
  harness.setOk(() => {});

  const changed = await harness.ensureNwidartViteMainConfig(
    projectPath,
    new Set(["nwidart/laravel-modules"]),
  );
  const viteConfig = fs.readFileSync(path.join(projectPath, "vite.config.js"), "utf8");

  assert.equal(changed, true);
  assert.match(viteConfig, /collectModuleAssetsPaths/);
  assert.match(viteConfig, /input: allPaths/);
  assert.match(viteConfig, /server: \{/);
  assert.match(viteConfig, /host: '0\.0\.0\.0'/);
});

test("ensureNwidartModuleStatusesFile and ensureNwidartModulesDirectory create expected filesystem state", async () => {
  const harness = loadInstallerHarness();
  const projectPath = fs.mkdtempSync(path.join(os.tmpdir(), "instalar-module-statuses-"));

  harness.setWarn(() => {});
  harness.setOk(() => {});

  const createdModulesDir = await harness.ensureNwidartModulesDirectory(
    projectPath,
    new Set(["nwidart/laravel-modules"]),
  );
  fs.mkdirSync(path.join(projectPath, "Modules", "Admin"), { recursive: true });
  fs.mkdirSync(path.join(projectPath, "Modules", "Billing"), { recursive: true });

  const createdStatuses = await harness.ensureNwidartModuleStatusesFile(
    projectPath,
    new Set(["nwidart/laravel-modules"]),
  );
  const statuses = JSON.parse(
    fs.readFileSync(path.join(projectPath, "modules_statuses.json"), "utf8"),
  );

  assert.equal(createdModulesDir, true);
  assert.equal(createdStatuses, true);
  assert.deepEqual(statuses, {
    Admin: true,
    Billing: true,
  });
});
