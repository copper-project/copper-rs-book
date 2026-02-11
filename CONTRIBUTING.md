# Contributing

Thanks for your interest in improving the Copper Book! Contributions of all kinds are welcome : fixes, clarifications, new content, and more.

## Prerequisites

- [Rust](https://rust-lang.org/tools/install/)
- [mdBook](https://rust-lang.github.io/mdBook/)

Install mdBook:

```bash
cargo install mdbook
```

## Building locally

Build the book:

```bash
cd book
mdbook build
```

The HTML output is generated in `book/output/`.

To serve the book locally with live-reload:

```bash
cd book
mdbook serve --open
```

This starts a local development server (default: `http://localhost:3000`) and opens the book in your browser. Any edits to the Markdown source files in `book/src/` will automatically trigger a rebuild and refresh.

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
