#!/usr/bin/env bash
# Fake tailscale CLI for the Shibumi Tailscale service regression.
set -euo pipefail
printf '%s\n' "$*" >> "${SHIBUMI_TAILSCALE_LOG:?}"
case ${1:-} in
  status)
    state=$(cat "${SHIBUMI_TAILSCALE_STATE:?}")
    cat <<JSON
{"BackendState":"$state","CurrentTailnet":{"Name":"example.org"},
 "Self":{"HostName":"laptop","DNSName":"laptop.example.ts.net.","TailscaleIPs":["100.64.0.1"]},
 "Peer":{"a":{"ID":"a","HostName":"exit","DNSName":"exit.example.ts.net.","TailscaleIPs":["100.64.0.3"],"OS":"linux","Online":true,"ExitNodeOption":true,"ExitNode":false},
         "b":{"ID":"b","HostName":"phone","DNSName":"phone.example.ts.net.","TailscaleIPs":["100.64.0.4"],"OS":"iOS","Online":false,"ExitNodeOption":false,"ExitNode":false}}}
JSON
    ;;
  up) printf 'Running' > "$SHIBUMI_TAILSCALE_STATE" ;;
  down) printf 'Stopped' > "$SHIBUMI_TAILSCALE_STATE" ;;
  set)
    [[ ${2:-} == --exit-node=* ]] || exit 2
    ;;
  *) printf 'unsupported\n' >&2; exit 2 ;;
esac
