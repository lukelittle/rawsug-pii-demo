# Speaker notes: Decide in code (45 min)

Exported from the deck's speaker notes. The same text appears under each slide in PowerPoint (View → Notes, or Presenter View).

## Slide 1: Decide in code.

[0:00 · 30 sec]
DO: Have this slide up while people sit down. scripts/warmup.sh --keep-warm is already running in a hidden terminal; the GUI is open in another window.
SAY: "Hi everyone, thanks for coming. Tonight is about a new kind of AI model that showed up about two weeks ago, why it matters for almost anything you build with AI, and how to run one on AWS today, even though it isn't in Bedrock. We'll finish with a live demo on AWS, and I'll change its logic live on stage."
NEXT: "Quick intro first."

## Slide 2: Hi, I'm Lucas

[0:30 · 30 sec]
SAY: "I'm Lucas. I lead Intelligent Data and Cloud at Ippon, which mostly means helping teams ship AI without giving their compliance department a heart attack. Snipe me about AWS, Bedrock, Minecraft or plant YouTubers. Denied topics are on the slide."
SAY: "The QR code is my LinkedIn. Scan it now or at the end; I'll share the repo and slides there."
DO: Pause two seconds for phones, then move on. Keep this under 30 seconds.
NEXT: "So, a confession about how we use AI in production."

## Slide 3: We keep hiring a novelist to answer yes-or-no questions.

[1:00 · 1 min]
DO: Ask for hands.
SAY: "Show of hands: who has a regex or a JSON parser wrapped around an LLM response in production? Keep your hand up if it has broken at least once."
DO: Let the laugh happen.
SAY: "That's the smell this talk is about. We use a model built to write, a novelist, and then we spend engineering time forcing its writing back into a single bit: yes or no, this team or that team. Tonight is about a kind of model that skips the writing entirely."
NEXT: "Let me show you how common this is."

## Slide 4: Most AI calls are decisions in disguise

[2:00 · 1.5 min]
SAY: "Here are four calls I see in almost every AI project." DO: Point at each card.
SAY: "Is this spam? Yes or no. Which team gets this ticket? One of N. Is this agent's tool call safe? Allow, block, or ask a human. Does this contain PII? A probability."
SAY: "Notice what they have in common: you knew every possible answer before you ever called the model. So you don't need the model to write an answer. You need it to tell you which answer, and how sure it is."
NEXT: "There's now a kind of model built for exactly that. Here's what talking to one looks like."

## Slide 5: A System One model answers typed questions

[3:30 · 2 min]
DO: Point left box, then right box. Go slowly.
SAY: "On the left is the whole request. Two things. The state: whatever you're deciding about, here a sentence with a name and an account number. And the questions: typed questions you write in plain English. This one is a 'noul', their name for a yes/no question. There's also 'choice', pick one from a list, and 'score', a level on a scale."
SAY: "On the right is the whole response. Not 'yes', not a paragraph. A number: 0.814 that this contains PII."
SAY: "Nothing comes back that you didn't ask for. So there's nothing to parse, nothing to validate against a schema. One pass, and the answer space was fixed before the model ran."
NEXT: "Why is it called System One? This is the slide that makes the rest of the talk make sense."

## Slide 6: Why “System One”?

[5:30 · 2.5 min] THE KEY SLIDE. Slow down.
SAY: "The name comes from Daniel Kahneman's book Thinking, Fast and Slow. Your brain has two modes. System 2 is slow and deliberate: work out 17 times 24 in your head. System 1 is the snap judgment: you see a face and just know it's angry. You don't reason it out."
DO: Point top-left. SAY: "A chat model writing an answer word by word is doing System 2, even for a yes/no question."
DO: Point top-right. SAY: "A System One model is built for the snap judgment. It reads your data and your questions once, and scores every allowed answer at the same time."
DO: Point bottom-left. SAY: "How? I'll use circuit-8b, because it's open and we can look inside. It's an ordinary 8-billion-parameter language model with one small extra layer on top that scores each allowed answer. In a moment I'll open both kinds of model up."
DO: Point bottom-right. SAY: "And why is the number worth anything? It's trained against real outcomes, so it's calibrated: across everything it said 0.8 about, it's right about 80% of the time. That's what lets you put a threshold on it in code."
IF ASKED "isn't that just a classifier?": "Yes, in spirit. The difference is that you define the classes per request, in plain English, with no training run."
NEXT: "First, how a normal LLM answers a question."

