const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const vm = require("node:vm");

function extractEmbeddedNodeSource() {
  const installerPath = path.join(__dirname, "..", "..", "instalar.sh");
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

function loadInstallerHarness() {
  const source = `${extractEmbeddedNodeSource()}
globalThis.__instalarTest = {
  state,
  parseCliArgs,
  validateInstallerConfig,
  resolveRuntime,
  resolvePackagePresetName,
  getPackagePresetById,
  askSecret,
  formatCommandForDisplay,
  classifyExistingPath,
  describePathClassification,
  canDeleteExistingPathNonInteractive,
  describeExistingPathStrategy,
  resolveAdminCredentials,
  printInstallPlan,
  printUpdatePlan,
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

module.exports = {
  createProjectFixture,
  loadInstallerHarness,
};
