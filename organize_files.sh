#!/bin/bash

# Script to organize multimedia files in year/month structure
# Usage: ./organize_files.sh /path/to/source /path/to/destination [--dry-run]

SOURCE_DIR=""
DEST_DIR=""
DRY_RUN=false

# Parse parameters
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            if [ -z "$SOURCE_DIR" ]; then
                SOURCE_DIR="$1"
            elif [ -z "$DEST_DIR" ]; then
                DEST_DIR="$1"
            else
                echo "Error: Too many parameters"
                echo "Usage: $0 <source_directory> <destination_directory> [--dry-run]"
                exit 1
            fi
            shift
            ;;
    esac
done

# Check that required parameters have been provided
if [ -z "$SOURCE_DIR" ] || [ -z "$DEST_DIR" ]; then
    echo "Usage: $0 <source_directory> <destination_directory> [--dry-run]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Simulate execution without making real changes"
    exit 1
fi

# Check that directories exist
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory not found: $SOURCE_DIR"
    exit 1
fi

# Create destination directory if it doesn't exist
if [ "$DRY_RUN" = false ]; then
    mkdir -p "$DEST_DIR"
fi

# Counters for statistics
MOVED=0
SKIPPED=0
ERRORS=0
DUPLICATES_FOUND=0

# Array to track duplicates
declare -a DUPLICATE_FILES

# Checkpoint files for intelligent restart
CHECKPOINT_FILE="/tmp/organize_files_checkpoint_$$"
PROCESSED_FILES_LOG="/tmp/organize_files_processed_$$"

# Hash cache for improved duplicate detection
HASH_CACHE_FILE="/tmp/organize_files_hashes_$$"
declare -A FILE_HASHES

# Function to calculate file hash
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

# Function to get or calculate file hash with caching
get_file_hash() {
    local file_path="$1"
    local file_size file_mtime hash_key cached_hash
    
    if [ ! -f "$file_path" ]; then
        echo ""
        return 1
    fi
    
    # Create hash key based on path, size, and modification time
    file_size=$(stat -c %s "$file_path" 2>/dev/null)
    file_mtime=$(stat -c %Y "$file_path" 2>/dev/null)
    hash_key="${file_path}:${file_size}:${file_mtime}"
    
    # Check if hash is already cached
    if [ -n "${FILE_HASHES[$hash_key]}" ]; then
        echo "${FILE_HASHES[$hash_key]}"
        return 0
    fi
    
    # Calculate new hash
    local file_hash
    file_hash=$(calculate_file_hash "$file_path")
    
    if [ -n "$file_hash" ]; then
        # Cache the hash
        FILE_HASHES[$hash_key]="$file_hash"
        echo "$file_hash"
        return 0
    else
        echo ""
        return 1
    fi
}

# Function to load hash cache from file
load_hash_cache() {
    if [ -f "$HASH_CACHE_FILE" ] && [ "$DRY_RUN" = false ]; then
        while IFS='=' read -r key value; do
            if [ -n "$key" ] && [ -n "$value" ]; then
                FILE_HASHES[$key]="$value"
            fi
        done < "$HASH_CACHE_FILE"
    fi
}

# Function to save hash cache to file
save_hash_cache() {
    if [ "$DRY_RUN" = false ]; then
        > "$HASH_CACHE_FILE"
        for key in "${!FILE_HASHES[@]}"; do
            echo "${key}=${FILE_HASHES[$key]}" >> "$HASH_CACHE_FILE"
        done
    fi
}

# Function to find duplicates by hash in destination directory
find_duplicate_by_hash() {
    local source_file="$1"
    local source_hash="$2"
    local search_dir="$3"
    
    if [ -z "$source_hash" ] || [ ! -d "$search_dir" ]; then
        echo ""
        return 1
    fi
    
    # Search for files with same hash in destination
    find "$search_dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.mkv" -o -iname "*.wmv" -o -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" \) -print0 | while IFS= read -r -d '' existing_file; do
        local existing_hash
        existing_hash=$(get_file_hash "$existing_file")
        
        if [ "$existing_hash" = "$source_hash" ]; then
            echo "$existing_file"
            return 0
        fi
    done
    
    echo ""
    return 1
}

