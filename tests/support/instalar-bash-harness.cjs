const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

function extractInstallerShellSource() {
  const installerPath = path.join(__dirname, "..", "..", "instalar.sh");
  const installerSource = fs.readFileSync(installerPath, "utf8");
  const marker = '\n# Execute the main Bash function with all CLI arguments\nmain_bash "$@"\n';
  const index = installerSource.indexOf(marker);

  if (index === -1) {
    throw new Error("Installer shell source could not be extracted from instalar.sh");
  }

  return installerSource.slice(0, index);
}

function runBashHarness(script, options = {}) {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "instalar-bash-harness-"));
  const harnessPath = path.join(tempDir, "instalar-shell.sh");

  fs.writeFileSync(harnessPath, `${extractInstallerShellSource()}\n`, "utf8");

  const result = spawnSync(
    "bash",
    ["-c", `source "$INSTALAR_BASH_HARNESS"\n${script}`],
    {
      encoding: "utf8",
      input: options.input ?? "",
      env: {
        ...process.env,
        INSTALAR_BASH_HARNESS: harnessPath,
        ...options.env,
      },
    },
  );

  fs.rmSync(tempDir, { recursive: true, force: true });

  return result;
}

module.exports = {
  runBashHarness,
};
