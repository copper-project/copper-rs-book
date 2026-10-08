# The Remaining Files and Running

We've covered `copperconfig.ron` and `tasks.rs` -- the two files you'll edit most. Now
let's look at `main.rs`, `build.rs`, and the relevant `Cargo.toml` bits. These are mostly
boilerplate that you write once and rarely touch. We'll come back to `logreader.rs` in
[Logging and Replaying Data](./logging-replay.md) and replay via `resim.rs` later.

## main.rs -- the entry point

```rust
pub mod tasks;

use cu29::prelude::*;
use std::path::Path;
use std::thread::sleep;
use std::time::Duration;

const PREALLOCATED_STORAGE_SIZE: Option<usize> = Some(1024 * 1024 * 100);

#[copper_runtime(config = "copperconfig.ron")]
struct MyProjectApplication {}

fn main() {
    let logger_path = "logs/my-project.copper";
    if let Some(parent) = Path::new(logger_path).parent() {
        if !parent.exists() {
            std::fs::create_dir_all(parent).expect("Failed to create logs directory");
        }
    }
    debug!("Logger created at {}.", logger_path);
    debug!("Creating application... ");
    let application = MyProjectApplication::builder()
        .with_log_path(logger_path, PREALLOCATED_STORAGE_SIZE)
        .expect("Failed to setup logger.")
        .build()
        .expect("Failed to create application.");
    debug!("Running... starting clock: {}.", application.clock().now());

    let stopped = application.run_until_shutdown().expect("Failed to run application.");
    debug!("End of program: {}.", stopped.clock().now());
    sleep(Duration::from_secs(1));
}
```

Here's what each part does:

**`pub mod tasks;`** -- Brings in your `tasks.rs`. The task types you defined there
(e.g., `tasks::MySource`) are what `copperconfig.ron` references.

**`#[copper_runtime(config = "copperconfig.ron")]`** -- The key macro. At **compile time**,
it reads your config file, parses the task graph, computes a topological execution order,
and generates a custom runtime struct with a deterministic scheduler. It also creates a
builder struct named `MyProjectApplicationBuilder`. The struct itself is empty -- all the
generated code is injected by the macro.

**`PREALLOCATED_STORAGE_SIZE`** -- How much memory (in bytes) to pre-allocate for the
structured log. 100 MB is a reasonable default.

**`MyProjectApplication::builder()`** -- Creates the generated application builder.
You provide the pieces you want to override, such as the clock, config override, or
resource factory.

**`.with_log_path(...).build()`** -- Wires
everything together: creates each task by calling their `new()` constructors,
pre-allocates all message buffers, and sets up the scheduler.

**`application.run_until_shutdown()`** -- Starts the deterministic execution loop. Calls `start()` on
all tasks, then enters the cycle loop (`preprocess` -> `process` -> `postprocess` for
each task, in topological order), and continues until you stop the application (Ctrl+C).
It consumes the initialized handle and returns a stopped handle, so the code uses
`stopped.clock()` after the run.

**`application.clock()`** -- Returns the runtime clock handle. The builder creates a
default clock unless you override it with `.with_clock(...)`, which is mainly useful in
tests or simulation.

## build.rs -- build-time setup

Keep the template's complete build script:

```rust
fn main() {
    cu29_build::setup();
}
```

The generated `Cargo.toml` already includes `cu29-build` under
`[build-dependencies]`. This helper prepares the interned string index used by
Copper's structured logging and the other build-time metadata. Keep its Copper
source and version aligned with `cu29`.
