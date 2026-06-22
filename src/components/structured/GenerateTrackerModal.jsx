import React, { useState } from 'react';
import {
  X, Search, FileText, Loader, ChevronDown, ChevronRight,
  AlertTriangle, Eye, Trash2, Sparkles,
} from 'lucide-react';
import { generateTrackerData } from '../../utils/aiTracker.js';

const MODES = [
  { id: 'auto',  label: 'Auto (web search)', icon: Search,   desc: 'Genie searches for guides and wikis' },
  { id: 'paste', label: 'Paste text',        icon: FileText, desc: 'Paste guide or walkthrough text' },
];

// ─── Review panel for generated data ─────────────────────────────────────────

function ReviewCategory({ category, onRemoveCategory, onRemoveItem }) {
  const [collapsed, setCollapsed] = useState(false);
  const items = category.items || [];
  const hiddenCount = items.filter(i => i.hideUntilDiscovered).length;
  const missableCount = items.filter(i => i.missable).length;

  return (
    <div className="bg-black/30 rounded-lg border border-white/10 overflow-hidden">
      <div className="flex items-center gap-2 px-3 py-2 hover:bg-white/5">
        <button onClick={() => setCollapsed(c => !c)} className="shrink-0 text-gray-500">
          {collapsed ? <ChevronRight className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
        </button>
        <div className="flex-1 min-w-0">
          <span className="text-sm font-medium text-gray-200">{category.name}</span>
          <span className="text-[10px] text-gray-500 uppercase tracking-wider ml-2">{category.type}</span>
          <span className="text-xs text-gray-500 ml-2">{items.length} items</span>
          {hiddenCount > 0 && (
            <span className="text-[10px] text-gray-500 ml-2">
              <Eye className="w-3 h-3 inline" /> {hiddenCount} hidden
            </span>
          )}
          {missableCount > 0 && (
            <span className="text-[10px] text-yellow-500 ml-2">
              <AlertTriangle className="w-3 h-3 inline" /> {missableCount} missable
            </span>
          )}
        </div>
        <button
          onClick={() => onRemoveCategory(category.id)}
          className="text-gray-600 hover:text-red-400 transition-colors p-1"
          title="Remove category"
        >
          <Trash2 className="w-3.5 h-3.5" />
        </button>
      </div>
      {!collapsed && (
        <div className="border-t border-white/5 divide-y divide-white/5 max-h-60 overflow-y-auto">
          {items.map(item => (
            <div key={item.id} className="flex items-center gap-2 px-3 py-1.5 text-xs group">
              <div className="flex-1 min-w-0">
                <span className={`${item.hideUntilDiscovered ? 'italic text-gray-500' : 'text-gray-300'}`}>
                  {item.hideUntilDiscovered ? '??? ' : ''}{item.name}
                </span>
                {item.location && <span className="text-gray-600 ml-1">— {item.location}</span>}
                {item.missable && <AlertTriangle className="w-3 h-3 text-yellow-500 inline ml-1" />}
                {item.maxRank != null && (
                  <span className="text-purple-400 ml-1">rank 0–{item.maxRank}</span>
                )}
              </div>
              <button
                onClick={() => onRemoveItem(category.id, item.id)}
                className="text-gray-700 hover:text-red-400 transition-colors opacity-0 group-hover:opacity-100 p-0.5"
                title="Remove item"
              >
                <X className="w-3 h-3" />
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ─── Main modal ──────────────────────────────────────────────────────────────

export default function GenerateTrackerModal({ game, onSave, onClose }) {
  const [mode, setMode] = useState('auto');
  const [pasteInput, setPasteInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [result, setResult] = useState(null); // { structuredData, usage }
  const [showCloseWarning, setShowCloseWarning] = useState(false);

  const handleGenerate = async () => {
    setLoading(true);
    setError(null);
    setResult(null);

    try {
      const payload = mode === 'paste' ? pasteInput.trim() : null;

      const igdbData = {
        genres: game.genres || [],
        themes: game.themes || [],
        gameModes: game.gameModes || [],
        developers: game.developers || [],
        publishers: game.publishers || [],
      };

      const res = await generateTrackerData({
        gameName: game.name,
        igdbData,
        mode,
        payload,
      });

      setResult(res);
    } catch (err) {
      setError(err.message || 'Generation failed');
    } finally {
      setLoading(false);
    }
  };

  const removeCategory = (catId) => {
    if (!result) return;
    setResult(prev => ({
      ...prev,
      structuredData: {
        ...prev.structuredData,
        categories: prev.structuredData.categories.filter(c => c.id !== catId),
      },
    }));
  };

  const removeItem = (catId, itemId) => {
    if (!result) return;
    setResult(prev => ({
      ...prev,
      structuredData: {
        ...prev.structuredData,
        categories: prev.structuredData.categories.map(c =>
          c.id === catId
            ? { ...c, items: c.items.filter(i => i.id !== itemId) }
            : c
        ),
      },
    }));
  };

  const handleSave = () => {
    if (!result?.structuredData) return;
    onSave(result.structuredData);
  };

  const totalItems = result?.structuredData?.categories?.reduce(
    (acc, c) => acc + (c.items?.length || 0), 0
  ) || 0;
  const totalCategories = result?.structuredData?.categories?.length || 0;

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      <div
        className="fixed inset-0 bg-black/70 backdrop-blur-sm"
        onClick={result ? handleSave : onClose}
      />
      <div
        className="flex min-h-full items-center justify-center px-4"
        style={{ paddingTop: 'max(1.5rem, env(safe-area-inset-top))', paddingBottom: '1.5rem' }}
      >
      <div className="relative bg-slate-900 border border-white/10 rounded-2xl shadow-2xl w-full max-w-xl z-10">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-white/10">
          <div className="flex items-center gap-2">
            <Sparkles className="w-5 h-5 text-purple-400" />
            <h2 className="font-bold text-white">Generate Tracker Data</h2>
          </div>
          <button
            onClick={result ? () => setShowCloseWarning(true) : onClose}
            className="text-gray-500 hover:text-white transition-colors p-1"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Close warning banner */}
        {showCloseWarning && (
          <div className="px-5 py-3 bg-yellow-900/20 border-b border-yellow-500/20 flex items-center gap-3 flex-wrap">
            <span className="text-sm text-yellow-200 flex-1">Save the generated tracker data before closing?</span>
            <button onClick={handleSave} className="btn-primary text-xs px-3 py-1.5 shrink-0">
              Save & Close
            </button>
            <button onClick={onClose} className="btn-secondary text-xs px-3 py-1.5 shrink-0">
              Discard
            </button>
            <button onClick={() => setShowCloseWarning(false)} className="text-gray-400 text-xs hover:text-white shrink-0">
              Keep Editing
            </button>
          </div>
        )}


        <div className="px-5 py-4 space-y-4 max-h-[70vh] overflow-y-auto">
          {!result ? (
            <>
              {/* Source selection */}
              <div>
                <label className="text-xs text-gray-400 mb-2 block">Source</label>
                <div className="grid grid-cols-2 gap-2">
                  {MODES.map(m => {
                    const Icon = m.icon;
                    return (
                      <button
                        key={m.id}
                        onClick={() => setMode(m.id)}
                        className={`text-left px-3 py-2.5 rounded-lg border transition-colors ${
                          mode === m.id
                            ? 'border-purple-500 bg-purple-900/30 text-white'
                            : 'border-white/10 bg-white/5 text-gray-400 hover:bg-white/10'
                        }`}
                      >
                        <div className="flex items-center gap-2 mb-0.5">
                          <Icon className="w-3.5 h-3.5" />
                          <span className="text-xs font-medium">{m.label}</span>
                        </div>
                        <div className="text-[10px] text-gray-500">{m.desc}</div>
                      </button>
                    );
                  })}
                </div>
              </div>

              {/* Mode-specific input */}
              {mode === 'paste' && (
                <div>
                  <label className="text-xs text-gray-400 mb-1 block">Guide text</label>
                  <textarea
                    placeholder="Paste walkthrough or guide text here..."
                    value={pasteInput}
                    onChange={e => setPasteInput(e.target.value)}
                    className="input-field text-sm w-full resize-none"
                    rows={6}
                  />
                </div>
              )}

              {/* Error */}
              {error && (
                <div className="text-red-400 text-sm bg-red-900/20 border border-red-700/30 rounded-lg p-3">
                  {error}
                </div>
              )}

              {/* Generate button */}
              <button
                onClick={handleGenerate}
                disabled={loading}
                className="btn-primary w-full flex items-center justify-center gap-2 disabled:opacity-50"
              >
                {loading ? (
                  <>
                    <Loader className="w-4 h-4 animate-spin" />
                    Generating... (this may take 1–2 minutes)
                  </>
                ) : (
                  <>
                    <Sparkles className="w-4 h-4" />
                    Generate Tracker Data
                  </>
                )}
              </button>

              {loading && (
                <p className="text-xs text-gray-500 text-center">
                  Genie is searching the web and building your tracker data. Hang tight.
                </p>
              )}
            </>
          ) : (
            /* ── Review generated data ─────────────────────────────────── */
            <>
              <div className="bg-green-900/20 border border-green-700/30 rounded-lg p-3 text-sm text-green-300">
                Generated {totalCategories} categories with {totalItems} items.
                {result.structuredData.estimatedHours && (
                  <span className="text-green-400"> ~{result.structuredData.estimatedHours}h to complete.</span>
                )}
                <span className="text-green-500/80 text-xs block mt-1">
                  Review below — remove anything that looks wrong, then save.
                </span>
              </div>

              {result.structuredData.completionNotes && (
                <div className="text-xs text-gray-500 bg-white/[0.02] border border-white/5 rounded-lg p-2.5">
                  {result.structuredData.completionNotes}
                </div>
              )}

              <div className="space-y-2">
                {(result.structuredData.categories || []).map(cat => (
                  <ReviewCategory
                    key={cat.id}
                    category={cat}
                    onRemoveCategory={removeCategory}
                    onRemoveItem={removeItem}
                  />
                ))}
              </div>

              {result.usage && (
                <div className="text-[10px] text-gray-600 text-center">
                  Tokens: {result.usage.input_tokens} in / {result.usage.output_tokens} out
                </div>
              )}
            </>
          )}
        </div>

        {/* Footer */}
        <div className="px-5 py-3 border-t border-white/10 flex gap-2">
          {result ? (
            <>
              <button
                onClick={() => { setResult(null); setError(null); }}
                className="btn-secondary flex-1 text-sm"
              >
                Regenerate
              </button>
              <button
                onClick={handleSave}
                disabled={totalItems === 0}
                className="btn-primary flex-1 text-sm disabled:opacity-50"
              >
                Save Tracker Data ({totalItems} items)
              </button>
            </>
          ) : (
            <button onClick={onClose} className="btn-secondary w-full text-sm">
              Cancel
            </button>
          )}
        </div>
      </div>
      </div>
    </div>
  );
}
