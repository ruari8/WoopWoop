# WoopWoop Metric Cheat Sheet

Last updated: 2026-06-13

This app is not reading every displayed value from a WHOOP API. Most health values are either live BLE values, decoded local packet evidence, local estimates derived from that evidence, or currently unavailable placeholders. The `HealthDataSource` badge in the UI should match one of these states: `Live`, `Bridge`, `Local`, or `Unavailable`.

## External References

- WHOOP Steps support: https://support.whoop.com/s/article/Steps
- WHOOP Recovery support: https://support.whoop.com/s/article/WHOOP-Recovery
- WHOOP Strain support: https://support.whoop.com/s/article/WHOOP-Strain
- WHOOP Health Monitor support: https://support.whoop.com/s/article/WHOOP-Health-Monitor-Report
- WHOOP max HR / zone settings: https://support.whoop.com/s/article/What-is-Max-Heart-Rate-and-How-Do-I-Adjust-It

## Data Path Summary

| Metric | Primary input | Decode/storage path | Calculation | Why it may be blank |
| --- | --- | --- | --- | --- |
| Live heart rate | Standard BLE heart-rate stream | `GooseBLEClient+VitalsAndLogging.swift` publishes `liveVitals.liveHeartRateBPM`; `HeartRateSeriesStore` persists samples | Latest valid BLE BPM sample | Band not connected, HR broadcast unavailable, or no recent sample |
| Heart-rate trend | BLE HR samples | `HeartRateSeriesStore.samples` and hourly buckets | Average BPM per 5 min, 30 min, or 1 hour bucket depending on selected range | Needs locally stored BLE HR samples |
| Resting HR | Packet-derived daily recovery metric, resting HR rollup, or local HR low-quartile fallback | `HealthDataStore+Vitals.swift` | Preferred stored `resting_hr_bpm`; fallback is low quartile of local HR samples | Not enough HR samples, resting HR packet feature not run, or field unresolved |
| HRV | Packet-derived RR intervals | `metrics.hrv_features` -> `HealthDataStore+Vitals.swift` | RMSSD from valid RR intervals between 300 and 2000 ms | Beat interval semantics not trusted or too few valid intervals |
| Steps | WHOOP step counter candidates, then local rollup | `metrics.step_packet_discovery` -> `metrics.step_counter_ingest` -> `metrics.step_counter_daily_rollup` / `hourly_rollup` | Counter delta from decoded step counter samples; source is `device_counter` when trusted | No step-counter packet candidates, too few samples, counter reset/conflict, or rollup not run |
| Active/total calories | Local HR + motion estimate | `metrics.energy_daily_rollup` / `energy_hourly_rollup` | Local calorie estimate from HR samples, motion samples, profile weight, resting HR, and coverage | Needs HR and motion coverage; not a direct WHOOP calorie field |
| Sleep | Packet-derived sleep window/stage features | `metrics.sleep_score_from_features` using `goose.sleep.v1` | Weighted sleep components: duration, continuity, schedule, architecture, cardiovascular context, confidence | Needs sleep window, HR/motion coverage, and enough history for baseline/training states |
| Recovery | HRV, resting HR, respiratory rate, temp, sleep score, prior strain | `metrics.recovery_score_from_features` using `goose.recovery.v0` | Weighted readiness score; baselines are required for HRV/RHR/respiratory comparisons | Missing HRV/RHR/vitals, insufficient baseline days, no sleep score, or packet proof pending |
| Strain | HR zones, duration, average/max HR, resting HR | `metrics.strain_score_from_features` using `goose.strain.v0` | Zone-load score plus average HR reserve, normalized to WHOOP-style 0-21 then UI percent | Needs activity/HR zone evidence and resting HR |
| Cardio Load | Stored Goose activity sessions with HR | `HealthDataStore+Cardio.swift` | Acute/chronic local load from activity sessions and HR samples | Needs stored activity sessions, HR samples, and enough days for baseline status |
| Stress | Local HR samples | `HealthDataStore+StressEnergy.swift` | Local proxy: 10-minute HR buckets, resting-HR elevation, HR volatility, sleep-window discount | Needs at least six HR samples today; confidence is internal model coverage, not a user-facing score |
| Energy Bank | Stress windows plus recovery seed | `HealthDataStore+StressEnergy.swift` | Local estimate: charges during likely sleep/quiet rest and drains with stress load | Needs stress windows; this is a local experimental estimate |
| Respiratory rate | Packet-derived recovery/vital event field | `metrics.vital_event_features` and daily recovery metrics | Preferred stored `respiratory_rate_rpm` | Packet field unresolved or not enough trusted vital evidence |
| SpO2 | Packet-derived pulse/vital event candidate | `metrics.vital_event_features` | Display only after a trusted field is mapped | K25/K26 candidates may exist while SpO2 semantics remain unresolved |
| Wrist temperature | Packet-derived temperature event | `metrics.vital_event_features` / recovery daily metrics | Stored skin temperature delta in Celsius | Candidate may exist but semantics must be verified before promotion |

