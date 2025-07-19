# Blue-Green Deployment Pipeline - Implementation Plan

## Project Name: `k8s-blue-green-webapp`

## Objective
Implement a blue-green deployment strategy for zero-downtime updates using Kubernetes Services, Labels, Selectors, and automated traffic switching.

## Overview

Blue-green deployment is a technique that reduces downtime and risk by running two identical production environments called Blue and Green. At any time, only one environment is live, serving all production traffic. When deploying a new version, you deploy to the inactive environment, test it thoroughly, then switch traffic to it instantly.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Load Balancer / Ingress                      │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Active Service Selector                         │
│           (Points to Blue OR Green environment)                 │
└─────────────────────┬───────────────────────────────────────────┘
                      │
        ┌─────────────┴─────────────┐
        ▼                           ▼
┌─────────────────┐         ┌─────────────────┐
│ BLUE Environment│         │GREEN Environment│
│   (v1.0.0)      │         │   (v1.1.0)      │
│                 │         │                 │
│ Frontend Pods   │         │ Frontend Pods   │
│ Backend Pods    │         │ Backend Pods    │
│ Database        │         │ Database        │
│ Redis Cache     │         │ Redis Cache     │
└─────────────────┘         └─────────────────┘
```

## Key Components

### 1. Environment Versioning
- **Blue Environment**: Current stable production version
- **Green Environment**: New version being deployed
- **Shared Resources**: Database and persistent storage (shared between environments)
- **Isolated Resources**: Application pods with version-specific labels

### 2. Traffic Switching Mechanism
- **Service Selectors**: Use label selectors to route traffic
- **Environment Labels**: `environment: blue` or `environment: green`
- **Version Labels**: `version: v1.0.0`, `version: v1.1.0`
- **Instant Switching**: Update service selector to switch traffic

### 3. Deployment Strategy
- **Prepare**: Deploy new version to inactive environment
- **Test**: Validate new environment functionality
- **Switch**: Update service selector for instant traffic switch
- **Cleanup**: Remove old environment after successful deployment

## Directory Structure

```
k8s-blue-green-webapp/
├── frontend/
│   ├── Dockerfile
│   ├── package.json
│   └── src/
├── backend/
│   ├── Dockerfile
│   ├── go.mod
│   └── main.go
├── k8s/
│   ├── namespace.yaml
│   ├── shared/                    # Shared resources
│   │   ├── configmaps/
│   │   ├── secrets/
│   │   ├── database/
│   │   └── redis/
│   ├── blue/                      # Blue environment
│   │   ├── backend-deployment.yaml
│   │   ├── frontend-deployment.yaml
│   │   └── services.yaml
│   ├── green/                     # Green environment
│   │   ├── backend-deployment.yaml
│   │   ├── frontend-deployment.yaml
│   │   └── services.yaml
│   ├── routing/                   # Traffic routing
│   │   ├── active-services.yaml
│   │   └── ingress.yaml
│   └── monitoring/
├── scripts/
│   ├── deploy-blue-green.sh
│   ├── switch-traffic.sh
│   ├── rollback.sh
│   ├── health-check.sh
│   └── cleanup.sh
└── README.md
```

## Implementation Steps

### Step 1: Shared Infrastructure

**File: k8s/namespace.yaml**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: blue-green-webapp
  labels:
    deployment-strategy: blue-green
```

**File: k8s/shared/secrets/db-credentials.yaml**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
  namespace: blue-green-webapp
type: Opaque
stringData:
  username: postgres
  password: postgres123
```

**File: k8s/shared/configmaps/app-config.yaml**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: blue-green-webapp
data:
  DB_HOST: 'postgres-service'
  DB_PORT: '5432'
  DB_NAME: 'webapp'
  REDIS_HOST: 'redis-service'
  LOG_LEVEL: 'info'
```

**File: k8s/shared/database/statefulset.yaml**
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: blue-green-webapp
  labels:
    component: database
    shared: "true"
spec:
  serviceName: postgres-service
  replicas: 1
  selector:
    matchLabels:
      app: postgres
      component: database
  template:
    metadata:
      labels:
        app: postgres
        component: database
        shared: "true"
    spec:
      containers:
        - name: postgres
          image: postgres:15
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: username
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: password
            - name: POSTGRES_DB
              value: webapp
          volumeMounts:
            - name: postgres-storage
              mountPath: /var/lib/postgresql/data
          resources:
            requests:
              memory: '256Mi'
              cpu: '250m'
            limits:
              memory: '512Mi'
              cpu: '500m'
  volumeClaimTemplates:
    - metadata:
        name: postgres-storage
      spec:
        accessModes: ['ReadWriteOnce']
        resources:
          requests:
            storage: 10Gi
