import React, { useState, useRef, useEffect } from 'react';
import {
  ArrowLeft, Home, Play, Star, Clock, Trophy, ChevronDown, ExternalLink,
  Edit2, Check, X, Gamepad2, RefreshCw, Plus, Trash2,
} from 'lucide-react';
import { igdbCoverUrl, igdbGameUrl, fetchIGDBByName, fetchIGDBGame } from '../utils/igdb.js';
import { migratePlayPeriods } from '../utils/factories.js';
import { generateId } from '../utils/format.js';

// ─── Constants ───────────────────────────────────────────────────────────────

const STATUS_COLORS = {
  playing:   'bg-green-500',
  queued:    'bg-cyan-500',
  paused:    'bg-yellow-500',
  completed: 'bg-blue-500',
  backlog:   'bg-gray-500',
  shelved:   'bg-orange-500',
  abandoned: 'bg-red-500',
};

const STATUS_LABELS = {
  playing:   'Playing',
  queued:    'Up Next',
  paused:    'Paused',
  completed: 'Completed',
  backlog:   'Backlog',
  shelved:   'Shelved',
  abandoned: 'Abandoned',
};

// ─── Helpers ─────────────────────────────────────────────────────────────────

function formatDuration(seconds) {
  if (!seconds || seconds < 60) return seconds > 0 ? `${Math.round(seconds)}s` : '—';
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

function getGamePlaytime(game) {
  // Sum all saves
  let total = 0;
  (game.saves || []).forEach(save => {
    if (typeof save.totalPlaytime === 'number') {
      total += save.totalPlaytime;
    } else if (Array.isArray(save.sessions)) {
      total += save.sessions.reduce((acc, s) => acc + (s.duration || 0), 0);
    } else if (Array.isArray(save.runs)) {
      total += save.runs.reduce((acc, r) => acc + (r.duration || 0), 0);
    }
  });
  return total;
}

function getGameRating(game) {
  return game.saves?.[0]?.rating ?? game.userRating ?? null;
}

function getCompletionCount(game) {
  // Count completed saves / runs across all tracker types
  let count = (game.clears || []).length;
  (game.saves || []).forEach(save => {
    if (save.completedAt) count++;
    if (Array.isArray(save.runs)) {
      count += save.runs.filter(r => r.escaped || r.completed || r.won).length;
    }
  });
  return count;
}

// ─── Play History Helpers ─────────────────────────────────────────────────────

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// All platforms that can appear in a play period dropdown
const KNOWN_PLATFORMS = [
  'Switch', 'Switch 2', 'Mac', 'iOS', 'Recalbox',
  'NES', 'SNES', 'N64', 'GameCube', 'Wii', 'Wii U',
  'Game Boy', 'GBA', 'DS', '3DS',
  'Genesis', 'Xbox', 'Xbox 360', 'Xbox One', 'Xbox Series X',
  'PS1', 'PS2', 'PS3', 'PS4', 'PS5', 'PSP', 'PS Vita',
  'PC', 'Steam Deck', 'Android',
];

function formatPeriod(period) {
  const fmt = (m, y) => {
    if (m && y) return `${MONTHS[m - 1]} ${y}`;
    if (y) return String(y);
    if (m) return MONTHS[m - 1];
    return null;
  };
  const start = fmt(period.startMonth, period.startYear);
  const end = period.ongoing ? 'present' : fmt(period.endMonth, period.endYear);
  if (!start && !end) return 'Unknown date';
  if (!end) return start;
  if (!start) return end;
  if (start === end) return start;
  return `${start} – ${end}`;
}

// ─── Tag Input with autocomplete dropdown ────────────────────────────────────

function TagInput({ suggestions = [], onAdd, placeholder = 'Add a tag…' }) {
  const [query, setQuery] = useState('');
  const [open, setOpen] = useState(false);
  const wrapperRef = useRef(null);

  const filtered = query.trim()
    ? suggestions.filter(t => t.toLowerCase().includes(query.toLowerCase()))
    : suggestions;

  useEffect(() => {
    if (!open) return;
    const handler = (e) => {
      if (wrapperRef.current && !wrapperRef.current.contains(e.target)) setOpen(false);
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [open]);

  const commit = (val) => {
    const cleaned = val.trim().replace(/,/g, '');
    if (cleaned) onAdd(cleaned);
    setQuery('');
    setOpen(false);
  };

  return (
    <div ref={wrapperRef} className="relative flex-1">
      <input
        type="text"
        placeholder={placeholder}
        value={query}
        onChange={e => { setQuery(e.target.value); setOpen(true); }}
        onFocus={() => setOpen(true)}
        onKeyDown={e => {
          if (e.key === 'Enter' || e.key === ',') { e.preventDefault(); commit(query); }
          if (e.key === 'Escape') setOpen(false);
        }}
        className="input-field text-sm w-full"
      />
      {open && filtered.length > 0 && (
        <div className="absolute left-0 top-full mt-1 z-50 bg-slate-800 border border-white/10 rounded-xl shadow-2xl overflow-hidden w-full max-h-40 overflow-y-auto">
          {filtered.slice(0, 8).map(tag => (
            <button
              key={tag}
              type="button"
              onMouseDown={e => e.preventDefault()}
              onClick={() => commit(tag)}
              className="w-full text-left px-3 py-2 text-xs hover:bg-white/10 transition-colors text-gray-300 flex items-center gap-1.5"
            >
              <span className="text-purple-400">#</span>{tag}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

// ─── Status Picker ───────────────────────────────────────────────────────────

function StatusPicker({ status, onChange }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="relative">
      <button
        onClick={() => setOpen(o => !o)}
        className={`${STATUS_COLORS[status] || 'bg-gray-500'} text-white text-sm font-medium px-4 py-2 rounded-full flex items-center gap-2`}
      >
        {STATUS_LABELS[status] || status}
        <ChevronDown className="w-4 h-4" />
      </button>
      {open && (
        <div className="absolute left-0 top-full mt-2 z-30 bg-slate-800 border border-white/10 rounded-xl shadow-2xl overflow-hidden min-w-[160px]">
          {Object.entries(STATUS_LABELS).map(([val, label]) => (
            <button
              key={val}
              onClick={() => { onChange(val); setOpen(false); }}
              className={`w-full text-left px-4 py-2.5 text-sm flex items-center gap-3 hover:bg-white/10 transition-colors ${status === val ? 'text-white' : 'text-gray-400'}`}
            >
              <span className={`w-2.5 h-2.5 rounded-full flex-shrink-0 ${STATUS_COLORS[val]}`} />
              {label}
              {status === val && <Check className="w-3.5 h-3.5 ml-auto text-purple-400" />}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

// ─── Star Rating display / interactive ───────────────────────────────────────

function StarRating({ value, onChange, size = 'md', readOnly = false }) {
  const [hover, setHover] = useState(null);
  const sz = size === 'lg' ? 'w-7 h-7' : 'w-5 h-5';
  return (
    <div className="flex gap-1">
      {[1, 2, 3, 4, 5].map(n => (
        <button
          key={n}
          onClick={readOnly ? undefined : () => onChange(n === value ? null : n)}
          onMouseEnter={readOnly ? undefined : () => setHover(n)}
          onMouseLeave={readOnly ? undefined : () => setHover(null)}
          className={readOnly ? '' : 'p-0.5 transition-transform hover:scale-110'}
          disabled={readOnly}
        >
          <Star
            className={`${sz} transition-colors ${
              n <= (hover ?? value ?? 0)
                ? 'fill-yellow-400 text-yellow-400'
                : 'text-gray-600'
            }`}
          />
        </button>
      ))}
    </div>
  );
}

// ─── Saves / Runs selector ───────────────────────────────────────────────────

function SaveSelector({ game, onOpenTracker }) {
  const hasTracker = game.trackerType !== null;
  const saves = game.saves || [];

  if (saves.length === 0) {
    return (
      <button
        onClick={onOpenTracker}
        className="btn-primary w-full gap-2 text-base py-3"
      >
        <Play className="w-5 h-5" />
        {hasTracker ? 'Open Tracker' : 'Start Tracking'}
      </button>
    );
  }

  return (
    <div className="space-y-2">
      {saves.map((save, i) => {
        const playtime = typeof save.totalPlaytime === 'number'
          ? save.totalPlaytime
          : (save.sessions || []).reduce((a, s) => a + (s.duration || 0), 0);
        const progress = save.progressPercent ?? (
          save.milestones?.length > 0
            ? Math.round((save.milestones.filter(m => m.completed).length / save.milestones.length) * 100)
            : null
        );

        return (
          <button
            key={save.id || i}
            onClick={onOpenTracker}
            className="card-hover w-full p-3 text-left flex items-center gap-3"
          >
            <div className="w-10 h-10 rounded-lg bg-purple-900/40 border border-purple-500/20 flex items-center justify-center flex-shrink-0">
              <Gamepad2 className="w-5 h-5 text-purple-400" />
            </div>
            <div className="flex-1 min-w-0">
              <div className="text-sm font-medium truncate">{save.name || `Save ${i + 1}`}</div>
              <div className="text-xs text-gray-500 flex items-center gap-2 mt-0.5">
                {playtime > 0 && (
                  <span className="flex items-center gap-1">
                    <Clock className="w-3 h-3" />
                    {formatDuration(playtime)}
                  </span>
                )}
                {progress !== null && <span>{progress}%</span>}
              </div>
            </div>
            {hasTracker && (
              <div className="text-xs text-purple-400 flex-shrink-0">Open →</div>
            )}
          </button>
        );
      })}
      <button
        onClick={onOpenTracker}
        className="btn-primary w-full gap-2 mt-2"
      >
        <Play className="w-4 h-4" />
        {hasTracker ? 'Open Full Tracker' : 'Track This Game'}
      </button>
    </div>
  );
}

// ─── Main GamePage Component ──────────────────────────────────────────────────

// Must stay in sync with PRESET_PLATFORMS in Library.jsx
const PRESET_PLATFORMS = [
  'Switch', 'Switch 2', 'Mac', 'iOS', 'Recalbox',
  'NES', 'SNES', 'N64', 'GameCube', 'Wii', 'Wii U',
  'Game Boy', 'GBA', 'DS', '3DS',
  'Genesis', 'Xbox', 'Xbox 360',
  'PS1', 'PS2', 'PS3', 'PS4', 'PS5',
  'PC', 'Steam Deck',
];

// ─── Related Games section ───────────────────────────────────────────────────

function RelatedGames({ game, library, onOpenGame }) {
  const others = library.filter(g => g.id !== game.id);

  let relatedGames = [];
  let sectionLabel = null;

  // Priority 1: same franchise (2+ games)
  if (game.franchise) {
    const sameFranchise = others.filter(g => g.franchise === game.franchise);
    if (sameFranchise.length >= 1) {
      relatedGames = sameFranchise;
      sectionLabel = `More from ${game.franchise}`;
    }
  }

  // Priority 2: same developer
  if (!relatedGames.length && game.developers?.length > 0) {
    const sameDev = others.filter(g =>
      g.developers?.some(d => game.developers.includes(d))
    );
    if (sameDev.length >= 1) {
      relatedGames = sameDev;
      sectionLabel = `More from ${game.developers[0]}`;
    }
  }

  // Priority 3: overlapping genres/themes
  if (!relatedGames.length) {
    const gameGenres = new Set([...(game.genres || []), ...(game.themes || [])]);
    if (gameGenres.size > 0) {
      const similar = others.filter(g => {
        const gGenres = [...(g.genres || []), ...(g.themes || [])];
        return gGenres.some(t => gameGenres.has(t));
      });
      if (similar.length >= 1) {
        relatedGames = similar;
        sectionLabel = 'Similar Games';
      }
    }
  }

  if (!relatedGames.length || !sectionLabel) return null;

  const toShow = relatedGames.slice(0, 5);

  return (
    <div className="card p-4">
      <h2 className="text-sm font-medium mb-3">{sectionLabel}</h2>
      <div className="flex gap-3 overflow-x-auto pb-1 scroll-smooth-ios">
        {toShow.map(g => {
          const coverUrl = g.coverImageId
            ? igdbCoverUrl(g.coverImageId, 'cover_big')
            : g.coverUrl || null;
          return (
            <button
              key={g.id}
              onClick={() => onOpenGame(g.id, 'library')}
              className="flex-shrink-0 w-24 text-left group"
            >
              {coverUrl ? (
                <img
                  src={coverUrl}
                  alt={g.name}
                  className="w-24 aspect-[3/4] object-cover rounded-lg shadow-md mb-1.5"
                  onError={e => { e.target.style.display = 'none'; }}
                />
              ) : (
                <div className="w-24 aspect-[3/4] rounded-lg bg-purple-900/40 border border-purple-500/20 flex items-center justify-center mb-1.5">
                  <span className="text-2xl opacity-40">🎮</span>
                </div>
              )}
              <p className="text-xs text-gray-300 group-hover:text-purple-300 line-clamp-2 leading-tight transition-colors">
                {g.name}
              </p>
            </button>
          );
        })}
      </div>
    </div>
  );
}

export default function GamePage({ game, library, navSource = 'library', onBack, onGoHome, onGoLibrary, onOpenTracker, onUpdateGame, onOpenGame }) {
  const [editingReview, setEditingReview] = useState(false);
  const [reviewDraft, setReviewDraft] = useState('');

  // Play history
  const [playPeriods, setPlayPeriods] = useState(() => migratePlayPeriods(game));
  const [editingPeriodId, setEditingPeriodId] = useState(null);
  // periodDraft: { startMonth, startYear, endMonth, endYear, ongoing, note }
  const [periodDraft, setPeriodDraft] = useState(null);

  // IGDB refresh
  const [igdbFetching, setIgdbFetching] = useState(false);
  const [igdbFetchDone, setIgdbFetchDone] = useState(false);

  // Franchise editing
  const [editingFranchise, setEditingFranchise] = useState(false);
  const [franchiseDraft, setFranchiseDraft] = useState('');

  // Tags — derive all tags from library for autocomplete
  const allLibraryTags = [...new Set((library || []).flatMap(g => g.userTags || []))].sort();
  const allGameTags = game.userTags || [];

  const addTag = (tag) => {
    const val = tag.trim();
    if (!val || allGameTags.includes(val)) return;
    onUpdateGame({ ...game, userTags: [...allGameTags, val] });
  };

  const removeTag = (tag) => {
    onUpdateGame({ ...game, userTags: allGameTags.filter(t => t !== tag) });
  };

  // Franchise editing
  const allLibraryFranchises = [...new Set((library || [])
    .map(g => g.franchise).filter(Boolean))].sort();

  const startEditFranchise = () => {
    setFranchiseDraft(game.franchise || '');
    setEditingFranchise(true);
  };

  const saveFranchise = () => {
    onUpdateGame({ ...game, franchise: franchiseDraft.trim() || null });
    setEditingFranchise(false);
  };

  // Platform editing
  const [editingPlatforms, setEditingPlatforms] = useState(false);
  const [platformDraft, setPlatformDraft] = useState([]);
  const [customPlatformDraft, setCustomPlatformDraft] = useState('');

  const coverUrl = game.coverImageId
    ? igdbCoverUrl(game.coverImageId, 'cover_big')
    : game.coverUrl || null;

  const bigCoverUrl = game.coverImageId
    ? igdbCoverUrl(game.coverImageId, '720p')
    : game.coverUrl || null;

  const totalPlaytime = getGamePlaytime(game);
  const completionCount = getCompletionCount(game);
  const rating = getGameRating(game);
  const save = game.saves?.[0];
  const review = save?.review || game.review || null;

  const handleStatusChange = (newStatus) => {
    onUpdateGame({ ...game, status: newStatus });
  };

  const handleRatingChange = (val) => {
    if (save) {
      onUpdateGame({
        ...game,
        saves: game.saves.map((s, i) => i === 0 ? { ...s, rating: val } : s),
      });
    } else {
      onUpdateGame({ ...game, userRating: val });
    }
  };

  const handleSaveReview = () => {
    if (save) {
      onUpdateGame({
        ...game,
        saves: game.saves.map((s, i) => i === 0 ? { ...s, review: reviewDraft } : s),
      });
    } else {
      onUpdateGame({ ...game, review: reviewDraft });
    }
    setEditingReview(false);
  };

  // ── Play Period handlers ───────────────────────────────────────────────────

  const savePlayPeriods = (updated) => {
    setPlayPeriods(updated);
    // Keep legacy yearPlayed in sync (use earliest start year for compat)
    const firstYear = updated.find(p => p.startYear)?.startYear || null;
    onUpdateGame({ ...game, playPeriods: updated, yearPlayed: firstYear });
  };

  const startAddPeriod = () => {
    // Suggest the game's platform if there's only one, otherwise blank
    const defaultPlatform = game.platforms?.length === 1 ? game.platforms[0] : '';
    const newPeriod = { id: generateId(), startMonth: null, startYear: null, endMonth: null, endYear: null, ongoing: false, platform: defaultPlatform || null, note: '' };
    const updated = [...playPeriods, newPeriod];
    setPlayPeriods(updated);
    setEditingPeriodId(newPeriod.id);
    setPeriodDraft({ startMonth: '', startYear: '', endMonth: '', endYear: '', ongoing: false, platform: defaultPlatform, note: '' });
  };

  const startEditPeriod = (period) => {
    setEditingPeriodId(period.id);
    setPeriodDraft({
      startMonth: period.startMonth ?? '',
      startYear: period.startYear ?? '',
      endMonth: period.endMonth ?? '',
      endYear: period.endYear ?? '',
      ongoing: period.ongoing ?? false,
      platform: period.platform ?? '',
      note: period.note ?? '',
    });
  };

  const savePeriodEdit = () => {
    const d = periodDraft;
    const updated = playPeriods.map(p =>
      p.id === editingPeriodId
        ? {
            ...p,
            startMonth: d.startMonth ? parseInt(d.startMonth, 10) : null,
            startYear: d.startYear ? parseInt(d.startYear, 10) : null,
            endMonth: d.ongoing ? null : (d.endMonth ? parseInt(d.endMonth, 10) : null),
            endYear: d.ongoing ? null : (d.endYear ? parseInt(d.endYear, 10) : null),
            ongoing: !!d.ongoing,
            platform: d.platform || null,
            note: d.note || '',
          }
        : p
    );
    setEditingPeriodId(null);
    setPeriodDraft(null);
    savePlayPeriods(updated);
  };

  const cancelPeriodEdit = () => {
    // If this period was brand-new (no year info and we just added it), remove it
    const period = playPeriods.find(p => p.id === editingPeriodId);
    if (period && !period.startYear && !period.endYear && !period.ongoing) {
      setPlayPeriods(prev => prev.filter(p => p.id !== editingPeriodId));
    }
    setEditingPeriodId(null);
    setPeriodDraft(null);
  };

  const deletePeriod = (id) => {
    const updated = playPeriods.filter(p => p.id !== id);
    setEditingPeriodId(null);
    setPeriodDraft(null);
    savePlayPeriods(updated);
  };

  const handleFetchIGDB = async () => {
    setIgdbFetching(true);
    try {
      // Try by ID first, fall back to name search
      const result = game.igdbId
        ? await fetchIGDBGame(game.igdbId)
        : await fetchIGDBByName(game.name);

      if (result) {
        onUpdateGame({
          ...game,
          igdbId: result.igdbId || game.igdbId,
          igdbSlug: result.igdbSlug || game.igdbSlug,
          coverImageId: result.coverImageId || game.coverImageId,
          coverUrl: result.coverUrl || game.coverUrl,
          franchise: game.franchise || result.franchise,
          firstReleaseDate: game.firstReleaseDate || result.firstReleaseDate,
          genres: result.genres?.length ? result.genres : game.genres,
          themes: result.themes?.length ? result.themes : game.themes,
          gameModes: result.gameModes?.length ? result.gameModes : game.gameModes,
          playerPerspectives: result.playerPerspectives?.length ? result.playerPerspectives : game.playerPerspectives,
          developers: result.developers?.length ? result.developers : game.developers,
          publishers: result.publishers?.length ? result.publishers : game.publishers,
        });
        setIgdbFetchDone(true);
        setTimeout(() => setIgdbFetchDone(false), 3000);
      }
    } catch (e) {
      console.error('IGDB fetch failed:', e);
    } finally {
      setIgdbFetching(false);
    }
  };

  const startEditingPlatforms = () => {
    setPlatformDraft([...(game.platforms || [])]);
    setCustomPlatformDraft('');
    setEditingPlatforms(true);
  };

  const togglePlatformDraft = (p) => {
    setPlatformDraft(prev =>
      prev.includes(p) ? prev.filter(x => x !== p) : [...prev, p]
    );
  };

  const addCustomPlatform = () => {
    const val = customPlatformDraft.trim();
    if (val && !platformDraft.includes(val)) {
      setPlatformDraft(prev => [...prev, val]);
    }
    setCustomPlatformDraft('');
  };

  const savePlatforms = () => {
    const allPlatforms = [
      ...platformDraft,
      ...(customPlatformDraft.trim() && !platformDraft.includes(customPlatformDraft.trim())
        ? [customPlatformDraft.trim()] : []),
    ];
    onUpdateGame({ ...game, platforms: allPlatforms });
    setEditingPlatforms(false);
  };

  const statusColor = STATUS_COLORS[game.status] || 'bg-gray-500';
  const dekuSearchUrl = `https://www.dekudeals.com/search?q=${encodeURIComponent(game.name)}`;

  return (
    <div className="min-h-screen bg-gradient-to-b from-slate-900 via-slate-800 to-slate-900 safe-area-bottom">

      {/* Hero area with blurred cover background */}
      <div className="relative">
        {/* Blurred background */}
        {bigCoverUrl && (
          <div
            className="absolute inset-0 bg-cover bg-center"
            style={{ backgroundImage: `url(${bigCoverUrl})` }}
          >
            <div className="absolute inset-0 bg-slate-900/75 backdrop-blur-xl" />
          </div>
        )}

        <div className="relative max-w-4xl mx-auto px-4 pt-4 pb-6">
          {/* Navigation */}
          <div className="flex items-center justify-between mb-4">
            <button
              onClick={onBack}
              className="btn-secondary !px-3 !py-2 !min-h-0 text-sm flex items-center gap-1.5"
            >
              <ArrowLeft className="w-3.5 h-3.5" />
              Back
            </button>
            <div className="flex items-center gap-2">
              <button
                onClick={onGoHome || onBack}
                className="btn-secondary !px-3 !py-2 !min-h-0 text-sm flex items-center gap-1.5"
              >
                <Home className="w-3.5 h-3.5" />
                <span className="hidden sm:inline">Home</span>
              </button>
              <button
                onClick={onGoLibrary || onBack}
                className="btn-secondary !px-3 !py-2 !min-h-0 text-sm flex items-center gap-1.5"
              >
                Library
              </button>
            </div>
          </div>

          {/* Cover + Info */}
          <div className="flex gap-5 items-start">
            {/* Cover art */}
            <div className="flex-shrink-0 w-28 sm:w-36 space-y-2">
              {coverUrl ? (
                <img
                  src={coverUrl}
                  alt={game.name}
                  className="w-full rounded-xl shadow-2xl"
                  onError={e => { e.target.style.display = 'none'; }}
                />
              ) : (
                <div className="w-full aspect-[3/4] rounded-xl bg-purple-900/40 border border-purple-500/20 flex items-center justify-center">
                  <span className="text-5xl opacity-40">🎮</span>
                </div>
              )}
              {/* IGDB fetch button — shown when no art or as refresh */}
              <button
                onClick={handleFetchIGDB}
                disabled={igdbFetching}
                className={`w-full text-xs py-1.5 px-2 rounded-lg flex items-center justify-center gap-1 transition-colors ${
                  igdbFetchDone
                    ? 'bg-green-900/50 text-green-300'
                    : 'bg-white/10 hover:bg-white/20 text-gray-400 disabled:opacity-50'
                }`}
                title={coverUrl ? 'Refresh IGDB data' : 'Fetch art from IGDB'}
              >
                {igdbFetching ? (
                  <><RefreshCw className="w-3 h-3 animate-spin" /> Fetching…</>
                ) : igdbFetchDone ? (
                  <><Check className="w-3 h-3" /> Updated!</>
                ) : (
                  <><RefreshCw className="w-3 h-3" /> {coverUrl ? 'Refresh' : 'Get Art'}</>
                )}
              </button>
            </div>

            {/* Game info */}
            <div className="flex-1 min-w-0 space-y-3">
              <div>
                <h1 className="text-2xl sm:text-3xl font-bold leading-tight">{game.name}</h1>
                {game.franchise && (
                  <p className="text-gray-400 text-sm mt-1">{game.franchise} series</p>
                )}
                {game.platforms?.length > 0 && (
                  <p className="text-gray-500 text-xs mt-1">{game.platforms.join(' · ')}</p>
                )}
              </div>

              {/* Status picker */}
              <div>
                <div className="text-xs text-gray-500 mb-1.5">Status</div>
                <StatusPicker status={game.status} onChange={handleStatusChange} />
              </div>

              {/* Rating */}
              <div>
                <div className="text-xs text-gray-500 mb-1.5">Your Rating</div>
                <StarRating value={rating} onChange={handleRatingChange} size="lg" />
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Content below hero */}
      <div className="max-w-4xl mx-auto px-4 py-4 space-y-4">

        {/* Play stats */}
        <div className="grid grid-cols-3 gap-3">
          <div className="card p-4 text-center">
            <div className="text-2xl font-bold text-purple-300">{formatDuration(totalPlaytime)}</div>
            <div className="text-xs text-gray-500 mt-1">Time Played</div>
          </div>
          <div className="card p-4 text-center">
            <div className="text-2xl font-bold text-blue-300">{(game.saves || []).length}</div>
            <div className="text-xs text-gray-500 mt-1">Save{(game.saves || []).length !== 1 ? 's' : ''}</div>
          </div>
          <div className="card p-4 text-center relative group">
            <div className="text-2xl font-bold text-green-300">{completionCount || '—'}</div>
            <div className="text-xs text-gray-500 mt-1">Clears</div>
            <button
              onClick={() => onUpdateGame({ ...game, clears: [...(game.clears || []), { id: generateId(), clearedAt: new Date().toISOString() }] })}
              className="absolute top-1.5 right-1.5 p-1 rounded text-gray-700 hover:text-green-400 hover:bg-white/5 transition-colors opacity-0 group-hover:opacity-100"
              title="Mark cleared"
            >
              <Plus className="w-3.5 h-3.5" />
            </button>
            {(game.clears || []).length > 0 && (
              <button
                onClick={() => onUpdateGame({ ...game, clears: (game.clears || []).slice(0, -1) })}
                className="absolute top-1.5 left-1.5 p-1 rounded text-gray-700 hover:text-red-400 hover:bg-white/5 transition-colors opacity-0 group-hover:opacity-100"
                title="Remove last clear"
              >
                <X className="w-3.5 h-3.5" />
              </button>
            )}
          </div>
        </div>

        {/* Open tracker / save selector */}
        <div className="card p-4">
          <h2 className="text-sm font-medium text-gray-400 mb-3">
            {game.trackerType ? 'Tracker' : 'Play Tracking'}
          </h2>
          <SaveSelector game={game} onOpenTracker={onOpenTracker} />
        </div>

        {/* Play History */}
        <div className="card p-4 space-y-3">
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-medium">Play History</h2>
            <button
              onClick={startAddPeriod}
              className="text-xs text-purple-400 hover:text-purple-300 flex items-center gap-1"
            >
              <Plus className="w-3 h-3" /> Add
            </button>
          </div>

          {playPeriods.length === 0 && (
            <p className="text-sm text-gray-600 italic">No play history yet.</p>
          )}

          <div className="space-y-2">
            {playPeriods.map(period => {
              const isEditing = editingPeriodId === period.id;
              if (isEditing && periodDraft) {
                return (
                  <div key={period.id} className="bg-slate-700/40 rounded-xl p-3 space-y-2.5">
                    {/* Start */}
                    <div>
                      <div className="text-xs text-gray-500 mb-1">Started</div>
                      <div className="flex gap-2">
                        <select
                          value={periodDraft.startMonth}
                          onChange={e => setPeriodDraft(d => ({ ...d, startMonth: e.target.value }))}
                          className="input-field text-sm !py-1 flex-1"
                        >
                          <option value="">Month (optional)</option>
                          {MONTHS.map((m, i) => <option key={m} value={i + 1}>{m}</option>)}
                        </select>
                        <input
                          type="number"
                          placeholder="Year"
                          min="1970"
                          max={new Date().getFullYear() + 1}
                          value={periodDraft.startYear}
                          onChange={e => setPeriodDraft(d => ({ ...d, startYear: e.target.value }))}
                          className="input-field text-sm !py-1 w-24"
                        />
                      </div>
                    </div>

                    {/* End */}
                    <div>
                      <div className="flex items-center justify-between mb-1">
                        <div className="text-xs text-gray-500">Ended</div>
                        <label className="flex items-center gap-1.5 text-xs text-gray-400 cursor-pointer">
                          <input
                            type="checkbox"
                            checked={periodDraft.ongoing}
                            onChange={e => setPeriodDraft(d => ({ ...d, ongoing: e.target.checked }))}
                            className="w-3.5 h-3.5 accent-purple-500"
                          />
                          Still playing
                        </label>
                      </div>
                      {!periodDraft.ongoing && (
                        <div className="flex gap-2">
                          <select
                            value={periodDraft.endMonth}
                            onChange={e => setPeriodDraft(d => ({ ...d, endMonth: e.target.value }))}
                            className="input-field text-sm !py-1 flex-1"
                          >
                            <option value="">Month (optional)</option>
                            {MONTHS.map((m, i) => <option key={m} value={i + 1}>{m}</option>)}
                          </select>
                          <input
                            type="number"
                            placeholder="Year"
                            min="1970"
                            max={new Date().getFullYear() + 1}
                            value={periodDraft.endYear}
                            onChange={e => setPeriodDraft(d => ({ ...d, endYear: e.target.value }))}
                            className="input-field text-sm !py-1 w-24"
                          />
                        </div>
                      )}
                    </div>

                    {/* Platform */}
                    <div>
                      <div className="text-xs text-gray-500 mb-1">Played on</div>
                      <select
                        value={periodDraft.platform}
                        onChange={e => setPeriodDraft(d => ({ ...d, platform: e.target.value }))}
                        className="input-field text-sm !py-1 w-full"
                      >
                        <option value="">— Unknown / not listed —</option>
                        {/* Game's own platforms first */}
                        {(game.platforms || []).length > 0 && (
                          <optgroup label="This game's platforms">
                            {(game.platforms || []).map(p => (
                              <option key={p} value={p}>{p}</option>
                            ))}
                          </optgroup>
                        )}
                        <optgroup label="Other platforms">
                          {KNOWN_PLATFORMS.filter(p => !(game.platforms || []).includes(p)).map(p => (
                            <option key={p} value={p}>{p}</option>
                          ))}
                        </optgroup>
                      </select>
                    </div>

                    {/* Note */}
                    <input
                      type="text"
                      placeholder="Note (optional — e.g. 'first playthrough', 'NG+')"
                      value={periodDraft.note}
                      onChange={e => setPeriodDraft(d => ({ ...d, note: e.target.value }))}
                      className="input-field text-sm !py-1 w-full"
                    />

                    {/* Actions */}
                    <div className="flex gap-2">
                      <button onClick={savePeriodEdit} className="btn-primary flex-1 text-xs py-1.5 gap-1">
                        <Check className="w-3.5 h-3.5" /> Save
                      </button>
                      <button onClick={cancelPeriodEdit} className="btn-secondary flex-1 text-xs py-1.5 gap-1">
                        <X className="w-3.5 h-3.5" /> Cancel
                      </button>
                      <button
                        onClick={() => deletePeriod(period.id)}
                        className="btn-secondary !px-2.5 py-1.5 text-red-400 hover:text-red-300"
                        title="Remove this period"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  </div>
                );
              }

              // Display mode
              return (
                <button
                  key={period.id}
                  onClick={() => startEditPeriod(period)}
                  className="w-full text-left flex items-center gap-3 px-3 py-2 rounded-xl hover:bg-white/5 transition-colors group"
                >
                  <div className="w-2 h-2 rounded-full bg-purple-500 flex-shrink-0 mt-0.5" />
                  <div className="flex-1 min-w-0">
                    <div className="text-sm text-gray-200">{formatPeriod(period)}</div>
                    <div className="flex items-center gap-2 mt-0.5">
                      {period.platform && (
                        <span className="text-xs text-purple-400 bg-purple-900/30 px-1.5 py-0.5 rounded">
                          {period.platform}
                        </span>
                      )}
                      {period.note && <span className="text-xs text-gray-500">{period.note}</span>}
                    </div>
                  </div>
                  <Edit2 className="w-3 h-3 text-gray-600 group-hover:text-purple-400 flex-shrink-0 transition-colors" />
                </button>
              );
            })}
          </div>
        </div>

        {/* Review */}
        <div className="card p-4 space-y-3">
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-medium">Your Review</h2>
            {!editingReview && (
              <button
                onClick={() => { setReviewDraft(review || ''); setEditingReview(true); }}
                className="text-xs text-purple-400 hover:text-purple-300 flex items-center gap-1"
              >
                <Edit2 className="w-3 h-3" />
                {review ? 'Edit' : 'Write'}
              </button>
            )}
          </div>

          {/* Stars */}
          <StarRating value={rating} onChange={handleRatingChange} size="md" />
          {rating && (
            <div className="text-sm text-gray-400">
              {['', 'Terrible', 'Mediocre', 'Good', 'Great', 'Excellent'][rating]}
            </div>
          )}

          {/* Review text */}
          {editingReview ? (
            <div className="space-y-2">
              <textarea
                value={reviewDraft}
                onChange={e => setReviewDraft(e.target.value)}
                placeholder="Share your thoughts…"
                className="input-field resize-none h-36 text-sm w-full"
                autoFocus
              />
              <div className="flex gap-2">
                <button onClick={handleSaveReview} className="btn-primary flex-1 text-sm gap-1">
                  <Check className="w-4 h-4" /> Save
                </button>
                <button onClick={() => setEditingReview(false)} className="btn-secondary flex-1 text-sm gap-1">
                  <X className="w-4 h-4" /> Cancel
                </button>
              </div>
            </div>
          ) : review ? (
            <p className="text-sm text-gray-300 leading-relaxed whitespace-pre-wrap">{review}</p>
          ) : (
            <p className="text-sm text-gray-600 italic">No review yet.</p>
          )}
        </div>

        {/* Tags */}
        <div className="card p-4 space-y-2.5">
          <h2 className="text-sm font-medium">Tags</h2>
          <div className="flex flex-wrap gap-1.5">
            {allGameTags.map(tag => (
              <span key={tag} className="px-2.5 py-1 rounded-full text-xs font-medium bg-purple-600/50 text-purple-200 flex items-center gap-1">
                #{tag}
                <button onClick={() => removeTag(tag)} className="hover:text-white">
                  <X className="w-3 h-3" />
                </button>
              </span>
            ))}
          </div>
          <div className="flex gap-1.5">
            <TagInput
              suggestions={allLibraryTags.filter(t => !allGameTags.includes(t))}
              onAdd={addTag}
              placeholder="Add a tag…"
            />
          </div>
        </div>

        {/* Game Info block */}
        <div className="card p-4 space-y-4">
          <h2 className="text-sm font-medium text-gray-400">Game Info</h2>

          <div className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">

            {/* Release year */}
            {game.firstReleaseDate && (
              <div>
                <div className="text-xs text-gray-500 mb-0.5">Released</div>
                <div className="text-gray-200">{game.firstReleaseDate}</div>
              </div>
            )}


            {/* Franchise — editable */}
            <div>
              <div className="flex items-center justify-between mb-0.5">
                <div className="text-xs text-gray-500">Series</div>
                {!editingFranchise && (
                  <button
                    onClick={startEditFranchise}
                    className="text-xs text-purple-400 hover:text-purple-300 flex items-center gap-1"
                  >
                    <Edit2 className="w-3 h-3" />
                    {game.franchise ? 'Edit' : 'Add'}
                  </button>
                )}
              </div>
              {editingFranchise ? (
                <div className="col-span-2 space-y-1.5 mt-0.5">
                  <input
                    type="text"
                    placeholder="e.g. Zelda, Ori, Mario…"
                    value={franchiseDraft}
                    onChange={e => setFranchiseDraft(e.target.value)}
                    onKeyDown={e => { if (e.key === 'Enter') saveFranchise(); if (e.key === 'Escape') setEditingFranchise(false); }}
                    className="input-field text-sm !py-1 w-full"
                    autoFocus
                    list="franchise-suggestions"
                  />
                  <datalist id="franchise-suggestions">
                    {allLibraryFranchises.map(f => <option key={f} value={f} />)}
                  </datalist>
                  <div className="flex gap-1.5">
                    <button onClick={saveFranchise} className="btn-primary flex-1 text-xs py-1.5 gap-1">
                      <Check className="w-3.5 h-3.5" /> Save
                    </button>
                    <button onClick={() => setEditingFranchise(false)} className="btn-secondary flex-1 text-xs py-1.5 gap-1">
                      <X className="w-3.5 h-3.5" /> Cancel
                    </button>
                  </div>
                </div>
              ) : (
                <div className="text-gray-200">
                  {game.franchise || <span className="text-gray-600 italic">—</span>}
                </div>
              )}
            </div>

            {/* Platforms — editable */}
            <div className={game.platforms?.length > 0 ? '' : 'col-span-2'}>
              <div className="flex items-center justify-between mb-0.5">
                <div className="text-xs text-gray-500">Platform{(game.platforms?.length || 0) !== 1 ? 's' : ''}</div>
                {!editingPlatforms && (
                  <button
                    onClick={startEditingPlatforms}
                    className="text-xs text-purple-400 hover:text-purple-300 flex items-center gap-1"
                  >
                    <Edit2 className="w-3 h-3" />
                    {game.platforms?.length ? 'Edit' : 'Add'}
                  </button>
                )}
              </div>
              {editingPlatforms ? (
                <div className="col-span-2 space-y-2 mt-1">
                  {/* Preset chips */}
                  <div className="flex flex-wrap gap-1.5">
                    {PRESET_PLATFORMS.map(p => (
                      <button
                        key={p}
                        onClick={() => togglePlatformDraft(p)}
                        className={`px-2.5 py-1 rounded-full text-xs font-medium transition-colors ${
                          platformDraft.includes(p)
                            ? 'bg-purple-600 text-white'
                            : 'bg-white/10 text-gray-400 hover:bg-white/20'
                        }`}
                      >
                        {p}
                      </button>
                    ))}
                    {/* Custom platforms already in draft that aren't presets */}
                    {platformDraft.filter(p => !PRESET_PLATFORMS.includes(p)).map(p => (
                      <button
                        key={p}
                        onClick={() => togglePlatformDraft(p)}
                        className="px-2.5 py-1 rounded-full text-xs font-medium bg-blue-600 text-white"
                      >
                        {p} ×
                      </button>
                    ))}
                  </div>
                  {/* Custom input */}
                  <div className="flex gap-1.5">
                    <input
                      type="text"
                      placeholder="Other platform…"
                      value={customPlatformDraft}
                      onChange={e => setCustomPlatformDraft(e.target.value)}
                      onKeyDown={e => e.key === 'Enter' && addCustomPlatform()}
                      className="input-field text-sm flex-1 !py-1"
                    />
                    <button onClick={addCustomPlatform} className="btn-secondary !px-2 !py-1 !min-h-0">
                      <Plus className="w-3.5 h-3.5" />
                    </button>
                  </div>
                  <div className="flex gap-1.5">
                    <button onClick={savePlatforms} className="btn-primary flex-1 text-xs py-1.5 gap-1">
                      <Check className="w-3.5 h-3.5" /> Save
                    </button>
                    <button onClick={() => setEditingPlatforms(false)} className="btn-secondary flex-1 text-xs py-1.5 gap-1">
                      <X className="w-3.5 h-3.5" /> Cancel
                    </button>
                  </div>
                </div>
              ) : (
                <div className="text-gray-200">
                  {game.platforms?.length
                    ? game.platforms.join(', ')
                    : <span className="text-gray-600 italic">—</span>}
                </div>
              )}
            </div>

            {/* Developer */}
            {game.developers?.length > 0 && (
              <div>
                <div className="text-xs text-gray-500 mb-0.5">Developer</div>
                <div className="text-gray-200">{game.developers.join(', ')}</div>
              </div>
            )}

            {/* Publisher */}
            {game.publishers?.length > 0 && (
              <div>
                <div className="text-xs text-gray-500 mb-0.5">Publisher</div>
                <div className="text-gray-200">{game.publishers.join(', ')}</div>
              </div>
            )}
          </div>

          {/* Tags row — genres + themes combined, game modes, perspectives */}
          {(() => {
            // Combine genres and themes into one tag group (IGDB separates them but they're both "what kind of game")
            const genreTags = [...(game.genres || []), ...(game.themes || [])];
            const modeTags = game.gameModes || [];
            const perspTags = game.playerPerspectives || [];
            if (genreTags.length === 0 && modeTags.length === 0 && perspTags.length === 0) return null;

            return (
              <div className="space-y-2 pt-1 border-t border-white/10">
                {genreTags.length > 0 && (
                  <div>
                    <div className="text-xs text-gray-500 mb-1.5">Genre / Theme</div>
                    <div className="flex flex-wrap gap-1.5">
                      {genreTags.map(tag => (
                        <span key={tag} className="text-xs bg-purple-900/40 text-purple-300 border border-purple-500/20 px-2 py-0.5 rounded-full">
                          {tag}
                        </span>
                      ))}
                    </div>
                  </div>
                )}

                {modeTags.length > 0 && (
                  <div>
                    <div className="text-xs text-gray-500 mb-1.5">Game Modes</div>
                    <div className="flex flex-wrap gap-1.5">
                      {modeTags.map(tag => (
                        <span key={tag} className="text-xs bg-blue-900/40 text-blue-300 border border-blue-500/20 px-2 py-0.5 rounded-full">
                          {tag}
                        </span>
                      ))}
                    </div>
                  </div>
                )}

                {perspTags.length > 0 && (
                  <div>
                    <div className="text-xs text-gray-500 mb-1.5">Perspective</div>
                    <div className="flex flex-wrap gap-1.5">
                      {perspTags.map(tag => (
                        <span key={tag} className="text-xs bg-slate-700/60 text-gray-300 border border-white/10 px-2 py-0.5 rounded-full">
                          {tag}
                        </span>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            );
          })()}

          {/* External links */}
          <div className="flex items-center gap-4 pt-1 border-t border-white/10">
            <a
              href={dekuSearchUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-1.5 text-xs text-orange-400 hover:text-orange-300"
            >
              <ExternalLink className="w-3.5 h-3.5" />
              Search Deku Deals
            </a>
            {(game.igdbSlug || game.igdbId) && (
              <a
                href={game.igdbSlug ? igdbGameUrl(game.igdbSlug) : `https://www.igdb.com/games/${game.igdbId}`}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-1.5 text-xs text-purple-400 hover:text-purple-300"
              >
                <ExternalLink className="w-3.5 h-3.5" />
                View on IGDB
              </a>
            )}
          </div>
        </div>

        {/* Related games */}
        {library && library.length > 1 && (
          <RelatedGames game={game} library={library} onOpenGame={onOpenGame} />
        )}

      </div>
    </div>
  );
}