# Function to check if two files are duplicates using size and hash
are_files_duplicate() {
    local file1="$1"
    local file2="$2"
    
    if [ ! -f "$file1" ] || [ ! -f "$file2" ]; then
        return 1
    fi
    
    # Quick size check first
    local size1 size2
    size1=$(stat -c %s "$file1" 2>/dev/null)
    size2=$(stat -c %s "$file2" 2>/dev/null)
    
    if [ "$size1" != "$size2" ]; then
        return 1  # Different sizes, definitely not duplicates
    fi
    
    # If sizes match, compare hashes
    local hash1 hash2
    hash1=$(get_file_hash "$file1")
    hash2=$(get_file_hash "$file2")
    
    if [ -n "$hash1" ] && [ -n "$hash2" ] && [ "$hash1" = "$hash2" ]; then
        return 0  # Files are duplicates
    else
        return 1  # Files are different or hash calculation failed
    fi
}

# Function to load existing checkpoint
load_checkpoint() {
    if [ -f "$CHECKPOINT_FILE" ] && [ "$DRY_RUN" = false ]; then
        echo "=========================================="
        echo "CHECKPOINT FOUND - LOADING DATA"
        echo "=========================================="
        source "$CHECKPOINT_FILE"
        echo "Loaded previous session data:"
        echo "- Files already moved: $MOVED"
        echo "- Files already skipped: $SKIPPED"  
        echo "- Duplicates already found: $DUPLICATES_FOUND"
        echo "- Previous errors: $ERRORS"
        echo ""
        
        if [ -f "$PROCESSED_FILES_LOG" ]; then
            processed_count=$(wc -l < "$PROCESSED_FILES_LOG")
            echo "- Files already processed: $processed_count"
            echo ""
            echo "Resuming processing..."
        fi
        
        # Load hash cache for improved duplicate detection
        load_hash_cache
        if [ -f "$HASH_CACHE_FILE" ]; then
            cached_hashes=$(wc -l < "$HASH_CACHE_FILE")
            echo "- Cached file hashes loaded: $cached_hashes"
        fi
        
        echo "----------------------------------------"
    elif [ -f "$CHECKPOINT_FILE" ] && [ "$DRY_RUN" = true ]; then
        echo "ℹ️  Existing checkpoint ignored in dry-run mode"
    fi
}

# Function to save checkpoint
save_checkpoint() {
    if [ "$DRY_RUN" = false ]; then
        cat > "$CHECKPOINT_FILE" << EOF
MOVED=$MOVED
SKIPPED=$SKIPPED
ERRORS=$ERRORS
DUPLICATES_FOUND=$DUPLICATES_FOUND
declare -a DUPLICATE_FILES=($(printf "'%s' " "${DUPLICATE_FILES[@]}"))
EOF
        
        # Also save hash cache for performance
        save_hash_cache
    fi
}

# Function to check if a file has already been processed
is_file_processed() {
    local file_path="$1"
    if [ -f "$PROCESSED_FILES_LOG" ] && [ "$DRY_RUN" = false ]; then
        grep -Fxq "$file_path" "$PROCESSED_FILES_LOG" 2>/dev/null
    else
        return 1  # File not processed
    fi
}

# Function to mark a file as processed
mark_file_processed() {
    local file_path="$1"
    if [ "$DRY_RUN" = false ]; then
        echo "$file_path" >> "$PROCESSED_FILES_LOG"
    fi
}