## Slide 7: How an LLM answers “is this spam?”

[8:00 · 1.5 min]
SAY: "To see why that's different, here's how a normal LLM answers 'is this spam?'"
DO: Walk the five cards left to right.
SAY: "It breaks your prompt into tokens, turns each one into a vector of numbers, and runs them through a stack of transformer layers, thirty to eighty of them, so every token can look at the others. Then the last layer scores every token in its vocabulary, a hundred thousand or more, to pick the next word."
DO: Point at the blue bars. SAY: "That's one step. It picks a token, sticks it on the end of the input, and runs the whole stack again. Once per word."
DO: Point at the dark card. SAY: "So to answer a yes/no question, it writes a sentence. Then your code goes looking for the word 'spam' in that sentence."
NEXT: "Now the same question, System One style."

## Slide 8: How a System One model answers it

[9:30 · 1.5 min]
SAY: "Same question. Look at how much stays the same."
DO: Point at cards 1 to 3. SAY: "Tokenize, embed, the transformer layers: the same kind of machinery. circuit-8b's body literally is an 8-billion-parameter language model. Two differences: the input includes the question and its allowed answers, and the stack runs once."
DO: Point at card 4. SAY: "Here's the change. Instead of scoring the whole vocabulary to pick a next word, a small decision head scores only the answers you allowed. Spam, not spam."
DO: Point at card 5 and the bars. SAY: "A softmax turns those scores into probabilities that add up to one. 0.92 spam. Done. Nothing generated, no loop."
DO: Point at the dark card. SAY: "You get numbers back, not prose. Your code compares 0.92 to a threshold and decides. Same body, different head. That's really the whole idea."
IF ASKED about Jev: "Jev's internals aren't public. TypeSafe describes a parallel sampler and a training method they call RLCD. circuit-8b's design is published, which is why I'm using it to explain."
NEXT: "Side by side."

## Slide 9: Same engine, different job

[11:00 · 1 min]
DO: Read across the rows quickly; don't read every cell.
SAY: "Same engine, different job. An LLM produces text, one pass per token, scoring the whole vocabulary, trained to predict the next token. Great for writing and open-ended work."
SAY: "A System One model produces a probability per allowed answer, one pass for everything, trained against real outcomes so the numbers are calibrated. Great for classify, route, flag, gate."
DO: Point at the last row. SAY: "And each has a catch. The LLM drifts out of format and you pay per token. The System One model needs you to know the answers up front, and, as we'll see in a few minutes, a valid answer isn't necessarily a correct one."
SAY: "So use both. The demo does exactly that: System One decides, and Bedrock only writes a note when a human needs one."
NEXT: "Let me zoom into one real call."

## Slide 10: Inside one System One call

[12:00 · 1 min]
DO: Keep this one quick; slides 7–9 did the heavy lifting. Walk the four steps, then point at the dark card.
SAY: "Here's what that decision head looks like in circuit-8b specifically."
SAY: "Step one, pack: the data, every question and every allowed answer go in as one input. One call answers all the questions."
SAY: "Step two, mark: each allowed answer gets wrapped in special marker tokens, and the input ends with a 'decide' token. Think of the markers as slots the model fills with a score."
SAY: "Step three, read once: one forward pass. It reads your input the way an LLM reads your prompt, but it never starts writing. That's where the speed comes from. An LLM spends most of its time generating tokens one after another; this skips that completely."
SAY: "Step four, score: a small layer scores each marker against 'decide', and a softmax turns those scores into probabilities that add up to one."
DO: Point at the bars. SAY: "So 'I was charged twice, please refund one' comes back billing 0.93, technical 0.05, other 0.02. Your code reads 0.93 and routes it. An LLM would have to write the word 'billing', and you'd hope it spelled it the way your router expects."
NOTE (if asked): these numbers are illustrative; the demo shows real ones. This is circuit-8b's published design; Jev's internals aren't public. TypeSafe describes a 'parallel sampler' and a training method they call RLCD.
NEXT: "This idea hit the market two weeks ago."

