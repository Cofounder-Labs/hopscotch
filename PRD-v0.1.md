# Product Requirements Document – Universal Overlay Assistant (MVP v0.1)

## 1. Document Control
| Item | Detail |
|------|--------|
| **Product Code‑Name** | Universal Overlay Assistant |
| **Version** | 0.1 (MVP) |
| **Authors** | Internal team, drafted via ChatGPT (Apr 28 2025) |
| **Status** | Draft – review needed |

---

## 2. Purpose & Scope
A lightweight macOS utility that grants large‑language‑model agents the ability to **draw on‑screen annotations** and **observe user interactions** anywhere on the desktop. The MVP covers two modes—**Act** (draw) and **Observe** (monitor clicks)—while handling all required macOS privacy permissions.

Out‑of‑scope for v0.1: automatic computer‑vision element detection, multi‑user analytics, Windows/Linux builds, in‑app onboarding flows.

---

## 3. Goals & Success Metrics
| Goal | Metric | Target |
|------|--------|--------|
| Obtain permissions | % installs that successfully grant all three privacy entitlements on first run | ≥ 90 % |
| Responsive overlay | Latency from agent command → annotation visible | ≤ 100 ms |
| Click detection accuracy | Clicks inside annotated region correctly reported | ≥ 99 % |

---

## 4. Key User Stories (P0 = MVP‑critical)
| ID | Priority | Story |
|----|----------|-------|
| US‑1 | P0 | *As a first‑run user*, I am prompted once for Accessibility, Screen Recording, and Input Monitoring permissions, with clear instructions if I decline and later reopen the app. |
| US‑2 | P0 | *As an agent/developer*, I can send an **Act** command containing `{x, y, width, height, targetBundleID}` and see an annotation (highlight rectangle) drawn at those coordinates over the correct app window. |
| US‑3 | P0 | *As an agent/developer*, I can send an **Observe** command with `{x, y, width, height}` and receive an event/callback if the user clicks within that region. |
| US‑4 | P0 | *As a user*, I can toggle between **Observe** and **Act** modes from a menu‑bar icon or keyboard shortcut, with the current mode visibly indicated. |

---

## 5. Functional Requirements
### 5.1 Permission Handling (REQ‑PERM‑1)
* On launch, the app checks and requests:
  1. **Accessibility** (`AXTrustedCheckOptionPrompt`)  
  2. **Screen Recording** (via `CGPreflightScreenCaptureAccess`)  
  3. **Input Monitoring** (click‑event tap)  
* The UI shows real‑time status for each permission and disables overlay functionality until all are granted.

### 5.2 Mode Management (REQ‑MODE‑1)
* Two mutually exclusive runtime states: **Observe** and **Act**.
* Mode can be set programmatically (`/usr/local/bin/overlayctl --mode act`) or via UI.

### 5.3 Act Mode (REQ‑ACT‑*)
| ID | Requirement |
|----|-------------|
| REQ‑ACT‑1 | The utility determines the **frontmost app** (via `NSWorkspace.shared.frontmostApplication`) and validates that it matches `targetBundleID` in the command. |
| REQ‑ACT‑2 | Creates a transparent, click‑through **overlay window** at `.screenSaver` level (one per display) and positions a highlight layer at `{x, y, width, height}` (global coordinates). |
| REQ‑ACT‑3 | Supports `style: box | arrow | pulse` and `duration` parameters (future‑proofing). |
| REQ‑ACT‑4 | Emits a JSON acknowledgment `{status:"drawn", ts:…}` once the annotation is visible. |

### 5.4 Observe Mode (REQ‑OBS‑*)
| ID | Requirement |
|----|-------------|
| REQ‑OBS‑1 | Installs a global left‑click event‑tap (`kCGHIDEventTap`). |
| REQ‑OBS‑2 | On each click, compares location to active annotation rect(s) and, if intersecting, sends `{event:"click‑inside", rectId, ts}` to the agent. |
| REQ‑OBS‑3 | Handles coordinate conversion across multiple displays and varying scale factors. |
| REQ‑OBS‑4 | Provides throttling so the same click is not reported twice. |

---

## 6. Non‑Functional Requirements
* **Performance**: annotation render ≤ 16 ms per frame; observe polling ≤ 1 % CPU.
* **Security**: No screenshots or click logs are stored to disk.
* **Compatibility**: macOS 12.0 (Monterey) and later; Apple Silicon & Intel.
* **Resilience**: Gracefully disables features lacking permissions but keeps menu‑bar UI alive.

---

## 7. External Interfaces
| Interface | Direction | Format |
|-----------|-----------|--------|
| `overlayctl` CLI | Agent → App | JSON on `stdin` / `stdout` |
| Notification Center | App → User | macOS alerts for unrecoverable errors |

---

## 8. UX & UI
* **Menu‑bar extra** shows ○ Observe / ● Act icon, permission checklist, “Quit”.
* No main window; preferences sheet opens from menu.
* Annotations default to 4 pt rounded corner lime‑green box with drop‑shadow.

---

## 9. Risks & Mitigations
| Risk | Likelihood | Mitigation |
|------|------------|-----------|
| Users deny Screen Recording | Med | Provide onboarding video + deep‑link to System Settings ▶ Privacy. |
| Event‑tap conflicts with other security tools | Low | Allow fallback to polling `NSEvent` addGlobalMonitor. |
| Overlay hidden behind full‑screen games | Med | Expose debug flag to raise window level further. |

---

## 10. Decisions on Previously Open Questions
1. **Overlay dismissal**: The overlay automatically dismisses after a **2‑second** timeout (value hard‑coded for v0.1; may become user‑configurable later).
2. **Annotation style**: MVP delivers **static box highlights only**; no arrows or animated effects.
3. **Multi‑agent arbitration**: Deferred—out of scope for v0.1. We will consider an IPC/auth model in a later release.

---

## 11. Timeline (T‑shirt sizing)
| Phase | Tasks | Duration |
|-------|-------|----------|
| **Spike** | Prototype overlay drawing + click detection | 2 wks |
| **Build** | Permissions flow, CLI, mode toggles | 4 wks |
| **QA** | Multi‑display, Sonoma, Intel Macs | 2 wks |
| **Beta** | Internal dogfood, bug‑bash | 2 wks |
| **Ship MVP** | v0.1 to Cursor integration repo | **D+10 wks** |

---

> **End of PRD v0.1**

