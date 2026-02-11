# From Project to Workspace

In Chapter 3, we generated a single-crate project with `cu_project`. That flat structure
is perfect for getting started, but as your robot grows -- more sensors, more algorithms,
shared components across multiple robots -- a single crate with everything in `tasks.rs`
becomes hard to manage.

Copper provides a second template, `cu_full`, that scaffolds a **Cargo workspace** with
a clear separation between applications and reusable components. In this chapter, we'll
generate one and understand its layout.

## Generating a workspace

From the `templates/` directory inside the Copper RS repository, run:

```bash
cargo +stable generate \
    --path cu_full \
    --name my_workspace \
    --destination . \
    --define copper_source=local \
    --define copper_root_path=../..
```

This creates a `my_workspace/` directory with a full workspace layout.

## What you get

```text
my_workspace/
├── Cargo.toml                          # Workspace root
├── justfile                            # Automation helpers
├── apps/
│   └── cu_example_app/                 # Your first application
│       ├── Cargo.toml
│       ├── build.rs
│       ├── copperconfig.ron
│       └── src/
│           ├── main.rs
│           ├── logreader.rs
│           ├── messages.rs
│           └── tasks/
│               ├── mod.rs
│               ├── local_example_src.rs
│               ├── local_example_task.rs
│               └── local_example_sink.rs
├── components/
│   ├── bridges/
│   ├── monitors/
│   ├── payloads/
│   ├── sinks/
│   ├── sources/
│   └── tasks/
└── doc/
```

That's a lot more structure than our simple `my_project/`. Let's walk through it.

## The workspace root: Cargo.toml

The top-level `Cargo.toml` defines the workspace and shared dependencies:

```toml
[workspace]
members = [
    "apps/cu_example_app",
    "components/bridges/cu_example_shared_bridge",
]
resolver = "2"

[workspace.dependencies]
cu29 = { path = "../../core/cu29" }
cu29-helpers = { path = "../../core/cu29_helpers" }
cu29-export = { path = "../../core/cu29_export" }
bincode = { package = "cu-bincode", version = "2.0", default-features = false, features = ["derive", "alloc"] }
serde = { version = "*", features = ["derive"] }
```

Every crate in the workspace references these shared dependencies with
`workspace = true` in its own `Cargo.toml`. This means you define dependency versions
**once** at the workspace level, and all crates stay in sync.

When you add a new application or component, you add it to the `members` list.

## The apps/ directory

This is where your **application crates** live. Each app is a standalone binary that owns
its own runtime configuration, log storage, and logreader.

The example app (`cu_example_app`) looks very similar to the `my_project` we built in
earlier chapters, but with two key differences.

### Messages are in their own file

Instead of defining `MyPayload` inside `tasks.rs`, the workspace template puts message
types in a dedicated `messages.rs`:

```rust
use bincode::{Decode, Encode};
use cu29::prelude::*;
use serde::{Deserialize, Serialize};

#[derive(Default, Debug, Clone, Encode, Decode, Serialize, Deserialize, Reflect)]
pub struct MyPayload {
    pub value: i32,
}
```

This makes it easier to share message types -- other files within the app import them
with `use crate::messages::MyPayload`.

### Tasks are in their own directory

Instead of one big `tasks.rs`, each task gets its own file under `src/tasks/`:

```text
src/tasks/
├── mod.rs                    # Re-exports all tasks
├── local_example_src.rs      # MySource
├── local_example_task.rs     # MyTask
└── local_example_sink.rs     # MySink
```

The `mod.rs` ties them together:

```rust
mod local_example_sink;
mod local_example_src;
mod local_example_task;

pub use local_example_sink::MySink;
pub use local_example_src::MySource;
pub use local_example_task::MyTask;
```

From the rest of the codebase, you still write `tasks::MySource` -- the internal file
structure is hidden behind the module.

This is standard Rust module organization, but it matters as your robot grows. When you
have 15 tasks, having them in separate files with clear names is much easier to navigate
than scrolling through a 1000-line `tasks.rs`.

### The copperconfig.ron is identical

The task graph configuration works exactly the same way. The only difference is that
message paths reference `crate::messages::MyPayload` instead of
`crate::tasks::MyPayload`, because the message type moved to its own module:

```ron
(
    tasks: [
        (
            id: "src",
            type: "tasks::MySource",
        ),
        (
            id: "t-0",
            type: "tasks::MyTask",
        ),
        (
            id: "sink",
            type: "tasks::MySink",
        ),
    ],
    cnx: [
        (
            src: "src",
            dst: "t-0",
            msg: "crate::messages::MyPayload",
        ),
        (
            src: "t-0",
            dst: "sink",
            msg: "crate::messages::MyPayload",
        ),
    ],
)
```

## The components/ directory

This is where **reusable components** live -- code that can be shared across multiple
applications or even published for other people to use.

The directory is organized by category:

| Directory | Purpose | Example |
|---|---|---|
| `sources/` | Sensor drivers that produce data | Camera driver, IMU reader |
| `sinks/` | Actuator drivers that consume data | Motor controller, GPIO writer |
| `tasks/` | Processing algorithms | PID controller, path planner |
| `bridges/` | Interfaces to external systems | Zenoh bridge, ROS bridge |
| `monitors/` | Monitoring and visualization | Console TUI, web dashboard |
| `payloads/` | Shared message types | Sensor payloads, spatial types |

The template generates these directories with placeholder `.keep` files. They're empty,
waiting for you to add your own components as your project grows. We'll cover how to
create shared components and how to reuse existing ones from the Copper ecosystem in the
[Reusing Community Components](./ch17-ecosystem.md) chapter.

## Where do message types go?

You might wonder: should messages go in `messages.rs` inside the app, or in a component
crate under `components/payloads/`? The answer depends on who needs them.

**App-local messages** stay in `messages.rs` inside the app. If `MyPayload` is only used
by the tasks within `cu_example_app`, it belongs right there. This is the most common case
when you're starting out -- and it's exactly where the template puts it.

**Shared messages** go into a component crate when multiple apps or components need the
same type. For example, if you have two robots that both use the same sensor data format,
you'd create a crate under `components/payloads/` and have both apps depend on it.

**Ecosystem messages** are already defined in Copper's built-in payload crates (like
`cu-sensor-payloads` for common sensor types). You don't write these -- you just depend on
them. We'll explore them in the
[Reusing Community Components](./ch17-ecosystem.md) chapter.

Here's the rule of thumb:

| Question | Put messages in... |
|---|---|
| Only used by tasks within one app? | `apps/my_app/src/messages.rs` |
| Shared between multiple apps in your workspace? | A crate under `components/payloads/` |
| Already defined by an existing Copper component? | Just depend on that crate |

When in doubt, start local. You can always move a message type into a shared crate later
when a second consumer appears.

## Running the workspace

From the workspace root, run the example app with:

```bash
cargo run -p cu_example_app
```

The `-p` flag tells Cargo which workspace member to build and run. This is different from
the simple project where `cargo run` was enough -- in a workspace with multiple binaries,
you need to be explicit.

## Simple project vs workspace: when to switch

You don't need to start with a workspace. Here's a simple rule of thumb:

| Situation | Use |
|---|---|
| Learning, prototyping, single-robot projects | `cu_project` (simple) |
| Multiple robots sharing components | `cu_full` (workspace) |
| Components you want to publish or reuse | `cu_full` (workspace) |
| Team projects with clear module boundaries | `cu_full` (workspace) |

The good news: migrating from a simple project to a workspace is just moving files around
and updating `Cargo.toml` paths. The task code, message types, and `copperconfig.ron`
format are identical in both cases.
