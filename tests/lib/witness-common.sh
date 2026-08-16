#!/usr/bin/env bash
# Shared PASS/FAIL witness counters, sourced by tests/*-witness.sh.
# See hf7y/scheduler#210: 51 files each defined their own ok()/bad(),
# already diverged into 6 distinct signatures before anything noticed.
PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS: %s\n' "$*"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$*"; }
