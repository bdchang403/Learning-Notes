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
