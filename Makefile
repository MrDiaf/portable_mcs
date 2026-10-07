# ==========================================================================
#  Portable Minecraft 1.8.8 server
#  Edit the settings below, then run `make` (or `make up`).
#  Every setting can also be overridden per command: `make up PORT=25570`
# ==========================================================================

# --- Server settings ------------------------------------------------------
PORT         = 25565
MEMORY       = 16G
# survival | creative | adventure | spectator
GAMEMODE     = survival
# peaceful | easy | normal | hard
DIFFICULTY   = hard
HARDCORE     = false
MAX_PLAYERS  = 20
MOTD         = A Minecraft 1.8.8 Server
# false lets non-premium (cracked) clients join
ONLINE_MODE  = false
PVP          = true
VIEW_DISTANCE = 10

# --- Internals (you normally don't need to touch these) -------------------
SESSION      = mc-1.8.8
SERVER_DIR   = server
RUNTIME_DIR  = runtime

export PORT MEMORY GAMEMODE DIFFICULTY HARDCORE MAX_PLAYERS MOTD ONLINE_MODE \
       PVP VIEW_DISTANCE SESSION SERVER_DIR RUNTIME_DIR

MC := ./scripts/mc.sh

.DEFAULT_GOAL := up
.PHONY: up down restart console ip status logs install help

up: ## Start the server in the background
	@$(MC) up

down: ## Save the world and stop the server
	@$(MC) down

restart: ## Stop then start the server
	@$(MC) down
	@$(MC) up

console: ## Attach to the server console (detach: Ctrl+A then D)
	@$(MC) console

ip: ## Show the local IP and port to connect to
	@$(MC) ip

status: ## Show whether the server is running
	@$(MC) status

logs: ## Follow the server log (Ctrl+C to stop following)
	@$(MC) logs

install: ## Download Java 8 and the server jar without starting
	@$(MC) install

help: ## List the available commands
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-8s %s\n", $$1, $$2}'
