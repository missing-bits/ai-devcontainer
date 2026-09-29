#!/usr/bin/env bash
# Shared helpers for the Docker integration suite (tests/integration/).
# Every name this suite creates carries the run id AIDC_IT_RUN
# ("it<run>-..."); setup refuses to start on a collision, and each helper
# that creates a Docker resource is paired with a tracking call so teardown
# removes exactly what was created, never by pattern (Task 7 brief).
# Sourced with a plain `source` (not bats' `load`, which resolves relative to
# the .bats file, not to this file) so it works no matter which test
# directory loads it.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.bash"

# aidc_it_run(): prints this bats run's id, computed once per invocation of
# `bats --recursive tests/integration` (BATS_RUN_TMPDIR is shared by every
# file of one run) and cached in a file so later files reuse it. Refuses to
# start when a Docker resource already uses the id (collision).
aidc_it_run() {
  local marker="$BATS_RUN_TMPDIR/aidc-it-run"
  if [ -f "$marker" ]; then
    cat "$marker"
    return 0
  fi
  local id
  id="it$(basename "$BATS_RUN_TMPDIR" | tr '[:upper:]' '[:lower:]' | tr -cd '[:lower:][:digit:]')"
  # docker's name filter is a substring match. Every resource this suite
  # creates carries "-<id>-" somewhere in its name (aidc-<id>-a's container,
  # aidc-tools-<id>-a's and aidc-claude-<id>-shared's volumes alike), so this
  # single substring catches them all without needing a pattern *delete*
  # anywhere else in the suite (only this read-only check uses one).
  if docker ps -aq --filter "name=-${id}-" 2>/dev/null | grep -q . ||
    docker volume ls -q --filter "name=-${id}-" 2>/dev/null | grep -q .; then
    printf 'aidc-it: run id %s collides with an existing Docker resource; refusing to start\n' "$id" >&2
    return 1
  fi
  printf '%s' "$id" >"$marker"
  printf '%s' "$id"
}

# aidc_it_downloads_volume: this run's mise downloads volume. Every
# profile:code of the suite uses it instead of the real aidc-mise-downloads
# (AIDC_MISE_DOWNLOADS_VOLUME below); zz_cleanup.bats removes it by name, so
# a run of single files without zz_cleanup.bats leaves it behind:
# `docker volume rm aidc-mise-downloads-<run id>-run`.
aidc_it_downloads_volume() {
  printf 'aidc-mise-downloads-%s-run' "$(aidc_it_run)"
}

# aidc_it_name <suffix>: a profile or state-profile name carrying this run's id.
aidc_it_name() {
  printf '%s-%s' "$(aidc_it_run)" "$1"
}

# aidc_it_repo [<base-dir>]: aidc_test_repo, kept as its own name so a file
# reads as integration-suite setup rather than a borrowed unit-test helper.
aidc_it_repo() {
  aidc_test_repo "$@"
}

# aidc_it_stub_bin [<dir>]: creates devcontainer and code stubs (each logs
# its arguments and exits 0) in <dir> (default: a directory under the
# current test/file tmp dir) and prepends it to PATH. Real docker stays on
# PATH; only devcontainer and code are stubbed, per the brief.
aidc_it_stub_bin() {
  local dir="${1:-${BATS_FILE_TMPDIR:-$BATS_TEST_TMPDIR}/stub-bin}"
  mkdir -p "$dir"
  local cmd
  for cmd in devcontainer code; do
    cat >"$dir/$cmd" <<STUB
#!/usr/bin/env bash
printf '%s %s\n' "$cmd" "\$*" >>"${AIDC_IT_STUB_CALLS:-/dev/null}"
exit 0
STUB
    chmod +x "$dir/$cmd"
  done
  PATH="$dir:$PATH"
  export PATH
  AIDC_IT_STUB_DIR="$dir"
  export AIDC_IT_STUB_DIR
}

