# Pencil and handwriting

Standard text input supports Scribble; custom input needs explicit integration. PencilKit is a useful starting point for ink and annotation. Detect actual device capabilities for pressure, tilt, hover, double tap, squeeze, and barrel roll rather than assuming every Pencil supports them.

Respect configured double-tap and squeeze actions when meaningful. Keep these gestures nondestructive and easy to undo; squeeze performs a discrete action and can reveal tools near the tip. Barrel roll changes the mark, not navigation. Hover previews the prospective stroke without committing it; keep preview changes stable as height varies.

Sources: [Apple Pencil and Scribble](https://developer.apple.com/design/human-interface-guidelines/apple-pencil-and-scribble).
