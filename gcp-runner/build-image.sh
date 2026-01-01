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
sleep 300

# 3. Stop and Create Image
gcloud compute instances stop gh-runner-builder --zone=$ZONE
gcloud compute images create $IMAGE_NAME \
    --source-disk=gh-runner-builder \
    --source-disk-zone=$ZONE \
    --family=gh-runner-image

# 4. Cleanup
gcloud compute instances delete gh-runner-builder --zone=$ZONE --quiet
