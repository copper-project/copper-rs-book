# Setting Up Your Environment

Before we can build a Copper project, we need Rust and the Copper project template.

## Install Rust

Follow the official installation guide at <https://rust-lang.org/tools/install/>, or run:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

After installation, make sure `cargo` is available:

```bash
cargo --version
```

## Install cargo-generate

`cargo-generate` lets you scaffold a new Copper project from the official template:

```bash
cargo install cargo-generate
```

## Generate our first simple Copper project

Clone the Copper RS repository and use the built-in template tool:

```bash
git clone https://github.com/copper-project/copper-rs
cd copper-rs/templates

cargo +stable generate \
    --path cu_project \
    --name my_project \
    --destination . \
    --define copper_source=local \
    --define copper_root_path=../..
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