## Slide 11: Jev put the idea on the market

[13:00 · 1 min]
SAY: "On September 15th TypeSafe launched Jev and coined the term 'System One model'. 70 to 500 milliseconds per call, end to end, by their numbers. Zero words of prose: labels, scores and probabilities."
SAY: "I'll be honest about maturity: it's two weeks old, early access, and the benchmarks are the vendor's own. The architecture idea is the thing to take home, whoever's model you use."
NEXT: "So why should an architect care?"

## Slide 12: Why it belongs in your architecture

[14:00 · 1 min]
DO: One card at a time.
SAY: "Fast and cheap: one pass, no generation, hundreds of milliseconds."
SAY: "Always parseable: it can't answer outside the questions you defined. No regex over prose."
SAY: "Honest about doubt: every answer has a probability you can put a threshold on. We'll use that in a few minutes."
SAY: "And auditable. For the financial-services folks in the room: a model risk reviewer can read 'p = 0.81, threshold 0.6, decided' far more easily than a paragraph of chain-of-thought."
NEXT: "So far this sounds perfect. It isn't."

## Slide 13: Valid isn't correct.

[15:00 · 2 min] THE PIVOT. Slow down, let it land.
SAY: "Valid isn't correct. A schema guarantees the shape of an answer, not the truth of it. A System One model can say 0.9 about something it has no business being sure of, and that answer passes every validation check you have."
SAY: "The scoreboard number: on test items deliberately built to be undecidable, every model measured, Jev included, still answered with average confidence between 0.5 and 0.97. Calibrated on average does not mean right on this item."
SAY: "So the model shouldn't be the one making the decision. It should answer questions, and your code should decide, with an explicit way to say 'I'm not sure, send this to a person.' That's the rest of the talk."
NEXT: "But first, the AWS question everyone's thinking: can I get this in Bedrock?"

## Slide 14: It's not in Bedrock. Now what?

[17:00 · 2 min]
SAY: "Not yet. As of late September, Jev isn't in the Bedrock catalog and AWS hasn't announced anything. So there are three ways in."
DO: Walk the rows. SAY: "One: call TypeSafe's API directly. Easy, but data leaves your account. Two: a drop-in clone, circuit-8b, hosted, speaking the exact same API. Swapping between them is one URL. Three: own the weights. Run circuit-1.7b or 8b from Hugging Face on SageMaker or ECS, and the data never leaves your account. That's the answer for regulated shops."
SAY: "Whichever door you pick, the AWS pattern is the same: the model sits next to Bedrock, not instead of it. Key in Secrets Manager, a Lambda wrapper, thresholds before anything consequential."
NEXT: "Are the open clones any good?"

## Slide 15: The open clones hold their own

[19:00 · 1.5 min]
SAY: "Surprisingly good. These are the author's reported numbers." DO: Point at the table.
SAY: "On spam and on 151 intents, the circuit models hold their own. Be fair about the footnote: the circuit models trained on the public spam and intent data, and Jev presumably didn't. The utility-calls column is the cleaner comparison, and Jev still leads it."
SAY: "The point isn't that the clone beats Jev. It's that a model you can host yourself is close enough to be a real option. circuit-1.7b was trained in 61 minutes on one gaming GPU, and the weights are public. These are James Barney's models; I'll give him proper credit in a minute."
NEXT: "Now, how do you make the model answer while your code decides?"

## Slide 16: Decision circuits: the model answers, code decides

