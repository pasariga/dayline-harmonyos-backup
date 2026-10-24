[English](README.md) | [简体中文](README.zh-CN.md)

# Dayline

A local-first HarmonyOS deadline planner for students. Dayline connects task breakdown, progress, explicitly confirmed remaining effort and shared daily capacity to help answer a practical question: **what should I work on today?**

This repository is a source backup of the existing ArkTS/ArkUI application, internally named DDL. It is not an AppGallery release or a complete signed distribution. The latest source-backup commit predates this documentation-only update; ongoing product maintenance is not implied.

## Product workflow

Create a deadline with a name and due date, add tasks or optional effort estimates, follow the next recommended action, and revise the remaining effort when circumstances change. The application recalculates risk and reverse schedules from the available inputs instead of treating task percentages as hours already spent.

Implemented local features include nested tasks, manual/automatic progress, overdue handling, undo and draft protection, shared capacity across deadlines, local relational storage, appearance settings and multilingual resources. The UI separates Today/Deadlines and the detail page's Action/Workload-and-plan workspaces.

## Engineering work preserved here

| Area | Implementation and existing records |
| --- | --- |
| Workload and planning | Remaining effort is confirmed separately from initial estimates and task completion. Unknown/stale estimates degrade honestly; deadlines share daily capacity. See `DeadlineInsightService`, `DeadlineScheduleService` and `TodayActionService`. |
| Persistence | Relational-store services, migrations, transactional updates and historical conflict handling are retained in `entry/src/main/ets/services/`. |
| Time semantics | `DeadlineTime.ets` and time-boundary validation distinguish fixed instants from calendar days, including timezone and daylight-saving cases. |
| Interaction | The existing experience redesign reorganizes actions and explanations; draft retention, undo, small-screen/large-font behavior and accessibility labels have accompanying records. |
| Cloud boundary | `ReleaseScope.ets` fixes `CLOUD_SYNC_AVAILABLE=false`. Historical synchronization/conflict code is retained, but account login and real app cloud exchange are outside the current local-first scope. |

These are source-backed changes. Historical validation results are kept as dated evidence, not presented as tests rerun by this documentation update.

## Important limits

- Notifications are optional assistance. Reliable background timed delivery/cancellation is **not** established; the historical Calendar/Timer `1700002` issue and device-validation limits remain documented.
- Current scope does not expose account login or cloud sync. Preserved protocol and AGC integration code is not evidence that a cloud service is ready.
- The previous project record identifies release-profile, publisher identity and formal policy-link requirements before store submission. No app-store publication or new signed package is claimed here.

## Explore or build

Start with `entry/src/main/ets/pages/`, then inspect `models/Deadline.ets` and the services. The recorded environment is DevEco Studio with HarmonyOS 6.1.1 / API 24, Stage model, Phone target.

Open the project in a matching DevEco Studio environment. This backup contains module configuration and Hvigor files, but the root `build-profile.json5` and private signing material are not included. Supply your own authorized project/product configuration before attempting a signed build; do not copy someone else's signing credentials. A fresh-clone build has not been verified in this documentation task.

- [Historical project and development record (Chinese)](docs/PROJECT-HISTORY.zh-CN.md)
- [Cloud configuration boundaries](CLOUD_SYNC_SETUP.md) and [sync reliability record](SYNC_RELIABILITY_REPORT.md)
- [Experience redesign](validation/experience-2026-10-18/README.md), [layout/accessibility hardening](validation/hardening-2026-10-19/README.md), [time semantics](validation/time-boundaries-2026-10-05/README.md)

Long implementation history is preserved separately to keep the homepage readable. Device/emulator observations in those records apply only to their stated conditions; they are not broad compatibility or current service guarantees.

## License and attribution

The source identifies the application as Dayline, bundle `com.gary.ddl`. No repository-level license file is present in this snapshot. This README adds no license grant and does not establish redistribution rights for third-party materials. Existing authorship and history are retained; publisher and release authorization remain to be confirmed by the owner.
