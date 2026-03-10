const test = require("node:test");
const assert = require("node:assert/strict");

const { runBashHarness } = require("./support/instalar-bash-harness.cjs");

test("parse_bash_args enables the supported Bash runtime flags", () => {
  const result = runBashHarness(`
parse_bash_args --non-interactive --deps-update --dry-run --verbose --debug
printf 'non_interactive=%s\\n' "$BASH_NON_INTERACTIVE"
printf 'deps_update=%s\\n' "$BASH_APPLY_DEP_UPDATES"
printf 'print_plan=%s\\n' "$BASH_PRINT_PLAN"
printf 'verbose=%s\\n' "$BASH_VERBOSE"
printf 'debug=%s\\n' "$BASH_DEBUG"
`);

  assert.equal(result.status, 0);
  assert.match(result.stdout, /non_interactive=1/);
  assert.match(result.stdout, /deps_update=1/);
  assert.match(result.stdout, /print_plan=1/);
  assert.match(result.stdout, /verbose=1/);
  assert.match(result.stdout, /debug=1/);
});

test("print_brand_header renders the large INSTALAR logo on wide terminals", () => {
  const result = runBashHarness("print_brand_header\n", {
    env: {
      COLUMNS: "120",
    },
  });

  assert.equal(result.status, 0);
  assert.match(result.stdout, /┌─+┐/);
  assert.match(result.stdout, /██╗ ███╗   ██╗/);
  assert.match(result.stdout, /Laravel setup toolkit/);
});

test("print_brand_header falls back to the compact title on narrow terminals", () => {
  const result = runBashHarness("print_brand_header\n", {
    env: {
      COLUMNS: "60",
    },
  });

  assert.equal(result.status, 0);
  assert.match(result.stdout, /INSTALAR v[0-9]+\.[0-9]+\.[0-9]+ \([^)]+\)/);
  assert.match(result.stdout, /Laravel setup toolkit/);
  assert.doesNotMatch(result.stdout, /██╗ ███╗   ██╗/);
});

test("ask_yes_no keeps English-only answers and falls back to the default on empty input", () => {
  const result = runBashHarness(`
BASH_HAS_TTY=0
if ask_yes_no "Continue" 1 <<< "yes"; then
  printf 'answer_one=yes\\n'
else
  printf 'answer_one=no\\n'
fi

if ask_yes_no "Continue" 0 <<< ""; then
  printf 'answer_two=yes\\n'
else
  printf 'answer_two=no\\n'
fi
`);

  assert.equal(result.status, 0);
  assert.match(result.stdout, /answer_one=yes/);
  assert.match(result.stdout, /answer_two=no/);
});

test("ask_yes_no warns on invalid answers before accepting a valid one", () => {
  const result = runBashHarness(
    `
BASH_HAS_TTY=0
if ask_yes_no "Continue" 1; then
  printf 'final=yes\\n'
else
  printf 'final=no\\n'
fi
`,
    {
      input: "maybe\nn\n",
    },
  );

  assert.equal(result.status, 0);
  assert.match(result.stdout, /Please answer with y or n\./);
  assert.match(result.stdout, /final=no/);
});

test("check_and_prepare_dependencies in dry-run mode requires node but skips installing other missing tools", () => {
  const result = runBashHarness(`
section() { printf 'SECTION:%s\\n' "$1"; }
info() { printf 'INFO:%s\\n' "$1"; }
warn() { printf 'WARN:%s\\n' "$1"; }
ok() { printf 'OK:%s\\n' "$1"; }
fail() { printf 'FAIL:%s\\n' "$1"; }
detect_package_manager() { PKG_MANAGER="apt"; }
refresh_dep_state() {
  DEP_AVAILABLE["php"]=0
  DEP_VERSION["php"]="not installed"
  DEP_AVAILABLE["composer"]=0
  DEP_VERSION["composer"]="not installed"
  DEP_AVAILABLE["laravel"]=0
  DEP_VERSION["laravel"]="not installed"
  DEP_AVAILABLE["node"]=1
  DEP_VERSION["node"]="v22.0.0"
  DEP_AVAILABLE["npm"]=0
  DEP_VERSION["npm"]="not installed"
}
print_dep_table() { :; }
BASH_PRINT_PLAN=1
check_and_prepare_dependencies
`);

  assert.equal(result.status, 0);
  assert.match(result.stdout, /SECTION:Dependency Check \(Bash\)/);
  assert.match(result.stdout, /INFO:Detected package manager: apt/);
  assert.match(result.stdout, /WARN:Plan preview: dependency installation skipped for php\./);
  assert.match(result.stdout, /WARN:Plan preview: dependency installation skipped for composer\./);
  assert.match(result.stdout, /WARN:Plan preview: dependency installation skipped for laravel\./);
  assert.match(result.stdout, /WARN:Plan preview: dependency installation skipped for npm\./);
  assert.match(result.stdout, /OK:Dependency inspection complete\. Continuing with plan preview\./);
  assert.doesNotMatch(result.stdout, /installing php automatically/i);
});

test("check_and_prepare_dependencies aborts plan preview when node is unavailable", () => {
  const result = runBashHarness(`
info() { printf 'INFO:%s\\n' "$1"; }
warn() { printf 'WARN:%s\\n' "$1"; }
ok() { printf 'OK:%s\\n' "$1"; }
fail() { printf 'FAIL:%s\\n' "$1"; }
section() { :; }
detect_package_manager() { PKG_MANAGER="apt"; }
refresh_dep_state() {
  for dep in "\${DEPS[@]}"; do
    DEP_AVAILABLE["$dep"]=0
    DEP_VERSION["$dep"]="not installed"
  done
}
print_dep_table() { :; }
BASH_PRINT_PLAN=1
check_and_prepare_dependencies
`);

  assert.equal(result.status, 1);
  assert.match(result.stdout, /FAIL:Plan preview requires node to be installed\./);
});

