# Troubleshooting & Optimization Guide

## Optimization Techniques

### Reducing Cold Start Times ("Golden Image" Approach)
To significantly reduce runner startup time (Cold Start) from ~10 minutes to < 3 minutes, follow the "Golden Image" strategy. This moves the heavy lifting (installations, downloads) from the *startup* phase to the *build* phase.

**1. The Problem**
- Standard startup scripts install Docker, Git, and GitHub Runner agents on *every* boot.
- They also pull Docker images (e.g., `node:20-alpine`) from scratch for every job.
- This creates a 5-10 minute delay before the runner is ready.

**2. The Solution: Golden Image**
Create a custom GCP Disk Image that has all dependencies pre-installed.

**Steps:**
1.  **Configure Setup Script (`gcp-runner/setup-image.sh`)**:
    - Install system dependencies (Docker, Git, jq, gh).
    - Download and extract the GitHub Runner tarball.
    - **Pre-pull Docker Images**: Run `docker pull node:20-alpine` (and others) so they are cached locally.
    - Clean up unique identifiers (`/etc/machine-id`, `.runner` config).

2.  **Build the Image (`gcp-runner/build-image.sh`)**:
    - Spawns a temporary VM.
    - Runs the setup script.
    - Snapshots the disk into a reusable image (e.g., `gh-runner-golden-image-v1`).

3.  **Deploy using the Image (`gcp-runner/deploy.sh`)**:
    - Update `deploy.sh` to use `--image-family=gh-runner-image` instead of the base Ubuntu image.
    - Update `startup-script.sh` to skip installations and only handle registration ("lightweight startup").

**3. Additional Performance Tweaks**
- **Use SSDs**: In `deploy.sh`, set `--boot-disk-type=pd-ssd`. This improves boot time and Docker I/O.
- **Idle Monitor**: Ensure runners persist for a set time (e.g., 10 mins) to handle consecutive jobs instantly ("Hot Start") before scaling down.

## Reference Code Samples (Sanitized)

### 1. Image Setup Script (`setup-image.sh`)
This script installs dependencies on the temporary VM before imaging.

```bash
#!/bin/bash
set -e

# 1. Install Dependencies
apt-get update
apt-get install -y docker.io git jq curl wget

# Ensure Docker is running (for pulls)
systemctl start docker
systemctl enable docker

# 2. Install GitHub Runner
mkdir -p /actions-runner && cd /actions-runner
curl -o actions-runner-linux-x64-2.311.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz
tar xzf ./actions-runner-linux-x64-2.311.0.tar.gz
./bin/installdependencies.sh

# 3. Pre-pull Docker Layers (Optimization)
# Pull the images your CI pipeline uses
docker pull node:20-alpine
docker pull nginx:alpine

# 4. Cleanup for Imaging
rm -f .runner .credentials
truncate -s 0 /etc/machine-id
```

### 2. Image Build Script (`build-image.sh`)
Automates the creation of the golden image.

```bash
#!/bin/bash
PROJECT_ID="YOUR_PROJECT_ID"
ZONE="us-central1-a"
IMAGE_NAME="gh-runner-golden-image-v1"

# 1. Create temporary builder VM
gcloud compute instances create gh-runner-builder \
    --project=$PROJECT_ID \
    --zone=$ZONE \
    --metadata-from-file=startup-script=./setup-image.sh \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud

# 2. Wait for setup (Monitor serial output manually or via script loop)
sleep 300```

## Build / Deployment Issues

### Runners Not Connecting (Golden Image Failure)
**Symptoms:**
- The deployment (`deploy.sh`) succeeds, but runners never appear in GitHub Settings.
- Validated via `gcloud compute instances list` that VMs are running.
- Validated via `gcloud compute instances get-serial-port-output` that the startup script failed or exited early.

