# Web cloud analysis / native local analysis

The web report uses the server-only `/api/vision` endpoint and OpenAI Responses API.
The default vision model is `gpt-4.1-mini`; override it with `PIXFUN_VISION_MODEL`.
Set `OPENAI_API_KEY` in the web server process environment and restart `app.py`.
`.env.example` documents the names; `.env` files are not loaded automatically.
Never paste a key into chat, browser JavaScript, IndexedDB, or the native bundle.

## Data and output

- Videos: three 960-pixel, aspect-preserving frames per scene, at most 24 images.
- Photos: one resized JPEG, at most 960 pixels on the longest side.
- Only frames and scene IDs/timestamps go to OpenAI. The original video, filename,
  transcript, API key, and local path are not included in the model prompt.
- `store: false` is sent. This is not a promise of zero provider retention;
  OpenAI's account/data policies still apply.
- Strict JSON output: overall description, visible people/animals, objects,
  setting, actions, visual style, readable text, uncertainties, per-scene descriptions.
- These are **sampled-frame descriptions**, not exhaustive frame-by-frame analysis.
- API failures retain file metadata and display an explicit retryable state.
- Old reports are not silently uploaded; choose **Analyze content** to analyze them.
- Successful video results are cached with the job; retries reuse them.
- API keys and upstream raw errors are never returned to the browser.

Audio transcription still uses the existing local MLX Whisper pipeline on the
web server. Runaway repetition is excluded and flagged for review, not corrected
by inventing dialogue. An excluded cue can include legitimate repeated lyrics;
this is a quality warning, not proof that the original audio has no speech.

## Mac boundary

The native app does not dispatch `/api/vision`, call OpenAI, or fall back to cloud.
It retains local FFmpeg analysis and embedded subtitle extraction. **A local visual
language model is not bundled or installed yet**; choosing the local route does not
make visual scene descriptions available in the existing Mac build. No model
download or cloud fallback is performed automatically.

## Verification

`node tests/web-analysis.test.cjs`

`.venv/bin/python tests/cloud-vision.test.py`

Tests use offline response fixtures and exercise the actual local HTTP route;
they do not send media to OpenAI or demonstrate real model quality. A configured
server API key and a live authorized sample are needed for the final cloud check.

Official implementation references:
- https://developers.openai.com/api/docs/guides/images-vision
- https://developers.openai.com/api/docs/guides/structured-outputs
