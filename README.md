# INSTALAR

[![Version](https://img.shields.io/github/v/release/yezzmedia/Instalar?include_prereleases&style=flat&color=blue)](https://github.com/yezzmedia/Instalar/releases)
[![License](https://img.shields.io/github/license/yezzmedia/Instalar?style=flat&color=green)](LICENSE)
[![PHP Version](https://img.shields.io/badge/PHP-8.5-blue?style=flat)](https://www.php.net/)
[![Laravel](https://img.shields.io/badge/Laravel-12-blue?style=flat)](https://laravel.com/)
[![Filament](https://img.shields.io/badge/Filament-5-blueviolet?style=flat)](https://filamentphp.com/)

Reference installer for Laravel 12 + Filament 5.

Made with ❤️ by [yezzmedia.com](https://yezzmedia.com) *(coming soon)*

`instalar.sh` is intentionally built as a **single file**:

- Bash entrypoint for dependency checks/install/update
- Embedded Node installer for interactive and configurable project setup

Current version: **0.1.10** (Rosie)

---

## What INSTALAR does

- Creates new Laravel 12 projects (`laravel new`) or updates existing ones.
- Supports **Auto**, **Manual**, and **Update** modes.
- Prints a resolved install or update plan before execution.
- Supports preview-only runs and plain-text installer logs.
- Hides sensitive values in prompts and logs wherever possible.
- Checks system dependencies with versions (`php`, `composer`, `laravel`, `node`, `npm`).
- Installs missing dependencies and can apply available dependency updates.
- Supports package presets (`minimal`, `standard`, `full`) and richer optional package labels.
- Installs and configures Filament, Fortify, Boost, and optional packages.
- Runs build/optimize steps in a practical order.
- Runs post-install health checks and permission checks.
- Can optionally run `composer run dev` at the end.

---

## Quick Start

```bash
chmod +x instalar.sh
./instalar.sh
```

Help:

```bash
./instalar.sh --help
```

---

## Cheatsheet (Copy/Paste)

```bash
# 1) Standard interactive run
./instalar.sh

# 2) Non-interactive with local config (./instalar.json)
./instalar.sh --non-interactive

# 3) Non-interactive with explicit config + manual mode
./instalar.sh --non-interactive --config ./instalar.json --mode manual

# 4) Replace existing target, keep backup, generate admin password
./instalar.sh --non-interactive --mode auto --allow-delete-existing --backup --admin-generate

# 4b) Replace a generic non-empty path only with the explicit high-risk override
./instalar.sh --non-interactive --mode auto --allow-delete-any-existing

# 5) Update existing Laravel project in current directory
./instalar.sh --mode update

# 6) Apply dependency updates during Bash dependency stage
./instalar.sh --deps-update

# 7) Verbose output for debugging
./instalar.sh --verbose

# 8) Preview the resolved plan without creating or updating files
./instalar.sh --dry-run

# 8b) Write installer output to a plain-text log file
./instalar.sh --log-file ./instalar.log

# 9) Use the full package preset and skip boost:install
./instalar.sh --mode auto --preset full --skip-boost-install

# 10) Debug mode (shows all commands)
./instalar.sh --debug

# 11) Continue unattended runs even when health checks fail
./instalar.sh --non-interactive --continue-on-health-check-failure
```

---

## Architecture (Flow)

```text
┌──────────────────────────────────────────────────────────────┐
│ Bash Entrypoint (instalar.sh)                                │
│ - Banner                                                     │
│ - Dependency check (php/composer/laravel/node/npm)           │
│ - Optional install/update of missing tools                   │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│ Embedded Node Installer (same file)                          │
│ - CLI args + optional instalar.json                          │
│ - Auto / Manual / Update mode                                │
└──────────────────────────────────────────────────────────────┘
                │                      │                    │
                ▼                      ▼                    ▼
         Auto Installation      Manual Installation      Update Flow
                │                      │                    │
                └──────────────┬───────┴──────────────┬─────┘
                               ▼                      ▼
                    Setup + Migrate + Boost   Optimize + Frontend Build
                               │
                               ▼
                    Health Check + Permission Check
                               │
                               ▼
                    Optional: composer run dev
```

---

## CLI Options

| Option | Description |
|---|---|
| `--help` | Show help |
| `--config <file>` | Load JSON configuration file |
| `--non-interactive`, `-y`, `--yes` | Run without prompts, use defaults/config |
| `--dry-run` | Collect input, print the resolved install/update plan, and exit |
| `--print-plan` | Legacy alias for `--dry-run` |
| `--log-file <path>` | Write installer output to a plain-text log file |
| `--preset <minimal\|standard\|full>` | Choose the default optional package bundle |
| `--skip-boost-install` | Skip the interactive `php artisan boost:install` step |
| `--continue-on-health-check-failure` | Continue non-interactive runs after failed final health checks |
| `--mode <auto\|manual\|update>` | Force mode |
| `--backup` | Backup existing target directory before replacing |
| `--admin-generate` | Generate admin password instead of `password` |
| `--allow-delete-existing` | Allow replacing existing target directory in non-interactive mode |
| `--allow-delete-any-existing` | Also allow replacing generic or git-managed paths in non-interactive mode |
| `--start-server` | Run `composer run dev` automatically at the end |
| `--deps-update` | Apply detected dependency updates in Bash phase |
| `--verbose` | Enable verbose output |
| `--debug` | Enable debug mode (shows all commands) |

---

## Plan Preview and Presets

- INSTALAR prints a resolved plan before installation or update starts.
- Interactive runs ask for confirmation against that plan before anything is changed.
- `--dry-run` goes one step further: it resolves the flow, prints the plan, and exits without modifying files.
- `--print-plan` remains available as a legacy alias.
- `--log-file <path>` stores installer status lines and command output in a plain-text file.
- Package presets help choose a starting stack quickly:
  - `minimal` keeps the install lean.
  - `standard` adds Fortify and AI tooling.
  - `full` adds a broader auth, monitoring, and DX stack.
- Plan output never prints configured passwords.

---

## Safer Defaults

- DB passwords are treated as secrets:
  - interactive prompts are masked
  - non-interactive logs print `(hidden)` instead of the value
- Generated admin passwords are shown once at the end of the run.
- Configured or default admin passwords are never printed back to the terminal.
- Non-interactive path replacement is stricter:
  - `--allow-delete-existing` only covers empty directories and detected Laravel projects
  - `--allow-delete-any-existing` is required for generic non-empty paths and Git repositories

---

## Modes

### Auto

- Asks for project name and package preset.
- Uses SQLite by default.
- Uses Laravel startup flags: `--npm --livewire --boost --pest`.
- Uses the selected preset to prefill optional packages.
- Creates default admin by default:
  - Email: `admin@example.com`
  - Password: `password` (or generated with `--admin-generate`)

### Manual

- Full control over:
  - project directory
  - database
  - Laravel startup flags
  - Laravel test suite (`Pest` or `PHPUnit`)
  - package preset, optional packages, and custom Composer packages
  - admin creation
  - optional `git init`
- Package multi-select keyboard support:
  - `↑/↓` move
  - `Space` toggle
  - `Enter` confirm
  - includes `Select all`
- Optional package choices show a category and short summary to make selection easier.
- DB password prompts are masked.

### Update

- For existing Laravel projects.
- Prints the detected package set before execution.
- Runs `composer update`, migrations, build, and optional Boost setup.

---

## Installation Sequence (Simplified)

1. Dependency check + optional install/update
2. Create/select project
3. Configure `.env`
4. Install Composer packages
5. Run setup commands (Fortify/Filament/Nwidart/etc.)
6. `boost:install` (interactive unless skipped)
7. `php artisan optimize`
8. `npm install` + `npm run build`
9. Health check + permission check + optional server start

---

## Nwidart / Modules Setup

When `nwidart/laravel-modules` is selected, INSTALAR automatically handles:

- `allow-plugins.wikimedia/composer-merge-plugin = true`
- `extra.merge-plugin.include = ["Modules/*/composer.json"]`
- removal of legacy `autoload.psr-4["Modules\\"]` (if present)
- publish of Nwidart config + vite loader
- creation of `Modules/` and `modules_statuses.json`
- Vite module asset loader wiring (`collectModuleAssetsPaths`)
- Core module bootstrap:
  - `php artisan module:make CoreModule`
  - `php artisan module:filament:install CoreModule`

When `coolsam/modules` is selected, INSTALAR also runs:

- `php artisan modules:install --no-interaction`
- `php artisan vendor:publish --tag=modules-config --no-interaction`

You also get a clear status line:

- `[ OK ] Nwidart setup complete (plugins + merge + vite)`
- or `[WARN] Nwidart setup incomplete: ...`

---

## Non-Interactive + JSON Config

You can run INSTALAR without prompts.

Example:

```bash
./instalar.sh --non-interactive --config instalar.json --mode manual --backup --admin-generate --allow-delete-existing
```

Example `instalar.json`:

```json
{
  "mode": "manual",
  "projectName": "My App",
  "projectPath": "./my-app",
  "preset": "standard",
  "allowDeleteExisting": true,
  "allowDeleteAnyExisting": false,
  "backup": true,
  "adminGenerate": true,
  "dryRun": false,
  "printPlan": false,
  "logFile": "./logs/instalar.log",
  "skipBoostInstall": false,
  "continueOnHealthCheckFailure": false,
  "startServer": false,
  "database": {
    "connection": "sqlite"
  },
  "laravelFlags": ["--npm", "--livewire", "--boost", "--pest"],
  "optionalPackageIds": ["fortify", "ai", "modules_bundle"],
  "customNormalPackages": [],
  "customDevPackages": [],
  "createAdmin": true,
  "gitInit": false,
  "admin": {
    "name": "Admin",
    "email": "admin@example.com"
  }
}
```

Notes:

- If `--config` is omitted, `./instalar.json` is loaded automatically when present.
- `preset` can be `minimal`, `standard`, or `full`.
- Set `"dryRun": true` or `"printPlan": true` to resolve and preview the flow without modifying files.
- `logFile` is resolved relative to the JSON config file when set there.
- Set `"skipBoostInstall": true` when unattended runs should skip the interactive Boost step.
- Set `"allowDeleteAnyExisting": true` only when unattended runs may replace a generic non-empty directory or Git repository.
- Test suite can be set via `laravelFlags` (`--pest` / `--phpunit`) or optional `"testSuite": "pest|phpunit"`.
- Set `"continueOnHealthCheckFailure": true` when unattended runs should warn and continue after failed final health checks.
- In non-interactive mode with an existing target directory:
  - without `--allow-delete-existing` => abort
  - with `--allow-delete-existing` => replace only empty directories or detected Laravel projects
  - with `--allow-delete-any-existing` => replace generic non-empty paths too (with `--backup`, backup first)

---

## End-of-Run Health Checks

INSTALAR runs:

- Check for `APP_KEY` in `.env`
- `php artisan db:show` (database connection)
- Check for `public/storage` symlink
- `composer validate`
- `php artisan about`
- `php artisan migrate:status`
- `php artisan route:list`
- check for `public/build/manifest.json`
- permission checks for:
  - project directory
  - `storage`
  - `bootstrap/cache`
  - `.env`

If any health check fails:

- Interactive mode prompts you to continue or abort.
- Non-interactive mode aborts with exit code `1`.
- Add `--continue-on-health-check-failure` or `"continueOnHealthCheckFailure": true` to continue anyway.
- Failed commands include a short recent-output snippet to speed up debugging.

Optional afterward:

- `composer run dev`
- `php artisan boost:install` if the Boost step was skipped

---

## Troubleshooting

- **`modules_statuses.json` missing / Vite ENOENT**
  - INSTALAR creates it automatically.
  - Manual fallback: create it in project root with at least `{}`.

- **`reverb:install` requires interaction**
  - This is expected in some setups; it is intentionally not forced with `--no-interaction`.

- **Existing target directory**
  - Interactive mode: installer asks for confirmation.
  - Non-interactive mode: use `--allow-delete-existing` for empty/Laravel paths, or `--allow-delete-any-existing` for generic/Git paths, optionally `--backup`.

---

## Quality Gates

- Pull requests and pushes to `main` run GitHub Actions for:
  - `bash -n instalar.sh`
  - `shellcheck instalar.sh`
  - `./instalar.sh --help`
  - `node --test`
- Tag pushes matching `v*` validate release metadata and create/update a GitHub draft release from the latest changelog section.

---

## Future Improvements

These features are planned or under consideration:

### Short-term
- Additional health checks (Redis connection, mail configuration)
- Enhanced backup/restore functionality
- Custom post-install commands
- Improved verbose output for failed commands

### Mid-term
- Extended database support (PostgreSQL, SQL Server)
- Plugin system for custom packages
- Cross-platform CI coverage for more shell/package-manager combinations

### Long-term
- Optional web-based installation UI
- Remote installation support (`curl ... | bash` from remote URL)

---

## Project Files

- `instalar.sh` — main installer (single required file)
- `tests/` — Node-based installer smoke and consistency tests
- `.github/workflows/` — CI and draft-release automation
- `CHANGELOG.md` — change history
- `LICENSE` — MIT license

---

## License

MIT. See `LICENSE`.
