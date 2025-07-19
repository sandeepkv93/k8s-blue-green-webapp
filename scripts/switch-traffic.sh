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
TARGET_ENV=${1:-"green"}
SOURCE_ENV=${2:-"blue"}
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo -e "${BLUE}=== Traffic Switching Script ===${NC}"
echo "Switching FROM: $SOURCE_ENV"
echo "Switching TO: $TARGET_ENV"
echo "Namespace: $NAMESPACE"
echo "Timestamp: $TIMESTAMP"

# Function to get current active environment
get_active_environment() {
    kubectl get service backend-service -n $NAMESPACE -o jsonpath='{.spec.selector.environment}' 2>/dev/null || echo "unknown"
}

# Function to update service selector
update_service_selector() {
    local service_name=$1
    local target_env=$2
    
    echo -e "${YELLOW}Updating $service_name to point to $target_env environment...${NC}"
    
    # Update the selector and annotations
    kubectl patch service $service_name -n $NAMESPACE --type='merge' -p="{
        \"spec\": {
            \"selector\": {
                \"app\": \"${service_name%%-service}\",
                \"environment\": \"$target_env\"
            }
        },
        \"metadata\": {
            \"annotations\": {
                \"blue-green.deployment/active-environment\": \"$target_env\",
                \"blue-green.deployment/last-switch\": \"$TIMESTAMP\",
                \"blue-green.deployment/previous-environment\": \"$SOURCE_ENV\"
            }
        }
    }"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $service_name updated successfully${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to update $service_name${NC}"
        return 1
    fi
}

# Function to verify traffic switch
verify_traffic_switch() {
    local target_env=$1
    local max_attempts=30
    local attempt=1
    
    echo -e "${YELLOW}Verifying traffic switch to $target_env environment...${NC}"
    
    while [ $attempt -le $max_attempts ]; do
        current_env=$(get_active_environment)
        
        if [ "$current_env" == "$target_env" ]; then
            echo -e "${GREEN}✓ Traffic successfully switched to $target_env environment${NC}"
            
            # Additional verification: check if pods are receiving traffic
            echo "Verifying pod endpoints..."
            kubectl get endpoints backend-service -n $NAMESPACE
            return 0
        fi
        
        echo "Attempt $attempt/$max_attempts: Current environment is $current_env, waiting..."
        sleep 2
        ((attempt++))
    done
    
    echo -e "${RED}✗ Traffic switch verification failed after $max_attempts attempts${NC}"
    return 1
}

# Step 1: Pre-switch validation
echo -e "\n${BLUE}Step 1: Pre-switch validation${NC}"

# Check if target environment is healthy
echo "Checking $TARGET_ENV environment health..."
BACKEND_PODS_READY=$(kubectl get pods -n $NAMESPACE -l app=backend,environment=$TARGET_ENV --no-headers | grep "Running" | grep "1/1" | wc -l)
FRONTEND_PODS_READY=$(kubectl get pods -n $NAMESPACE -l app=frontend,environment=$TARGET_ENV --no-headers | grep "Running" | grep "1/1" | wc -l)

if [ "$BACKEND_PODS_READY" -eq 0 ] || [ "$FRONTEND_PODS_READY" -eq 0 ]; then
    echo -e "${RED}✗ Target environment $TARGET_ENV is not healthy${NC}"
    echo "Backend pods ready: $BACKEND_PODS_READY"
    echo "Frontend pods ready: $FRONTEND_PODS_READY"
    exit 1
fi

echo -e "${GREEN}✓ Target environment $TARGET_ENV is healthy${NC}"

# Check current active environment
CURRENT_ENV=$(get_active_environment)
echo "Current active environment: $CURRENT_ENV"

if [ "$CURRENT_ENV" == "$TARGET_ENV" ]; then
    echo -e "${YELLOW}Warning: Traffic is already pointing to $TARGET_ENV environment${NC}"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# Step 2: Create backup of current state
echo -e "\n${BLUE}Step 2: Creating backup of current configuration${NC}"

