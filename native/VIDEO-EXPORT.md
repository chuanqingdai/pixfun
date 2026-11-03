# Source video export

The existing Export button has a dropdown with 1080p (default) and 4K. Selecting
one opens the standard save panel for filename/location only; there is no quality
selector or accessory panel in that dialog. Landscape, portrait and square retain the saved
timeline's aspect ratio. Low-resolution inputs do not gain original detail.

Exports use the same renderer, validated timeline, original source ranges, photo
preparation, sound, caption, transition and title layers as previews. Resolution
and H.264 encoding are explicit render settings; preview files and 720p shot
caches are never used as export sources. Cache keys include resolution and codec.
The LGPL FFmpeg build enables Apple's VideoToolbox encoder; encoding failures
are reported rather than silently exporting low-resolution or MPEG-4 Part 2.

`POST /api/desktop/agent/export` is native-authenticated and supports start,
status and cancel. Start captures the saved version and source fingerprints.
One export at a time uses the existing serial media-task executor, with separate
progress and cancellation state. Editing during export cannot alter its snapshot.
Missing or changed sources fail explicitly. Restart interrupts pending exports.
No model calls, skill loading or new timeline/catalog is involved.

The service writes only into its private export directory. It checks dimensions,
duration, audio/video streams and fully decodes the output before reporting ready.
The native client copies to a temporary sibling of the user-chosen destination,
then installs atomically. It protects original paths and hardlinks, rejects
symlink destinations, and checks that any approved existing file has not changed
while rendering. Cancellation/failure never publishes a partial destination.
Old preview export requests are rejected rather than exporting another version.
Unsaved editor changes must be saved; a saved edit can export without first
regenerating its 720p preview. Non-video artifact export remains unchanged.

Checks:

```sh
.desktop-venv/bin/python tests/video-export.test.py
node scripts/test-native.cjs
python3 scripts/verify-packaged-export.py dist-native/Pixfun.app
```
