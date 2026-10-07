#!/usr/bin/env bash
# Helper behind the Makefile. Settings come in as environment variables
# exported by the Makefile; run commands through `make`, not directly.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

: "${PORT:=25565}" "${MEMORY:=16G}" "${GAMEMODE:=survival}" "${DIFFICULTY:=hard}"
: "${HARDCORE:=false}" "${MAX_PLAYERS:=20}" "${MOTD:=A Minecraft 1.8.8 Server}"
: "${ONLINE_MODE:=true}" "${PVP:=true}" "${VIEW_DISTANCE:=10}"
: "${SESSION:=mc-1.8.8}" "${SERVER_DIR:=server}" "${RUNTIME_DIR:=runtime}"

SERVER_DIR="$ROOT/$SERVER_DIR"
RUNTIME_DIR="$ROOT/$RUNTIME_DIR"
JAVA="$RUNTIME_DIR/java/bin/java"
JAR="$SERVER_DIR/minecraft_server.1.8.8.jar"

# Official Mojang 1.8.8 server jar
JAR_URL="https://launcher.mojang.com/v1/objects/5fafba3f58c40dc51b5c3ca72a98f62dfdae1db7/server.jar"
JAR_SHA1="5fafba3f58c40dc51b5c3ca72a98f62dfdae1db7"

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

need() {
    command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed. Install it with your package manager (e.g. sudo apt install $1)."
}

download() {
    if command -v curl >/dev/null 2>&1; then
        curl -fL --progress-bar -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --show-progress -O "$2" "$1"
    else
        die "Neither curl nor wget is installed."
    fi
}

is_running() {
    screen -ls 2>/dev/null | grep -qE "[0-9]+\.${SESSION}[[:space:]]"
}

local_ip() {
    local ip=""
    if command -v ip >/dev/null 2>&1; then
        ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<NF;i++) if ($i=="src") {print $(i+1); exit}}')
    fi
    if [ -z "$ip" ] && command -v hostname >/dev/null 2>&1; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    echo "${ip:-127.0.0.1}"
}

port_listening() {
    if command -v ss >/dev/null 2>&1; then
        ss -ltnH "sport = :$PORT" 2>/dev/null | grep -q .
    else
        (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null
    fi
}

# ---------------------------------------------------------------------------

install_java() {
    [ -x "$JAVA" ] && return
    local arch
    case "$(uname -m)" in
        x86_64|amd64)  arch=x64 ;;
        aarch64|arm64) arch=aarch64 ;;
        *) die "Unsupported CPU architecture: $(uname -m)" ;;
    esac
    info "Downloading portable Java 8 runtime ($arch)..."
    mkdir -p "$RUNTIME_DIR"
    local tmp="$RUNTIME_DIR/java.tar.gz"
    download "https://api.adoptium.net/v3/binary/latest/8/ga/linux/$arch/jre/hotspot/normal/eclipse" "$tmp"
    rm -rf "$RUNTIME_DIR/java"
    mkdir -p "$RUNTIME_DIR/java"
    tar -xzf "$tmp" -C "$RUNTIME_DIR/java" --strip-components=1
    rm -f "$tmp"
    [ -x "$JAVA" ] || die "Java install failed."
}

install_jar() {
    [ -f "$JAR" ] && return
    info "Downloading Minecraft 1.8.8 server jar..."
    mkdir -p "$SERVER_DIR"
    download "$JAR_URL" "$JAR.part"
    echo "$JAR_SHA1  $JAR.part" | sha1sum -c --quiet - || { rm -f "$JAR.part"; die "Checksum mismatch on server jar."; }
    mv "$JAR.part" "$JAR"
}

# server.properties in 1.8.8 wants numbers for gamemode and difficulty
gamemode_id() {
    case "$1" in
        survival|0) echo 0 ;; creative|1) echo 1 ;;
        adventure|2) echo 2 ;; spectator|3) echo 3 ;;
        *) die "Unknown GAMEMODE '$1' (use survival, creative, adventure or spectator)" ;;
    esac
}

difficulty_id() {
    case "$1" in
        peaceful|0) echo 0 ;; easy|1) echo 1 ;;
        normal|2) echo 2 ;; hard|3) echo 3 ;;
        *) die "Unknown DIFFICULTY '$1' (use peaceful, easy, normal or hard)" ;;
    esac
}

set_prop() {
    local file="$SERVER_DIR/server.properties" key="$1" value="$2"
    if grep -q "^${key}=" "$file"; then
        # Escape characters special to the sed replacement
        local escaped
        escaped=$(printf '%s' "$value" | sed -e 's/[\/&|]/\\&/g')
        sed -i "s|^${key}=.*|${key}=${escaped}|" "$file"
    else
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
}

