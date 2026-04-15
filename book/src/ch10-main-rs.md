# The Remaining Files and Running

We've covered `copperconfig.ron` and `tasks.rs` -- the two files you'll edit most. Now
let's look at the three remaining files: `main.rs`, `build.rs`, and `Cargo.toml`. These
are mostly boilerplate that you write once and rarely touch.

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
    let mut application = MyProjectApplication::builder()
        .with_log_path(logger_path, PREALLOCATED_STORAGE_SIZE)
        .expect("Failed to setup logger.")
        .build()
        .expect("Failed to create application.");
    debug!("Running... starting clock: {}.", application.clock().now());

    application.run().expect("Failed to run application.");
    debug!("End of program: {}.", application.clock().now());
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

**`application.run()`** -- Starts the deterministic execution loop. Calls `start()` on
all tasks, then enters the cycle loop (`preprocess` -> `process` -> `postprocess` for
each task, in topological order), and continues until you stop the application (Ctrl+C).

**`application.clock()`** -- Returns the runtime clock handle. The builder creates a
default clock unless you override it with `.with_clock(...)`, which is mainly useful in
tests or simulation.

## build.rs -- log index setup

```rust
fn main() {
    println!(
        "cargo:rustc-env=LOG_INDEX_DIR={}",
        std::env::var("OUT_DIR").unwrap()
    );
}
```

This sets the `LOG_INDEX_DIR` environment variable at compile time. Copper's logging macros
(`debug!`, `info!`, etc.) need it to generate a string index for log messages. Without it,
you'll get:

```text
no LOG_INDEX_DIR system variable set, be sure build.rs sets it
```

**You never need to change this file.** Just make sure it exists.
