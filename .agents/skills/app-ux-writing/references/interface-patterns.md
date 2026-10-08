# Interface patterns

Consult the patterns involved in the requested screen or flow. The examples below are original illustrations, not quotations or product behavior specifications. Use their wording only when the stated behavior is true of the app.

## Flow and hierarchy (PACE)

Use PACE when deciding what a screen says, where information appears, or how steps connect:

- **Purpose:** Give each screen one primary job. Make it visible in the heading and action; supporting text adds distinct information. Disclose secondary detail where it becomes useful, while keeping informed-choice consequences beside the decision.
- **Anticipation:** Answer the next likely question. Explain intermediate states and how someone will know when they can proceed; match each step to the expectation created by the previous one.
- **Context:** Fit information to attention, device, surroundings, and emotional stakes. Put instructions beside the interaction that needs them. Move mistimed explanations or remove an unnecessary step instead of polishing around a hierarchy problem.
- **Empathy:** Check assumptions about ability, identity, circumstances, and feelings. Apply the accessibility and localization checks below so the conversation works beyond its visual, source-language presentation.

## Headings, onboarding, and instructions

Describe the reason for a request before its mechanics when that helps someone decide.

For example, “To get pickup updates, add your phone number” explains a reason for providing information. It is appropriate only if those updates are the actual use; it must not disguise other material uses of that information.

## Buttons and choices

Established navigation labels such as “Next” can work when the action is simply advancing through a flow.

When cancellation is itself the task, name the alternatives explicitly. For a hypothetical booking flow, “Cancel Booking” and “Keep Booking” make the outcomes clearer than “Confirm” and “Cancel.” Identify the affected booking and disclose relevant consequences based on the actual policy.

## Errors and blocked actions

Identify the problem in terms the person understands. Explain a supported recovery action and provide a control that reaches it when the app supports that path. If retrying cannot resolve the problem, a generic retry instruction provides no recovery.

For a known connectivity failure, a draft might be:

- Heading: “Upload Paused”
- Body: “Connect to the internet to upload your recording.”
- Action: “Retry Upload”

This draft requires a retained recording and a working retry action. If either is unknown, resolve that behavior before promising it. Keep diagnostic codes secondary to the explanation when support needs them. Use a neutral tone that takes the inconvenience seriously.

## Alerts and permissions

Use an alert for a necessary decision, acknowledgment, or interruption; suggest a contextual inline message when that would better support the task. Explain why requested access is useful at the relevant moment. Distinguish app-authored rationale from system-controlled permission text.

For a destructive choice, identify the object, scope, and whether recovery is possible when known. Preserve critical consequences even when this makes the copy longer. Use exact actions for both alternatives and check that dismissing the alert behaves as described.

## Empty states

Determine why content is absent before choosing the message: first use, no search matches, completed work, or a loading failure call for different explanations. Describe what belongs here and how it will appear when that guidance is useful.

For example, an unused saved-trails list could say “No Saved Trails” with “Save trails while browsing to find them here.” A list of completed tasks can acknowledge completion; a retrieval failure needs recovery language. An empty container alone is not evidence that someone has finished their work.

## Notifications and progress

Give notifications useful, self-contained information or an available task: someone should learn what happened without opening the app. Lead with the event, changed expectation, or benefit; use expanded content for relevant detail or actions. Distinguish elapsed delay from remaining time: “delayed 10 minutes” and “arrives in 10 minutes” make different promises. Preserve estimates and uncertainty when the underlying data is uncertain.

For progress, say what is happening and what the person should do or expect next when known. Fit the message to a glance when attention is divided.

## Accessibility and localization

Check that meaning survives the visual presentation. Label controls by their function in context, rather than a glyph’s appearance. Disambiguate repeated actions with their object and update labels when the action changes with state. Rely on native role announcements instead of repeating “button” in the label. Informative images and charts need descriptions of their relevant meaning or intention; account for grouping and decorative content so the spoken experience stays coherent. Avoid relying solely on position, color, or imagery for necessary instructions.

Allow for longer words, taller scripts, larger or bold text, and right-to-left layouts. Abbreviations that work in English may have different lengths or no equivalent in another language. Adapt the layout or wording without discarding essential meaning to fit an English-sized space.

Use inclusive terms and culturally portable expressions appropriate to the audience. Avoid assumptions that a task is easy, that someone is happy, or that everyone shares a cultural reference. Flag idioms, jokes, and coined names for language review where needed. A source-language review can identify risks; it cannot certify every translation or the runtime VoiceOver experience.
