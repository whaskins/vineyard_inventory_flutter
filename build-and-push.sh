#!/bin/bash

set -e

# Configuration
ECR_REPO="283282846400.dkr.ecr.us-east-1.amazonaws.com/vineyard/dashboard"
REGION="us-east-1"
IMAGE_TAG=$(date +"%Y%m%d%H%M%S")

# Build the Flutter web app
echo "Building Flutter web app..."
flutter build web --release

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin 283282846400.dkr.ecr.us-east-1.amazonaws.com

# Build the Docker image for amd64 platform
echo "Building Docker image for amd64 platform..."
docker buildx build --platform linux/amd64 \
  -t $ECR_REPO:latest \
  -t $ECR_REPO:$DATE_TAG \
  --load .

# Push the images to ECR
echo "Pushing images to ECR..."
docker push $ECR_REPO:latest
docker push $ECR_REPO:$DATE_TAG

echo "Build and push completed successfully!"
echo "Images pushed:"
echo "  - $ECR_REPO:latest"
echo "  - $ECR_REPO:$DATE_TAG"