const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const vm = require("node:vm");

function extractEmbeddedNodeSource() {
  const installerPath = path.join(__dirname, "..", "instalar.sh");
  const installerSource = fs.readFileSync(installerPath, "utf8");
  const match = installerSource.match(/<<'NODE'\n([\s\S]*?)\nNODE\n/);

  if (!match) {
    throw new Error("Embedded Node.js source could not be extracted from instalar.sh");
  }

  return match[1].replace(
    /\/\/ Global top-level error handler for the Node phase\.[\s\S]*$/,
    "",
  );
}

function loadHealthCheckHarness() {
  const source = `${extractEmbeddedNodeSource()}
globalThis.__instalarTest = {
  state,
  runHealthChecks,
  setRunCommand(value) { runCommand = value; },
  setAskYesNo(value) { askYesNo = value; },
  setInfo(value) { info = value; },
  setWarn(value) { warn = value; },
  setOk(value) { ok = value; },
  setFail(value) { fail = value; },
  setSection(value) { section = value; },
};
`;

  const fakeProcess = {
    env: process.env,
    argv: [],
    stdin: { isTTY: false },
    stdout: { isTTY: false, write() {} },
    stderr: { write() {} },
    cwd: () => process.cwd(),
    exitCode: 0,
    exit(code) {
      throw new Error(`EXIT:${code}`);
    },
  };

  const context = {
    require,
    console,
    Buffer,
    process: fakeProcess,
    setTimeout,
    clearTimeout,
    setInterval,
    clearInterval,
  };
  context.globalThis = context;

  vm.runInNewContext(source, context, { filename: "instalar-node.cjs" });

  return context.__instalarTest;
}

function createProjectFixture() {
  const projectPath = fs.mkdtempSync(path.join(os.tmpdir(), "instalar-health-check-"));

  fs.mkdirSync(path.join(projectPath, "public", "build"), { recursive: true });
  fs.mkdirSync(path.join(projectPath, "storage", "app", "public"), { recursive: true });
  fs.writeFileSync(
    path.join(projectPath, ".env"),
    "APP_KEY=base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n",
  );
  fs.writeFileSync(path.join(projectPath, "public", "build", "manifest.json"), "{}\n");
  fs.symlinkSync(
    path.join(projectPath, "storage", "app", "public"),
    path.join(projectPath, "public", "storage"),
  );

  return projectPath;
}

test("runHealthChecks handles failed artisan checks for interactive and non-interactive runs", async () => {
  const nonInteractiveHarness = loadHealthCheckHarness();
  const nonInteractiveProjectPath = createProjectFixture();
  const nonInteractiveFailures = [];

  nonInteractiveHarness.state.runtime = { nonInteractive: true };
  nonInteractiveHarness.setSection(() => {});
  nonInteractiveHarness.setInfo(() => {});
  nonInteractiveHarness.setWarn(() => {});
  nonInteractiveHarness.setOk(() => {});
  nonInteractiveHarness.setAskYesNo(async () => {
    throw new Error("askYesNo should not be called in non-interactive mode");
  });
  nonInteractiveHarness.setFail((message) => {
    nonInteractiveFailures.push(message);
  });
  nonInteractiveHarness.setRunCommand(async (command, args) => {
    if (command === "composer" && args[0] === "validate") {
      return { exitCode: 0, success: true };
    }

    if (command === "php" && args[0] === "artisan" && args[1] === "db:show") {
      return { exitCode: 0, success: true };
    }

    if (command === "php" && args[0] === "artisan" && args[1] === "about") {
      return { exitCode: 1, success: false };
    }

    return { exitCode: 0, success: true };
  });

  await assert.rejects(nonInteractiveHarness.runHealthChecks(nonInteractiveProjectPath), /EXIT:1/);
  assert.deepEqual(nonInteractiveFailures, [
    "Health check failed for: php artisan about",
    "Installation aborted because health checks failed in non-interactive mode.",
  ]);

  const interactiveHarness = loadHealthCheckHarness();
  const interactiveProjectPath = createProjectFixture();
  const prompts = [];
  const interactiveFailures = [];

  interactiveHarness.state.runtime = { nonInteractive: false };
  interactiveHarness.setSection(() => {});
  interactiveHarness.setInfo(() => {});
  interactiveHarness.setWarn(() => {});
  interactiveHarness.setOk(() => {});
  interactiveHarness.setFail((message) => {
    interactiveFailures.push(message);
  });
  interactiveHarness.setAskYesNo(async (question, defaultYes) => {
    prompts.push({ question, defaultYes });
    return true;
  });
  interactiveHarness.setRunCommand(async (command, args) => {
    if (command === "composer" && args[0] === "validate") {
      return { exitCode: 0, success: true };
    }

    if (command === "php" && args[0] === "artisan" && args[1] === "route:list") {
      return { exitCode: 1, success: false };
    }

    return { exitCode: 0, success: true };
  });

  await interactiveHarness.runHealthChecks(interactiveProjectPath);

  assert.deepEqual(interactiveFailures, ["Health check failed for: php artisan route:list"]);
  assert.deepEqual(prompts, [
    { question: "Do you want to continue anyway?", defaultYes: false },
  ]);
});
