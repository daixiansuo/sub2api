#!/usr/bin/env bash
# =============================================================================
# Sub2API Deployment Script
# =============================================================================
# Unified script for building, deploying, rolling back, and managing
# sub2api Docker images with version tagging.
#
# Usage:
#   ./deploy.sh build              Build image from current source code
#   ./deploy.sh deploy             Deploy using the latest built image
#   ./deploy.sh up                 Build + deploy in one step
#   ./deploy.sh rollback [tag]     Rollback to previous or specified version
#   ./deploy.sh list               List all available local image versions
#   ./deploy.sh status             Show current running version and container status
#   ./deploy.sh logs [lines]       Show application logs (default: 100 lines)
#   ./deploy.sh cleanup [N]        Remove old images, keep latest N (default: 5)
#   ./deploy.sh stop               Stop all services
#   ./deploy.sh restart            Restart all services
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.prod.yml"
ENV_FILE="${SCRIPT_DIR}/.env"
CURRENT_VERSION_FILE="${SCRIPT_DIR}/.current_version"
DEPLOY_HISTORY_FILE="${SCRIPT_DIR}/.deploy_history"
IMAGE_NAME="sub2api"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

check_env_file() {
    if [ ! -f "$ENV_FILE" ]; then
        error ".env file not found at $ENV_FILE"
        echo "  Run: cp ${SCRIPT_DIR}/.env.example ${ENV_FILE}"
        echo "  Then edit ${ENV_FILE} with your configuration."
        exit 1
    fi
}

check_compose_file() {
    if [ ! -f "$COMPOSE_FILE" ]; then
        error "Compose file not found: $COMPOSE_FILE"
        exit 1
    fi
}

get_current_version() {
    if [ -f "$CURRENT_VERSION_FILE" ]; then
        cat "$CURRENT_VERSION_FILE"
    else
        echo "unknown"
    fi
}

save_version() {
    local tag="$1"
    local prev
    prev="$(get_current_version)"

    echo "$tag" > "$CURRENT_VERSION_FILE"

    # Append to history (timestamp | action | new_tag | previous_tag)
    echo "$(date '+%Y-%m-%d %H:%M:%S') | deploy | ${tag} | prev:${prev}" >> "$DEPLOY_HISTORY_FILE"
}

generate_image_tag() {
    cd "$REPO_ROOT"
    local git_commit git_tag image_tag

    git_commit="$(git rev-parse --short HEAD)"

    # Check for exact git tag on current commit
    git_tag="$(git describe --tags --exact-match 2>/dev/null || true)"

    if [ -n "$git_tag" ]; then
        image_tag="${git_tag}-${git_commit}"
    else
        image_tag="$(date '+%Y%m%d-%H%M%S')-${git_commit}"
    fi

    echo "$image_tag"
}