mkdir -p backups
kubectl get service backend-service -n $NAMESPACE -o yaml > "backups/backend-service-$TIMESTAMP.yaml"
kubectl get service frontend-service -n $NAMESPACE -o yaml > "backups/frontend-service-$TIMESTAMP.yaml"

echo -e "${GREEN}✓ Configuration backed up${NC}"

# Step 3: Final confirmation
echo -e "\n${YELLOW}Step 3: Final confirmation${NC}"
echo "About to switch traffic:"
echo "  FROM: $SOURCE_ENV environment"
echo "  TO: $TARGET_ENV environment"
echo "  At: $TIMESTAMP"
echo ""
read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Traffic switch cancelled."
    exit 0
fi

# Step 4: Perform traffic switch
echo -e "\n${BLUE}Step 4: Switching traffic${NC}"

# Update backend service
update_service_selector "backend-service" $TARGET_ENV || exit 1

# Update frontend service
update_service_selector "frontend-service" $TARGET_ENV || exit 1

# Step 5: Verify traffic switch
echo -e "\n${BLUE}Step 5: Verifying traffic switch${NC}"

verify_traffic_switch $TARGET_ENV || {
    echo -e "${RED}Traffic switch verification failed!${NC}"
    echo "You may want to rollback using: ./scripts/rollback.sh"
    exit 1
}

# Step 6: Post-switch monitoring
echo -e "\n${BLUE}Step 6: Post-switch monitoring${NC}"

echo "Monitoring new environment for 30 seconds..."
for i in {1..6}; do
    echo "Check $i/6 ($(date)):"
    
    # Check service endpoints
    BACKEND_ENDPOINTS=$(kubectl get endpoints backend-service -n $NAMESPACE -o jsonpath='{.subsets[0].addresses}' | jq length 2>/dev/null || echo "0")
    FRONTEND_ENDPOINTS=$(kubectl get endpoints frontend-service -n $NAMESPACE -o jsonpath='{.subsets[0].addresses}' | jq length 2>/dev/null || echo "0")
    
    echo "  Backend endpoints: $BACKEND_ENDPOINTS"
    echo "  Frontend endpoints: $FRONTEND_ENDPOINTS"
    
    # Check for any pod restarts or failures
    BACKEND_RESTARTS=$(kubectl get pods -n $NAMESPACE -l app=backend,environment=$TARGET_ENV -o jsonpath='{.items[*].status.containerStatuses[0].restartCount}' | tr ' ' '\n' | awk '{sum+=$1} END {print sum+0}')
    FRONTEND_RESTARTS=$(kubectl get pods -n $NAMESPACE -l app=frontend,environment=$TARGET_ENV -o jsonpath='{.items[*].status.containerStatuses[0].restartCount}' | tr ' ' '\n' | awk '{sum+=$1} END {print sum+0}')
    
    echo "  Backend restarts: $BACKEND_RESTARTS"
    echo "  Frontend restarts: $FRONTEND_RESTARTS"
    
    if [ $i -lt 6 ]; then
        sleep 5
    fi
done

echo -e "\n${GREEN}=== Traffic Switch Completed Successfully ===${NC}"
echo "✓ Traffic switched from $SOURCE_ENV to $TARGET_ENV"
echo "✓ All services are pointing to $TARGET_ENV environment"
echo "✓ Post-switch monitoring completed"
echo ""
echo "Next steps:"
echo "1. Monitor application logs: kubectl logs -n $NAMESPACE -l environment=$TARGET_ENV -f"
echo "2. Run additional testing on the live environment"
echo "3. If issues occur, rollback with: ./scripts/rollback.sh"
echo "4. If everything is stable, cleanup old environment with: ./scripts/cleanup.sh $SOURCE_ENV"
echo ""
echo "Access URLs:"
echo "- Main application: http://blue-green-webapp.local"
echo "- Active ($TARGET_ENV) environment: http://$TARGET_ENV.blue-green-webapp.local"
echo "- Standby ($SOURCE_ENV) environment: http://$SOURCE_ENV.blue-green-webapp.local"