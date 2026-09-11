# App size comparison

Measured on September 11, 2026 for the README. These are release-specific measurements, not a performance benchmark or a comparison of equivalent feature sets.

| Measurement | Smallibre 0.4.1 | Calibre 9.14.0 |
| --- | ---: | ---: |
| Homebrew download, bytes | 3,232,227 | 344,439,358 |
| Installed app files, bytes | 8,777,632 | 1,153,281,126 |
| Main executable architecture | arm64 | x86_64 + arm64 |

## Sources

`brew info --cask --json=v2 calibre tajchert/tap/smallibre` identified the versions and download URLs:

- [Smallibre Homebrew cask](https://github.com/tajchert/homebrew-tap/blob/main/Casks/smallibre.rb): [0.4.1 release ZIP](https://github.com/tajchert/smallibre/releases/download/v0.4.1/Smallibre-0.4.1-macos-arm64.zip).
- [Calibre Homebrew cask](https://formulae.brew.sh/cask/calibre): [9.14.0 release DMG](https://download.calibre-ebook.com/9.14.0/calibre-9.14.0.dmg).

The cached Smallibre ZIP was measured locally. Its SHA-256 matched the cask: `4a5ceb1dc4845c3f53a7e039f43c8316383aa919aecfa1cdab667585a6377a41`.

The official Calibre DMG returned `Content-Length: 344439358` in an HTTP HEAD response. The download button on [Calibre’s macOS download page](https://calibre-ebook.com/download_osx) was also checked: it redirects through `https://calibre-ebook.com/dist/osx` to the GitHub 9.14.0 DMG, which returned the same `Content-Length: 344439358`. The website and Homebrew downloads therefore have the same measured size. Both installed versions were checked against their local app-bundle metadata. `lipo -archs` confirmed the executable architectures above.

## Method

Download means the compressed app archive fetched by Homebrew, excluding Homebrew itself and metadata. Installed means the sum of regular-file sizes within the installed `.app`, excluding symlinks so linked files are not counted twice. It excludes ebook libraries, conversion artifacts, backups, preferences, and caches. Disk allocation shown by `du` or Finder can differ.

To reproduce the installed measurement:

```python
from pathlib import Path

for name in ("Smallibre", "calibre"):
    bundle = Path("/Applications") / f"{name}.app"
    size = sum(
        path.stat().st_size
        for path in bundle.rglob("*")
        if path.is_file() and not path.is_symlink()
    )
    print(name, size, f"{size / 1_000_000:,.1f} MB")
```

The README uses decimal MB (1 MB = 1,000,000 bytes), rounded to one decimal place. Smallibre is 99.06% smaller by download and 99.24% smaller by installed file bytes in this snapshot. Calibre ships a universal bundle and a broader feature set; Smallibre ships an Apple Silicon bundle with a deliberately narrower scope.

The chart uses separate, labeled linear scales for download and installed size. Exact values are also provided in the README table for accessibility.
