# Desktop preview verification — 2026-09-27

Build: Pixfun 0.1.0, Apple Silicon. Local development build; no Developer ID signature or notarization.

Verified:

- Packaged `.app` starts its bundled standalone backend on a random loopback port, independently of the website on port 8765.
- Brand startup screen renders the new vector icon, typography and loading state. The normal launch enters Home automatically; the design preview adds no artificial delay to normal startup.
- Native file chooser imports `public/media/travel/hero-citywalk.mp4` by reference. Real analysis completes and the video can be played and sought through scene thumbnails.
- Favorite survives quitting and reopening the packaged application. `⌘2` opens Media. Singular counters render correctly.
- Three Node desktop tests pass (origin boundary, directory selection, sandbox/bridge configuration).
- Four service integration tests pass both from Python and from the frozen backend with the bundled media tools (auth/native grants; analysis, range serving and persistence; missing-file relink; stop/retry).
- Existing library, import, asset-understanding, scene navigation, related-filter, metadata and studio regression tests pass. `git diff --check` passes.
- DMG created using native `hdiutil`; disk image verification passes.
- Packaged icon matches the generated ICNS; startup SVG/JS/HTML are present in app.asar.
- Website health on port 8765 remains healthy; browser IndexedDB is untouched. User library data and imported source media are excluded from the application bundle.

Not yet verified: a clean second Mac, Intel hardware, old macOS versions, OS signing/notarization or public distribution. Speech models, visual understanding and automatic editing are not included. HEIC/TIFF conversion has a defensive implementation but has not been manually validated against a device library in this pass.
