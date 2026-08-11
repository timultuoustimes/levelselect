import Foundation

/// A small, anonymized legacy blob that exercises every importer path.
/// Committable (no personal data). Mirrors the real shape in
/// native/fixtures/LEGACY-SCHEMA.md.
enum SyntheticFixture {
    static var data: Data { Data(json.utf8) }

    static let json = """
    {
      "version": 5,
      "currentGameId": "g-none",
      "currentSaveId": "s1",
      "lastSavedAt": "2026-06-28T19:54:37.000Z",
      "games": [],
      "library": [
        {
          "id": "g-none", "name": "Test RPG", "status": "completed", "notes": "n",
          "igdbId": 111, "igdbSlug": "test-rpg", "summary": "sum", "coverUrl": "http://x/c.jpg",
          "franchise": "TF", "platforms": ["Switch"], "userTags": ["fav"], "genres": ["RPG"],
          "themes": [], "gameModes": [], "playerPerspectives": [], "developers": ["Dev"], "publishers": ["Pub"],
          "complexity": "high", "coverColor": "#ffffff", "yearPlayed": 2026, "playPeriods": [],
          "trackerType": "None", "coverImageId": "ci", "currentSaveId": "s1", "addedAt": "2026-01-01T00:00:00.000Z",
          "userRating": 5,
          "clears": [{ "id": "c1", "clearedAt": "2026-05-15T03:08:02.354Z" }],
          "saves": [{
            "id": "s1", "name": "Playthrough", "createdAt": "2026-01-01T00:00:00.000Z",
            "lastPlayedAt": "2026-05-15T00:00:00.000Z", "notes": "pn", "rating": 0, "review": "",
            "progressPercent": 100, "totalPlaytime": 5400, "milestones": [], "activeSession": null,
            "sessions": [
              { "id": "ses1", "startTime": "2026-05-14T10:00:00.000Z", "endTime": "2026-05-14T11:00:00.000Z", "duration": 3600, "accumulatedTime": 3600, "pausedAt": null, "manual": false, "notes": "" },
              { "id": "ses2", "startTime": "2026-05-15T10:00:00.000Z", "endTime": "2026-05-15T10:30:00.000Z", "duration": 1800, "accumulatedTime": 1800, "pausedAt": null, "manual": true, "notes": "m" }
            ]
          }]
        },
        {
          "id": "g-obj", "name": "Metroid Test", "status": "playing", "notes": "",
          "igdbId": "222", "igdbSlug": "metroid-test", "summary": "", "coverUrl": "",
          "platforms": ["SNES"], "userTags": [], "genres": [], "themes": [], "gameModes": [],
          "playerPerspectives": [], "developers": [], "publishers": [], "complexity": "", "coverColor": "",
          "yearPlayed": null, "playPeriods": [], "trackerType": "hollow-knight", "coverImageId": "",
          "currentSaveId": "so1", "addedAt": "2026-02-01T00:00:00.000Z", "userRating": 5,
          "structuredData": {
            "schemaVersion": 1, "generatedBy": "claude", "generatedAt": "2026-04-01T00:00:00.000Z",
            "categories": [{ "id": "cat1", "name": "Bosses", "items": [{ "id": "i1", "name": "Boss A", "type": "boolean" }] }],
            "runs": [], "tags": [], "sources": ["http://guide"]
          },
          "maps": [{
            "id": "m1", "name": "World", "type": "world", "imageUrl": "http://x/m.png",
            "storageType": "upload", "storagePath": "maps/m1.png", "addedAt": "2026-02-02T00:00:00.000Z",
            "markers": [{ "id": "mk1", "category": "warning", "label": "Trap", "notes": "", "x": 43.15, "y": 61.36, "createdAt": "2026-02-03T00:00:00.000Z" }]
          }],
          "saves": [{
            "id": "so1", "name": "Playthrough", "createdAt": "2026-02-01T00:00:00.000Z", "lastPlayedAt": null,
            "notes": "", "rating": 0, "review": "", "progressPercent": 10, "totalPlaytime": 0,
            "milestones": [], "activeSession": null, "sessions": [],
            "itemState": { "i1": { "done": true } }
          }]
        },
        {
          "id": "g-run", "name": "Rogue Test", "status": "playing", "notes": "",
          "igdbId": 333, "platforms": ["PC"], "userTags": [], "genres": [], "themes": [], "gameModes": [],
          "playerPerspectives": [], "developers": [], "publishers": [], "complexity": "", "coverColor": "", "playPeriods": [],
          "trackerType": "lone-ruin", "coverImageId": "", "currentSaveId": "sr1", "addedAt": "2026-03-01T00:00:00.000Z",
          "saves": [{
            "id": "sr1", "name": "Playthrough", "createdAt": "2026-03-01T00:00:00.000Z",
            "progressPercent": 0, "totalPlaytime": 0, "milestones": [], "activeSession": null, "sessions": []
          }]
        },
        {
          "id": "g-active", "name": "Active Test", "status": "playing", "notes": "",
          "igdbId": 444, "platforms": [], "userTags": [], "genres": [], "themes": [], "gameModes": [],
          "playerPerspectives": [], "developers": [], "publishers": [], "complexity": "", "coverColor": "", "playPeriods": [],
          "trackerType": "None", "coverImageId": "", "currentSaveId": "sa1", "addedAt": "2026-04-01T00:00:00.000Z",
          "saves": [{
            "id": "sa1", "name": "Playthrough", "createdAt": "2026-04-01T00:00:00.000Z",
            "progressPercent": 0, "totalPlaytime": 120, "rating": 4, "review": "good", "milestones": [],
            "activeSession": { "id": "act1", "startTime": "2026-04-01T12:00:00.000Z", "endTime": null, "duration": 0, "accumulatedTime": 120, "pausedAt": "2026-04-01T12:02:00.000Z", "manual": false, "notes": "" },
            "sessions": [{ "id": "act1", "startTime": "2026-04-01T12:00:00.000Z", "endTime": null, "duration": 0, "accumulatedTime": 120, "pausedAt": "2026-04-01T12:02:00.000Z", "manual": false, "notes": "" }]
          }]
        }
      ]
    }
    """
}
