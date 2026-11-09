//! Pure charge/float policy.
//!
//! This is intentionally independent of any operating system or firmware. A
//! platform controller can turn the returned action into a real write only
//! after it has confirmed that the hardware exposes a supported interface.

use crate::model::ChargeMode;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ChargeAction {
    None,
    Auto,
    Inhibit,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ChargeDecision {
    pub action: ChargeAction,
    pub float_active: bool,
}

pub fn evaluate(
    standard_charging: bool,
    on_ac: bool,
    percent: i32,
    ceiling: Option<i32>,
    resume: Option<i32>,
    float_mode: bool,
    float_active: bool,
    mode: ChargeMode,
) -> ChargeDecision {
    let mut result = ChargeDecision {
        action: ChargeAction::None,
        float_active,
    };

    if standard_charging || ceiling.is_none() {
        result.float_active = false;
        if mode == ChargeMode::Inhibit {
            result.action = ChargeAction::Auto;
        }
        return result;
    }

    if !on_ac {
        result.float_active = false;
        if mode == ChargeMode::Inhibit {
            result.action = ChargeAction::Auto;
        }
        return result;
    }

    let limit = ceiling.unwrap_or_default();
    let resume_at = resume.unwrap_or_else(|| (limit - 5).max(1));

    if percent >= limit {
        result.float_active = float_mode;
        if mode == ChargeMode::Auto {
            result.action = ChargeAction::Inhibit;
        }
        return result;
    }

    if mode == ChargeMode::Inhibit {
        if float_active {
            // Once float is active, stay on charger power until the explicit
            // resume point; a small drop must not cycle the battery.
            if percent <= resume_at {
                result.float_active = false;
                result.action = ChargeAction::Auto;
            }
            return result;
        }

        // Inhibit below the target is not float. Release it so charging can
        // reach the configured limit before float starts.
        if float_mode {
            result.float_active = false;
            result.action = ChargeAction::Auto;
        }
        return result;
    }

    result.float_active = false;
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn check(
        name: &str,
        standard: bool,
        on_ac: bool,
        percent: i32,
        ceiling: Option<i32>,
        resume: Option<i32>,
        float_mode: bool,
        float_active: bool,
        mode: ChargeMode,
        expected_action: ChargeAction,
        expected_float: bool,
    ) {
        let decision = evaluate(
            standard,
            on_ac,
            percent,
            ceiling,
            resume,
            float_mode,
            float_active,
            mode,
        );
        assert_eq!(
            decision.action, expected_action,
            "{name}: action {:?}",
            decision.action
        );
        assert_eq!(
            decision.float_active, expected_float,
            "{name}: float {}",
            decision.float_active
        );
    }

    #[test]
    fn matches_the_thirteen_charge_and_float_cases() {
        check("below limit, auto", false, true, 70, Some(80), Some(75), true, false, ChargeMode::Auto, ChargeAction::None, false);
        check("one point below limit", false, true, 79, Some(80), Some(75), true, false, ChargeMode::Auto, ChargeAction::None, false);
        check("at limit, auto", false, true, 80, Some(80), Some(75), true, false, ChargeMode::Auto, ChargeAction::Inhibit, true);
        check("above limit, auto", false, true, 85, Some(80), Some(75), true, false, ChargeMode::Auto, ChargeAction::Inhibit, true);
        check("at limit, float off", false, true, 80, Some(80), Some(75), false, false, ChargeMode::Auto, ChargeAction::Inhibit, false);
        check("float holds above resume", false, true, 78, Some(80), Some(75), true, true, ChargeMode::Inhibit, ChargeAction::None, true);
        check("float holds at limit", false, true, 80, Some(80), Some(75), true, true, ChargeMode::Inhibit, ChargeAction::None, true);
        check("resume point reached", false, true, 75, Some(80), Some(75), true, true, ChargeMode::Inhibit, ChargeAction::Auto, false);
        check("below resume", false, true, 70, Some(80), Some(75), true, true, ChargeMode::Inhibit, ChargeAction::Auto, false);
        check("stale inhibit below limit", false, true, 70, Some(80), Some(75), true, false, ChargeMode::Inhibit, ChargeAction::Auto, false);
        check("on battery at limit", false, false, 80, Some(80), Some(75), true, false, ChargeMode::Inhibit, ChargeAction::Auto, false);
        check("standard charging window", true, true, 80, Some(80), Some(75), true, false, ChargeMode::Inhibit, ChargeAction::Auto, false);
        check("no ceiling configured", false, true, 80, None, None, true, false, ChargeMode::Auto, ChargeAction::None, false);
    }
}
