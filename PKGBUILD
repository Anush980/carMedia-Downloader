pkgname=carmedia-downloader
pkgver=1.1
pkgrel=1
pkgdesc="YAD-based GUI media downloader optimised for Hyundai i20 / Apple CarPlay"
arch=('x86_64' 'aarch64')
url="https://github.com/Anush980/carMedia-Downloader"
license=('MIT')
depends=('bash' 'yad' 'yt-dlp' 'ffmpeg')
optdepends=('chromium: for automatic cookie extraction'
            'firefox: for automatic cookie extraction')

source=("git+https://github.com/Anush980/carMedia-Downloader.git#tag=v${pkgver}")
sha256sums=('SKIP')

build() {
    cd carMedia-Downloader
    # No compilation needed
    :
}

package() {
    cd carMedia-Downloader
    
    # ─────────────────────────────────────────────────────────────────────────
    # Install app files to /opt/carmedia
    # ─────────────────────────────────────────────────────────────────────────
    install -dm755 "$pkgdir/opt/carmedia"
    
    # Copy all app files
    cp -r . "$pkgdir/opt/carmedia/"
    chmod +x "$pkgdir/opt/carmedia/main.sh"
    
    # Remove PKGBUILD from package (not needed after install)
    rm -f "$pkgdir/opt/carmedia/PKGBUILD"
    
    # ─────────────────────────────────────────────────────────────────────────
    # Create /usr/bin/carmedia command
    # ─────────────────────────────────────────────────────────────────────────
    install -dm755 "$pkgdir/usr/bin"
    cat > "$pkgdir/usr/bin/carmedia" << 'WRAPPER'
#!/bin/bash
# CarMedia Downloader launcher
cd /opt/carmedia && exec ./main.sh "$@"
WRAPPER
    chmod 755 "$pkgdir/usr/bin/carmedia"
    
    # ─────────────────────────────────────────────────────────────────────────
    # Install Desktop Entry (creates app in Application Menu + icon)
    # ─────────────────────────────────────────────────────────────────────────
    install -Dm644 carmedia.desktop "$pkgdir/usr/share/applications/carmedia.desktop"
    
    # Update Exec path in desktop file to use /opt/carmedia
    sed -i 's|Exec=.*|Exec=carmedia|' "$pkgdir/usr/share/applications/carmedia.desktop"
    
    # ─────────────────────────────────────────────────────────────────────────
    # Install icon (optional — uses system default if not present)
    # ─────────────────────────────────────────────────────────────────────────
    if [[ -f carmedia.png ]]; then
        install -Dm644 carmedia.png "$pkgdir/usr/share/pixmaps/carmedia.png"
        # Update desktop entry to use custom icon
        sed -i 's|Icon=.*|Icon=carmedia|' "$pkgdir/usr/share/applications/carmedia.desktop"
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # Install documentation
    # ─────────────────────────────────────────────────────────────────────────
    install -Dm644 README.md "$pkgdir/usr/share/doc/carmedia/README.md"
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/carmedia/LICENSE"
}