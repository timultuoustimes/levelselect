import {
  keepRequestedCategories,
  matchKey,
  MAX_REQUESTED_CATEGORIES,
  parseRequestedCategories,
  scopeInstructions,
} from './tracker-scope.ts';

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(actual: unknown, expected: unknown, message: string) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${message}\n  expected ${e}\n  actual   ${a}`);
}

// Every request from a build that predates the field arrives without it. Those
// must be unscoped — the whole game, exactly as before this change.
Deno.test('a request without categories is unscoped, so older builds behave as before', () => {
  assertEquals(parseRequestedCategories(undefined), null, 'a missing field must not scope');
  assertEquals(parseRequestedCategories([]), null, 'an empty list must not scope');
  assertEquals(parseRequestedCategories('Grubs'), null, 'a non-array must not scope');
  assertEquals(parseRequestedCategories([{ name: '   ' }, { nope: 1 }]), null,
    'entries without a name scope nothing');
});

Deno.test('requested categories are trimmed, de-duplicated and clamped', () => {
  const parsed = parseRequestedCategories([
    { name: '  Warrior Graves ', expectedCount: 7 },
    { name: 'warrior graves' },
    { name: 'Korok Seeds', expectedCount: 900, counted: true },
    { name: 'Grubs', expectedCount: -3 },
    { name: 'Huge', expectedCount: 99_999 },
  ])!;
  assertEquals(parsed.map((c) => c.name), ['Warrior Graves', 'Korok Seeds', 'Grubs', 'Huge'], 'names');
  assertEquals(parsed[0].expectedCount, 7, 'a size is kept');
  assertEquals(parsed[1].counted, true, 'a counter is kept');
  assertEquals(parsed[2].expectedCount, null, 'a nonsense size is dropped');
  assertEquals(parsed[3].expectedCount, 1000, 'a size is clamped');
  const many = parseRequestedCategories(Array.from({ length: 50 }, (_, i) => ({ name: `Set ${i}` })))!;
  assertEquals(many.length, MAX_REQUESTED_CATEGORIES, 'the list is capped');
});

// The bug Tim found: a regeneration came back with lists he never had. The
// prompt asks the model not to; this is what holds it to that regardless.
Deno.test('the answer is held to the list: extras dropped, names restored, order kept, gaps named', () => {
  const requested = parseRequestedCategories([
    { name: 'Warrior Graves' }, { name: 'Grubs' }, { name: 'Endings' },
  ])!;
  const answer = [
    { id: 'charms', name: 'Charms', items: [{ id: 'a', name: 'Grubsong' }] },
    { id: 'grubs', name: 'grubs', items: [{ id: 'g1', name: 'Grub 1' }] },
    { id: 'graves', name: "Warrior's Graves", items: [{ id: 'xero', name: 'Xero' }] },
  ];
  const { categories, missing } = keepRequestedCategories(answer, requested);
  assertEquals(categories.map((c) => c.name), ['Warrior Graves', 'Grubs'],
    'only what was asked for, in the order asked, under the names asked');
  assertEquals(categories.map((c) => c.id), ['warrior-graves', 'grubs'], 'ids follow the requested names');
  assertEquals(missing, ['Endings'], 'the one that did not come back is named');
  assert((categories[0].items as unknown[]).length === 1, 'items survive the reshaping');
});

Deno.test('matching ignores punctuation and case, and nothing else', () => {
  assert(matchKey("Warrior's Graves") === matchKey('warrior graves'), 'apostrophe and case');
  assert(matchKey('Grubs') !== matchKey('Grub Songs'), 'different sets stay different');
});

Deno.test('the scoped prompt names every category and forbids new ones', () => {
  const text = scopeInstructions(parseRequestedCategories([
    { name: 'Warrior Graves', expectedCount: 7 },
    { name: 'Korok Seeds', expectedCount: 900, counted: true },
  ])!);
  assert(text.includes('"Warrior Graves"') && text.includes('"Korok Seeds"'), 'every name is listed');
  assert(text.includes('RUNNING TOTAL'), 'a counter is explained as one');
  assert(text.includes('no others') && text.includes('Do not add'), 'new categories are forbidden');
});
