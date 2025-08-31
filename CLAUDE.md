# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains file organization scripts designed to automatically organize multimedia files into year/month directory structures based on dates extracted from filenames or metadata. The main script `organize_files.sh` is feature-rich with checkpoint system, duplicate handling, and robust date pattern recognition.

## Common Commands

### Main Script Operations
```bash
# Make scripts executable (required first step)
chmod +x organize_files.sh test_patterns.sh manage_checkpoints.sh build_hash_database.sh manage_hash_database.sh

# Test file organization (simulation mode)
./organize_files.sh /source /dest --dry-run

# Run actual file organization
./organize_files.sh /source /dest

# Test date pattern recognition
./test_patterns.sh /source

# Quick pattern test (statistics only)
./test_patterns.sh /source --dry-run
```

### Hash Database Operations
```bash
# Build hash database for destination directory (first time)
./build_hash_database.sh /dest

# Update existing database with new/modified files
./build_hash_database.sh /dest --update

# Rebuild database from scratch
./build_hash_database.sh /dest --rebuild

# View database information and statistics
./manage_hash_database.sh /dest info

# Clean up entries for removed files
./manage_hash_database.sh /dest cleanup

# Optimize database performance
./manage_hash_database.sh /dest vacuum
```

### Checkpoint Management
```bash
# List active checkpoints
./manage_checkpoints.sh list

# View specific checkpoint details
./manage_checkpoints.sh info <PID>

# Clean all checkpoints (restart from scratch)
./manage_checkpoints.sh clean
```

## Architecture and Features

### Core Components

1. **organize_files.sh** - Main file organization script with:
   - Recursive directory scanning
   - Multiple date pattern recognition (YYYY-MM-DD, DD-MM-YYYY, MM-DD-YYYY, YYYYMMDD)
   - EXIF metadata fallback
   - **Advanced hash-based duplicate detection** (SHA256/MD5)
   - Global duplicate search across entire destination directory
   - Hash caching for improved performance
   - Checkpoint system for resume capability
   - Signal handling (Ctrl+C safe)

2. **test_patterns.sh** - Date pattern testing utility that:
   - Uses identical logic to main script
   - Provides detailed pattern analysis
   - Shows preview of directory structure
   - Helps validate date recognition before running

3. **manage_checkpoints.sh** - Checkpoint management utility for:
   - Listing active checkpoint sessions
   - Viewing detailed checkpoint information
   - Cleaning checkpoint files

4. **build_hash_database.sh** - Hash database builder script that:
   - Scans destination directory and builds SQLite database
   - Calculates SHA256/MD5 hashes for all multimedia files
   - Supports incremental updates and full rebuilds
   - Optimizes database with indexes and vacuum operations
   - Can be scheduled as cron job for maintenance

5. **manage_hash_database.sh** - Hash database management utility for:
   - Database information and statistics
   - Cleanup of obsolete file entries
   - Database optimization and integrity checking
   - Verification of file existence

### Date Pattern Recognition

The system recognizes multiple date formats with prefix/suffix support:
- ISO format: `vacation_2024-03-15_sunset.jpg`
- European: `photo_15-03-2024_evening.png`
- American: `backup_03-15-2024.zip`
- Compact: `IMG_20240315_120000.jpg`
- Partial: `video_2024-03_birthday.mp4`

### Advanced Duplicate Detection

The script uses **SQLite database with SHA256 hash-based comparison** for accurate and efficient duplicate detection:

- **Hash calculation**: SHA256 (fallback to MD5 if unavailable)
- **SQLite database storage**: Persistent hash database in `destination/.file_hashes.db`
- **Instant duplicate lookup**: O(1) hash queries instead of full directory scans
- **Cross-directory detection**: Finds duplicates even with different names in different subdirectories
- **Performance optimization**: Pre-built database eliminates need to scan entire destination
- **Maintenance tools**: Database can be updated, cleaned, and optimized independently

#### Duplicate Handling Strategy:
- **Identical files anywhere in destination**: Source renamed with `_DUP` suffix, stays in source directory
- **Different files, same name**: Destination file gets numbered suffix (`_1`, `_2`)
- **Files already in correct position**: Skipped without processing

#### Database Performance Benefits:
- **First-time setup**: Run `./build_hash_database.sh /dest` once to scan and hash all existing files
- **Incremental updates**: Use `--update` flag to add only new/modified files to database
- **Instant duplicate detection**: Database lookup vs. full directory scan (1000x+ faster)
- **Cron scheduling**: Automated maintenance with `0 2 * * * ./build_hash_database.sh /dest --update`

#### Examples:
- `vacation_2024-03-15.jpg` detected as duplicate of `different_name.jpg` in `2024/01/`
- Shows original location: `Duplicate found in database: /dest/2024/01/different_name.jpg`

### Checkpoint System

The script automatically creates checkpoint files in `/tmp/` with PID-based naming:
- `organize_files_checkpoint_<PID>` - Contains statistics and state  
- `organize_files_processed_<PID>` - Lists already processed files

Interruption with Ctrl+C is safe - the script will resume from exact interruption point when restarted. The SQLite hash database provides persistent performance optimization across sessions.

### File Types Supported

Images: jpg, jpeg, png, gif, bmp, tiff
Videos: mp4, avi, mov, mkv, wmv  
Audio: mp3, wav, flac

Files with `_DUP.*` pattern are automatically excluded to prevent reprocessing.