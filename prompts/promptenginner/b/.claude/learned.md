# Learned Lessons - Prompt Enhancer V3

## 2025-12-10 14:08 - API max_tokens Error

**What went wrong:**
When user entered a very long prompt (38,533 chars), the API returned error 400:
```
InternalError.Algo.InvalidParameter: Range of max_tokens should be [1, 65536]
```

**Why it happened:**
The code calculated `max_tokens = target_max * 2` without checking API limits.
- For a 38,533 char prompt with "complex" complexity (6.0x ratio)
- target_max = 38,533 * 6.0 = 231,198
- max_tokens = 231,198 * 2 = 462,396
- API maximum is 65,536 tokens

**Correct solution:**
1. Cap max_tokens at API's hard limit: `max_tokens_limit = min(65536, max(8192, target_max * 2))`
2. Remove strict length restrictions from system prompt - changed "MANDATORY" to "FLEXIBLE"
3. Prioritize detail preservation over length targets
4. Updated user message to remove length requirements

**Code changes:**
- Line 130-135: Changed LENGTH CONTROL from MANDATORY to FLEXIBLE
- Line 565: Removed strict length requirement from user message
- Line 573-574: Added `max_tokens_limit = min(65536, max(8192, target_max * 2))`
- Line 589: Changed to use `max_tokens_limit`

**Key insight:**
User wants UNLIMITED length capability to ensure 100% detail preservation. The only limit should be the API's technical maximum (65536 tokens).
