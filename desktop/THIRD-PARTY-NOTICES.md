# Pixfun desktop preview — third-party components

- Electron: MIT; Chromium and bundled dependencies have their own licenses, included by Electron in the application resources.
- Python: PSF License; the standalone service includes the Python runtime. PyInstaller is GPL with its bootloader exception allowing distribution of bundled applications.
- FFmpeg and FFprobe: built from the official FFmpeg 9.0.2 release, **without GPL or nonfree components** and without optional third-party libraries. LGPL v2.1 or later. They run as separate command-line programs, not linked into Pixfun. The complete unmodified corresponding source archive, license and exact build script are included under `Contents/Resources/licenses/ffmpeg`. Users may rebuild and replace these programs under `Contents/Resources/bin` in this unsigned development build. FFmpeg project: https://ffmpeg.org/.
- Existing website fonts and visual media retain their original licenses and credits in the repository's ASSETS.md and media source records. No user library, user footage, downloaded test collection, model cache or credentials are included in the app.

This is a local development preview, not a signed/notarized public release. Release engineering must review all component notices, supported OS versions and codec distribution obligations before public distribution.

## Starter music library

Carefree, Life of Riley, and With the Sea by Kevin MacLeod (incompetech.com) are distributed unmodified under Creative Commons Attribution 4.0 International: https://creativecommons.org/licenses/by/4.0/ . Track sources and credits are included in `Contents/Resources/Music/ATTRIBUTION.txt` and `catalog.json`. These recordings remain separately licensed CC BY assets, without additional application-license restrictions or an implied endorsement. The app displays publishing credits, embeds them in rendered MP4 metadata, and offers a credits export. Users must retain attribution when publishing; video platforms may remove metadata.

Standard narration uses voices installed with macOS through the system speech service. Pixfun does not bundle or clone third-party reference voices, and does not download voice models automatically.

# Local people recognition

YuNet (2023mar), Copyright Shiqi Yu, MIT; SFace (2021dec), OpenCV Zoo contributors, Apache-2.0. Unmodified ONNX weights are bundled in `PeopleModels` with their full licenses. Source: https://github.com/opencv/opencv_zoo/tree/main/models . Models are used offline for face grouping, not identity lookup. OpenCV Python headless 4.11.0.86 and NumPy 1.26.4 are bundled through PyInstaller with their package licenses.
