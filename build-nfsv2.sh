#!/bin/bash
# Build and Push NFSv2 Docker Image to GitLab Registry

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Reset terminal color on exit
trap 'tput sgr0' EXIT

echo -e "${BLUE}=========================================="
echo "Build and Push NFSv2 Image to GitLab"
echo "==========================================${NC}"
echo ""

# GitLab registry configuration
GITLAB_REGISTRY="registry.gitlab.com"
GITLAB_PROJECT="nsf-noirlab/gemini/rtsw/nfsv2-bootserver"
IMAGE_NAME="nfsv2"
IMAGE_TAG="TCS"
FULL_IMAGE_NAME="${GITLAB_REGISTRY}/${GITLAB_PROJECT}/${IMAGE_NAME}:${IMAGE_TAG}"

echo -e "${BLUE}Configuration:${NC}"
echo "  Registry:    ${GITLAB_REGISTRY}"
echo "  Project:     ${GITLAB_PROJECT}"
echo "  Image Tag:   ${GREEN}${IMAGE_TAG}${NC}"
echo "  Full Image:  ${FULL_IMAGE_NAME}"
echo ""

# Get the directory where script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Check if Dockerfile exists
if [ ! -f "Dockerfile" ]; then
    echo -e "${RED}Error: Dockerfile not found${NC}"
    exit 1
fi

# Check if source tarball exists
if [ ! -f "nfs-user-server_2.2beta47.orig.tar.gz" ]; then
    echo -e "${RED}Error: nfs-user-server_2.2beta47.orig.tar.gz not found${NC}"
    exit 1
fi

# Check if logged in to GitLab registry
echo -e "${YELLOW}Checking GitLab registry login...${NC}"
if ! cat ~/.docker/config.json 2>/dev/null | grep -q "${GITLAB_REGISTRY}"; then
    echo -e "${YELLOW}Not logged in to GitLab registry${NC}"
    echo ""
    echo "Please login to GitLab registry first:"
    echo "  docker login ${GITLAB_REGISTRY}"
    echo ""
    echo "Or use a personal access token:"
    echo "  docker login ${GITLAB_REGISTRY} -u <username> -p <token>"
    echo ""
    read -p "Do you want to login now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker login ${GITLAB_REGISTRY}
        if [ $? -ne 0 ]; then
            echo -e "${RED}✗ Login failed${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Aborted. Please login and try again.${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Already logged in${NC}"
fi
echo ""

# Build the image
echo -e "${YELLOW}Building Docker image...${NC}"
echo "  Dockerfile: Dockerfile"
echo "  Tag: ${FULL_IMAGE_NAME}"
echo ""
docker build -f Dockerfile -t ${FULL_IMAGE_NAME} .

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Build failed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Image built successfully${NC}"
echo ""

# Push to GitLab registry
echo -e "${YELLOW}Pushing to GitLab registry...${NC}"
docker push ${FULL_IMAGE_NAME}

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Push failed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Image pushed to ${IMAGE_TAG} tag${NC}"
echo ""

echo -e "${GREEN}=========================================="
echo "✅ Build and Push Complete!"
echo "==========================================${NC}"
echo ""
echo "Image pushed with tag:"
echo -e "  ${GREEN}${FULL_IMAGE_NAME}${NC}"
echo ""

