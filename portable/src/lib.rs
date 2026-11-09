//! BatteryGuard portable core.
//!
//! The core is deliberately free of user-interface and installer concerns. It
//! owns the battery model, display formatting and the pure charge policy; each
//! operating system supplies a backend. Charge control is opt-in and remains
//! limited by the hardware interfaces that are actually available.

pub mod format;
pub mod model;
pub mod platform;
pub mod policy;

pub use format::{format_electrical, format_minutes};
pub use model::{BatteryError, BatteryReading, ChargeMode};
pub use platform::{backend_for_current_platform, BatteryBackend};
pub use policy::{evaluate, ChargeAction, ChargeDecision};
