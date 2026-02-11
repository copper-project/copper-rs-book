# copper-rs-book

Most people learn Rust with the amazing [Rust Book](https://rust-book.cs.brown.edu/), so we built it for [Copper RS](https://github.com/copper-project/copper-rs).

This book has been written with the help of AI, for the sake of speed, proper grammar and formatting, but each and every line has been reviewed by a human. I am personally using this book to learn.

## Prerequisites

- [Rust](https://rust-lang.org/tools/install/)
- [mdBook](https://rust-lang.github.io/mdBook/)

Install mdBook:

```bash
cargo install mdbook
```

## Building the book

```bash
cd book
mdbook build
```

The HTML output is generated in `book/output/`.

## Viewing in the browser

To serve the book locally with live-reload:

```bash
cd book
mdbook serve --open
```

This starts a local development server (default: `http://localhost:3000`) and opens the
book in your browser. Any edits to the Markdown source files in `book/src/` will
automatically trigger a rebuild and refresh.

## Read online

This book is automatically deployed to GitHub Pages on every push to `main`:

**[https://nrdrgz.github.io/copper-rs-book/](https://copper-project.github.io/copper-rs-book/)**
