# Portable Minecraft 1.8.8 Server

A Minecraft **1.8.8** server you can start with one command. You don't need Docker or a system-wide Java install.
On first start it downloads a portable Java 8 runtime and the official Mojang server jar into this folder.

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

The server reserves **16 GB of RAM** by default. Make sure the machine has more than that free, or lower `MEMORY` (see below).

## Setup

```bash
git clone <this-repo> portable_mcs
cd portable_mcs
make
```

That's all. The first run downloads about 50 MB and generates the world. It then prints the address to connect to:

```
==> Server is up!

  Connect in Minecraft (1.8.8) with:

      192.168.0.170:25565
```

In Minecraft 1.8.8, go to **Multiplayer → Add Server** and enter that address.

By running the server you accept the [Minecraft EULA](https://www.minecraft.net/en-us/eula).

## Commands

| Command        | What it does                                                   |
|----------------|----------------------------------------------------------------|
| `make` / `make up` | Start the server in the background                         |
| `make down`    | Save the world and stop the server                              |
| `make restart` | Stop, then start again                                          |
| `make console` | Open the live server console                                    |
| `make ip`      | Show the local IP and port to connect to                        |
| `make status`  | Show whether the server is running                              |
| `make logs`    | Follow the server log                                           |
| `make install` | Only download Java and the server jar, without starting         |
| `make help`    | List all commands                                               |

### Using the console

`make console` opens the server console, where you can type commands such as `op <name>`, `say hi` or `list`. You don't need a `/` before them.

**To leave the console, press `Ctrl+A`, then `D`.** The server keeps running.
Pressing `Ctrl+C` or typing `stop` in the console shuts the server down.

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
```

Put comments on their own line, as above. In a Makefile, a comment at the end of a line adds trailing spaces to the value.

After you edit them, run `make restart`. They are written into `server/server.properties` every time the server starts.

You can also override a setting for a single run:

```bash
make up PORT=25570 MEMORY=8G
```

Any other `server.properties` option (for example `level-seed` or `spawn-protection`) can be changed directly in `server/server.properties`. Only the keys listed above get overwritten.

`ONLINE_MODE = false` lets players without a paid Minecraft account join. It also turns off account verification, so anyone can join under any name. Use it only on a trusted LAN.

## Playing with others

- **Same network (LAN):** use the address from `make ip`.
- **Firewall:** if other machines can't connect, open the port:
  `sudo ufw allow 25565/tcp` (or your `PORT`).
- **Over the internet:** forward the port (TCP) on your router to this machine's local IP. Players then connect to your public IP.

## Files

```
Makefile          settings and commands
scripts/mc.sh     the logic behind the make commands
runtime/java/     portable Java 8 (downloaded, git-ignored)
server/           server jar, world, configs and logs (git-ignored)
```

- **Back up the world:** stop the server with `make down`, then copy `server/world/`.
- **Start over with a new world:** run `make down`, then `rm -rf server/world`.
- **Remove everything:** run `make down`, then delete the folder.
