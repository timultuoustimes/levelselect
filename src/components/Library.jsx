import React, { useState, useRef } from 'react';
import { parseGameryCSV } from '../utils/csvParser.js';
import { createGameEntry } from '../utils/factories.js';
import { Search, Upload, Plus, Gamepad2, Trash2 } from 'lucide-react';

const STATUS_COLORS = {
  playing: 'bg-green-500',
  completed: 'bg-blue-500',
  backlog: 'bg-gray-500',
  abandoned: 'bg-red-500',
};

const STATUS_LABELS = {
  playing: 'Playing',
  completed: 'Completed',
  backlog: 'Backlog',
  abandoned: 'Abandoned',
};

// Games that have dedicated detailed trackers
const TRACKER_TYPES = {
  'Hades': 'hades',
  'Lone Ruin': 'lone-ruin',
  'LONE RUIN': 'lone-ruin',
};

export default function Library({ data, updateData, onOpenGame }) {
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [showImport, setShowImport] = useState(false);
  const [showAddGame, setShowAddGame] = useState(false);
  const [newGameName, setNewGameName] = useState('');
  const [newGamePlatform, setNewGamePlatform] = useState('');
  const [deleteConfirmId, setDeleteConfirmId] = useState(null);
  const fileInputRef = useRef(null);

  const { library } = data;

  // Filter games
  const filteredGames = library.filter(g => {
    const matchesSearch = g.name.toLowerCase().includes(search.toLowerCase());
    const matchesStatus = statusFilter === 'all' || g.status === statusFilter;
    return matchesSearch && matchesStatus;
  });

  // Sort: Playing first, then by name
  const sortedGames = [...filteredGames].sort((a, b) => {
    const statusOrder = { playing: 0, backlog: 1, completed: 2, abandoned: 3 };
    const aDiff = statusOrder[a.status] ?? 9;
    const bDiff = statusOrder[b.status] ?? 9;
    if (aDiff !== bDiff) return aDiff - bDiff;
    return a.name.localeCompare(b.name);
  });

  // Status counts
  const counts = library.reduce((acc, g) => {
    acc[g.status] = (acc[g.status] || 0) + 1;
    acc.all = (acc.all || 0) + 1;
    return acc;
  }, { all: 0 });

  // Import CSV
  const handleImportCSV = (e) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (event) => {
      const csvText = event.target.result;
      const parsedGames = parseGameryCSV(csvText);

      if (parsedGames.length === 0) {
        alert('No games found in CSV. Please check the format.');
        return;
      }

      const newGames = parsedGames.map(g => {
        const trackerType = TRACKER_TYPES[g.name] || null;
        return createGameEntry({
          name: g.name,
          igdbId: g.igdbId,
          platforms: g.platforms,
          status: g.status,
          complexity: trackerType ? 'detailed' : 'simple',
          summary: g.summary,
        });
      });

      newGames.forEach(g => {
        g.trackerType = TRACKER_TYPES[g.name] || null;
      });

      const existingNames = new Set(library.map(g => g.name.toLowerCase()));
      const toAdd = newGames.filter(g => !existingNames.has(g.name.toLowerCase()));

      updateData(prev => ({
        ...prev,
        library: [...prev.library, ...toAdd],
      }));

      setShowImport(false);
      alert(`Imported ${toAdd.length} new games (${parsedGames.length - toAdd.length} duplicates skipped).`);
    };
    reader.readAsText(file);
    if (fileInputRef.current) fileInputRef.current.value = '';
  };

  // Add game manually
  const handleAddGame = () => {
    if (!newGameName.trim()) return;
    const trackerType = TRACKER_TYPES[newGameName.trim()] || null;
    const game = createGameEntry({
      name: newGameName.trim(),
      platforms: newGamePlatform ? [newGamePlatform.trim()] : [],
      status: 'backlog',
      complexity: trackerType ? 'detailed' : 'simple',
    });
    game.trackerType = trackerType;

    updateData(prev => ({
      ...prev,
      library: [...prev.library, game],
    }));

    setNewGameName('');
    setNewGamePlatform('');
    setShowAddGame(false);
  };

  // Delete game
  const handleDeleteGame = (gameId) => {
    updateData(prev => ({
      ...prev,
      library: prev.library.filter(g => g.id !== gameId),
    }));
    setDeleteConfirmId(null);
  };

  return (
    <div className="min-h-screen bg-gradient-to-b from-slate-900 via-slate-800 to-slate-900 safe-area-bottom">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-slate-900/90 backdrop-blur border-b border-white/10">
        <div className="max-w-7xl mx-auto px-4 py-3">
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-2">
              <Gamepad2 className="w-6 h-6 text-purple-400" />
              <h1 className="text-xl font-bold">Game Tracker</h1>
            </div>
            <div className="flex gap-2">
              <button
                onClick={() => setShowImport(true)}
                className="btn-secondary text-sm gap-1.5"
              >
                <Upload className="w-4 h-4" />
                <span className="hidden sm:inline">Import</span>
              </button>
              <button
                onClick={() => setShowAddGame(true)}
                className="btn-primary text-sm gap-1.5"
              >
                <Plus className="w-4 h-4" />
                <span className="hidden sm:inline">Add Game</span>
              </button>
            </div>
          </div>

          {/* Search */}
          <div className="relative mb-3">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500" />
            <input
              type="text"
              placeholder="Search games..."
              value={search}
              onChange={e => setSearch(e.target.value)}
              className="input-field pl-10"
            />
          </div>

          {/* Status filter tabs */}
          <div className="flex gap-1 overflow-x-auto pb-1 scroll-smooth-ios">
            {['all', 'playing', 'backlog', 'completed', 'abandoned'].map(status => (
              <button
                key={status}
                onClick={() => setStatusFilter(status)}
                className={`${statusFilter === status ? 'tab-button-active' : 'tab-button-inactive'} whitespace-nowrap text-xs`}
              >
                {status === 'all' ? 'All' : STATUS_LABELS[status]} ({counts[status] || 0})
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Game Grid */}
      <div className="max-w-7xl mx-auto px-4 py-4">
        {library.length === 0 ? (
          <div className="card p-12 text-center">
            <Gamepad2 className="w-16 h-16 text-purple-400 mx-auto mb-4 opacity-50" />
            <h2 className="text-xl font-bold mb-2">No games yet</h2>
            <p className="text-gray-400 mb-6">
              Import your Gamery library or add games manually.
            </p>
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
          <div className="text-center py-12 text-gray-400">
            No games match your search.
          </div>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3">
            {sortedGames.map(game => (
              <GameCard
                key={game.id}
                game={game}
                onOpen={() => onOpenGame(game.id)}
                onUpdateStatus={(status) => {
                  updateData(prev => ({
                    ...prev,
                    library: prev.library.map(g =>
                      g.id === game.id ? { ...g, status } : g
                    ),
                  }));
                }}
                onDelete={() => setDeleteConfirmId(game.id)}
              />
            ))}
          </div>
        )}
      </div>

      {/* Import Modal */}
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
              file:cursor-pointer hover:file:bg-purple-700
              file:min-h-[44px]"
          />
        </Modal>
      )}

      {/* Add Game Modal */}
      {showAddGame && (
        <Modal onClose={() => setShowAddGame(false)} title="Add Game">
          <div className="space-y-3">
            <input
              type="text"
              placeholder="Game name"
              value={newGameName}
              onChange={e => setNewGameName(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && handleAddGame()}
              className="input-field"
              autoFocus
            />
            <input
              type="text"
              placeholder="Platform (optional)"
              value={newGamePlatform}
              onChange={e => setNewGamePlatform(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && handleAddGame()}
              className="input-field"
            />
            <button onClick={handleAddGame} className="btn-primary w-full">
              Add Game
            </button>
          </div>
        </Modal>
      )}

      {/* Delete Confirm Modal */}
      {deleteConfirmId && (() => {
        const game = library.find(g => g.id === deleteConfirmId);
        return (
          <Modal onClose={() => setDeleteConfirmId(null)} title="Remove Game">
            <p className="text-gray-300 mb-2">
              Remove <span className="font-semibold text-white">{game?.name}</span> from your library?
            </p>
            <p className="text-gray-500 text-sm mb-5">
              This will delete all saves and tracking data for this game. This cannot be undone.
            </p>
            <div className="flex gap-3">
              <button
                onClick={() => setDeleteConfirmId(null)}
                className="btn-secondary flex-1"
              >
                Cancel
              </button>
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
    </div>
  );
}

function GameCard({ game, onOpen, onUpdateStatus, onDelete }) {
  const hasTracker = game.trackerType !== null;

  return (
    <div className="card-hover p-4 text-left w-full group relative">
      {/* Delete button — appears on hover */}
      <button
        onClick={(e) => { e.stopPropagation(); onDelete(); }}
        className="absolute top-2 right-2 p-1.5 rounded-md text-gray-600 hover:text-red-400 hover:bg-red-400/10 transition-colors opacity-0 group-hover:opacity-100"
        title="Remove game"
      >
        <Trash2 className="w-3.5 h-3.5" />
      </button>

      {/* Card content — clickable to open */}
      <button onClick={onOpen} className="w-full text-left">
        <div className="flex items-start justify-between mb-2 pr-6">
          <h3 className="font-semibold text-sm leading-tight group-hover:text-purple-300 transition-colors">
            {game.name}
          </h3>
          <span className={`${STATUS_COLORS[game.status]} text-white text-[10px] font-medium px-2 py-0.5 rounded-full whitespace-nowrap flex-shrink-0 ml-2`}>
            {STATUS_LABELS[game.status]}
          </span>
        </div>
        {game.platforms.length > 0 && (
          <p className="text-gray-500 text-xs mb-2 truncate">
            {game.platforms.join(', ')}
          </p>
        )}
        {hasTracker && (
          <div className="flex items-center gap-1 text-purple-400 text-xs">
            <span className="w-1.5 h-1.5 rounded-full bg-purple-400" />
            Detailed tracking available
          </div>
        )}
        {game.saves?.length > 0 && (
          <p className="text-gray-500 text-xs mt-1">
            {game.saves.length} save{game.saves.length !== 1 ? 's' : ''}
          </p>
        )}
      </button>
    </div>
  );
}

function Modal({ onClose, title, children }) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm" onClick={onClose}>
      <div className="card p-6 w-full max-w-md" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-bold">{title}</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-white p-1 min-h-[44px] min-w-[44px] flex items-center justify-center">
            ✕
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}
