#!/usr/bin/env python3
"""Wikidata's video game genres, as a curation candidate list.

**A development tool, not shipped code.** Stage 2's vocabulary is a hand
curated file (`SuggestedTags.json`); this exists to check that curation
against a source with provenance, and to re-check it later without
re-remembering the query. Nothing here runs in the app and nothing it writes
is loaded at runtime.

Why Wikidata rather than Steam: its structured data is explicitly CC0, while
Steam's tag taxonomy is user-contributed under a licence that grants Valve
usage rights and says nothing about anyone repackaging the compilation.
Individual terms like "Metroidvania" are factual terminology either way; the
curated *set* is the part worth being careful about.

Usage:
    python3 scripts/wikidata-genres.py            # compare against the shipped file
    python3 scripts/wikidata-genres.py --dump     # print every candidate

The User-Agent is required by Wikimedia policy. No key, no account, no token —
which is exactly why Wikidata cleared the bar for this project.
"""

import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

UA = "LevelSelect-dev/0.1 (https://levelselect.app; wikimedia@timrmiller.com)"
ENDPOINT = "https://query.wikidata.org/sparql"
SHIPPED = Path(__file__).resolve().parents[1] / (
    "native/LevelSelect/LevelSelect/Resources/SuggestedTags.json")

# Q659563 is "video game genre". Anything that is one, or is a subclass of one.
QUERY = """
SELECT DISTINCT ?genre ?genreLabel ?altLabel WHERE {
  { ?genre wdt:P31 wd:Q659563 } UNION { ?genre wdt:P279 wd:Q659563 }
  OPTIONAL { ?genre skos:altLabel ?altLabel FILTER(LANG(?altLabel) = "en") }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
"""


def fetch():
    url = ENDPOINT + "?" + urllib.parse.urlencode({"query": QUERY, "format": "json"})
    request = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(request, timeout=90) as response:
        return json.load(response)


def candidates():
    """Genre label -> its English aliases, QID kept for the audit trail."""
    found = {}
    for row in fetch()["results"]["bindings"]:
        label = row.get("genreLabel", {}).get("value", "")
        qid = row["genre"]["value"].rsplit("/", 1)[-1]
        # An entity with no English label comes back AS its Q-number. That is
        # not a word anybody would tag a game with.
        if not label or label == qid:
            continue
        entry = found.setdefault(label, {"qid": qid, "aliases": set()})
        if alias := row.get("altLabel", {}).get("value"):
            entry["aliases"].add(alias)
    return found


def main():
    found = candidates()
    print(f"Wikidata offers {len(found)} named video game genres.\n")

    if "--dump" in sys.argv:
        for label in sorted(found):
            aliases = ", ".join(sorted(found[label]["aliases"]))
            print(f"  {label:38} {found[label]['qid']:10} {aliases}")
        return

    shipped = json.loads(SHIPPED.read_text())["tags"]
    ours = {t["name"] for t in shipped}
    # Match on aliases too — "Souls-like" here is "Soulslike" there.
    theirs = {}
    for label, entry in found.items():
        for term in {label} | entry["aliases"]:
            theirs[term.lower()] = label

    confirmed = sorted(n for n in ours if n.lower() in theirs)
    unconfirmed = sorted(n for n in ours if n.lower() not in theirs)

    print(f"CONFIRMED by Wikidata ({len(confirmed)}/{len(ours)}):")
    for name in confirmed:
        print(f"  {name}  →  {theirs[name.lower()]}")
    print(f"\nNOT in Wikidata ({len(unconfirmed)}):")
    for name in unconfirmed:
        print(f"  {name}")
    print("\nMatching is EXACT, on names and aliases only, so this undercounts:"
          "\n\"Farming Sim\" does not match Wikidata's \"farming simulation game\""
          "\neven though they are plainly the same thing. Read the unconfirmed"
          "\nlist as \"worth a look\", never as \"made up\".")
    print("\nUnconfirmed is not wrong. Wikidata's coverage is uneven and its"
          "\nmodelling is inconsistent between entries — a term people use is"
          "\nstill a term people use. This is a cross-check, not an authority.")


if __name__ == "__main__":
    main()
