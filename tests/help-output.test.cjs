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
  assert.match(output, /Modes:/);
  assert.match(output, /Common options:/);
  assert.match(output, /Automation:/);
  assert.match(output, /Safety:/);
  assert.match(output, /Examples:/);
  assert.match(output, /--dry-run/);
  assert.match(output, /--print-plan/);
  assert.match(output, /--log-file <path>/);
  assert.match(output, /--preset <name>/);
  assert.match(output, /--skip-boost-install/);
  assert.match(output, /--allow-delete-any-existing/);
  assert.match(output, /--continue-on-health-check-failure/);
  assert.match(output, /--mode <auto\|manual\|update\|doctor>/);
  assert.match(output, /Guided step-by-step project setup/);
  assert.match(output, /Diagnose the Laravel project in the current directory/);
  assert.match(output, /Resolve input, print the plan, and exit without modifying files/);
  assert.match(output, /Legacy alias for --dry-run/);
  assert.match(output, /Write installer output to a plain-text log file/);
  assert.match(output, /Package preset: minimal, standard, or full/);
  assert.match(output, /Skip interactive boost:install step/);
  assert.match(output, /Also allow replacing generic or git-managed directories/);
  assert.match(output, /Continue unattended runs even when final health checks fail/);
  assert.match(output, /\.\/instalar\.sh --mode manual/);
  assert.match(output, /\.\/instalar\.sh --mode doctor --log-file \.\/doctor\.log/);
});
