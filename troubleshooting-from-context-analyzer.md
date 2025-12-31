# Troubleshooting Guide

This document captures common errors and solutions encountered during the setup, development, and deployment of the Context Analyzer application.

## CI/CD & Google Cloud Deployment

### 1. Artifact Registry Repository Not Found
**Error:**
```
name unknown: Repository "context-checker-repo" not found
```
**Cause:**
The target Artifact Registry repository does not exist in the specified Google Cloud Project. Docker cannot push images to a missing repo.

**Solution:**
Create the repository using the `gcloud` CLI:
```bash
gcloud artifacts repositories create context-checker-repo \
    --project=<PROJECT_ID> \
    --repository-format=docker \
    --location=us-central1 \
    --description="Docker repository for Context Analyzer"
```

### 2. Cloud Run Admin API Disabled
**Error:**
```
ERROR: (gcloud.run.deploy) PERMISSION_DENIED: Cloud Run Admin API has not been used in project ... before or it is disabled.
```
**Cause:**
The necessary API was not enabled on the GCP project.

**Solution:**
Enable the API:
```bash
gcloud services enable run.googleapis.com --project=<PROJECT_ID>
```

### 3. Reserved Environment Variable (PORT)
**Error:**
```
ERROR: (gcloud.run.deploy) spec.template.spec.containers[0].env: The following reserved env names were provided: PORT. These values are automatically set by the system.
```
**Cause:**
Attempting to explicitly set the `PORT` environment variable in the `gcloud run deploy` command or GitHub Actions workflow. Cloud Run automatically injects this variable, and manual assignment conflicts with the system.

**Solution:**
Remove `PORT` from the `env_vars` section of your GitHub Actions workflow. Ensure your application listens on the port provided by the `PORT` env var (or defaults to one), but do not try to set it during deployment.

### 4. GitHub Actions Authentication
**Issue:**
Need to authenticate GitHub Actions with Google Cloud securely without hardcoding JSON keys in the repo code.

**Solution:**
Use **Workload Identity Federation (WIF)** or a **Service Account Key** stored as a GitHub Secret (`GCP_CREDENTIALS`).
The `google-github-actions/auth` action supports both via the `credentials_json` input.

### 5. YAML Syntax Errors in Workflow
**Error:**
YAML validation failure due to duplicate keys (e.g., `flags` defined twice).

**Solution:**
Carefully review YAML indentation and ensure keys are unique within their parent scope. Use a linter or IDE validation to catch these before pushing.

### 6. "Resource not accessible by integration" (403 Error)
**Error:**
```
HTTP 403: Resource not accessible by integration
```
**Cause:**
The default `GITHUB_TOKEN` used in GitHub Actions does not have permissions to modify repository settings (like the "website" URL), even with `contents: write` permissions.

**Solution:**
1.  Create a **Personal Access Token (PAT)** in GitHub Developer Settings with `repo` scope.
2.  Add this token as a repository secret named `GH_PAT`.
3.  Update the workflow to use `${{ secrets.GH_PAT }}` instead of `${{ secrets.GITHUB_TOKEN }}`.

### 7. "gh: command not found"
**Error:**
```
/actions-runner/.../script.sh: line 1: gh: command not found
```
**Cause:**
You are using a self-hosted runner which does not have the GitHub CLI (`gh`) installed by default (unlike GitHub-hosted runners).

**Solution:**
Install the GitHub CLI in your runner's startup script.
- **Fix**: The `startup-script.sh` has been updated to install `gh` via `apt`.
- **Action**: Redeploy your runners to pick up the changes.

## Local Development: Debugging "Blank Page of Death"

A summary of lessons learned from debugging the Context-Checking Tool. Use this guide when the app server starts but the browser shows a white screen or fails to load.

### The 4-Step Troubleshooting Protocol

#### 1. The "Default Port" Trap (Port Drift)
**Symptom**: App opens on port `5174` instead of `5173`. Bookmarks break.
**Cause**: The default port was occupied (zombie process), so Vite incremented the port.
**Fix**: Enforce strict port in `vite.config.js`.

