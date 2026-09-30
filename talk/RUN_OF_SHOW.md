# Run of show: "Decide in code" (45 min)

Richmond AWS User Group, Oct 1. Deck: `Decide_in_Code_System_One_Models_on_AWS.pptx` (speaker notes on every slide).

## The one idea the audience must leave with

> **An LLM writes an answer. A System One model scores the answers you allowed.**
> So you get a probability back instead of prose, and your code, not the model, makes the decision.

Everything else in the talk hangs off that sentence. If someone only remembers slide 5 and the demo, the talk worked.

## System One in plain words (for you, before the talk)

- **The name** is from Kahneman's *Thinking, Fast and Slow*. System 1 is the snap judgment (you see a face
  and *know* it's angry). System 2 is slow, deliberate reasoning. A chat LLM writing an answer word by word
  is System 2. A System One model is built for the snap judgment.
- **What you send:** the state (a support message, a tool call, a JSON blob) plus questions, each with its
  allowed answers: yes/no (`noul`), one of a list (`choice`), or a level (`score`).
- **What happens inside** (circuit-8b; its design is public): it's an ordinary 8B language model with a small
  extra layer on top. Each allowed answer is wrapped in marker tokens, the input ends with a "decide" token,
  and the extra layer scores every answer's marker against it at once. A softmax turns the scores into
  probabilities that sum to 1. One forward pass, no text generated, so ~100-200 ms.
- **Why the probability is useful:** it's trained against real outcomes, so "0.8" should be right about 8
  times in 10 (that's *calibration*). That's what makes a threshold like `>= 0.6` mean something.
- **Why it can still be wrong** (slide 8): calibrated *on average* doesn't mean right *on this item*. On
  questions built to be undecidable, models still answered with 0.5-0.97 confidence. So: the model answers,
  code decides, and anything near the line (the band) goes to a person.
- **Is it just a classifier?** Pretty much, yes, but you define the classes per request, in English, for
  any state, with no training run. That's the new part.

## Timeline

| Clock | Slide(s) | What happens | Minutes |
|---|---|---|---|
| 0:00 | 1-2 | Title; "hands up if you've wrapped a regex around an LLM response" | 2 |
| 0:02 | 3-4 | Decisions in disguise; the request/response shape | 4 |
| 0:06 | **5** | **Why "System One"**: the key slide, go slowly | 5 |
| 0:11 | 6-7 | Jev launch (be honest: two weeks old, vendor numbers); why it belongs | 3 |
| 0:14 | 8 | Valid isn't correct: the pivot of the talk | 3 |
| 0:17 | 9-10 | Not in Bedrock: three paths; the open clones | 4 |
| 0:21 | 11-12 | Decision circuits; the band | 6 |
| 0:27 | 13 | Architecture: walk left to right | 2 |
| 0:29 | 14 | **Live demo** (below) | 10 |
| 0:39 | 15 | Three takeaways | 1 |
| 0:40 | | Q&A | 5 |

If you're running long, compress 6-7 and 9-10 (they're context). Never cut 5, 8, 12 or the demo.

## Demo script (slide 14)

Before the talk (stack already deployed; don't `terraform apply` from scratch on stage):
1. 30 min out: `scripts/preflight.sh`, every line `ok`.
2. Second terminal: `scripts/warmup.sh --keep-warm` (leave it running).
3. Editor open on `lambda/circuit.py`; terminal font large; `clear`.

On stage:
1. `scripts/demo.sh --step`. Enter before each message:
   - **1 routed.** Point at `gates.redact.p` (tiny) and `gates.route`: "the model never saw the rule."
   - **2 redacted.** `redact.p` high, `[ACCOUNT]`/`[PHONE]` masked: "model decides *whether*, code decides *what*."
   - **3 human review.** `redact.p` in 0.5-0.7 → `202`, Nova's two-sentence summary: "Bedrock only runs here."
2. Show the trace: `aws logs tail /aws/lambda/decide-in-code-guard --since 5m | grep circuit_decision`.
3. **Live change**, in `lambda/circuit.py`, at the bottom:
   ```python
   c.noul("angry", "Is the customer angry?")
   c.gate("angry_to_human", Q("angry") >= 0.7, on_uncertain="escalate")
   REVIEW_WHEN_TRUE: list[str] = ["angry_to_human"]
   ```
   `scripts/deploy.sh` (tests, then `terraform apply`, ~10 s), then:
   `scripts/demo.sh "This is the THIRD time you've double charged me. Fix it today or I'm cancelling."` → `202`, reason `angry_to_human`.
   Line to say: "Three lines. No prompt changed, no model retrained. The policy is code."

If it breaks: `503` means the model went cold, so run `scripts/warmup.sh` and talk over the band slide. No network means
the recorded run. **Record one tonight** (screen capture of the full demo) and keep it on the desktop.

## Likely questions

- **"Why not just ask an LLM for JSON / read its logprobs?"** You can approximate it (the library even has a
  logprobs backend), but a chat model wasn't trained so its probabilities are calibrated, and you're still
  generating. System One models are trained for exactly this.
- **"Does customer data leave AWS?"** With the hosted model, yes. Path 3 (open weights on SageMaker) keeps it
  in the account; the demo switches with one Terraform value.
- **"How do you pick 0.6 and the band?"** Start conservative, run real traffic through `probe`, look at where
  wrong answers cluster, move the numbers. They're code, so they're reviewed and versioned like code.
- **"What does the reviewer see?"** The raw message, every gate's probability and trace, and Nova's summary, in
  an encrypted SQS queue. CloudWatch never gets the message text.
- **"Cost?"** One small-model call per message. Bedrock runs only for the uncertain slice.

## Numbers on slides I couldn't re-check from here

Slides 8 (0.5-0.97 on undecidable items) and 10 (the accuracy table) cite decisioncircuits.com, which I
couldn't reach while preparing. Slide 6's launch date and latency match TypeSafe's launch coverage. Re-read
the scoreboard tonight so you can defend the numbers if asked.
