# Setting Up Your Environment

Before we can build a Copper project, we need Rust 1.95 or newer and the Copper project
bootstrap tool.

## Install Rust

Follow the official installation guide at <https://rust-lang.org/tools/install/>, or run:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

After installation, make sure `cargo` is available and recent enough:

```bash
cargo --version
rustc --version
```

## Install cargo-cunew

`cargo-cunew` scaffolds a new Copper project from the official Copper templates:

```bash
cargo install cargo-cunew
```

## Generate our first simple Copper project

Generate a new project directly:

```bash
cargo cunew my_project
```

This generates a complete, ready-to-compile Copper project at the path you specify.

For more details, see the official documentation:
<https://copper-project.github.io/copper-rs/Project-Templates/>

## What you get

The generated project contains everything you need:

```text
my_project/
├── build.rs              # Build script (required by Copper logging)
├── Cargo.toml            # Dependencies
├── copperconfig.ron      # Task graph definition
└── src/
    ├── main.rs           # Runtime entry point
    └── tasks.rs          # Your task implementations
```

In the next chapter, we'll explore what each of these files does.

## Try it

You can try to compile and run your project:

```bash
cd my_project
cargo run
```

It will compile and run, and you'll start to receive some messages:

```text
00:00:01.1781 [Debug] Received message: 42
00:00:01.1781 [Debug] Sink Received message: 43
```

Kill the process and let's move to the next chapter.
