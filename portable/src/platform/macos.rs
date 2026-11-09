//! macOS read-only battery backend.
//!
//! `pmset` provides percentage, power source and the coarse charging state
//! without private APIs. Voltage and wattage are not exposed by this backend
//! yet; a later IOKit adapter can add AppleSmartBattery details. Charge control
//! is intentionally absent because it needs SMC/private firmware interfaces.

use std::process::Command;

use crate::model::{BatteryError, BatteryReading};
use crate::platform::BatteryBackend;

pub struct MacOsBackend;

impl BatteryBackend for MacOsBackend {
    fn name(&self) -> &'static str {
        "macos-pmset"
    }

    fn read(&self) -> Result<BatteryReading, BatteryError> {
        let output = Command::new("pmset")
            .args(["-g", "batt"])
            .output()
            .map_err(|error| BatteryError::new(format!("cannot run pmset: {error}")))?;
        if !output.status.success() {
            return Err(BatteryError::new("pmset -g batt failed"));
        }
        parse(&String::from_utf8_lossy(&output.stdout))
    }
}

pub fn parse(text: &str) -> Result<BatteryReading, BatteryError> {
    let ac_online = if text.contains("AC Power") {
        Some(true)
    } else if text.contains("Battery Power") {
        Some(false)
    } else {
        None
    };

    let line = text
        .lines()
        .find(|line| line.contains('%'))
        .ok_or_else(|| BatteryError::new("pmset returned no battery percentage"))?;

    let before_percent = line
        .split('%')
        .next()
        .ok_or_else(|| BatteryError::new("pmset battery line is malformed"))?;
    let percent = before_percent
        .split_whitespace()
        .last()
        .and_then(|value| value.parse::<i32>().ok())
        .map(|value| value.clamp(0, 100) as u8)
        .ok_or_else(|| BatteryError::new("pmset battery percentage is malformed"))?;

    let state = line
        .split(';')
        .nth(1)
        .unwrap_or("")
        .trim()
        .to_ascii_lowercase();
    let discharging = state.contains("discharging");
    let charging = state.contains("charging") && !discharging;

    Ok(BatteryReading {
        percent: Some(percent),
        ac_online,
        charging,
        discharging,
        source: "macos-pmset".to_string(),
        ..BatteryReading::default()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_ac_charging_line() {
        let text = "Now drawing from 'AC Power'\n -InternalBattery-0 (id=123)\t61%; charging; 1:20 remaining present: true\n";
        let reading = parse(text).expect("fixture should parse");
        assert_eq!(reading.percent, Some(61));
        assert_eq!(reading.ac_online, Some(true));
        assert!(reading.charging);
        assert!(!reading.discharging);
    }

    #[test]
    fn parses_battery_discharging_line() {
        let text = "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=123)\t61%; discharging; 4:32 remaining present: true\n";
        let reading = parse(text).expect("fixture should parse");
        assert_eq!(reading.ac_online, Some(false));
        assert!(reading.discharging);
    }

    #[test]
    fn rejects_output_without_percentage() {
        assert!(parse("Now drawing from 'AC Power'\n").is_err());
    }
}
