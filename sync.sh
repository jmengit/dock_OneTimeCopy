#!/bin/bash

# One-Time Copy Script
# Copies files from /input to /output exactly once
# Tracks copied files by content hash so they won't be recopied even if renamed or deleted from output

INPUT_DIR="/input"
OUTPUT_DIR="/output"
TRACKING_FILE="/data/copied_files.manifest"
HASH_TRACKING_FILE="/data/copied_hashes.manifest"
LOCK_FILE="/data/sync.lock"

# Configuration from environment variables
SYNC_INTERVAL="${SYNC_INTERVAL:-60}"       # Default: check every 60 seconds
RUN_ONCE="${RUN_ONCE:-false}"               # Default: run continuously
FILE_EXTENSIONS="${FILE_EXTENSIONS:-}"      # Comma-separated list of extensions (e.g., "jpg,png,pdf")
EXTENSION_MODE="${EXTENSION_MODE:-include}" # "include" = only copy these extensions, "exclude" = skip these extensions

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Ensure tracking files exist
init_tracking() {
    if [ ! -f "$TRACKING_FILE" ]; then
        touch "$TRACKING_FILE"
        log_info "Created new tracking file: $TRACKING_FILE"
    fi
    if [ ! -f "$HASH_TRACKING_FILE" ]; then
        touch "$HASH_TRACKING_FILE"
        log_info "Created new hash tracking file: $HASH_TRACKING_FILE"
    fi
}

# Calculate SHA256 hash of a file
get_file_hash() {
    local file="$1"
    sha256sum "$file" 2>/dev/null | cut -d' ' -f1
}

# Check if a file hash has already been copied
is_hash_already_copied() {
    local hash="$1"
    grep -qFx "$hash" "$HASH_TRACKING_FILE" 2>/dev/null
}

# Check if a file path has already been copied (legacy support)
is_path_already_copied() {
    local relative_path="$1"
    grep -qFx "$relative_path" "$TRACKING_FILE" 2>/dev/null
}

