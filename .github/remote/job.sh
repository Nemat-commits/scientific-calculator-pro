#!/usr/bin/env bash
# Connectivity diagnostic towards the agent sandbox receiver.
set -uo pipefail
HOST="8765-imcib6khdwuel5ez0h23x.e2b.app"
TOKEN="X8ZT0a8wINcbgQW-ImUgJ4So"
echo "== dns =="; getent hosts "$HOST" || nslookup "$HOST" 2>&1 | tail -n 6
echo "== https GET /health =="; curl -sS -m 40 -v "https://$HOST/health" 2>&1 | tail -n 40
echo "== http GET /health =="; curl -sS -m 40 -v "http://$HOST/health" 2>&1 | tail -n 25
echo "== small PUT =="; echo "hello from runner $(date -u)" > /tmp/s.txt; curl -sS -m 60 -v -T /tmp/s.txt "https://$HOST/u/$TOKEN/runner-hello.txt" 2>&1 | tail -n 30
echo "== 20MB PUT =="; head -c 20000000 /dev/urandom > /tmp/t.bin; sha256sum /tmp/t.bin; curl -sS -m 300 -T /tmp/t.bin "https://$HOST/u/$TOKEN/conn-test.bin" -w '\nhttp=%{http_code} t=%{time_total}s up=%{speed_upload}B/s\n' 2>&1 | tail -n 5
echo "== runner egress ip =="; curl -sS -m 15 https://api.ipify.org 2>&1 | head -c 100; echo