docker_compose() {
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_build() {
    info "Building image from source..."
    cd "$REPO_ROOT"

    # Check for uncommitted changes
    if ! git diff --quiet HEAD 2>/dev/null; then
        warn "Working tree has uncommitted changes. Image will include uncommitted code."
    fi

    local image_tag git_commit
    image_tag="$(generate_image_tag)"
    git_commit="$(git rev-parse --short HEAD)"

    info "Version tag: ${BLUE}${image_tag}${NC}"
    info "Commit:      ${git_commit}"

    docker build \
        --build-arg COMMIT="$git_commit" \
        --build-arg VERSION="$image_tag" \
        --build-arg DATE="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        -t "${IMAGE_NAME}:${image_tag}" \
        -t "${IMAGE_NAME}:latest" \
        -f "${REPO_ROOT}/Dockerfile" \
        "$REPO_ROOT"

    info "Build complete: ${BLUE}${IMAGE_NAME}:${image_tag}${NC}"
    echo "$image_tag" > "$CURRENT_VERSION_FILE"
}

cmd_deploy() {
    check_env_file
    check_compose_file

    local image_tag
    image_tag="$(get_current_version)"

    if [ "$image_tag" = "unknown" ]; then
        # No version recorded, try latest
        if docker image inspect "${IMAGE_NAME}:latest" >/dev/null 2>&1; then
            image_tag="latest"
            warn "No version recorded, using 'latest'"
        else
            error "No image found. Run './deploy.sh build' first."
            exit 1
        fi
    fi

    # Verify image exists locally
    if [ "$image_tag" != "latest" ] && ! docker image inspect "${IMAGE_NAME}:${image_tag}" >/dev/null 2>&1; then
        error "Image ${IMAGE_NAME}:${image_tag} not found locally."
        error "Run './deploy.sh build' to build it, or './deploy.sh list' to see available versions."
        exit 1
    fi

    info "Deploying version: ${BLUE}${image_tag}${NC}"

    IMAGE_TAG="$image_tag" docker_compose up -d

    save_version "$image_tag"
    info "Deployment complete. Use './deploy.sh status' to check."
}

cmd_up() {
    cmd_build
    echo ""
    cmd_deploy
}

cmd_rollback() {
    check_env_file
    check_compose_file

    local target_tag="$1"

    if [ -z "$target_tag" ]; then
        # No tag specified: find previous version from history
        if [ ! -f "$DEPLOY_HISTORY_FILE" ]; then
            error "No deploy history found. Specify a version tag: ./deploy.sh rollback <tag>"
            exit 1
        fi

        local current_tag
        current_tag="$(get_current_version)"

        # Find the most recent entry that is different from current
        target_tag="$(grep '| deploy |' "$DEPLOY_HISTORY_FILE" \
            | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3}' \
            | grep -v "^${current_tag}$" \
            | tail -1)"

        if [ -z "$target_tag" ]; then
            error "No previous version found in history."
            echo "  Available versions:"
            cmd_list
            echo ""
            echo "  Usage: ./deploy.sh rollback <tag>"
            exit 1
        fi
    fi

    # Verify image exists
    if ! docker image inspect "${IMAGE_NAME}:${target_tag}" >/dev/null 2>&1; then
        error "Image ${IMAGE_NAME}:${target_tag} not found locally."
        echo "  Available versions:"
        cmd_list
        exit 1
    fi

    local current_tag
    current_tag="$(get_current_version)"
    warn "Rolling back: ${current_tag} -> ${BLUE}${target_tag}${NC}"

    IMAGE_TAG="$target_tag" docker_compose up -d

    echo "$target_tag" > "$CURRENT_VERSION_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | rollback | ${target_tag} | prev:${current_tag}" >> "$DEPLOY_HISTORY_FILE"

    info "Rollback complete to ${BLUE}${target_tag}${NC}"
}

cmd_list() {
    info "Available ${IMAGE_NAME} images:"
    echo ""

    local current_tag
    current_tag="$(get_current_version)"

    # List all tags sorted by creation time (newest first)
    docker images "${IMAGE_NAME}" --format "table {{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" \
        | head -1  # header

    docker images "${IMAGE_NAME}" --format "{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" \
        | grep -v '^latest$' \
        | sort -r \
        | while IFS=$'\t' read -r tag size created; do
            if [ "$tag" = "latest" ]; then
                continue
            fi
            if [ "$tag" = "$current_tag" ]; then
                echo -e "  ${GREEN}* ${tag}${NC}\t${size}\t${created}  ${GREEN}<- current${NC}"
            else
                echo -e "    ${tag}\t${size}\t${created}"
            fi
        done

    echo ""

    # Show deploy history if available
    if [ -f "$DEPLOY_HISTORY_FILE" ]; then
        echo "Recent deploy history (last 10):"
        tail -10 "$DEPLOY_HISTORY_FILE" | while IFS= read -r line; do
            echo "  $line"
        done
    fi
}

cmd_status() {
    local current_tag
    current_tag="$(get_current_version)"
    info "Current version: ${BLUE}${current_tag}${NC}"
    echo ""

    check_compose_file
    if [ -f "$ENV_FILE" ]; then
        IMAGE_TAG="$current_tag" docker_compose ps
    else
        warn ".env not found, showing raw docker status"
        docker ps --filter "name=sub2api" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    fi
}

cmd_logs() {
    local lines="${1:-100}"
    check_compose_file
    check_env_file

    local current_tag
    current_tag="$(get_current_version)"
    IMAGE_TAG="$current_tag" docker_compose logs -f --tail "$lines" sub2api
}

cmd_cleanup() {
    local keep="${1:-5}"
    info "Cleaning up old images, keeping latest ${keep} versions..."

    # Get all tags except 'latest', sorted newest first
    local tags
    tags="$(docker images "${IMAGE_NAME}" --format "{{.Tag}}" \
        | grep -v '^latest$' \
        | sort -r)"

    local count=0
    local removed=0
    while IFS= read -r tag; do
        [ -z "$tag" ] && continue
        count=$((count + 1))
        if [ "$count" -gt "$keep" ]; then
            info "Removing ${IMAGE_NAME}:${tag}"
            docker rmi "${IMAGE_NAME}:${tag}" 2>/dev/null || warn "Failed to remove ${tag} (may be in use)"
            removed=$((removed + 1))
        fi
    done <<< "$tags"

    if [ "$removed" -eq 0 ]; then
        info "Nothing to clean up (${count} images, keeping ${keep})"
    else
        info "Removed ${removed} old image(s)"
    fi
}

cmd_stop() {
    check_compose_file
    check_env_file
    local current_tag
    current_tag="$(get_current_version)"
    info "Stopping all services..."
    IMAGE_TAG="$current_tag" docker_compose down
    info "All services stopped."
}

cmd_restart() {
    check_compose_file
    check_env_file
    local current_tag
    current_tag="$(get_current_version)"
    info "Restarting all services..."
    IMAGE_TAG="$current_tag" docker_compose restart
    info "All services restarted."
}

cmd_help() {
    cat <<'HELP'
Sub2API Deployment Script

Usage: ./deploy.sh <command> [args]

Commands:
  build              Build image from current source code
  deploy             Deploy using the latest built image
  up                 Build + deploy in one step
  rollback [tag]     Rollback to previous or specified version (instant)
  list               List all available local image versions
  status             Show current running version and container status
  logs [lines]       Show application logs (default: 100 lines, follow mode)
  cleanup [N]        Remove old images, keep latest N (default: 5)
  stop               Stop all services
  restart            Restart all services
  help               Show this help message

Examples:
  ./deploy.sh up                   # First-time or regular deployment
  ./deploy.sh rollback             # Rollback to previous version (instant)
  ./deploy.sh rollback 20260522-143052-a1b2c3d   # Rollback to specific version
  ./deploy.sh list                 # See all available versions
  ./deploy.sh cleanup 3            # Keep only last 3 versions

Workflow:
  1. cp .env.example .env && vim .env   # First-time setup
  2. ./deploy.sh up                     # Build & deploy
  3. git pull && ./deploy.sh up         # Update to latest code
  4. ./deploy.sh rollback               # Oops, rollback instantly
HELP
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        build)    cmd_build "$@" ;;
        deploy)   cmd_deploy "$@" ;;
        up)       cmd_up "$@" ;;
        rollback) cmd_rollback "${1:-}" ;;
        list)     cmd_list "$@" ;;
        status)   cmd_status "$@" ;;
        logs)     cmd_logs "${1:-}" ;;
        cleanup)  cmd_cleanup "${1:-}" ;;
        stop)     cmd_stop "$@" ;;
        restart)  cmd_restart "$@" ;;
        help|--help|-h) cmd_help ;;
        *)
            error "Unknown command: $command"
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
