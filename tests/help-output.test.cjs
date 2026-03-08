const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { readInstallerMetadata } = require("./support/instalar-metadata.cjs");

test("help output documents the current installer flags and version", () => {
  const installerPath = path.join(__dirname, "..", "instalar.sh");
  const installer = readInstallerMetadata();
  const result = spawnSync("bash", [installerPath, "--help"], {
    encoding: "utf8",
  });
  const output = result.stdout ?? "";

  assert.equal(result.status, 0);
  assert.match(output, new RegExp(`INSTALAR v${installer.version.replaceAll(".", "\\.")}`));
  assert.match(output, /--print-plan/);
  assert.match(output, /--preset <name>/);
  assert.match(output, /--skip-boost-install/);
  assert.match(output, /--allow-delete-any-existing/);
  assert.match(output, /--continue-on-health-check-failure/);
  assert.match(output, /Collect input and print the resolved plan/);
  assert.match(output, /Package preset: minimal, standard, or full/);
  assert.match(output, /Skip interactive boost:install step/);
  assert.match(output, /Also allow replacing generic or git-managed directories/);
  assert.match(output, /Continue unattended runs even when final health checks fail/);
});
