#!/usr/bin/env bash
# Fahrstand des Referenzverfahrens stromentlastung (Entwicklungsbetrieb).
#
#   stromentlastung.sh start    Keycloak (Compose) + vier Dienste (JDK 17) + Oberfläche
#   stromentlastung.sh stop     beendet, was dieses Skript gestartet hat
#   stromentlastung.sh status   wer läuft
#   stromentlastung.sh reset    stop, H2-Dateien löschen — der nächste Start sät neu
#   stromentlastung.sh logs <dienst>   tail des Dienstprotokolls
#
# Das Skript beendet nur Prozesse, deren Arbeitsverzeichnis im Arbeitsbereich liegt.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"   # ~/stromentlastung
PLATFORM="$ROOT/stromentlastung-platform"
RUN=/tmp/stromentlastung-run
KC_PORT=9091 UI_PORT=4202
declare -A PORTS=([unternehmen]=8091 [antrag]=8092 [bescheid]=8093 [zahlung]=8094)
DIENSTE=(unternehmen bescheid zahlung antrag)
mkdir -p "$RUN"

say()  { printf '\033[0;36m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[0;32m%s\033[0m\n' "$*"; }
warn() { printf '  \033[0;33m%s\033[0m\n' "$*"; }

resolve_jdk() {
  local jh
  jh=$(/usr/libexec/java_home -v 17 2>/dev/null) || { warn "kein JDK 17"; exit 1; }
  "$jh/bin/java" -version 2>&1 | grep -q 'version "17' || {
    jh=$(/usr/libexec/java_home -V 2>&1 | awk '/ 17\./ {print $NF; exit}')
    [ -n "$jh" ] && "$jh/bin/java" -version 2>&1 | grep -q 'version "17' || { warn "kein exaktes JDK 17"; exit 1; }
  }
  echo "$jh"
}

port_holder() { lsof -ti :"$1" 2>/dev/null | head -1; }
holder_is_ours() {
  local pid=$1 cwd
  cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
  case "$cwd" in "$ROOT"*) return 0 ;; *) return 1 ;; esac
}
stop_port() {
  local pid; pid=$(port_holder "$1")
  [ -z "$pid" ] && return 0
  if holder_is_ours "$pid"; then
    kill "$pid" 2>/dev/null || true; sleep 2
    kill -9 "$(port_holder "$1")" 2>/dev/null || true
    ok "Port $1: PID $pid beendet"
  else
    warn "Port $1 gehört einem Prozess außerhalb von $ROOT — nicht angefasst"; return 1
  fi
}
wait_http() { # url seconds
  local i=0; until curl -fsS -o /dev/null "$1" 2>/dev/null; do i=$((i+1)); [ $i -ge "$2" ] && return 1; sleep 1; done; return 0
}

api_pfad() { case "$1" in antrag) echo /api/antraege ;; bescheid) echo /api/bescheide ;; zahlung) echo /api/zahlungen ;; *) echo /api/unternehmen ;; esac; }

start_dienst() {
  local d=$1 port=${PORTS[$1]} jh=$2
  if [ -n "$(port_holder "$port")" ]; then ok "$d läuft bereits auf $port"; return; fi
  ( cd "$ROOT/stromentlastung-$d" && JAVA_HOME="$jh" nohup ./mvnw -q spring-boot:run > "$RUN/$d.log" 2>&1 & echo $! > "$RUN/$d.pid" )
  wait_http "http://localhost:$port$(api_pfad "$d")/v3/api-docs" 240 \
    && ok "$d auf $port" || warn "$d meldet sich nicht — $RUN/$d.log"
}

cmd_start() {
  say "Keycloak"; (cd "$PLATFORM" && docker compose -p stromentlastung up -d keycloak >/dev/null)
  wait_http "http://localhost:$KC_PORT/realms/stromentlastung" 180 && ok "Keycloak auf $KC_PORT" || { warn "Keycloak antwortet nicht"; exit 1; }
  local jh; jh=$(resolve_jdk); say "Dienste (JDK $jh)"
  for d in "${DIENSTE[@]}"; do start_dienst "$d" "$jh"; done
  say "Oberfläche"
  if [ -n "$(port_holder "$UI_PORT")" ]; then ok "Oberfläche läuft bereits auf $UI_PORT"; else
    ( cd "$ROOT/stromentlastung-ui" && [ -d node_modules ] || npm ci --silent )
    ( cd "$ROOT/stromentlastung-ui" && nohup npm start > "$RUN/ui.log" 2>&1 & echo $! > "$RUN/ui.pid" )
    wait_http "http://localhost:$UI_PORT" 180 && ok "Oberfläche auf http://localhost:$UI_PORT" || warn "Oberfläche meldet sich nicht — $RUN/ui.log"
  fi
}
cmd_stop() {
  say "Stop"; stop_port "$UI_PORT" || true
  for d in "${DIENSTE[@]}"; do stop_port "${PORTS[$d]}" || true; done
  (cd "$PLATFORM" && docker compose -p stromentlastung stop keycloak >/dev/null 2>&1) && ok "Keycloak gestoppt" || true
}
cmd_status() {
  say "Status"
  curl -fsS -o /dev/null "http://localhost:$KC_PORT/realms/stromentlastung" 2>/dev/null && ok "Keycloak $KC_PORT" || warn "Keycloak aus"
  for d in "${DIENSTE[@]}"; do [ -n "$(port_holder "${PORTS[$d]}")" ] && ok "$d ${PORTS[$d]}" || warn "$d aus"; done
  [ -n "$(port_holder "$UI_PORT")" ] && ok "Oberfläche $UI_PORT" || warn "Oberfläche aus"
}
cmd_reset() {
  cmd_stop
  for d in "${DIENSTE[@]}"; do rm -rf "$ROOT/stromentlastung-$d/data" && ok "H2-Dateien von $d gelöscht"; done
}
cmd_logs() { tail -n 80 -f "$RUN/${1:-antrag}.log"; }

case "${1:-}" in
  start) cmd_start ;; stop) cmd_stop ;; status) cmd_status ;; reset) cmd_reset ;; logs) cmd_logs "${2:-}" ;;
  *) sed -n '2,10p' "$0"; exit 1 ;;
esac
