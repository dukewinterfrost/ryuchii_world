#!/bin/zsh
set -eu
cd "$(dirname "$0")"
python3 tools/apply_game_balance.py "Game Balance.xlsx"
printf '\nPress Return to close.'
read
