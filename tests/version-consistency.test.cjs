const test = require("node:test");
const assert = require("node:assert/strict");

const {
  readChangelogMetadata,
  readInstallerMetadata,
  readLatestChangelogSection,
  readReadmeMetadata,
} = require("./support/instalar-metadata.cjs");

test("installer, README, and changelog share the same release metadata", () => {
  const installer = readInstallerMetadata();
  const readme = readReadmeMetadata();
  const changelog = readChangelogMetadata();

  assert.deepEqual(readme, {
    version: installer.version,
    codename: installer.codename,
  });
  assert.deepEqual(
    { version: changelog.version, codename: changelog.codename },
    { version: installer.version, codename: installer.codename },
  );
  assert.equal(installer.expectedTag, `v${installer.version}-${installer.codename}`);
});

test("latest changelog section matches the current release header", () => {
  const installer = readInstallerMetadata();
  const changelog = readChangelogMetadata();
  const latestSection = readLatestChangelogSection();
  const releaseHeaders = latestSection.match(/^## \[/gm) ?? [];

  assert.match(
    latestSection,
    new RegExp(
      `^## \\[${installer.version.replaceAll(".", "\\.")}\\] - ${changelog.date} \\(${installer.codename}\\)`,
    ),
  );
  assert.equal(releaseHeaders.length, 1, "latest section should contain exactly one release heading");
});
