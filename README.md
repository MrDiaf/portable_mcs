# Portable Minecraft 1.8.8 Server

A Minecraft **1.8.8** server you can start with one command. Players can join from regular Minecraft and from **Eaglercraft** in a web browser.
You don't need Docker or a system-wide Java install: on first start, everything it needs downloads into this folder.

## Requirements

A Linux machine (x86_64 or ARM64) with:

- `make`
- `screen`: keeps the server running in the background and lets you open its console
- `curl` (or `wget`), `tar`, `sha1sum`

On Debian/Ubuntu:

```bash
sudo apt install make screen curl
```

On Fedora: `sudo dnf install make screen curl`. On Arch: `sudo pacman -S make screen curl`.

The server reserves **16 GB of RAM** by default, plus about 512 MB for the Eaglercraft proxy. Make sure the machine has more than that free, or lower `MEMORY` (see below).

## Setup

```bash
git clone <this-repo> portable_mcs
cd portable_mcs
make
```

That's all. The first run downloads about 140 MB, generates the world, and prints the addresses to connect to:

```
==> Server is up!

  Minecraft 1.8.8:  192.168.0.170:25565
  Eaglercraft:      ws://192.168.0.170:25565
```

- **Minecraft 1.8.8:** go to **Multiplayer → Add Server** and enter the first address.
- **Eaglercraft (browser):** see [Playing with Eaglercraft](#playing-with-eaglercraft).

By running the server you accept the [Minecraft EULA](https://www.minecraft.net/en-us/eula).

## Commands

| Command              | What it does                                                |
|----------------------|-------------------------------------------------------------|
| `make` / `make up`   | Start the server in the background                          |
| `make down`          | Save the world and stop the server                          |
| `make restart`       | Stop, then start again                                      |
| `make console`       | Open the live server console                                |
| `make proxy-console` | Open the Eaglercraft proxy console                          |
| `make ip`            | Show the local addresses to connect to                      |
| `make status`        | Show whether the server is running                          |
| `make logs`          | Follow the server log                                       |
| `make install`       | Only download everything, without starting                  |
| `make help`          | List all commands                                           |

### Using the console

`make console` opens the server console, where you can type commands such as `op <name>`, `say hi` or `list`. You don't need a `/` before them.

**To leave the console, press `Ctrl+A`, then `D`.** The server keeps running.
Pressing `Ctrl+C` or typing `stop` in the console shuts the server down. Use `make down` instead, which stops the server and the proxy cleanly.

## Configuration

All settings are at the top of the [Makefile](Makefile):

```make
PORT          = 25565
MEMORY        = 16G
# survival | creative | adventure | spectator
GAMEMODE      = survival
# peaceful | easy | normal | hard
DIFFICULTY    = hard
HARDCORE      = false
MAX_PLAYERS   = 20
MOTD          = A Minecraft 1.8.8 Server
ONLINE_MODE   = true
PVP           = true
VIEW_DISTANCE = 10
EAGLERCRAFT   = true
```

Put comments on their own line, as above. In a Makefile, a comment at the end of a line adds trailing spaces to the value.

After you edit them, run `make restart`. They are written into the server and proxy config files every time the server starts.

You can also override a setting for a single run:

```bash
make up PORT=25570 MEMORY=8G
```

Any other `server.properties` option (for example `level-seed` or `spawn-protection`) can be changed directly in `server/server.properties`. Only the keys the Makefile controls get overwritten.

- **`ONLINE_MODE`:** `true` only lets players with a paid Minecraft account join through regular Minecraft. `false` lets anyone join under any name. Use `false` only on a trusted LAN.
- **`EAGLERCRAFT`:** `false` turns off browser support and runs the 1.8.8 server directly on `PORT`, without the proxy.

## Playing with Eaglercraft

Browsers block `ws://` connections from pages loaded over `https://`. If you use an Eaglercraft client from a website, you'll see:
*"you are on a https: page! html5 will only allow wss://"*.
The fix is to host the client yourself, over plain `http://`, on the same port as the server:

1. Get an **EaglercraftX 1.8 offline client**. This is a single `.html` file, usually offered as "Offline Download" on Eaglercraft sites.
2. Put it in the `web/` folder of this repo. Any file name works.
3. Run `make restart`. `make ip` now shows a browser link:
   ```
     Play in browser:  http://192.168.0.170:25565
   ```
4. Open that link, go to **Multiplayer → Add Server** and enter the `ws://` address from `make ip`.

Everything in `web/` is served at `http://IP:PORT/`. If the folder holds a single `.html` file, it's also served as `index.html`.

Notes:

- **Use an EaglercraftX 1.8 client.** Older Eaglercraft 1.5 clients won't work.
- **Opening the downloaded `.html` file straight from disk also works**, without the `web/` folder.
- **Joining from an `https://` Eaglercraft website** needs secure `wss://`. That means a TLS certificate for a domain name, through a reverse proxy (nginx, Caddy) in front of `PORT` or through `tls_config` in `proxy/plugins/EaglercraftXServer/listeners.yml`.
- **Eaglercraft players have no Mojang account, so they can pick any username.** To control who joins, use the whitelist from `make console`: `whitelist add <name>`, then `whitelist on`.

### How it works

Eaglercraft runs in a browser, and a browser can only connect over WebSockets, which a plain Minecraft server doesn't speak.
So when `EAGLERCRAFT = true`, a [BungeeCord](https://www.spigotmc.org/wiki/bungeecord/) proxy listens on `PORT`.
It runs two plugins:

- [EaglerXServer](https://modrinth.com/mod/eaglercraftxserver) accepts regular Minecraft and Eaglercraft connections on that one port.
- [EaglerWeb](https://modrinth.com/plugin/eaglerweb) serves the `web/` folder.

The proxy forwards everyone to the 1.8.8 server, which only listens on `127.0.0.1:25566` (`BACKEND_PORT`), so it can't be reached from outside.

## Playing with others

- **Same network (LAN):** use the addresses from `make ip`.
- **Firewall:** if other machines can't connect, open the port:
  `sudo ufw allow 25565/tcp` (or your `PORT`).
- **Over the internet:** forward the port (TCP) on your router to this machine's local IP. Players then connect to your public IP.

## Files

```
Makefile          settings and commands
scripts/mc.sh     the logic behind the make commands
runtime/java8/    portable Java 8 for the 1.8.8 server (downloaded, git-ignored)
runtime/java21/   portable Java 21 for the proxy (downloaded, git-ignored)
server/           server jar, world, configs and logs (git-ignored)
proxy/            BungeeCord, its plugins and their configs (git-ignored)
web/              put an Eaglercraft client .html here (contents git-ignored)
```

- **Back up the world:** stop the server with `make down`, then copy `server/world/`.
- **Start over with a new world:** run `make down`, then `rm -rf server/world`.
- **Remove everything:** run `make down`, then delete the folder.