```javascript
// vite.config.js
export default defineConfig({
  server: {
    port: 5173,
    strictPort: true, // Fail if 5173 is busy (prevents drift)
  }
})
```

#### 2. The 20-Second Delay (IPv6 Timeout)
**Symptom**: App loads... eventually. Or times out completely (Blank Page).
**Cause**: Node.js/Linux often tries to resolve `localhost` via IPv6 (`::1`) first. If strict IPv6 isn't configured correctly, it hangs for 20s before falling back to IPv4.
**Fix**: Force IPv4 host binding.

```javascript
// vite.config.js
server: {
  host: '127.0.0.1', // Bypasses DNS resolution lag
}
```

#### 3. The "Silent Crash" (Import Errors)
**Symptom**: Instant white screen. Error Boundary does **NOT** show.
**Cause**: Static import errors (e.g., typos in `import { Typo } from 'lib'`).
**Why**: Static imports are evaluated *before* any code runs. If they fail, the browser script crashes entirely before React mounts.
**Detection**:
- **Do not inspect browser console** (it can be misleadingly empty if the script file 404s or fails to parse).
- **Run `npm run build`**. The compiler will catch these errors immediately even if the dev server swallows them.

```bash
npm run build
# Output: "Alertoctagon" is not exported by "lucide-react"
```

#### 4. The "React Crash" (Runtime Errors)
**Symptom**: White screen. Console has red stack traces.
**Cause**: Code logic error inside a component.
**Fix**: Wrap your app in a global Error Boundary in `main.jsx` to see the error on-screen.

```javascript
// src/main.jsx
class ErrorBoundary extends React.Component {
  componentDidCatch(error) { console.error(error); }
  render() {
    if (this.state.hasError) return <h1>Something went wrong</h1>;
    return this.props.children;
  }
}
```

### The "Nuclear Option": Vanilla JS Isolation
If you are unsure if the problem is the Code, the Server, or the Browser:
1. **Delete/Rename** `src/main.jsx`.
2. **Create a new `src/main.jsx`** with only:
   ```javascript
   document.body.innerHTML = "<h1>IT WORKS</h1>";
   ```
3. **Test**.
   - If it works: Your React app is broken (Outcome 3 or 4).
   - If it fails: Your Server/Environment is broken (Outcome 1 or 2).

## GCP Self-Hosted Runners

A guide to setting up and troubleshooting self-hosted GitHub Runners on Google Cloud Platform.

### 1. Setup & Deployment (The "Easy" Way)
We have automated the deployment using scripts in the `gcp-runner/` directory.

**Steps:**
1.  **Preparation**: Install `gcloud` SDK and authenticate (`gcloud auth login`).
2.  **Configuration**: Create a `.env` file in `gcp-runner/` to store your GitHub Personal Access Token (PAT).
    ```bash
    # gcp-runner/.env
    GITHUB_PAT=ghp_your_token_here
    ```
    *Note: Using `.env` prevents your secret token from being logged in terminal history or committed inadvertently.*
3.  **Deploy**: Run the deployment script.
    ```bash
    cd gcp-runner
    ./deploy.sh
    ```

### 2. Common Errors

#### "Invalid value for field 'resource.instanceTemplate'"
**Error:**
```
ERROR: (gcloud.compute.instance-groups.managed.create) Could not fetch resource:
 - Invalid value for field 'resource.instanceTemplate': ... does not exist.
```
**Cause:**
Scope Mismatch. The Instance Template was created as a **Regional** resource (using `--region=us-central1`), but the Managed Instance Group (MIG) creation command looked for a **Global** template by default.

**Solution:**
Ensure the Instance Template is created as a Global resource.
- **Fix**: Remove the `--region` flag from the `gcloud compute instance-templates create` command.
- **Status**: This has been fixed in the `deploy.sh` script in the repository. If you see this error, ensure you are using the latest version of the script.

#### "Push cannot contain secrets" (GitHub Push Protection)
**Error:**
```
remote: - GITHUB PUSH PROTECTION
remote: Push cannot contain secrets
```
**Cause:**
You attempted to commit a file (like `deploy.sh`) that contained a hardcoded GitHub PAT.