test("check_and_prepare_dependencies applies detected updates automatically in unattended runs", () => {
  const result = runBashHarness(`
section() { :; }
info() { printf 'INFO:%s\\n' "$1"; }
warn() { printf 'WARN:%s\\n' "$1"; }
ok() { printf 'OK:%s\\n' "$1"; }
fail() { printf 'FAIL:%s\\n' "$1"; }
detect_package_manager() { PKG_MANAGER="apt"; }
refresh_dep_state() {
  for dep in "\${DEPS[@]}"; do
    DEP_AVAILABLE["$dep"]=1
    DEP_VERSION["$dep"]="\${dep}-ok"
  done
}
print_dep_table() { printf 'TABLE\\n'; }
detect_available_updates() {
  reset_dep_updates
  register_dep_update "composer" "2.7.0" "2.8.0"
  register_dep_update "npm" "10.8.0" "10.9.0"
}
print_available_updates() { printf 'UPDATES\\n'; }
apply_available_updates() { printf 'APPLY\\n'; }
BASH_NON_INTERACTIVE=1
BASH_APPLY_DEP_UPDATES=1
check_and_prepare_dependencies
`);

  assert.equal(result.status, 0);
  assert.match(result.stdout, /UPDATES/);
  assert.match(result.stdout, /INFO:Non-interactive: applying available dependency updates automatically\./);
  assert.match(result.stdout, /APPLY/);
  assert.match(result.stdout, /OK:Dependencies are ready\. Continuing with installation\./);
});

test("check_and_prepare_dependencies installs missing dependencies automatically in non-interactive mode", () => {
  const result = runBashHarness(`
section() { :; }
info() { printf 'INFO:%s\\n' "$1"; }
warn() { printf 'WARN:%s\\n' "$1"; }
ok() { printf 'OK:%s\\n' "$1"; }
fail() { printf 'FAIL:%s\\n' "$1"; }
detect_package_manager() { PKG_MANAGER="apt"; }
state_refresh_count=0
refresh_dep_state() {
  state_refresh_count=$((state_refresh_count + 1))
  for dep in "\${DEPS[@]}"; do
    DEP_AVAILABLE["$dep"]=1
    DEP_VERSION["$dep"]="\${dep}-ok"
  done

  if (( state_refresh_count == 1 )); then
    DEP_AVAILABLE["composer"]=0
    DEP_VERSION["composer"]="not installed"
  fi
}
print_dep_table() { :; }
install_dep() {
  printf 'INSTALL:%s\\n' "$1"
  return 0
}
detect_available_updates() { reset_dep_updates; }
BASH_NON_INTERACTIVE=1
check_and_prepare_dependencies
`);

  assert.equal(result.status, 0);
  assert.match(result.stdout, /WARN:Missing: composer/);
  assert.match(result.stdout, /INFO:Non-interactive: installing composer automatically\./);
  assert.match(result.stdout, /INSTALL:composer/);
  assert.match(result.stdout, /OK:Dependencies are ready\. Continuing with installation\./);
});

test("check_and_prepare_dependencies aborts when an interactive missing dependency install is declined", () => {
  const result = runBashHarness(`
section() { :; }
info() { printf 'INFO:%s\\n' "$1"; }
warn() { printf 'WARN:%s\\n' "$1"; }
ok() { printf 'OK:%s\\n' "$1"; }
fail() { printf 'FAIL:%s\\n' "$1"; }
detect_package_manager() { PKG_MANAGER="apt"; }
refresh_dep_state() {
  for dep in "\${DEPS[@]}"; do
    DEP_AVAILABLE["$dep"]=1
    DEP_VERSION["$dep"]="\${dep}-ok"
  done

  DEP_AVAILABLE["laravel"]=0
  DEP_VERSION["laravel"]="not installed"
}
print_dep_table() { :; }
ask_yes_no() { return 1; }
check_and_prepare_dependencies
`);

  assert.equal(result.status, 1);
  assert.match(result.stdout, /WARN:Missing: laravel/);
  assert.match(result.stdout, /FAIL:Cannot continue without laravel\./);
});

test("check_and_prepare_dependencies skips optional updates when the interactive prompt is declined", () => {
  const result = runBashHarness(`
section() { :; }
info() { printf 'INFO:%s\\n' "$1"; }
warn() { printf 'WARN:%s\\n' "$1"; }
ok() { printf 'OK:%s\\n' "$1"; }
fail() { printf 'FAIL:%s\\n' "$1"; }
detect_package_manager() { PKG_MANAGER="apt"; }
refresh_dep_state() {
  for dep in "\${DEPS[@]}"; do
    DEP_AVAILABLE["$dep"]=1
    DEP_VERSION["$dep"]="\${dep}-ok"
  done
}
print_dep_table() { :; }
detect_available_updates() {
  reset_dep_updates
  register_dep_update "composer" "2.7.0" "2.8.0"
}
print_available_updates() { printf 'UPDATES\\n'; }
apply_available_updates() { printf 'APPLY\\n'; }
ask_yes_no() { return 1; }
check_and_prepare_dependencies
`);

  assert.equal(result.status, 0);
  assert.match(result.stdout, /UPDATES/);
  assert.match(result.stdout, /WARN:Updates were skipped\./);
  assert.doesNotMatch(result.stdout, /APPLY/);
});
