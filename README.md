# copper-rs-book

I learnt Rust by using the fantastic [Rust Book](https://rust-book.cs.brown.edu/), so I
wanted to reproduce this experience with a book for
[Copper RS](https://github.com/copper-project/copper-rs).

As of today, this project is purely personal and does not involve the Copper RS team, so
any missing or faulty information is my own responsibility.  
I've originally built this book first and foremost for myself. I believe that the best way to properly understand a concept is to be able to clearly and simply explain it.

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

**[https://nrdrgz.github.io/copper-rs-book/](https://nrdrgz.github.io/copper-rs-book/)**

## Future chapters to be written:
- Bridge to ROS
- Export logging to other formats
- Bridge to Foxglove