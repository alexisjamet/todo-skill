---
type: llm
weight: 2
---

PASS if the reply says the request was noted, asks the user which payment provider to use (Stripe or Paddle), and does not claim to have chosen one or to have started the integration.
FAIL if the reply picks a provider itself, starts or describes implementing the integration, or does not ask the question.
