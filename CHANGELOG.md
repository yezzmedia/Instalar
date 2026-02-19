# Changelog

All notable changes to this project will be documented in this file.

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
