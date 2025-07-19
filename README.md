# Blue-Green Deployment with Kubernetes

A comprehensive implementation of blue-green deployment strategy using Kubernetes Services, Labels, Selectors, and automated traffic switching.

## Overview

This project demonstrates zero-downtime deployments using the blue-green deployment pattern. It includes:

- **Frontend**: React application with environment awareness
- **Backend**: Go API server with health checks and database integration
- **Database**: PostgreSQL with persistent storage
- **Automation**: Complete set of deployment and management scripts
- **Monitoring**: Health checks and traffic verification

## Architecture

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
└─────────────────┘         └─────────────────┘
```

## Quick Start

### Prerequisites

1. **Kubernetes Cluster**: minikube, kind, or cloud provider
2. **kubectl**: Configured and authenticated
3. **Docker**: For building images
4. **Ingress Controller**: nginx-ingress for routing

### Setup Ingress Controller (if using minikube)

```bash
minikube addons enable ingress
```

### Add Local DNS Entries

Add these entries to your `/etc/hosts` file:

```bash
echo "$(minikube ip) blue-green-webapp.local" | sudo tee -a /etc/hosts
echo "$(minikube ip) blue.blue-green-webapp.local" | sudo tee -a /etc/hosts
echo "$(minikube ip) green.blue-green-webapp.local" | sudo tee -a /etc/hosts
```

### Initial Deployment

1. **Deploy to Blue Environment**:
   ```bash
   ./scripts/deploy-blue-green.sh v1.0.0 blue
   ```

2. **Access the Application**:
   - Main: http://blue-green-webapp.local
   - Blue: http://blue.blue-green-webapp.local

3. **Deploy New Version to Green**:
   ```bash
   ./scripts/deploy-blue-green.sh v1.1.0 green blue
   ```

4. **Switch Traffic**:
   ```bash
   ./scripts/switch-traffic.sh green blue
   ```

## Scripts Reference

### Deployment Script

```bash
./scripts/deploy-blue-green.sh [VERSION] [TARGET_ENV] [SOURCE_ENV]
```

**Example:**
```bash
./scripts/deploy-blue-green.sh v1.2.0 green blue
```

**Features:**
- Builds Docker images
- Deploys to target environment
- Runs health checks
- Optional traffic switching

### Traffic Switching Script

```bash
./scripts/switch-traffic.sh [TARGET_ENV] [SOURCE_ENV]
```

**Example:**
```bash
./scripts/switch-traffic.sh green blue
```

**Features:**
- Pre-switch validation
- Configuration backup
- Verification and monitoring
- Rollback guidance

### Rollback Script

```bash
./scripts/rollback.sh
```

**Features:**
- Automatic rollback target detection
- Emergency confirmation
- Immediate traffic switch
- Post-rollback verification

### Health Check Script

```bash
./scripts/health-check.sh [ENVIRONMENT]
```

**Examples:**
```bash
./scripts/health-check.sh          # Check all environments
./scripts/health-check.sh blue     # Check blue environment only
./scripts/health-check.sh green    # Check green environment only
```

**Features:**
- Pod health verification
- Service endpoint testing
- Resource usage monitoring
- Database connectivity checks

### Cleanup Script

```bash
./scripts/cleanup.sh [ENVIRONMENT] [force]
```

**Examples:**
```bash
./scripts/cleanup.sh blue          # Interactive cleanup
./scripts/cleanup.sh green force   # Force cleanup without confirmation
```

**Features:**
- Safety checks (prevents cleanup of active environment)
- Resource enumeration
- Confirmation prompts
- Verification of cleanup

## Deployment Workflow

### Standard Deployment Process

1. **Prepare**: Deploy new version to inactive environment
   ```bash
   ./scripts/deploy-blue-green.sh v1.1.0 green blue
   ```

2. **Test**: Validate new environment
   ```bash
   ./scripts/health-check.sh green
   curl http://green.blue-green-webapp.local/api/status
   ```

3. **Switch**: Move traffic to new environment
   ```bash
   ./scripts/switch-traffic.sh green blue
   ```

4. **Monitor**: Watch for issues
   ```bash
   kubectl logs -n blue-green-webapp -l environment=green -f
   ```

5. **Cleanup**: Remove old environment (optional)
   ```bash
   ./scripts/cleanup.sh blue
   ```

### Emergency Rollback

If issues are detected after traffic switch:

```bash
./scripts/rollback.sh
```

This will immediately switch traffic back to the previous environment.

## Monitoring and Troubleshooting

### Check Current Active Environment

```bash
kubectl get service backend-service -n blue-green-webapp -o jsonpath='{.spec.selector.environment}'
```

### View Deployment History

```bash
kubectl get service backend-service -n blue-green-webapp -o jsonpath='{.metadata.annotations}'
```

### Monitor Pods

```bash
# All pods
kubectl get pods -n blue-green-webapp

