# Modern Floating HUD Player Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the Stitch video player (`CustomVideo` for VODs and `StitchVideo` for Live streams) into a modern, dual-zone Floating HUD (Apple TV / modern Twitch style) with Lucide-style iconography, dynamic gradient scrims, responsive sidebar layout, and an integrated Settings button.

**Architecture:** Split the player HUD from a cramped single 160px bottom bar into a Top Floating Header (streamer info, title, category, live uptime, quality badge) and a Bottom Floating Scrubber & Capsule Action Bar. Implement shadcn-style pill buttons with Lucide icon assets and SceneGraph `blendColor` tinting. Dynamically adjust HUD coordinates and widths when the chat sidebar is toggled.

**Tech Stack:** Roku SceneGraph (XML), BrightScript (BRS), Archivo fonts, 9-patch assets, Lucide PNG icons.

**Spec:** [DESIGN.md](file:///home/diego/Documents/GitHub/Stitch-Revitalized-For-Roku/DESIGN.md)

## Global Constraints
- Target platform: Roku OS (1080p coordinate space: 1920x1080).
- Overscan safe zones: Horizontal min 60px, vertical min 50px.
- Typography: Minimum 16px for any readable text on 10-foot UI.
- All colors must use Design System semantic tokens from `constants.brs`.
- Conventional Commits with max 100 character subject headers.

## Review Focus
- Chat sidebar toggle in both VOD and Live player must resize the seekbar and recenter action buttons without layout jumps.
- Settings button `[ ⚙ ]` must open the quality picker in both Live and VOD.
- D-pad navigation across action buttons must wrap cleanly and update focus states accurately.
- Text overflow in stream titles must truncate cleanly with `maxWidth` without clipping streamer name or badges.
- Muted segment highlights on VOD seekbar must remain visible and correctly positioned when seekbar width changes.

---

### Task 1: Update Design System Specification (`DESIGN.md`)

**Files:**
- Modify: `DESIGN.md`

- [ ] Add Section 6 to `DESIGN.md` documenting the Modern Floating HUD architecture:
  - Top Floating Header layout, coordinates, and safe areas.
  - Bottom Floating HUD with precision 6px seekbar and time remaining display.
  - Action Capsules specification (`focusRing` halo, `blendColor` icon states).
  - Quick Settings `[ ⚙ ]` modal trigger specification.
  - Chat Sidebar responsive behavior (`1800 - chatWidth` seekbar contraction).
- [ ] Verify formatting and markdown structure.
- [ ] Commit: `docs(design): document modern floating hud player architecture in DESIGN.md`.

---

### Task 2: Icon Assets & Scrim Textures

**Files:**
- Create: `images/icons/settings-gear.png`
- Create: `images/icons/rotate-ccw-10.png`
- Create: `images/icons/rotate-cw-10.png`
- Create: `images/icons/time-travel.png`
- Create: `images/icons/chat-bubble.png`
- Create: `images/scrim_top.png`
- Create: `images/scrim_bottom.png`

- [ ] Generate crisp Lucide-style RGBA PNG icons (48x48) for player actions:
  - Settings gear, rotate -10s, rotate +10s, clock timetravel, chat bubble, back arrow.
- [ ] Generate smooth vertical gradient scrims for top (fade from `0x000000D0` to `0x00000000`) and bottom (fade from `0x00000000` to `0x000000E6`).
- [ ] Verify image assets in `images/` directory.
- [ ] Commit: `feat(assets): add lucide-style player icons and gradient scrims`.

---

### Task 3: Redesign `CustomVideo` (VOD Player) Floating HUD

**Files:**
- Modify: `components/Modules/CustomVideo/CustomVideo.xml`
- Modify: `components/Modules/CustomVideo/CustomVideo.brs`

- [ ] Restructure `controlOverlay` into `topOverlayGroup` and `bottomOverlayGroup`:
  - `topOverlayGroup`: Top scrim, Avatar (48x48), Streamer name (22px Archivo-Bold), Stream title (16px Archivo-Regular, maxWidth 1100), Quality badge.
  - `bottomOverlayGroup`: Bottom scrim, timeProgress (`01:23:45`), progressBar (height 6px, base, buffer, progress, mutedSegmentsGroup, progressDot), timeRemaining (`-00:45:12`).
  - Action capsules row: `[ ← ] [ ⏱ ] [ -10 ] [ ▶/⏸ ] [ +10 ] [ 💬 ] [ ⚙ ]` using Lucide icons with `blendColor` for focused/unfocused states.
- [ ] Update `CustomVideo.brs`:
  - Update button navigation indices (`m.currentFocusedButton` from 0 to 6):
    - 0: Back (`←`)
    - 1: TimeTravel (`⏱`)
    - 2: Rewind (`-10`)
    - 3: Play/Pause (`▶/⏸`)
    - 4: FastForward (`+10`)
    - 5: Chat Mode (`💬`)
    - 6: Settings (`⚙`)
  - Implement button 6 action: trigger quality/speed quick dialog or settings callback.
  - Update `onChatVisibilityChange()` to adjust top metadata width, seekbar width, and recenter bottom buttons within the active video area.
  - Format right time label as remaining time (`-HH:MM:SS` or `-MM:SS`).
- [ ] Verify build: `npm run build`.
- [ ] Commit: `feat(player): implement modern floating hud in CustomVideo`.

---

### Task 4: Redesign `StitchVideo` (Live Stream Player) Floating HUD

**Files:**
- Modify: `components/Modules/StitchVideo/StitchVideo.xml`
- Modify: `components/Modules/StitchVideo/StitchVideo.brs`

- [ ] Restructure `controlOverlay` into `topOverlayGroup` and `bottomOverlayGroup`:
  - `topOverlayGroup`: Top scrim, Avatar (48x48), Streamer name, Stream title, Live badge + Uptime capsule, Quality badge.
  - `bottomOverlayGroup`: Bottom scrim, Live progress bar (full purple with live indicator), Action capsules row:
    `[ ← ] [ 💬 ] [ ⚙ ]` (centered in video area).
- [ ] Update `StitchVideo.brs`:
  - Button 0: Back (`←`), Button 1: Chat Mode (`💬`), Button 2: Settings (`⚙`).
  - Connect Button 2 directly to `showQualityDialog()`.
  - Update `onChatVisibilityChange()` for recentering and width adjustments.
- [ ] Verify build: `npm run build`.
- [ ] Commit: `feat(player): implement modern floating hud in StitchVideo`.

---

### Task 5: Compilation, Packaging & Roku Deployment Verification

**Files:**
- Output: `out/Stitch-Revitalized-For-Roku.zip`

- [ ] Run full production build and package: `npm run build && npm run package`.
- [ ] Deploy to Roku Express 4K+ (`192.168.1.3`):
  `curl -s -u rokudev:2903 --digest -F "mysubmit=Replace" -F "archive=@out/Stitch-Revitalized-For-Roku.zip" http://192.168.1.3/plugin_install`.
- [ ] Confirm "Install Success" and verify functionality on target Roku hardware.
- [ ] Final summary and handoff to user.
