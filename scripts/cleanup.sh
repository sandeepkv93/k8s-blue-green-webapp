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
TARGET_ENV=${1}
FORCE=${2:-"false"}

echo -e "${BLUE}=== Blue-Green Cleanup Script ===${NC}"

# Validate input
if [ -z "$TARGET_ENV" ]; then
    echo -e "${RED}Error: Environment not specified${NC}"
    echo "Usage: $0 <blue|green> [force]"
    echo ""
    echo "Examples:"
    echo "  $0 blue        # Cleanup blue environment (with confirmation)"
    echo "  $0 green force # Cleanup green environment (no confirmation)"
    exit 1
fi

if [ "$TARGET_ENV" != "blue" ] && [ "$TARGET_ENV" != "green" ]; then
    echo -e "${RED}Error: Environment must be 'blue' or 'green'${NC}"
    exit 1
fi

echo "Target Environment: $TARGET_ENV"
echo "Namespace: $NAMESPACE"

# Function to get current active environment
get_active_environment() {
    kubectl get service backend-service -n $NAMESPACE -o jsonpath='{.spec.selector.environment}' 2>/dev/null || echo "unknown"
}

# Step 1: Safety checks
echo -e "\n${BLUE}Step 1: Safety checks${NC}"

ACTIVE_ENV=$(get_active_environment)
echo "Current active environment: $ACTIVE_ENV"

if [ "$ACTIVE_ENV" == "$TARGET_ENV" ]; then
    echo -e "${RED}✗ Cannot cleanup active environment${NC}"
    echo "The $TARGET_ENV environment is currently serving traffic!"
    echo ""
    echo "To cleanup $TARGET_ENV environment:"
    echo "1. First switch traffic to the other environment:"
    if [ "$TARGET_ENV" == "blue" ]; then
        echo "   ./scripts/switch-traffic.sh green blue"
    else
        echo "   ./scripts/switch-traffic.sh blue green"
    fi
    echo "2. Then run cleanup again"
    exit 1
fi

# Check if target environment exists
BACKEND_DEPLOYMENT=$(kubectl get deployment backend-$TARGET_ENV -n $NAMESPACE 2>/dev/null || echo "")
FRONTEND_DEPLOYMENT=$(kubectl get deployment frontend-$TARGET_ENV -n $NAMESPACE 2>/dev/null || echo "")

if [ -z "$BACKEND_DEPLOYMENT" ] && [ -z "$FRONTEND_DEPLOYMENT" ]; then
    echo -e "${YELLOW}⚠ $TARGET_ENV environment is not deployed${NC}"
    exit 0
fi

echo -e "${GREEN}✓ Safety checks passed${NC}"

# Step 2: Show what will be deleted
echo -e "\n${BLUE}Step 2: Resources to be deleted${NC}"

echo -e "${YELLOW}Deployments:${NC}"
kubectl get deployments -n $NAMESPACE -l environment=$TARGET_ENV

echo -e "\n${YELLOW}Pods:${NC}"
kubectl get pods -n $NAMESPACE -l environment=$TARGET_ENV

echo -e "\n${YELLOW}Services (environment-specific):${NC}"
kubectl get services -n $NAMESPACE -l environment=$TARGET_ENV

echo -e "\n${YELLOW}ReplicaSets:${NC}"
kubectl get replicasets -n $NAMESPACE -l environment=$TARGET_ENV

# Step 3: Confirmation
if [ "$FORCE" != "force" ]; then
    echo -e "\n${YELLOW}Step 3: Confirmation${NC}"
    echo -e "${RED}WARNING: This will permanently delete the $TARGET_ENV environment${NC}"
    echo "This action cannot be undone!"
    echo ""
    echo "Resources that will be deleted:"
    echo "- All pods in $TARGET_ENV environment"
    echo "- All deployments in $TARGET_ENV environment"
    echo "- Environment-specific services"
    echo "- Associated ReplicaSets"
    echo ""
    echo "Resources that will NOT be deleted:"
    echo "- Shared database and Redis"
    echo "- Active traffic routing services"
    echo "- ConfigMaps and Secrets"
    echo "- Persistent volumes"
    echo ""
    read -p "Type 'DELETE' to confirm deletion of $TARGET_ENV environment: " -r
    echo
    
    if [ "$REPLY" != "DELETE" ]; then
        echo "Cleanup cancelled."
        exit 0
    fi
fi