[20:30 · 3 min]
DO: Point at the code, line by line.
SAY: "This is decision-circuits, James Barney's open-source library. Three ideas."
SAY: "Questions: you ask them, and the model answers with probabilities. It never sees the rules."
SAY: "Gates: thresholds, AND, OR, NOT, votes, written in plain code. This one says redact if the probability of PII is at least 0.6, with a band of 0.1, and escalate if it's uncertain."
SAY: "Traces: every decision keeps its probability, its outcome and the path that produced it."
SAY: "Same idea as a policy engine: the model supplies evidence, your code applies policy. Because the threshold lives in code, you change it in a pull request, not by retraining or re-prompting."
NOTE: the demo's redact gate is one step richer: it also asks 'are the details about a business, not a person?' and redacts on (pii AND NOT business) >= 0.6. AND is just multiplying the two probabilities.
NEXT: "And that 'band' is the most important number on this slide."

## Slide 17: The band is where people come back in

[23:30 · 2 min]
DO: Point at the line, then the shaded box, then each dot.
SAY: "Threshold 0.6, band 0.1. Clearly above 0.7: decided, redact. Clearly below 0.5: decided, don't redact. Anything between 0.5 and 0.7, the circuit refuses to guess. It escalates to a human."
SAY: "So 0.81 is decided. 0.65 is in the band, so a person looks at it."
SAY: "Compare that with the usual trick of asking two LLMs and escalating when they disagree. Disagreement was a stand-in for a confidence number we didn't have. Now we have the number, so the human-in-the-loop rule is one line of code you can tune."
NEXT: "Before the demo, I owe someone a thank-you."

## Slide 18: Thank you, James Barney

[25:30 · 1 min]
SAY: "Everything you're about to see runs on work by James Barney, and he built it in the open."
DO: One card at a time.
SAY: "The circuit models: open-weights System One models, plus the code that trains them. decision-circuits: the library behind every question, gate and band in tonight's demo. And the hosted API at decisioncircuits.com: that's the model answering every message you're about to see. He let us use it for tonight, so thank you, James."
SAY: "If any of this is useful to you: star the repos, grab a free key, and tell him Richmond says thanks."
DO: Lead a quick round of applause if the room is up for it.
NEXT: "Here's what we built on top of it."

## Slide 19: Tonight's demo: a PII and routing guard

[26:30 · 1.5 min]
DO: Walk the diagram left to right.
SAY: "A client calls API Gateway. The route requires IAM-signed requests, so nobody who sees the URL on a slide can hit it. API Gateway invokes a Lambda that runs the circuit. The Lambda reads the model's API key from Secrets Manager and asks circuit-8b its questions: is there personal info, is it about a business, which team. Probabilities come back."
SAY: "If every gate decides, the message is redacted or routed and the full trace goes to CloudWatch. If any gate is uncertain, the message goes to an SQS human-review queue, and Bedrock, Amazon Nova here, writes a two-sentence note for the reviewer."
SAY: "Two things to notice. The only thing outside AWS is the model call, and swapping it for Jev or a SageMaker endpoint is one Terraform value. And Bedrock only runs on the uncertain slice, so the generative model does the one job that actually needs language. It never makes the decision. All of it is in Terraform, tagged, with least-privilege IAM."
NEXT: "Here's the full picture." (or skip slide 20 and go straight to the demo)

## Slide 20: Full architecture diagram (optional)

[28:00 · 1 min] OPTIONAL: skip it if you're running behind; the previous slide told the story.
SAY: "Here's the full picture, exactly what Terraform deploys. Two ways in on the left: the page you're about to see is served from CloudFront and S3, and it gets short-lived guest credentials from Cognito that can do exactly one thing, call POST /messages. Or my laptop signs the request with my own AWS credentials."
DO: Point at the dashed orange box top right. SAY: "The only thing outside AWS is the model itself, James's circuit-8b. Everything inside the dashed frame is one Terraform stack: tagged, least-privilege, one KMS key encrypting the secret, the queue and the logs."
SAY: "And notice the two exits from the Lambda: decided goes straight back with a trace; uncertain goes to Nova and then a human."
NEXT: "Enough boxes. Let's run it."

## Slide 21: terraform apply

