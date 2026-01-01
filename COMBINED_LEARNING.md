# Combined Learning & Troubleshooting Guide

This document consolidates lessons learned, troubleshooting guides, and setup instructions from multiple source files.

## Table of Contents
1. [CI/CD & Testing Lessons Learned](#1-cicd--testing-lessons-learned)
2. [GCP & Workload Identity Federation Guide](#2-gcp--workload-identity-federation-guide)
3. [Lessons Learned: Roadmap App](#3-lessons-learned-roadmap-app)
4. [Lessons Learned: Golden Image & Roadtrip](#4-lessons-learned-golden-image--roadtrip)
5. [Troubleshooting: Context Analyzer](#5-troubleshooting-context-analyzer)
6. [Troubleshooting: Golden Image](#6-troubleshooting-golden-image)

---

## 1. CI/CD & Testing Lessons Learned
*(Source: `CI_CD_LESSONS_LEARNED.md`)*

#### 1. Docker Build Arguments and Secrets
**Issue**: Passing secrets as build arguments to `docker build` via shell commands is prone to errors due to quoting and shell expansion.
**Symptoms**: You might see obscure syntax errors in your build log like `docker: "build" requires 1 argument.` or empty secrets at runtime.
**Solution**: Use the official `docker/build-push-action`. It handles secret injection safely.

#### 2. GitHub Environments
**Issue**: Secrets defined in a specific GitHub Environment (e.g., `CI`) are not accessible unless the job explicitly references that environment.
**Solution**: Add the `environment` property to the job configuration.

#### 3. Java Version Compatibility
**Issue**: Tools like Karate 1.5.0+ require Java 17, while the project might be on Java 11.
**Solution**: Explicitly set the Java version in both the CI environment (`actions/setup-java`) and the Maven configuration.

#### 4. Testing with Restricted API Keys
**Issue**: Frontend API keys often have "Referrer Restrictions" which fail in direct API tests.
**Solution**: Add `Referer` headers in tests or avoid running backend tests with frontend-only keys.

#### 5. Headless Chrome Stability (UI Tests)
**Issue**: UI tests fail in headless CI due to race conditions.
**Solutions**: Use explicit waits (`waitFor`), robust selectors, and mock blocking functions like `window.alert`.

---

## 2. GCP & Workload Identity Federation Guide
*(Source: `GCP_GitHub_WIF_Guide.md`)*

### Secure CI/CD: Connecting GitHub Actions to Google Cloud

#### 1. Create a GitHub Repository
Start by creating a repository if you haven't already.

#### 2. Google Cloud Initial Setup
Set environment variables:
```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
```
Enable APIs: `iam`, `cloudresourcemanager`, `iamcredentials`, `artifactregistry`.

#### 3. Workload Identity Federation Setup
Create a Pool and Provider to trust GitHub's OIDC token. This eliminates the need for service account keys.

#### 4. Service Account & IAM
Create a Service Account and grant it `artifactregistry.writer`.
**Critical Step**: Allow GitHub repo to impersonate this SA using `roles/iam.workloadIdentityUser`.

#### 5. Artifact Registry Setup
Create a Docker repository in Artifact Registry.

#### 6. GitHub Actions Workflow
Create `.github/workflows/deploy.yaml` that uses `google-github-actions/auth` with the WIF provider.

#### 7. Common Deployment Errors
-   **PORT Error**: Don't set `PORT` manually; let Cloud Run inject it.
-   **Permission Denied**: Check IAM roles (Cloud Run Admin, Service Account User).
-   **Subject Issuer Mismatch**: Verify the `repository` attribute in WIF binding.

---

## 3. Lessons Learned: Roadmap App
*(Source: `LESSONS_LEARNED-Roadmap-App.md`)*

#### 1. Deployment Script Hanging
**Solution**: Remove output suppression (`&>/dev/null`) from `gcloud` commands to see auth prompts, and add an explicit `gcloud auth print-access-token` check.

#### 2. High Severity Security Vulnerabilities
**Solution**: Use `overrides` in `package.json` to force secure versions of nested dependencies like `nth-check`.

#### 3. CI Failure: "mvn: command not found"
**Solution**: Install `maven` in `gcp-startup-script.sh`.

#### 4. CI Failure: "driver config / start failed" (Chrome)
**Solution**: Install `google-chrome-stable` in the runner startup script.

---

## 4. Lessons Learned: Golden Image & Roadtrip
*(Source: `LESSONS_LEARNED-golden-image-Roadtrip.md`)*

*(Note: Supersedes Roadmap App lessons with additional findings)*

#### 5. Golden Image Build Hang (apt-get)
**Issue**: `build-image.sh` hangs at `apt-get install`.
**Solution**: Export `DEBIAN_FRONTEND=noninteractive` in `setup-image.sh`.

#### General Best Practice: Redeploying Runners
**Lesson**: Changes to startup scripts do NOT apply to running instances. You must using `deploy.sh` to recreate the MIG.

#### 6. Stuck Runners (Queueing Indefinitely)
**Causes**: Label mismatch (`self-hosted` vs `gcp-runner`) or deleted infrastructure.
**Solution**: Align labels in workflow and startup script; redeploy infrastructure.

---

## 5. Troubleshooting: Context Analyzer
*(Source: `troubleshooting-from-context-analyzer.md`)*

### CI/CD & Google Cloud Deployment
1.  **Artifact Registry Not Found**: Create the repo first.
2.  **Cloud Run Admin API Disabled**: Enable it.
3.  **Reserved Env Var (PORT)**: Do not set PORT in `gcloud run deploy`.
4.  **Resource not accessible (403)**: Use a PAT (`GH_PAT`) if `GITHUB_TOKEN` permissions are insufficient.
5.  **"gh: command not found"**: Install GitHub CLI in the runner.

### Local Development: Debugging "Blank Page of Death"
1.  **Default Port Trap**: Vite switching to 5174. Enforce `strictPort: true`.
2.  **20-Second Delay (IPv6)**: Force `host: '127.0.0.1'`.
3.  **Silent Crash (Import Errors)**: Run `npm run build` to detect static import failures.
4.  **React Crash**: Use a Global Error Boundary.
5.  **Nuclear Option**: Replace `main.jsx` with basic HTML to isolate the issue.

### GCP Self-Hosted Runners
-   **Invalid value for instanceTemplate**: Ensure Template is Global, not Regional.
-   **Push cannot contain secrets**: Remove hardcoded PATs.
-   **No space left on device**: Upgrade to 100GB disks.
-   **Could not fetch image resource**: Use `--image-family` instead of specific versions.
-   **Slow Performance**: Use Idle Timeout and increase MIG size > 1.

---

## 6. Troubleshooting: Golden Image
*(Source: `troubleshooting-golden-image.md`)*

### Optimization Techniques
**Golden Image Approach**: Pre-install Docker, Git, and pull images (like `node:20-alpine`) during the build phase to reduce cold start from 10m to <3m.

### Build / Deployment Issues
1.  **Runners Not Connecting**: If `setup-image.sh` fails, the image is broken. Check serial output logs.
2.  **gcloud Command Not Found**: Scripts should dynamic resolve `gcloud` path if installed locally.
3.  **Offline Runner Clutter**: Use `--ephemeral` flag for runners to auto-deregister after one job.

### Reference Scripts
*See original file for full `setup-image.sh`, `build-image.sh`, and `startup-script.sh` examples.*
