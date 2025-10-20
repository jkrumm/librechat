#!/bin/bash

# LibreChat Setup and Run Script
# This script sets up the environment, validates configuration, and starts LibreChat

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENV_FILE=".env"
ENV_EXAMPLE_FILE=".env.example"
CONFIG_FILE="librechat.yaml"
DATA_DIR="./data"
FIRST_RUN=false

# Print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Generate secure random string
generate_secret() {
    local length=$1
    openssl rand -hex $length 2>/dev/null || xxd -l $length -p /dev/urandom | tr -d '\n'
}

# Check if required commands exist
check_dependencies() {
    print_status "Checking dependencies..."

    local missing_deps=()

    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    fi

    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        missing_deps+=("docker-compose")
    fi

    if ! command -v openssl &> /dev/null && ! command -v xxd &> /dev/null; then
        missing_deps+=("openssl or xxd")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        exit 1
    fi

    print_success "All dependencies found"
}

# Create required directories
setup_directories() {
    print_status "Setting up directories..."

    local dirs=(
        "$DATA_DIR/mongodb"
        "$DATA_DIR/meilisearch"
        "$DATA_DIR/vectordb"
        "$DATA_DIR/images"
        "$DATA_DIR/uploads"
        "$DATA_DIR/logs"
    )

    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
    done

    print_success "Data directories ready"
}

# Setup environment file
setup_env_file() {
    print_status "Setting up environment file..."

    if [ ! -f "$ENV_FILE" ]; then
        if [ -f "$ENV_EXAMPLE_FILE" ]; then
            cp "$ENV_EXAMPLE_FILE" "$ENV_FILE"
            print_success "Created .env from .env.example"
            FIRST_RUN=true
        else
            print_error ".env.example not found! Please create it first."
            exit 1
        fi
    else
        print_success "Environment file already exists"
    fi
}

# Extract ${} variables from docker-compose.yml
get_env_vars_from_docker_compose() {
    if [ ! -f "docker-compose.yml" ]; then
        print_error "docker-compose.yml not found!"
        exit 1
    fi

    # Extract ${VAR} and ${VAR:-default} patterns, remove duplicates
    grep -oE '\$\{[A-Z_][A-Z0-9_]*[^}]*\}' docker-compose.yml | \
        sed 's/\${\([A-Z_][A-Z0-9_]*\).*/\1/' | \
        sort -u
}

# Extract ${} variables from librechat.yaml
get_env_vars_from_librechat() {
    if [ ! -f "$CONFIG_FILE" ]; then
        return 0  # Not an error if librechat.yaml doesn't exist yet
    fi

    # Extract ${VAR} and ${VAR:-default} patterns, remove duplicates
    grep -oE '\$\{[A-Z_][A-Z0-9_]*[^}]*\}' "$CONFIG_FILE" 2>/dev/null | \
        sed 's/\${\([A-Z_][A-Z0-9_]*\).*/\1/' | \
        sort -u || true
}

# Get all environment variables from both sources
get_all_required_env_vars() {
    local docker_vars librechat_vars all_vars

    # Get variables from both sources
    docker_vars=$(get_env_vars_from_docker_compose)
    librechat_vars=$(get_env_vars_from_librechat)

    # Combine and deduplicate
    all_vars=$(echo -e "$docker_vars\n$librechat_vars" | grep -v '^$' | sort -u)

    echo "$all_vars"
}

# Generate secrets automatically
generate_secrets() {
    print_status "Generating security secrets..."

    local secret_vars=(
        "JWT_SECRET:32"
        "JWT_REFRESH_SECRET:32"
        "CREDS_KEY:32"
        "CREDS_IV:16"
    )

    local secrets_generated=false

    for secret_info in "${secret_vars[@]}"; do
        local var_name=$(echo "$secret_info" | cut -d: -f1)
        local byte_length=$(echo "$secret_info" | cut -d: -f2)

        # Check if secret is already set and not empty
        if grep -q "^${var_name}=.\+$" "$ENV_FILE" 2>/dev/null; then
            continue
        fi

        print_status "Generating $var_name..."
        local secret_value=$(generate_secret $byte_length)

        # Replace the empty placeholder with the generated secret
        sed -i.bak "s|^${var_name}=.*|${var_name}=${secret_value}|" "$ENV_FILE"
        secrets_generated=true
    done

    if [ "$secrets_generated" = true ]; then
        rm -f "$ENV_FILE.bak" 2>/dev/null
        print_success "Generated new security secrets"
    else
        print_success "Security secrets already configured"
    fi
}

