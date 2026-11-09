//! Display formatting shared by the platform backends and the CLI.

/// Formats millivolts and milliwatts as `11.8 V · 6.5 W`.
///
/// Zero power is shown when voltage confirms that a battery reading exists;
/// this is useful while a charger holds the pack idle. With no voltage and no
/// power the result is empty, so callers can omit the field.
pub fn format_electrical(voltage_mv: i32, power_mw: i32) -> String {
    let mut parts: Vec<String> = Vec::new();
    if voltage_mv > 0 {
        parts.push(format!("{:.1} V", voltage_mv as f64 / 1000.0));
    }
    if power_mw > 0 || voltage_mv > 0 {
        parts.push(format!("{:.1} W", power_mw as f64 / 1000.0));
    }
    parts.join(" · ")
}

/// Formats minutes as `45 min`, `2 h` or `2 h 5 min`.
pub fn format_minutes(minutes: i32) -> String {
    let minutes = minutes.max(0);
    if minutes < 60 {
        return format!("{minutes} min");
    }
    let hours = minutes / 60;
    let rest = minutes % 60;
    if rest == 0 {
        format!("{hours} h")
    } else {
        format!("{hours} h {rest} min")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formats_voltage_and_power() {
        assert_eq!(format_electrical(11781, 6500), "11.8 V · 6.5 W");
        assert_eq!(format_electrical(11781, 0), "11.8 V · 0.0 W");
        assert_eq!(format_electrical(0, 0), "");
        assert_eq!(format_electrical(0, 6500), "6.5 W");
    }

    #[test]
    fn formats_duration() {
        assert_eq!(format_minutes(45), "45 min");
        assert_eq!(format_minutes(120), "2 h");
        assert_eq!(format_minutes(125), "2 h 5 min");
        assert_eq!(format_minutes(-5), "0 min");
    }
}
