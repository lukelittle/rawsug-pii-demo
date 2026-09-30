# Decide in code: System One models on AWS

The live demo for the Richmond AWS User Group talk (Oct 1): a PII-and-routing guard for support
messages. A small model answers typed questions with calibrated probabilities, and plain code
(a *decision circuit*) makes the decision.

```
            SigV4                     one System One request
 client ──► API Gateway ──► Lambda ─────────────────────────► circuit-8b (api.decisioncircuits.com)
            POST /messages    │        pii? business? dept?     returns probabilities, not prose
                              │
                              ├─ every gate decided ──► 200: redacted / routed, full trace to CloudWatch
                              │
                              └─ any gate uncertain ──► Claude Haiku 4.5 on Bedrock (2-sentence note)
                                                        └► SQS "human-review" queue ──► 202
```

## The circuit

The whole decision lives in [`lambda/circuit.py`](lambda/circuit.py):

| | | |
|---|---|---|
| `noul pii` | question | contains personal info about a private individual? |
| `noul business` | question | identifying details are about a business, not a person? |
| `choice dept` | question | billing / technical / other |
| `redact` | gate | `(pii & ~business) >= 0.6`, band 0.1, **escalate** when uncertain |
| `route` | gate | `argmax(dept)`, `min_confidence 0.35` |

Rules in [`lambda/decide.py`](lambda/decide.py):
- **Every gate decided:** the message is routed to `dept`. If `redact` is True, deterministic
  patterns mask the account/card numbers, emails, phones and SSNs ([`lambda/redact.py`](lambda/redact.py)).
  The model decides *whether* to redact, and code decides *what*. If the model says PII but no
  pattern matches, the whole body is withheld.
- **Any gate uncertain** (escalate/abstain), or a gate listed in `REVIEW_WHEN_TRUE` fires: the
  message goes to the `human-review` SQS queue with a 2-sentence Claude summary for the reviewer.
- **Model unreachable:** 503. Nothing is routed, redacted or queued without the model's answers.

Nothing here generates text to classify. The only generated text is the reviewer summary, and
it's advice attached to a decision the circuit already made.

## Prerequisites

