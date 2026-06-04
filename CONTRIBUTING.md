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
