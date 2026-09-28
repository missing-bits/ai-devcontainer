#!/usr/bin/env bash
# Plain flock helpers (TD SS5). The single host profile lock is waited for
# without a bound. Sets no shell options.

# aidc::profile_lock <name> <fd-var>
# Takes the exclusive host profile lock .local/locks/<name>.lock, creating
# .local/locks first. Sets <fd-var> to the file descriptor the lock is held
# on; it is released when that descriptor closes, including on process exit.
aidc::profile_lock() {
  local name="$1" __fdvar="$2" file fd
  mkdir -p "$AIDC_ROOT/.local/locks" || aidc::die "cannot create .local/locks"
  file="$AIDC_ROOT/.local/locks/$name.lock"
  exec {fd}>"$file" || aidc::die "cannot open the lock file of profile '$name'"
  flock -x "$fd" || aidc::die "cannot take the lock of profile '$name'"
  printf -v "$__fdvar" '%s' "$fd"
}
