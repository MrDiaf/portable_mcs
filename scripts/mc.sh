#!/usr/bin/env bash
# Helper behind the Makefile. Settings come in as environment variables
# exported by the Makefile; run commands through `make`, not directly.
#
# With EAGLERCRAFT=true, players connect to a BungeeCord proxy (with the
# EaglerXServer plugin) on PORT, which accepts both regular Java clients and
# Eaglercraft browser clients and forwards them to the 1.8.8 server, which
# only listens on 127.0.0.1:BACKEND_PORT.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

: "${PORT:=25565}" "${MEMORY:=16G}" "${GAMEMODE:=survival}" "${DIFFICULTY:=hard}"
: "${HARDCORE:=false}" "${MAX_PLAYERS:=20}" "${MOTD:=A Minecraft 1.8.8 Server}"
: "${ONLINE_MODE:=true}" "${PVP:=true}" "${VIEW_DISTANCE:=10}" "${EAGLERCRAFT:=true}"
: "${BACKEND_PORT:=25566}" "${PROXY_MEMORY:=512M}"
: "${SESSION:=mc-1.8.8}" "${SERVER_DIR:=server}" "${PROXY_DIR:=proxy}" "${RUNTIME_DIR:=runtime}"

SERVER_DIR="$ROOT/$SERVER_DIR"
PROXY_DIR="$ROOT/$PROXY_DIR"
RUNTIME_DIR="$ROOT/$RUNTIME_DIR"
PROXY_SESSION="$SESSION-proxy"

JAVA8="$RUNTIME_DIR/java8/bin/java"     # the 1.8.8 server needs Java 8
JAVA21="$RUNTIME_DIR/java21/bin/java"   # BungeeCord + EaglerXServer need Java 17+

# Official Mojang 1.8.8 server jar
JAR="$SERVER_DIR/minecraft_server.1.8.8.jar"
JAR_URL="https://launcher.mojang.com/v1/objects/5fafba3f58c40dc51b5c3ca72a98f62dfdae1db7/server.jar"
JAR_SHA1="5fafba3f58c40dc51b5c3ca72a98f62dfdae1db7"

# BungeeCord proxy, build 2102
BUNGEE_JAR="$PROXY_DIR/BungeeCord.jar"
BUNGEE_URL="https://ci.md-5.net/job/BungeeCord/2102/artifact/bootstrap/target/BungeeCord.jar"
BUNGEE_SHA1="f2f4c12fa33aa63742fa983a895363c07e3e8df5"

# EaglerXServer 1.1.1 plugin (Eaglercraft browser client support)
EAGLER_JAR="$PROXY_DIR/plugins/EaglerXServer.jar"
EAGLER_URL="https://cdn.modrinth.com/data/Gtsn3SWv/versions/PN1bJIda/EaglerXServer.jar"
EAGLER_SHA1="f0b54a0dc47b512a1721c49eb94e3e4ff6c3302e"
EAGLER_LISTENERS="$PROXY_DIR/plugins/EaglercraftXServer/listeners.yml"

# EaglerWeb 1.0.1 plugin: serves the files in web/ over http://IP:PORT, so
# browsers can load an Eaglercraft client that is allowed to use ws://
EAGLERWEB_JAR="$PROXY_DIR/plugins/EaglerWeb.jar"
EAGLERWEB_URL="https://cdn.modrinth.com/data/U6w6KGWx/versions/58YjqiHB/EaglerWeb.jar"
EAGLERWEB_SHA1="8030568b09ba7aeab8ecd80f14d1f059d56145d1"
WEB_DIR="$ROOT/web"
WEB_ROOT="$PROXY_DIR/plugins/EaglerWeb/web"

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

eagler_enabled() {
    case "$EAGLERCRAFT" in
        true) return 0 ;;
        false) return 1 ;;
        *) die "EAGLERCRAFT must be true or false, not '$EAGLERCRAFT'" ;;
    esac
}

