# Changelog

All notable changes to this project will be documented in this file.

## [0.1.18] - 2026-03-13 (Rosie)

### Added

- A project logo and a direct `curl -fsSL https://yezzmedia.com/instalar.sh | bash` quick-start path in the README
- A moving activity bar for long-running installer commands when command output stays hidden
- `--display-command-output` and `--display-info` to reveal live subprocess output on demand

### Changed

- Composer, npm, and Artisan subprocess output now stays hidden by default so auto and manual mode remain readable
- Manual-mode step cards and top-level sections now use a more polished visual structure with clearer progress feedback
- Reverb and module-related setup commands now stay visibly interactive when they may ask follow-up questions

### Fixed

- Skip potentially interactive Reverb and module setup commands in non-interactive runs and record clear manual follow-up steps instead of letting the installer hang

## [0.1.17] - 2026-03-13 (Rosie)

### Added

- `--upgrade-dependencies` to opt into `composer update` during update mode
- Bash-phase minimum version checks for required dependencies before the Node runtime starts
- Regression coverage for safer update planning, final warning separation, custom Nwidart Vite fallbacks, and minimum-version enforcement

### Changed

- Update mode now defaults to lockfile-safe `composer install` and only upgrades dependencies when requested explicitly
- Final completion output now shows only unresolved run warnings instead of transient prompt validation noise
- Refactored the Node entrypoint into smaller mode dispatch helpers so auto, manual, update, and detected-project flows share less duplicated control flow

### Fixed

- Skip aggressive automatic rewrites for customized `vite.config.js` files in Nwidart projects and keep them unchanged with a clear warning instead
- Record continued health-check and permission issues in the final completion summary when a run is allowed to finish anyway

## [0.1.16] - 2026-03-11 (Rosie)

### Fixed

- Corrected the interactive multi-select redraw logic so the Manual-mode package picker no longer shifts the screen on arrow-key navigation
- Made the multi-select renderer account for wrapped terminal rows, which restores reliable up/down navigation for longer package labels

## [0.1.15] - 2026-03-10 (Rosie)

### Added

- A bolder modern-terminal presentation across install, update, doctor, completion, and error output
- A mode-aware onboarding intro for guided runs
- Mermaid diagrams and a redesigned landing-plus-reference README structure

### Changed

- Renamed review and summary sections to feel more guided and easier to scan
- Refreshed `--help` and top-level banner copy around a stronger "start here / run controls" structure
- Reworked Manual mode so the flow opens with a clearer onboarding section before the step cards
- Expanded output-focused regression coverage to lock in the new plan, review, and help layouts

## [0.1.13] - 2026-03-09 (Rosie)

### Added

- Coverage for the grouped plan output, final summary output, Manual-mode review step, and non-interactive Manual-mode dry-run flow

### Changed

- Refreshed the CLI interface with a smaller startup header and cleaner grouped help output
- Reworked Manual mode into a step-based guided flow for project, database, starter, package, and admin setup
- Replaced the flat install and update plan dumps with grouped review sections and compact package lists
- Improved Doctor and completion summaries to group project details, next actions, and unresolved issues
- Clarified prompt copy and selection input labels to feel more guided and less raw

### Fixed

- Kept README, help output, and release metadata aligned with the refreshed interface

## [0.1.12] - 2026-03-09 (Rosie)

### Added

- `doctor` mode for auditing the current Laravel project with a focused health and permission report
- Interactive Doctor-mode repair support for a missing `public/storage` symlink
- Doctor-focused regression coverage for report-only runs, safe repairs, ignored install-only settings, and Nwidart status reporting

### Changed

- Refactored health checks and permission checks into reusable diagnostics building blocks shared by install, update, and Doctor mode
- Help output and README now document `--mode doctor` and its report-only behavior in unattended runs

### Fixed

- Keep Doctor mode read-only in `--non-interactive` and `--dry-run` runs by suppressing repair prompts
- Return a non-zero exit code from Doctor mode when unresolved issues remain

## [0.1.11] - 2026-03-09 (Rosie)

### Added

- Comment-focused coverage for prompt-driven config collection, normalization helpers, and Nwidart rewrite helpers

### Changed

- Normalized the remaining installer prompts, comments, and documentation to English-only wording
- Expanded inline installer comments around runtime resolution, command execution, path safety, env mutation, and setup orchestration
- Restored `node --test` as the primary documented quality gate while keeping the explicit `tests/*.cjs` fallback for local sample apps

### Fixed

- Ignore dot-prefixed local sample app directories used to keep Node test discovery clean
- Align CI workflow expectations with the documented default Node test command

## [0.1.10] - 2026-03-09 (Rosie)

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
- Pass release metadata from the Bash entrypoint into the embedded Node runtime for real dry-run logging

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
- Manual mode multi-select UX with arrows + space + enter, including "Select all".
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
