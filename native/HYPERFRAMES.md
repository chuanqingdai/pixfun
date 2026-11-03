# Motion graphics in Media / VisionFlow 0.9.1

Creator skills include Motion Titles, Journey Route and Highlight Counter.
These parameter-based adapters use the existing HyperFrames 0.8.123 renderer,
GSAP 3.14.2 and Node.js 24.6.0. The generator in VisionFlow 0.9.1 matches the
reviewed source checksum enforced by `scripts/vf_hyperframes.py`.

Use a skill in the Agent conversation, or choose Graphics beside Build preview
or inside the editor's caption controls. The existing draft/undo/save mechanism
retains the selected graphic. Only one graphic is applied per film. Opening
graphics require a shot of at least 2.5 seconds; ending text needs 2.5 seconds
of total footage. Route names and counter values must be provided explicitly.
Routes are schematic, not verified GPS tracks. Graphics do not extend a film.

New films retain Media's highlight-analysis and trip-confirmation gate. Adding
a motion skill to an existing edit preserves its shot sequence. Source media
remains unchanged. The generated animation project can be exported from its
conversation action.

The packaged runtime is in Resources/HyperFrames. Local Chrome is required.
Rendering uses the existing macOS isolation profile with local-only connections,
bundled templates and stripped environment variables. There is no runtime
download or automatic cloud fallback. Runtime licenses travel with the package.

Validation:

```
PIXFUN_TEST_SANDBOX=1 .desktop-venv/bin/python tests/motion-skills.test.py
PIXFUN_TEST_HYPERFRAMES=1 .desktop-venv/bin/python tests/hyperframes.test.py
PIXFUN_TEST_HYPERFRAMES=1 .desktop-venv/bin/python tests/travel-graphics.test.py
```
