# One-Time Copy Docker Container

A Docker container that copies files from an input folder to an output folder **exactly once**. Files that are deleted from the output folder will NOT be recopied from the input. Renamed files in the input folder are also detected and won't be copied again.

## How It Works

1. The container monitors the `/input` folder for files (recursively scanning all subfolders)
2. When a new file is detected, its **content hash (SHA256)** is calculated
3. If the hash hasn't been seen before, the file is copied to `/output`
4. Both the file path and hash are recorded in tracking manifests
5. On subsequent runs, files are skipped if their hash was already copied - **even if renamed**

## Key Features

- **Content-based tracking**: Uses SHA256 hashes to detect duplicate content
- **Rename detection**: Renamed files won't be copied again (same content = same hash)
- **Recursive scanning**: All subfolders in input are scanned
- **Extension filtering**: Include or exclude specific file types
- **Persistent tracking**: Survives container restarts

## Quick Start

### 1. Build the container

```bash
docker-compose build
```

### 2. Create the required folders

```bash
mkdir -p input output data
```

### 3. Start the container

```bash
docker-compose up -d
```

### 4. View logs

```bash
docker-compose logs -f
```

## Configuration

Environment variables in `docker-compose.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `SYNC_INTERVAL` | `60` | How often to scan for new files (in seconds) |
| `RUN_ONCE` | `false` | Set to `true` to run once and exit |
| `FILE_EXTENSIONS` | *(empty)* | Comma-separated list of extensions (e.g., `jpg,png,pdf`) |
| `EXTENSION_MODE` | `include` | `include` = only copy listed extensions, `exclude` = skip listed extensions |
| `FLATTEN_OUTPUT` | `false` | Set to `true` to copy only files (no folders) to a flat output directory |
| `LOG_LEVEL` | `INFO` | Logging verbosity: `DEBUG`, `INFO`, `WARN`, or `ERROR` |

### Extension Filter Examples

**Copy only images:**
```yaml
environment:
  - FILE_EXTENSIONS=jpg,jpeg,png,gif,webp
  - EXTENSION_MODE=include
```

**Copy everything except videos:**
```yaml
environment:
  - FILE_EXTENSIONS=mp4,avi,mkv,mov,wmv
  - EXTENSION_MODE=exclude
```

**Copy all files (no filter):**
```yaml
environment:
  - FILE_EXTENSIONS=
```

### Flatten Output Examples

**Create a flat output directory (no subdirectories):**
```yaml
environment:
  - FLATTEN_OUTPUT=true
```

This will copy only files from the input folder, ignoring all subdirectory structure. All files will be placed directly in the output folder root, resulting in a completely flat directory.

**Example:**
```
Input folder:
  /input/
    file1.txt
    photos/photo1.jpg
    docs/reports/report.pdf

Output folder (with FLATTEN_OUTPUT=true):
  /output/
    file1.txt
    photo1.jpg
    report.pdf
```

**Note:** If you have files with the same name in different subdirectories, the last one processed will overwrite previous ones. Consider using extension filters with flatten mode if needed.

**Combine with extension filter to flatten only specific file types:**
```yaml
environment:
  - FLATTEN_OUTPUT=true
  - FILE_EXTENSIONS=jpg,png,gif
  - EXTENSION_MODE=include
```

### Log Level Examples

**Minimal logging (errors only):**
```yaml
environment:
  - LOG_LEVEL=ERROR
```

**Verbose debugging:**
```yaml
environment:
  - LOG_LEVEL=DEBUG
```

**Standard logging (default):**
```yaml
environment:
  - LOG_LEVEL=INFO
```

## Volume Mounts

| Container Path | Purpose |
|----------------|---------|
| `/input` | Source folder (read-only) |
| `/output` | Destination folder |
| `/data` | Tracking data (manifest file) |

**IMPORTANT**: The `/data` volume must be persistent to track copied files across container restarts!

## Usage Examples

### Run Once Mode

For a one-time copy operation:

```bash
docker run --rm \
  -v /path/to/source:/input:ro \
  -v /path/to/destination:/output \
  -v /path/to/data:/data \
  -e RUN_ONCE=true \
  one-time-copy
```

### Continuous Monitoring

For continuous monitoring (default):

```bash
docker-compose up -d
```

### Custom Sync Interval

Check for new files every 30 seconds:

```yaml
environment:
  - SYNC_INTERVAL=30
```

## Resetting the Tracking

To allow files to be copied again, delete or clear the manifests:

```bash
# Remove all tracking (allows all files to be copied again)
rm data/copied_files.manifest data/copied_hashes.manifest

# Or clear specific entries by editing the files
nano data/copied_files.manifest
nano data/copied_hashes.manifest
```

**Note:** The hash manifest (`copied_hashes.manifest`) is what prevents renamed files from being copied. If you only clear `copied_files.manifest`, renamed files will still be detected as duplicates.

## File Structure

```
dock_OneTimeCopy/
├── Dockerfile
├── docker-compose.yml
├── sync.sh
├── .dockerignore
├── README.md
├── input/          # Your source files (create this)
├── output/         # Copied files go here (create this)
└── data/           # Tracking manifests stored here (create this)
    ├── copied_files.manifest   # Tracks file paths
    └── copied_hashes.manifest  # Tracks content hashes (for rename detection)
```

## Notes

- Subdirectories are preserved during copy unless used with FLATTEN_OUTPUT 
- File permissions and timestamps are preserved (`cp -p`)
- The input folder is mounted read-only for safety
- Files are tracked by SHA256 hash, so renamed files won't be copied again
- Extension matching is case-insensitive (`JPG` = `jpg`)
- Extensions can be specified with or without dots (`jpg` or `.jpg`)
