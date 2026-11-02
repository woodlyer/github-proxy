#!/usr/bin/env bash

# cd to repository directory
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$BASE_DIR"

PID_FILE="$BASE_DIR/app.pid"
LOG_FILE="$BASE_DIR/app.log"
APP_ENTRY="$BASE_DIR/app/main.py"
PORT=8001

# Determine Python executable
if command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD="python3"
elif command -v python >/dev/null 2>&1; then
    PYTHON_CMD="python"
else
    PYTHON_CMD="python3"
fi

get_pid() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
    fi
    # Fallback to searching process table
    pgrep -f "python.*${APP_ENTRY}" | head -n 1
}

start() {
    local pid
    pid=$(get_pid)
    if [ -n "$pid" ]; then
        echo "Service is already running (PID: $pid)."
        return 0
    fi

    echo "Starting github-proxy service on port ${PORT}..."
    
    # Check dependencies
    if ! $PYTHON_CMD -c "import flask, requests" >/dev/null 2>&1; then
        echo "Warning: Missing flask or requests. Installing..."
        $PYTHON_CMD -m pip install -q flask requests || true
    fi

    # Set PYTHONPATH
    export PYTHONPATH="$BASE_DIR/app:$PYTHONPATH"
    
    nohup $PYTHON_CMD "$APP_ENTRY" >> "$LOG_FILE" 2>&1 &
    local new_pid=$!
    echo "$new_pid" > "$PID_FILE"
    
    sleep 1
    if kill -0 "$new_pid" 2>/dev/null; then
        echo "Service started successfully (PID: $new_pid)."
        echo "Log file: $LOG_FILE"
    else
        echo "Error: Failed to start service. Check logs at $LOG_FILE:"
        tail -n 15 "$LOG_FILE"
        return 1
    fi
}

stop() {
    local pid
    pid=$(get_pid)
    if [ -z "$pid" ]; then
        echo "Service is not running."
        rm -f "$PID_FILE"
        return 0
    fi

    echo "Stopping service (PID: $pid)..."
    kill "$pid" 2>/dev/null || true
    
    # Wait for process to exit
    for i in $(seq 1 10); do
        if ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        sleep 0.5
    done

    # Force kill if still running
    if kill -0 "$pid" 2>/dev/null; then
        echo "Force killing process $pid..."
        kill -9 "$pid" 2>/dev/null || true
    fi

    rm -f "$PID_FILE"
    echo "Service stopped."
}

status() {
    local pid
    pid=$(get_pid)
    if [ -n "$pid" ]; then
        echo "Status: RUNNING (PID: $pid)"
        if command -v netstat >/dev/null 2>&1; then
            netstat -tlpn 2>/dev/null | grep "$pid" || true
        elif command -v ss >/dev/null 2>&1; then
            ss -tlpn 2>/dev/null | grep "$pid" || true
        fi
    else
        echo "Status: STOPPED"
    fi
}

log() {
    if [ -f "$LOG_FILE" ]; then
        tail -f -n 50 "$LOG_FILE"
    else
        echo "No log file found at $LOG_FILE."
    fi
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        sleep 1
        start
        ;;
    status)
        status
        ;;
    log|logs)
        log
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|log}"
        exit 1
        ;;
esac