```

**File: k8s/shared/database/service.yaml**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
  namespace: blue-green-webapp
  labels:
    component: database
    shared: "true"
spec:
  selector:
    app: postgres
    component: database
  ports:
    - port: 5432
      targetPort: 5432
  clusterIP: None
```

### Step 2: Blue Environment Deployments

**File: k8s/blue/backend-deployment.yaml**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-blue
  namespace: blue-green-webapp
  labels:
    app: backend
    environment: blue
    component: backend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: backend
      environment: blue
  template:
    metadata:
      labels:
        app: backend
        environment: blue
        component: backend
        version: v1.0.0
    spec:
      containers:
        - name: backend
          image: backend:v1.0.0
          ports:
            - containerPort: 8080
              name: http
          env:
            - name: ENVIRONMENT
              value: "blue"
            - name: VERSION
              value: "v1.0.0"
            - name: DB_USER
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: username
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: password
          envFrom:
            - configMapRef:
                name: app-config
          resources:
            requests:
              memory: '128Mi'
              cpu: '100m'
            limits:
              memory: '256Mi'
              cpu: '200m'
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
```

**File: k8s/blue/frontend-deployment.yaml**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-blue
  namespace: blue-green-webapp
  labels:
    app: frontend
    environment: blue
    component: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
      environment: blue
  template:
    metadata:
      labels:
        app: frontend
        environment: blue
        component: frontend
        version: v1.0.0
    spec:
      containers:
        - name: frontend
          image: frontend:v1.0.0
          ports:
            - containerPort: 80
              name: http
          env:
            - name: REACT_APP_API_URL
              value: 'http://backend-service:8080'
            - name: REACT_APP_ENVIRONMENT
              value: 'blue'
            - name: REACT_APP_VERSION
              value: 'v1.0.0'
          resources:
            requests:
              memory: '64Mi'
              cpu: '50m'
            limits:
              memory: '128Mi'
              cpu: '100m'
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 15
            periodSeconds: 10
```

**File: k8s/blue/services.yaml**
```yaml
# Direct service for blue environment (for testing)
apiVersion: v1
kind: Service
metadata:
  name: backend-blue-service
  namespace: blue-green-webapp
  labels:
    app: backend
    environment: blue
    component: backend
spec:
  selector:
    app: backend
    environment: blue
  ports:
    - port: 8080
      targetPort: 8080
      name: http
  type: ClusterIP

---
# Direct service for blue frontend (for testing)
apiVersion: v1
kind: Service
metadata:
  name: frontend-blue-service
  namespace: blue-green-webapp
  labels:
    app: frontend
    environment: blue
    component: frontend
spec:
  selector:
    app: frontend
    environment: blue
  ports:
    - port: 80
      targetPort: 80
      name: http
  type: ClusterIP
```

### Step 3: Green Environment Deployments

**File: k8s/green/backend-deployment.yaml**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-green
  namespace: blue-green-webapp
  labels:
    app: backend
    environment: green
    component: backend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: backend
      environment: green
  template:
    metadata:
      labels:
        app: backend
        environment: green
        component: backend
        version: v1.1.0
    spec:
      containers:
        - name: backend
          image: backend:v1.1.0
          ports:
            - containerPort: 8080
              name: http
          env:
            - name: ENVIRONMENT
              value: "green"
            - name: VERSION
              value: "v1.1.0"
            - name: DB_USER
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: username
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: password
          envFrom:
            - configMapRef:
                name: app-config
          resources:
            requests:
              memory: '128Mi'
              cpu: '100m'
            limits:
              memory: '256Mi'
              cpu: '200m'
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
```

**File: k8s/green/frontend-deployment.yaml**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-green
  namespace: blue-green-webapp
  labels:
    app: frontend
    environment: green
    component: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
      environment: green
  template:
    metadata:
      labels:
        app: frontend
        environment: green
        component: frontend
        version: v1.1.0
    spec:
      containers:
        - name: frontend
          image: frontend:v1.1.0
          ports:
            - containerPort: 80
              name: http
          env:
            - name: REACT_APP_API_URL
              value: 'http://backend-service:8080'
            - name: REACT_APP_ENVIRONMENT
              value: 'green'
            - name: REACT_APP_VERSION
              value: 'v1.1.0'
          resources:
            requests:
              memory: '64Mi'
              cpu: '50m'
            limits:
              memory: '128Mi'
              cpu: '100m'
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 15
            periodSeconds: 10
```

### Step 4: Active Traffic Routing Services

