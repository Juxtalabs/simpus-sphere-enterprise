#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
umask 077
action=${1:-status}
dc() { docker compose --env-file .env.local "$@"; }
case "$action" in
 prepare)
  if [ ! -f .env.local ]; then
   printf 'POSTGRES_PASSWORD=%s\nWEB_PORT=3003\nALLOW_PRIVATE_DESTINATIONS=false\nCOOKIE_SECURE=true\n' "$(openssl rand -hex 32)" > .env.local
  fi
  printf 'Settings prepared.\n'
  ;;
 init)
  dc up -d --wait postgres
  printf 'Administrator username: '; read -r admin_name
  printf 'Administrator password (minimum 12 characters): '
  old_tty=$(stty -g); trap 'stty "$old_tty"' EXIT HUP INT TERM
  stty -echo; read -r admin_password; stty "$old_tty"; trap - EXIT HUP INT TERM
  printf '\n'
  printf '%s\n' "$admin_password" | dc run --rm -T app init --username "$admin_name" --password-stdin
  unset admin_password
  ;;
 up) dc up -d --wait --wait-timeout 180 ;;
 local) dc --profile test up -d --wait --wait-timeout 180 ;;
 status) dc ps ;;
 logs) dc logs --tail 100 --follow app ;;
 doctor) dc exec -T app puskesmas-scraper check ;;
 backup)
  backup_root=${2:-}
  case "$backup_root" in /*) ;; *) printf 'Use an existing absolute backup directory.\n'; exit 2 ;; esac
  [ -d "$backup_root" ] || { printf 'Backup directory does not exist.\n'; exit 2; }
  app_id=$(dc ps -q app)
  [ -n "$app_id" ] || { printf 'Start the app before taking this maintenance backup.\n'; exit 2; }
  runtime_volume=$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Name}}{{end}}{{end}}' "$app_id")
  [ -n "$runtime_volume" ] || { printf 'Runtime volume not found.\n'; exit 2; }
  backup_root=$(CDPATH= cd -- "$backup_root" && pwd -P)
  backup_dir="$backup_root/simpus-$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -m 700 "$backup_dir"
  # The Loop worker is optional: stop and restart it only if it is running now.
  services=app
  [ -z "$(dc --profile loop-agent ps -q --status running loop-worker)" ] || services="app loop-worker"
  dc --profile loop-agent stop $services
  trap 'dc --profile loop-agent start $services' EXIT HUP INT TERM
  dc exec -T postgres pg_dump -U puskesmas -d puskesmas_rust -Fc > "$backup_dir/database.dump"
  docker run --rm --mount "type=volume,src=$runtime_volume,dst=/data,readonly" \
   --mount "type=bind,src=$backup_dir,dst=/backup" --entrypoint tar \
   puskesmas-scraper:rust-hybrid czf /backup/runtime.tar.gz -C /data .
  cp .env.local "$backup_dir/config.env"
  dc --profile loop-agent start $services
  trap - EXIT HUP INT TERM
  printf 'Backup saved to %s\n' "$backup_dir"
  ;;
 down) dc --profile test --profile loop-agent down ;;
 *) printf 'Usage: sh deploy.sh prepare|init|up|local|status|logs|doctor|backup ABSOLUTE_DIR|down\n'; exit 2 ;;
esac
