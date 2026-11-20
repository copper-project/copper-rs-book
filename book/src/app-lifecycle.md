# Choosing an Application Lifecycle

A robot with one graph can usually let Copper start its tasks, run them until
shutdown, and stop them. Both project templates use
`builder().build()?.run_until_shutdown()?`. Keep that default for the
[application you built in the first project](./main-rs.md).

<span class="version-marker" data-version="1.4">v1.4</span>
Copper 1.4.0-dev adds experimental options for applications that need to decide
when to stop, share a process with a UI, or switch between named missions.

| What owns the decision? | What to use |
| --- | --- |
| Copper handles shutdown for a single graph | `run_until_shutdown()` |
| The application has a stop condition, such as a capture deadline | `start()`, `run_until(predicate)`, then `stop()` |
| A UI or service needs its own thread to stay responsive | `CuRunner::spawn` on a host with `std` |
| The application switches between graphs declared in RON | The generated mission runner, named `AppRunner` for an application named `App` |

## Try a mission switch

From the root of a Copper 1.4.0-dev checkout containing the supervised camera
example, run this on your development machine with the default Cargo features.
The camera is simulated.

```sh
cargo run -p cu-missions --example supervised
```

The program opens the camera in the idle mission. After one second it switches
to recording, waits for the first frame, records for one second, requests
end-of-stream, and drains the last frame before returning to idle. Each
transition stops the old graph and releases its camera before the next graph
opens it. The program exits and leaves a `missions_0.copper` log in the checkout
root. To verify that the archive contains the three activations in order, run
the example's resource-handoff test.

```sh
cargo test -p cu-missions --example supervised transitions_release_the_camera_and_keep_each_recording
```

Read `examples/cu_missions/examples/supervised.rs` alongside its
`supervised.ron`. The example calls `transition_to(AppMission::Recording)`
before `wait_until_ready` because successful startup means the task start hooks
have finished. The first frame can arrive on a later iteration. Both
`wait_until_ready` and `drain_until` drive the active graph, take a `CuDuration`
timeout, and check a nonblocking device predicate. The application requests
end-of-stream itself. See [Using Missions](./missions.md) to declare your own graphs.

## Stop a single graph at a deadline

To try the other lifecycles with the same camera, replace just `fn main()` in
`examples/cu_missions/examples/supervised.rs` with either function below and
rerun the same `cargo run` command. Here `idle::App` selects one generated graph.
In a single-graph project use the application type from your own `main.rs`.

```rust
fn main() -> CuResult<()> {
    let clock = RobotClock::default();
    let mut app = idle::App::builder().with_clock(clock.clone()).build()?.start()?;
    let deadline = clock.raw_now() + CuDuration::from_secs(2);
    let run = app.run_until(|| clock.raw_now() >= deadline);
    let stop = app.stop();
    let exit = run?;
    stop?;
    println!("Graph stopped: {exit:?}");
    Ok(())
}
```

After two seconds the program prints `Graph stopped: Requested`. Copper checks
the predicate between iterations. A Copper shutdown returns `Shutdown`.
`run_until` leaves the graph running, so the caller can resume it or stop it.
Saving the run result lets the caller attempt cleanup even if an iteration fails.

## Let a UI or service request shutdown

This host example uses the Enter key for the event a UI would deliver through
its close callback. The Copper thread builds and drives the graph while the
main thread waits for input.

```rust
fn main() -> CuResult<()> {
    let runner = CuRunner::spawn(|| idle::App::builder().build())?;
    let control = runner.control();

    println!("Press Enter to stop the camera.");
    std::io::stdin().read_line(&mut String::new()).expect("read stdin");
    control.request_stop();
    let exit = runner.join()?;
    println!("Camera released: {exit:?}");
    Ok(())
}
```

Press Enter to see `Camera released: Requested`. In a UI, move the control handle
into the close callback. Its stop request returns immediately. Call `join()`
after the event loop exits to wait for cleanup and receive any execution or
cleanup error.
