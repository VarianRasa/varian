# Charts Milestone 3 Implementation Plan

## Overview
Complete the app-owned part of Charts Milestone 3 without inventing a database contract: add a bounded JSON/API URL source, preserve a manual fallback, and make vector export resolve local Table/Grid sources and category filters consistently with canvas rendering.

## Architecture decisions
- Reuse the existing `http` dependency and `ChartPayload` JSON contract: `{categories, series}` or `{data: {categories, series}}`.
- Keep remote data transient at render time. Persist the URL and a refresh revision, while retaining the last saved chart data as the offline fallback.
- Enforce HTTP(S)-only URLs, an 8-second timeout, no request credentials, and a 1 MiB response limit.
- Keep Table/Grid resolution and category filtering in the existing `ChartPayload`/canvas path; export uses the same effective payload.
- Do not add a database adapter until an endpoint/query/auth contract exists.

## Task list

### Phase 1: JSON/API URL source
- [x] Add persisted source URL and refresh revision fields to `ChartPayload`.
- [x] Add a bounded HTTP JSON loader with payload validation and safe fallback.
- [x] Render the loaded payload in `ChartNodeWidget` without recursive fetches.
- [x] Add inspector URL and refresh controls.

### Phase 2: Export parity
- [x] Resolve Table/Grid source and category filter before SVG chart export.
- [x] Preserve manual fallback when a remote source is unavailable during export.

### Checkpoint: Milestone 3 app-owned scope
- [x] Focused source, model, inspector, and export tests pass.
- [x] Analyzer, full tests, and Web release build pass.
- [x] `git diff --check` passes.

## Out of scope
- Database-specific queries, credentials, pagination, and server-side aggregation without a backend contract.
- Canvas click-through drill-down; chart nodes remain pointer-ignored so canvas selection and drag behavior stay intact. Persisted `categoryFilter` remains the local filter path for authoring and export.
- Remote writes, authentication setup, or deployment.