**Cause:**
- If the **Golden Image setup script** (`setup-image.sh`) fails (e.g., missing `wget` or Docker not started), the image is created with a broken state.
- When the runner boots from this image, the "lightweight" startup script assumes dependencies exist, but they don't, leading to immediate failure.

**Solution:**
1.  **Check Setup Logs**: Run the build script and monitor the temporary VM's serial output to ensure `setup-image.sh` completed successfully ("Golden Image Setup Complete").
2.  **Robustify Setup**: Ensure `setup-image.sh` explicitly installs all tools (including `wget` for the runner download) and starts critical services like Docker (`systemctl start docker`) before attempting downstream actions.
3.  **Rebuild**: You MUST delete the old image and rebuild it for changes to `setup-image.sh` to take effect.

# 3. Stop and Create Image
gcloud compute instances stop gh-runner-builder --zone=$ZONE
gcloud compute images create $IMAGE_NAME \
    --source-disk=gh-runner-builder \
    --source-disk-zone=$ZONE \
    --family=gh-runner-image

# 4. Cleanup
gcloud compute instances delete gh-runner-builder --zone=$ZONE --quiet
```

### 3. Lightweight Startup Script (`startup-script.sh`)
Runs on the actual runners. Fast, because dependencies are already there.

```bash
#!/bin/bash
set -e

# 1. Configuration
# We use metadata to inject the PAT safely
GITHUB_REPO="YOUR_USERNAME/YOUR_REPO"
PAT=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/github_pat")

# 2. Get Token & Register
cd /actions-runner
REG_TOKEN=$(curl -s -X POST -H "Authorization: token ${PAT}" ... https://api.github.com/repos/${GITHUB_REPO}/actions/runners/registration-token | jq -r .token)

./config.sh --url https://github.com/${GITHUB_REPO} --token ${REG_TOKEN} --unattended --name "$(hostname)" --replace

# 3. Start Service
./svc.sh start

# 4. Trap Shutdown for Deregistration (Important!)
cleanup() {
   ./svc.sh stop
   # ... Fetch Remove Token ...
   ./config.sh remove --token "$REMOVE_TOKEN"
}
trap cleanup EXIT SIGINT SIGTERM
```

### gcloud Command Not Found (Path Issues)
**Symptoms:**
- Build or Deploy scripts fail with `gcloud: command not found`.
- Partial execution where some resource creation calls work (if hardcoded) but others properly using the variable fail.

**Cause:**
- The `gcloud` CLI is not in the system `$PATH`, which is common when the SDK is installed locally in the project directory (e.g., `./google-cloud-sdk/bin/gcloud`) rather than globally.

**Solution:**
- **Dynamic Path Resolution**: Update scripts (`build-image.sh`, `deploy.sh`) to detect and use the local binary if present.
  ```bash
  GCLOUD_BIN="gcloud"
  if [ -f "./google-cloud-sdk/bin/gcloud" ]; then
      GCLOUD_BIN="./google-cloud-sdk/bin/gcloud"
  fi
  # Use $GCLOUD_BIN instead of gcloud
  $GCLOUD_BIN compute instances list ...
  ```

### Offline Runner Clutter
**Symptoms:**
- GitHub "Runners" settings page is filled with hundreds of "Offline" runners.
- Requires manual cleanup.

**Cause:**
- Runners are destroyed (e.g., by MIG scaling down or preemption) without successfully running their deregistration cleanup scripts.
- Runners are not configured as "ephemeral", so GitHub expects them to reconnect.

**Solution:**
1.  **Use Ephemeral Runners**: Add the `--ephemeral` flag to your `config.sh` command in `startup-script.sh`. This instructs GitHub to automatically unregister the runner after it processes *one* job.
    ```bash
    # startup-script.sh
    ./config.sh ... --ephemeral --replace
    ```
2.  **Cleanup Script**: Use the GitHub API to bulk-delete offline runners if they accumulate. Since `gh` CLI might not be authenticated or available, a raw API script (Node.js/Curl) is reliable.

