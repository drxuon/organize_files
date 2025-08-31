#!/bin/bash

# Hash Database Builder for File Organization System
# Usage: ./build_hash_database.sh /path/to/destination [--update|--rebuild]
# This script scans a destination directory and builds/updates a SQLite database
# with file hashes for efficient duplicate detection

DEST_DIR=""
MODE="build"  # build, update, or rebuild

# Parse parameters
while [[ $# -gt 0 ]]; do
    case $1 in
        --update)
            MODE="update"
            shift
            ;;
        --rebuild)
            MODE="rebuild"
            shift
            ;;
        *)
            if [ -z "$DEST_DIR" ]; then
                DEST_DIR="$1"
            else
                echo "Error: Too many parameters"
                echo "Usage: $0 <destination_directory> [--update|--rebuild]"
                exit 1
            fi
            shift
            ;;
    esac
done

# Check required parameters
if [ -z "$DEST_DIR" ]; then
    echo "Usage: $0 <destination_directory> [--update|--rebuild]"
    echo ""
    echo "Modes:"
    echo "  (default)    Build new database or update existing one intelligently"
    echo "  --update     Update existing database with new/modified files only"
    echo "  --rebuild    Delete existing database and rebuild from scratch"
    exit 1
fi

# Check destination directory exists
if [ ! -d "$DEST_DIR" ]; then
    echo "Error: Destination directory not found: $DEST_DIR"
    exit 1
fi

# Database file location
DB_FILE="$DEST_DIR/.file_hashes.db"

echo "Hash Database Builder"
echo "===================="
echo "Destination directory: $DEST_DIR"
echo "Database file: $DB_FILE"
echo "Mode: $MODE"
echo ""

# Function to calculate file hash (same as organize_files.sh)
calculate_file_hash() {
    local file_path="$1"
    if [ ! -f "$file_path" ]; then
        echo ""
        return 1
    fi
    
    # Use SHA256 for reliable duplicate detection
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file_path" 2>/dev/null | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file_path" 2>/dev/null | cut -d' ' -f1
    else
        # Fallback to MD5 if SHA256 not available
        if command -v md5sum >/dev/null 2>&1; then
            md5sum "$file_path" 2>/dev/null | cut -d' ' -f1
        elif command -v md5 >/dev/null 2>&1; then
            md5 -q "$file_path" 2>/dev/null
        else
            echo ""
            return 1
        fi
    fi
}

