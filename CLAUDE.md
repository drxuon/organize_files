# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains file organization scripts designed to automatically organize multimedia files into year/month directory structures based on dates extracted from filenames or metadata. The main script `organize_files.sh` is feature-rich with checkpoint system, duplicate handling, and robust date pattern recognition.

## Common Commands

### Main Script Operations
```bash
# Make scripts executable (required first step)
chmod +x organize_files.sh test_patterns.sh manage_checkpoints.sh

# Test file organization (simulation mode)
./organize_files.sh /source /dest --dry-run

# Run actual file organization
./organize_files.sh /source /dest

# Test date pattern recognition
./test_patterns.sh /source

# Quick pattern test (statistics only)
./test_patterns.sh /source --dry-run
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

### Date Pattern Recognition

The system recognizes multiple date formats with prefix/suffix support:
- ISO format: `vacation_2024-03-15_sunset.jpg`
- European: `photo_15-03-2024_evening.png`
- American: `backup_03-15-2024.zip`
- Compact: `IMG_20240315_120000.jpg`
- Partial: `video_2024-03_birthday.mp4`

### Advanced Duplicate Detection

The script uses **SHA256 hash-based comparison** for accurate duplicate detection:

- **Hash calculation**: SHA256 (fallback to MD5 if unavailable)
- **Global search**: Scans entire destination directory, not just exact filename matches
- **Cross-directory detection**: Finds duplicates even with different names in different subdirectories
- **Performance optimization**: Hash caching with size-based pre-filtering
- **Cache persistence**: Hashes saved with checkpoints for faster restarts

#### Duplicate Handling Strategy:
- **Identical files anywhere in destination**: Source renamed with `_DUP` suffix, stays in source directory
- **Different files, same name**: Destination file gets numbered suffix (`_1`, `_2`)
- **Files already in correct position**: Skipped without processing

#### Examples:
- `vacation_2024-03-15.jpg` detected as duplicate of `different_name.jpg` in `2024/01/`
- Shows original location: `Original duplicate is at: /dest/2024/01/different_name.jpg`

### Checkpoint System

The script automatically creates checkpoint files in `/tmp/` with PID-based naming:
- `organize_files_checkpoint_<PID>` - Contains statistics and state
- `organize_files_processed_<PID>` - Lists already processed files
- `organize_files_hashes_<PID>` - **Hash cache for performance** (new feature)

Interruption with Ctrl+C is safe - the script will resume from exact interruption point when restarted. Hash cache is automatically restored for continued performance optimization.

### File Types Supported

Images: jpg, jpeg, png, gif, bmp, tiff
Videos: mp4, avi, mov, mkv, wmv  
Audio: mp3, wav, flac

Files with `_DUP.*` pattern are automatically excluded to prevent reprocessing.