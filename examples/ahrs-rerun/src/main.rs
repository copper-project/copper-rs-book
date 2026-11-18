//! Render Copper's AHRS payload with its existing Rerun representation.

use cu_ahrs::AhrsPose;
use cu_rerun::rerun;
use cu29::units::si::angle::degree;
use cu29::units::si::f32::Angle;
use rerun::blueprint::{Blueprint, BlueprintActivation, Spatial3DView};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let recording = rerun::RecordingStreamBuilder::new("Copper AHRS").save("ahrs.rrd")?;
    recording.log_static("world", &rerun::ViewCoordinates::FRD())?;
    Blueprint::new(Spatial3DView::new("AHRS body axes").with_origin("world"))
        .send(&recording, BlueprintActivation::default())?;

    for sample in 0..=120 {
        recording.set_time_sequence("sample", sample);
        let pose = AhrsPose {
            roll: Angle::new::<degree>(15.0),
            pitch: Angle::new::<degree>(20.0),
            yaw: Angle::new::<degree>(sample as f32 * 0.75),
        };
        recording.log("world/ahrs", &pose)?;
    }
    recording.flush_blocking()?;
    Ok(())
}