# Function to initialize database
init_database() {
    local db_file="$1"
    
    sqlite3 "$db_file" << 'EOF'
CREATE TABLE IF NOT EXISTS file_hashes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT UNIQUE NOT NULL,
    file_size INTEGER NOT NULL,
    file_hash TEXT NOT NULL,
    last_modified INTEGER NOT NULL,
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    updated_at INTEGER DEFAULT (strftime('%s', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_file_hash ON file_hashes(file_hash);
CREATE INDEX IF NOT EXISTS idx_file_path ON file_hashes(file_path);
CREATE INDEX IF NOT EXISTS idx_last_modified ON file_hashes(last_modified);

-- Trigger to update updated_at on modifications
CREATE TRIGGER IF NOT EXISTS update_timestamp 
    AFTER UPDATE ON file_hashes
    FOR EACH ROW 
    BEGIN
        UPDATE file_hashes SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
    END;
EOF
    
    echo "Database initialized: $db_file"
}

# Function to check if file needs hash update
needs_hash_update() {
    local file_path="$1"
    local db_file="$2"
    
    if [ ! -f "$file_path" ]; then
        return 1  # File doesn't exist, skip
    fi
    
    local file_size file_mtime
    file_size=$(stat -c %s "$file_path" 2>/dev/null)
    file_mtime=$(stat -c %Y "$file_path" 2>/dev/null)
    
    # Check if file exists in database with current size and modification time
    local db_mtime
    db_mtime=$(sqlite3 "$db_file" "SELECT last_modified FROM file_hashes WHERE file_path = '$file_path' AND file_size = $file_size;" 2>/dev/null)
    
    if [ -z "$db_mtime" ]; then
        return 0  # File not in database or size changed, needs update
    fi
    
    if [ "$file_mtime" -gt "$db_mtime" ]; then
        return 0  # File modified after last hash calculation
    fi
    
    return 1  # File up to date
}

# Function to add or update file hash in database
update_file_hash() {
    local file_path="$1"
    local db_file="$2"
    
    if [ ! -f "$file_path" ]; then
        return 1
    fi
    
    local file_size file_mtime file_hash
    file_size=$(stat -c %s "$file_path" 2>/dev/null)
    file_mtime=$(stat -c %Y "$file_path" 2>/dev/null)
    
    echo -n "  Processing: $(basename "$file_path")... "
    
    file_hash=$(calculate_file_hash "$file_path")
    if [ -z "$file_hash" ]; then
        echo "FAILED (hash calculation)"
        return 1
    fi
    
    # Use INSERT OR REPLACE for upsert operation
    sqlite3 "$db_file" << EOF
INSERT OR REPLACE INTO file_hashes (file_path, file_size, file_hash, last_modified)
VALUES ('$file_path', $file_size, '$file_hash', $file_mtime);
EOF
    
    if [ $? -eq 0 ]; then
        echo "OK"
        return 0
    else
        echo "FAILED (database)"
        return 1
    fi
}

# Function to clean up removed files from database
cleanup_database() {
    local db_file="$1"
    
    echo "Cleaning up removed files from database..."
    
    # Get all file paths from database
    local temp_file="/tmp/db_cleanup_$$"
    sqlite3 "$db_file" "SELECT file_path FROM file_hashes;" > "$temp_file"
    
    local removed_count=0
    while IFS= read -r file_path; do
        if [ -n "$file_path" ] && [ ! -f "$file_path" ]; then
            sqlite3 "$db_file" "DELETE FROM file_hashes WHERE file_path = '$file_path';"
            echo "  Removed: $file_path"
            ((removed_count++))
        fi
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    if [ "$removed_count" -eq 0 ]; then
        echo "  No removed files found"
    else
        echo "  Removed $removed_count obsolete entries"
    fi
    
    # Vacuum database to reclaim space
    echo "Optimizing database..."
    sqlite3 "$db_file" "VACUUM;"
}

# Handle rebuild mode
if [ "$MODE" = "rebuild" ]; then
    if [ -f "$DB_FILE" ]; then
        echo "Removing existing database..."
        rm -f "$DB_FILE"
    fi
    MODE="build"
fi

# Initialize database
init_database "$DB_FILE"

# Count total multimedia files
echo "Scanning directory for multimedia files..."
total_files=$(find "$DEST_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.mkv" -o -iname "*.wmv" -o -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" \) | wc -l)

echo "Found $total_files multimedia files"
echo ""

# Process files
processed=0
updated=0
errors=0

echo "Processing files..."
echo "==================="

find "$DEST_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.mkv" -o -iname "*.wmv" -o -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" \) -print0 | while IFS= read -r -d '' file; do
    ((processed++))
    
    # Show progress every 100 files
    if (( processed % 100 == 0 )); then
        echo "--- Progress: $processed/$total_files files processed ---"
    fi
    
    # Check if file needs update (skip if in update mode and file is current)
    if [ "$MODE" = "update" ] && ! needs_hash_update "$file" "$DB_FILE"; then
        continue
    fi
    
    # Update file hash
    if update_file_hash "$file" "$DB_FILE"; then
        ((updated++))
    else
        ((errors++))
    fi
done

# Clean up database (remove entries for deleted files)
cleanup_database "$DB_FILE"

# Final statistics
echo ""
echo "Database build completed!"
echo "========================"
echo "Total files processed: $processed"
echo "Files updated in database: $updated"
echo "Errors: $errors"

# Database statistics
db_entries=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM file_hashes;" 2>/dev/null)
echo "Total database entries: $db_entries"

# Database file size
db_size=$(du -h "$DB_FILE" 2>/dev/null | cut -f1)
echo "Database file size: $db_size"

echo ""
echo "Database location: $DB_FILE"
echo ""
echo "To maintain the database, you can:"
echo "  - Schedule this script with --update in cron"
echo "  - Run --rebuild periodically for full refresh"
echo ""
echo "Example cron entry (daily at 2 AM):"
echo "0 2 * * * $0 \"$DEST_DIR\" --update"