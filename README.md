# INSTALAR

Reference installer for Laravel 12 + Filament 5.

`instalar.sh` is intentionally built as a **single file**:

- Bash entrypoint for dependency checks/install/update
- Embedded Node installer for interactive and configurable project setup

Current version: **0.1.5** (Rosie)

---

## What INSTALAR does

- Creates new Laravel 12 projects (`laravel new`) or updates existing ones.
- Supports **Auto**, **Manual**, and **Update** modes.
- Checks system dependencies with versions (`php`, `composer`, `laravel`, `node`, `npm`).
- Installs missing dependencies and can apply available dependency updates.
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

# 5) Update existing Laravel project in current directory
./instalar.sh --mode update

# 6) Apply dependency updates during Bash dependency stage
./instalar.sh --deps-update

# 7) Verbose output for debugging
./instalar.sh --verbose

# 8) Debug mode (shows all commands)
./instalar.sh --debug
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
| `--mode <auto\|manual\|update>` | Force mode |
| `--backup` | Backup existing target directory before replacing |
| `--admin-generate` | Generate admin password instead of `password` |
| `--allow-delete-existing` | Allow replacing existing target directory in non-interactive mode |
| `--start-server` | Run `composer run dev` automatically at the end |
| `--deps-update` | Apply detected dependency updates in Bash phase |
| `--verbose` | Enable verbose output |
| `--debug` | Enable debug mode (shows all commands) |

---

## Modes

### Auto

- Asks only for project name.
- Uses SQLite by default.
- Uses Laravel startup flags: `--npm --livewire --boost --pest`.
- Creates default admin by default:
  - Email: `admin@example.com`
  - Password: `password` (or generated with `--admin-generate`)

### Manual

- Full control over:
  - project directory
  - database
  - Laravel startup flags
  - Laravel test suite (`Pest` or `PHPUnit`)
  - optional packages + custom Composer packages
  - admin creation
  - optional `git init`
- Package multi-select keyboard support:
  - `↑/↓` move
  - `Space` toggle
  - `Enter` confirm
  - includes `Select all`

### Update

- For existing Laravel projects.
- Runs `composer update`, migrations, build, and optional Boost setup.

---

## Installation Sequence (Simplified)

1. Dependency check + optional install/update
2. Create/select project
3. Configure `.env`
4. Install Composer packages
5. Run setup commands (Fortify/Filament/Nwidart/etc.)
6. `boost:install` (interactive)
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
  "allowDeleteExisting": true,
  "backup": true,
  "adminGenerate": true,
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
- Test suite can be set via `laravelFlags` (`--pest` / `--phpunit`) or optional `"testSuite": "pest|phpunit"`.
- In non-interactive mode with an existing target directory:
  - without `--allow-delete-existing` => abort
  - with `--allow-delete-existing` => replace (with `--backup`, backup first)

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

If any health check fails, you'll be prompted to continue or abort.

Optional afterward:

- `composer run dev`

---

## Troubleshooting

- **`modules_statuses.json` missing / Vite ENOENT**
  - INSTALAR creates it automatically.
  - Manual fallback: create it in project root with at least `{}`.

- **`reverb:install` requires interaction**
  - This is expected in some setups; it is intentionally not forced with `--no-interaction`.

- **Existing target directory**
  - Interactive mode: installer asks for confirmation.
  - Non-interactive mode: use `--allow-delete-existing`, optionally `--backup`.

---

## Future Improvements

These features are planned or under consideration:

### Short-term
- Additional health checks (Redis connection, mail configuration)
- Enhanced backup/restore functionality
- Custom post-install commands
- Improved verbose output for failed commands

### Mid-term
- Automated tests for the installer itself
- GitHub Actions CI/CD workflow
- Extended database support (PostgreSQL, SQL Server)
- Plugin system for custom packages

### Long-term
- Optional web-based installation UI
- Remote installation support (`curl ... | bash` from remote URL)

---

## Project Files

- `instalar.sh` — main installer (single required file)
- `CHANGELOG.md` — change history
- `LICENSE` — MIT license

---

## License

MIT. See `LICENSE`.