# aidc_it_ensure_image(): builds aidc-workspace:local once per bats run, from
# a throwaway copy of the current AIDC_ROOT, and leaves it outside cleanup.
# Idempotent: a later call in the same run is a no-op. Uses a per-run lock so
# two files (bats runs files sequentially; this only guards a stray parallel
# invocation) never build at once.
aidc_it_ensure_image() {
  local marker="$BATS_RUN_TMPDIR/aidc-it-image-built"
  local lock="$BATS_RUN_TMPDIR/aidc-it-image.lock"
  exec 8>"$lock"
  flock 8
  if [ -f "$marker" ]; then
    flock -u 8
    return 0
  fi
  local build_root="$BATS_RUN_TMPDIR/image-build"
  mkdir -p "$build_root"
  (
    aidc_test_repo "$build_root"
    cd "$AIDC_ROOT" &&
      docker compose -f .devcontainer/compose.yaml build \
        --build-arg "USER_UID=$(id -u)" --build-arg "USER_GID=$(id -g)" workspace
  ) >"$BATS_RUN_TMPDIR/image-build.log" 2>&1
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    touch "$marker"
  else
    cat "$BATS_RUN_TMPDIR/image-build.log" >&2
  fi
  flock -u 8
  return "$rc"
}

# aidc_it_set_env <profile> <KEY=value>...: upserts fields in
# profiles/<profile>/profile.env in place (replaces an existing KEY= line,
# appends otherwise). Values are written literally.
aidc_it_set_env() {
  local profile="$1" file
  shift
  file="$AIDC_ROOT/profiles/$profile/profile.env"
  local kv key value
  for kv in "$@"; do
    key="${kv%%=*}"
    value="${kv#*=}"
    if grep -q "^${key}=" "$file"; then
      local tmp
      tmp="$(mktemp)"
      awk -v k="$key" -v v="$value" -F= 'BEGIN{OFS="="} $1==k{$0=k"="v} {print}' "$file" >"$tmp"
      mv "$tmp" "$file"
    else
      printf '%s=%s\n' "$key" "$value" >>"$file"
    fi
  done
}

aidc_it_new_profile() {
  run bash "$AIDC_ROOT/tasks/host/profile/new" "$1"
  assert_success
}

# aidc_it_code <profile>: runs profile:code with devcontainer and code
# stubbed (aidc_it_stub_bin must already be on PATH), so it only validates,
# generates .local/<profile>/ and creates the five volumes.
aidc_it_code() {
  run bash "$AIDC_ROOT/tasks/host/profile/code" "$1"
  assert_success
}

# aidc_it_compose <profile> [<fixture file>...]: prints the -f arguments for
# the shared file, the profile's generated fragment, and any extra fixture.
aidc_it_compose_args() {
  local profile="$1"
  shift
  local args=(-f .devcontainer/compose.yaml -f ".local/$profile/compose.yaml")
  local f
  for f in "$@"; do
    args+=(-f "$f")
  done
  printf '%s\n' "${args[@]}"
}

# aidc_it_up <profile> [<fixture file>...]: the real first (or later) start,
# from AIDC_ROOT, with -p aidc-<profile>.
aidc_it_up() {
  local profile="$1"
  shift
  local -a args
  mapfile -t args < <(aidc_it_compose_args "$profile" "$@")
  (cd "$AIDC_ROOT" && docker compose -p "aidc-$profile" "${args[@]}" up -d)
}

# aidc_it_down <profile> [<fixture file>...]: stops and removes the
# profile's container and network (never its external volumes).
aidc_it_down() {
  local profile="$1"
  shift
  local -a args
  mapfile -t args < <(aidc_it_compose_args "$profile" "$@")
  (cd "$AIDC_ROOT" && docker compose -p "aidc-$profile" "${args[@]}" down)
}

aidc_it_container() {
  printf 'aidc-%s-workspace-1' "$1"
}

aidc_it_exec() {
  local profile="$1"
  shift
  docker exec "$(aidc_it_container "$profile")" "$@"
}