# Handle interruptions (Ctrl+C)
cleanup() {
    echo ""
    echo "=========================================="
    echo "INTERRUPTION DETECTED - SAVING STATE"
    echo "=========================================="
    
    # Save final checkpoint
    save_checkpoint
    
    echo "Operation interrupted by user"
    echo ""
    echo "PARTIAL STATISTICS:"
    echo "- Files processed before interruption: $((MOVED + SKIPPED + ERRORS + DUPLICATES_FOUND))"
    echo "- Files moved successfully: $MOVED"
    echo "- Files skipped: $SKIPPED"
    echo "- Duplicate files found and renamed: $DUPLICATES_FOUND"
    echo "- Errors: $ERRORS"
    
    if [ ${#DUPLICATE_FILES[@]} -gt 0 ]; then
        echo ""
        echo "DUPLICATE FILES FOUND AND RENAMED:"
        for dup_file in "${DUPLICATE_FILES[@]}"; do
            echo "  • $dup_file"
        done
    fi
    
    echo ""
    echo "📁 Checkpoint saved to: $CHECKPOINT_FILE"
    echo "📝 Processed files log: $PROCESSED_FILES_LOG"
    echo ""
    echo "To resume from interruption point, run again:"
    echo "$0 \"$SOURCE_DIR\" \"$DEST_DIR\""
    echo ""
    echo "To restart from scratch, first delete checkpoint files:"
    echo "rm -f \"$CHECKPOINT_FILE\" \"$PROCESSED_FILES_LOG\" \"$HASH_CACHE_FILE\""
    
    exit 1
}

# Capture interruption signals
trap cleanup INT TERM

# Dry-run mode
if [ "$DRY_RUN" = true ]; then
    echo "=== DRY-RUN MODE ACTIVE ==="
    echo "No changes will be made"
    echo ""
fi

echo "Starting file organization from $SOURCE_DIR to $DEST_DIR"
echo "Recursive scanning of all subdirectories..."
echo "Excluding files with pattern *_DUP.*"
echo "----------------------------------------"

# Load checkpoint if existing
load_checkpoint

# Load hash cache for improved duplicate detection (if not already loaded by checkpoint)
if [ "${#FILE_HASHES[@]}" -eq 0 ]; then
    load_hash_cache
    if [ -f "$HASH_CACHE_FILE" ] && [ "$DRY_RUN" = false ]; then
        cached_hashes=$(wc -l < "$HASH_CACHE_FILE")
        echo "Hash cache loaded: $cached_hashes entries"
        echo "----------------------------------------"
    fi
fi

# Count files to process
echo "Counting files to process..."
total_files_to_process=$(find "$SOURCE_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.mkv" -o -iname "*.wmv" -o -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" \) ! -name "*_DUP.*" | wc -l)

excluded_files=$(find "$SOURCE_DIR" -type f -name "*_DUP.*" | wc -l)

echo "Multimedia files found: $total_files_to_process"
if [ "$excluded_files" -gt 0 ]; then
    echo "Files _DUP.* excluded: $excluded_files"
fi
echo "----------------------------------------"

# Create array with all files to process (avoids pipe subshell)
echo "Creating list of files to process..."
mapfile -t files_array < <(find "$SOURCE_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.mkv" -o -iname "*.wmv" -o -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" \) ! -name "*_DUP.*")

echo "Starting processing of ${#files_array[@]} files..."
echo "----------------------------------------"

# Process each file in array (NOT in subshell)
for file in "${files_array[@]}"; do
    
    # Check if file has already been processed
    if is_file_processed "$file"; then
        if [ "$DRY_RUN" = false ]; then
            # In normal mode, skip already processed files silently
            continue
        fi
    fi
    
    filename=$(basename "$file")
    relative_path="${file#$SOURCE_DIR/}"
    echo "Processing: $relative_path"
    
    # Extract date from filename - various formats with prefixes/suffixes
    year=""
    month=""
    
    # Format: [prefix_]YYYY-MM-DD[_suffix] or [prefix_]YYYY_MM_DD[_suffix] or [prefix_]YYYYMMDD[_suffix]
    if [[ $filename =~ ([^0-9]*)([0-9]{4})[-_]?([0-9]{2})[-_]?([0-9]{2})(.*)$ ]]; then
        year="${BASH_REMATCH[2]}"
        month="${BASH_REMATCH[3]}"
        echo "  Date found (YYYY-MM-DD): $year-$month"
    # Format: [prefix_]DD-MM-YYYY[_suffix] or [prefix_]DD_MM_YYYY[_suffix] or [prefix_]DD/MM/YYYY[_suffix]
    elif [[ $filename =~ ([^0-9]*)([0-9]{1,2})[-_/]([0-9]{1,2})[-_/]([0-9]{4})(.*)$ ]]; then
        potential_year="${BASH_REMATCH[4]}"
        potential_month="${BASH_REMATCH[3]}"
        # Remove leading zeros and ensure month is valid (01-12)
        potential_month=$((10#$potential_month))
        if [ "$potential_month" -ge 1 ] && [ "$potential_month" -le 12 ]; then
            year="$potential_year"
            month=$(printf "%02d" $potential_month)
            echo "  Date found (DD-MM-YYYY): $year-$month"
        else
            year=""
            month=""
        fi
    # Format: [prefix_]MM-DD-YYYY[_suffix] (American format)
    elif [[ $filename =~ ([^0-9]*)([0-9]{1,2})[-_/]([0-9]{1,2})[-_/]([0-9]{4})(.*)$ ]]; then
        potential_year="${BASH_REMATCH[4]}"
        potential_month="${BASH_REMATCH[2]}"
        # Remove leading zeros and ensure month is valid (01-12)
        potential_month=$((10#$potential_month))
        if [ "$potential_month" -ge 1 ] && [ "$potential_month" -le 12 ]; then
            year="$potential_year"
            month=$(printf "%02d" $potential_month)
            echo "  Date found (MM-DD-YYYY): $year-$month"
        else
            year=""
            month=""
        fi
    # Format with timestamp: [prefix_]YYYY[MM[DD[_HHMMSS]]][_suffix]
    elif [[ $filename =~ ([^0-9]*)([0-9]{4})([0-9]{2})([0-9]{2})[^0-9]*(.*) ]]; then
        year="${BASH_REMATCH[2]}"
        month="${BASH_REMATCH[3]}"
        echo "  Date found (YYYYMMDD): $year-$month"
    # ISO format with prefix/suffix: [prefix_]YYYY[MM][_suffix]
    elif [[ $filename =~ ([^0-9]*)([0-9]{4})[^0-9]*([0-9]{2})[^0-9]*(.*) ]]; then
        potential_year="${BASH_REMATCH[2]}"
        potential_month="${BASH_REMATCH[3]}"
        # Remove leading zeros and validate month
        potential_month=$((10#$potential_month))
        if [ "$potential_month" -ge 1 ] && [ "$potential_month" -le 12 ]; then
            year="$potential_year"
            month=$(printf "%02d" $potential_month)
            echo "  Date found (YYYY-MM): $year-$month"
        fi
    fi
    
    # If unable to extract date, try file metadata
    if [ -z "$year" ] || [ -z "$month" ]; then
        # Use exiftool if available (only if not in dry-run or for testing)
        if command -v exiftool >/dev/null 2>&1 && [ "$DRY_RUN" = false ]; then
            date_taken=$(exiftool -DateTimeOriginal -d "%Y-%m" -T "$file" 2>/dev/null)
            if [ -n "$date_taken" ] && [ "$date_taken" != "-" ]; then
                year=$(echo "$date_taken" | cut -d'-' -f1)
                month=$(echo "$date_taken" | cut -d'-' -f2)
                echo "  Date from EXIF metadata: $year-$month"
            fi
        elif [ "$DRY_RUN" = true ]; then
            echo "  [DRY-RUN] Would try to extract date from EXIF metadata"
        fi
        
        # If still no date, use file modification date
        if [ -z "$year" ] || [ -z "$month" ]; then
            if [ "$DRY_RUN" = false ]; then
                file_date=$(stat -c %Y "$file")
                year=$(date -d "@$file_date" +%Y)
                month=$(date -d "@$file_date" +%m)
            else
                # In dry-run, simulate modification date
                year=$(date +%Y)
                month=$(date +%m)
            fi
            echo "  Using modification date: $year-$month"
        fi
    fi
    
    # Validate year and month
    if [ -n "$year" ] && [ -n "$month" ] && [ "$year" -ge 1990 ] && [ "$year" -le $(date +%Y) ]; then
        # Remove leading zeros from month to avoid octal printf issues
        month_num=$((10#$month))
        if [ "$month_num" -ge 1 ] && [ "$month_num" -le 12 ]; then
            # Create destination directory
            month_formatted=$(printf "%02d" $month_num)
            dest_dir="$DEST_DIR/$year/$month_formatted"
            
            if [ "$DRY_RUN" = false ]; then
                mkdir -p "$dest_dir"
            else
                echo "  [DRY-RUN] Would create directory: $dest_dir"
            fi
            
            dest_file="$dest_dir/$filename"
            
            # CRITICAL CHECK: Verify if file is already in correct position
            if [ "$DRY_RUN" = false ]; then
                source_real=$(realpath "$file" 2>/dev/null)
                dest_real=$(realpath "$dest_file" 2>/dev/null)
                
                # If real paths are identical, file is already in right place
                if [ -n "$source_real" ] && [ -n "$dest_real" ] && [ "$source_real" = "$dest_real" ]; then
                    echo "  File already in correct position, skipped"
                    ((SKIPPED++))
                    mark_file_processed "$file"
                    save_checkpoint
                    continue
                fi
            fi
            
            # Advanced duplicate detection using hash comparison
            source_hash=""
            duplicate_found=false
            duplicate_location=""
            
            if [ "$DRY_RUN" = false ]; then
                # Calculate hash of source file
                source_hash=$(get_file_hash "$file")
                
                if [ -n "$source_hash" ]; then
                    # First check if identical file already exists in exact destination
                    if [ -f "$dest_file" ]; then
                        if are_files_duplicate "$file" "$dest_file"; then
                            duplicate_found=true
                            duplicate_location="$dest_file"
                            echo "  Identical file found in exact destination: $(basename "$dest_file")"
                        fi
                    fi
                    
                    # If not found in exact location, search entire destination directory for duplicates
                    if [ "$duplicate_found" = false ]; then
                        echo "  Scanning destination directory for duplicates..."
                        duplicate_file=$(find_duplicate_by_hash "$file" "$source_hash" "$DEST_DIR")
                        if [ -n "$duplicate_file" ]; then
                            duplicate_found=true
                            duplicate_location="$duplicate_file"
                            echo "  Duplicate found elsewhere in destination: $duplicate_file"
                        fi
                    fi
                fi
            else
                # In dry-run, simulate duplicate detection for demo
                if (( RANDOM % 6 == 0 )); then  # ~17% probability of finding duplicate
                    duplicate_found=true
                    if [ -f "$dest_file" ]; then
                        duplicate_location="$dest_file"
                        echo "  [DRY-RUN] Would find identical file in exact destination"
                    else
                        duplicate_location="$DEST_DIR/$(date +%Y)/$(printf "%02d" $((1 + RANDOM % 12)))/simulated_duplicate.jpg"
                        echo "  [DRY-RUN] Would find duplicate elsewhere in destination"
                    fi
                fi
            fi
            
            # Handle duplicate files
            if [ "$duplicate_found" = true ]; then
                echo "  Duplicate file detected - renaming source with _DUP suffix"
                base_name="${filename%.*}"
                extension="${filename##*.}"
                
                # Find free name for duplicate in source directory
                dup_counter=1
                dup_name="${base_name}_DUP"
                if [ -n "$extension" ]; then
                    dup_filename="${dup_name}.$extension"
                else
                    dup_filename="$dup_name"
                fi
                
                dup_path="$(dirname "$file")/$dup_filename"
                
                if [ "$DRY_RUN" = false ]; then
                    while [ -f "$dup_path" ]; do
                        dup_name="${base_name}_DUP$dup_counter"
                        if [ -n "$extension" ]; then
                            dup_filename="${dup_name}.$extension"
                        else
                            dup_filename="$dup_name"
                        fi
                        dup_path="$(dirname "$file")/$dup_filename"
                        ((dup_counter++))
                    done
                    
                    # Rename file in source directory
                    if mv "$file" "$dup_path"; then
                        echo "  File renamed as duplicate: $dup_filename"
                        echo "  Original duplicate is at: $duplicate_location"
                        DUPLICATE_FILES+=("$dup_filename")
                        ((DUPLICATES_FOUND++))
                        mark_file_processed "$file"
                        save_checkpoint
                    else
                        echo "  ERROR renaming duplicate"
                        ((ERRORS++))
                        mark_file_processed "$file"
                        save_checkpoint
                    fi
                else
                    echo "  [DRY-RUN] Would rename file as duplicate: $dup_filename"
                    echo "  [DRY-RUN] Original would be at: $duplicate_location"
                    DUPLICATE_FILES+=("$dup_filename")
                    ((DUPLICATES_FOUND++))
                fi
                continue
            fi
            
            # Check if destination file exists but is different (handle name conflicts)
            if [ -f "$dest_file" ] && [ "$duplicate_found" = false ]; then
                counter=1
                base_name="${filename%.*}"
                extension="${filename##*.}"
                
                if [ "$DRY_RUN" = false ]; then
                    while [ -f "$dest_dir/${base_name}_$counter.$extension" ]; do
                        ((counter++))
                    done
                fi
                
                dest_file="$dest_dir/${base_name}_$counter.$extension"
                echo "  Different file with same name, creating: ${base_name}_$counter.$extension"
                if [ "$DRY_RUN" = true ]; then
                    echo "  [DRY-RUN] Would create file with modified name"
                fi
            fi
            
            # Move the file
            if [ "$DRY_RUN" = false ]; then
                if mv "$file" "$dest_file"; then
                    echo "  Moved to: $dest_dir/"
                    ((MOVED++))
                    mark_file_processed "$file"
                    save_checkpoint
                else
                    echo "  ERROR in movement"
                    ((ERRORS++))
                    mark_file_processed "$file"
                    save_checkpoint
                fi
            else
                echo "  [DRY-RUN] Would move to: $dest_dir/"
                ((MOVED++))
            fi
        else
            echo "  Invalid date extracted: $year-$month_formatted, skipped"
            if [ "$DRY_RUN" = true ]; then
                echo "  [DRY-RUN] File would not be moved"
            fi
            ((SKIPPED++))
            mark_file_processed "$file"
            if [ "$DRY_RUN" = false ]; then
                save_checkpoint
            fi
        fi
    else
        echo "  Invalid date extracted: $year-$month, skipped"
        if [ "$DRY_RUN" = true ]; then
            echo "  [DRY-RUN] File would not be moved"
        fi
        ((SKIPPED++))
        mark_file_processed "$file"
        if [ "$DRY_RUN" = false ]; then
            save_checkpoint
        fi
    fi
    
    echo ""
    
    # Show progress every 50 processed files
    total_processed=$((MOVED + SKIPPED + ERRORS + DUPLICATES_FOUND))
    if (( total_processed % 50 == 0 )) && (( total_processed > 0 )); then
        echo "--- PROGRESS: $total_processed files processed ---"
        echo "    (Moved: $MOVED | Skipped: $SKIPPED | Duplicates: $DUPLICATES_FOUND | Errors: $ERRORS)"
    fi
done

echo "----------------------------------------"

# Final report
if [ "$DRY_RUN" = true ]; then
    echo "=== DRY-RUN REPORT COMPLETED ==="
    echo ""
    echo "SIMULATION SUMMARY:"
    echo "- Files that would be moved: $MOVED"
    echo "- Files that would be skipped: $SKIPPED"
    echo "- Duplicate files that would be renamed: $DUPLICATES_FOUND"
    echo "- Errors that would occur: $ERRORS"
    echo "- Total files that would be processed: $((MOVED + SKIPPED + DUPLICATES_FOUND + ERRORS))"
    
    if [ ${#DUPLICATE_FILES[@]} -gt 0 ]; then
        echo ""
        echo "DUPLICATE FILES THAT WOULD BE RENAMED:"
        for dup_file in "${DUPLICATE_FILES[@]}"; do
            echo "  • $dup_file"
        done
    fi
    
    echo ""
    echo "DIRECTORY STRUCTURE THAT WOULD BE CREATED:"
    
    # Simulate directory structure that would be created
    temp_structure="/tmp/dry_run_structure_$$"
    find "$SOURCE_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.mkv" -o -iname "*.wmv" -o -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" \) ! -name "*_DUP.*" | while read -r file; do
        filename=$(basename "$file")
        
        # Repeat date extraction logic (simplified version)
        year=""
        month=""
        
        if [[ $filename =~ ([^0-9]*)([0-9]{4})[-_]?([0-9]{2})[-_]?([0-9]{2})(.*)$ ]]; then
            year="${BASH_REMATCH[2]}"
            month="${BASH_REMATCH[3]}"
        elif [[ $filename =~ ([^0-9]*)([0-9]{1,2})[-_/]([0-9]{1,2})[-_/]([0-9]{4})(.*)$ ]]; then
            potential_year="${BASH_REMATCH[4]}"
            potential_month="${BASH_REMATCH[3]}"
            potential_month=$((10#$potential_month))
            if [ "$potential_month" -ge 1 ] && [ "$potential_month" -le 12 ]; then
                year="$potential_year"
                month=$(printf "%02d" $potential_month)
            else
                potential_month="${BASH_REMATCH[2]}"
                potential_month=$((10#$potential_month))
                if [ "$potential_month" -ge 1 ] && [ "$potential_month" -le 12 ]; then
                    year="$potential_year"
                    month=$(printf "%02d" $potential_month)
                fi
            fi
        elif [[ $filename =~ ([^0-9]*)([0-9]{4})([0-9]{2})([0-9]{2})[^0-9]*(.*) ]]; then
            year="${BASH_REMATCH[2]}"
            month="${BASH_REMATCH[3]}"
        elif [[ $filename =~ ([^0-9]*)([0-9]{4})[^0-9]*([0-9]{2})[^0-9]*(.*) ]]; then
            potential_year="${BASH_REMATCH[2]}"
            potential_month="${BASH_REMATCH[3]}"
            potential_month=$((10#$potential_month))
            if [ "$potential_month" -ge 1 ] && [ "$potential_month" -le 12 ]; then
                year="$potential_year"
                month=$(printf "%02d" $potential_month)
            fi
        fi
        
        if [ -n "$year" ] && [ -n "$month" ] && [ "$year" -ge 1990 ] && [ "$year" -le $(date +%Y) ]; then
            month_num=$((10#$month))
            if [ "$month_num" -ge 1 ] && [ "$month_num" -le 12 ]; then
                month_formatted=$(printf "%02d" $month_num)
                echo "$year/$month_formatted" >> "$temp_structure"
            fi
        fi
    done
    
    if [ -f "$temp_structure" ]; then
        sort "$temp_structure" | uniq | while read -r dir_path; do
            echo "$DEST_DIR/$dir_path/"
        done
        rm -f "$temp_structure"
    fi
    
    echo ""
    echo "To actually execute changes, run again without --dry-run:"
    echo "$0 \"$SOURCE_DIR\" \"$DEST_DIR\""
    
else
    echo "=========================================="
    echo "ORGANIZATION COMPLETED SUCCESSFULLY!"
    echo "=========================================="
    echo ""
    echo "FINAL STATISTICS:"
    echo "- Files moved successfully: $MOVED"
    echo "- Files skipped (invalid date or already positioned): $SKIPPED" 
    echo "- Duplicate files found and renamed: $DUPLICATES_FOUND"
    echo "- Errors occurred: $ERRORS"
    echo "- Total files processed: $((MOVED + SKIPPED + ERRORS + DUPLICATES_FOUND))"
    
    # Calculate percentages if there are processed files
    total_files=$((MOVED + SKIPPED + ERRORS + DUPLICATES_FOUND))
    if [ "$total_files" -gt 0 ]; then
        moved_percent=$(( MOVED * 100 / total_files ))
        duplicates_percent=$(( DUPLICATES_FOUND * 100 / total_files ))
        echo ""
        echo "PERCENTAGES:"
        echo "- Files moved correctly: ${moved_percent}%"
        if [ "$DUPLICATES_FOUND" -gt 0 ]; then
            echo "- Duplicate files found: ${duplicates_percent}%"
        fi
    fi
    
    if [ ${#DUPLICATE_FILES[@]} -gt 0 ]; then
        echo ""
        echo "📋 DETAIL OF DUPLICATE FILES RENAMED ($DUPLICATES_FOUND total):"
        for dup_file in "${DUPLICATE_FILES[@]}"; do
            echo "  • $dup_file"
        done
        echo ""
        echo "NOTE: Duplicate files remained in source directory"
        echo "      with _DUP suffix to avoid data loss"
    fi
    
    if [ "$ERRORS" -gt 0 ]; then
        echo ""
        echo "⚠️  WARNING: $ERRORS errors occurred during operation"
        echo "   Check messages above for details"
    fi
    
    if [ "$MOVED" -eq 0 ] && [ "$DUPLICATES_FOUND" -eq 0 ]; then
        echo ""
        echo "ℹ️  No files were moved. Possible causes:"
        echo "   • All files have unrecognizable dates"
        echo "   • All files are already in correct destination"
        echo "   • Source directory contains no multimedia files"
        echo "   • All multimedia files have already been renamed with _DUP"
    fi
    
    # Show summary of processed subdirectories
    if [ "$MOVED" -gt 0 ] || [ "$DUPLICATES_FOUND" -gt 0 ]; then
        echo ""
        echo "📁 PROCESSED DIRECTORIES SUMMARY:"
        find "$SOURCE_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.mkv" -o -iname "*.wmv" -o -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" \) ! -name "*_DUP.*" -printf '%h\n' | sort | uniq -c | sort -nr | head -10 | while read count dir; do
            relative_dir="${dir#$SOURCE_DIR}"
            [ -z "$relative_dir" ] && relative_dir="/"
            echo "  $count files from: $relative_dir"
        done
    fi
    
    # Clean checkpoint files upon completion
    if [ -f "$CHECKPOINT_FILE" ]; then
        rm -f "$CHECKPOINT_FILE"
    fi
    if [ -f "$PROCESSED_FILES_LOG" ]; then
        rm -f "$PROCESSED_FILES_LOG"
    fi
    if [ -f "$HASH_CACHE_FILE" ]; then
        rm -f "$HASH_CACHE_FILE"
    fi
    echo ""
    echo "🎉 Checkpoint files cleaned - operation completed!"
fi

# Remove trap at the end
trap - INT TERM