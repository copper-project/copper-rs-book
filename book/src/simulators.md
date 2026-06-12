# Interfacing a Simulator

The usual simulator integration is an event callback loop:

```text
simulator tick
    -> fill Copper's simulated inputs for this tick
    -> let Copper run the tasks that should run
    -> read Copper's outputs
    -> apply those outputs to the simulator
    -> advance the simulator
```

That is the mental model to start with. Copper does not currently ship a ready-made
integration for every simulator. The Bevy examples are the concrete examples in this
repository, and users have also integrated Copper successfully with simulators such as
Isaac Sim, CARLA, and MuJoCo. In all of those cases, the job is to write a thin adapter at
the simulator boundary.

If the simulator runs in another process, that adapter can use whatever RPC or message
transport fits your setup: sockets, shared memory, middleware topics, or the simulator's
own API. The important part is still the same: each simulator step produces observations
for Copper, Copper runs the graph, and commands are sent back to the simulator at a known
point in the simulation step.

## The callback shape

In simulation mode, Copper generates a `SimStep` enum from your `copperconfig.ron`. Each
variant corresponds to one task step in the graph.

Your simulator callback receives those steps while Copper is running an iteration. For
each step it returns one of two common answers:

| Return value | Meaning |
|---|---|
| `SimOverride::ExecuteByRuntime` | Copper should run that task normally. Use this for estimation, control, planning, and other algorithm tasks. |
| `SimOverride::ExecutedBySim` | The simulator handled that step. Use this for simulated sensors and actuators. |

The common pattern is:

1. Build the Copper runtime in `sim_mode = true`.
2. Register a simulation callback.
3. On each simulator tick, update Copper's clock to the simulator time.
4. When Copper reaches a simulated hardware task, fill its output from simulator state.
5. When Copper reaches a simulated actuator task, read the command and store it for the
   simulator.
6. Let all ordinary algorithm tasks run normally.

For example, a balancing robot simulator might do this:

```text
Bevy physics tick
    -> set Copper time to the current physics time
    -> encoder task output is filled from wheel position in the sim
    -> angle sensor task output is filled from body orientation in the sim
    -> controller tasks run normally
    -> motor task output is captured
    -> motor force is applied to the simulated body
```

The controller does not know this is a simulation. It sees the same kind of messages it
would see on the real robot.

## What to implement first

For any simulator that can call into Copper directly, start with a small adapter layer
owned by the simulator:

```rust
struct MySimCopperAdapter {
    copper: MyRobotSim,
    clock: RobotClock,
    clock_mock: RobotClockMock,
    last_motor_command: MotorCommand,
}
```

Then wire it into your simulator's tick/update function:

```rust
fn simulator_tick(adapter: &mut MySimCopperAdapter, sim: &mut MySimulator) -> CuResult<()> {
    adapter.clock_mock.set_value(sim.time_nanos());

    let mut callback = |step| {
        match step {
            my_robot::SimStep::Imu(CuTaskCallbackState::Process(_, output)) => {
                output.set_payload(sim.read_imu());
                SimOverride::ExecutedBySim
            }

            my_robot::SimStep::Motor(CuTaskCallbackState::Process(input, _output)) => {
                if let Some(command) = input.payload() {
                    adapter.last_motor_command = *command;
                }
                SimOverride::ExecutedBySim
            }

            _ => SimOverride::ExecuteByRuntime,
        }
    };

    adapter.copper.run_one_iteration(&mut callback)?;
    sim.apply_motor_command(adapter.last_motor_command);
    sim.step();
    Ok(())
}
```

Treat this as pseudocode: the generated runtime type and step names come from your
`copperconfig.ron`, and your payload types will be your own. The important point is where
the simulator code lives. It lives in the simulation adapter, not inside the controller
tasks.

In practice, simulated sensors write to `output`, simulated actuators read from `input`,
and the estimation/control/planning tasks return `ExecuteByRuntime`.

## Types to look for

When adapting a simulator, these are the Copper pieces to grep for in existing examples:

| Item | Why it matters |
|---|---|
| `#[copper_runtime(..., sim_mode = true)]` | Generates the simulation-aware runtime and `SimStep` enum for your graph. |
| `SimStep` | The generated enum you match in the simulation callback. The variants come from task ids in `copperconfig.ron`. |
| `CuTaskCallbackState::Process(input, output)` | Gives the callback access to a task's input and output messages for that step. |
| `SimOverride::ExecutedBySim` | Return this when the simulator filled the output or consumed the actuator command. |
| `SimOverride::ExecuteByRuntime` | Return this when Copper should run the task normally. |
| `RobotClock::mock()` and `RobotClockMock::set_value(...)` | Let the simulator drive Copper time from simulation time. |
| `run_one_iteration(&mut callback)` | Runs one Copper iteration while giving your callback a chance to handle simulated steps. |

The most useful files to read are:

```bash
rg "sim_mode|SimStep|SimOverride|CuTaskCallbackState|run_one_iteration|RobotClock::mock" ../extra-examples/examples/cu_rp_balancebot/src
rg "sim_mode|SimStep|SimOverride|CuTaskCallbackState|run_one_iteration|RobotClock::mock" ../extra-examples/examples/cu_flight_controller/src
```

The first line in the tick function is not incidental:

```rust
adapter.clock_mock.set_value(sim.time_nanos());
```

For simulation, Copper should usually see simulation time, not wall-clock time. If the
simulator pauses, Copper time pauses. If the simulator runs faster than real time, the
timestamps still describe the simulated run. Decide here whether one simulator tick equals
one Copper tick, whether Copper runs on every physics substep, and whether commands apply
immediately or on the next simulator step.

## Pick an ownership pattern

Choose the shape that matches who owns the main loop.

### The simulator owns the loop

This is the most common shape for an interactive simulator.

Your simulator has the main loop. Each simulator tick calls Copper, Copper runs the graph,
and the simulator applies the resulting commands.

Use this when:

- the simulator has a physics or rendering loop
- the simulator already controls pause, reset, and stepping
- you want interactive visualization
- you want one Copper tick per simulator tick, or one Copper tick every N simulator ticks

The Bevy examples in `../extra-examples` use this style:

| Example | What it demonstrates |
|---|---|
| `examples/cu_rp_balancebot` | Bevy owns the physics tick. The simulation callback fills encoder/ADC-style task outputs from the world and applies motor output back into the world. |
| `examples/cu_flight_controller` | Bevy owns the flight simulation. Copper runs the flight-control graph while simulated hardware endpoints provide IMU, barometer, magnetometer, GNSS, RC, battery, and motor behavior. |

These examples are useful even if you are not using Bevy. Look for the simulator callback
layer: that is the part to copy conceptually.

In `cu_rp_balancebot`, the callback does exactly this:

- `Balpos` is a simulated angle sensor, so the callback writes an ADC payload from the
  simulated body orientation.
- `Railpos` is a simulated encoder, so the callback writes encoder ticks from the
  simulated cart position.
- `Motor` is a simulated actuator, so the callback reads the motor command and applies a
  force in the physics world.
- all other steps return `ExecuteByRuntime`.

### Copper owns the loop

Use this when the simulator is a small model or library that Copper can step directly.

In this shape, the Copper app drives the timing. Simulated sensor tasks read from the
model, normal tasks run, and simulated actuator tasks write back to the model. This is a
good fit for headless tests and deterministic algorithm checks.

Use this when:

- the simulator has no strict main loop of its own
- rendering is not important
- you want batch tests or faster-than-real-time runs
- the simulator can be stepped from Rust without blocking
