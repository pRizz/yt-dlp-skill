# yt-dlp-download

A Codex skill for downloading media supported by `yt-dlp` while preserving source attribution and embedded metadata.

## What it does

- Downloads a media URL into the current working directory.
- Runs `yt-dlp --embed-metadata`.
- Prints the absolute path of each downloaded file.
- Prints embedded metadata tags with `ffprobe` when available.
- Adds a macOS Finder comment with the source URL when `xattr` and `python3` are available.

## Install

Install this repository as a root-level Codex skill. For manual installation, copy the repository contents into a skill directory such as `~/.codex/skills/yt-dlp-download`.

The skill folder contains:

- `SKILL.md`
- `scripts/yt-dlp-download.sh`
- `agents/openai.yaml`

Required runtime dependency:

```bash
command -v yt-dlp
```

Optional helpers:

```bash
command -v ffprobe
command -v xattr
command -v python3
```

## Direct script usage

Run the script from the directory where downloads should be saved:

```bash
scripts/yt-dlp-download.sh "https://example.com/media-url"
```

Use a custom source comment:

```bash
scripts/yt-dlp-download.sh "https://example.com/media-url" "Source URL: https://example.com/media-url"
```
