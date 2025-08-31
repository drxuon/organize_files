#!/bin/bash

# Hash Database Management Tool for File Organization System
# Usage: ./manage_hash_database.sh /path/to/destination <command>
# Commands: info, cleanup, vacuum, stats, verify

DEST_DIR=""
COMMAND=""

# Parse parameters
while [[ $# -gt 0 ]]; do
    case $1 in
        info|cleanup|vacuum|stats|verify)
            COMMAND="$1"
            shift
            ;;
        *)
            if [ -z "$DEST_DIR" ]; then
                DEST_DIR="$1"
            else
                echo "Error: Too many parameters"
                echo "Usage: $0 <destination_directory> <command>"
                exit 1
            fi
            shift
            ;;
    esac
done

# Check required parameters
if [ -z "$DEST_DIR" ] || [ -z "$COMMAND" ]; then
    echo "Hash Database Management Tool"
    echo "============================="
    echo ""
    echo "Usage: $0 <destination_directory> <command>"
    echo ""
    echo "Commands:"
    echo "  info     - Show database information and statistics"
    echo "  cleanup  - Remove entries for files that no longer exist"
    echo "  vacuum   - Optimize database and reclaim space"
    echo "  stats    - Show detailed database statistics"
    echo "  verify   - Verify database integrity and check for issues"
    echo ""
    echo "Examples:"
    echo "  $0 /media/photos info"
    echo "  $0 /media/photos cleanup"
    echo "  $0 /media/photos vacuum"
    exit 1
fi

# Check destination directory exists
if [ ! -d "$DEST_DIR" ]; then
    echo "Error: Destination directory not found: $DEST_DIR"
    exit 1
fi

# Database file location
DB_FILE="$DEST_DIR/.file_hashes.db"

# Check if database exists
if [ ! -f "$DB_FILE" ]; then
    echo "Error: Hash database not found at $DB_FILE"
    echo "Run build_hash_database.sh first to create the database"
    exit 1
fi

# Check if sqlite3 is available
if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "Error: sqlite3 not found. Please install sqlite3 to manage the database."
    exit 1
fi

echo "Hash Database Management Tool"
echo "============================="
echo "Database: $DB_FILE"
echo "Command: $COMMAND"
echo ""