[29:00 · 11 min, or 28:00 if you skipped slide 20] LIVE DEMO
BEFORE THE TALK: stack deployed; scripts/preflight.sh all "ok" 30 min before; scripts/warmup.sh --keep-warm running; the GUI open in the browser (scripts/gui.sh, or the AWS-hosted page), full screen, zoom about 125%; lambda/circuit.py open in the editor; a big-font terminal open in the repo.
DO: Switch to the browser.
1. DO: Click "Routine billing", then Send.
   SAY: "A routine question. Verdict: routed to billing. Look left: the model said PII 0.02. Look right: the code held that against 0.6 and decided. The model never saw that rule."
2. DO: Click "Account number", then Send.
   SAY: "This one has an account number, an SSN and a phone number, and says it's a personal account. PII is high, 'about a business' is low, so the redact dot lands right of the band: decided, redact. And look at what the support team sees: [ACCOUNT], [SSN], [PHONE]. The model decided whether to redact; plain code decided which characters."
3. DO: Click "Borderline", then Send.
   SAY: "Now a hard one: someone asking which email is on file for their husband's account. Is that personal info about a private individual? The model isn't sure. Look at the dot: it's inside the shaded band. That's the band slide, live. The circuit didn't guess. It sent this to a human, and only now did Bedrock run, to write this note for the reviewer." DO: Read Nova's note aloud. Point at the queue counter going up.
4. LIVE CHANGE. DO: Switch to the editor, lambda/circuit.py, scroll to the bottom. Type:
     c.noul("angry", "Is the customer angry?")
     c.gate("angry_to_human", Q("angry") >= 0.7, on_uncertain="escalate")
   and change the last line to: REVIEW_WHEN_TRUE: list[str] = ["angry_to_human"]
   SAY while typing: "New requirement from the business: angry customers go to a human. One question for the model. One gate in code. One line saying this gate means human review."
   DO: In the terminal: scripts/deploy.sh. SAY while it runs (~10 s): "That runs the tests and then terraform apply. Only the function code changes, a few kilobytes."
   DO: Back to the browser. Click "Angry customer", then Send.
   SAY: "Human review, because of angry_to_human. Look: a new question on the left, a new gate on the right with its 0.7 threshold, and I didn't touch the page. Three lines. No prompt changed, no model retrained, no UI changed. The policy is code."
IF IT BREAKS: a 503 or "model cold" means the model went to sleep. Run scripts/warmup.sh in the terminal and talk over it: "This is the scale-to-zero cold start I warned you about; give it a minute." No network: play the recorded run. The terminal version, scripts/demo.sh --step, does the same thing if the browser misbehaves.
NEXT: "So, three things to take home."

## Slide 22: Three things to take home

[40:00 · 1.5 min, then Q&A to 45:00]
SAY: "One: find the decisions hiding in your LLM calls. If you know the possible answers up front, you probably don't need a model to write one."
SAY: "Two: let the model answer questions and let code decide, with a band that sends the uncertain cases to a person."
SAY: "Three: don't wait for Bedrock. Vendor API, drop-in clone, or your own weights on SageMaker. The pattern on AWS is the same."
SAY: "Thanks again to James Barney for the models, the library and the API. decisioncircuits.com has free keys if you want to try this tonight. The repo with everything you saw, Terraform included, is on my LinkedIn. Questions?"
LIKELY QUESTIONS (details in talk/RUN_OF_SHOW.md):
- Why not an LLM with JSON or logprobs? You can approximate it, but chat models aren't trained so their probabilities are calibrated, and you're still generating text.
- Does data leave AWS? With the hosted model, yes. Path 3, open weights on SageMaker, keeps it in your account; here that's one Terraform value.
- How do you pick 0.6 and the band? Start conservative, run real traffic, look at where the mistakes cluster, then adjust. They're code, so they're reviewed and versioned like code.
- Cost? One small-model call per message; Bedrock only on the uncertain slice. This whole demo costs about a dollar a month to leave running.
AFTER: terraform -chdir=terraform destroy when you're done with it.
