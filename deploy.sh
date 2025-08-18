#!/bin/bash

REGIONS="${REGIONS:-us-east-2,us-west-2}"
ORG_ID="${ORG_ID:-}"
ACCOUNT_ID="${ACCOUNT_ID:-}"

# Convert comma-separated regions to array
IFS=',' read -ra REGIONS_ARRAY <<< "$REGIONS"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

check_dependencies() {
    log "Checking dependencies..."
    
    local deps=("cargo" "aws" "jq" "zip")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error "$dep is not installed"
            exit 1
        fi
    done
    
    if ! cargo lambda --version &> /dev/null; then
        error "cargo lambda is not installed. Install with: cargo install cargo-lambda"
        exit 1
    fi
    
    success "All dependencies are available"
}

build_packages() {
    log "Building packages for both architectures..."
    
    log "Building for x86_64..."
    if ! make package_x86; then
        error "Build failed for x86_64"
        exit 1
    fi
    
    log "Building for ARM64..."
    if ! make package_arm; then
        error "Build failed for ARM64"
        exit 1
    fi
    
    success "Packages built successfully"
}

deploy_to_region() {
    local region=$1
    local arch=$2
    
    log "Deploying $arch layer in $region region..."
    
    if [ "$arch" = "x86_64" ]; then
        if make deploy_x86 REGION="$region"; then
            success "$arch layer deployed in $region"
            
            if [ -n "$ORG_ID" ]; then
                make add_permissions_x86 REGION="$region" ORG_ID="$ORG_ID"
                if [ $? -eq 0 ]; then
                    success "Organization permissions added for $arch in $region"
                else
                    error "Failed to add organization permissions for $arch in $region"
                fi
            elif [ -n "$ACCOUNT_ID" ]; then
                make add_permissions_by_account_x86 REGION="$region" ACCOUNT_ID="$ACCOUNT_ID"
                if [ $? -eq 0 ]; then
                    success "Account permissions added for $arch in $region"
                else
                    error "Failed to add account permissions for $arch in $region"
                fi
            else
                warning "No ORG_ID or ACCOUNT_ID specified. Skipping permissions setup."
            fi
        else
            error "Failed to deploy $arch layer in $region"
            return 1
        fi
    elif [ "$arch" = "arm64" ]; then
        if make deploy_arm REGION="$region"; then
            success "$arch layer deployed in $region"
            
            if [ -n "$ORG_ID" ]; then
                make add_permissions_arm REGION="$region" ORG_ID="$ORG_ID"
                if [ $? -eq 0 ]; then
                    success "Organization permissions added for $arch in $region"
                else
                    error "Failed to add organization permissions for $arch in $region"
                fi
            elif [ -n "$ACCOUNT_ID" ]; then
                make add_permissions_by_account_arm REGION="$region" ACCOUNT_ID="$ACCOUNT_ID"
                if [ $? -eq 0 ]; then
                    success "Account permissions added for $arch in $region"
                else
                    error "Failed to add account permissions for $arch in $region"
                fi
            else
                warning "No ORG_ID or ACCOUNT_ID specified. Skipping permissions setup."
            fi
        else
            error "Failed to deploy $arch layer in $region"
            return 1
        fi
    fi
}

deploy_multi_region() {
    log "Starting multi-region deployment..."
    
    local failed_deployments=()
    
    for region in "${REGIONS_ARRAY[@]}"; do
        log "Processing region: $region"
        
        if deploy_to_region "$region" "x86_64"; then
            success "x86_64 deployment successful in $region"
        else
            failed_deployments+=("x86_64-$region")
        fi
        
        if deploy_to_region "$region" "arm64"; then
            success "ARM64 deployment successful in $region"
        else
            failed_deployments+=("arm64-$region")
        fi
        
        echo ""
    done
    
    if [ ${#failed_deployments[@]} -eq 0 ]; then
        success "All deployments completed successfully!"
    else
        error "Some deployments failed:"
        for failed in "${failed_deployments[@]}"; do
            echo "  - $failed"
        done
        exit 1
    fi
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -r, --regions REGION1,REGION2  Specify regions (overrides REGIONS env var)"
    echo "  -o, --org-id ORG_ID           Organization ID for permissions"
    echo "  -a, --account-id ACCOUNT_ID   Account ID for permissions"
    echo "  --build-only                  Only build packages, don't deploy"
    echo "  --deploy-only                 Only deploy (assumes packages already exist)"
    echo "  -h, --help                    Show this help"
    echo ""
    echo "Environment variables:"
    echo "  REGIONS     Comma-separated list of regions (default: us-east-1,us-west-2,eu-west-1,ap-southeast-1)"
    echo "  ORG_ID      AWS Organization ID"
    echo "  ACCOUNT_ID  AWS Account ID"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy with default configuration"
    echo "  REGIONS=us-east-1,eu-west-1 $0       # Deploy to specific regions"
    echo "  $0 -r us-east-1,eu-west-1           # Deploy to specific regions"
    echo "  $0 -o o-1234567890                   # Deploy with organization permissions"
    echo "  $0 -a 123456789012                   # Deploy with account permissions"
    echo "  $0 --build-only                      # Only build packages"
}

BUILD_ONLY=false
DEPLOY_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--regions)
            IFS=',' read -ra REGIONS_ARRAY <<< "$2"
            shift 2
            ;;
        -o|--org-id)
            ORG_ID="$2"
            shift 2
            ;;
        -a|--account-id)
            ACCOUNT_ID="$2"
            shift 2
            ;;
        --build-only)
            BUILD_ONLY=true
            shift
            ;;
        --deploy-only)
            DEPLOY_ONLY=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

main() {
    log "Starting multi-region deployment process for AWS Lambda Environment Variables from Secret Manager"
    
    check_dependencies
    
    if [ "$DEPLOY_ONLY" = false ]; then
        build_packages
    fi
    
    if [ "$BUILD_ONLY" = false ]; then
        if [ ! -f "out-x86.zip" ] || [ ! -f "out-arm.zip" ]; then
            error "Zip files don't exist. Run build first."
            exit 1
        fi
        
        deploy_multi_region
        
        log "Response files generated:"
        for region in "${REGIONS_ARRAY[@]}"; do
            echo "  - response-x86-$region.json"
            echo "  - response-arm-$region.json"
        done
    fi
    
    success "Process completed!"
}

main "$@"