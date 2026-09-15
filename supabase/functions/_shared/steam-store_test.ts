import { assertEquals } from 'https://deno.land/std@0.168.0/testing/asserts.ts';
import { shapeSchema, shapeSearch } from './steam-store.ts';

Deno.test('search keeps apps only, with a usable id and name', () => {
  const results = shapeSearch({
    items: [
      { type: 'app', id: 620, name: 'Portal 2' },
      { type: 'sub', id: 7932, name: 'Portal Bundle' },
      { type: 'app', id: 0, name: 'Broken' },
      { type: 'app', id: 400, name: '  ' },
    ],
  });
  assertEquals(results, [{ id: 620, name: 'Portal 2' }]);
});

Deno.test('search answers nothing for a malformed reply', () => {
  assertEquals(shapeSearch(null), []);
  assertEquals(shapeSearch({ items: 'nope' }), []);
});

Deno.test('search stops at the limit', () => {
  const items = Array.from({ length: 30 }, (_, i) => ({ type: 'app', id: i + 1, name: `Game ${i}` }));
  assertEquals(shapeSearch({ items }, 5).length, 5);
});

Deno.test('schema keeps what the app reads and drops the rest', () => {
  const shaped = shapeSchema({
    game: {
      gameName: 'Portal 2',
      gameVersion: '41',
      availableGameStats: {
        stats: [{ name: 'ignored' }],
        achievements: [
          { name: 'ACH.WAKE_UP', defaultvalue: 0, displayName: 'Wake Up Call', hidden: 0,
            description: 'Survive the manual override', icon: 'a.jpg', icongray: 'b.jpg' },
          { name: 'ACH.SECRET', displayName: 'Secret', hidden: 1 },
          { displayName: 'No api name' },
        ],
      },
    },
  });
  assertEquals(shaped, {
    gameName: 'Portal 2',
    achievements: [
      { name: 'ACH.WAKE_UP', displayName: 'Wake Up Call', description: 'Survive the manual override',
        icon: 'a.jpg', icongray: 'b.jpg', hidden: 0 },
      { name: 'ACH.SECRET', displayName: 'Secret', hidden: 1 },
    ],
  });
});

Deno.test('a game without achievements is null, not an empty list', () => {
  assertEquals(shapeSchema({ game: { gameName: 'Tool' } }), null);
  assertEquals(shapeSchema({ game: { availableGameStats: { achievements: [] } } }), null);
  assertEquals(shapeSchema({}), null);
});
