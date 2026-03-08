const fs = require("node:fs");
const path = require("node:path");

function readRepositoryFile(name) {
  return fs.readFileSync(path.join(__dirname, "..", "..", name), "utf8");
}

function readInstallerMetadata() {
  const source = readRepositoryFile("instalar.sh");
  const versionMatch = source.match(/SCRIPT_VERSION="([^"]+)"/);
  const codenameMatch = source.match(/SCRIPT_CODENAME="([^"]+)"/);

  if (!versionMatch || !codenameMatch) {
    throw new Error("Installer version metadata could not be parsed");
  }

  return {
    version: versionMatch[1],
    codename: codenameMatch[1],
    expectedTag: `v${versionMatch[1]}-${codenameMatch[1]}`,
  };
}

function readReadmeMetadata() {
  const source = readRepositoryFile("README.md");
  const match = source.match(/Current version:\s+\*\*([^\*]+)\*\*\s+\(([^)]+)\)/);

  if (!match) {
    throw new Error("README release metadata could not be parsed");
  }

  return {
    version: match[1].trim(),
    codename: match[2].trim(),
  };
}

function readChangelogMetadata() {
  const source = readRepositoryFile("CHANGELOG.md");
  const match = source.match(/^## \[([^\]]+)\] - ([^(]+)\(([^)]+)\)$/m);

  if (!match) {
    throw new Error("CHANGELOG release metadata could not be parsed");
  }

  return {
    version: match[1].trim(),
    date: match[2].trim(),
    codename: match[3].trim(),
  };
}

function readLatestChangelogSection() {
  const source = readRepositoryFile("CHANGELOG.md");
  const lines = source.split("\n");
  const startIndex = lines.findIndex((line) => line.startsWith("## ["));

  if (startIndex === -1) {
    throw new Error("No changelog release section could be found");
  }

  let endIndex = lines.length;
  for (let index = startIndex + 1; index < lines.length; index += 1) {
    if (lines[index].startsWith("## [")) {
      endIndex = index;
      break;
    }
  }

  return lines.slice(startIndex, endIndex).join("\n").trim();
}

module.exports = {
  readChangelogMetadata,
  readInstallerMetadata,
  readLatestChangelogSection,
  readReadmeMetadata,
};
