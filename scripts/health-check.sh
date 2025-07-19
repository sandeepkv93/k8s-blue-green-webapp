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
ENVIRONMENT=${1:-"all"}

echo -e "${BLUE}=== Blue-Green Health Check Script ===${NC}"
echo "Namespace: $NAMESPACE"
echo "Environment: $ENVIRONMENT"
echo "Timestamp: $(date)"

# Function to check pod health
check_environment_health() {
    local env=$1
    local overall_health=0
    
    echo -e "\n${BLUE}=== $env Environment Health Check ===${NC}"
    
    # Check if deployments exist
    BACKEND_DEPLOYMENT=$(kubectl get deployment backend-$env -n $NAMESPACE 2>/dev/null || echo "")
    FRONTEND_DEPLOYMENT=$(kubectl get deployment frontend-$env -n $NAMESPACE 2>/dev/null || echo "")
    
    if [ -z "$BACKEND_DEPLOYMENT" ] || [ -z "$FRONTEND_DEPLOYMENT" ]; then
        echo -e "${YELLOW}⚠ $env environment not fully deployed${NC}"
        if [ -z "$BACKEND_DEPLOYMENT" ]; then
            echo "  Missing: backend-$env deployment"
        fi
        if [ -z "$FRONTEND_DEPLOYMENT" ]; then
            echo "  Missing: frontend-$env deployment"
        fi
        return 1
    fi
    
    # Check deployment status
    echo -e "${YELLOW}Deployment Status:${NC}"
    kubectl get deployments -n $NAMESPACE -l environment=$env -o wide
    
    # Check pod status
    echo -e "\n${YELLOW}Pod Status:${NC}"
    kubectl get pods -n $NAMESPACE -l environment=$env -o wide
    
    # Count healthy pods
    BACKEND_PODS_TOTAL=$(kubectl get pods -n $NAMESPACE -l app=backend,environment=$env --no-headers | wc -l)
    BACKEND_PODS_READY=$(kubectl get pods -n $NAMESPACE -l app=backend,environment=$env --no-headers | grep "Running" | grep "1/1" | wc -l)
    
    FRONTEND_PODS_TOTAL=$(kubectl get pods -n $NAMESPACE -l app=frontend,environment=$env --no-headers | wc -l)
    FRONTEND_PODS_READY=$(kubectl get pods -n $NAMESPACE -l app=frontend,environment=$env --no-headers | grep "Running" | grep "1/1" | wc -l)
    
    echo -e "\n${YELLOW}Health Summary:${NC}"
    echo "  Backend Pods: $BACKEND_PODS_READY/$BACKEND_PODS_TOTAL ready"
    echo "  Frontend Pods: $FRONTEND_PODS_READY/$FRONTEND_PODS_TOTAL ready"
    
    # Health checks
    if [ "$BACKEND_PODS_READY" -eq "$BACKEND_PODS_TOTAL" ] && [ "$BACKEND_PODS_TOTAL" -gt 0 ]; then
        echo -e "  ${GREEN}✓ Backend: Healthy${NC}"
    else
        echo -e "  ${RED}✗ Backend: Unhealthy${NC}"
        overall_health=1
    fi
    
    if [ "$FRONTEND_PODS_READY" -eq "$FRONTEND_PODS_TOTAL" ] && [ "$FRONTEND_PODS_TOTAL" -gt 0 ]; then
        echo -e "  ${GREEN}✓ Frontend: Healthy${NC}"
    else
        echo -e "  ${RED}✗ Frontend: Unhealthy${NC}"
        overall_health=1
    fi
    
    # Test application endpoints if pods are healthy
    if [ $overall_health -eq 0 ]; then
        echo -e "\n${YELLOW}Application Endpoint Tests:${NC}"
        
        # Test backend health endpoint
        BACKEND_POD=$(kubectl get pods -n $NAMESPACE -l app=backend,environment=$env -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$BACKEND_POD" ]; then
            if kubectl exec -n $NAMESPACE $BACKEND_POD -- curl -f -s http://localhost:8080/health > /dev/null 2>&1; then
                echo -e "  ${GREEN}✓ Backend health endpoint responding${NC}"
            else
                echo -e "  ${RED}✗ Backend health endpoint not responding${NC}"
                overall_health=1
            fi
        fi
        
        # Test frontend endpoint
        FRONTEND_POD=$(kubectl get pods -n $NAMESPACE -l app=frontend,environment=$env -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$FRONTEND_POD" ]; then
            if kubectl exec -n $NAMESPACE $FRONTEND_POD -- curl -f -s http://localhost:80/ > /dev/null 2>&1; then
                echo -e "  ${GREEN}✓ Frontend endpoint responding${NC}"
            else
                echo -e "  ${RED}✗ Frontend endpoint not responding${NC}"
                overall_health=1
            fi
        fi
    fi
    
    # Resource usage
    echo -e "\n${YELLOW}Resource Usage:${NC}"
    kubectl top pods -n $NAMESPACE -l environment=$env 2>/dev/null || echo "  Metrics not available (metrics-server may not be installed)"
    
    return $overall_health
}

# Function to check service routing
check_service_routing() {
    echo -e "\n${BLUE}=== Service Routing Status ===${NC}"
    
    # Get active environment
    ACTIVE_BACKEND_ENV=$(kubectl get service backend-service -n $NAMESPACE -o jsonpath='{.spec.selector.environment}' 2>/dev/null || echo "unknown")
    ACTIVE_FRONTEND_ENV=$(kubectl get service frontend-service -n $NAMESPACE -o jsonpath='{.spec.selector.environment}' 2>/dev/null || echo "unknown")
    
    echo "Active Environments:"
    echo "  Backend Service -> $ACTIVE_BACKEND_ENV"
    echo "  Frontend Service -> $ACTIVE_FRONTEND_ENV"
    
    if [ "$ACTIVE_BACKEND_ENV" == "$ACTIVE_FRONTEND_ENV" ]; then
        echo -e "  ${GREEN}✓ Services are consistently routed${NC}"
    else
        echo -e "  ${RED}✗ Services are inconsistently routed${NC}"
    fi
    
    # Check service endpoints
    echo -e "\n${YELLOW}Service Endpoints:${NC}"
    kubectl get endpoints -n $NAMESPACE
    
    # Check last switch information
    LAST_SWITCH=$(kubectl get service backend-service -n $NAMESPACE -o jsonpath='{.metadata.annotations.blue-green\.deployment/last-switch}' 2>/dev/null || echo "unknown")
    PREVIOUS_ENV=$(kubectl get service backend-service -n $NAMESPACE -o jsonpath='{.metadata.annotations.blue-green\.deployment/previous-environment}' 2>/dev/null || echo "unknown")
    
    echo -e "\n${YELLOW}Deployment History:${NC}"
    echo "  Last Switch: $LAST_SWITCH"
    echo "  Previous Environment: $PREVIOUS_ENV"
}

# Function to check shared resources
check_shared_resources() {
    echo -e "\n${BLUE}=== Shared Resources Status ===${NC}"
    
    # Check database
    echo -e "${YELLOW}Database (PostgreSQL):${NC}"
    POSTGRES_PODS=$(kubectl get pods -n $NAMESPACE -l app=postgres --no-headers | wc -l)
    POSTGRES_READY=$(kubectl get pods -n $NAMESPACE -l app=postgres --no-headers | grep "Running" | grep "1/1" | wc -l)
    
    echo "  Pods: $POSTGRES_READY/$POSTGRES_PODS ready"
    
    if [ "$POSTGRES_READY" -eq "$POSTGRES_PODS" ] && [ "$POSTGRES_PODS" -gt 0 ]; then
        echo -e "  ${GREEN}✓ Database: Healthy${NC}"
    else
        echo -e "  ${RED}✗ Database: Unhealthy${NC}"
        kubectl get pods -n $NAMESPACE -l app=postgres
    fi
    
    # Check Redis
    echo -e "\n${YELLOW}Cache (Redis):${NC}"
    REDIS_PODS=$(kubectl get pods -n $NAMESPACE -l app=redis --no-headers 2>/dev/null | wc -l)
    if [ "$REDIS_PODS" -gt 0 ]; then
        REDIS_READY=$(kubectl get pods -n $NAMESPACE -l app=redis --no-headers | grep "Running" | grep "1/1" | wc -l)
        echo "  Pods: $REDIS_READY/$REDIS_PODS ready"
        
        if [ "$REDIS_READY" -eq "$REDIS_PODS" ]; then
            echo -e "  ${GREEN}✓ Redis: Healthy${NC}"
        else
            echo -e "  ${RED}✗ Redis: Unhealthy${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠ Redis: Not deployed${NC}"
    fi
    
    # Check persistent volumes
    echo -e "\n${YELLOW}Persistent Volumes:${NC}"
    kubectl get pvc -n $NAMESPACE
}

# Main execution
overall_status=0

# Check shared resources first
check_shared_resources

# Check service routing
check_service_routing

# Check environment health
if [ "$ENVIRONMENT" == "all" ]; then
    # Check both environments
    if check_environment_health "blue"; then
        echo -e "${GREEN}✓ Blue environment is healthy${NC}"
    else
        echo -e "${RED}✗ Blue environment has issues${NC}"
        overall_status=1
    fi
    
    if check_environment_health "green"; then
        echo -e "${GREEN}✓ Green environment is healthy${NC}"
    else
        echo -e "${RED}✗ Green environment has issues${NC}"
        overall_status=1
    fi
else
    # Check specific environment
    if check_environment_health "$ENVIRONMENT"; then
        echo -e "${GREEN}✓ $ENVIRONMENT environment is healthy${NC}"
    else
        echo -e "${RED}✗ $ENVIRONMENT environment has issues${NC}"
        overall_status=1
    fi
fi

# Summary
echo -e "\n${BLUE}=== Health Check Summary ===${NC}"
if [ $overall_status -eq 0 ]; then
    echo -e "${GREEN}✓ All checked components are healthy${NC}"
else
    echo -e "${RED}✗ Some components have issues - check details above${NC}"
fi

echo -e "\n${YELLOW}Quick Access Commands:${NC}"
echo "- kubectl get pods -n $NAMESPACE"
echo "- kubectl get services -n $NAMESPACE"
echo "- kubectl logs -n $NAMESPACE -l app=backend,environment=<env> -f"
echo "- kubectl describe pod <pod-name> -n $NAMESPACE"

echo -e "\n${YELLOW}Application URLs:${NC}"
echo "- Main: http://blue-green-webapp.local"
echo "- Blue: http://blue.blue-green-webapp.local"
echo "- Green: http://green.blue-green-webapp.local"

exit $overall_status