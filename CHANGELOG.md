# Changelog

All notable changes to this project will be documented in this file.

## [0.1.10] - 2026-03-08 (Rosie)

### Added

- `--dry-run` as the primary preview flag, with `--print-plan` kept as a legacy alias
- `--log-file <path>` plus matching JSON `logFile` support for plain-text installer logs
- Logging-focused regression coverage for runtime log output and command-failure context

### Changed

- Runtime plans now show whether the run is preview-only and where logs are written
- Relative `logFile` values from JSON config are resolved against the config file directory
- Final summary output is mirrored into the installer log file

### Fixed

- Capture recent stdout/stderr snippets for failed commands to make debugging faster
- Keep README, help output, and release metadata aligned with the new runtime logging flags

## [0.1.9] - 2026-03-08 (Rosie)

### Added

- Strict JSON config validation for unknown keys, invalid presets, and invalid nested values
- `--allow-delete-any-existing` / `allowDeleteAnyExisting` for explicitly replacing generic non-empty or Git-managed paths
- Secret-aware tests for hidden prompts, command redaction, and admin password handling

### Changed

- DB password prompts are now masked and hidden in non-interactive logs
- Installation plans now show path classification, secret usage, and admin password strategy without exposing plaintext values
- Filament admin creation no longer passes the password through process arguments
- Non-interactive replacement rules now distinguish empty directories, Laravel projects, Git repositories, and generic paths

### Fixed

- Stop echoing configured or default admin passwords in the final summary
- Resolve imported auth model aliases correctly when creating the Filament admin user
- Align README/help/release metadata with the hardened installer behavior

## [0.1.8] - 2026-03-08 (Rosie)

### Added

- `--print-plan` CLI/config preview mode to resolve install or update choices without modifying files
- `--preset <minimal|standard|full>` package presets for faster Auto and Manual setup
- `--skip-boost-install` CLI/config override to skip the interactive Boost step
- Plan-output tests for presets, preview mode, and path replacement behavior

### Changed

- Auto and Manual flows now surface a package preset before package selection
- Install and update flows now print a resolved execution plan before they start
- Final next-step notes now print only after health checks and permission checks complete
- Optional package prompts now include categories and short summaries

### Fixed

- Align README, help output, and release metadata with the new UX flags
- Replace the last visible mixed-language dependency update status line in the Bash phase

## [0.1.7] - 2026-03-08 (Rosie)

### Added

- `--continue-on-health-check-failure` CLI override and matching JSON config support for unattended runs
- Node-based consistency tests for runtime option merging and release metadata
- GitHub Actions CI workflow for Bash syntax, ShellCheck, help smoke tests, and Node tests
- GitHub Actions draft-release workflow for `v*` tags using the latest changelog section

### Changed

- Health checks now run through a unified evaluation flow before deciding whether to abort or continue
- Release metadata now includes an explicit installer codename for tag validation

### Fixed

- Keep installer version, README version, changelog header, and release tag format aligned

## [0.1.6] - 2026-03-08 (Rosie)

### Fixed

- Sync installer version output with the documented release version
- Count failed `php artisan about`, `migrate:status`, and `route:list` checks in the final health-check result
- Abort explicitly in non-interactive mode when a health check fails instead of falling through an implicit prompt default

## [0.1.5] - 2026-02-24 (Rosie)

### Added

- 6 new optional packages: Laravel Excel, IDE Helper, Migration Generator, Spatie Model Types, Breadcrumbs, Flare
- Enhanced health checks: APP_KEY, database connection, storage link, composer validation
- Auto-create storage link when missing (with retry option in interactive mode)
- User prompt on health check failure (ask to continue or abort)
- `--verbose` flag for detailed output
- `--debug` flag for debug mode (shows all commands, uses `set -x`)

### Changed

- `runCommand()` now returns exit code for better error handling

### Fixed

- Correct package name: `spatie/model-states` -> `spatie/laravel-model-states`
- Replace deprecated `facade/ignition` with `spatie/laravel-ignition` for Laravel 12 compatibility

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
