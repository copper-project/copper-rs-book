# Contributing

Thanks for your interest in improving the Copper Book! Contributions of all kinds are welcome : fixes, clarifications, new content, and more.

## Prerequisites

- [Rust](https://rust-lang.org/tools/install/)
- [mdBook](https://rust-lang.github.io/mdBook/)
- [just](https://github.com/casey/just) (command runner)

Install the tools:

```bash
cargo install mdbook just
```

## Building locally

Run `just` to see all available commands:

```bash
just
```

Build the book:

```bash
just build
```

Serve locally with live-reload:

```bash
just serve
```

This starts a local server (default: `http://localhost:3000`) and opens the book in your browser. Edits to files in `book/src/` trigger an automatic rebuild.

## Adding a chapter

Chapters are ordered by their position in `book/src/SUMMARY.md`, not by their
filename, so there is nothing to renumber. To add a chapter:

1. Create a slug-named file in `book/src/`, e.g. `book/src/my-new-topic.md`.
2. Add a line linking to it in `book/src/SUMMARY.md` at the position you want.

mdBook generates the chapter numbers automatically from the order in `SUMMARY.md`.

## Version markers

Use a permanent minimum-version marker for features or documented APIs introduced
in 1.0 or later. Leave features that predate 1.0 unmarked. Place a marker on its own
line immediately below a heading when it covers that section, or inline when only
one paragraph or list item needs it:

```html
<span class="version-marker" data-version="1.2">v1.2+</span>
```

`data-version` selects an official
[Catppuccin Mocha](https://catppuccin.com/palette/#mocha) background: Rosewater
`#f5e0dc` (1.0), Pink `#f5c2e7` (1.1), Mauve `#cba6f7` (1.2), or Lavender
`#b4befe` (1.3). Text uses Mocha Base `#1e1e2e` in every theme. The previous
palette is banned by the project's visual-design rules in `AGENTS.md`.
Keep the visible version text so color is never the only
cue. For a patch-level minimum, keep the minor in `data-version` and write the
full patch in the label. For backports, use paired labels with titles identifying
their release lines; do not imply that 1.1.4 support includes unpatched 1.2.0.

Markers describe availability, not release status, so they do not change when a
release ships. Update the single edition/release notice in
`book/src/introduction.md` instead. Keep experimental status, required Cargo
features, tools, and checkout directories in the tutorial's prerequisites.

Check the [feature/version mapping](./feature-versions.md) before adding or changing
a marker. Match the wiki release notes to the feature, then verify the actual
API in the corresponding copper-rs tag. A newer recipe or method can need a newer
marker than the underlying feature. For unreleased features, compare the checkout
against the latest release; do not guess from the version previously named in prose.

## How to contribute

1. **Fork** this repository on GitHub.

2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/<your-username>/copper-rs-book.git
   cd copper-rs-book
   ```

3. **Create a branch** for your changes:
   ```bash
   git checkout -b my-change
   ```

4. **Make your edits** in `book/src/` and verify them locally with `mdbook serve --open`.

5. **Commit and push** your changes:
   ```bash
   git add .
   git commit -m "Describe your change"
   git push origin my-change
   ```

6. **Open a Pull Request** against the `main` branch of this repository.

That's it, we'll review your PR and get it merged. Thank you!
