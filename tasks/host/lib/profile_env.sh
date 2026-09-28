#!/usr/bin/env bash
# Parser for profiles/<profile>/profile.env (TD SS3.1, SS3.9). Never sources
# the file. Only whole-line '#' comments are allowed; values are literal and
# never expanded. An empty value counts as unset.

aidc::_env_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

aidc::load_profile_env() {
  local profile="$1"
  local file="$AIDC_ROOT/profiles/$profile/profile.env"
  [ -f "$file" ] || aidc::die "profile '$profile' does not exist: run 'mise run profile:new $profile'"
  local -A seen=() val=()
  local line trimmed key value n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line="${line%$'\r'}"
    trimmed="$(aidc::_env_trim "$line")"
    [ -z "$trimmed" ] && continue
    [ "${trimmed:0:1}" = "#" ] && continue
    [[ "$trimmed" == *=* ]] || aidc::die "$file line $n: expected KEY=value"
    key="$(aidc::_env_trim "${trimmed%%=*}")"
    value="$(aidc::_env_trim "${trimmed#*=}")"
    case "$key" in
    PROFILE_CLAUDE | PROFILE_CODEX | PROFILE_SHELL | DOCKER_SOCKET | \
      GIT_AUTHOR_NAME | GIT_AUTHOR_EMAIL | GIT_COMMITTER_NAME | GIT_COMMITTER_EMAIL | GIT_SSH_COMMAND) ;;
    *) aidc::die "$file line $n: unknown key '$key'" ;;
    esac
    [ -z "${seen[$key]+x}" ] || aidc::die "$file line $n: duplicate key '$key'"
    seen[$key]=1
    val[$key]="$value"
  done <"$file"

  AIDC_STATE_CLAUDE="${val[PROFILE_CLAUDE]:-$profile}"
  AIDC_STATE_CODEX="${val[PROFILE_CODEX]:-$profile}"
  AIDC_STATE_SHELL="${val[PROFILE_SHELL]:-$profile}"
  aidc::require_name "agent state" "$AIDC_STATE_CLAUDE"
  aidc::require_name "agent state" "$AIDC_STATE_CODEX"
  aidc::require_name "shell history" "$AIDC_STATE_SHELL"

  AIDC_DOCKER_SOCKET="${val[DOCKER_SOCKET]:-off}"
  case "$AIDC_DOCKER_SOCKET" in
  on | off) ;;
  *) aidc::die "$file: DOCKER_SOCKET must be 'on' or 'off'" ;;
  esac

  AIDC_GIT_AUTHOR_NAME="${val[GIT_AUTHOR_NAME]:-}"
  AIDC_GIT_AUTHOR_EMAIL="${val[GIT_AUTHOR_EMAIL]:-}"
  AIDC_GIT_COMMITTER_NAME="${val[GIT_COMMITTER_NAME]:-}"
  AIDC_GIT_COMMITTER_EMAIL="${val[GIT_COMMITTER_EMAIL]:-}"
  AIDC_GIT_SSH_COMMAND="${val[GIT_SSH_COMMAND]:-}"
  export AIDC_STATE_CLAUDE AIDC_STATE_CODEX AIDC_STATE_SHELL AIDC_DOCKER_SOCKET \
    AIDC_GIT_AUTHOR_NAME AIDC_GIT_AUTHOR_EMAIL AIDC_GIT_COMMITTER_NAME \
    AIDC_GIT_COMMITTER_EMAIL AIDC_GIT_SSH_COMMAND
}
