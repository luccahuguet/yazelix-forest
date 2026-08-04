# Changelog

## 0.2.0

- Confine create and rename targets to the workspace and selected parent, including symlink-ancestor checks.
- Refuse to delete non-empty directories instead of recursively removing their contents.
- Parse Git status and ignored entries through NUL-delimited porcelain records and refresh state after explicit refreshes and mutations.
- Share hidden, ignored, and Git-ignored visibility semantics across both trees and searches.
- Load search inventories on demand with a 5,000-entry work budget so live fuzzy matching remains responsive.
- Bound mini previews to 200 lines and 64 KiB, with binary and unreadable-file fallbacks.
- Pin notify.hx and glyph.hx to exact revisions.
- Add isolated native Steel regression checks.
