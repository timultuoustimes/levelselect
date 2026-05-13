import React, { useState } from 'react';
import { X, Upload, Link, Loader, AlertCircle } from 'lucide-react';
import { uploadMapImage, newId } from '../../utils/mapStorage.js';

const SOURCES = [
  { id: 'upload', label: 'Upload image', icon: Upload },
  { id: 'url',    label: 'Use URL',      icon: Link   },
];

const MAP_TYPES = [
  { id: 'world', label: 'World map',       desc: 'Full-game overview' },
  { id: 'area',  label: 'Area / level map', desc: 'Specific region or stage' },
];

export default function AddMapModal({ game, deviceId, onAdd, onClose }) {
  const [source, setSource]     = useState('upload');
  const [name, setName]         = useState('');
  const [mapType, setMapType]   = useState('area');
  const [linkedId, setLinkedId] = useState('');
  const [urlInput, setUrlInput] = useState('');
  const [imgPreview, setImgPreview] = useState(null);
  const [file, setFile]         = useState(null);
  const [loading, setLoading]   = useState(false);
  const [error, setError]       = useState(null);

  // Collect tracker category names for the optional link step
  const trackerCategories = game.structuredTracker?.categories || [];

  const handleFileChange = (e) => {
    const f = e.target.files?.[0];
    if (!f) return;
    setFile(f);
    setImgPreview(URL.createObjectURL(f));
    if (!name) setName(f.name.replace(/\.[^.]+$/, '').replace(/[-_]/g, ' '));
    setError(null);
  };

  const handleUrlChange = (val) => {
    setUrlInput(val);
    setImgPreview(val.trim() || null);
    setError(null);
  };

  const handleAdd = async () => {
    if (!name.trim()) { setError('Please enter a name.'); return; }
    if (source === 'upload' && !file) { setError('Please choose an image file.'); return; }
    if (source === 'url' && !urlInput.trim()) { setError('Please enter a URL.'); return; }

    setLoading(true);
    setError(null);

    try {
      const mapId = newId();
      let imageUrl, storagePath;

      if (source === 'upload') {
        const result = await uploadMapImage(deviceId, game.id, mapId, file);
        imageUrl = result.url;
        storagePath = result.storagePath;
      } else {
        imageUrl = urlInput.trim();
        storagePath = null;
      }

      onAdd({
        id: mapId,
        name: name.trim(),
        type: mapType,
        linkedCategoryId: linkedId || undefined,
        storageType: source,
        imageUrl,
        storagePath,
        addedAt: new Date().toISOString(),
        markers: [],
      });
    } catch (err) {
      setError(err.message || 'Failed to add map.');
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      <div className="absolute inset-0 bg-black/70 backdrop-blur-sm" onClick={onClose} />
      <div className="flex min-h-full items-center justify-center px-4 py-6">
        <div className="relative bg-slate-900 border border-white/10 rounded-2xl shadow-2xl w-full max-w-md z-10">
          <div className="flex items-center justify-between px-5 py-4 border-b border-white/10">
            <span className="font-bold text-white">Add Map</span>
            <button onClick={onClose} className="text-gray-500 hover:text-white p-1">
              <X className="w-5 h-5" />
            </button>
          </div>

          <div className="px-5 py-4 space-y-4">
            {/* Source picker */}
            <div>
              <label className="text-xs text-gray-400 mb-2 block">Image source</label>
              <div className="grid grid-cols-2 gap-2">
                {SOURCES.map(s => {
                  const Icon = s.icon;
                  return (
                    <button
                      key={s.id}
                      onClick={() => { setSource(s.id); setError(null); }}
                      className={`flex items-center gap-2 px-3 py-2.5 rounded-lg border text-sm transition-colors ${
                        source === s.id
                          ? 'border-purple-500 bg-purple-900/30 text-white'
                          : 'border-white/10 bg-white/5 text-gray-400 hover:bg-white/10'
                      }`}
                    >
                      <Icon className="w-4 h-4" />
                      {s.label}
                    </button>
                  );
                })}
              </div>
            </div>

            {/* File or URL input */}
            {source === 'upload' ? (
              <div>
                <label className="text-xs text-gray-400 mb-1 block">Image file</label>
                <input
                  type="file"
                  accept="image/*"
                  onChange={handleFileChange}
                  className="block w-full text-sm text-gray-400
                    file:mr-3 file:py-2 file:px-3 file:rounded-lg file:border-0
                    file:text-sm file:font-medium file:bg-purple-600 file:text-white
                    file:cursor-pointer hover:file:bg-purple-700 file:min-h-[36px]"
                />
              </div>
            ) : (
              <div>
                <label className="text-xs text-gray-400 mb-1 block">Image URL</label>
                <input
                  type="url"
                  placeholder="https://…"
                  value={urlInput}
                  onChange={e => handleUrlChange(e.target.value)}
                  className="input-field text-sm w-full"
                />
              </div>
            )}

            {/* Preview */}
            {imgPreview && (
              <div className="rounded-lg overflow-hidden border border-white/10 max-h-40 flex items-center justify-center bg-black/30">
                <img
                  src={imgPreview}
                  alt="preview"
                  className="max-h-40 max-w-full object-contain"
                  onError={() => setError('Could not load image from that URL.')}
                />
              </div>
            )}

            {/* Name */}
            <div>
              <label className="text-xs text-gray-400 mb-1 block">Map name</label>
              <input
                type="text"
                placeholder="e.g. World Map, Norfair, Armored Armadillo Stage"
                value={name}
                onChange={e => setName(e.target.value)}
                className="input-field text-sm w-full"
              />
            </div>

            {/* Type */}
            <div>
              <label className="text-xs text-gray-400 mb-2 block">Map type</label>
              <div className="grid grid-cols-2 gap-2">
                {MAP_TYPES.map(t => (
                  <button
                    key={t.id}
                    onClick={() => setMapType(t.id)}
                    className={`text-left px-3 py-2 rounded-lg border text-sm transition-colors ${
                      mapType === t.id
                        ? 'border-purple-500 bg-purple-900/30 text-white'
                        : 'border-white/10 bg-white/5 text-gray-400 hover:bg-white/10'
                    }`}
                  >
                    <div className="font-medium">{t.label}</div>
                    <div className="text-[11px] text-gray-500 mt-0.5">{t.desc}</div>
                  </button>
                ))}
              </div>
            </div>

            {/* Optional category link — only shown when tracker has categories */}
            {trackerCategories.length > 0 && (
              <div>
                <label className="text-xs text-gray-400 mb-1 block">
                  Link to tracker section <span className="text-gray-600">(optional)</span>
                </label>
                <select
                  value={linkedId}
                  onChange={e => setLinkedId(e.target.value)}
                  className="input-field text-sm w-full bg-black/50"
                >
                  <option value="">None — standalone map</option>
                  {trackerCategories.map(c => (
                    <option key={c.id} value={c.id}>{c.name}</option>
                  ))}
                </select>
                <p className="text-[11px] text-gray-600 mt-1">
                  Linked maps appear in the tracker section and in the map panel when that section is expanded.
                </p>
              </div>
            )}

            {error && (
              <div className="flex items-start gap-2 text-sm text-red-400 bg-red-900/20 border border-red-700/30 rounded-lg p-3">
                <AlertCircle className="w-4 h-4 mt-0.5 shrink-0" />
                {error}
              </div>
            )}
          </div>

          <div className="px-5 py-3 border-t border-white/10 flex gap-2">
            <button onClick={onClose} className="btn-secondary flex-1 text-sm">
              Cancel
            </button>
            <button
              onClick={handleAdd}
              disabled={loading || !name.trim() || (source === 'upload' && !file) || (source === 'url' && !urlInput.trim())}
              className="btn-primary flex-1 text-sm disabled:opacity-50 flex items-center justify-center gap-2"
            >
              {loading ? <><Loader className="w-4 h-4 animate-spin" /> Uploading…</> : 'Add map'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
