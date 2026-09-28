#!/bin/sh
# Sourced by /etc/profile for login shells. Debian's /etc/profile resets
# PATH before sourcing profile.d scripts, dropping the image's own PATH
# override and letting another installed `claude` or `codex` ahead of the
# launchers shadow them. Prepends the launcher directory only when it is
# not already there.
case ":$PATH:" in
*":/usr/local/lib/aidc/launchers:"*) ;;
*) PATH="/usr/local/lib/aidc/launchers:$PATH" ;;
esac
export PATH
