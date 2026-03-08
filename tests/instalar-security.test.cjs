const test = require("node:test");
const assert = require("node:assert/strict");

const { loadInstallerHarness } = require("./support/instalar-harness.cjs");

test("askSecret hides secret values in non-interactive mode", async () => {
  const harness = loadInstallerHarness();
  const infos = [];

  harness.state.runtime = {
    ...harness.state.runtime,
    nonInteractive: true,
  };
  harness.setInfo((message) => {
    infos.push(message);
  });

  const value = await harness.askSecret("DB Password", "super-secret");

  assert.equal(value, "super-secret");
  assert.deepEqual(infos, ["[non-interactive] DB Password: (hidden)"]);
});

test("formatCommandForDisplay redacts secret values from logged commands", () => {
  const harness = loadInstallerHarness();

  const command = harness.formatCommandForDisplay(
    "php",
    ["artisan", "some:command", "--password=super-secret"],
    ["super-secret"],
  );

  assert.equal(command, "php artisan some:command --password=[REDACTED]");
});

test("resolveAdminCredentials only reveals generated passwords", () => {
  const harness = loadInstallerHarness();

  harness.state.runtime.adminGenerate = true;
  harness.setInfo(() => {});
  harness.setWarn(() => {});

  const generated = harness.resolveAdminCredentials({}, true);
  const configured = harness.resolveAdminCredentials(
    { admin: { password: "configured-secret" } },
    true,
  );

  harness.state.runtime.adminGenerate = false;
  const fallback = harness.resolveAdminCredentials({}, true);

  assert.equal(generated.passwordSource, "generated");
  assert.equal(generated.revealPassword, true);
  assert.ok(generated.password.length >= 20);
  assert.equal(configured.passwordSource, "config");
  assert.equal(configured.revealPassword, false);
  assert.equal(fallback.passwordSource, "default");
  assert.equal(fallback.revealPassword, false);
});