**File: k8s/routing/active-services.yaml**
```yaml
# Active backend service - initially points to blue
apiVersion: v1
kind: Service
metadata:
  name: backend-service
  namespace: blue-green-webapp
  labels:
    app: backend
    role: active
    component: backend
  annotations:
    blue-green.deployment/active-environment: "blue"
    blue-green.deployment/last-switch: ""
spec:
  selector:
    app: backend
    environment: blue  # This selector determines active environment
  ports:
    - port: 8080
      targetPort: 8080
      name: http
  type: ClusterIP

---
# Active frontend service - initially points to blue
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
  namespace: blue-green-webapp
  labels:
    app: frontend
    role: active
    component: frontend
  annotations:
    blue-green.deployment/active-environment: "blue"
    blue-green.deployment/last-switch: ""
spec:
  selector:
    app: frontend
    environment: blue  # This selector determines active environment
  ports:
    - port: 80
      targetPort: 80
      name: http
  type: ClusterIP
```

**File: k8s/routing/ingress.yaml**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: blue-green-webapp-ingress
  namespace: blue-green-webapp
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
spec:
  ingressClassName: nginx
  rules:
    - host: blue-green-webapp.local
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: backend-service
                port:
                  number: 8080
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend-service
                port:
                  number: 80
    # Additional hosts for direct environment access
    - host: blue.blue-green-webapp.local
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: backend-blue-service
                port:
                  number: 8080
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend-blue-service
                port:
                  number: 80
    - host: green.blue-green-webapp.local
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: backend-green-service
                port:
                  number: 8080
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend-green-service
                port:
                  number: 80
```

### Step 5: Deployment and Traffic Switching Scripts

**File: scripts/deploy-blue-green.sh**
```bash
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
```

**File: scripts/switch-traffic.sh**
```bash
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
```

**File: scripts/rollback.sh**
```bash
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
```

**File: scripts/health-check.sh**
```bash
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
```

**File: scripts/cleanup.sh**
```bash
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
```

## Key Learning Points

### 1. Service Label Selectors
- **Dynamic Routing**: Services use label selectors to determine which pods receive traffic
- **Instant Switching**: Changing service selector immediately redirects traffic
- **Zero Downtime**: No connection drops during traffic switch

### 2. Environment Labeling Strategy
```yaml
labels:
  app: backend
  environment: blue|green
  version: v1.0.0
  component: backend
```

### 3. Traffic Switching Mechanism
- **Active Service**: Points to current production environment
- **Environment Services**: Direct access for testing
- **Selector Updates**: `kubectl patch` commands for instant switching

### 4. Deployment Safety
- **Health Checks**: Validate new environment before switching
- **Rollback Capability**: Quick revert to previous environment
- **Monitoring**: Continuous health verification

### 5. Shared vs Isolated Resources
- **Shared**: Database, Redis, ConfigMaps, Secrets
- **Isolated**: Application pods, deployments, environment-specific services

## Testing Scenarios

### 1. Basic Blue-Green Deployment
```bash
# Deploy initial version to blue
./scripts/deploy-blue-green.sh v1.0.0 blue

# Deploy new version to green
./scripts/deploy-blue-green.sh v1.1.0 green blue

# Switch traffic
./scripts/switch-traffic.sh green blue
```

### 2. Rollback Testing
```bash
# If issues occur, immediate rollback
./scripts/rollback.sh

# Or targeted rollback
./scripts/switch-traffic.sh blue green
```

### 3. Health Monitoring
```bash
# Check all environments
./scripts/health-check.sh

# Check specific environment
./scripts/health-check.sh green
```

## Prerequisites

1. **Kubernetes Cluster**: minikube, kind, or cloud provider
2. **kubectl**: Configured and authenticated
3. **Docker**: For building images
4. **Ingress Controller**: nginx-ingress for routing
5. **Monitoring**: Metrics server (optional)

## Expected Outcomes

- **Zero-downtime deployments**: Instant traffic switching
- **Easy rollbacks**: Quick revert capability
- **Environment isolation**: Independent testing environments
- **Shared data consistency**: Database persists across switches
- **Automated health checks**: Validation before traffic switch
- **Clear monitoring**: Real-time environment status

## Advanced Features

### 1. Automated Testing Pipeline
- Pre-switch validation tests
- Smoke tests on new environment
- Load testing capabilities
- Automated rollback on failure

### 2. Gradual Traffic Shifting
- Canary releases with weighted routing
- Progressive traffic migration
- A/B testing capabilities

### 3. Multi-Service Coordination
- Coordinated deployment across services
- Service dependency management
- Cross-service compatibility testing

This comprehensive plan provides a production-ready blue-green deployment strategy with robust automation, safety checks, and monitoring capabilities.