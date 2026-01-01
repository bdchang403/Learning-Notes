#!/bin/bash
set -e

# --- 1. Configuration Variables ---
GITHUB_REPO="YOUR_USERNAME/YOUR_REPO"
REPO_URL="https://github.com/${GITHUB_REPO}"

# PAT fetched from Instance Metadata
PAT=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/github_pat")

if [ -z "$PAT" ]; then
  echo "Error: github_pat metadata not found."
  exit 1
fi

# --- 2. Get Registration Token ---
cd /actions-runner
echo "Fetching Registration Token..."
REG_TOKEN=$(curl -s -X POST -H "Authorization: token ${PAT}" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/${GITHUB_REPO}/actions/runners/registration-token | jq -r .token)

if [ "$REG_TOKEN" == "null" ]; then
    echo "Failed to get registration token. Check PAT permissions."
    exit 1
fi

# --- 3. Configure & Run (Persistent with Idle Timeout) ---
echo "Configuring Runner..."
export RUNNER_ALLOW_RUNASROOT=1
# Add --ephemeral if you want to ensure clean state for every job (requires restart logic or auto-scaling adaptation)
./config.sh --url ${REPO_URL} --token ${REG_TOKEN} --unattended --name "$(hostname)" --replace --labels "gcp-golden"

echo "Installing Runner as Service..."
./svc.sh install
./svc.sh start

# --- 4. Idle Shutdown Monitor ---
# Monitor for 'Runner.Worker' process which indicates an active job.
# If no job runs for IDLE_TIMEOUT seconds, shut down.
IDLE_TIMEOUT=600 # 10 minutes
CHECK_INTERVAL=30
IDLE_TIMER=0

echo "Starting Idle Monitor (Timeout: ${IDLE_TIMEOUT}s)..."

while true; do
  sleep $CHECK_INTERVAL
  
  # Check if Runner.Worker is running (indicates active job)
  if pgrep -f "Runner.Worker" > /dev/null; then
    echo "Job in progress. Resetting idle timer."
    IDLE_TIMER=0
  else
    IDLE_TIMER=$((IDLE_TIMER + CHECK_INTERVAL))
    echo "Runner idle for ${IDLE_TIMER}s..."
  fi

  if [ $IDLE_TIMER -ge $IDLE_TIMEOUT ]; then
    echo "Idle timeout reached (${IDLE_TIMEOUT}s). Shutting down..."
    # Deregister before shutdown usually handled by trap, but explicit removal is good hygiene if service stopped
    ./svc.sh stop
    ./config.sh remove --token "${REG_TOKEN}" # Note: token might be expired, ideal to fetch removal token
    shutdown -h now
    break
  fi
done
