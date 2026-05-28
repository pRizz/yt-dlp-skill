---
name: yt-dlp-download
description: Download media from yt-dlp-supported URLs while preserving source attribution and embedded metadata. Use when the user asks to download, archive, inspect, or prepare online video or audio media, including Twitter/X posts, social video URLs, or reposting workflows where the source URL and metadata should be retained.
---

# yt-dlp Download

## Overview

Use the bundled `scripts/yt-dlp-download.sh` wrapper to download media with `yt-dlp --embed-metadata`, preserve a source comment, print absolute downloaded file paths, and print embedded tags with `ffprobe` when available.

The script writes downloads to the user's platform Downloads folder by default:

- macOS: `$HOME/Downloads`
- Windows-like Bash shells: `%USERPROFILE%\Downloads` converted with `cygpath -u` when available, otherwise `$HOME/Downloads`
- Linux and other Unix platforms: `xdg-user-dir DOWNLOAD` when available, otherwise `$HOME/Downloads`

Use `--output-dir <dir>` or `YTDLP_DOWNLOAD_DIR=<dir>` when the user asks for a specific destination. The `--output-dir` flag takes precedence over the environment variable.

## Workflow

1. Confirm the user provided a media URL supported by `yt-dlp`, such as a Twitter/X post URL or direct media URL.
2. Let the script use the platform Downloads folder unless the user requested a specific destination.
3. Check the required downloader:

```bash
command -v yt-dlp
```

4. Optionally check metadata and platform helpers:

```bash
command -v ffprobe
command -v xattr
command -v python3
command -v xdg-user-dir
command -v cygpath
```

5. Run the bundled script:

```bash
scripts/yt-dlp-download.sh "$url"
```

6. For a custom source comment, pass it as the second argument:

```bash
scripts/yt-dlp-download.sh "$url" "Source URL: $url"
```

7. For a custom output directory, use either override:

```bash
scripts/yt-dlp-download.sh --output-dir "$HOME/Desktop" "$url"
YTDLP_DOWNLOAD_DIR="$HOME/Desktop" scripts/yt-dlp-download.sh "$url"
```

For multiple URLs, run the script once per URL so each file receives its own source comment.

## Verification

After the script completes:

- Confirm the downloaded media file exists in the selected output directory.
- Review each `Downloaded file:` log line for the absolute saved path.
- Review the script's `ffprobe` tag output when `ffprobe` is installed.
- On macOS, verify the Finder comment if needed:

```bash
mdls -raw -name kMDItemFinderComment "$downloaded_file"
```

If Spotlight metadata has not updated yet, inspect the extended attribute directly:

```bash
xattr -l "$downloaded_file"
```

## Operational Notes

- Keep URLs shell-quoted.
- Do not use third-party downloader websites for this workflow.
- Do not bypass private, deleted, paywalled, or access-controlled content.
- If `yt-dlp` reports that authentication is required, stop and ask the user how they want to provide access.
- If `yt-dlp` reports an extractor error for a public URL, update `yt-dlp` through the user's package manager or `yt-dlp -U` when appropriate, then retry.
- Treat upload, editing, or repost steps as separate workflows after the download has been verified.
