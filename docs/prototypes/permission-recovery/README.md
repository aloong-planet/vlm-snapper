# Screen capture permission recovery prototype

This prototype compares two requested structures for recovering when macOS screen capture permission is denied or revoked.

Direction A was selected on 2026-08-27. The product uses one reusable recovery panel over the current entry surface so onboarding and the menu-bar capture entry share the same recovery interaction.

- Direction A: one reusable recovery panel presented over the current entry surface.
- Direction B: recovery guidance expands in place inside the onboarding permission item or menu bar panel.

Both directions preserve the confirmed behavior: the app does not repeat the system permission request after denial or revocation, opens System Settings explicitly, asks for an app restart after access becomes available, and always allows the user to leave recovery without changing permission state.

The structure, scenario, permission state, and theme controls in the bottom dark pill are prototype harness UI and are not part of the product design.