configure() {
    mkdir -p "$SERVER_DIR"
    echo "eula=true" > "$SERVER_DIR/eula.txt"
    touch "$SERVER_DIR/server.properties"
    # Empty lists so a fresh server doesn't log missing-file stack traces
    local f
    for f in banned-players banned-ips ops whitelist; do
        [ -f "$SERVER_DIR/$f.json" ] || echo "[]" > "$SERVER_DIR/$f.json"
    done
    set_prop server-port   "$PORT"
    set_prop gamemode      "$(gamemode_id "$GAMEMODE")"
    set_prop force-gamemode true
    set_prop difficulty    "$(difficulty_id "$DIFFICULTY")"
    set_prop hardcore      "$HARDCORE"
    set_prop max-players   "$MAX_PLAYERS"
    set_prop motd          "$MOTD"
    set_prop online-mode   "$ONLINE_MODE"
    set_prop pvp           "$PVP"
    set_prop view-distance "$VIEW_DISTANCE"
}

# ---------------------------------------------------------------------------

cmd_install() {
    need screen
    need tar
    need sha1sum
    install_java
    install_jar
    info "Everything is downloaded."
}

cmd_up() {
    if is_running; then
        warn "Server is already running."
        cmd_ip
        return
    fi
    cmd_install
    configure

    if port_listening; then
        die "Port $PORT is already in use. Change PORT in the Makefile."
    fi

    # The server rolls latest.log on startup, so a new inode means a new log
    local log="$SERVER_DIR/logs/latest.log" old_log
    old_log=$(stat -c %i "$log" 2>/dev/null || echo none)

    info "Starting Minecraft 1.8.8 with $MEMORY RAM on port $PORT ($GAMEMODE, $DIFFICULTY)..."
    screen -dmS "$SESSION" bash -c "cd '$SERVER_DIR' && exec '$JAVA' \
        -Xms$MEMORY -Xmx$MEMORY \
        -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 \
        -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch \
        -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M \
        -XX:G1ReservePercent=20 -XX:InitiatingHeapOccupancyPercent=15 \
        -jar '$JAR' nogui"

    printf 'Waiting for the world to load'
    local i
    for i in $(seq 1 180); do
        if ! is_running; then
            echo
            die "Server exited during startup. Check $SERVER_DIR/logs/latest.log"
        fi
        if [ -f "$log" ] && [ "$(stat -c %i "$log")" != "$old_log" ] && grep -q 'Done (' "$log"; then
            echo
            info "Server is up!"
            cmd_ip
            return
        fi
        printf '.'
        sleep 1
    done
    echo
    warn "Server is still starting. Use 'make logs' or 'make console' to watch it."
}

cmd_down() {
    if ! is_running; then
        info "Server is not running."
        return
    fi
    info "Saving world and stopping server..."
    screen -S "$SESSION" -p 0 -X stuff $'save-all\rstop\r'
    local i
    for i in $(seq 1 60); do
        is_running || { info "Server stopped."; return; }
        sleep 1
    done
    warn "Server did not stop within 60s, forcing it to quit."
    screen -S "$SESSION" -X quit || true
}

cmd_console() {
    is_running || die "Server is not running. Start it with 'make up'."
    echo "Attaching to the console. Detach with Ctrl+A then D (do NOT press Ctrl+C)."
    sleep 1
    exec screen -r "$SESSION"
}

cmd_ip() {
    local ip
    ip=$(local_ip)
    echo
    echo "  Connect in Minecraft (1.8.8) with:"
    echo
    printf '      \033[1m%s:%s\033[0m\n' "$ip" "$PORT"
    echo
    echo "  Same PC:   localhost:$PORT"
    echo
}

cmd_status() {
    if is_running; then
        info "Server is running (screen session '$SESSION', port $PORT)."
    else
        info "Server is not running."
    fi
}

cmd_logs() {
    local log="$SERVER_DIR/logs/latest.log"
    [ -f "$log" ] || die "No log yet. Start the server with 'make up'."
    exec tail -n 50 -f "$log"
}

case "${1:-}" in
    up)      cmd_up ;;
    down)    cmd_down ;;
    console) cmd_console ;;
    ip)      cmd_ip ;;
    status)  cmd_status ;;
    logs)    cmd_logs ;;
    install) cmd_install ;;
    *) die "Usage: $0 {up|down|console|ip|status|logs|install}" ;;
esac
