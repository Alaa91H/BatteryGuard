use std::env;
use std::error::Error;
use std::io::ErrorKind;
use std::process;
use std::thread;
use std::time::Duration;

use batteryguard_core::{
    backend_for_current_platform, format_minutes, BatteryReading,
};

const VERSION: &str = match option_env!("CARGO_PKG_VERSION") {
    Some(version) => version,
    None => "0.0.0-dev",
};

fn main() {
    if let Err(error) = run() {
        eprintln!("batteryguard: {error}");
        process::exit(1);
    }
}

fn run() -> Result<(), Box<dyn Error>> {
    let args: Vec<String> = env::args().skip(1).collect();
    let mut json = false;
    let mut watch: Option<u64> = None;
    let mut index = 0;

    while index < args.len() {
        match args[index].as_str() {
            "--json" => json = true,
            "--help" | "-h" => {
                print_help();
                return Ok(());
            }
            "--version" | "-V" => {
                println!("BatteryGuard portable core {VERSION}");
                return Ok(());
            }
            "--watch" => {
                index += 1;
                let seconds = args
                    .get(index)
                    .ok_or_else(|| invalid("--watch needs a number of seconds"))?
                    .parse::<u64>()
                    .map_err(|_| invalid("--watch needs a positive number of seconds"))?;
                if seconds == 0 {
                    return Err(invalid("--watch needs a positive number of seconds"));
                }
                watch = Some(seconds);
            }
            other => {
                return Err(invalid(format!("unknown argument: {other}")));
            }
        }
        index += 1;
    }

    let backend = backend_for_current_platform();
    loop {
        let reading = backend.read()?;
        if json {
            println!("{}", render_json(&reading));
        } else {
            println!("{}", render_text(&reading));
        }

        match watch {
            Some(seconds) => thread::sleep(Duration::from_secs(seconds)),
            None => break,
        }
    }
    Ok(())
}

fn invalid(message: impl Into<String>) -> Box<dyn Error> {
    Box::new(std::io::Error::new(ErrorKind::InvalidInput, message.into()))
}

fn print_help() {
    println!("BatteryGuard portable battery core");
    println!();
    println!("Usage: batteryguard [--json] [--watch SECONDS]");
    println!();
    println!("  --json           Print one machine-readable JSON object.");
    println!("  --watch SECONDS  Repeat the reading every SECONDS seconds.");
    println!("  --version        Print the portable core version.");
    println!("  --help           Show this help.");
}

fn render_text(reading: &BatteryReading) -> String {
    let percent = reading
        .percent
        .map(|value| format!("{value}%"))
        .unwrap_or_else(|| "unknown".to_string());
    let electrical = reading.electrical_text();
    let mut lines = vec![
        "BatteryGuard portable core".to_string(),
        format!("platform: {} / {}", env::consts::OS, env::consts::ARCH),
        format!("source: {}", reading.source),
        format!("battery: {percent} · {}", reading.status_text()),
    ];

    if !electrical.is_empty() {
        lines.push(format!("electrical: {electrical}"));
    }
    if let Some(health) = reading.health_percent() {
        lines.push(format!("health: {health}%"));
    }
    if let Some(minutes) = reading.minutes_remaining() {
        lines.push(format!("remaining: {}", format_minutes(minutes)));
    }

    lines.join("\n")
}

fn render_json(reading: &BatteryReading) -> String {
    format!(
        concat!(
            "{{\"schema\":\"batteryguard.reading.v1\",",
            "\"source\":\"{}\",\"platform\":\"{}\",\"arch\":\"{}\",",
            "\"percent\":{},\"voltage_mv\":{},\"power_mw\":{},",
            "\"ac_online\":{},\"charging\":{},\"discharging\":{},",
            "\"electrical\":\"{}\",\"health_percent\":{},\"minutes_remaining\":{}}}"
        ),
        json_escape(&reading.source),
        json_escape(env::consts::OS),
        json_escape(env::consts::ARCH),
        option_u8(reading.percent),
        option_i32(reading.voltage_mv),
        option_i32(reading.power_mw()),
        option_bool(reading.ac_online),
        reading.charging,
        reading.discharging,
        json_escape(&reading.electrical_text()),
        option_i32(reading.health_percent()),
        option_i32(reading.minutes_remaining()),
    )
}

fn option_u8(value: Option<u8>) -> String {
    value
        .map(|value| value.to_string())
        .unwrap_or_else(|| "null".to_string())
}

fn option_i32(value: Option<i32>) -> String {
    value
        .map(|value| value.to_string())
        .unwrap_or_else(|| "null".to_string())
}

fn option_bool(value: Option<bool>) -> String {
    value
        .map(|value| value.to_string())
        .unwrap_or_else(|| "null".to_string())
}

fn json_escape(value: &str) -> String {
    let mut escaped = String::with_capacity(value.len());
    for character in value.chars() {
        match character {
            '\\' => escaped.push_str("\\\\"),
            '"' => escaped.push_str("\\\""),
            '\n' => escaped.push_str("\\n"),
            '\r' => escaped.push_str("\\r"),
            '\t' => escaped.push_str("\\t"),
            control if control.is_control() => {
                escaped.push_str(&format!("\\u{:04x}", control as u32))
            }
            other => escaped.push(other),
        }
    }
    escaped
}