is_running() {
    screen -ls 2>/dev/null | grep -qE "[0-9]+\.${1}[[:space:]]"
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
        ss -ltnH "sport = :$1" 2>/dev/null | grep -q .
    else
        (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
    fi
}

# ---------------------------------------------------------------------------

install_java() {
    local version="$1" dir="$RUNTIME_DIR/java$1" arch
    [ -x "$dir/bin/java" ] && return
    case "$(uname -m)" in
        x86_64|amd64)  arch=x64 ;;
        aarch64|arm64) arch=aarch64 ;;
        *) die "Unsupported CPU architecture: $(uname -m)" ;;
    esac
    info "Downloading portable Java $version runtime ($arch)..."
    mkdir -p "$RUNTIME_DIR"
    local tmp="$RUNTIME_DIR/java$version.tar.gz"
    download "https://api.adoptium.net/v3/binary/latest/$version/ga/linux/$arch/jre/hotspot/normal/eclipse" "$tmp"
    rm -rf "$dir"
    mkdir -p "$dir"
    tar -xzf "$tmp" -C "$dir" --strip-components=1
    rm -f "$tmp"
    [ -x "$dir/bin/java" ] || die "Java $version install failed."
}

# install_file <name> <url> <sha1> <destination>
install_file() {
    [ -f "$4" ] && return
    info "Downloading $1..."
    mkdir -p "$(dirname "$4")"
    download "$2" "$4.part"
    echo "$3  $4.part" | sha1sum -c --quiet - || { rm -f "$4.part"; die "Checksum mismatch on $1."; }
    mv "$4.part" "$4"
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

# Escape characters special to the sed replacement
sed_escape() {
    printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'
}

# Quote a string for YAML
yaml_quote() {
    printf "'%s'" "${1//\'/\'\'}"
}

set_prop() {
    local file="$SERVER_DIR/server.properties" key="$1" value="$2"
    if grep -q "^${key}=" "$file"; then
        sed -i "s|^${key}=.*|${key}=$(sed_escape "$value")|" "$file"
    else
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
}

# set_yaml <file> <indent regex> <key> <value>: replace the value of every
# matching `key:` line. In list items the first key is prefixed with "- ".
set_yaml() {
    sed -E -i "s|^(${2})${3}:.*|\\1${3}: $(sed_escape "$4")|" "$1"
}

configure_server() {
    mkdir -p "$SERVER_DIR"
    echo "eula=true" > "$SERVER_DIR/eula.txt"
    touch "$SERVER_DIR/server.properties"
    # Empty lists so a fresh server doesn't log missing-file stack traces
    local f
    for f in banned-players banned-ips ops whitelist; do
        [ -f "$SERVER_DIR/$f.json" ] || echo "[]" > "$SERVER_DIR/$f.json"
    done

    if eagler_enabled; then
        # Only reachable through the proxy, which handles authentication
        set_prop server-ip     127.0.0.1
        set_prop server-port   "$BACKEND_PORT"
        set_prop online-mode   false
    else
        set_prop server-ip     ""
        set_prop server-port   "$PORT"
        set_prop online-mode   "$ONLINE_MODE"
    fi
    set_prop gamemode       "$(gamemode_id "$GAMEMODE")"
    set_prop force-gamemode true
    set_prop difficulty     "$(difficulty_id "$DIFFICULTY")"
    set_prop hardcore       "$HARDCORE"
    set_prop max-players    "$MAX_PLAYERS"
    set_prop motd           "$MOTD"
    set_prop pvp            "$PVP"
    set_prop view-distance  "$VIEW_DISTANCE"
}

configure_proxy() {
    local motd
    motd=$(yaml_quote "$MOTD")
    mkdir -p "$PROXY_DIR/plugins/EaglercraftXServer"

    # Minimal starting configs; BungeeCord and EaglerXServer fill in the rest
    if [ ! -f "$PROXY_DIR/config.yml" ]; then
        cat > "$PROXY_DIR/config.yml" <<EOF
online_mode: true
ip_forward: false
player_limit: 20
servers:
  lobby:
    motd: $motd
    address: 127.0.0.1:$BACKEND_PORT
    restricted: false
listeners:
- host: 0.0.0.0:$PORT
  query_port: $PORT
  motd: $motd
  max_players: 20
  priorities:
  - lobby
  forced_hosts: {}
EOF
    fi
    if [ ! -f "$EAGLER_LISTENERS" ]; then
        cat > "$EAGLER_LISTENERS" <<EOF
listener_list:
- listener_name: 'listener0'
  inject_address: '0.0.0.0:$PORT'
  server_icon: ''
  server_motd:
  - $motd
EOF
    fi

    # Apply the Makefile settings on every start
    local cfg="$PROXY_DIR/config.yml" item='[ -] '
    set_yaml "$cfg" ''      online_mode  "$ONLINE_MODE"
    set_yaml "$cfg" ''      player_limit "$MAX_PLAYERS"
    set_yaml "$cfg" "$item" host         "0.0.0.0:$PORT"
    set_yaml "$cfg" "$item" query_port   "$PORT"
    set_yaml "$cfg" "$item" motd         "$motd"
    set_yaml "$cfg" "$item" max_players  "$MAX_PLAYERS"
    set_yaml "$cfg" '    '  address      "127.0.0.1:$BACKEND_PORT"
    set_yaml "$EAGLER_LISTENERS" "$item" inject_address "'0.0.0.0:$PORT'"
    sed -i "/^  server_motd:/{n;s|^  - .*|  - $(sed_escape "$motd")|}" "$EAGLER_LISTENERS"

    sync_web
}

# Copy web/ to the EaglerWeb document root. A lone client .html that isn't
# called index.html is also served as index.html, so http://IP:PORT/ opens it.
sync_web() {
    mkdir -p "$WEB_DIR"
    rm -rf "$WEB_ROOT"
    mkdir -p "$WEB_ROOT"
    cp -r "$WEB_DIR/." "$WEB_ROOT/"
    rm -f "$WEB_ROOT/.gitkeep"
    if [ ! -f "$WEB_ROOT/index.html" ]; then
        local pages=("$WEB_ROOT"/*.html)
        if [ "${#pages[@]}" -eq 1 ] && [ -f "${pages[0]}" ]; then
            cp "${pages[0]}" "$WEB_ROOT/index.html"
        fi
    fi
}

has_web_client() {
    [ -f "$WEB_ROOT/index.html" ]
}

# wait_for <description> <session> <seconds> <check command...>
wait_for() {
    local what="$1" session="$2" timeout="$3" i
    shift 3
    printf 'Waiting for %s' "$what"
    for i in $(seq 1 "$timeout"); do
        if ! is_running "$session"; then
            echo
            return 2
        fi
        if "$@"; then
            echo
            return 0
        fi
        printf '.'
        sleep 1
    done
    echo
    return 1
}

server_done() {
    [ -f "$SERVER_LOG" ] && [ "$(stat -c %i "$SERVER_LOG")" != "$OLD_SERVER_LOG" ] \
        && grep -q 'Done (' "$SERVER_LOG"
}

start_server() {
    local port="$PORT"
    eagler_enabled && port="$BACKEND_PORT"
    port_listening "$port" && die "Port $port is already in use. Change it in the Makefile."

    # The server rolls latest.log on startup, so a new inode means a new log
    SERVER_LOG="$SERVER_DIR/logs/latest.log"
    OLD_SERVER_LOG=$(stat -c %i "$SERVER_LOG" 2>/dev/null || echo none)

    info "Starting Minecraft 1.8.8 with $MEMORY RAM ($GAMEMODE, $DIFFICULTY)..."
    screen -dmS "$SESSION" bash -c "cd '$SERVER_DIR' && exec '$JAVA8' \
        -Xms$MEMORY -Xmx$MEMORY \
        -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 \
        -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch \
        -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M \
        -XX:G1ReservePercent=20 -XX:InitiatingHeapOccupancyPercent=15 \
        -jar '$JAR' nogui"

    local rc=0
    wait_for "the world to load" "$SESSION" 300 server_done || rc=$?
    case $rc in
        0) ;;
        2) die "Server exited during startup. Check $SERVER_LOG" ;;
        *) warn "Server is still starting. Use 'make logs' or 'make console' to watch it." ;;
    esac
}

start_proxy() {
    port_listening "$PORT" && die "Port $PORT is already in use. Change PORT in the Makefile."

    info "Starting proxy with Eaglercraft support on port $PORT..."
    screen -dmS "$PROXY_SESSION" bash -c "cd '$PROXY_DIR' && exec '$JAVA21' \
        -Xms$PROXY_MEMORY -Xmx$PROXY_MEMORY -XX:+UseG1GC \
        -jar '$BUNGEE_JAR'"

    local rc=0
    wait_for "the proxy" "$PROXY_SESSION" 60 port_listening "$PORT" || rc=$?
    case $rc in
        0) ;;
        2) die "Proxy exited during startup. Check $PROXY_DIR/proxy.log.0" ;;
        *) die "Proxy did not start listening on port $PORT. Use 'make proxy-console' to check." ;;
    esac
}

# stop_session <name> <session> <console commands>
stop_session() {
    is_running "$2" || return 0
    info "Stopping $1..."
    screen -S "$2" -p 0 -X stuff "$3"
    local i
    for i in $(seq 1 60); do
        is_running "$2" || return 0
        sleep 1
    done
    warn "$1 did not stop within 60s, forcing it to quit."
    screen -S "$2" -X quit || true
}

# ---------------------------------------------------------------------------

cmd_install() {
    need screen
    need tar
    need sha1sum
    install_java 8
    install_file "Minecraft 1.8.8 server" "$JAR_URL" "$JAR_SHA1" "$JAR"
    if eagler_enabled; then
        install_java 21
        install_file "BungeeCord proxy" "$BUNGEE_URL" "$BUNGEE_SHA1" "$BUNGEE_JAR"
        install_file "EaglerXServer plugin" "$EAGLER_URL" "$EAGLER_SHA1" "$EAGLER_JAR"
        install_file "EaglerWeb plugin" "$EAGLERWEB_URL" "$EAGLERWEB_SHA1" "$EAGLERWEB_JAR"
    fi
    info "Everything is downloaded."
}

cmd_up() {
    if is_running "$SESSION" || is_running "$PROXY_SESSION"; then
        warn "Server is already running. Use 'make restart' to apply new settings."
        cmd_ip
        return
    fi
    if eagler_enabled && [ "$PORT" = "$BACKEND_PORT" ]; then
        die "PORT and BACKEND_PORT must be different."
    fi
    cmd_install
    configure_server
    start_server
    if eagler_enabled; then
        configure_proxy
        start_proxy
    fi
    info "Server is up!"
    cmd_ip
}

cmd_down() {
    if ! is_running "$SESSION" && ! is_running "$PROXY_SESSION"; then
        info "Minecraft server is not running."
        return
    fi
    stop_session "proxy" "$PROXY_SESSION" $'end\r'
    stop_session "server (saving world)" "$SESSION" $'save-all\rstop\r'
    info "Server stopped."
}

attach() {
    is_running "$1" || die "$2 is not running. Start it with 'make up'."
    echo "Attaching to the $2 console. Detach with Ctrl+A then D (do NOT press Ctrl+C)."
    sleep 1
    exec screen -r "$1"
}

cmd_ip() {
    local ip
    ip=$(local_ip)
    echo
    printf '  Minecraft 1.8.8:  \033[1m%s:%s\033[0m\n' "$ip" "$PORT"
    if eagler_enabled; then
        printf '  Eaglercraft:      \033[1mws://%s:%s\033[0m\n' "$ip" "$PORT"
        if has_web_client; then
            printf '  Play in browser:  \033[1mhttp://%s:%s\033[0m\n' "$ip" "$PORT"
        else
            echo
            echo "  To play from a browser, put an EaglercraftX 1.8 offline client (.html)"
            echo "  in the web/ folder and run 'make restart'."
        fi
    fi
    echo
    echo "  On this PC use localhost:$PORT$(eagler_enabled && echo " / ws://localhost:$PORT")"
    echo
}

cmd_status() {
    if is_running "$SESSION"; then
        info "Minecraft server is running."
    else
        info "Minecraft server is not running."
    fi
    if eagler_enabled || is_running "$PROXY_SESSION"; then
        if is_running "$PROXY_SESSION"; then
            info "Eaglercraft proxy is running."
        else
            info "Eaglercraft proxy is not running."
        fi
    fi
}

cmd_logs() {
    local log="$SERVER_DIR/logs/latest.log"
    [ -f "$log" ] || die "No log yet. Start the server with 'make up'."
    exec tail -n 50 -f "$log"
}

case "${1:-}" in
    up)            cmd_up ;;
    down)          cmd_down ;;
    console)       attach "$SESSION" "server" ;;
    proxy-console) attach "$PROXY_SESSION" "proxy" ;;
    ip)            cmd_ip ;;
    status)        cmd_status ;;
    logs)          cmd_logs ;;
    install)       cmd_install ;;
    *) die "Usage: $0 {up|down|console|proxy-console|ip|status|logs|install}" ;;
esac
