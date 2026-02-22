import React, { useState, useRef, useEffect, useCallback } from 'react';
import { parseGameryCSV } from '../utils/csvParser.js';
import { createGameEntry } from '../utils/factories.js';
import { searchIGDB, igdbCoverUrl, batchFetchIGDB, fetchIGDBByName } from '../utils/igdb.js';
import {
  Search, Upload, Plus, Gamepad2, Trash2, ChevronDown,
  LayoutGrid, List, BarChart2, Star, Clock, Filter,
  ExternalLink, X, Check, ShoppingBag, RefreshCw, Download,
  CheckSquare, Square,
} from 'lucide-react';

// ─── Constants ───────────────────────────────────────────────────────────────

const STATUS_COLORS = {
  playing:   'bg-green-500',
  paused:    'bg-yellow-500',
  completed: 'bg-blue-500',
  backlog:   'bg-gray-500',
  shelved:   'bg-orange-500',
  abandoned: 'bg-red-500',
};

const STATUS_LABELS = {
  playing:   'Playing',
  paused:    'Paused',
  completed: 'Completed',
  backlog:   'Backlog',
  shelved:   'Shelved',
  abandoned: 'Abandoned',
};

const STATUS_ORDER = { playing: 0, paused: 1, backlog: 2, completed: 3, shelved: 4, abandoned: 5 };

// Platforms the user plays on — shown as quick-select chips
const PRESET_PLATFORMS = [
  'Switch',
  'Switch 2',
  'Mac',
  'iOS',
  'Recalbox',
];

// Map IGDB platform names → our preset names (and handle Mac-over-Windows preference)
const PLATFORM_MAP = {
  'PC (Microsoft Windows)': 'Mac', // prefer Mac — will be overridden to null if no Mac version
  'Mac': 'Mac',
  'macOS': 'Mac',
  'Nintendo Switch': 'Switch',
  'Nintendo Switch 2': 'Switch 2',
  'iOS': 'iOS',
  'iPhone': 'iOS',
  'iPad': 'iOS',
};

// Given IGDB platform list, return the user's preferred preset platforms.
// Prefers Mac over Windows; if the game has a Mac version, uses that.
// If it has Windows but no Mac, stays as null (user didn't ask for PC tracking).
function mapIGDBPlatforms(igdbPlatforms) {
  const names = (igdbPlatforms || []).map(p => (typeof p === 'string' ? p : p.name || ''));
  const hasMac = names.some(n => n === 'Mac' || n === 'macOS');
  const hasWindows = names.some(n => n === 'PC (Microsoft Windows)');
  const hasSwitch = names.some(n => n === 'Nintendo Switch');
  const hasSwitch2 = names.some(n => n === 'Nintendo Switch 2');
  const hasIOS = names.some(n => n === 'iOS' || n === 'iPhone' || n === 'iPad');

  const result = [];
  // Mac preferred over Windows; only add Mac if the game actually supports it
  if (hasMac) result.push('Mac');
  // Windows-only: don't add anything (user doesn't track "PC" as a platform)
  if (hasSwitch) result.push('Switch');
  if (hasSwitch2) result.push('Switch 2');
  if (hasIOS) result.push('iOS');
  return result;
}

// Games that have dedicated detailed trackers
const TRACKER_TYPES = {
  'Hades': 'hades',
  'Lone Ruin': 'lone-ruin',
  'LONE RUIN': 'lone-ruin',
  'GONNER': 'gonner',
  "GON'NER": 'gonner',
  'Gonner': 'gonner',
  'Cursed to Golf': 'cursed-to-golf',
  'Blazing Chrome': 'blazing-chrome',
  'Sayonara Wild Hearts': 'sayonara-wild-hearts',
  'Cast n Chill': 'cast-n-chill',
  'Citizen Sleeper': 'citizen-sleeper',
  'The Messenger': 'messenger',
};

// Sort options
const SORT_OPTIONS = [
  { value: 'status',    label: 'By Status' },
  { value: 'name',      label: 'A – Z' },
  { value: 'added',     label: 'Recently Added' },
  { value: 'played',    label: 'Recently Played' },
  { value: 'playtime',  label: 'Most Played' },
  { value: 'platform',  label: 'By Platform' },
  { value: 'franchise', label: 'By Franchise' },
  { value: 'rating',    label: 'By Rating' },
];

// ─── Helpers ─────────────────────────────────────────────────────────────────

