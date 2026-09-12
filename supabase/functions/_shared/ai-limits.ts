import type { QuotaRule } from './guard.ts';

export const PLAN_MAX_TOKENS = 1_500;
export const CATEGORY_MAX_TOKENS = 10_000;
export const FULL_GENERATION_MAX_TOKENS = 12_000;

export const PLAN_GLOBAL_DAILY_LIMIT = 500;
// At the category ceiling this permits 1.5M output tokens/day, below the full
// bucket's 150 × 12k rather than the prior 500 × 10k (5M). The higher
// per-install allowance still makes stepped generation usable.
export const CATEGORY_GLOBAL_DAILY_LIMIT = 150;
export const FULL_GENERATION_GLOBAL_DAILY_LIMIT = 150;

export interface AIQuotaPlan {
  fn: string;
  quotas: QuotaRule[];
}

export function quotaPlanForAI(body: Record<string, unknown>): AIQuotaPlan {
  const mode = typeof body.mode === 'string' ? body.mode : 'auto';
  if (mode === 'plan') {
    return {
      fn: 'ai-plan',
      quotas: [
        { scope: 'install', windowSeconds: 3_600, limit: 20 },
        { scope: 'install', windowSeconds: 86_400, limit: 60 },
        { scope: 'global', windowSeconds: 86_400, limit: PLAN_GLOBAL_DAILY_LIMIT },
      ],
    };
  }
  if (mode === 'category') {
    return {
      fn: 'ai-cat',
      quotas: [
        { scope: 'install', windowSeconds: 3_600, limit: 20 },
        { scope: 'install', windowSeconds: 86_400, limit: 80 },
        { scope: 'global', windowSeconds: 86_400, limit: CATEGORY_GLOBAL_DAILY_LIMIT },
      ],
    };
  }
  return {
    fn: 'ai',
    quotas: [
      { scope: 'install', windowSeconds: 3_600, limit: 10 },
      { scope: 'install', windowSeconds: 86_400, limit: 20 },
      { scope: 'global', windowSeconds: 86_400, limit: FULL_GENERATION_GLOBAL_DAILY_LIMIT },
    ],
  };
}

export function categoryTokenBudget(rawExpectedCount: unknown): {
  expectedCount: number | null;
  maxTokens: number;
} {
  const expectedCount = Number.isFinite(rawExpectedCount)
    ? Math.min(400, Math.max(0, Math.round(Number(rawExpectedCount))))
    : null;
  const perItem = (expectedCount ?? 40) > 60 ? 45 : 90;
  return {
    expectedCount,
    maxTokens: Math.min(
      CATEGORY_MAX_TOKENS,
      Math.max(6_000, 2_000 + (expectedCount ?? 40) * perItem),
    ),
  };
}
