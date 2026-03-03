# CarMedia Downloader v1.1

A YAD-based GUI media downloader optimised for Hyundai i20 / Apple CarPlay.

## Quick start
```bash
chmod +x main.sh
./main.sh
```

## Dependencies
| Tool    | Arch                     | Debian / Ubuntu          |
|---------|--------------------------|--------------------------|
| yad     | `sudo pacman -S yad`     | `sudo apt install yad`   |
| yt-dlp  | `sudo pacman -S yt-dlp`  | `pip install yt-dlp`     |
| ffmpeg  | `sudo pacman -S ffmpeg`  | `sudo apt install ffmpeg`|

## Profiles
| Key   | Output                    | Optimised for          |
|-------|---------------------------|------------------------|
| car   | 720p H.264 + AAC → MP4   | Hyundai i20 / CarPlay  |
| fast  | Best single MP4 stream    | Speed                  |
| best  | Best video + audio → MKV  | Archiving              |
| audio | MP3 high quality          | Music                  |

## Speed fixes applied
- `--extractor-args youtube:player_client=android`  
  Uses the Android API endpoint — bypasses bot checks, gets direct stream URLs
- `--concurrent-fragments 5`  
  Downloads DASH/HLS fragments in parallel (configurable in Settings)
- `--buffer-size 16K`  
  Larger read buffer, fewer round-trips
- `--http2`  
  HTTP/2 keep-alive for multi-fragment streams

## Architecture
```
main.sh                ← ONLY file that sets BASE_DIR and sources everything
├── services/
│   ├── error_handler.sh    logging + error dialogs
│   └── update_service.sh   yt-dlp update management
├── core/
│   ├── profiles.sh          format string presets
│   ├── platform_detector.sh URL → platform detection
│   └── downloader.sh        yt-dlp execution engine
├── ui.sh                   ALL YAD GUI (no sourcing, no path calc)
├── config/settings.conf    user preferences
└── logs/                   app.log + error.log
```

## Tip: folder name
Avoid spaces in the project path. Rename if needed:
```bash
mv "carMedia Downloader" carMediaDownloader
```
