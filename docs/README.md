# docs/

Documentation for Klip v3.0.0, including implementation planning, codebase analysis, and task briefs.

## plan/

- **PLAN.md** - Phased implementation plan (v3.0.0) with architecture, decisions (D1-D7), task matrix, and feature traceability
- **PROGRESS.md** - Execution log and timeline; read this when resuming work
- **briefs/** - Individual task briefs for each phase and agent:
  - Phase 0: 0.2 build_local.sh, 0.3 test runner, 0.4 rebrand, 0.5 upstream baseline
  - Phase 1: 1A history split, 1B model/store, 1C settings/theme
  - Phase 2: 2A Clipfield UI, 2B refute-review
  - Phase 3: 3A lock, 3B folders/drag-drop, 3C detection, 3D rich/plain/context menu, 3E shortcuts, 3F file clips, 3G permissions, 3H font sweep
  - Phase 4: 4A iCloud sync, 4B refute-review
  - Phase 5: 5A adversarial review, 5B xcodeproj sync, 5D docs
- **review-2B.md** - 2B refute-review findings (no regressions, 1 medium issue)

## analysis/

Codebase analysis reports for reference and architectural guidance:

- **buffer.md** - Analysis of upstream Buffer architecture, findings that changed the plan
- **clipfield.md** - Clipfield's design tokens, UI components, architecture (for porting)
- **pesty.md** - Pesty's iCloud Drive sync approach and other relevant patterns