**Solution:**
1.  **Never hardcode secrets**. Use environment variables or prompt for input.
2.  **Remove the secret**: Delete the token from the file.
3.  **Amend the commit**:
    ```bash
    git add deploy.sh
    git commit --amend --no-edit
    git commit --amend --no-edit
    git push --force-with-lease
    ```

#### "ENOSPC: no space left on device"
**Error:**
```
npm warn tar TAR_ENTRY_ERROR ENOSPC: no space left on device
```
**Cause:**
The default Free Tier disk (30GB standard) is too small for Docker images, swap files, and large `node_modules`.

**Solution:**
Upgrade the infrastructure to use a larger disk.
- **Fix**: The `deploy.sh` script has been updated to use **100GB pd-balanced (SSD)** disks.
- **Action**: Redeploy your runners using the updated script.

#### "The resource ... already exists"
**Error:**
```
ERROR: (gcloud.compute.instance-templates.create) Could not fetch resource:
 - The resource '.../gh-runner-template' already exists
```
**Cause:**
You are re-running an older version of the `deploy.sh` script that does not handle existing resources. The script attempts to create resources that are already there (preventing updates).

**Solution:**
Use the latest `deploy.sh` which includes auto-cleanup logic.
- **Fix**: The updated script checks for and deletes existing MIGs/Templates before creating new ones.
- **Action**: `git pull origin main` and re-run `./deploy.sh`.

#### "Could not fetch image resource"
**Error:**
```
ERROR: (gcloud.compute.instance-templates.create) Could not fetch image resource:
 - The resource 'projects/ubuntu-os-cloud/global/images/ubuntu-2204-jammy-v20231026' was not found
```
**Cause:**
The specific Ubuntu image version hardcoded in the script has been deprecated or deleted by Google Cloud.

**Solution:**
Use an **Image Family** instead of a specific version.
- **Fix**: The `deploy.sh` script has been updated to use `--image-family=ubuntu-2204-lts`. This ensures it always pulls the latest valid LTS image.
- **Action**: Update your script and redeploy.

#### "bash: ./deploy.sh: Permission denied"
**Error:**
```
bash: ./deploy.sh: Permission denied
```
**Cause:**
The scripts lost their executable permission, possibly due to a `git reset` or file transfer.

**Solution:**
Make the scripts executable.
- **Fix**: Run `chmod +x deploy.sh startup-script.sh`.

#### Slow Performance / Queuing
**Symptom:**
Validating or deploying seems slow, or jobs are waiting in queue.

**Cause:**
1.  **Cold Boot**: If you are using true "Ephemeral" mode, every job waits ~2 mins for a VM to boot.
2.  **MIG Size**: If size=1, only one job can run at a time.

**Solution:**
We have optimized the architecture to handle this:
1.  **Idle Timeout**: Runners now stay active for **10 minutes** after a job. This allows consecutive jobs to run instantly (0 latency) and leverage Docker layer caching.
2.  **Concurrency**: The Managed Instance Group (MIG) size is set to **2**, allowing 2 parallel jobs (or overlapping workflows).
- **Action**: Ensure you have deployed the latest version of `gcp-runner/deploy.sh` and `startup-script.sh`.

## Reference: Example Scripts

Below are the **sanitized** versions of the deployment scripts used in this solution. You can copy these, but remember to replace placeholders like `YOUR_PROJECT_ID` (though the script fetches it automatically) or repo names if you adaptation them.