# Check if file should be processed based on extension filter
should_process_extension() {
    local file="$1"
    
    # If no extensions specified, process all files
    if [ -z "$FILE_EXTENSIONS" ]; then
        return 0
    fi
    
    # Get file extension (lowercase)
    local filename=$(basename "$file")
    local extension="${filename##*.}"
    extension=$(echo "$extension" | tr '[:upper:]' '[:lower:]')
    
    # If file has no extension
    if [ "$filename" = "$extension" ]; then
        if [ "$EXTENSION_MODE" = "include" ]; then
            return 1  # No extension, and we're in include mode - skip
        else
            return 0  # No extension, and we're in exclude mode - process
        fi
    fi
    
    # Check if extension is in the list
    local ext_list=$(echo "$FILE_EXTENSIONS" | tr '[:upper:]' '[:lower:]')
    local found=false
    
    IFS=',' read -ra EXTS <<< "$ext_list"
    for ext in "${EXTS[@]}"; do
        # Trim whitespace and remove leading dot if present
        ext=$(echo "$ext" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^\.//')
        if [ "$extension" = "$ext" ]; then
            found=true
            break
        fi
    done
    
    if [ "$EXTENSION_MODE" = "include" ]; then
        # Include mode: only process if extension found in list
        if [ "$found" = true ]; then
            return 0
        else
            return 1
        fi
    else
        # Exclude mode: skip if extension found in list
        if [ "$found" = true ]; then
            return 1
        else
            return 0
        fi
    fi
}

# Mark a file as copied (both path and hash)
mark_as_copied() {
    local relative_path="$1"
    local hash="$2"
    echo "$relative_path" >> "$TRACKING_FILE"
    echo "$hash" >> "$HASH_TRACKING_FILE"
}

# Get relative path from input directory
get_relative_path() {
    local full_path="$1"
    echo "${full_path#$INPUT_DIR/}"
}

# Copy a single file
copy_file() {
    local src="$1"
    local relative_path="$2"
    local hash="$3"
    local dest="$OUTPUT_DIR/$relative_path"
    local dest_dir=$(dirname "$dest")
    
    # Create destination directory if needed
    if [ ! -d "$dest_dir" ]; then
        if ! mkdir -p "$dest_dir" 2>&1; then
            local mkdir_error=$(mkdir -p "$dest_dir" 2>&1)
            log_error "Failed to create directory: $dest_dir"
            log_error "mkdir error: $mkdir_error"
            return 1
        fi
        log_debug "Created directory: $dest_dir"
    fi
    
    # Copy the file with error capture
    local cp_error
    if cp_error=$(cp -p "$src" "$dest" 2>&1); then
        mark_as_copied "$relative_path" "$hash"
        log_info "Copied: $relative_path (hash: ${hash:0:12}...)"
        return 0
    else
        log_error "Failed to copy: $relative_path"
        log_error "Source: $src"
        log_error "Destination: $dest"
        log_error "cp error: $cp_error"
        
        # Check if source file is readable
        if [ ! -r "$src" ]; then
            log_error "Source file is not readable"
        fi
        
        # Check destination directory is writable
        if [ ! -w "$dest_dir" ]; then
            log_error "Destination directory is not writable: $dest_dir"
        fi
        
        return 1
    fi
}

# Main sync function
sync_files() {
    local copied_count=0
    local skipped_count=0
    local skipped_ext_count=0
    local error_count=0
    
    log_info "Starting sync scan..."
    
    # Find all files in input directory (recursive)
    while IFS= read -r -d '' file; do
        local relative_path=$(get_relative_path "$file")
        
        # Check extension filter first
        if ! should_process_extension "$file"; then
            ((skipped_ext_count++))
            continue
        fi
        
        # Calculate file hash
        local hash=$(get_file_hash "$file")
        
        if [ -z "$hash" ]; then
            log_error "Could not calculate hash for: $relative_path"
            ((error_count++))
            continue
        fi
        
        # Check if hash has been copied before (handles renames)
        if is_hash_already_copied "$hash"; then
            ((skipped_count++))
        # Also check path for backward compatibility
        elif is_path_already_copied "$relative_path"; then
            ((skipped_count++))
        else
            if copy_file "$file" "$relative_path" "$hash"; then
                ((copied_count++))
            else
                ((error_count++))
            fi
        fi
    done < <(find "$INPUT_DIR" -type f -print0 2>/dev/null)
    
    log_info "Sync complete - Copied: $copied_count, Skipped (already copied): $skipped_count, Skipped (extension filter): $skipped_ext_count, Errors: $error_count"
}

# Cleanup function
cleanup() {
    log_info "Shutting down..."
    rm -f "$LOCK_FILE"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Main execution
main() {
    log_info "============================================"
    log_info "One-Time Copy Service Starting"
    log_info "============================================"
    log_info "Input Directory: $INPUT_DIR"
    log_info "Output Directory: $OUTPUT_DIR"
    log_info "Tracking File: $TRACKING_FILE"
    log_info "Hash Tracking File: $HASH_TRACKING_FILE"
    log_info "Sync Interval: ${SYNC_INTERVAL}s"
    log_info "Run Once Mode: $RUN_ONCE"
    if [ -n "$FILE_EXTENSIONS" ]; then
        log_info "Extension Filter: $FILE_EXTENSIONS"
        log_info "Extension Mode: $EXTENSION_MODE (${EXTENSION_MODE}d extensions)"
    else
        log_info "Extension Filter: None (all files)"
    fi
    log_info "============================================"
    
    # Initialize
    init_tracking
    
    # Create lock file
    echo $$ > "$LOCK_FILE"
    
    if [ "$RUN_ONCE" = "true" ]; then
        # Run once and exit
        sync_files
        log_info "Run once complete. Exiting."
    else
        # Run continuously
        while true; do
            sync_files
            log_info "Sleeping for ${SYNC_INTERVAL} seconds..."
            sleep "$SYNC_INTERVAL"
        done
    fi
}

main
