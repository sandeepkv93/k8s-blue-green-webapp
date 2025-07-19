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
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo -e "${RED}=== Emergency Rollback Script ===${NC}"

# Function to get current active environment
get_active_environment() {
    kubectl get service backend-service -n $NAMESPACE -o jsonpath='{.spec.selector.environment}' 2>/dev/null || echo "unknown"
}

# Function to get previous environment from annotations
get_previous_environment() {
    kubectl get service backend-service -n $NAMESPACE -o jsonpath='{.metadata.annotations.blue-green\.deployment/previous-environment}' 2>/dev/null || echo "unknown"
}

# Step 1: Determine rollback target
echo -e "\n${BLUE}Step 1: Determining rollback target${NC}"

CURRENT_ENV=$(get_active_environment)
PREVIOUS_ENV=$(get_previous_environment)

echo "Current active environment: $CURRENT_ENV"
echo "Previous environment: $PREVIOUS_ENV"

if [ "$PREVIOUS_ENV" == "unknown" ] || [ "$PREVIOUS_ENV" == "" ]; then
    # Determine the other environment
    if [ "$CURRENT_ENV" == "blue" ]; then
        ROLLBACK_TARGET="green"
    elif [ "$CURRENT_ENV" == "green" ]; then
        ROLLBACK_TARGET="blue"
    else
        echo -e "${RED}✗ Cannot determine rollback target${NC}"
        exit 1
    fi
    echo "Auto-determined rollback target: $ROLLBACK_TARGET"
else
    ROLLBACK_TARGET=$PREVIOUS_ENV
fi

# Step 2: Validate rollback target
echo -e "\n${BLUE}Step 2: Validating rollback target${NC}"

# Check if rollback target environment is healthy
BACKEND_PODS=$(kubectl get pods -n $NAMESPACE -l app=backend,environment=$ROLLBACK_TARGET --no-headers 2>/dev/null | wc -l)
FRONTEND_PODS=$(kubectl get pods -n $NAMESPACE -l app=frontend,environment=$ROLLBACK_TARGET --no-headers 2>/dev/null | wc -l)

if [ "$BACKEND_PODS" -eq 0 ] || [ "$FRONTEND_PODS" -eq 0 ]; then
    echo -e "${RED}✗ Rollback target environment $ROLLBACK_TARGET has no running pods${NC}"
    echo "Backend pods: $BACKEND_PODS"
    echo "Frontend pods: $FRONTEND_PODS"
    echo ""
    echo "Available environments:"
    kubectl get deployments -n $NAMESPACE
    exit 1
fi

# Check health of rollback target
BACKEND_READY=$(kubectl get pods -n $NAMESPACE -l app=backend,environment=$ROLLBACK_TARGET --no-headers | grep "Running" | grep "1/1" | wc -l)
FRONTEND_READY=$(kubectl get pods -n $NAMESPACE -l app=frontend,environment=$ROLLBACK_TARGET --no-headers | grep "Running" | grep "1/1" | wc -l)

echo "Rollback target health:"
echo "  Backend pods ready: $BACKEND_READY/$BACKEND_PODS"
echo "  Frontend pods ready: $FRONTEND_READY/$FRONTEND_PODS"

if [ "$BACKEND_READY" -eq 0 ] || [ "$FRONTEND_READY" -eq 0 ]; then
    echo -e "${YELLOW}Warning: Not all pods in $ROLLBACK_TARGET environment are ready${NC}"
    read -p "Continue with rollback anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# Step 3: Emergency confirmation
echo -e "\n${RED}Step 3: EMERGENCY ROLLBACK CONFIRMATION${NC}"
echo -e "${YELLOW}This will immediately switch traffic:${NC}"
echo "  FROM: $CURRENT_ENV environment"
echo "  TO: $ROLLBACK_TARGET environment"
echo "  At: $TIMESTAMP"
echo ""
read -p "PROCEED WITH EMERGENCY ROLLBACK? (type 'YES' to confirm): " -r
echo

if [ "$REPLY" != "YES" ]; then
    echo "Rollback cancelled."
    exit 0
fi

# Step 4: Perform immediate rollback
echo -e "\n${RED}Step 4: Performing immediate rollback${NC}"

echo -e "${YELLOW}Rolling back backend service...${NC}"
kubectl patch service backend-service -n $NAMESPACE --type='merge' -p="{
    \"spec\": {
        \"selector\": {
            \"app\": \"backend\",
            \"environment\": \"$ROLLBACK_TARGET\"
        }
    },
    \"metadata\": {
        \"annotations\": {
            \"blue-green.deployment/active-environment\": \"$ROLLBACK_TARGET\",
            \"blue-green.deployment/rollback-timestamp\": \"$TIMESTAMP\",
            \"blue-green.deployment/rollback-from\": \"$CURRENT_ENV\",
            \"blue-green.deployment/rollback-reason\": \"emergency-rollback\"
        }
    }
}"

echo -e "${YELLOW}Rolling back frontend service...${NC}"
kubectl patch service frontend-service -n $NAMESPACE --type='merge' -p="{
    \"spec\": {
        \"selector\": {
            \"app\": \"frontend\",
            \"environment\": \"$ROLLBACK_TARGET\"
        }
    },
    \"metadata\": {
        \"annotations\": {
            \"blue-green.deployment/active-environment\": \"$ROLLBACK_TARGET\",
            \"blue-green.deployment/rollback-timestamp\": \"$TIMESTAMP\",
            \"blue-green.deployment/rollback-from\": \"$CURRENT_ENV\",
            \"blue-green.deployment/rollback-reason\": \"emergency-rollback\"
        }
    }
}"

# Step 5: Verify rollback
echo -e "\n${BLUE}Step 5: Verifying rollback${NC}"

# Wait a moment for changes to propagate
sleep 3

NEW_ACTIVE_ENV=$(get_active_environment)
if [ "$NEW_ACTIVE_ENV" == "$ROLLBACK_TARGET" ]; then
    echo -e "${GREEN}✓ Rollback successful${NC}"
    echo "Traffic is now pointing to $ROLLBACK_TARGET environment"
else
    echo -e "${RED}✗ Rollback verification failed${NC}"
    echo "Expected: $ROLLBACK_TARGET, Got: $NEW_ACTIVE_ENV"
fi

# Step 6: Quick health check
echo -e "\n${BLUE}Step 6: Post-rollback health check${NC}"

# Check service endpoints
echo "Checking service endpoints..."
kubectl get endpoints -n $NAMESPACE

# Check pod status
echo -e "\nCurrent pod status:"
kubectl get pods -n $NAMESPACE -l environment=$ROLLBACK_TARGET

echo -e "\n${GREEN}=== EMERGENCY ROLLBACK COMPLETED ===${NC}"
echo "✓ Traffic rolled back from $CURRENT_ENV to $ROLLBACK_TARGET"
echo "✓ Rollback timestamp: $TIMESTAMP"
echo ""
echo "IMMEDIATE ACTIONS REQUIRED:"
echo "1. Monitor application: http://blue-green-webapp.local"
echo "2. Check logs: kubectl logs -n $NAMESPACE -l environment=$ROLLBACK_TARGET -f"
echo "3. Verify application functionality"
echo "4. Investigate the issue that caused the rollback"
echo ""
echo "Access URLs:"
echo "- Main application: http://blue-green-webapp.local"
echo "- Active ($ROLLBACK_TARGET): http://$ROLLBACK_TARGET.blue-green-webapp.local"
echo "- Failed ($CURRENT_ENV): http://$CURRENT_ENV.blue-green-webapp.local"