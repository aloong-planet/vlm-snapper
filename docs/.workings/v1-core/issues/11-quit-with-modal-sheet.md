# 11 — Quit while an application sheet is presented

Status: completed

Blocked by: none

## Goal

Ensure menu Quit, `Command-Q`, and system Quit reach the coordinated shutdown path while a VLMSnapper-owned SwiftUI sheet is presented.

## Acceptance

- Provider setup, permission recovery, and storage/privacy sheets do not cause AppKit to cancel application termination before the application delegate is consulted.
- An accepted termination still cancels and persists active work through the existing shutdown coordinator.
- Canceling the unsaved-result confirmation keeps the application running and preserves the sheet that was visible before Quit.
- App-modal alerts and system panels outside this sheet policy retain their existing termination behavior.
- A real AppKit window test proves that attaching the policy changes the sheet-window termination flag; a signed-app smoke test reproduces Quit with Provider setup visible.
- The v1 spec, feature catalog, prototype, and implementation describe the same behavior.

## Comments

- 2026-08-31: The installed build reproduced `User canceled (-128)` twice. Unified Log reported `App termination blocked by modal sheet`, and the live 720 x 590 window matched Provider setup.
- 2026-08-31: Design review rejected forcibly ending sheets before termination because canceling the unsaved-result confirmation would discard the user's visible configuration context. The selected design uses the AppKit modal-termination policy only on VLMSnapper-owned SwiftUI sheets.
- 2026-08-31: The real AppKit integration test covers Provider setup, permission recovery, and storage/privacy sheet windows. A targeted mutation that removed the storage/privacy modifier failed on the window policy assertion, then passed again after restoration.
- 2026-08-31: A separate-bundle Developer ID probe built from this branch opened the real Provider setup sheet. Standard Apple Event Quit returned success and PID 97975 exited; the installed old build was neither replaced nor terminated.
