const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { loadInstallerHarness } = require("./support/instalar-harness.cjs");

test("readComposerPackages excludes platform requirements from doctor package reporting", () => {
  const harness = loadInstallerHarness();
  const projectPath = fs.mkdtempSync(path.join(os.tmpdir(), "instalar-doctor-packages-"));

  fs.writeFileSync(
    path.join(projectPath, "composer.json"),
    JSON.stringify(
      {
        require: {
          php: "^8.5",
          "ext-json": "*",
          "laravel/framework": "^12.0",
        },
        "require-dev": {
          "pestphp/pest": "^4.0",
        },
      },
      null,
      4,
    ),
    "utf8",
  );

  assert.deepEqual(
    [...harness.readComposerPackages(projectPath)].sort(),
    ["laravel/framework", "pestphp/pest"],
  );
});
