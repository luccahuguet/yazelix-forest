# Yazelix Forest

Yazelix Forest is a maintained fork of [forest.hx](https://github.com/Ra77a3l3-jar/forest.hx). It is a file tree explorer for [Helix](https://github.com/helix-editor/helix/) with two selectable styles: `snacks`, a persistent sidebar panel with an integrated fuzzy search bar (default), and `mini`, floating Miller columns with a live preview.

### 🍿 `snacks` style

![forest.hx snacks preview](.github/assets/preview-snacks.gif)

<details>
<summary>🔍 <code>mini</code> style preview</summary>

![forest.hx mini preview](.github/assets/preview-mini.gif)

</details>

---

## Installation

**1. Install the plugin-enabled fork of Helix** by following the instructions [here](https://github.com/mattwparas/helix/blob/steel-event-system/STEEL.md).

**2. Install forest.hx via forge:**

```sh
forge pkg install --git https://github.com/luccahuguet/yazelix-forest.git
```

**3. Load the plugin** by adding this to your `init.scm`:

```scheme
(require "forest/forest.scm")

;; Optional: which side the tree renders on ('left by default), and which
;; entry names are always hidden
(forest-configure! 'left #:ignore (list ".git" "target" "__pycache__"))

;; Optional: which explorer UI forest-open uses ('snacks by default)
;; (forest-set-style! style)
(forest-set-style! 'snacks) ; or 'mini

;; Optional (snacks): give the sidebar its own background per focus state, so the
;; tree stands apart from the buffer.
(forest-set-sidebar-bg! #:focused "#1e1e2e" #:unfocused "#181825")

;; Optional (snacks): color the search box outline. It marks focus by default
;; (orange focused, white unfocused); override the colors, or stop it changing.
(forest-set-search-color! #:focused "#89b4fa" #:unfocused "#585b70")
(forest-set-search-color! #:always "#89b4fa")            ; one color, both states
(forest-set-search-color! #:focused "#89b4fa" #:follow-focus? #f) ; never changes
```

Bind `:forest-open` to a key, e.g. in `init.scm`:

```scheme
(keymap (global)
        (normal (space (e ":forest-open"))))
```

---

## Usage

### `snacks` style

| Key | Action |
|-----|--------|
| `↑` / `↓` / `j` / `k` | Navigate |
| `Enter` | Open the selected file, or toggle the selected directory |
| `Tab` | Toggle the selected directory (outside search) |
| `/` | Start typing a fuzzy search query |
| `n` | Create a file or directory (end name with `/` for a directory) |
| `r` | Rename the selected entry |
| `d` | Delete the selected entry |
| `R` | Refresh the tree, search inventory, and Git state |
| `.` | Toggle dotfiles (`.env`, `.git`, etc.) |
| `i` | Toggle git-ignored entries |
| `+` / `-` | Widen / narrow the panel |
| `Space` | Open the which-key menu; press any listed key to run its action (`Esc` dismisses) |
| `Esc` | Switch focus to the editor, panel stays open |
| `q` | Close the panel |

Opening or refocusing the tree reveals and centers whatever file is currently open in the editor.

| Mouse | Action |
|-------|--------|
| Click an entry | Select it, focusing the panel first if the editor had focus |
| Click it again | Open the file, or toggle the directory |
| Click the search box | Start typing, keeping whatever query is already there |
| Wheel over the panel | Scroll the selection |
| Click in the buffer | Return focus to the editor, panel stays open |

### `mini` style

| Key | Action |
|-----|--------|
| `↑` / `↓` / `j` / `k` | Move within the active column |
| `→` / `l` / `Enter` | Open the selected file, or cascade into the selected directory |
| `←` / `h` | Back up to the parent column |
| `/` | Fuzzy search the whole workspace and jump to the match |
| `n` | Create a file or directory (end name with `/` for a directory) |
| `r` | Rename the selected entry |
| `d` | Delete the selected entry |
| `R` | Refresh the columns and Git state |
| `.` | Toggle dotfiles (`.env`, `.git`, etc.) |
| `i` | Toggle git-ignored entries |
| `+` / `-` | Widen / narrow the columns |
| `Space` | Open the which-key menu; press any listed key to run its action (`Esc` dismisses) |
| `Esc` / `q` | Close |

Opening the tree reveals whatever file is currently open in the editor, cascading a column for each ancestor directory along the way.

| Mouse | Action |
|-------|--------|
| Click an entry | Select it; in an ancestor column, drop the columns cascaded off it |
| Click it again | Open the file, or cascade into the directory |
| Click in the preview | Cascade into the previewed directory, landing on the entry clicked |
| Wheel over the active column or preview | Move the selection |
| Click off the columns | Close |

## Notes

- Press `Space` opens the which-key menu in the bottom right corner, and when pressed any listed key to run its action.
- Mouse support needs Helix's own `editor.mouse` left on (it is by default).
- Two clicks on an entry activate it. They needn't be quick, but a keypress in between cancels.
- Create paths stay within the canonical workspace, and rename accepts one basename in the selected entry's parent. Traversal, absolute paths, alternate separators, existing targets, and symlinked ancestors are rejected.
- Directory deletion is non-recursive and fails unless the selected directory is empty.
- Tree and search visibility share the same explicit-ignore, dotfile, and Git-ignored policy.
- Search is loaded on demand and visits at most 5,000 directory entries per inventory. This bound keeps live fuzzy matching responsive in large workspaces. Mini previews retain at most 200 lines from the first 64 KiB of a file; binary and unreadable files are not rendered as text.
- Git state uses NUL-delimited porcelain records, so whitespace, quotes, newlines, and renames remain filename-safe. Explicit refresh and successful mutations rescan it without polling.

## Native checks

The regression suite uses Steel and isolated temporary workspace, Git, and package roots. It does not read user configuration, reach the network, or leave child processes running.

```sh
tests/run.sh
```

Set `FOREST_STEEL_BIN` when the exact consumer Steel executable is not named `steel`. Yazelix validates against Steel revision `b67efd5c262962226424148bb87abefaf4109c5a`, embedded in its Helix revision `19b9ac4d`.

## Fork and dependency policy

- Upstream history begins at forest.hx revision `c487956a8f002813fe44ae2a30fffe1859fcc206`; the upstream MIT license and Raffaele Meo's attribution remain intact.
- `main` is the accepted fork line. Work uses short-lived `agent/*` branches and reviewable pull requests. Upstream updates are reviewed against the maintained delta before `main` advances.
- Release tags are immutable. Consumers pin an exact Yazelix Forest release revision rather than a moving branch.
- Forge resolves [notify.hx](https://github.com/chuwy/notify.hx) at `0a328073e6d3e5041346374ae747c275ab8ce746` and [glyph.hx](https://github.com/Ra77a3l3-jar/glyph.hx) at `1e63ccbc8f17511543412c955879ba672f3f8ec1`. Both are leaf packages with no further dependencies.
- Forest owns plugin behavior and dependency declarations. A consuming distribution owns its exact Forest pin, Helix/Steel composition, and end-to-end packaging proof.
