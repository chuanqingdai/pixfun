# Native client verification — 2026-09-30

Build: `dist-native/Pixfun.app`, arm64 Mach-O, about 226 MB with offline face models and OpenCV/NumPy. Swift 5.10, macOS 26.6.2 test host, deployment target macOS 13. Ad-hoc signature verified with `codesign --verify --deep --strict`. `otool -L` confirms SwiftUI, AppKit and AVKit; no Chromium/Electron/WebKit runtime is bundled.

## Automated checks

- `npm run test:desktop`: 47 native model/import/navigation/filter checks, 2 real DM Sans registration checks, 9 creator-strategy compatibility checks, 12 Node architecture/legacy/style/composer/selection regressions passed. People checks cover background exclusions, cross-clip filters, location facets, corrupted-index preservation, manual corrections across rescans, reversible merges and cycle rejection.
- `node --test tests/desktop-skills.test.cjs`: 4 creator-skill tests passed, including the Travel Vlog source reference, five-beat framework, six-principle summary, cover, and brief size limit. The imported v5.4 source was byte-compared with the supplied original without modifying it.
- Python service integration suite: 10 passed against the packaged executable, using temporary databases; source passed its original nine plus the new offline recognition test individually. Native-only APIs check authentication, origin protection, relinking, remove/restore, face inference/cache restart and unchanged source bytes. A first frozen-suite model call timed out during concurrent release compilation; isolated recognition passed in 3.2 seconds and the full frozen suite then passed in 46 seconds.
- `tests/local-people.test.py`: four checks passed using actual YuNet/SFace inference on a real project image and a lighting variant, stable cross-asset/restart groups, unchanged source bytes, prominence filtering and conservative matching. This is a smoke test, not an accuracy benchmark. A separate real Glacier 30-second excerpt sample produced one eligible group and suppressed one transient group.
- Release compilation passed after replacing the SwiftUI VideoPlayer wrapper with direct `AVPlayerView` integration.
- Native DMG packaging script syntax checked; DMG creation, Intel, Developer ID signing, notarization and App Store review were not exercised.

## Actual native UI checks

1. Launched with `/tmp/pixfun-native-qa.B1v6rc` as isolated storage.
2. Imported `qa/media-library/captioned-test.mp4` through NSOpenPanel. Analysis produced three segments and two subtitle entries.
3. Opened the native AVKit player, played the clip, sought to the second segment (~4 s), and sought from a subtitle (~3 s).
4. Opened Outdoor adventure skill, inspected its story framework, and used it in Home.
5. Entered a test brief, selected the clip through From Media, returned with its cover and skill, and saved it. The Project list showed the saved test brief and attachment.
6. Restarted the test app; the imported media/draft survived. Test records were never placed in the real library.
7. Backed up the real database to `build-native/library-before-native-20260930.sqlite3` before opening the native client against it.
8. Verified all 16 original library records and existing favorite state in the native masonry view. Opened the Glacier 11:30 video and read the eight navigation chapters and 165 subtitle entries. Verified actual playback of the long original after loading. Duplicate import was correctly rejected without adding a second record.
9. Verified the compact single-row Media filters: selecting the travel-long folder showed three files; searching for Glacier reduced the result to one.
10. Opened Glacier as an in-window child page, with the sidebar retained and no sheet. Confirmed the full original path, Copy path and Show in Finder controls, native video frame, eight segments and 165 subtitle entries. Returning to Media preserved both the folder and name search.
11. Verified the compact View options menu contains sorting and search scope, then cleared filters and left the app on the complete 16-file Media library. The website and original media were not modified.
12. Web-style native pass: visually checked Home, Media, its detail child page and Skills. Confirmed charcoal/gold tokens, bundled DM Sans, flatter buttons, underlined category tabs and unified sidebar/card styling. From Media enters selection mode with import buttons hidden; choosing a clip enables Add 1 to brief; Cancel exits without changing the draft. Name search updates results, and opening/returning from the Glacier detail preserves the query. The original file path wraps without overlapping its actions.
13. Composer/brand correction: confirmed the approved web wordmark in the sidebar and no duplicate decorative star above the Home heading. Empty and focused editor screenshots show no scrollbar gutter or focus outline. Pasted Chinese/English text and pressed Return: newline inserted, no project saved, save button enabled. Pasted 16 lines: editor grew to its cap and scrolled internally while actions stayed fixed. Cmd-Z restored the short text; clearing it restored the original empty draft, placeholder, compact height and disabled save button. No test project was created. IME marked-text preservation is implemented but an actual input-method composition session was not exercised.

14. Travel Vlog v5.4: restarted the updated client and confirmed nine skills, with Travel Vlog first. Inspected its real travel cover, five story beats, six key principles and Full skill versioned link in the native child page. Use skill returned to Home with the Travel Vlog chip; removed that test selection to restore the previously empty draft without saving a project. Bundled specification byte-matches the imported original and code signing passed. The full document was verified on disk; opening it in an external editor was not exercised. No automatic rendering was attempted.

15. Media selection contrast: release build/signature passed. Verified 30 pt white-ring controls with opaque charcoal backing across bright scenery and dark street covers. Selecting Glacier shows a gold fill, dark checkmark, selected card border, accessible Deselect label and Add 1 count. Deselecting restores the empty ring and disables Add 0. Left Media in selection mode with no selected files; no assets were added to the draft or projects.

## Remaining limitations

- Real native UI verified: location circle filters Glacier to one file; an automatically cropped person avatar becomes selected and filters its matching clip; the detail child page shows the four automatically detected groups and individual management menus, including Same person as, Not this person in this clip and Exclude as background person. Final build restarted with cached results intact and finished all 16 library assets: 833 sampled frames, eight eligible face groups (not eight verified individuals), no visible scan errors. Side-facing views can create duplicate groups. Explicit merge/separate is tested without assigning real-world identities. Broad recognition accuracy and perfect bystander exclusion are not claimed.

- Large existing recordings can take noticeably longer to load in AVKit than short test clips. The app displays a non-blocking warning after 15 seconds and offers retry; the warning clears when the player becomes ready. Cold-start latency still needs profiling. Do not claim instantaneous long-video playback.
- Native playback depends on system-supported codecs. Analysis can accept more formats than AVKit can play.
- Offline face detection/grouping is now implemented; general semantic video understanding, speech recognition, automatic montage and timeline export remain unimplemented. Embedded and sidecar subtitles are extracted; descriptions are not inferred from transcripts.
- The native app was left open on Media using the real library. The old Electron source/bundle and website were not replaced or removed.
