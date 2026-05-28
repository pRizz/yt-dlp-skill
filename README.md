# yt-dlp-download

A Codex skill for downloading media supported by `yt-dlp` while preserving source attribution and embedded metadata.

## What it does

- Downloads a media URL into the user's platform Downloads folder by default.
- Runs `yt-dlp --embed-metadata`.
- Prints the absolute path of each downloaded file.
- Prints embedded metadata tags with `ffprobe` when available.
- Adds a macOS Finder comment with the source URL when `xattr` and `python3` are available.

Default output directories:

- macOS: `$HOME/Downloads`
- Windows-like Bash shells: `%USERPROFILE%\Downloads` converted with `cygpath -u` when available, otherwise `$HOME/Downloads`
- Linux and other Unix platforms: `xdg-user-dir DOWNLOAD` when available, otherwise `$HOME/Downloads`

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
command -v xdg-user-dir
command -v cygpath
```

## Direct script usage

Run the script with a supported media URL:

```bash
scripts/yt-dlp-download.sh "https://example.com/media-url"
```

Use a custom source comment:

```bash
scripts/yt-dlp-download.sh "https://example.com/media-url" "Source URL: https://example.com/media-url"
```

Override the output directory with either a flag or environment variable. The flag takes precedence:

```bash
scripts/yt-dlp-download.sh --output-dir "$HOME/Desktop" "https://example.com/media-url"
YTDLP_DOWNLOAD_DIR="$HOME/Desktop" scripts/yt-dlp-download.sh "https://example.com/media-url"
```
