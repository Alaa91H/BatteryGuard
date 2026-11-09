//! Platform-neutral battery data.
//!
//! Values use the units exposed by the operating systems: millivolts,
//! milliwatts, milliwatt-hours and degrees Celsius. Missing measurements are
//! represented by `None`; zero is a real value (for example, a pack held idle
//! by the charger).

use std::fmt;

use crate::format::format_electrical;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ChargeMode {
    Auto,
    Inhibit,
    ForceDischarge,
    Unsupported,
}

impl ChargeMode {
    pub fn as_str(self) -> &'static str {
        match self {
            ChargeMode::Auto => "auto",
            ChargeMode::Inhibit => "inhibit",
            ChargeMode::ForceDischarge => "force-discharge",
            ChargeMode::Unsupported => "unsupported",
        }
    }
}

#[derive(Clone, Debug, Default)]
pub struct BatteryReading {
    pub percent: Option<u8>,
    pub voltage_mv: Option<i32>,
    pub charge_rate_mw: Option<i32>,
    pub discharge_rate_mw: Option<i32>,
    pub ac_online: Option<bool>,
    pub charging: bool,
    pub discharging: bool,
    pub energy_now_mwh: Option<i32>,
    pub energy_full_mwh: Option<i32>,
    pub energy_full_design_mwh: Option<i32>,
    pub cycle_count: Option<u32>,
    pub temperature_c: Option<f32>,
    pub source: String,
}

impl BatteryReading {
    /// The current transfer rate, preferring the active direction and then the
    /// larger of the two reported rates.
    pub fn power_mw(&self) -> Option<i32> {
        if self.charging {
            if let Some(rate) = self.charge_rate_mw {
                if rate > 0 {
                    return Some(rate);
                }
            }
        }
        if self.discharging {
            if let Some(rate) = self.discharge_rate_mw {
                if rate > 0 {
                    return Some(rate);
                }
            }
        }

        match (self.charge_rate_mw, self.discharge_rate_mw) {
            (Some(charge), Some(discharge)) => Some(charge.max(discharge)),
            (Some(charge), None) => Some(charge),
            (None, Some(discharge)) => Some(discharge),
            (None, None) => None,
        }
    }

    pub fn electrical_text(&self) -> String {
        format_electrical(
            self.voltage_mv.unwrap_or(0),
            self.power_mw().unwrap_or(0),
        )
    }

    pub fn status_text(&self) -> &'static str {
        if self.charging {
            "Charging"
        } else if self.discharging {
            "Discharging"
        } else {
            match self.ac_online {
                Some(true) => "Plugged in",
                Some(false) => "On battery",
                None => "Unknown",
            }
        }
    }

    pub fn health_percent(&self) -> Option<i32> {
        match (self.energy_full_mwh, self.energy_full_design_mwh) {
            (Some(full), Some(designed)) if full > 0 && designed > 0 => {
                Some(((full as f64 * 100.0 / designed as f64).round()) as i32)
            }
            _ => None,
        }
    }

    pub fn minutes_remaining(&self) -> Option<i32> {
        if self.charging {
            if let (Some(rate), Some(full), Some(now)) = (
                self.charge_rate_mw,
                self.energy_full_mwh,
                self.energy_now_mwh,
            ) {
                if rate > 0 && full > now {
                    return Some(((full - now) as f64 * 60.0 / rate as f64).round() as i32);
                }
            }
        }
        if self.discharging {
            if let (Some(rate), Some(now)) = (self.discharge_rate_mw, self.energy_now_mwh) {
                if rate > 0 && now > 0 {
                    return Some((now as f64 * 60.0 / rate as f64).round() as i32);
                }
            }
        }
        None
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BatteryError {
    message: String,
}

impl BatteryError {
    pub fn new(message: impl Into<String>) -> Self {
        BatteryError {
            message: message.into(),
        }
    }
}

impl fmt::Display for BatteryError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl std::error::Error for BatteryError {}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> BatteryReading {
        BatteryReading {
            percent: Some(61),
            voltage_mv: Some(11781),
            charge_rate_mw: Some(0),
            discharge_rate_mw: Some(0),
            ac_online: Some(true),
            charging: false,
            discharging: false,
            energy_now_mwh: Some(24810),
            energy_full_mwh: Some(40940),
            energy_full_design_mwh: Some(51000),
            cycle_count: Some(42),
            temperature_c: Some(30.0),
            source: "test".to_string(),
        }
    }

    #[test]
    fn electrical_uses_voltage_and_zero_power() {
        assert_eq!(sample().electrical_text(), "11.8 V · 0.0 W");
    }

    #[test]
    fn health_and_status_are_derived() {
        let reading = sample();
        assert_eq!(reading.health_percent(), Some(80));
        assert_eq!(reading.status_text(), "Plugged in");
    }

    #[test]
    fn active_charge_rate_wins() {
        let mut reading = sample();
        reading.charging = true;
        reading.charge_rate_mw = Some(6500);
        reading.discharge_rate_mw = Some(9000);
        assert_eq!(reading.power_mw(), Some(6500));
    }

    #[test]
    fn unavailable_measurements_stay_unavailable() {
        let reading = BatteryReading::default();
        assert_eq!(reading.power_mw(), None);
        assert_eq!(reading.electrical_text(), "");
        assert_eq!(reading.health_percent(), None);
    }
}
