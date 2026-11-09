//! Windows battery backend.
//!
//! The read-only provider uses the built-in PowerShell/.NET WMI client. This
//! keeps the portable core dependency-free and works on x86, x64 and ARM64
//! Windows installations where PowerShell is available. The existing native
//! C# tray remains responsible for HP charge control.

use std::process::Command;

use crate::model::{BatteryError, BatteryReading};
use crate::platform::BatteryBackend;

const SCRIPT: &str = r#"
$ErrorActionPreference = 'Stop'
Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus -ErrorAction Stop |
    ForEach-Object {
        'status|{0}|{1}|{2}|{3}|{4}|{5}' -f $_.Voltage, $_.ChargeRate, $_.DischargeRate, $_.PowerOnline, $_.Charging, $_.Discharging
    }
Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue |
    Select-Object -First 1 |
    ForEach-Object { 'battery|{0}' -f $_.EstimatedChargeRemaining }
Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue |
    Select-Object -First 1 |
    ForEach-Object { 'full|{0}' -f $_.FullChargedCapacity }
Get-CimInstance -Namespace root/wmi -ClassName BatteryCycleCount -ErrorAction SilentlyContinue |
    Select-Object -First 1 |
    ForEach-Object { 'cycles|{0}' -f $_.CycleCount }
"#;

pub struct WindowsBackend;

impl BatteryBackend for WindowsBackend {
    fn name(&self) -> &'static str {
        "windows-wmi"
    }

    fn read(&self) -> Result<BatteryReading, BatteryError> {
        let output = Command::new("powershell.exe")
            .args([
                "-NoProfile",
                "-NonInteractive",
                "-Command",
                SCRIPT,
            ])
            .output()
            .map_err(|error| BatteryError::new(format!("cannot start PowerShell: {error}")))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(BatteryError::new(format!(
                "PowerShell battery query failed: {}",
                stderr.trim()
            )));
        }

        parse(&String::from_utf8_lossy(&output.stdout))
    }
}

pub fn parse(text: &str) -> Result<BatteryReading, BatteryError> {
    let mut reading = BatteryReading {
        source: "windows-wmi".to_string(),
        ..BatteryReading::default()
    };
    let mut saw_status = false;

    for raw in text.lines() {
        let fields: Vec<&str> = raw.trim().split('|').collect();
        if fields.len() < 2 {
            continue;
        }
        match fields[0] {
            "status" if fields.len() >= 7 => {
                saw_status = true;
                reading.voltage_mv = parse_i32(fields[1]);
                reading.charge_rate_mw = parse_i32(fields[2]);
                reading.discharge_rate_mw = parse_i32(fields[3]);
                reading.ac_online = parse_bool(fields[4]);
                reading.charging = parse_bool(fields[5]).unwrap_or(false);
                reading.discharging = parse_bool(fields[6]).unwrap_or(false);
            }
            "battery" => {
                if let Some(value) = parse_i32(fields[1]) {
                    reading.percent = Some(value.clamp(0, 100) as u8);
                }
            }
            "full" => {
                reading.energy_full_mwh = parse_i32(fields[1]);
            }
            "cycles" => {
                reading.cycle_count = parse_u32(fields[1]);
            }
            _ => {}
        }
    }

    if !saw_status {
        return Err(BatteryError::new("Windows returned no BatteryStatus instance"));
    }
    Ok(reading)
}

fn parse_i32(value: &str) -> Option<i32> {
    value.trim().parse::<i32>().ok()
}

fn parse_u32(value: &str) -> Option<u32> {
    value.trim().parse::<u32>().ok()
}

fn parse_bool(value: &str) -> Option<bool> {
    let value = value.trim();
    if value.eq_ignore_ascii_case("true") || value == "1" {
        Some(true)
    } else if value.eq_ignore_ascii_case("false") || value == "0" {
        Some(false)
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_wmi_output() {
        let text = "status|11781|0|0|True|False|False\nbattery|61\nfull|40940\ncycles|42\n";
        let reading = parse(text).expect("fixture should parse");
        assert_eq!(reading.percent, Some(61));
        assert_eq!(reading.voltage_mv, Some(11781));
        assert_eq!(reading.charge_rate_mw, Some(0));
        assert_eq!(reading.ac_online, Some(true));
        assert!(!reading.charging);
        assert_eq!(reading.energy_full_mwh, Some(40940));
        assert_eq!(reading.cycle_count, Some(42));
        assert_eq!(reading.electrical_text(), "11.8 V · 0.0 W");
    }

    #[test]
    fn rejects_missing_status() {
        assert!(parse("battery|61\n").is_err());
    }
}
