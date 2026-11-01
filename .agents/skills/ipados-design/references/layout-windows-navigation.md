# Layout, windows, and navigation

## Window size is the constraint

Current iPadOS supports full-screen and freely resizable windowed apps. Build around the available scene bounds, safe areas, and actual content fit; size classes alone do not describe every window size. Keep editing state, selection, focus, and scroll position through resize and rotation. System window controls occupy the leading toolbar area in windowed mode, so custom leading actions must adapt to their insets.

Earlier deployment targets can still use Split View, Slide Over, and Stage Manager. Test the configurations available on the supported OS and hardware; fixed split ratios are not the current layout model. Apps receive available geometry rather than a multitasking-mode identifier.

Multiwindow is useful for comparing content or composing beside a source. Use independent per-window navigation, selection, drafts, and undo context while synchronizing shared model data. Opening a new window should follow a user task; every navigation tap need not spawn one.

## Match navigation to content

Prefer a top tab bar for frequently used peer sections; a sidebar-adaptable tab view lets people expose a richer hierarchy. `.sidebarAdaptable` requires iPadOS 18 or later and provides a top tab bar that can convert to a sidebar, not an unconditional regular-width sidebar. Use a navigation split view when persistent category/list/detail columns represent the hierarchy. Collapse to a useful compact path and preserve selection across transitions.

Use extra width for related content or tools rather than stretching narrow forms. An unselected detail pane can explain the selection task. Toolbars and inspectors keep context visible; popovers anchor focused options to their source, while sheets suit bounded workflows. Allow these presentations to adapt in small windows.

## External displays

Distinguish an app window moved to an external display from a deliberate presentation or playback scene. Only the latter needs complementary content and controls separated across displays. Use the connected scene's geometry and lifecycle, not the main device's screen bounds. Preserve work when the display disconnects, and return control to a usable remaining scene. Multiple ordinary WindowGroups alone do not configure an external-display scene role.

Sources: [Windows](https://developer.apple.com/design/human-interface-guidelines/windows), [Multitasking on iPad, Mac, and Apple Vision Pro](https://developer.apple.com/documentation/uikit/multitasking-on-ipad-mac-and-apple-vision-pro), [Multitasking](https://developer.apple.com/design/human-interface-guidelines/multitasking), [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars), [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars), [sidebarAdaptable](https://developer.apple.com/documentation/swiftui/tabviewstyle/sidebaradaptable), [Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers), [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets).
