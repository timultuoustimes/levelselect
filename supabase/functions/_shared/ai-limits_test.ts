import {
  CATEGORY_GLOBAL_DAILY_LIMIT,
  CATEGORY_MAX_TOKENS,
  categoryTokenBudget,
  FULL_GENERATION_GLOBAL_DAILY_LIMIT,
  FULL_GENERATION_MAX_TOKENS,
  quotaPlanForAI,
} from './ai-limits.ts';
import { readBodyWithinLimit } from './guard.ts';

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test('category mode cannot buy more worst-case daily output than full generation', () => {
  assert(
    CATEGORY_MAX_TOKENS * CATEGORY_GLOBAL_DAILY_LIMIT
      <= FULL_GENERATION_MAX_TOKENS * FULL_GENERATION_GLOBAL_DAILY_LIMIT,
    'category daily output ceiling exceeds the full-generation ceiling',
  );
  assert(
    quotaPlanForAI({ mode: 'category' }).quotas.at(-1)?.limit
      === CATEGORY_GLOBAL_DAILY_LIMIT,
    'category requests are not wired to the bounded global quota',
  );
});

Deno.test('maximum category request is clamped to its documented token class', () => {
  const budget = categoryTokenBudget(10_000);
  assert(budget.expectedCount === 400, 'expected count was not clamped');
  assert(budget.maxTokens === CATEGORY_MAX_TOKENS, 'category ceiling was bypassed');
});

Deno.test('body limit does not trust a false small content-length', async () => {
  const request = new Request('https://example.test', {
    method: 'POST',
    headers: { 'content-length': '1' },
    body: JSON.stringify({ mode: 'category', padding: 'x'.repeat(200) }),
  });
  const result = await readBodyWithinLimit(request, 32);
  assert(result.tooLarge, 'stream exceeded the byte limit after a false header');
  assert(result.raw === undefined, 'oversized body was returned for JSON parsing');
});
