# MobileClaw Architecture

## Goals
- Keep PicoClaw-like core flow: `message -> context build -> memory retrieval -> provider -> persist`.
- Support conversation memory and OpenClaw-compatible workspace files.
- Support bidirectional migration/backup with OpenClaw workspace (`AGENTS.md`, `skills/**/SKILL.md`, `memory/**`).
- Keep AI runtime alive when app is backgrounded by using Android foreground service.
- UI follows Material 3 and renders markdown via `flutter_markdown`.

## Layers
- `core/models`: transport and domain models.
- `core/services`: memory store, skill loader, migration bridge, backup service, runtime loop.
- `core/providers`: LLM abstraction and providers.
- `features/chat`: controller and UI.
- `features/settings`: import/export/backup controls.

## OpenClaw compatibility rules
- Workspace config files: `AGENTS.md`, `SOUL.md`, `USER.md`, `TOOLS.md`, `HEARTBEAT.md`.
- Skill folder format: `skills/<name>/SKILL.md`.
- Memory: app stores JSONL + metadata; import/export can map to markdown memory notes for OpenClaw workspace.

## Background strategy
- On Android, run a foreground service (`flutter_foreground_task`) with a persistent notification when AI runtime is active.
- This is the most stable mobile strategy against background process kills.
