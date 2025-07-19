#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="blue-green-webapp"
NEW_VERSION=${1:-"v1.1.0"}
TARGET_ENV=${2:-"green"}
SOURCE_ENV=${3:-"blue"}

echo -e "${BLUE}=== Blue-Green Deployment Script ===${NC}"
echo "Target Environment: $TARGET_ENV"
echo "Source Environment: $SOURCE_ENV"
echo "New Version: $NEW_VERSION"
echo "Namespace: $NAMESPACE"

# Function to check if deployment is ready
check_deployment_ready() {
    local deployment=$1
    local namespace=$2
    
    echo -e "${YELLOW}Waiting for deployment $deployment to be ready...${NC}"
    kubectl wait --for=condition=available deployment/$deployment -n $namespace --timeout=300s
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Deployment $deployment is ready${NC}"
        return 0
    else
        echo -e "${RED}✗ Deployment $deployment failed to become ready${NC}"
        return 1
    fi
}

# Function to check pod health
check_pod_health() {
    local app=$1
    local environment=$2
    local namespace=$3
    
    echo -e "${YELLOW}Checking health of $app pods in $environment environment...${NC}"
    
    # Get pod count
    POD_COUNT=$(kubectl get pods -n $namespace -l app=$app,environment=$environment --no-headers | wc -l)
    READY_COUNT=$(kubectl get pods -n $namespace -l app=$app,environment=$environment --no-headers | grep "Running" | grep "1/1\|2/2\|3/3" | wc -l)
    
    echo "Pods: $READY_COUNT/$POD_COUNT ready"
    
    if [ "$READY_COUNT" -eq "$POD_COUNT" ] && [ "$POD_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓ All $app pods are healthy${NC}"
        return 0
    else
        echo -e "${RED}✗ Not all $app pods are healthy${NC}"
        kubectl get pods -n $namespace -l app=$app,environment=$environment
        return 1
    fi
}

# Step 1: Build new Docker images
echo -e "\n${BLUE}Step 1: Building Docker images for version $NEW_VERSION${NC}"

# Build backend
echo "Building backend:$NEW_VERSION..."
cd backend
docker build -t backend:$NEW_VERSION .
cd ..

# Build frontend
echo "Building frontend:$NEW_VERSION..."
cd frontend
docker build -t frontend:$NEW_VERSION .
cd ..

echo -e "${GREEN}✓ Docker images built successfully${NC}"

# Step 2: Create namespace and shared resources
echo -e "\n${BLUE}Step 2: Setting up shared infrastructure${NC}"

kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/shared/

# Wait for database to be ready
check_deployment_ready "postgres" $NAMESPACE || exit 1

# Step 3: Deploy to target environment
echo -e "\n${BLUE}Step 3: Deploying to $TARGET_ENV environment${NC}"

# Update image versions in target environment deployments
sed -i.bak "s|image: backend:.*|image: backend:$NEW_VERSION|g" k8s/$TARGET_ENV/backend-deployment.yaml
sed -i.bak "s|image: frontend:.*|image: frontend:$NEW_VERSION|g" k8s/$TARGET_ENV/frontend-deployment.yaml
sed -i.bak "s|value: \"v.*\"|value: \"$NEW_VERSION\"|g" k8s/$TARGET_ENV/backend-deployment.yaml
sed -i.bak "s|value: 'v.*'|value: '$NEW_VERSION'|g" k8s/$TARGET_ENV/frontend-deployment.yaml

# Apply target environment deployments
kubectl apply -f k8s/$TARGET_ENV/

# Step 4: Wait for target environment to be ready
echo -e "\n${BLUE}Step 4: Waiting for $TARGET_ENV environment to be ready${NC}"

check_deployment_ready "backend-$TARGET_ENV" $NAMESPACE || exit 1
check_deployment_ready "frontend-$TARGET_ENV" $NAMESPACE || exit 1

# Step 5: Health checks
echo -e "\n${BLUE}Step 5: Performing health checks${NC}"

check_pod_health "backend" $TARGET_ENV $NAMESPACE || exit 1
check_pod_health "frontend" $TARGET_ENV $NAMESPACE || exit 1

# Step 6: Run application-specific tests on target environment
echo -e "\n${BLUE}Step 6: Running application tests on $TARGET_ENV environment${NC}"

# Test backend health endpoint directly
BACKEND_POD=$(kubectl get pods -n $NAMESPACE -l app=backend,environment=$TARGET_ENV -o jsonpath='{.items[0].metadata.name}')
echo "Testing backend health on pod $BACKEND_POD..."

kubectl exec -n $NAMESPACE $BACKEND_POD -- curl -f http://localhost:8080/health || {
    echo -e "${RED}✗ Backend health check failed${NC}"
    exit 1
}

echo -e "${GREEN}✓ All tests passed on $TARGET_ENV environment${NC}"

# Step 7: Prompt for traffic switch
echo -e "\n${YELLOW}Step 7: Ready to switch traffic to $TARGET_ENV environment${NC}"
echo "Current active environment: $SOURCE_ENV"
echo "Target environment: $TARGET_ENV"
echo "New version: $NEW_VERSION"
echo ""
read -p "Do you want to switch traffic now? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Switching traffic to $TARGET_ENV environment...${NC}"
    ./scripts/switch-traffic.sh $TARGET_ENV $SOURCE_ENV
else
    echo -e "${YELLOW}Traffic switch skipped. To switch traffic later, run:${NC}"
    echo "./scripts/switch-traffic.sh $TARGET_ENV $SOURCE_ENV"
fi

echo -e "\n${GREEN}=== Blue-Green Deployment Completed ===${NC}"
echo "✓ New version $NEW_VERSION deployed to $TARGET_ENV environment"
echo "✓ All health checks passed"
echo ""
echo "Access URLs:"
echo "- Main application: http://blue-green-webapp.local"
echo "- Blue environment: http://blue.blue-green-webapp.local"
echo "- Green environment: http://green.blue-green-webapp.local"
echo ""
echo "Monitoring commands:"
echo "- kubectl get pods -n $NAMESPACE -l environment=$TARGET_ENV"
echo "- kubectl logs -n $NAMESPACE -l app=backend,environment=$TARGET_ENV"
echo "- kubectl get services -n $NAMESPACE"