## Coach Wiring

The Coach tab is separate from the Home screen. It uses `CoachView`, `CoachChatScreen`, `OpenAICoachChat`, and `CoachLocalToolContext`. The local context includes current health snapshots, live vitals, packet readiness summaries, and recent activity timeline items. Home previously showed an inline `CoachTipCard`; that was only a launcher into the Coach tab and has been removed from Home for now.

## Missing Data Checklist

1. Connect the band and keep BLE heart-rate samples flowing.
2. Run packet extraction from Health -> Data & Algorithms -> Packet Inputs.
3. Check Packet Inputs for next actions. It reports readiness blockers such as missing motion, missing HR, unresolved packet fields, insufficient step samples, and baseline requirements.
4. Record or import activities so activity sessions exist for Strain/Cardio Load.
5. Collect enough sleep/recovery nights for baselines. The local sleep model has explicit baseline/training states, and WHOOP's own recovery/strain docs also frame these scores as personalized rather than instant raw sensor values.

## How To Get Each Metric Working

The fastest path is: connect the band, leave HR streaming, go for normal activity, sleep with the band on, then run `Extract Local Packet Inputs` followed by `Recompute Sleep, Recovery, Strain, Stress` on the Packet Inputs page. Extract turns raw local packets into inputs. Recompute turns those inputs into local Goose scores.

| Metric | What to do | What proves it is working |
| --- | --- | --- |
| Live heart rate | Connect the band and keep the app open long enough for the BLE HR stream to update. | Home Heart Rate shows a live BPM and the Heart Rate page plots recent samples. |
| Heart-rate graph | Keep the band connected during the period you want to inspect. | Heart Rate detail shows points for 1H, 6H, 1D, or 7D. |
| Steps | Walk with the band connected, then run Extract. The app needs at least two trusted step-counter samples so it can calculate a counter delta. | Steps changes from `--` to a number; Packet Inputs shows step counter ingest and daily/hourly rollup reports. |
| Active/total calories | Collect HR plus motion during the day, then run Extract. | Strain/energy rows show calories from local HR + motion estimates. |
| Sleep | Sleep with the band on, then run Extract and Recompute Scores. | Sleep shows a packet-derived score and the Packet Inputs page shows sleep window/stage evidence. |
| Recovery | Sleep with the band on for several nights and collect HRV/resting HR/vitals, then run Extract and Recompute Scores. | Recovery shows a score; HRV/resting HR/vitals rows stop reporting missing inputs. |
| Strain | Record activities or collect enough daytime HR/motion evidence, then run Extract and Recompute Scores. | Strain shows a local score and activity rows show HR/duration/zone evidence. |
| Cardio Load | Record workouts with HR for multiple days. | Cardio Load shows recent sessions and eventually moves out of calibrating/no-data states. |
| Stress | Keep HR samples flowing today. No score run is required for the local stress proxy. | Stress shows HR sample windows instead of `No HR data`. |
| Energy Bank | Get Stress working first, then sleep/recovery history improves the seed value. | Energy Bank shows charged/balanced/using energy instead of no data. |
| Respiratory rate, SpO2, wrist temperature | Sleep with the band on and run Extract. These remain hidden/unavailable until the local packet mapping is trusted. | Health Monitor rows show packet-derived values rather than packet proof pending. |

If a button appears to do nothing, check the status row under it. `Extract Local Packet Inputs` and `Recompute Sleep, Recovery, Strain, Stress` can take a few seconds because they call the local Rust bridge across captured packet history.