# Step 4: Perform cleanup
echo -e "\n${BLUE}Step 4: Cleaning up $TARGET_ENV environment${NC}"

# Delete deployments (this will also delete associated ReplicaSets and Pods)
echo -e "${YELLOW}Deleting deployments...${NC}"
if kubectl delete deployment -n $NAMESPACE -l environment=$TARGET_ENV; then
    echo -e "${GREEN}✓ Deployments deleted${NC}"
else
    echo -e "${RED}✗ Failed to delete some deployments${NC}"
fi

# Delete environment-specific services
echo -e "\n${YELLOW}Deleting environment-specific services...${NC}"
if kubectl delete service -n $NAMESPACE -l environment=$TARGET_ENV; then
    echo -e "${GREEN}✓ Environment-specific services deleted${NC}"
else
    echo -e "${YELLOW}⚠ No environment-specific services found or failed to delete${NC}"
fi

# Wait for pods to terminate
echo -e "\n${YELLOW}Waiting for pods to terminate...${NC}"
timeout=60
elapsed=0
while [ $elapsed -lt $timeout ]; do
    POD_COUNT=$(kubectl get pods -n $NAMESPACE -l environment=$TARGET_ENV --no-headers 2>/dev/null | wc -l)
    if [ "$POD_COUNT" -eq 0 ]; then
        echo -e "${GREEN}✓ All pods terminated${NC}"
        break
    fi
    
    echo "Waiting for $POD_COUNT pods to terminate... ($elapsed/$timeout seconds)"
    sleep 5
    elapsed=$((elapsed + 5))
done

if [ $elapsed -ge $timeout ]; then
    echo -e "${YELLOW}⚠ Timeout waiting for pods to terminate${NC}"
    echo "Remaining pods:"
    kubectl get pods -n $NAMESPACE -l environment=$TARGET_ENV
fi

# Step 5: Verify cleanup
echo -e "\n${BLUE}Step 5: Verifying cleanup${NC}"

REMAINING_DEPLOYMENTS=$(kubectl get deployments -n $NAMESPACE -l environment=$TARGET_ENV --no-headers 2>/dev/null | wc -l)
REMAINING_PODS=$(kubectl get pods -n $NAMESPACE -l environment=$TARGET_ENV --no-headers 2>/dev/null | wc -l)
REMAINING_SERVICES=$(kubectl get services -n $NAMESPACE -l environment=$TARGET_ENV --no-headers 2>/dev/null | wc -l)

echo "Cleanup verification:"
echo "  Remaining deployments: $REMAINING_DEPLOYMENTS"
echo "  Remaining pods: $REMAINING_PODS"
echo "  Remaining services: $REMAINING_SERVICES"

if [ "$REMAINING_DEPLOYMENTS" -eq 0 ] && [ "$REMAINING_PODS" -eq 0 ]; then
    echo -e "${GREEN}✓ Cleanup completed successfully${NC}"
    cleanup_success=true
else
    echo -e "${YELLOW}⚠ Some resources may still be terminating${NC}"
    cleanup_success=false
fi

# Step 6: Show current state
echo -e "\n${BLUE}Step 6: Current deployment state${NC}"

echo -e "${YELLOW}Active environment: $ACTIVE_ENV${NC}"

echo -e "\n${YELLOW}Remaining deployments:${NC}"
kubectl get deployments -n $NAMESPACE

echo -e "\n${YELLOW}All pods:${NC}"
kubectl get pods -n $NAMESPACE

echo -e "\n${YELLOW}All services:${NC}"
kubectl get services -n $NAMESPACE

# Summary and next steps
echo -e "\n${GREEN}=== Cleanup Summary ===${NC}"
if [ "$cleanup_success" = true ]; then
    echo -e "${GREEN}✓ $TARGET_ENV environment successfully cleaned up${NC}"
else
    echo -e "${YELLOW}⚠ $TARGET_ENV environment cleanup completed with warnings${NC}"
fi

echo -e "\n${YELLOW}Current state:${NC}"
echo "- Active environment: $ACTIVE_ENV"
echo "- Cleaned environment: $TARGET_ENV"
echo "- Shared resources: Preserved"

echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. To deploy a new version to $TARGET_ENV:"
echo "   ./scripts/deploy-blue-green.sh <new-version> $TARGET_ENV $ACTIVE_ENV"
echo ""
echo "2. To check overall system health:"
echo "   ./scripts/health-check.sh"
echo ""
echo "3. Access current application:"
echo "   http://blue-green-webapp.local"