### 1. deploy.sh
```bash
#!/bin/bash
# Deploy GCP GitHub Runner Infrastructure (Standard Tier + Persistence)

# Configuration
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
ZONE="us-central1-a"
TEMPLATE_NAME="gh-runner-template"
MIG_NAME="gh-runner-mig"
REPO_OWNER="<YOUR_GITHUB_USERNAME>"
REPO_NAME="<YOUR_REPO_NAME>"

# Load from .env if it exists
if [ -f .env ]; then
    export $(cat .env | xargs)
fi

# Check if GITHUB_PAT is set, otherwise prompt
if [ -z "$GITHUB_PAT" ]; then
    read -s -p "Enter GitHub PAT: " GITHUB_PAT
    echo ""
fi

echo "Deploying to Project: $PROJECT_ID"

# 0. Cleanup Existing Resources (to allow upgrades/re-runs)
echo "Cleaning up existing resources..."
# Delete MIG if it exists
if gcloud compute instance-groups managed describe $MIG_NAME --zone=$ZONE --project=$PROJECT_ID &>/dev/null; then
    echo "Deleting existing MIG: $MIG_NAME"
    gcloud compute instance-groups managed delete $MIG_NAME --zone=$ZONE --project=$PROJECT_ID --quiet
fi

# Delete Instance Template if it exists (Global)
if gcloud compute instance-templates describe $TEMPLATE_NAME --project=$PROJECT_ID &>/dev/null; then
    echo "Deleting existing Instance Template: $TEMPLATE_NAME"
    gcloud compute instance-templates delete $TEMPLATE_NAME --project=$PROJECT_ID --quiet
fi

# 1. Create Instance Template
echo "Creating Instance Template..."
gcloud compute instance-templates create $TEMPLATE_NAME \
    --project=$PROJECT_ID \
    --machine-type=e2-standard-4 \
    --network-interface=network-tier=PREMIUM,network=default,address= \
    --metadata-from-file=startup-script=./startup-script.sh \
    --metadata=github_pat=$GITHUB_PAT \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --service-account=default \
    --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
    --tags=http-server,https-server \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud \
    --boot-disk-size=100GB \
    --boot-disk-type=pd-balanced \
    --boot-disk-device-name=$TEMPLATE_NAME

# 2. Create Managed Instance Group (MIG)
echo "Creating Managed Instance Group..."
gcloud compute instance-groups managed create $MIG_NAME \
    --project=$PROJECT_ID \
    --base-instance-name=gh-runner \
    --template=$TEMPLATE_NAME \
    --size=2 \
    --zone=$ZONE

echo "Deployment Complete."
```

### 2. startup-script.sh
```bash
#!/bin/bash
# GCP GitHub Runner Startup Script
# Optimized for e2-standard-4 (4 vCPU, 16 GB RAM) with Idle Timeout

set -e

# --- 1. Swap Configuration ---
echo "Setting up Swap..."
# Create 4GB swap file
fallocate -l 4G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=4096
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
sysctl vm.swappiness=60
echo 'vm.swappiness=60' >> /etc/sysctl.conf

# --- 2. Install Dependencies ---
echo "Installing Docker, Git, and GitHub CLI..."
apt-get update
apt-get install -y docker.io git jq curl

# Install gh CLI
mkdir -p -m 755 /etc/apt/keyrings
wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
apt-get update
apt-get install -y gh

systemctl enable --now docker

# --- 3. Install GitHub Runner ---
echo "Installing GitHub Runner..."
mkdir /actions-runner && cd /actions-runner
curl -o actions-runner-linux-x64-2.311.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz
tar xzf ./actions-runner-linux-x64-2.311.0.tar.gz

# --- 4. Configuration Variables ---
GITHUB_REPO="<YOUR_GITHUB_USERNAME>/<YOUR_REPO_NAME>"
REPO_URL="https://github.com/${GITHUB_REPO}"
# PAT fetched from Instance Metadata
PAT=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/github_pat")

if [ -z "$PAT" ]; then
  echo "Error: github_pat metadata not found."
  exit 1
fi

# --- 5. Get Registration Token ---
echo "Fetching Registration Token..."
REG_TOKEN=$(curl -s -X POST -H "Authorization: token ${PAT}" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/${GITHUB_REPO}/actions/runners/registration-token | jq -r .token)

if [ "$REG_TOKEN" == "null" ]; then
    echo "Failed to get registration token. Check PAT permissions."
    exit 1
fi

# --- 6. Configure & Run (Persistent with Idle Timeout) ---
echo "Configuring Runner..."
export RUNNER_ALLOW_RUNASROOT=1
./config.sh --url ${REPO_URL} --token ${REG_TOKEN} --unattended --name "$(hostname)" --labels "gcp-micro"

echo "Installing Runner as Service..."
./svc.sh install
./svc.sh start

# --- 7. Idle Shutdown Monitor ---
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
    shutdown -h now
    break
  fi
done
```
