# Pixfun software palette

The landing page and editor share semantic tokens in `public/palette.css`, loaded after component styles. Photography supplies the travel atmosphere; large working surfaces remain neutral.

| Role | Color | Use |
| --- | --- | --- |
| Canvas | `#151819` | Workspace background |
| Surface | `#1d2123` | Media and conversation panels |
| Raised | `#272c2f` | Secondary controls and user messages |
| Input | `#292f32` | Editable fields |
| Preview | `#101213` | Neutral video surround |
| Text | `#e9ebe8` | Primary content |
| Secondary text | `#b1b9bc` | Descriptions and supporting information |
| Metadata | `#9aa5aa` | Times, filenames and placeholders |
| Brand | `#d7b581` | Primary actions and selected-item borders |
| Selected surface | `#343027` | Quiet selected-state tint |
| Focus | `#9bbfd9` | Keyboard focus, distinct from selection |
| Success | `#91cbaa` | Successful operations |
| Warning | `#e5c17d` | Caution with an accompanying message |
| Error | `#f0a2a2` | Errors with a readable explanation |
| Information | `#a4c5de` | Progress and structure labels |

## Usage rules

- Do not fill ordinary panels or every tag with the brand color.
- Separate hover, selection, keyboard focus, disabled, and loading states.
- Keep source video pixels unchanged. Do not apply UI tint filters to the editor preview.
- Keep status messages and existing selected-state attributes; color is not the sole signal.
- Use thin boundaries for panel grouping and stronger boundaries for editable controls.
- Retain restrained serif headings on the landing page and readable sans-serif working UI.

## Verification

`node tests/palette.test.cjs` checks core text/background pairs at 4.5:1, primary action labels at 4.5:1, and input boundaries/focus at 3:1. This covers the defined token pairs, not a full accessibility certification of the site or text over photography.
