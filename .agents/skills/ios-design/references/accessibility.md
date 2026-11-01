# Accessibility

Check the exposed accessibility label, value, role, and reading order before adding overrides to standard controls. Name icon-only controls by their action or meaning, rather than the symbol’s visual shape. After dismissal, return focus to the invoking control or useful content; after navigation or resizing, keep it on the intended surviving content. Essential text can reflow or scroll at enlarged sizes rather than truncating the task.

For touch, aim for 44×44 pt controls. Current HIG distinguishes this default from the 28×28 pt minimum; smaller controls need careful spacing and an effective hit region. Test actual tapping and assistive activation rather than enlarging only the visible symbol.

For changed semantics or focus, follow the affected task with VoiceOver and keyboard or switch navigation. For changed feedback, expose status and errors beyond color, sound, position, or hover alone. For media, provide captions or descriptions for essential information.

Sources: [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover), [Typography](https://developer.apple.com/design/human-interface-guidelines/typography).
