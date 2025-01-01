Here is the production-ready `startup.sh` script for the AI Resume Analyzer MVP:

#!/bin/bash

set -euo pipefail

# Load environment variables
if [ -f .env ]; then
  source .env
fi

# Validate required environment variables
if [ -z "${MONGODB_URI-}" ] || [ -z "${STRIPE_SECRET_KEY-}" ] || [ -z "${OPENAI_API_KEY-}" ]; then
  echo "Error: Missing required environment variables" >&2
  exit 1
fi

# Set default values for optional variables
PORT="${PORT:-3000}"
REACT_APP_BASE_URL="${REACT_APP_BASE_URL:-http://localhost:$PORT}"

# Directories and files
PROJECT_ROOT=$(pwd)
LOG_FILE="$PROJECT_ROOT/logs/startup.log"
PID_FILE="$PROJECT_ROOT/pids/startup.pid"

# Functions
log_info() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_error() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" >&2
}

cleanup() {
  log_info "Cleaning up processes and files..."
  if [ -f "$PID_FILE" ]; then
    kill $(cat "$PID_FILE") || true
    rm "$PID_FILE"
  fi
  exit 0
}

check_dependencies() {
  for cmd in node npm mongodb mongod pg_ctl redis-server docker docker-compose; do
    if ! command -v "$cmd" &> /dev/null; then
      log_error "Required dependency '$cmd' not found. Please ensure it is installed."
      exit 1
    fi
  done
}

check_port() {
  if lsof -Pi :"$1" -sTCP:LISTEN -t >/dev/null; then
    return 1
  else
    return 0
  fi
}

wait_for_service() {
  local service_name="$1"
  local timeout="${2:-60}"
  local interval="${3:-5}"

  log_info "Waiting for $service_name to start..."
  local start_time=$SECONDS
  while true; do
    if "$@"; then
      log_info "$service_name is ready"
      return 0
    fi

    if [ $((SECONDS - start_time)) -gt $timeout ]; then
      log_error "$service_name failed to start within the timeout period"
      return 1
    fi

    sleep $interval
  done
}

verify_service() {
  local service_name="$1"
  local health_check="${2:-}"

  if [ -n "$health_check" ]; then
    if ! $health_check; then
      log_error "$service_name is not healthy"
      return 1
    fi
  else
    if ! check_port "$3"; then
      log_error "$service_name is not running"
      return 1
    fi
  fi

  return 0
}

start_database() {
  log_info "Starting MongoDB..."
  mongod --fork --logpath "$LOG_FILE" --pidfilepath "$PID_FILE"
  wait_for_service "MongoDB" 60 5 verify_service "MongoDB" "" 27017
}

start_backend() {
  log_info "Starting backend server..."
  cd "$PROJECT_ROOT/backend"
  npm install
  npm start &
  echo $! >> "$PID_FILE"
  wait_for_service "Backend server" 120 10 verify_service "Backend server" "" 3000
}

start_frontend() {
  log_info "Starting frontend server..."
  cd "$PROJECT_ROOT/frontend"
  npm install
  npm start &
  echo $! >> "$PID_FILE"
  wait_for_service "Frontend server" 120 10 verify_service "Frontend server" "" 3000
}

store_pid() {
  local pid=$1
  echo $pid > "$PID_FILE"
}

# Main execution
check_dependencies
start_database
start_backend
start_frontend

log_info "AI Resume Analyzer startup complete!"
log_info "Backend: $REACT_APP_BASE_URL/api"
log_info "Frontend: $REACT_APP_BASE_URL"

trap cleanup EXIT ERR

while true; do
  sleep 60
done