# Useful Resources

Throughout this book, we've been learning Copper by building projects step by step. But the
Copper RS repository itself is a goldmine of resources that go far beyond what we've
covered. This chapter is a guided tour of where to find documentation, examples, and tools
in the [copper-rs repository](https://github.com/copper-project/copper-rs).

## Official documentation

The Copper project maintains a documentation site with detailed guides on every aspect of
the framework:

**[copper-project.github.io/copper-rs](https://copper-project.github.io/copper-rs/)**

Here are the most useful pages:

| Page | What you'll find |
|---|---|
| [Copper Application Overview](https://copper-project.github.io/copper-rs/Copper-Application-Overview) | Full walkthrough of a task graph and runtime |
| [Copper RON Configuration Reference](https://copper-project.github.io/copper-rs/Copper-RON-Configuration-Reference) | Complete schema for `copperconfig.ron` |
| [Task Lifecycle](https://copper-project.github.io/copper-rs/Task-Lifecycle) | Detailed explanation of `new`, `start`, `process`, `stop` |
| [Modular Configuration](https://copper-project.github.io/copper-rs/Modular-Configuration) | Includes, parameter substitution, composition |
| [Build and Deploy](https://copper-project.github.io/copper-rs/Build-and-Deploy-a-Copper-Application) | Building for different targets and deploying |
| [Supported Platforms](https://copper-project.github.io/copper-rs/Supported-Platforms) | What hardware and OS combinations are supported |
| [Baremetal Development](https://copper-project.github.io/copper-rs/Baremetal-Development) | Running Copper on microcontrollers without an OS |
| [Available Components](https://copper-project.github.io/copper-rs/Available-Components) | Catalog of drivers, algorithms, and bridges |
| [FAQ](https://copper-project.github.io/copper-rs/FAQ) | Common questions and answers |

Bookmark the configuration reference in particular -- it's the definitive source for every
field you can put in `copperconfig.ron`.

## The examples/ directory

The repository ships with a large collection of working examples. Each one is a complete,
buildable project that demonstrates a specific feature or use case:

Each example is a complete, buildable project with its own `copperconfig.ron`, task
implementations, and `main.rs`. When you want to learn a new feature, reading the
corresponding example is often the fastest way to understand how it works in practice.

Browse them at
[github.com/copper-project/copper-rs/tree/master/examples](https://github.com/copper-project/copper-rs/tree/master/examples),
or run any example from the repository root:

```bash
cargo run -p cu_missions
```

## Project templates

We used `cu_project` (Chapter 3) and `cu_full` (Chapter 15) to scaffold our projects, but
the templates directory has more to offer:

```text
templates/
├── cu_project/     # Simple single-crate project
├── cu_full/        # Multi-crate workspace with components
└── README.md       # Detailed usage guide
```

The `templates/README.md` documents all available `cargo generate` options, including how
to use the `cunew` alias and the `just gen-workspace` / `just gen-project` shortcuts.

## Docker images

The `support/docker/` directory contains Dockerfiles for building Copper projects in
containerized environments:

- **`Dockerfile.ubuntu`** -- Standard Ubuntu-based build environment
- **`Dockerfile.ubuntu-cuda`** -- Ubuntu with CUDA support for GPU-accelerated tasks

These are useful for CI pipelines or for building on machines where you don't want to
install the full Rust toolchain.

## Cross-compilation support

The `support/` directory also includes helpers for cross-compiling and deploying to
embedded targets:

```bash
just cross-armv7-deploy     # Build and deploy to ARMv7 (e.g., Raspberry Pi)
just cross-riscv64-deploy   # Build and deploy to RISC-V 64
```

These commands build release binaries for the target architecture and `scp` them to the
robot along with the `copperconfig.ron`.

## The Discord

Finally, the Copper project has an active
[Discord server](https://discord.gg/VkCG7Sb9Kw) where you can ask questions, share
your projects, and get help from the community and the framework authors.
