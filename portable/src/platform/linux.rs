//! Linux battery backend using the standard power-supply sysfs interface.
//!
//! This is deliberately read-only. Kernel/vendor charge-threshold files differ
//! by machine and firmware, so a later controller adapter must probe and
//! confirm those capabilities before writing anything.

use std::fs;
use std::path::{Path, PathBuf};

use crate::model::{BatteryError, BatteryReading};
use crate::platform::BatteryBackend;

const POWER_SUPPLY: &str = "/sys/class/power_supply";

pub struct LinuxBackend;

impl BatteryBackend for LinuxBackend {
    fn name(&self) -> &'static str {
        "linux-sysfs"
    }

    fn read(&self) -> Result<BatteryReading, BatteryError> {
        read_from(Path::new(POWER_SUPPLY))
    }
}

pub fn read_from(root: &Path) -> Result<BatteryReading, BatteryError> {
    let battery = find_battery(root)?;
    let status = read_text(&battery.join("status")).unwrap_or_default();
    let status_lower = status.to_ascii_lowercase();
    let charging = status_lower == "charging";
    let discharging = status_lower == "discharging";

    let voltage_mv = read_i64(&battery.join("voltage_now"))
        .map(|value| (value / 1000) as i32)
        .filter(|value| *value > 0);
    let power_now_mw = read_i64(&battery.join("power_now"))
        .map(|value| (value.abs() / 1000) as i32);
    let current_ua = read_i64(&battery.join("current_now")).map(i64::abs);
    let calculated_power_mw = match (voltage_mv, current_ua) {
        (Some(voltage), Some(current)) => {
            Some(((voltage as i64 * current) / 1_000_000) as i32)
        }
        _ => None,
    };
    let power_mw = power_now_mw.or(calculated_power_mw);

    let mut reading = BatteryReading {
        percent: read_i64(&battery.join("capacity"))
            .map(|value| value.clamp(0, 100) as u8),
        voltage_mv,
        charge_rate_mw: if charging { power_mw } else { None },
        discharge_rate_mw: if discharging { power_mw } else { None },
        ac_online: read_ac_online(root),
        charging,
        discharging,
        energy_now_mwh: read_i64(&battery.join("energy_now")).map(|value| (value / 1000) as i32),
        energy_full_mwh: read_i64(&battery.join("energy_full")).map(|value| (value / 1000) as i32),
        energy_full_design_mwh: read_i64(&battery.join("energy_full_design"))
            .map(|value| (value / 1000) as i32),
        cycle_count: read_i64(&battery.join("cycle_count")).and_then(|value| {
            if value >= 0 {
                Some(value as u32)
            } else {
                None
            }
        }),
        temperature_c: read_i64(&battery.join("temp")).map(|value| value as f32 / 10.0),
        source: "linux-sysfs".to_string(),
    };

    // A full/idle pack has a real zero rate. Keep it visible when voltage is
    // available, matching the Windows readout.
    if !charging && !discharging && power_mw.is_some() {
        reading.charge_rate_mw = power_mw;
        reading.discharge_rate_mw = power_mw;
    }

    if reading.percent.is_none() && reading.voltage_mv.is_none() {
        return Err(BatteryError::new("the Linux battery has no capacity or voltage reading"));
    }
    Ok(reading)
}

fn find_battery(root: &Path) -> Result<PathBuf, BatteryError> {
    let entries = fs::read_dir(root).map_err(|error| {
        BatteryError::new(format!("cannot read {}: {error}", root.display()))
    })?;
    let mut candidates = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        let kind = read_text(&path.join("type")).unwrap_or_default();
        let name = entry.file_name().to_string_lossy().to_string();
        if kind.eq_ignore_ascii_case("battery") || name.starts_with("BAT") {
            candidates.push(path);
        }
    }
    candidates.sort();
    candidates.into_iter().next().ok_or_else(|| {
        BatteryError::new(format!("no battery found under {}", root.display()))
    })
}

fn read_ac_online(root: &Path) -> Option<bool> {
    let entries = fs::read_dir(root).ok()?;
    let mut saw_supply = false;
    let mut online = false;
    for entry in entries.flatten() {
        let path = entry.path();
        let kind = read_text(&path.join("type")).unwrap_or_default();
        if kind.eq_ignore_ascii_case("mains") || kind.eq_ignore_ascii_case("ac") {
            saw_supply = true;
            if read_i64(&path.join("online")) == Some(1) {
                online = true;
            }
        }
    }
    if saw_supply {
        Some(online)
    } else {
        None
    }
}

fn read_i64(path: &Path) -> Option<i64> {
    fs::read_to_string(path)
        .ok()
        .and_then(|value| value.trim().parse::<i64>().ok())
}

fn read_text(path: &Path) -> Option<String> {
    fs::read_to_string(path)
        .ok()
        .map(|value| value.trim().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn fixture_root() -> PathBuf {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_nanos())
            .unwrap_or(0);
        std::env::temp_dir().join(format!("batteryguard-sysfs-{}-{stamp}", std::process::id()))
    }

    #[test]
    fn reads_sysfs_fixture() {
        let root = fixture_root();
        let battery = root.join("BAT0");
        let ac = root.join("AC");
        fs::create_dir_all(&battery).unwrap();
        fs::create_dir_all(&ac).unwrap();
        fs::write(battery.join("type"), "Battery\n").unwrap();
        fs::write(battery.join("capacity"), "61\n").unwrap();
        fs::write(battery.join("status"), "Charging\n").unwrap();
        fs::write(battery.join("voltage_now"), "11781000\n").unwrap();
        fs::write(battery.join("power_now"), "0\n").unwrap();
        fs::write(battery.join("energy_now"), "24810000\n").unwrap();
        fs::write(battery.join("energy_full"), "40940000\n").unwrap();
        fs::write(battery.join("energy_full_design"), "51000000\n").unwrap();
        fs::write(battery.join("cycle_count"), "42\n").unwrap();
        fs::write(battery.join("temp"), "300\n").unwrap();
        fs::write(ac.join("type"), "Mains\n").unwrap();
        fs::write(ac.join("online"), "1\n").unwrap();

        let reading = read_from(&root).expect("fixture should parse");
        assert_eq!(reading.percent, Some(61));
        assert_eq!(reading.voltage_mv, Some(11781));
        assert_eq!(reading.energy_now_mwh, Some(24810));
        assert_eq!(reading.energy_full_mwh, Some(40940));
        assert_eq!(reading.energy_full_design_mwh, Some(51000));
        assert_eq!(reading.cycle_count, Some(42));
        assert_eq!(reading.ac_online, Some(true));
        assert!(reading.charging);
        assert_eq!(reading.electrical_text(), "11.8 V · 0.0 W");

        fs::remove_dir_all(&root).unwrap();
    }
}