case $COMMAND in
    "info")
        echo "DATABASE INFORMATION:"
        echo "===================="
        
        # Database file size
        db_size=$(du -h "$DB_FILE" 2>/dev/null | cut -f1)
        echo "File size: $db_size"
        
        # Total entries
        total_entries=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM file_hashes;" 2>/dev/null)
        echo "Total entries: $total_entries"
        
        # Database schema version
        schema_info=$(sqlite3 "$DB_FILE" "SELECT sql FROM sqlite_master WHERE type='table' AND name='file_hashes';" 2>/dev/null)
        if [ -n "$schema_info" ]; then
            echo "Schema: OK"
        else
            echo "Schema: ERROR"
        fi
        
        # Check for indexes
        index_count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND tbl_name='file_hashes';" 2>/dev/null)
        echo "Indexes: $index_count"
        
        # Most recent entries
        echo ""
        echo "RECENT ENTRIES (last 5):"
        echo "========================"
        sqlite3 "$DB_FILE" "SELECT file_path, datetime(created_at, 'unixepoch') as created FROM file_hashes ORDER BY created_at DESC LIMIT 5;" 2>/dev/null | while IFS='|' read -r file_path created; do
            filename=$(basename "$file_path")
            echo "  $created - $filename"
        done
        
        # Directory distribution
        echo ""
        echo "DIRECTORY DISTRIBUTION (top 10):"
        echo "================================="
        sqlite3 "$DB_FILE" "SELECT SUBSTR(file_path, 1, LENGTH('$DEST_DIR') + 8) as dir_prefix, COUNT(*) as count FROM file_hashes WHERE file_path LIKE '$DEST_DIR/%' GROUP BY dir_prefix ORDER BY count DESC LIMIT 10;" 2>/dev/null | while IFS='|' read -r dir_path count; do
            dir_name=$(echo "$dir_path" | sed "s|$DEST_DIR/||")
            echo "  $count files in $dir_name"
        done
        ;;
        
    "cleanup")
        echo "CLEANING UP OBSOLETE ENTRIES:"
        echo "============================="
        
        # Get all file paths from database
        temp_file="/tmp/db_cleanup_$$"
        sqlite3 "$DB_FILE" "SELECT file_path FROM file_hashes;" > "$temp_file"
        
        removed_count=0
        total_checked=0
        
        while IFS= read -r file_path; do
            if [ -n "$file_path" ]; then
                ((total_checked++))
                if [ ! -f "$file_path" ]; then
                    # Escape single quotes in the path for SQL
                    escaped_path=$(echo "$file_path" | sed "s/'/''/g")
                    sqlite3 "$DB_FILE" "DELETE FROM file_hashes WHERE file_path = '$escaped_path';"
                    echo "  Removed: $file_path"
                    ((removed_count++))
                fi
                
                # Show progress every 1000 files
                if (( total_checked % 1000 == 0 )); then
                    echo "  Checked $total_checked files, removed $removed_count"
                fi
            fi
        done < "$temp_file"
        
        rm -f "$temp_file"
        
        echo ""
        echo "CLEANUP RESULTS:"
        echo "==============="
        echo "Files checked: $total_checked"
        echo "Entries removed: $removed_count"
        echo "Entries remaining: $((total_checked - removed_count))"
        
        if [ "$removed_count" -gt 0 ]; then
            echo ""
            echo "Optimizing database..."
            sqlite3 "$DB_FILE" "VACUUM;"
            new_size=$(du -h "$DB_FILE" 2>/dev/null | cut -f1)
            echo "Database optimized, new size: $new_size"
        fi
        ;;
        
    "vacuum")
        echo "OPTIMIZING DATABASE:"
        echo "==================="
        
        # Get size before optimization
        old_size=$(du -h "$DB_FILE" 2>/dev/null | cut -f1)
        echo "Size before optimization: $old_size"
        
        # Run vacuum
        sqlite3 "$DB_FILE" "VACUUM;"
        
        # Get size after optimization
        new_size=$(du -h "$DB_FILE" 2>/dev/null | cut -f1)
        echo "Size after optimization: $new_size"
        
        # Additional optimizations
        echo ""
        echo "Running additional optimizations..."
        sqlite3 "$DB_FILE" "ANALYZE;"
        sqlite3 "$DB_FILE" "REINDEX;"
        
        echo "Database optimization completed"
        ;;
        
    "stats")
        echo "DETAILED STATISTICS:"
        echo "==================="
        
        # Database file info
        db_size=$(du -h "$DB_FILE" 2>/dev/null | cut -f1)
        db_size_bytes=$(du -b "$DB_FILE" 2>/dev/null | cut -f1)
        echo "Database file size: $db_size ($db_size_bytes bytes)"
        
        # Total entries and storage efficiency
        total_entries=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM file_hashes;" 2>/dev/null)
        echo "Total hash entries: $total_entries"
        
        if [ "$total_entries" -gt 0 ]; then
            avg_size=$((db_size_bytes / total_entries))
            echo "Average bytes per entry: $avg_size"
        fi
        
        # Hash type distribution (based on length)
        echo ""
        echo "HASH TYPE DISTRIBUTION:"
        echo "======================"
        sqlite3 "$DB_FILE" "SELECT CASE WHEN LENGTH(file_hash) = 64 THEN 'SHA256' WHEN LENGTH(file_hash) = 32 THEN 'MD5' ELSE 'Other' END as hash_type, COUNT(*) as count FROM file_hashes GROUP BY hash_type;" 2>/dev/null | while IFS='|' read -r hash_type count; do
            echo "  $hash_type: $count files"
        done
        
        # File size statistics
        echo ""
        echo "FILE SIZE DISTRIBUTION:"
        echo "======================"
        sqlite3 "$DB_FILE" "SELECT CASE 
            WHEN file_size < 1024*1024 THEN 'Under 1MB'
            WHEN file_size < 10*1024*1024 THEN '1-10MB'
            WHEN file_size < 100*1024*1024 THEN '10-100MB'
            WHEN file_size < 1024*1024*1024 THEN '100MB-1GB'
            ELSE 'Over 1GB'
        END as size_range, COUNT(*) as count 
        FROM file_hashes 
        GROUP BY size_range 
        ORDER BY MIN(file_size);" 2>/dev/null | while IFS='|' read -r size_range count; do
            echo "  $size_range: $count files"
        done
        
        # Duplicate detection statistics
        echo ""
        echo "DUPLICATE STATISTICS:"
        echo "===================="
        duplicate_hashes=$(sqlite3 "$DB_FILE" "SELECT COUNT(DISTINCT file_hash) as unique_hashes FROM file_hashes;" 2>/dev/null)
        if [ "$total_entries" -gt 0 ] && [ "$duplicate_hashes" -gt 0 ]; then
            duplicate_count=$((total_entries - duplicate_hashes))
            echo "Unique files: $duplicate_hashes"
            echo "Duplicate files: $duplicate_count"
            
            if [ "$duplicate_count" -gt 0 ]; then
                echo ""
                echo "TOP DUPLICATE FILES (by occurrence):"
                echo "===================================="
                sqlite3 "$DB_FILE" "SELECT file_hash, COUNT(*) as occurrences FROM file_hashes GROUP BY file_hash HAVING COUNT(*) > 1 ORDER BY occurrences DESC LIMIT 5;" 2>/dev/null | while IFS='|' read -r hash_val occurrences; do
                    # Get one example file path for this hash
                    example_file=$(sqlite3 "$DB_FILE" "SELECT file_path FROM file_hashes WHERE file_hash = '$hash_val' LIMIT 1;" 2>/dev/null)
                    example_name=$(basename "$example_file")
                    echo "  $occurrences copies: $example_name (hash: ${hash_val:0:16}...)"
                done
            fi
        fi
        
        # Time-based statistics
        echo ""
        echo "TIME-BASED STATISTICS:"
        echo "====================="
        oldest=$(sqlite3 "$DB_FILE" "SELECT datetime(MIN(created_at), 'unixepoch') FROM file_hashes;" 2>/dev/null)
        newest=$(sqlite3 "$DB_FILE" "SELECT datetime(MAX(created_at), 'unixepoch') FROM file_hashes;" 2>/dev/null)
        echo "Oldest entry: $oldest"
        echo "Newest entry: $newest"
        ;;
        
    "verify")
        echo "VERIFYING DATABASE INTEGRITY:"
        echo "============================"
        
        # SQLite integrity check
        echo "Running SQLite integrity check..."
        integrity_result=$(sqlite3 "$DB_FILE" "PRAGMA integrity_check;" 2>/dev/null)
        if [ "$integrity_result" = "ok" ]; then
            echo "✓ Database integrity: OK"
        else
            echo "✗ Database integrity: FAILED"
            echo "  Result: $integrity_result"
            exit 1
        fi
        
        # Check for required tables and indexes
        echo ""
        echo "Checking database schema..."
        
        table_exists=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='file_hashes';" 2>/dev/null)
        if [ "$table_exists" = "1" ]; then
            echo "✓ Table 'file_hashes': exists"
        else
            echo "✗ Table 'file_hashes': missing"
        fi
        
        # Check indexes
        required_indexes=("idx_file_hash" "idx_file_path" "idx_last_modified")
        for index_name in "${required_indexes[@]}"; do
            index_exists=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name='$index_name';" 2>/dev/null)
            if [ "$index_exists" = "1" ]; then
                echo "✓ Index '$index_name': exists"
            else
                echo "⚠ Index '$index_name': missing (performance may be degraded)"
            fi
        done
        
        # Sample file verification (check if files still exist)
        echo ""
        echo "Verifying sample files..."
        sample_count=10
        verified_count=0
        missing_count=0
        
        sqlite3 "$DB_FILE" "SELECT file_path FROM file_hashes ORDER BY RANDOM() LIMIT $sample_count;" 2>/dev/null | while IFS= read -r file_path; do
            if [ -n "$file_path" ]; then
                if [ -f "$file_path" ]; then
                    ((verified_count++))
                else
                    echo "⚠ Missing file: $file_path"
                    ((missing_count++))
                fi
            fi
        done
        
        total_entries=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM file_hashes;" 2>/dev/null)
        echo "Sample verification complete ($sample_count of $total_entries entries checked)"
        
        if [ "$missing_count" -gt 0 ]; then
            echo ""
            echo "⚠ Found $missing_count missing files in sample"
            echo "  Consider running 'cleanup' command to remove obsolete entries"
        fi
        
        echo ""
        echo "Database verification completed"
        ;;
        
    *)
        echo "Error: Unknown command: $COMMAND"
        echo "Available commands: info, cleanup, vacuum, stats, verify"
        exit 1
        ;;
esac