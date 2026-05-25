#!/bin/bash
set -e

mkdir -p /var/log/opencanary

echo "[honeypot] Starting OpenCanary..."
opencanaryd --dev &
CANARY_PID=$!

# Give opencanary a moment to initialize before tailing
sleep 3

echo "[honeypot] Starting ntfy notifier..."
python3 /usr/local/bin/notifier.py &
NOTIFIER_PID=$!

echo "[honeypot] Running — canary PID $CANARY_PID, notifier PID $NOTIFIER_PID"

# If either process dies, kill both and exit so Docker restarts the container
wait -n $CANARY_PID $NOTIFIER_PID
echo "[honeypot] A process exited — shutting down container for restart"
kill $CANARY_PID $NOTIFIER_PID 2>/dev/null
exit 1
