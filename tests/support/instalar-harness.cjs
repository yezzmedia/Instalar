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

function readInstallerShellMetadata() {
  const installerPath = path.join(__dirname, "..", "..", "instalar.sh");
  const installerSource = fs.readFileSync(installerPath, "utf8");
  const versionMatch = installerSource.match(/SCRIPT_VERSION="([^"]+)"/);
  const codenameMatch = installerSource.match(/SCRIPT_CODENAME="([^"]+)"/);

  if (!versionMatch || !codenameMatch) {
    throw new Error("Installer shell metadata could not be extracted");
  }

  return {
    version: versionMatch[1],
    codename: codenameMatch[1],
  };
}

function loadInstallerHarness() {
  const metadata = readInstallerShellMetadata();
  const source = `${extractEmbeddedNodeSource()}
globalThis.__instalarTest = {
  state,
  OPTIONAL_PACKAGE_CHOICES,
  PACKAGE_PRESETS,
  parseCliArgs,
  validateInstallerConfig,
  resolveRuntime,
  resolveLogFilePath,
  warnDoctorModeIgnoredOptions,
  resolvePackagePresetName,
  getPackagePresetById,
  ask,
  askSecret,
  askYesNo,
  initializeRuntimeLog,
  stripAnsi,
  buildCommandFailureSnippet,
  formatCommandForDisplay,
  normalizeLaravelTestSuiteFlag,
  normalizeLaravelFlags,
  splitPackageInput,
  mergePackageSpecs,
  packageNameFromSpec,
  getOptionIndexesByIds,
  envSafeValue,
  setEnvValue,
  applyEnvConfig,
  resolveAuthUserModel,
  readComposerPackages,
  isLaravelProject,
  classifyExistingPath,
  describePathClassification,
  canDeleteExistingPathNonInteractive,
  describeExistingPathStrategy,
  getProtectedPathReason,
  ensureSafeProjectTarget,
  getBackupTargetPath,
  resolveAdminCredentials,
  describeAdminPasswordStrategy,
  configUsesSensitiveValues,
  packageSetFromConfig,
  extractObjectPropertyBlock,
  indentLines,
  ensureComposerPluginAllowList,
  ensureNwidartComposerMergeConfig,
  ensureNwidartViteMainConfig,
  ensureNwidartModuleStatusesFile,
  ensureNwidartModulesDirectory,
  collectAutoConfig,
  collectManualConfig,
  printInstallPlan,
  printUpdatePlan,
  runPermissionChecks,
  runCommand,
  runHealthChecks,
  runDoctorFlow,
  setRunCommand(value) { runCommand = value; },
  setAsk(value) { ask = value; },
  setAskRequired(value) { askRequired = value; },
  setAskYesNo(value) { askYesNo = value; },
  setAskChoice(value) { askChoice = value; },
  setAskMultiChoice(value) { askMultiChoice = value; },
  setAskMultiChoiceWithAll(value) { askMultiChoiceWithAll = value; },
  setAskSecret(value) { askSecret = value; },
  setInfo(value) { info = value; },
  setWarn(value) { warn = value; },
  setOk(value) { ok = value; },
  setFail(value) { fail = value; },
  setSection(value) { section = value; },
};
`;

  const fakeProcess = {
    env: {
      ...process.env,
      INSTALAR_SCRIPT_VERSION: metadata.version,
      INSTALAR_SCRIPT_CODENAME: metadata.codename,
    },
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

  fs.mkdirSync(path.join(projectPath, "bootstrap"), { recursive: true });
  fs.mkdirSync(path.join(projectPath, "bootstrap", "cache"), { recursive: true });
  fs.mkdirSync(path.join(projectPath, "public", "build"), { recursive: true });
  fs.mkdirSync(path.join(projectPath, "storage", "app", "public"), { recursive: true });
  fs.writeFileSync(path.join(projectPath, "artisan"), "#!/usr/bin/env php\n", "utf8");
  fs.writeFileSync(path.join(projectPath, "bootstrap", "app.php"), "<?php\n", "utf8");
  fs.writeFileSync(
    path.join(projectPath, "composer.json"),
    JSON.stringify(
      {
        require: {
          "laravel/framework": "^12.0",
        },
      },
      null,
      4,
    ),
    "utf8",
  );
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
