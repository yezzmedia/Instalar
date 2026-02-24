# Changelog

All notable changes to this project will be documented in this file.

## [0.1.5] - 2026-02-24 (Rosie)

### Added

- 6 new optional packages: Laravel Excel, IDE Helper, Migration Generator, Spatie Model Types, Breadcrumbs, Flare
- Enhanced health checks: APP_KEY, database connection, storage link, composer validation
- User prompt on health check failure (ask to continue or abort)
- `--verbose` flag for detailed output
- `--debug` flag for debug mode (shows all commands, uses `set -x`)

### Changed

- `runCommand()` now returns exit code for better error handling

## [0.1.4] - 2026-02-24 (Rosie)

### Added

- Comprehensive inline comments in embedded Node.js phase using //
- Full PHPDoc-style documentation for all major functions

## [0.1.3] - 2026-02-23 (Rosie)

### Added

- Comprehensive inline comments in Bash phase using #
- Full documentation for all major functions and sections

## [0.1.2] - 2026-02-21 (Rosie)

### Fixed

- Hardened interactive TTY handling for piped execution
- Use /dev/tty for prompts, abort interactive mode without terminal
- Pass TTY stdin into embedded Node phase

## [0.1.1] - 2026-02-20 (Rosie)

### Added

- Pest as default test suite for auto installations
- Selectable test suite (Pest vs PHPUnit) in manual mode
- "testSuite" option in JSON config support

## [0.1.0] - 2026-02-19

### Added

- Bash entrypoint with interactive dependency verification and version table.
- Missing dependency install flow and update flow with available-version preview.
- Non-interactive mode with JSON config support (`--non-interactive`, `--config`).
- Manual mode multi-select UX with arrows + space + enter, including "Alles auswaehlen".
- Existing target directory delete confirmation before project creation.
- Optional backup flow for existing directories (`--backup`).
- Optional generated admin password (`--admin-generate`).
- Nwidart modules setup automation:
  - allow-plugins handling for `wikimedia/composer-merge-plugin`
  - `extra.merge-plugin.include` management
  - legacy `Modules\\` autoload removal
  - `Modules/` and `modules_statuses.json` creation
  - vite module loader integration
  - `CoreModule` creation and Filament module install
- Final permissions check and optional `composer run dev` startup.
- Post-install health checks (`about`, `migrate:status`, `route:list`, Vite manifest).

### Changed

- Project creation now uses `laravel new`.
- `boost:install` is interactive and runs after setup commands.
- `optimize` runs before `npm install` and `npm run build`.
- Banner and startup output redesigned.

### Fixed

- Prevented duplicate Fortify two-factor migration issues.
- Added safer handling for optional install commands not available in all setups.
- Fixed reverb install handling for interactive requirements.
- Added explicit module asset compile prerequisites to avoid Vite ENOENT errors.
