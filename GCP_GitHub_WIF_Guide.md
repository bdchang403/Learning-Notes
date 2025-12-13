# Secure CI/CD: Connecting GitHub Actions to Google Cloud with Workload Identity Federation

This guide provides a step-by-step walkthrough for setting up a secure deployment pipeline from GitHub to Google Cloud Platform (GCP) using Workload Identity Federation (WIF). WIF eliminates the need for long-lived service account keys, significantly improving security.

## Prerequisites

- A [GitHub](https://github.com) account.
- A [Google Cloud Platform](https://console.cloud.google.com) account with billing enabled.
- `gcloud` CLI installed (or use Cloud Shell).

---

## 1. Create a GitHub Repository

First, create the repository that will host your code and the GitHub Actions workflow.

1.  Log in to GitHub and click the **+** icon in the top-right corner, then select **New repository**.
2.  **Repository name**: Enter a name (e.g., `gcp-wif-demo`).
3.  **Description**: Optional.
4.  **Visibility**: Choose **Public** or **Private**.
5.  **Initialize this repository with**: Check **Add a README file**.
6.  Click **Create repository**.


img src="/home/bdchang/.gemini/antigravity/brain/114e2ee9-cace-49aa-8194-8528ee5ff82e/github_new_repo_ui.png" alt="Create New Repository" width="600"/>

Now that you have a repository, keep the **Repository URL** handy (e.g., `https://github.com/your-username/gcp-wif-demo`). We'll need the `username/repo` format later.

---

## 2. Google Cloud Initial Setup

In this section, we'll prepare your Google Cloud project. You can do this via the Cloud Console or the `gcloud` CLI. We'll use the CLI for precision, but you can verify everything in the Console.

### 2.1. Set Environment Variables
Open your terminal (or Cloud Shell) and set variables to make the commands easier to copy-paste.

```bash
export PROJECT_ID="your-project-id"  # Replace with your actual Project ID
export REGION="us-central1"
export REPO_NAME="gcp-wif-demo"      # The GitHub repo name
export USER_NAME="your-github-username"
```

### 2.2. Enable Required APIs
We need to enable the services for IAM, Workload Identity, and Artifact Registry.

```bash
gcloud services enable iam.googleapis.com \
    cloudresourcemanager.googleapis.com \
    iamcredentials.googleapis.com \
    artifactregistry.googleapis.com \
    --project="${PROJECT_ID}"
```

---

## 3. Workload Identity Federation Setup

This is the core security piece. We will create a "Pool" and a "Provider" that trusts GitHub's OIDC token.

### 3.1. Create a Workload Identity Pool
A pool organizes identity providers.

```bash
gcloud iam workload-identity-pools create "github-pool" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --display-name="GitHub Actions Pool"
```

### 3.2. Create a Workload Identity Provider
This tells GCP to trust tokens signed by `https://token.actions.githubusercontent.com`.

```bash
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com"
```

![Workload Identity Pool Creation](/home/bdchang/.gemini/antigravity/brain/114e2ee9-cace-49aa-8194-8528ee5ff82e/gcp_wif_pool_ui.png)
*(The screenshot above illustrates the Pool creation form in the Console, if you prefer using the UI.)*

---

## 4. Service Account & IAM

Now we need an actual Identity (Service Account) inside GCP that the GitHub runner will "impersonate".

### 4.1. Create Service Account

```bash
export SERVICE_ACCOUNT="github-actions-sa"

gcloud iam service-accounts create "${SERVICE_ACCOUNT}" \
  --project="${PROJECT_ID}" \
  --display-name="GitHub Actions Service Account"
```

### 4.2. specific Permissions
Grant the Service Account the ability to write to Artifact Registry (and any other permissions you need, like Cloud Run Admin).

```bash
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"
```



*(You can verify the roles in the IAM & Admin > IAM page in the Console found at https://console.cloud.google.com/iam-admin/iam)*


### 4.3. Allow GitHub to Impersonate the Service Account
This is the binding that links the WIF Provider to the Service Account. We strictly limit it to **your specific repository**.

```bash
gcloud iam service-accounts add-iam-policy-binding "${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/$(gcloud projects describe ${PROJECT_ID} --format='value(projectNumber)')/locations/global/workloadIdentityPools/github-pool/attribute.repository/${USER_NAME}/${REPO_NAME}"
```

> **Note**: The `member` string is where the security magic happens. It ensures ONLY the workflow in `${USER_NAME}/${REPO_NAME}` can assume this service account.

---

## 5. Artifact Registry Setup

We need a place to store our Docker images.

### 5.1. Create a Repository

```bash
export AR_REPO="my-docker-repo"

gcloud artifacts repositories create "${AR_REPO}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --repository-format=docker \
  --description="Docker repository for GitHub Actions"
```

![Artifact Registry Console](/home/bdchang/.gemini/antigravity/brain/114e2ee9-cace-49aa-8194-8528ee5ff82e/gcp_artifact_registry_ui.png)

---

## 6. GitHub Actions Workflow

Finally, let's create the workflow file in your GitHub repository.

### 6.1. Create the Workflow File
In your repository, create a file at `.github/workflows/deploy.yaml`.

```yaml
name: Build and Push to GCP

on:
  push:
    branches: [ "main" ]

env:
  PROJECT_ID: 'your-project-id' # UPDATE THIS
  REGION: 'us-central1'         # UPDATE THIS
  GAR_LOCATION: 'us-central1-docker.pkg.dev/your-project-id/my-docker-repo' # UPDATE THIS
  SERVICE_ACCOUNT: 'github-actions-sa@your-project-id.iam.gserviceaccount.com' # UPDATE THIS
  WORKLOAD_IDENTITY_PROVIDER: 'projects/123456789/locations/global/workloadIdentityPools/github-pool/providers/github-provider' # UPDATE THIS

jobs:
  build-push:
    runs-on: ubuntu-latest
    permissions:
      contents: 'read'
      id-token: 'write' # Required for Workload Identity Federation

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Google Auth
        id: auth
        uses: 'google-github-actions/auth@v2'
        with:
          workload_identity_provider: '${{ env.WORKLOAD_IDENTITY_PROVIDER }}'
          service_account: '${{ env.SERVICE_ACCOUNT }}'

      - name: Set up Cloud SDK
        uses: 'google-github-actions/setup-gcloud@v2'

      - name: Docker Auth
        run: |-
          gcloud auth configure-docker us-central1-docker.pkg.dev

      - name: Build and Push Container
        run: |-
          docker build -t "${{ env.GAR_LOCATION }}/my-app:${{ github.sha }}" .
          docker push "${{ env.GAR_LOCATION }}/my-app:${{ github.sha }}"

      # --- NEW: Deploy to Cloud Run ---
      - name: Deploy to Cloud Run
        id: deploy
        uses: google-github-actions/deploy-cloudrun@v2
        with:
          service: my-app-service
          region: ${{ env.REGION }}
          image: ${{ env.GAR_LOCATION }}/my-app:${{ github.sha }}
          flags: '--allow-unauthenticated' # For public access demo

### 6.2. How to find the `WORKLOAD_IDENTITY_PROVIDER` string?
You can run this command to get the full path:

```bash
gcloud iam workload-identity-pools providers describe "github-provider" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --format="value(name)"
```

Copy the output and paste it into `WORKLOAD_IDENTITY_PROVIDER` in the yaml above.

---

## 7. Kick-starting the Deployment

Now that everything is set up, it's time to run it!

1.  **Commit and Push**: Add your changes (`.github/workflows/deploy.yaml`) to the repository.
    ```bash
    git add .
    git commit -m "Setup CI/CD pipeline"
    git push origin main
    ```
2.  **View Actions**: Go to your GitHub repository -> click **Actions** tab.
3.  **Watch**: You should see a workflow running. Click on it to see the live logs.

---

## 8. Top 10 Troubleshooting Guide (First Deploy)

If your deployment fails, it's usually one of these common reasons.

| # | Error / Symptom | Solution |
| :--- | :--- | :--- |
| **1** | `Container failed to start. Failed to listen on PORT 8080` | **Missing Environment Variable**. Your app must listen on the port defined by the `$PORT` env var (default 8080). Hardcoding ports often fails. |
| **2** | `Permission 'run.services.create' denied` | **IAM Role Missing**. The Service Account (`github-actions-sa`) needs the **Cloud Run Admin** role. <br> Run: `gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SERVICE_ACCOUNT@..." --role="roles/run.admin"` |
| **3** | `Permission 'iam.serviceAccounts.actAs' denied` | **SA User Role Missing**. The Service Account needs to "act as" itself to launch the service. <br> Run: `gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SERVICE_ACCOUNT@..." --role="roles/iam.serviceAccountUser"` |
| **4** | `Subject issuer mismatch` | **WIF Typo**. The `attribute.repository` in your WIF binding doesn't match `Owner/Repo`. Check for case-sensitivity or typos. |
| **5** | `Permission 'artifactregistry.repositories.uploadArtifacts' denied` | **Artifact Registry Role Missing**. Ensure the SA has **Artifact Registry Writer**. |
| **6** | `The organization policy restricts unauthenticated access` | **Org Policy**. Your organization prevents public services. Remove the `--allow-unauthenticated` flag or ask an admin to change the Domain Restriction policy. |
| **7** | `Requested entity was not found` (Artifacts) | **Region Mismatch**. Did you create the Artifact Registry in `us-central1` but try to push to `us-east1`? Check environment variables. |
| **8** | `API 'run.googleapis.com' not enabled` | **Enable API**. You forgot to enable the Cloud Run API. <br> Run: `gcloud services enable run.googleapis.com` |
| **9** | `Invalid authentication credentials` | **GitHub Secrets**. If you stored values in Secrets, double-check for leading/trailing whitespace. |
| **10** | `COPY failed: file not found` | **Docker Context**. Your `Dockerfile` is trying to copy a file that isn't in the repository or is excluded by `.dockerignore`. |

---

## Conclusion
You have now set up a secure, keyless pipeline using Workload Identity Federation! 
- **GitHub** authenticates via OIDC.
- **GCP** trusts the GitHub token and exchanges it for a short-lived Service Account token.
- **GitHub Actions** uses that token to push images to **Artifact Registry** and deploy to **Cloud Run**.
