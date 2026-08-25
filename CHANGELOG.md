# Changelog

## Unreleased

- Merge upstream forest.hx 0.1.1, including sibling-wrapping snacks navigation, `h`/`l` folder traversal preserved with Steel's native `parent-name`, sidebar geometry accessors, reserved-bar clipping, open/close cursor fixes, single-close focus handoffs that keep the background tree visible, covered native-picker dismissal when Forest opens a file, valid redraws after closing or resizing the sidebar, hidden lower-modal cursors while Forest is focused, and an optional native chord for toggling focus from either side or over a native modal.

## 0.2.0

- Confine create and rename targets to the workspace and selected parent, including symlink-ancestor checks, exclusive file creation, and exact-destination rename semantics.
- Refuse to delete non-empty directories instead of recursively removing their contents, while deleting directory symlinks without touching their targets.
- Keep directory traversal on real entries so tree expansion and mini previews never follow directory symlinks, and identify those entries accurately in delete confirmations.
- Permit confined rename of dangling symlink entries; deletion remains link-local.
- Keep filtered workspace roots visible in snacks and protect the root itself from deletion.
- Report a bounded search as truncated only when at least one entry was omitted.
- Resolve repeated path components through native parent semantics so current-file reveal and nested creation remain correct.
- Parse Git status and ignored entries through NUL-delimited porcelain records, retain conflict and type-change markers, and refresh state after explicit refreshes and mutations.
- Share hidden, ignored, and Git-ignored visibility semantics across both trees and searches.
- Load search inventories on demand with a 5,000-entry work budget so live fuzzy matching remains responsive.
- Bound mini previews to 200 lines and 64 KiB, with binary and unreadable-file fallbacks.
- Pin notify.hx and glyph.hx to exact revisions.
- Add isolated native Steel regression checks, including a complete-plugin syntax gate.
