#!/bin/bash
# Wrapper for devcontainer lifecycle commands.
# Logs all output to a file so it survives the "Press Any Key to Close Terminal" dismissal.

PHASE="$1"
shift
LOG_DIR="/tmp/devcontainer-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/${PHASE}.log"

echo "=== devcontainer $PHASE started at $(date) ===" | tee "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Run the command, teeing output to the log file.
# Use pipefail so we still catch failures from the actual command.
set -o pipefail
eval "$*" 2>&1 | tee -a "$LOG_FILE"
EXIT_CODE=${PIPESTATUS[0]}

echo "" | tee -a "$LOG_FILE"
if [ $EXIT_CODE -eq 0 ]; then
  echo "=== $PHASE completed successfully at $(date) ===" | tee -a "$LOG_FILE"
else
  echo "=== $PHASE FAILED (exit $EXIT_CODE) at $(date) ===" | tee -a "$LOG_FILE"
fi
echo "Log saved to: $LOG_FILE" | tee -a "$LOG_FILE"

exit $EXIT_CODE