- An AWS account and admin-ish credentials in your shell (`aws sts get-caller-identity` works)
- Terraform ≥ 1.7, AWS CLI v2 ≥ 2.9, curl ≥ 7.75, jq, and Python 3 with pip (to build the layer)
- A circuit API key from [decisioncircuits.com](https://decisioncircuits.com/#api)
- **Bedrock, once per account:** Anthropic models need the first-use form. Then make one call
  as yourself, which also accepts the Marketplace offer, so the Lambda role doesn't need
  Marketplace permissions:
  ```bash
  aws bedrock-runtime converse --region us-east-1 \
    --model-id us.anthropic.claude-haiku-4-5-20251001-v1:0 \
    --messages '[{"role":"user","content":[{"text":"hi"}]}]'
  ```

## Deploy

```bash
scripts/build-layer.sh                         # deps layer (decision-circuits + anthropic), once
terraform -chdir=terraform init
terraform -chdir=terraform apply

# The API key goes straight into Secrets Manager. It never touches Terraform variables or state.
read -rs CIRCUIT_KEY && aws secretsmanager put-secret-value --region us-east-1 \
  --secret-id "$(terraform -chdir=terraform output -raw api_key_secret_id)" \
  --secret-string "$CIRCUIT_KEY"; unset CIRCUIT_KEY

scripts/warmup.sh                              # first call wakes the model: ~1 min
```

## Demo

```bash
scripts/warmup.sh --keep-warm    # separate terminal, start before you go on; pings every 4 min
scripts/demo.sh                  # 1. routed  2. redacted + routed  3. human review
scripts/demo.sh "any text"       # one custom message
scripts/probe.sh "any text"      # every probability, no side effects (for rehearsing)
```

Why warmup invokes the Lambda directly: the hosted model scales to zero, and API Gateway gives up
after 30s. A direct invoke can wait out the minute. API calls fail fast with a 503 and a hint
instead of hanging.

**Rehearse message 3 tonight.** Whether a message lands in the uncertain band depends on the real
model's probabilities, and I couldn't call it while building this. Run `scripts/probe.sh` on
the borderline text in `demo.sh`. If `would.status` isn't `human_review`, try these candidates
and paste the winner into `demo.sh`:
- `My landlord Dave keeps saying the payment for unit 4B never went through, can you check whose card that was?`
- `Can you tell me which email is on file for my husband's account? He asked me to check.`
- `I think someone at my office used my login. Her name is Priya, can you see what she changed?`

Show what happened:

```bash
# The decision trace (answers, gate probabilities, gate traces) for each request
aws logs tail /aws/lambda/decide-in-code-guard --since 10m --format short | grep circuit_decision

# The human-review queue, with the Claude summary
aws sqs receive-message --queue-url "$(terraform -chdir=terraform output -raw review_queue_url)" \
  --max-number-of-messages 5 --query 'Messages[].Body' --output text | jq .
```

Logs Insights query for the talk:

```
fields @timestamp, status, department, redacted, gates.redact.p, gates.route.p, latency_ms
| filter event = "circuit_decision"
| sort @timestamp desc
```

CloudWatch gets the trace and the redacted text, never the raw message, which is logged only as
a sha256. The raw text goes only to the encrypted review queue, where the reviewer needs it.

## Live-coding: "angry customer"

Add these three lines in `lambda/circuit.py`, then redeploy:

```python
c.noul("angry", "Is the customer angry?")
c.gate("angry_to_human", Q("angry") >= 0.7, on_uncertain="escalate")
REVIEW_WHEN_TRUE: list[str] = ["angry_to_human"]     # replaces the empty list
```

```bash
scripts/deploy.sh      # re-zips lambda/ (a few KB) and applies; about 10 seconds
scripts/demo.sh "This is the THIRD time you've double charged me. Fix it today or I'm cancelling."
```

`tests/test_circuit.py::test_stage_change_angry_customer` runs the same change offline.
If an angry message comes back uncertain (p near 0.7), it escalates too. The band did its job.

## Swapping the model

One Terraform value, `model_endpoint` (in `terraform/variables.tf`, or override it in a `.tfvars`):

```hcl
model_endpoint = { url = "https://api.typesafe.ai/v1/systemone", model = "jev-latest" } # Jev: put its key in the same secret
model_endpoint = { url = "sagemaker://my-circuit-endpoint",      model = "circuit-8b" } # SageMaker: IAM auth, no key
```

The IAM policy follows the choice. A `sagemaker://` endpoint gets `sagemaker:InvokeEndpoint`
on that endpoint and loses the secret read.

## Security posture

- API route requires **IAM (SigV4)** auth, and the stage is throttled (5 rps, burst 10).
- Lambda role: logs on its own group, `GetSecretValue` on one secret, `SendMessage` on one
  queue, `bedrock:InvokeModel` on one inference profile (and its base model only *via* that
  profile), KMS only via Secrets Manager/SQS. The one `*` is X-Ray, which has no resource-level
  permissions. `terraform test` asserts this.
- One customer-managed KMS key (rotation on) encrypts the secret, the queue and both log groups.
- Everything is tagged `project=decide-in-code` (provider `default_tags`).

## Checks

```bash
pip install -r requirements-dev.txt && pytest          # circuit + redaction, offline
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
terraform -chdir=terraform test                        # mocked providers, no AWS needed
checkov -d terraform --framework terraform             # 0 failed; each skip has its reason inline
```

## Teardown

```bash
terraform -chdir=terraform destroy
```

The secret is deleted immediately (no recovery window), so you can redeploy the same day. The KMS key
waits the 7-day minimum before deletion, and CloudWatch log groups go with the stack.
