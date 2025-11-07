#!/bin/bash

URL="https://console-openshift-console.apps.ocp.example.com"

# Create a temporary user data directory
TMP_PROFILE=$(mktemp -d)

# Set up SSH SOCKS5 proxy
ssh -fN -D 127.0.0.1:6666 root@10.0.79.55

# Launch Chrome (light theme + temporary profile + new window)
 /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --proxy-server="socks5://127.0.0.1:6666" \
  --user-data-dir="$TMP_PROFILE" \
  --disable-features=DarkMode,WebUIDarkMode \
  --no-first-run --no-default-browser-check \
  --new-window "$URL"

# Remove the temporary directory after Chrome exits
rm -rf "$TMP_PROFILE"