function formatDuration(seconds) {
  if (!seconds || seconds < 60) return seconds > 0 ? `${seconds}s` : '—';
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

function getGamePlaytime(game) {
  const save = game.saves?.[0];
  if (!save) return 0;
  // General tracker
  if (typeof save.totalPlaytime === 'number') return save.totalPlaytime;
  // Checklist tracker
  if (typeof save.totalPlaytime === 'number') return save.totalPlaytime;
  // Sessions array
  if (Array.isArray(save.sessions)) {
    return save.sessions.reduce((acc, s) => acc + (s.duration || 0), 0);
  }
  // Runs array
  if (Array.isArray(save.runs)) {
    return save.runs.reduce((acc, r) => acc + (r.duration || 0), 0);
  }
  return 0;
}

function getGameRating(game) {
  return game.saves?.[0]?.rating ?? game.userRating ?? null;
}

function getGameLastPlayed(game) {
  const save = game.saves?.[0];
  return save?.lastPlayedAt || game.addedAt;
}

function getLibraryStats(library) {
  const total = library.length;
  const byStatus = {};
  let totalPlaytime = 0;
  let ratedCount = 0;
  let ratingSum = 0;
  const byPlatform = {};
  const byFranchise = {};

  library.forEach(g => {
    // Status
    byStatus[g.status] = (byStatus[g.status] || 0) + 1;

    // Playtime
    totalPlaytime += getGamePlaytime(g);

    // Rating
    const r = getGameRating(g);
    if (r) { ratedCount++; ratingSum += r; }

    // Platform
    (g.platforms || []).forEach(p => {
      byPlatform[p] = (byPlatform[p] || 0) + 1;
    });

    // Franchise
    if (g.franchise) {
      byFranchise[g.franchise] = (byFranchise[g.franchise] || 0) + 1;
    }
  });

  return {
    total,
    byStatus,
    totalPlaytime,
    avgRating: ratedCount > 0 ? (ratingSum / ratedCount).toFixed(1) : null,
    ratedCount,
    byPlatform,
    byFranchise,
    completionRate: total > 0 ? Math.round(((byStatus.completed || 0) / total) * 100) : 0,
  };
}

// ─── Sub-components ──────────────────────────────────────────────────────────

function StatusBadge({ status, onChange }) {
  const [open, setOpen] = useState(false);
  const [dropdownPos, setDropdownPos] = useState({ top: 0, left: 0 });
  const btnRef = useRef(null);

  useEffect(() => {
    if (!open) return;
    const handler = (e) => {
      // Close if click is outside both the button and the portal dropdown
      if (btnRef.current && !btnRef.current.contains(e.target) && !e.target.closest('[data-status-dropdown]')) {
        setOpen(false);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [open]);

  const handleOpen = (e) => {
    e.stopPropagation();
    if (!open && btnRef.current) {
      const rect = btnRef.current.getBoundingClientRect();
      setDropdownPos({ top: rect.bottom + 4, left: rect.left });
    }
    setOpen(o => !o);
  };

  return (
    <>
      <button
        ref={btnRef}
        onClick={handleOpen}
        className={`${STATUS_COLORS[status]} text-white text-[10px] font-medium px-2 py-0.5 rounded-full whitespace-nowrap flex items-center gap-1`}
      >
        {STATUS_LABELS[status]}
        <ChevronDown className="w-2.5 h-2.5" />
      </button>
      {open && (
        <div
          data-status-dropdown
          style={{ position: 'fixed', top: dropdownPos.top, left: dropdownPos.left, zIndex: 9999 }}
          className="bg-slate-800 border border-white/10 rounded-lg shadow-2xl overflow-hidden min-w-[130px]"
          onClick={e => e.stopPropagation()}
        >
          {Object.entries(STATUS_LABELS).map(([val, label]) => (
            <button
              key={val}
              onClick={() => { onChange(val); setOpen(false); }}
              className={`w-full text-left px-3 py-2 text-xs flex items-center gap-2 hover:bg-white/10 transition-colors ${status === val ? 'text-white' : 'text-gray-400'}`}
            >
              <span className={`w-2 h-2 rounded-full flex-shrink-0 ${STATUS_COLORS[val]}`} />
              {label}
              {status === val && <Check className="w-3 h-3 ml-auto text-purple-400" />}
            </button>
          ))}
        </div>
      )}
    </>
  );
}

function StarRow({ rating, size = 'sm' }) {
  const sz = size === 'sm' ? 'w-3 h-3' : 'w-4 h-4';
  if (!rating) return null;
  return (
    <div className="flex gap-0.5">
      {[1,2,3,4,5].map(n => (
        <Star key={n} className={`${sz} ${n <= rating ? 'fill-yellow-400 text-yellow-400' : 'text-gray-700'}`} />
      ))}
    </div>
  );
}

function GameCard({ game, onOpen, onUpdateStatus, onDelete, viewMode, selectMode = false, selected = false, onToggleSelect }) {
  const hasTracker = game.trackerType !== null;
  const rating = getGameRating(game);
  const playtime = getGamePlaytime(game);
  const coverUrl = game.coverImageId ? igdbCoverUrl(game.coverImageId) : game.coverUrl || null;

  if (viewMode === 'list') {
    return (
      <div
        onClick={selectMode ? onToggleSelect : undefined}
        className={`card-hover px-3 py-2.5 text-left w-full group relative flex items-center gap-3 ${selected ? 'ring-2 ring-purple-500 bg-purple-900/20' : ''} ${selectMode ? 'cursor-pointer' : ''}`}
      >
        {/* Checkbox (select mode) or cover thumbnail */}
        {selectMode ? (
          <div className="w-8 h-10 flex-shrink-0 flex items-center justify-center">
            {selected
              ? <CheckSquare className="w-5 h-5 text-purple-400" />
              : <Square className="w-5 h-5 text-gray-500" />}
          </div>
        ) : (
          <div className="w-8 h-10 flex-shrink-0 rounded overflow-hidden bg-purple-900/20 border border-purple-500/10">
            {coverUrl ? (
              <img src={coverUrl} alt={game.name} className="w-full h-full object-cover" onError={e => { e.target.style.display='none'; }} />
            ) : (
              <div className="w-full h-full flex items-center justify-center text-sm">🎮</div>
            )}
          </div>
        )}

        <button onClick={selectMode ? undefined : onOpen} className="flex-1 min-w-0 text-left" tabIndex={selectMode ? -1 : 0}>
          <div className="flex items-center gap-2 min-w-0">
            <span className="font-medium text-sm truncate group-hover:text-purple-300 transition-colors">
              {game.name}
            </span>
            {hasTracker && <span className="w-1.5 h-1.5 rounded-full bg-purple-400 flex-shrink-0" />}
          </div>
          <div className="flex items-center gap-2 mt-0.5 text-xs text-gray-500">
            {game.platforms?.length > 0 && <span className="truncate">{game.platforms.join(', ')}</span>}
            {game.franchise && <span className="text-gray-600">· {game.franchise}</span>}
            {playtime > 0 && <span className="text-gray-600">· {formatDuration(playtime)}</span>}
          </div>
        </button>

        <div className="flex items-center gap-2 flex-shrink-0">
          {rating && <StarRow rating={rating} />}
          {!selectMode && <StatusBadge status={game.status} onChange={onUpdateStatus} />}
          {!selectMode && (
            <button
              onClick={(e) => { e.stopPropagation(); onDelete(); }}
              className="text-gray-600 hover:text-red-400 transition-colors opacity-0 group-hover:opacity-100 p-1"
            >
              <Trash2 className="w-3.5 h-3.5" />
            </button>
          )}
        </div>
      </div>
    );
  }

  // Grid view
  return (
    <div
      onClick={selectMode ? onToggleSelect : undefined}
      className={`card-hover text-left w-full group relative flex flex-col ${selected ? 'ring-2 ring-purple-500' : ''} ${selectMode ? 'cursor-pointer' : ''}`}
    >
      {/* Select checkbox overlay (top-left in select mode) */}
      {selectMode && (
        <div className="absolute top-2 left-2 z-10 bg-slate-900/70 rounded p-0.5">
          {selected
            ? <CheckSquare className="w-5 h-5 text-purple-400" />
            : <Square className="w-5 h-5 text-gray-400" />}
        </div>
      )}

      {/* Delete button (only when NOT in select mode) */}
      {!selectMode && (
        <button
          onClick={(e) => { e.stopPropagation(); onDelete(); }}
          className="absolute top-2 right-2 p-1.5 rounded-md text-gray-600 hover:text-red-400 hover:bg-red-400/10 transition-colors opacity-0 group-hover:opacity-100 z-10"
          title="Remove game"
        >
          <Trash2 className="w-3.5 h-3.5" />
        </button>
      )}

      {/* Cover art — full 3:4 ratio, no cropping */}
      <div className="rounded-t-xl overflow-hidden relative">
        {coverUrl ? (
          <img
            src={coverUrl}
            alt={game.name}
            className="w-full aspect-[3/4] object-cover"
            onError={e => { e.target.parentElement.classList.add('no-cover'); e.target.style.display = 'none'; }}
          />
        ) : (
          <div className="w-full aspect-[3/4] bg-gradient-to-br from-purple-900/40 to-slate-900/60 flex items-center justify-center border-b border-white/5">
            <span className="text-4xl opacity-40">🎮</span>
          </div>
        )}
      </div>

      {/* Status badge — outside the cover (no overflow-hidden) and outside the card body button (no nested button) */}
      {!selectMode && (
        <div className="px-3 pt-2" onClick={e => e.stopPropagation()}>
          <StatusBadge status={game.status} onChange={onUpdateStatus} />
        </div>
      )}

      {/* Card body — tappable area to open game */}
      <button onClick={selectMode ? undefined : onOpen} className="flex-1 px-3 pb-3 pt-1 text-left" tabIndex={selectMode ? -1 : 0}>
        <h3 className="font-semibold text-sm leading-tight group-hover:text-purple-300 transition-colors line-clamp-2 mb-1">
          {game.name}
        </h3>
        {game.platforms?.length > 0 && (
          <p className="text-gray-500 text-xs mb-1 truncate">{game.platforms.join(', ')}</p>
        )}
        {game.franchise && (
          <p className="text-gray-600 text-xs mb-1 truncate">{game.franchise}</p>
        )}
        <div className="flex items-center justify-between mt-2">
          {rating ? <StarRow rating={rating} /> : <span />}
          {playtime > 0 && (
            <span className="text-xs text-gray-500 flex items-center gap-1">
              <Clock className="w-3 h-3" />{formatDuration(playtime)}
            </span>
          )}
        </div>
        {hasTracker && (
          <div className="flex items-center gap-1 text-purple-400 text-xs mt-1">
            <span className="w-1.5 h-1.5 rounded-full bg-purple-400" />
            Detailed tracker
          </div>
        )}
      </button>
    </div>
  );
}

// ─── IGDB Search in Add Game modal ───────────────────────────────────────────

function IGDBSearchResult({ result, onSelect }) {
  return (
    <button
      onClick={() => onSelect(result)}
      className="w-full flex items-center gap-3 px-3 py-2.5 hover:bg-white/10 rounded-lg transition-colors text-left"
    >
      {result.coverUrl ? (
        <img src={result.coverUrl} alt={result.name} className="w-8 h-10 object-cover rounded flex-shrink-0" />
      ) : (
        <div className="w-8 h-10 bg-purple-900/30 rounded flex-shrink-0 flex items-center justify-center text-xs">🎮</div>
      )}
      <div className="min-w-0">
        <div className="text-sm font-medium truncate">{result.name}</div>
        <div className="text-xs text-gray-500 truncate">
          {[result.franchise, result.firstReleaseDate].filter(Boolean).join(' · ')}
        </div>
      </div>
    </button>
  );
}

// ─── Library Stats view ──────────────────────────────────────────────────────

function LibraryStats({ library }) {
  const stats = getLibraryStats(library);

  const platformEntries = Object.entries(stats.byPlatform).sort((a,b) => b[1]-a[1]);
  const franchiseEntries = Object.entries(stats.byFranchise).sort((a,b) => b[1]-a[1]).slice(0, 10);
  const maxPlatformCount = platformEntries[0]?.[1] || 1;
  const maxFranchiseCount = franchiseEntries[0]?.[1] || 1;

  return (
    <div className="space-y-4 pb-8">
      {/* Headline stats */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        {[
          { label: 'Total Games', value: stats.total, color: 'text-white' },
          { label: 'Completed', value: stats.byStatus.completed || 0, color: 'text-blue-400' },
          { label: 'Playing', value: stats.byStatus.playing || 0, color: 'text-green-400' },
          { label: 'Completion Rate', value: `${stats.completionRate}%`, color: 'text-purple-400' },
        ].map(s => (
          <div key={s.label} className="card p-4 text-center">
            <div className={`text-3xl font-bold ${s.color}`}>{s.value}</div>
            <div className="text-xs text-gray-500 mt-1">{s.label}</div>
          </div>
        ))}
      </div>

      {/* Playtime + Rating */}
      <div className="grid grid-cols-2 gap-3">
        <div className="card p-4 text-center">
          <div className="text-2xl font-bold text-purple-300">{formatDuration(stats.totalPlaytime)}</div>
          <div className="text-xs text-gray-500 mt-1">Total Tracked Playtime</div>
        </div>
        <div className="card p-4 text-center">
          <div className="text-2xl font-bold text-yellow-400">
            {stats.avgRating ? `★ ${stats.avgRating}` : '—'}
          </div>
          <div className="text-xs text-gray-500 mt-1">
            Avg Rating ({stats.ratedCount} rated)
          </div>
        </div>
      </div>

      {/* Status breakdown */}
      <div className="card p-4">
        <h3 className="text-sm font-medium mb-3">Status Breakdown</h3>
        <div className="space-y-2">
          {Object.entries(STATUS_LABELS).map(([status, label]) => {
            const count = stats.byStatus[status] || 0;
            const pct = stats.total > 0 ? (count / stats.total) * 100 : 0;
            return (
              <div key={status} className="flex items-center gap-3">
                <span className={`w-2 h-2 rounded-full flex-shrink-0 ${STATUS_COLORS[status]}`} />
                <span className="text-sm text-gray-300 w-20 flex-shrink-0">{label}</span>
                <div className="flex-1 bg-black/40 rounded-full h-2">
                  <div
                    className={`${STATUS_COLORS[status]} h-2 rounded-full transition-all`}
                    style={{ width: `${pct}%` }}
                  />
                </div>
                <span className="text-sm text-gray-400 w-6 text-right">{count}</span>
              </div>
            );
          })}
        </div>
      </div>

      {/* Platform breakdown */}
      {platformEntries.length > 0 && (
        <div className="card p-4">
          <h3 className="text-sm font-medium mb-3">By Platform</h3>
          <div className="space-y-2">
            {platformEntries.map(([platform, count]) => (
              <div key={platform} className="flex items-center gap-3">
                <span className="text-sm text-gray-300 w-28 flex-shrink-0 truncate">{platform}</span>
                <div className="flex-1 bg-black/40 rounded-full h-2">
                  <div
                    className="bg-purple-600 h-2 rounded-full transition-all"
                    style={{ width: `${(count / maxPlatformCount) * 100}%` }}
                  />
                </div>
                <span className="text-sm text-gray-400 w-6 text-right">{count}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Franchise breakdown */}
      {franchiseEntries.length > 0 && (
        <div className="card p-4">
          <h3 className="text-sm font-medium mb-3">By Franchise</h3>
          <div className="space-y-2">
            {franchiseEntries.map(([franchise, count]) => (
              <div key={franchise} className="flex items-center gap-3">
                <span className="text-sm text-gray-300 flex-1 truncate">{franchise}</span>
                <div className="w-24 bg-black/40 rounded-full h-2">
                  <div
                    className="bg-blue-600 h-2 rounded-full transition-all"
                    style={{ width: `${(count / maxFranchiseCount) * 100}%` }}
                  />
                </div>
                <span className="text-sm text-gray-400 w-6 text-right">{count}</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

// ─── Modal ────────────────────────────────────────────────────────────────────

function Modal({ onClose, title, children }) {
  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/70 backdrop-blur-sm" onClick={onClose}>
      <div className="card p-6 w-full max-w-md max-h-[90vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-bold">{title}</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-white p-1 min-h-[44px] min-w-[44px] flex items-center justify-center">
            <X className="w-5 h-5" />
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}

// ─── Main Export ──────────────────────────────────────────────────────────────

export default function Library({ data, updateData, onOpenGame }) {
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [sortBy, setSortBy] = useState('status');
  const [viewMode, setViewMode] = useState('grid'); // 'grid' | 'list'
  const [libraryView, setLibraryView] = useState('games'); // 'games' | 'stats'
  const [showImport, setShowImport] = useState(false);
  const [igdbFetchStatus, setIgdbFetchStatus] = useState(null); // null | 'fetching' | 'done'
  const [showAddGame, setShowAddGame] = useState(false);
  const [deleteConfirmId, setDeleteConfirmId] = useState(null);
  const [showSortFilter, setShowSortFilter] = useState(false);

  // Multi-select state
  const [selectMode, setSelectMode] = useState(false);
  const [selectedIds, setSelectedIds] = useState(new Set());
  const [bulkStatusOpen, setBulkStatusOpen] = useState(false);
  const [bulkPlatformOpen, setBulkPlatformOpen] = useState(false);
  const [bulkPlatformDraft, setBulkPlatformDraft] = useState([]);
  const [bulkCustomPlatform, setBulkCustomPlatform] = useState('');
  const [bulkDeleteConfirm, setBulkDeleteConfirm] = useState(false);
  const [bulkIgdbFetching, setBulkIgdbFetching] = useState(false);

  // Add game state
  const [addStep, setAddStep] = useState('search'); // 'search' | 'confirm'
  const [searchQuery, setSearchQuery] = useState('');
  const [igdbResults, setIgdbResults] = useState([]);
  const [igdbLoading, setIgdbLoading] = useState(false);
  const [igdbError, setIgdbError] = useState(false);
  const [selectedResult, setSelectedResult] = useState(null);
  const [manualName, setManualName] = useState('');
  const [selectedPlatforms, setSelectedPlatforms] = useState([]);
  const [customPlatform, setCustomPlatform] = useState('');
  const [manualStatus, setManualStatus] = useState('backlog');
  const [manualFranchise, setManualFranchise] = useState('');
  const [manualYearPlayed, setManualYearPlayed] = useState('');

  const fileInputRef = useRef(null);
  const searchDebounceRef = useRef(null);

  const { library } = data;

  // ── IGDB search with debounce ──────────────────────────────────────────

  useEffect(() => {
    if (!showAddGame || addStep !== 'search') return;
    if (searchQuery.trim().length < 2) { setIgdbResults([]); return; }

    clearTimeout(searchDebounceRef.current);
    setIgdbLoading(true);
    setIgdbError(false);
    searchDebounceRef.current = setTimeout(async () => {
      const results = await searchIGDB(searchQuery);
      setIgdbLoading(false);
      if (results.length === 0 && searchQuery.trim().length > 1) setIgdbError(true);
      setIgdbResults(results);
    }, 400);
  }, [searchQuery, showAddGame, addStep]);

  // ── Filter + sort ──────────────────────────────────────────────────────

  const filteredGames = library.filter(g => {
    const matchSearch = g.name.toLowerCase().includes(search.toLowerCase())
      || (g.franchise || '').toLowerCase().includes(search.toLowerCase());
    const matchStatus = statusFilter === 'all' || g.status === statusFilter;
    return matchSearch && matchStatus;
  });

  const sortedGames = [...filteredGames].sort((a, b) => {
    switch (sortBy) {
      case 'status': {
        const ao = STATUS_ORDER[a.status] ?? 9;
        const bo = STATUS_ORDER[b.status] ?? 9;
        if (ao !== bo) return ao - bo;
        return a.name.localeCompare(b.name);
      }
      case 'name':
        return a.name.localeCompare(b.name);
      case 'added':
        return new Date(b.addedAt) - new Date(a.addedAt);
      case 'played':
        return new Date(getGameLastPlayed(b)) - new Date(getGameLastPlayed(a));
      case 'playtime': {
        const at = getGamePlaytime(a);
        const bt = getGamePlaytime(b);
        if (at !== bt) return bt - at;
        return a.name.localeCompare(b.name);
      }
      case 'platform': {
        const ap = (a.platforms?.[0] || '').toLowerCase();
        const bp = (b.platforms?.[0] || '').toLowerCase();
        if (ap !== bp) return ap.localeCompare(bp);
        return a.name.localeCompare(b.name);
      }
      case 'franchise': {
        const af = (a.franchise || '').toLowerCase();
        const bf = (b.franchise || '').toLowerCase();
        if (af !== bf) return af.localeCompare(bf);
        return a.name.localeCompare(b.name);
      }
      case 'rating': {
        const ar = getGameRating(a) || 0;
        const br = getGameRating(b) || 0;
        if (ar !== br) return br - ar;
        return a.name.localeCompare(b.name);
      }
      default:
        return 0;
    }
  });

  // Status counts
  const counts = library.reduce((acc, g) => {
    acc[g.status] = (acc[g.status] || 0) + 1;
    acc.all = (acc.all || 0) + 1;
    return acc;
  }, { all: 0 });

  // ── Group headers for franchise/platform sorts ──────────────────────────

  const shouldShowGroupHeaders = sortBy === 'franchise' || sortBy === 'platform';

  function getGroupKey(game) {
    if (sortBy === 'franchise') return game.franchise || 'No Franchise';
    if (sortBy === 'platform') return game.platforms?.[0] || 'Unknown';
    return null;
  }

  // ── Import CSV ──────────────────────────────────────────────────────────

  const handleImportCSV = (e) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = async (event) => {
      const csvText = event.target.result;
      const parsedGames = parseGameryCSV(csvText);

      if (parsedGames.length === 0) {
        alert('No games found in CSV. Please check the format.');
        return;
      }

      // Build initial game entries from CSV data
      const existingNames = new Set(library.map(g => g.name.toLowerCase()));
      const toAdd = parsedGames
        .filter(g => !existingNames.has(g.name.toLowerCase()))
        .map(g => {
          const trackerType = TRACKER_TYPES[g.name] || null;
          // Map CSV platforms using our preference logic
          const mappedPlatforms = mapIGDBPlatforms(g.platforms);
          const entry = createGameEntry({
            name: g.name,
            igdbId: g.igdbId,
            platforms: mappedPlatforms,
            status: g.status,
            complexity: trackerType ? 'detailed' : 'simple',
            summary: g.summary,
          });
          entry.trackerType = trackerType;
          return entry;
        });

      if (toAdd.length === 0) {
        alert(`All ${parsedGames.length} games already in library. Nothing to import.`);
        setShowImport(false);
        return;
      }

      // Add games to library immediately (no art yet)
      updateData(prev => ({ ...prev, library: [...prev.library, ...toAdd] }));
      setShowImport(false);
      const skipped = parsedGames.length - toAdd.length;
      const skipMsg = skipped > 0 ? ` (${skipped} duplicate${skipped > 1 ? 's' : ''} skipped)` : '';

      // Now fetch IGDB data for games that have an igdbId
      const withId = toAdd.filter(g => g.igdbId);
      const withoutId = toAdd.filter(g => !g.igdbId);

      if (withId.length === 0) {
        alert(`Imported ${toAdd.length} game${toAdd.length > 1 ? 's' : ''}${skipMsg}. No IGDB IDs found — add games individually to get cover art.`);
        return;
      }

      alert(`Imported ${toAdd.length} game${toAdd.length > 1 ? 's' : ''}${skipMsg}. Fetching cover art for ${withId.length} game${withId.length > 1 ? 's' : ''} from IGDB…`);
      setIgdbFetchStatus('fetching');

      try {
        const igdbMap = await batchFetchIGDB(withId.map(g => g.igdbId));

        updateData(prev => ({
          ...prev,
          library: prev.library.map(g => {
            if (!g.igdbId || !igdbMap.has(String(g.igdbId))) return g;
            const igdbData = igdbMap.get(String(g.igdbId));

            // Prefer Mac over Windows when mapping IGDB platform data
            const preferredPlatforms = mapIGDBPlatforms(igdbData.igdbPlatforms || []);
            // Keep user's existing platforms if they already had some set, only fill if empty
            const finalPlatforms = (g.platforms && g.platforms.length > 0)
              ? g.platforms
              : preferredPlatforms;

            return {
              ...g,
              coverImageId: igdbData.coverImageId || g.coverImageId,
              coverUrl: igdbData.coverUrl || g.coverUrl,
              igdbSlug: igdbData.igdbSlug || g.igdbSlug,
              franchise: g.franchise || igdbData.franchise,
              firstReleaseDate: g.firstReleaseDate || igdbData.firstReleaseDate,
              platforms: finalPlatforms,
              genres: igdbData.genres || g.genres || [],
              themes: igdbData.themes || g.themes || [],
              gameModes: igdbData.gameModes || g.gameModes || [],
              playerPerspectives: igdbData.playerPerspectives || g.playerPerspectives || [],
              developers: igdbData.developers || g.developers || [],
              publishers: igdbData.publishers || g.publishers || [],
            };
          }),
        }));
      } catch (err) {
        console.error('IGDB batch fetch failed:', err);
      } finally {
        setIgdbFetchStatus('done');
        setTimeout(() => setIgdbFetchStatus(null), 3000);
      }
    };
    reader.readAsText(file);
    if (fileInputRef.current) fileInputRef.current.value = '';
  };

  // ── Select IGDB result → confirm step ──────────────────────────────────

  const handleSelectIGDBResult = (result) => {
    setSelectedResult(result);
    setManualName(result.name);
    setManualFranchise(result.franchise || '');
    setManualYearPlayed('');
    // Pre-fill platform from result if it matches a preset
    const matchedPreset = PRESET_PLATFORMS.find(p =>
      (result.platforms || []).some(rp => rp.toLowerCase().includes(p.toLowerCase()))
    );
    setSelectedPlatforms(matchedPreset ? [matchedPreset] : []);
    setAddStep('confirm');
  };

  const handleSkipIGDB = () => {
    setSelectedResult(null);
    setManualName(searchQuery);
    setManualFranchise('');
    setSelectedPlatforms([]);
    setAddStep('confirm');
  };

  // ── Add game (confirm step) ─────────────────────────────────────────────

  const handleAddGame = () => {
    if (!manualName.trim()) return;
    const trackerType = TRACKER_TYPES[manualName.trim()] || null;
    const allPlatforms = [
      ...selectedPlatforms,
      ...(customPlatform.trim() ? [customPlatform.trim()] : []),
    ];
    const game = createGameEntry({
      name: manualName.trim(),
      platforms: allPlatforms,
      status: manualStatus,
      complexity: trackerType ? 'detailed' : 'simple',
    });
    game.trackerType = trackerType;
    game.franchise = manualFranchise.trim() || null;
    game.yearPlayed = manualYearPlayed.trim() ? parseInt(manualYearPlayed.trim(), 10) : null;

    if (selectedResult) {
      game.igdbId = selectedResult.igdbId;
      game.igdbSlug = selectedResult.igdbSlug || null;
      game.coverImageId = selectedResult.coverImageId || null;
      game.coverUrl = selectedResult.coverUrl || null;
      game.firstReleaseDate = selectedResult.firstReleaseDate || null;
      game.genres = selectedResult.genres || [];
      game.themes = selectedResult.themes || [];
      game.gameModes = selectedResult.gameModes || [];
      game.playerPerspectives = selectedResult.playerPerspectives || [];
      game.developers = selectedResult.developers || [];
      game.publishers = selectedResult.publishers || [];
    }

    updateData(prev => ({ ...prev, library: [...prev.library, game] }));
    resetAddGame();
  };

  const resetAddGame = () => {
    setShowAddGame(false);
    setAddStep('search');
    setSearchQuery('');
    setIgdbResults([]);
    setIgdbLoading(false);
    setIgdbError(false);
    setSelectedResult(null);
    setManualName('');
    setManualFranchise('');
    setManualYearPlayed('');
    setSelectedPlatforms([]);
    setCustomPlatform('');
    setManualStatus('backlog');
  };

  const togglePlatform = (p) => {
    setSelectedPlatforms(prev =>
      prev.includes(p) ? prev.filter(x => x !== p) : [...prev, p]
    );
  };

  // ── Delete game ─────────────────────────────────────────────────────────

  const handleDeleteGame = (gameId) => {
    updateData(prev => ({ ...prev, library: prev.library.filter(g => g.id !== gameId) }));
    setDeleteConfirmId(null);
  };

  // ── Update game status ──────────────────────────────────────────────────

  const handleUpdateStatus = (gameId, status) => {
    updateData(prev => ({
      ...prev,
      library: prev.library.map(g => g.id === gameId ? { ...g, status } : g),
    }));
  };

  // ── Multi-select helpers ────────────────────────────────────────────────

  const toggleSelectMode = () => {
    setSelectMode(s => !s);
    setSelectedIds(new Set());
    setBulkStatusOpen(false);
    setBulkPlatformOpen(false);
    setBulkDeleteConfirm(false);
  };

  const toggleSelectGame = (id) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  };

  const selectAll = (visibleGames) => {
    setSelectedIds(new Set(visibleGames.map(g => g.id)));
  };

  const deselectAll = () => setSelectedIds(new Set());

  const handleBulkDelete = () => {
    updateData(prev => ({ ...prev, library: prev.library.filter(g => !selectedIds.has(g.id)) }));
    setSelectedIds(new Set());
    setBulkDeleteConfirm(false);
    setSelectMode(false);
  };

  const handleBulkStatus = (status) => {
    updateData(prev => ({
      ...prev,
      library: prev.library.map(g => selectedIds.has(g.id) ? { ...g, status } : g),
    }));
    setBulkStatusOpen(false);
  };

  const handleBulkPlatform = () => {
    const allPlatforms = [
      ...bulkPlatformDraft,
      ...(bulkCustomPlatform.trim() && !bulkPlatformDraft.includes(bulkCustomPlatform.trim())
        ? [bulkCustomPlatform.trim()] : []),
    ];
    updateData(prev => ({
      ...prev,
      library: prev.library.map(g => selectedIds.has(g.id) ? { ...g, platforms: allPlatforms } : g),
    }));
    setBulkPlatformOpen(false);
    setBulkPlatformDraft([]);
    setBulkCustomPlatform('');
  };

  const handleBulkRefreshIGDB = async () => {
    setBulkIgdbFetching(true);
    const selected = library.filter(g => selectedIds.has(g.id));
    const withId = selected.filter(g => g.igdbId);
    const withoutId = selected.filter(g => !g.igdbId);

    try {
      // Batch-fetch games that have an IGDB ID
      const igdbMap = withId.length > 0
        ? await batchFetchIGDB(withId.map(g => g.igdbId))
        : new Map();

      // Name-search for games without an ID
      const nameResults = await Promise.all(
        withoutId.map(async g => {
          const result = await fetchIGDBByName(g.name);
          return result ? { gameId: g.id, data: result } : null;
        })
      );

      updateData(prev => ({
        ...prev,
        library: prev.library.map(g => {
          if (!selectedIds.has(g.id)) return g;
          if (g.igdbId && igdbMap.has(String(g.igdbId))) {
            const d = igdbMap.get(String(g.igdbId));
            const preferredPlatforms = mapIGDBPlatforms(d.igdbPlatforms || []);
            return {
              ...g,
              coverImageId: d.coverImageId || g.coverImageId,
              coverUrl: d.coverUrl || g.coverUrl,
              igdbSlug: d.igdbSlug || g.igdbSlug,
              franchise: g.franchise || d.franchise,
              firstReleaseDate: g.firstReleaseDate || d.firstReleaseDate,
              genres: d.genres?.length ? d.genres : g.genres,
              themes: d.themes?.length ? d.themes : g.themes,
              gameModes: d.gameModes?.length ? d.gameModes : g.gameModes,
              playerPerspectives: d.playerPerspectives?.length ? d.playerPerspectives : g.playerPerspectives,
              developers: d.developers?.length ? d.developers : g.developers,
              publishers: d.publishers?.length ? d.publishers : g.publishers,
              platforms: (g.platforms && g.platforms.length > 0) ? g.platforms : preferredPlatforms,
            };
          }
          // Check name-results
          const nameMatch = nameResults.find(r => r && r.gameId === g.id);
          if (nameMatch) {
            const d = nameMatch.data;
            const preferredPlatforms = mapIGDBPlatforms(d.platforms || []);
            return {
              ...g,
              igdbId: d.igdbId || g.igdbId,
              igdbSlug: d.igdbSlug || g.igdbSlug,
              coverImageId: d.coverImageId || g.coverImageId,
              coverUrl: d.coverUrl || g.coverUrl,
              franchise: g.franchise || d.franchise,
              firstReleaseDate: g.firstReleaseDate || d.firstReleaseDate,
              genres: d.genres?.length ? d.genres : g.genres,
              themes: d.themes?.length ? d.themes : g.themes,
              gameModes: d.gameModes?.length ? d.gameModes : g.gameModes,
              playerPerspectives: d.playerPerspectives?.length ? d.playerPerspectives : g.playerPerspectives,
              developers: d.developers?.length ? d.developers : g.developers,
              publishers: d.publishers?.length ? d.publishers : g.publishers,
              platforms: (g.platforms && g.platforms.length > 0) ? g.platforms : preferredPlatforms,
            };
          }
          return g;
        }),
      }));
    } catch (e) {
      console.error('Bulk IGDB refresh failed:', e);
    } finally {
      setBulkIgdbFetching(false);
    }
  };

  const handleBulkExport = () => {
    const selected = library.filter(g => selectedIds.has(g.id));
    const rows = [
      ['Name', 'Status', 'Platforms', 'Year Played', 'IGDB ID', 'Franchise', 'Developer', 'Publisher', 'Genres', 'First Release Date', 'Rating', 'Time Played (min)'],
      ...selected.map(g => {
        const playtime = (g.saves || []).reduce((total, save) => {
          if (typeof save.totalPlaytime === 'number') return total + save.totalPlaytime;
          if (Array.isArray(save.sessions)) return total + save.sessions.reduce((a, s) => a + (s.duration || 0), 0);
          if (Array.isArray(save.runs)) return total + save.runs.reduce((a, r) => a + (r.duration || 0), 0);
          return total;
        }, 0);
        const rating = g.saves?.[0]?.rating ?? g.userRating ?? '';
        return [
          g.name,
          g.status,
          (g.platforms || []).join('; '),
          g.yearPlayed || '',
          g.igdbId || '',
          g.franchise || '',
          (g.developers || []).join('; '),
          (g.publishers || []).join('; '),
          (g.genres || []).join('; '),
          g.firstReleaseDate || '',
          rating,
          playtime > 0 ? Math.round(playtime / 60) : '',
        ].map(v => `"${String(v).replace(/"/g, '""')}"`);
      }),
    ];
    const csv = rows.map(r => r.join(',')).join('\n');
    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `levelselect-export-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  // ─── Render ───────────────────────────────────────────────────────────────

  return (
    <div className="min-h-screen bg-gradient-to-b from-slate-900 via-slate-800 to-slate-900 safe-area-bottom">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-slate-900/90 backdrop-blur border-b border-white/10">
        <div className="max-w-7xl mx-auto px-4 py-3">
          <div className="flex items-center justify-between mb-3">
            <button
              onClick={() => setLibraryView('games')}
              className="flex items-center gap-2 hover:opacity-80 transition-opacity"
            >
              <Gamepad2 className="w-6 h-6 text-purple-400" />
              <h1 className="text-xl font-bold">LevelSelect</h1>
            </button>
            <div className="flex gap-2">
              <a
                href="https://www.dekudeals.com/wishlist/cwnns56whw"
                target="_blank"
                rel="noopener noreferrer"
                className="btn-secondary !px-3 text-sm gap-1.5"
                title="Deku Deals Wishlist"
              >
                <ShoppingBag className="w-4 h-4" />
                <span className="hidden sm:inline">Wishlist</span>
              </a>
              <button
                onClick={() => setLibraryView(v => v === 'games' ? 'stats' : 'games')}
                className={`btn-secondary !px-3 text-sm gap-1.5 ${libraryView === 'stats' ? 'text-purple-300 border-purple-500/50' : ''}`}
                title="Library Stats"
              >
                <BarChart2 className="w-4 h-4" />
                <span className="hidden sm:inline">Stats</span>
              </button>
              <button
                onClick={() => setShowImport(true)}
                className="btn-secondary !px-3 text-sm gap-1.5"
              >
                <Upload className="w-4 h-4" />
                <span className="hidden sm:inline">Import</span>
              </button>
              <button
                onClick={() => setShowAddGame(true)}
                className="btn-primary !px-3 text-sm gap-1.5"
              >
                <Plus className="w-4 h-4" />
                <span className="hidden sm:inline">Add Game</span>
              </button>
            </div>
          </div>

          {/* IGDB fetch progress indicator */}
          {igdbFetchStatus && (
            <div className={`text-xs px-3 py-1.5 rounded-lg mb-2 flex items-center gap-2 ${
              igdbFetchStatus === 'fetching'
                ? 'bg-purple-900/40 text-purple-300'
                : 'bg-green-900/40 text-green-300'
            }`}>
              {igdbFetchStatus === 'fetching' ? (
                <><span className="animate-pulse">⏳</span> Fetching cover art from IGDB…</>
              ) : (
                <><span>✓</span> Cover art loaded!</>
              )}
            </div>
          )}

          {libraryView === 'games' && (
            <>
              {/* Search */}
              <div className="relative mb-3">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500" />
                <input
                  type="text"
                  placeholder="Search games or franchises…"
                  value={search}
                  onChange={e => setSearch(e.target.value)}
                  className="input-field pl-10 pr-10"
                />
                {search && (
                  <button onClick={() => setSearch('')} className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-500 hover:text-white">
                    <X className="w-4 h-4" />
                  </button>
                )}
              </div>

              {/* Filter / sort / view row */}
              <div className="flex items-center gap-2 mb-3">
                {/* Status tabs — scrollable */}
                <div className="flex gap-1 overflow-x-auto scroll-smooth-ios flex-1">
                  {['all', 'playing', 'paused', 'backlog', 'completed', 'shelved', 'abandoned'].map(status => (
                    <button
                      key={status}
                      onClick={() => setStatusFilter(status)}
                      className={`${statusFilter === status ? 'tab-button-active' : 'tab-button-inactive'} whitespace-nowrap text-xs`}
                    >
                      {status === 'all' ? 'All' : STATUS_LABELS[status]} ({counts[status] || 0})
                    </button>
                  ))}
                </div>

                {/* Sort + view toggle */}
                <div className="flex gap-1.5 flex-shrink-0">
                  <div className="relative">
                    <button
                      onClick={() => setShowSortFilter(o => !o)}
                      className="btn-secondary !px-2.5 !py-2 !min-h-0 text-xs gap-1"
                    >
                      <Filter className="w-3.5 h-3.5" />
                      <span className="hidden sm:inline">Sort</span>
                    </button>
                    {showSortFilter && (
                      <div className="absolute right-0 top-full mt-1 z-20 bg-slate-800 border border-white/10 rounded-lg shadow-xl min-w-[140px] overflow-hidden">
                        {SORT_OPTIONS.map(opt => (
                          <button
                            key={opt.value}
                            onClick={() => { setSortBy(opt.value); setShowSortFilter(false); }}
                            className={`w-full text-left px-3 py-2 text-xs flex items-center gap-2 hover:bg-white/10 transition-colors ${sortBy === opt.value ? 'text-purple-300' : 'text-gray-400'}`}
                          >
                            {sortBy === opt.value && <Check className="w-3 h-3" />}
                            {opt.label}
                          </button>
                        ))}
                      </div>
                    )}
                  </div>

                  <button
                    onClick={() => setViewMode(v => v === 'grid' ? 'list' : 'grid')}
                    className="btn-secondary !px-2.5 !py-2 !min-h-0"
                    title={viewMode === 'grid' ? 'Switch to list view' : 'Switch to grid view'}
                  >
                    {viewMode === 'grid' ? <List className="w-3.5 h-3.5" /> : <LayoutGrid className="w-3.5 h-3.5" />}
                  </button>

                  <button
                    onClick={toggleSelectMode}
                    className={`btn-secondary !px-2.5 !py-2 !min-h-0 text-xs gap-1 ${selectMode ? 'ring-1 ring-purple-500 text-purple-300' : ''}`}
                    title="Select multiple games"
                  >
                    <CheckSquare className="w-3.5 h-3.5" />
                    <span className="hidden sm:inline">Select</span>
                  </button>
                </div>
              </div>
            </>
          )}
        </div>
      </div>

      {/* Content */}
      <div className="max-w-7xl mx-auto px-4 py-4">

        {/* ── Bulk action bar ── */}
        {selectMode && libraryView === 'games' && (
          <div className="card mb-3 p-3 flex flex-wrap items-center gap-2 border-purple-500/30 bg-purple-950/30">
            <span className="text-sm font-medium text-purple-300 mr-1">
              {selectedIds.size} selected
            </span>

            {/* Select all / none */}
            <button
              onClick={() => selectedIds.size === sortedGames.length ? deselectAll() : selectAll(sortedGames)}
              className="text-xs text-gray-400 hover:text-white underline"
            >
              {selectedIds.size === sortedGames.length ? 'Deselect all' : 'Select all'}
            </button>

            <div className="flex-1" />

            {/* IGDB Refresh */}
            <button
              onClick={handleBulkRefreshIGDB}
              disabled={selectedIds.size === 0 || bulkIgdbFetching}
              className="btn-secondary !px-3 !py-1.5 !min-h-0 text-xs gap-1.5 disabled:opacity-40"
            >
              <RefreshCw className={`w-3.5 h-3.5 ${bulkIgdbFetching ? 'animate-spin' : ''}`} />
              {bulkIgdbFetching ? 'Fetching…' : 'Get Art'}
            </button>

            {/* Status picker */}
            <div className="relative">
              <button
                onClick={() => { setBulkStatusOpen(o => !o); setBulkPlatformOpen(false); }}
                disabled={selectedIds.size === 0}
                className="btn-secondary !px-3 !py-1.5 !min-h-0 text-xs gap-1 disabled:opacity-40"
              >
                Status <ChevronDown className="w-3 h-3" />
              </button>
              {bulkStatusOpen && (
                <div className="absolute right-0 top-full mt-1 z-30 bg-slate-800 border border-white/10 rounded-xl shadow-xl overflow-hidden min-w-[150px]">
                  {Object.entries(STATUS_LABELS).map(([val, label]) => (
                    <button
                      key={val}
                      onClick={() => handleBulkStatus(val)}
                      className="w-full text-left px-3 py-2.5 text-sm flex items-center gap-2.5 hover:bg-white/10 transition-colors"
                    >
                      <span className={`w-2 h-2 rounded-full ${STATUS_COLORS[val]}`} />
                      {label}
                    </button>
                  ))}
                </div>
              )}
            </div>

            {/* Platform picker */}
            <div className="relative">
              <button
                onClick={() => { setBulkPlatformOpen(o => !o); setBulkStatusOpen(false); if (!bulkPlatformOpen) { setBulkPlatformDraft([]); setBulkCustomPlatform(''); } }}
                disabled={selectedIds.size === 0}
                className="btn-secondary !px-3 !py-1.5 !min-h-0 text-xs gap-1 disabled:opacity-40"
              >
                Platform <ChevronDown className="w-3 h-3" />
              </button>
              {bulkPlatformOpen && (
                <div className="absolute right-0 top-full mt-1 z-30 bg-slate-800 border border-white/10 rounded-xl shadow-xl p-3 min-w-[220px] space-y-2">
                  <div className="text-xs text-gray-400 mb-1">Set platforms for all selected games</div>
                  <div className="flex flex-wrap gap-1.5">
                    {['Switch', 'Switch 2', 'Mac', 'iOS', 'Recalbox'].map(p => (
                      <button
                        key={p}
                        onClick={() => setBulkPlatformDraft(prev => prev.includes(p) ? prev.filter(x => x !== p) : [...prev, p])}
                        className={`px-2.5 py-1 rounded-full text-xs font-medium transition-colors ${bulkPlatformDraft.includes(p) ? 'bg-purple-600 text-white' : 'bg-white/10 text-gray-400 hover:bg-white/20'}`}
                      >
                        {p}
                      </button>
                    ))}
                    {bulkPlatformDraft.filter(p => !['Switch', 'Switch 2', 'Mac', 'iOS', 'Recalbox'].includes(p)).map(p => (
                      <button
                        key={p}
                        onClick={() => setBulkPlatformDraft(prev => prev.filter(x => x !== p))}
                        className="px-2.5 py-1 rounded-full text-xs font-medium bg-blue-600 text-white"
                      >
                        {p} ×
                      </button>
                    ))}
                  </div>
                  <div className="flex gap-1.5">
                    <input
                      type="text"
                      placeholder="Other platform…"
                      value={bulkCustomPlatform}
                      onChange={e => setBulkCustomPlatform(e.target.value)}
                      onKeyDown={e => { if (e.key === 'Enter' && bulkCustomPlatform.trim()) { setBulkPlatformDraft(p => [...p, bulkCustomPlatform.trim()]); setBulkCustomPlatform(''); }}}
                      className="input-field text-xs flex-1 !py-1"
                    />
                    <button
                      onClick={() => { if (bulkCustomPlatform.trim()) { setBulkPlatformDraft(p => [...p, bulkCustomPlatform.trim()]); setBulkCustomPlatform(''); }}}
                      className="btn-secondary !px-2 !py-1 !min-h-0"
                    >
                      <Plus className="w-3.5 h-3.5" />
                    </button>
                  </div>
                  <div className="flex gap-1.5 pt-1 border-t border-white/10">
                    <button onClick={handleBulkPlatform} className="btn-primary flex-1 text-xs py-1.5 gap-1">
                      <Check className="w-3.5 h-3.5" /> Apply
                    </button>
                    <button onClick={() => setBulkPlatformOpen(false)} className="btn-secondary flex-1 text-xs py-1.5">
                      Cancel
                    </button>
                  </div>
                </div>
              )}
            </div>

            {/* Export */}
            <button
              onClick={handleBulkExport}
              disabled={selectedIds.size === 0}
              className="btn-secondary !px-3 !py-1.5 !min-h-0 text-xs gap-1.5 disabled:opacity-40"
            >
              <Download className="w-3.5 h-3.5" /> Export
            </button>

            {/* Delete */}
            <button
              onClick={() => setBulkDeleteConfirm(true)}
              disabled={selectedIds.size === 0}
              className="text-xs text-red-400 hover:text-red-300 disabled:opacity-40 flex items-center gap-1 px-2 py-1.5"
            >
              <Trash2 className="w-3.5 h-3.5" /> Delete
            </button>

            {/* Cancel select mode */}
            <button
              onClick={toggleSelectMode}
              className="btn-secondary !px-3 !py-1.5 !min-h-0 text-xs"
            >
              Done
            </button>
          </div>
        )}

        {libraryView === 'stats' ? (
          <LibraryStats library={library} />
        ) : library.length === 0 ? (
          <div className="card p-12 text-center">
            <Gamepad2 className="w-16 h-16 text-purple-400 mx-auto mb-4 opacity-50" />
            <h2 className="text-xl font-bold mb-2">No games yet</h2>
            <p className="text-gray-400 mb-6">Import your Gamery library or add games manually.</p>
            <div className="flex gap-3 justify-center flex-wrap">
              <button onClick={() => setShowImport(true)} className="btn-primary gap-2">
                <Upload className="w-4 h-4" /> Import from Gamery
              </button>
              <button onClick={() => setShowAddGame(true)} className="btn-secondary gap-2">
                <Plus className="w-4 h-4" /> Add Game
              </button>
            </div>
          </div>
        ) : sortedGames.length === 0 ? (
          <div className="text-center py-12 text-gray-400">No games match your search.</div>
        ) : viewMode === 'list' ? (
          <div className="space-y-1">
            {shouldShowGroupHeaders
              ? (() => {
                  const groups = [];
                  let lastKey = null;
                  sortedGames.forEach(game => {
                    const key = getGroupKey(game);
                    if (key !== lastKey) { groups.push({ key, games: [] }); lastKey = key; }
                    groups[groups.length - 1].games.push(game);
                  });
                  return groups.map(({ key, games }) => (
                    <div key={key}>
                      <div className="text-xs font-semibold text-gray-500 uppercase tracking-wider px-1 pt-4 pb-1 first:pt-0">
                        {key}
                      </div>
                      {games.map(game => (
                        <GameCard
                          key={game.id}
                          game={game}
                          viewMode="list"
                          onOpen={() => onOpenGame(game.id)}
                          onUpdateStatus={status => handleUpdateStatus(game.id, status)}
                          onDelete={() => setDeleteConfirmId(game.id)}
                          selectMode={selectMode}
                          selected={selectedIds.has(game.id)}
                          onToggleSelect={() => toggleSelectGame(game.id)}
                        />
                      ))}
                    </div>
                  ));
                })()
              : sortedGames.map(game => (
                  <GameCard
                    key={game.id}
                    game={game}
                    viewMode="list"
                    onOpen={() => onOpenGame(game.id)}
                    onUpdateStatus={status => handleUpdateStatus(game.id, status)}
                    onDelete={() => setDeleteConfirmId(game.id)}
                    selectMode={selectMode}
                    selected={selectedIds.has(game.id)}
                    onToggleSelect={() => toggleSelectGame(game.id)}
                  />
                ))
            }
          </div>
        ) : (
          // Grid view
          shouldShowGroupHeaders
            ? (() => {
                const groups = [];
                let lastKey = null;
                sortedGames.forEach(game => {
                  const key = getGroupKey(game);
                  if (key !== lastKey) { groups.push({ key, games: [] }); lastKey = key; }
                  groups[groups.length - 1].games.push(game);
                });
                return (
                  <div className="space-y-6">
                    {groups.map(({ key, games }) => (
                      <div key={key}>
                        <div className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">
                          {key}
                        </div>
                        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-3">
                          {games.map(game => (
                            <GameCard
                              key={game.id}
                              game={game}
                              viewMode="grid"
                              onOpen={() => onOpenGame(game.id)}
                              onUpdateStatus={status => handleUpdateStatus(game.id, status)}
                              onDelete={() => setDeleteConfirmId(game.id)}
                              selectMode={selectMode}
                              selected={selectedIds.has(game.id)}
                              onToggleSelect={() => toggleSelectGame(game.id)}
                            />
                          ))}
                        </div>
                      </div>
                    ))}
                  </div>
                );
              })()
            : (
              <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-3">
                {sortedGames.map(game => (
                  <GameCard
                    key={game.id}
                    game={game}
                    viewMode="grid"
                    onOpen={() => onOpenGame(game.id)}
                    onUpdateStatus={status => handleUpdateStatus(game.id, status)}
                    onDelete={() => setDeleteConfirmId(game.id)}
                    selectMode={selectMode}
                    selected={selectedIds.has(game.id)}
                    onToggleSelect={() => toggleSelectGame(game.id)}
                  />
                ))}
              </div>
            )
        )}
      </div>

      {/* ── Add Game Modal ──────────────────────────────────────────────────── */}
      {showAddGame && (
        <Modal onClose={resetAddGame} title={addStep === 'search' ? 'Add Game' : 'Confirm Game Details'}>
          {addStep === 'search' ? (
            <div className="space-y-3">
              <p className="text-gray-400 text-sm">Search IGDB to auto-fill cover art and franchise data.</p>
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500" />
                <input
                  type="text"
                  placeholder="Search for a game…"
                  value={searchQuery}
                  onChange={e => setSearchQuery(e.target.value)}
                  className="input-field pl-10"
                  autoFocus
                />
              </div>

              {igdbLoading && (
                <div className="text-center py-4 text-gray-500 text-sm animate-pulse">Searching IGDB…</div>
              )}

              {!igdbLoading && igdbResults.length > 0 && (
                <div className="space-y-1">
                  {igdbResults.map(r => (
                    <IGDBSearchResult key={r.igdbId} result={r} onSelect={handleSelectIGDBResult} />
                  ))}
                </div>
              )}

              {!igdbLoading && igdbError && searchQuery.trim().length >= 2 && (
                <p className="text-gray-500 text-sm text-center">No IGDB results. You can still add it manually.</p>
              )}

              {/* Skip IGDB */}
              {searchQuery.trim().length > 0 && (
                <button onClick={handleSkipIGDB} className="btn-secondary w-full text-sm">
                  Add "{searchQuery}" without IGDB data
                </button>
              )}
            </div>
          ) : (
            <div className="space-y-4">
              {/* Selected cover preview */}
              {selectedResult?.coverUrl && (
                <div className="flex items-center gap-3 p-3 bg-black/30 rounded-lg">
                  <img src={selectedResult.coverUrl} alt={selectedResult.name} className="w-12 h-16 object-cover rounded" />
                  <div>
                    <div className="font-medium text-sm">{selectedResult.name}</div>
                    {selectedResult.franchise && <div className="text-xs text-gray-500">{selectedResult.franchise}</div>}
                    {selectedResult.firstReleaseDate && <div className="text-xs text-gray-600">{selectedResult.firstReleaseDate}</div>}
                  </div>
                  <button onClick={() => setAddStep('search')} className="ml-auto text-gray-500 hover:text-white text-xs">
                    Change
                  </button>
                </div>
              )}

              {/* Name */}
              <div>
                <label className="text-xs text-gray-400 mb-1 block">Game Name</label>
                <input
                  type="text"
                  placeholder="Game name"
                  value={manualName}
                  onChange={e => setManualName(e.target.value)}
                  className="input-field"
                />
              </div>

              {/* Franchise */}
              <div>
                <label className="text-xs text-gray-400 mb-1 block">Franchise / Series (optional)</label>
                <input
                  type="text"
                  placeholder="e.g. Zelda, Mario, Metroid…"
                  value={manualFranchise}
                  onChange={e => setManualFranchise(e.target.value)}
                  className="input-field"
                />
              </div>

              {/* Platform */}
              <div>
                <label className="text-xs text-gray-400 mb-1 block">Platform</label>
                <div className="flex flex-wrap gap-2 mb-2">
                  {PRESET_PLATFORMS.map(p => (
                    <button
                      key={p}
                      onClick={() => togglePlatform(p)}
                      className={`px-3 py-1.5 rounded-full text-xs font-medium transition-colors ${
                        selectedPlatforms.includes(p)
                          ? 'bg-purple-600 text-white'
                          : 'bg-white/10 text-gray-400 hover:bg-white/20'
                      }`}
                    >
                      {p}
                    </button>
                  ))}
                </div>
                <input
                  type="text"
                  placeholder="Other platform…"
                  value={customPlatform}
                  onChange={e => setCustomPlatform(e.target.value)}
                  className="input-field text-sm"
                />
              </div>

              {/* Status */}
              <div>
                <label className="text-xs text-gray-400 mb-1 block">Status</label>
                <div className="flex flex-wrap gap-2">
                  {Object.entries(STATUS_LABELS).map(([val, label]) => (
                    <button
                      key={val}
                      onClick={() => setManualStatus(val)}
                      className={`px-3 py-1.5 rounded-full text-xs font-medium transition-colors ${
                        manualStatus === val
                          ? `${STATUS_COLORS[val]} text-white`
                          : 'bg-white/10 text-gray-400 hover:bg-white/20'
                      }`}
                    >
                      {label}
                    </button>
                  ))}
                </div>
              </div>

              {/* Year Played */}
              <div>
                <label className="text-xs text-gray-400 mb-1 block">Year Played / Beaten (optional)</label>
                <input
                  type="number"
                  placeholder={`e.g. ${new Date().getFullYear()}`}
                  min="1970"
                  max={new Date().getFullYear() + 1}
                  value={manualYearPlayed}
                  onChange={e => setManualYearPlayed(e.target.value)}
                  className="input-field text-sm"
                />
              </div>

              <button
                onClick={handleAddGame}
                disabled={!manualName.trim()}
                className="btn-primary w-full disabled:opacity-50"
              >
                Add to Library
              </button>
            </div>
          )}
        </Modal>
      )}

      {/* ── Import Modal ─────────────────────────────────────────────────────── */}
      {showImport && (
        <Modal onClose={() => setShowImport(false)} title="Import from Gamery">
          <p className="text-gray-400 mb-4 text-sm">
            Export your library from Gamery as CSV, then select the file below.
          </p>
          <input
            ref={fileInputRef}
            type="file"
            accept=".csv"
            onChange={handleImportCSV}
            className="block w-full text-sm text-gray-400
              file:mr-4 file:py-2.5 file:px-4 file:rounded-lg file:border-0
              file:text-sm file:font-medium file:bg-purple-600 file:text-white
              file:cursor-pointer hover:file:bg-purple-700 file:min-h-[44px]"
          />
        </Modal>
      )}

      {/* ── Delete Confirm Modal ─────────────────────────────────────────────── */}
      {deleteConfirmId && (() => {
        const game = library.find(g => g.id === deleteConfirmId);
        return (
          <Modal onClose={() => setDeleteConfirmId(null)} title="Remove Game">
            <p className="text-gray-300 mb-2">
              Remove <span className="font-semibold text-white">{game?.name}</span> from your library?
            </p>
            <p className="text-gray-500 text-sm mb-5">
              This will delete all saves and tracking data. This cannot be undone.
            </p>
            <div className="flex gap-3">
              <button onClick={() => setDeleteConfirmId(null)} className="btn-secondary flex-1">Cancel</button>
              <button
                onClick={() => handleDeleteGame(deleteConfirmId)}
                className="flex-1 bg-red-600 hover:bg-red-700 text-white font-medium py-2.5 px-4 rounded-lg transition-colors"
              >
                Remove
              </button>
            </div>
          </Modal>
        );
      })()}

      {/* Bulk delete confirmation */}
      {bulkDeleteConfirm && (
        <Modal onClose={() => setBulkDeleteConfirm(false)} title="Delete Games">
          <p className="text-gray-300 mb-1">
            Permanently delete <span className="text-white font-semibold">{selectedIds.size} game{selectedIds.size !== 1 ? 's' : ''}</span>?
          </p>
          <p className="text-gray-500 text-sm mb-6">All tracking data and saves will be lost. This cannot be undone.</p>
          <div className="flex gap-3">
            <button onClick={() => setBulkDeleteConfirm(false)} className="btn-secondary flex-1">Cancel</button>
            <button
              onClick={handleBulkDelete}
              className="flex-1 bg-red-600 hover:bg-red-700 text-white font-medium py-2.5 px-4 rounded-lg transition-colors"
            >
              Delete {selectedIds.size} game{selectedIds.size !== 1 ? 's' : ''}
            </button>
          </div>
        </Modal>
      )}
    </div>
  );
}