# Validate environment variables dynamically from docker-compose.yml and librechat.yaml
validate_env() {
    print_status "Scanning configuration files for required environment variables..."

    # Get all required variables from docker-compose.yml and librechat.yaml
    local all_required_vars
    all_required_vars=$(get_all_required_env_vars)

    if [ -z "$all_required_vars" ]; then
        print_success "No environment variables required"
        return 0
    fi

    local auto_generated_vars=("JWT_SECRET" "JWT_REFRESH_SECRET" "CREDS_KEY" "CREDS_IV")

    # Filter out auto-generated variables from the display and processing
    local user_configurable_vars=""
    for var in $all_required_vars; do
        local is_auto_generated=false
        for auto_var in "${auto_generated_vars[@]}"; do
            if [ "$var" = "$auto_var" ]; then
                is_auto_generated=true
                break
            fi
        done

        if [ "$is_auto_generated" = false ]; then
            user_configurable_vars="$user_configurable_vars $var"
        fi
    done

    if [ -n "$user_configurable_vars" ]; then
        print_status "Found user-configurable variables in configuration files:"
        echo "$user_configurable_vars" | tr ' ' '\n' | grep -v '^$' | sed 's/^/  - /'
        echo
    fi

    local missing_vars=()

    # Source the .env file to get current values (after secrets have been generated)
    source "$ENV_FILE" 2>/dev/null || true

    # Check each user-configurable variable
    for var in $user_configurable_vars; do
        # Check if variable is empty or not set
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -ne 0 ]; then
        print_warning "Found ${#missing_vars[@]} missing environment variable(s):"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done

        echo
        print_status "Please provide values for the missing variables:"

        # Interactive prompt for missing variables
        for var in "${missing_vars[@]}"; do
            # Special handling for OPENAI_BASE_URL with default suggestion
            if [ "$var" = "OPENAI_BASE_URL" ]; then
                echo -n "Enter value for $var (press Enter for IU default: https://unified-endpoint-main.app.iu-it.org/openai/v1): "
                read -r value
                if [ -z "$value" ]; then
                    value="https://unified-endpoint-main.app.iu-it.org/openai/v1"
                    print_status "Using IU default URL"
                fi
            else
                echo -n "Enter value for $var (press Enter to skip): "
                read -r value
            fi

            if [ -n "$value" ]; then
                # Update the variable in .env file (use different delimiter to handle URLs with slashes)
                if grep -q "^$var=" "$ENV_FILE" 2>/dev/null; then
                    sed -i.bak "s|^$var=.*|$var=$value|" "$ENV_FILE"
                else
                    echo "$var=$value" >> "$ENV_FILE"
                fi
                rm -f "$ENV_FILE.bak" 2>/dev/null
                print_success "Set $var"
            else
                print_warning "Skipped $var - you can set it manually in .env file"
            fi
        done

        echo
        print_status "Re-validating after updates..."
        # Re-source after updates
        source "$ENV_FILE" 2>/dev/null || true

        # Check if variables are still missing after user input
        local still_missing=()
        for var in $user_configurable_vars; do
            if [ -z "${!var}" ]; then
                still_missing+=("$var")
            fi
        done

        if [ ${#still_missing[@]} -ne 0 ]; then
            print_warning "The following variables are still not set:"
            for var in "${still_missing[@]}"; do
                echo "  - $var"
            done
            echo "You can set them later by editing .env file or by adding them to librechat.yaml"
        fi
    else
        if [ -n "$user_configurable_vars" ]; then
            print_success "All user-configurable environment variables are set"
        else
            print_success "No user-configurable environment variables required"
        fi
    fi

    # Critical validation - some variables are absolutely required
    source "$ENV_FILE" 2>/dev/null || true
    local critical_missing=()

    # Check critical variables that LibreChat absolutely needs
    if [ -z "$UNIFIED_ENDPOINT_API_KEY" ]; then
        critical_missing+=("UNIFIED_ENDPOINT_API_KEY")
    fi

    if [ ${#critical_missing[@]} -ne 0 ]; then
        echo
        print_error "Critical variables are missing and LibreChat cannot start without them:"
        for var in "${critical_missing[@]}"; do
            echo "  - $var"
        done
        echo
        print_error "Please set these in your .env file before continuing."
        exit 1
    fi
}

# Validate librechat.yaml configuration exists
validate_config() {
    print_status "Validating LibreChat configuration..."

    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "librechat.yaml not found! This file should be in your repository."
        print_error "Please ensure librechat.yaml exists in your project root."
        exit 1
    else
        print_success "librechat.yaml found"
    fi
}

# Create initial admin user
create_initial_user() {
    print_status "Creating initial admin user..."
    echo
    echo "Please provide details for the first admin user:"
    echo

    read -p "Email: " email
    read -p "Name (default: ${email%%@*}): " name
    name=${name:-${email%%@*}}
    read -p "Username (default: ${email%%@*}): " username
    username=${username:-${email%%@*}}
    read -s -p "Password: " password
    echo
    echo

    if [ -z "$email" ] || [ -z "$password" ]; then
        print_error "Email and password are required"
        return 1
    fi

    # Wait for API to be ready
    print_status "Waiting for LibreChat API to be ready..."
    local max_attempts=20
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if docker exec LibreChat-API test -f /app/config/create-user.js 2>/dev/null; then
            break
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    if [ $attempt -eq $max_attempts ]; then
        print_error "LibreChat API did not become ready in time"
        return 1
    fi

    # Create the user
    print_status "Creating user account..."
    if docker exec LibreChat-API node /app/config/create-user.js "$email" "$name" "$username" "$password" --email-verified=true 2>&1 | grep -q "User created successfully"; then
        echo
        print_success "Admin user created successfully!"
        print_success "Email: $email"
        print_success "Username: $username"
        echo
        return 0
    else
        print_error "Failed to create user"
        return 1
    fi
}

# Determine docker compose command
get_compose_cmd() {
    if docker compose version &> /dev/null; then
        echo "docker compose"
    else
        echo "docker-compose"
    fi
}

# Start services
start_services() {
    print_status "Starting LibreChat services..."

    local compose_cmd=$(get_compose_cmd)

    # Pull latest images
    print_status "Pulling latest images..."
    $compose_cmd pull

    # Start services
    print_status "Starting containers..."
    $compose_cmd up -d

    if [ $? -eq 0 ]; then
        print_success "Services started successfully"
        print_status "Waiting for services to initialize..."
        sleep 10
        return 0
    else
        print_error "Failed to start services"
        return 1
    fi
}

# Restart API service
restart_api() {
    print_status "Restarting LibreChat API..."
    local compose_cmd=$(get_compose_cmd)

    $compose_cmd restart librechat-api

    if [ $? -eq 0 ]; then
        print_success "LibreChat API restarted successfully"
        return 0
    else
        print_error "Failed to restart LibreChat API"
        return 1
    fi
}

# Show status and connection info
show_status() {
    local compose_cmd=$(get_compose_cmd)

    echo
    print_success "LibreChat is ready!"
    echo
    print_status "Service Information:"
    echo "  🌐 LibreChat URL: http://localhost:3080"
    echo "  📁 Data Directory: $DATA_DIR"
    echo "  ⚙️  Environment: $ENV_FILE"
    echo "  📝 Configuration: $CONFIG_FILE"
    echo
    print_status "Useful Commands:"
    echo "  View logs:      docker logs LibreChat-API -f"
    echo "  Stop services:  $compose_cmd down"
    echo "  Restart:        $compose_cmd restart"
    echo "  Create user:    docker exec LibreChat-API node /app/config/create-user.js"
    echo
}

# Main execution
main() {
    echo "=� LibreChat Setup Script"
    echo "=========================="
    echo

    # Run setup steps
    check_dependencies
    setup_directories
    setup_env_file
    generate_secrets
    validate_env
    validate_config

    if start_services; then
        # Only prompt for user creation on first run
        if [ "$FIRST_RUN" = true ]; then
            echo
            print_status "🎉 First time setup detected!"
            echo
            echo -n "Would you like to create an admin user now? (y/n): "
            read -r create_user_choice

            if [[ $create_user_choice =~ ^[Yy]$ ]]; then
                create_initial_user
            else
                echo
                print_warning "Skipping user creation."
                print_status "You can create a user later with:"
                echo "  docker exec LibreChat-API node /app/config/create-user.js"
                echo
            fi
        fi

        restart_api
        show_status
    else
        print_error "Setup failed"
        exit 1
    fi
}

# Run main function
main "$@"