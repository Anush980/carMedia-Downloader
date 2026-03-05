# CarMedia Pro

[![Made with ❤️](https://img.shields.io/badge/Made%20with-❤️-dark?style=flat-square)](https://github.com/Anush980)
![GitHub last commit](https://img.shields.io/github/last-commit/Anush980/carMedia-Downloader?style=flat-square)
![Platform](https://img.shields.io/badge/Platform-Linux-FCC624?style=flat-square&logo=linux&logoColor=black)
![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)

A YouTube downloader built specifically for **car head units and Apple CarPlay**. Downloads videos and music in formats that actually play on your car — H.264 MP4 for video, AAC/MP3 for music. Features a full GUI, playlist selector, and smart cookie handling to bypass YouTube bot detection.

---

## 🛠 Technologies Used

![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)
![yt-dlp](https://img.shields.io/badge/yt--dlp-FF0000?style=flat-square&logo=youtube&logoColor=white)
![ffmpeg](https://img.shields.io/badge/ffmpeg-007808?style=flat-square&logo=ffmpeg&logoColor=white)
![YAD](https://img.shields.io/badge/YAD-GUI-blueviolet?style=flat-square)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=flat-square&logo=linux&logoColor=black)

---

## ✨ Features

- **Car-optimised profiles** — 720p H.264 + AAC in MP4, compatible with all head units and Apple CarPlay
- **HD profile** — 1080p H.264 + AAC for higher-resolution screens
- **Music modes** — MP3 320kbps, M4A AAC, Opus with embedded metadata and cover art
- **Playlist selector** — visual checklist to pick exactly which videos to download from a playlist
- **"First video only" mode** — skip the selector and grab just the video in the URL
- **Live download log** — raw yt-dlp output streamed to the GUI in real time, exactly like a terminal
- **Auto browser detection** — detects Firefox, Chrome, Brave, Chromium automatically for cookie auth
- **cookies.txt import** — file picker to import exported cookies for YouTube bot bypass
- **Auto-update yt-dlp** — detects pip vs package manager install and updates accordingly
- **One-command install** — `bash install.sh` sets up everything from scratch

---

## 📋 Requirements

| Dependency | Purpose | Min Version |
|------------|---------|-------------|
| `bash` | Shell runtime | 4.0+ |
| `yt-dlp` | YouTube downloading | 2024.x+ |
| `ffmpeg` | Merging video + audio streams | Any recent |
| `yad` | GUI dialogs | 7.0+ |
| `python3-pip` | Installing/updating yt-dlp | Any |

---

## 🚀 Installation

### One-command install (recommended)

```bash
git clone https://github.com/Anush980/carMedia-Downloader.git
cd carMedia-Downloader
bash install.sh
```

`install.sh` will automatically:
1. Detect your distro (`apt` / `dnf` / `pacman` / `zypper`)
2. Install `ffmpeg`, `yad`, `python3-pip`
3. Install the latest `yt-dlp` via pip (not the stale distro package)
4. Set correct permissions on all scripts
5. Write a default `config/settings.conf`
6. Create an app launcher in your system menu
7. Create a desktop shortcut (if `~/Desktop` exists)

### Manual install

```bash
# Install dependencies (Ubuntu/Debian)
sudo apt-get install -y ffmpeg yad python3-pip

# Install latest yt-dlp
pip3 install yt-dlp --break-system-packages

# Make scripts executable
chmod +x main.sh ui.sh core/*.sh services/*.sh

# Run
bash main.sh
```

---

## ▶️ Usage

```bash
bash main.sh
```

Or launch from your application menu / desktop shortcut after running `install.sh`.

### Download flow

1. Paste a YouTube URL (single video or playlist)
2. Select **Video** or **Music** mode and a quality profile
3. Choose a save folder
4. Hit **Download**
   - For playlists: a checklist appears — tick what you want, click OK
   - Tick **"First video only"** to skip the selector entirely
5. Watch live progress in the log pane

### Profiles

| Profile | Format | Best for |
|---------|--------|----------|
| Car Compatible | 720p H.264 + AAC → MP4 | All car head units, CarPlay |
| HD | 1080p H.264 + AAC → MP4 | Higher-res screens |
| Fast | Best single MP4 stream | Quick downloads, no merge |
| Best Quality | Max resolution → MKV | Archiving |
| MP3 | 320kbps + cover art | Music, all players |
| M4A AAC | Best quality AAC | Apple CarPlay music |
| Opus | Smallest file size | Storage-constrained |

---

## 🍪 Cookies Setup (Required for most downloads)

YouTube now requires a valid browser session (cookies) on most IPs to prove you're not a bot. Without cookies you'll see:

```
ERROR: Sign in to confirm you're not a bot.
```

This affects **all videos including fully public ones** — it's YouTube's IP-level bot detection, not a login requirement.

### Option A — Auto-detect (default)

The app automatically scans for installed browsers (`firefox` → `chromium` → `chrome` → `brave`) and uses the first one found. The browser **must be completely closed** (not just the window — the full process) when downloading, otherwise its cookie database is locked and yt-dlp gets nothing.

Set in **Settings → Browser Cookies** if auto-detect picks the wrong one.

### Option B — Import cookies.txt (most reliable, works on any machine)

This method works regardless of browser state and is the recommended approach for machines where browser extraction fails.

**Step 1 — Install the extension**

| Browser | Extension |
|---------|-----------|
| Chrome / Brave | [Get cookies.txt LOCALLY](https://chrome.google.com/webstore/detail/get-cookiestxt-locally/cclelndahbckbenkjhflpdbgdldlbecc) |
| Firefox | [cookies.txt](https://addons.mozilla.org/en-US/firefox/addon/cookies-txt/) |

**Step 2 — Export**

1. Go to [youtube.com](https://youtube.com) and make sure you're logged in
2. Click the extension icon in your toolbar
3. Click **Export** — a `cookies.txt` file downloads to your `~/Downloads` folder

**Step 3 — Import into CarMedia**

1. Open CarMedia → **Settings**
2. Click **📂 Import cookies.txt**
3. Navigate to your downloaded `cookies.txt` and click **Open**
4. Done — the app confirms how many lines were imported

The cookies file is saved to `config/cookies.txt` and takes priority over browser extraction. It stays valid until your YouTube session expires (usually 1–2 months). Click **🗑 Clear cookies.txt** in Settings to remove it.

---

## 🐛 Debugging & Known Issues

### "Requested format is not available"

**Cause:** yt-dlp has a user config at `~/.config/yt-dlp/config` from a previous manual run that contains `--cookies-from-browser firefox` or other flags. This silently overrides everything the app sets.

**Fix:** 
```bash
cat ~/.config/yt-dlp/config   # check what's in it
rm ~/.config/yt-dlp/config    # delete it
```

The app now always passes `--ignore-config` to yt-dlp so this can't happen again.

---

### "Sign in to confirm you're not a bot"

**Cause:** No cookies being sent. YouTube's bot detection triggers on requests without a valid browser session, even for public videos.

**Fix (in order of reliability):**
1. Import a `cookies.txt` file via **Settings → 📂 Import cookies.txt** (see above)
2. Close your browser completely, then set it in **Settings → Browser Cookies**
3. Make sure yt-dlp isn't reading a stale config: `rm ~/.config/yt-dlp/config`

---

### Downloads stuck / `.part` files left behind

**Cause:** YouTube throttled or stalled a fragment download and yt-dlp had no timeout — it waited forever.

**Fix (already applied in current version):**
- `--socket-timeout 30` — abort if no data for 30 seconds
- `--throttled-rate 50K` — restart request if speed drops below 50 KB/s
- Concurrent fragments reduced from 5 → 3 to avoid triggering rate limiting

If it still happens: lower **Concurrent Fragments** in Settings to `1`.

---

### Cookie extraction fails even with browser closed

**Cause:** On some distros, `--cookies-from-browser firefox` requires access to the system keyring (GNOME Keyring / KWallet) to decrypt the cookie database. This fails silently on minimal installs or remote sessions.

**Fix:** Use **Option B** above — import a `cookies.txt` file instead. It bypasses the keyring entirely.

---

### `yt-dlp -U` fails with "Use your package manager"

**Cause:** yt-dlp was installed via `apt`/`dnf`/`pacman` rather than pip, so it can't self-update.

**Fix:** The update service now falls back to pip automatically:
```bash
pip3 install --upgrade yt-dlp --break-system-packages
```
Or click **⬆ Update yt-dlp Now** in Settings.

---

### GUI doesn't appear / `yad` not found

```bash
# Ubuntu/Debian
sudo apt-get install yad

# Fedora
sudo dnf install yad

# Arch
sudo pacman -S yad
```

---

## 📁 Project Structure

```
carMedia-Downloader/
├── main.sh                  # Entry point — loads modules, checks deps, launches UI
├── ui.sh                    # All YAD GUI windows and user interaction
├── install.sh               # One-command installer
├── uninstall.sh             # Removes launchers, config, logs (keeps videos)
├── config/
│   └── settings.conf        # User preferences (auto-generated)
├── core/
│   ├── downloader.sh        # Builds yt-dlp argument array
│   ├── download_manager.sh  # Job queue, progress window, live log streaming
│   ├── profiles.sh          # Video/music format string definitions
│   ├── playlist_parser.sh   # Fetches playlist metadata for the selector
│   ├── metadata_fetcher.sh  # Fetches video title for display
│   └── platform_detector.sh # URL type detection (single/playlist/video-in-playlist)
├── services/
│   ├── logger.sh            # Logging functions (INFO/WARN/ERROR)
│   ├── error_handler.sh     # YAD error dialogs
│   └── update_service.sh    # yt-dlp update logic (pip fallback)
└── logs/
    ├── app.log              # Full session log including raw yt-dlp output
    └── error.log            # Errors only
```

---

## 🗑 Uninstall

```bash
bash uninstall.sh
```

Removes: app menu launcher, desktop shortcut, `config/settings.conf`, `config/cookies.txt`, logs.  
Does **not** remove: ffmpeg, yad, yt-dlp, or your downloaded videos.

To remove everything including the app folder:
```bash
bash uninstall.sh
rm -rf /path/to/carMedia-Downloader
```

---

## 📄 License

MIT — do whatever you want with it.

---

[![Made with ❤️](https://img.shields.io/badge/Made%20with-❤️-dark?style=flat-square)](https://github.com/Anush980)