# Specific environment
kubectl get pods -n blue-green-webapp -l environment=blue

# Watch pods in real-time
kubectl get pods -n blue-green-webapp -l environment=green -w
```

### Check Logs

```bash
# Backend logs
kubectl logs -n blue-green-webapp -l app=backend,environment=green -f

# Frontend logs
kubectl logs -n blue-green-webapp -l app=frontend,environment=blue -f

# Database logs
kubectl logs -n blue-green-webapp -l app=postgres -f
```

### Service Endpoints

```bash
kubectl get endpoints -n blue-green-webapp
```

### Resource Usage

```bash
kubectl top pods -n blue-green-webapp
```

## Application Features

### Frontend (React)

- **Environment Awareness**: Displays current frontend and backend environments
- **Real-time Status**: Shows backend connectivity and version information
- **Visit Tracking**: Displays recent visits with environment/version details
- **Auto-refresh**: Updates data every 30 seconds
- **Responsive Design**: Works on desktop and mobile devices

### Backend (Go)

- **Health Endpoint**: `/health` - Kubernetes health checks
- **Status API**: `/api/status` - Environment and version information
- **Visit Tracking**: Records visits in PostgreSQL database
- **Database Integration**: Automatic connection retry and health monitoring
- **CORS Support**: Enables frontend communication

### Key Endpoints

- `GET /health` - Health check (used by Kubernetes probes)
- `GET /api/status` - Environment status and information
- `GET /api/version` - Version and uptime information
- `GET /api/visits` - Recent visit history

## Configuration

### Environment Variables

**Backend:**
- `ENVIRONMENT`: blue/green (set automatically by deployment)
- `VERSION`: Application version (set automatically)
- `DB_HOST`: Database hostname
- `DB_PORT`: Database port
- `DB_USER`: Database username
- `DB_PASSWORD`: Database password
- `DB_NAME`: Database name

**Frontend:**
- `REACT_APP_ENVIRONMENT`: blue/green (set automatically)
- `REACT_APP_VERSION`: Application version (set automatically)
- `REACT_APP_API_URL`: Backend API URL

### Kubernetes Resources

**Shared Resources:**
- Namespace: `blue-green-webapp`
- PostgreSQL StatefulSet with persistent storage
- ConfigMaps and Secrets
- Database service

**Environment-Specific Resources:**
- Backend Deployment (3 replicas)
- Frontend Deployment (2 replicas)
- Environment-specific services
- Resource limits and health checks

**Traffic Routing:**
- Active backend service (switches between environments)
- Active frontend service (switches between environments)
- Ingress with multiple hosts
- Direct environment access for testing

## Troubleshooting Guide

### Common Issues

1. **Pods not starting**:
   ```bash
   kubectl describe pod <pod-name> -n blue-green-webapp
   kubectl logs <pod-name> -n blue-green-webapp
   ```

2. **Database connection issues**:
   ```bash
   kubectl logs -n blue-green-webapp -l app=postgres
   ./scripts/health-check.sh
   ```

3. **Traffic not switching**:
   ```bash
   kubectl get service backend-service -n blue-green-webapp -o yaml
   kubectl get endpoints -n blue-green-webapp
   ```

4. **Build failures**:
   - Ensure Docker is running
   - Check image tags in deployment files
   - Verify go.mod and package.json are valid

### Reset Everything

To completely reset the deployment:

```bash
kubectl delete namespace blue-green-webapp
./scripts/deploy-blue-green.sh v1.0.0 blue
```

## Security Considerations

- Database credentials are stored in Kubernetes Secrets
- Services use ClusterIP (not exposed externally except via Ingress)
- Health checks don't expose sensitive information
- CORS is configured for frontend-backend communication
- nginx security headers are enabled

## Advanced Features

### Canary Deployments

The foundation supports canary deployments by:
- Using weighted service selectors
- Implementing gradual traffic shifting
- Adding monitoring and automatic rollback

### Multi-Region Deployments

Can be extended for multi-region by:
- Replicating across regions
- Adding region-aware routing
- Implementing cross-region database replication

### CI/CD Integration

Integrate with CI/CD pipelines:
- Trigger deployments on git push
- Run automated tests before traffic switch
- Implement approval workflows
- Add Slack/email notifications

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.