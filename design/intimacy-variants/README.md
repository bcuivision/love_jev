# Intimacy score UI explorations

Created 2026-09-27 with the built-in ImageGen tool, grounded in the current native iOS preview at `current-icon-only.png`. These are visual concepts, not implemented score layouts. The requested Sparkle background removal is already implemented in `ios/Shared/KeyboardSurface.swift`; the icon retains its invisible 44 × 44 pt touch area. The simulator build passed.

The images were displayed in this order:

1. [Score beside reply](01-score-beside-reply.png): a dedicated large score column, recommended reply beside it. Best starting point for keeping the keyboard compact.
2. [Score-led header](02-score-led-header.png): a prominent metric row and a slim scale above the reply. Makes the score the first reading stop, with more vertical space.
3. [Score transition](03-score-transition.png): current and predicted values share a large before/after comparison during drafting. Labels separate the current interaction score from the predicted change.

## Design rationale

The existing ready state presents the score as 12 pt secondary text in the upper corner. In the draft impact state, the large change competes with the small current/resulting values. Promote the score with 30–34 pt numerals, a clear `亲密值` label, dedicated space and restrained warm accent color. Keep the recommendation readable and preserve manual analysis, evidence disclosure and draft insertion. All concepts use a bare blue Sparkle icon without a background.

The concepts explore hierarchy rather than a new visual brand. Dark native materials, Chinese chat bubbles and the keyboard are retained. The design target is a 390 × 844 pt portrait app surface. Some concepts propose a taller assistant area than the current 88 pt toolbar; implementation should account for this explicitly rather than compressing the keys. Scores are illustrative interaction values, not probabilities.

## Generation brief / prompt set

All three calls used the current native screenshot as an attached reference and the built-in image generation tool. Shared direction: production-quality native iOS mockup, app content only, no phone bezel or system status chrome, clear Chinese typography, no nested cards, bare blue SF Symbols Sparkle with an invisible 44 pt touch area, no unrelated features.

- **Score beside reply:** recommendation-ready state with empty draft; large warm 72 and `亲密值` in a left column, quiet divider, `下一句` and the reply `要不要一起喝杯咖啡？我知道一家不错的。` to the right, with `填入`; compact assistant area around 100 pt. No predicted delta in this state.
- **Score-led header:** recommendation-ready state; a full-width metric row with `亲密值`, a large 72 and `互动顺畅`, a thin 0–100 scale, then a full-width recommendation row. Sparkle at upper right. Assistant area around 110 pt; no predicted delta.
- **Score transition:** drafting state with the recommendation in the composer; large `当前 64` and `发送后预估 72`, central `预计 +8`, and a short explanation. Neutral dark background with a subtle warm accent line, no broad orange gradient. Assistant area around 115 pt. Preserve the host app's send button and label the prediction as an illustrative estimate.

ImageGen concepts are not pixel-exact implementation specifications; native controls, exact text, layout measurements and accessibility remain authoritative during the selected design's implementation.