# aidc_it_wait_init <profile> [<timeout-seconds>]: polls init.status until it
# no longer starts with "running" and prints its final content.
aidc_it_wait_init() {
  local profile="$1" timeout="${2:-420}" waited=0 status=""
  while [ "$waited" -lt "$timeout" ]; do
    status="$(aidc_it_exec "$profile" cat /opt/aidc/tools/init.status 2>/dev/null || true)"
    case "$status" in
    running* | "") ;;
    *)
      printf '%s' "$status"
      return 0
      ;;
    esac
    sleep 2
    waited=$((waited + 2))
  done
  printf 'aidc-it: init.status of %s did not leave "running" within %ss (last: %s)\n' \
    "$profile" "$timeout" "$status" >&2
  return 1
}

# --- resource tracking and cleanup -----------------------------------------
# A ledger is a plain file of "<kind> <name>" lines, one resource per line;
# <kind> is profile, volume, or container. Cleanup removes exactly the
# recorded resources, in an order safe for their dependencies (containers,
# then profiles -- which stop their own container and remove their tools
# volume via the real profile:remove task -- then bare volumes).

aidc_it_file_ledger() { printf '%s' "$BATS_FILE_TMPDIR/aidc-it-resources"; }
aidc_it_test_ledger() { printf '%s' "$BATS_TEST_TMPDIR/aidc-it-resources"; }

aidc_it_track() { # <ledger> <kind> <name>
  printf '%s %s\n' "$2" "$3" >>"$1"
}

aidc_it_track_profile() { aidc_it_track "$(aidc_it_file_ledger)" profile "$1"; }
aidc_it_track_volume() { aidc_it_track "$(aidc_it_file_ledger)" volume "$1"; }
aidc_it_track_container() { aidc_it_track "$(aidc_it_file_ledger)" container "$1"; }

# aidc_it_track_state <profile>: tracks the profile itself plus its three
# state volumes (Claude, Codex, shell), for the common case of a profile
# whose PROFILE_CLAUDE/CODEX/SHELL fields are unset, so each state volume
# defaults to the profile's own name (TD §3.1). profile:remove never touches
# state volumes, so they are tracked here explicitly. Not for a profile that
# shares a state name with another profile -- track that volume once,
# separately, after every profile referencing it is tracked.
aidc_it_track_state() {
  aidc_it_track_profile "$1"
  aidc_it_track_volume "aidc-claude-$1"
  aidc_it_track_volume "aidc-codex-$1"
  aidc_it_track_volume "aidc-shell-$1"
}

aidc_it_cleanup() { # [<ledger>], default the file-scoped one
  local ledger="${1:-$(aidc_it_file_ledger)}" kind name
  [ -f "$ledger" ] || return 0
  while read -r kind name; do
    [ "$kind" = container ] || continue
    docker rm -f "$name" >/dev/null 2>&1 ||
      printf 'aidc-it: warning: could not remove container %s\n' "$name" >&2
  done <"$ledger"
  while read -r kind name; do
    [ "$kind" = profile ] || continue
    bash "$AIDC_ROOT/tasks/host/profile/remove" "$name" >/dev/null 2>&1 ||
      printf 'aidc-it: warning: profile:remove %s failed\n' "$name" >&2
  done <"$ledger"
  while read -r kind name; do
    [ "$kind" = volume ] || continue
    docker volume rm -f "$name" >/dev/null 2>&1 ||
      printf 'aidc-it: warning: could not remove volume %s\n' "$name" >&2
  done <"$ledger"
  rm -f "$ledger"
}

# Keep every profile:code of this suite off the real shared downloads volume.
# A file that needs its own volume exports another name in setup_file; this
# default then leaves it alone.
: "${AIDC_MISE_DOWNLOADS_VOLUME:=$(aidc_it_downloads_volume)}"
export AIDC_MISE_DOWNLOADS_VOLUME
