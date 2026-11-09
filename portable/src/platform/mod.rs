//! Operating-system battery backends.
//!
//! Every backend is read-only for now. A future charge controller belongs
//! behind a separate capability check so a monitoring backend can never write
//! an unsupported firmware register.

use crate::model::BatteryError;
use crate::model::BatteryReading;

#[cfg(target_os = "linux")]
pub mod linux;
#[cfg(target_os = "macos")]
pub mod macos;
#[cfg(target_os = "windows")]
pub mod windows;

pub trait BatteryBackend {
    fn name(&self) -> &'static str;
    fn read(&self) -> Result<BatteryReading, BatteryError>;
    fn can_control_charge(&self) -> bool {
        false
    }
}

pub struct UnsupportedBackend {
    platform: String,
}

impl UnsupportedBackend {
    pub fn new(platform: impl Into<String>) -> Self {
        UnsupportedBackend {
            platform: platform.into(),
        }
    }
}

impl BatteryBackend for UnsupportedBackend {
    fn name(&self) -> &'static str {
        "unsupported"
    }

    fn read(&self) -> Result<BatteryReading, BatteryError> {
        Err(BatteryError::new(format!(
            "no battery backend is implemented for {} / {}",
            self.platform,
            std::env::consts::ARCH
        )))
    }
}

pub fn backend_for_current_platform() -> Box<dyn BatteryBackend> {
    #[cfg(target_os = "linux")]
    {
        return Box::new(linux::LinuxBackend);
    }
    #[cfg(target_os = "windows")]
    {
        return Box::new(windows::WindowsBackend);
    }
    #[cfg(target_os = "macos")]
    {
        return Box::new(macos::MacOsBackend);
    }

    #[allow(unreachable_code)]
    Box::new(UnsupportedBackend::new(std::env::consts::OS))
}
