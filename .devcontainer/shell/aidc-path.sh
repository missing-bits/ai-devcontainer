#!/bin/sh
# Sourced by /etc/profile for login shells. Debian's /etc/profile resets
# PATH before sourcing profile.d scripts, dropping the image's own PATH
# override. Prepends the mise shims only when they are not already there,
# so shells without mise activation still find the container tools.
case ":$PATH:" in
*":/opt/aidc/tools/mise/shims:"*) ;;
*) PATH="/opt/aidc/tools/mise/shims:$PATH" ;;
esac
export PATH
