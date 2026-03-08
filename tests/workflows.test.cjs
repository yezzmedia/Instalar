const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

function readWorkflow(name) {
  return fs.readFileSync(path.join(__dirname, "..", ".github", "workflows", name), "utf8");
}

test("CI workflow runs the expected installer quality gates", () => {
  const workflow = readWorkflow("ci.yml");

  assert.match(workflow, /pull_request:/);
  assert.match(workflow, /branches:\s*\n\s*-\s*main/);
  assert.match(workflow, /bash -n instalar\.sh/);
  assert.match(workflow, /shellcheck instalar\.sh/);
  assert.match(workflow, /\.\/instalar\.sh --help/);
  assert.match(workflow, /node --test/);
});

test("release workflow validates metadata and manages draft releases for tags", () => {
  const workflow = readWorkflow("release-draft.yml");

  assert.match(workflow, /tags:\s*\n\s*-\s*"v\*"/);
  assert.match(workflow, /readInstallerMetadata/);
  assert.match(workflow, /readLatestChangelogSection/);
  assert.match(workflow, /release-notes\.md/);
  assert.match(workflow, /draft:\s*true/);
  assert.match(workflow, /createRelease/);
  assert.match(workflow, /updateRelease/);
});
