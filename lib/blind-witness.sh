#!/usr/bin/env bash
# blind-witness.sh -- exit-6 BLIND verdict line shared by interchange-probe.sh
# and thermostat-probe.sh (#210). Source after setting $PROJECT, if any.
# tempo.sh's blind() is a different contract (exit 2) and stays separate.

blind() {
  if [ -n "${PROJECT:-}" ]; then
    printf 'verdict=BLIND project=%s reason=%s\n' "$PROJECT" "$1"
  else
    printf 'verdict=BLIND reason=%s\n' "$1"
  fi
  exit 6
}
