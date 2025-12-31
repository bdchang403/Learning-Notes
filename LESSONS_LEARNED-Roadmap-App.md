# CI/CD & GCP Runner Helper Guide

This document summarizes the issues encountered while setting up GCP self-hosted runners and the implementation of a secure CI/CD pipeline.

## 1. Deployment Script Hanging
**Issue**: The `gcp-runner-deploy.sh` script appeared to hang indefinitely at the "Cleaning up existing resources..." step.
**Cause**: The `gcloud` command was waiting for user authentication or input, but the output was redirected to `/dev/null` (e.g., `&>/dev/null`), hiding the prompt.
**Solution**:
1.  **Remove output suppression**: Removed `&>/dev/null` to see errors.
2.  **Explicit Auth Check**: Added a pre-check to ensure `gcloud` is authenticated before running commands.
```bash
if ! gcloud auth print-access-token &>/dev/null; then
    echo "Error: gcloud not authenticated..."
    exit 1
fi
```

## 2. High Severity Security Vulnerabilities
**Issue**: `npm audit` reported multiple High severity vulnerabilities in nested dependencies (e.g., `nth-check`, `postcss`, `node-fetch`).
**Cause**: Deeply nested dependencies (transitive dependencies) used by `react-scripts` or other libraries were outdated.
**Solution**: Used `overrides` in `package.json` to force the package manager to use secure versions of these specific libraries throughout the dependency tree.
```json
"overrides": {
  "nth-check": "^2.0.1",
  "postcss": "^8.4.31",
  "node-fetch": "^2.6.7"
}
```

## 3. CI Failure: "mvn: command not found"
**Issue**: Within the self-hosted runner, the CI job failed when trying to run tests.
**Cause**: The runner VM image (Ubuntu) does not come with Maven pre-installed, and the previous `startup-script` only installed Docker and Git.
**Solution**: Updated `scripts/gcp-startup-script.sh` to install `maven` via `apt-get`.
```bash
apt-get install -y docker.io git jq curl maven
```
*Note: Runners must be re-deployed (instance recreated) for startup script changes to take effect.*

## 4. CI Failure: "driver config / start failed" (Chrome)
**Issue**: UI tests failed with `driver config / start failed` and options showing `type=chrome`.
**Cause**: The runner environment did not have Google Chrome installed, which is required for browser-based tests (even in headless mode).
**Solution**: Updated `scripts/gcp-startup-script.sh` to add the Google Chrome repository and install `google-chrome-stable`.
```bash
echo "Installing Google Chrome..."
wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add -
echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list
apt-get update
apt-get install -y google-chrome-stable
```

## General Best Practice: Redeploying Runners
**Lesson**: When modifying `gcp-startup-script.sh`, changes do **not** apply to existing running instances.
**Procedure**: You must always re-run the deployment script (`./scripts/gcp-runner-deploy.sh`). This script handles the lifecycle:
1.  Deletes the existing Managed Instance Group (MIG).
2.  Deletes the old Instance Template.
3.  Creates a new Template with the updated startup script.
4.  Creates a new MIG, which provisions fresh VMs.
