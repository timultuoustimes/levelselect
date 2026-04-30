import React, { useState, useRef, useEffect, useCallback } from 'react';
import {
  X, ZoomIn, ZoomOut, RefreshCw, Plus, Filter, Maximize2, Loader,
  ChevronLeft, ChevronRight, ChevronDown, MapPin,
} from 'lucide-react';
import MarkerEditModal, { CATEGORIES } from './MarkerEditModal.jsx';
import { addMarker, updateMarker, removeMarker, newId, upgradeImageUrl } from '../../utils/mapStorage.js';

const CATEGORY_COLORS = {
  collectible: '#3b82f6',
  note:        '#facc15',
  warning:     '#ef4444',
  secret:      '#a855f7',
};

// ─── Map switcher (multi-map nav) ────────────────────────────────────────────

function MapSwitcher({ maps, activeMapId, onSwitch }) {
  const [open, setOpen] = useState(false);
  const idx = maps.findIndex(m => m.id === activeMapId);
  const current = maps[idx];
  const sorted = [...maps].sort((a, b) => {
    if (a.type === b.type) return a.name.localeCompare(b.name);
    return a.type === 'world' ? -1 : 1;
  });

  if (maps.length <= 1) return null;

  return (
    <div className="relative flex items-center gap-1">
      <button
        onClick={() => {
          const prev = maps[(idx - 1 + maps.length) % maps.length];
          onSwitch(prev.id);
        }}
        className="p-1.5 rounded-lg hover:bg-white/10 text-gray-400 hover:text-white transition-colors"
        title="Previous map"
      >
        <ChevronLeft className="w-4 h-4" />
      </button>

      <button
        onClick={() => setOpen(o => !o)}
        className="flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-white/10 hover:bg-white/20 text-sm text-white transition-colors max-w-[160px]"
      >
        <span className="truncate">{current?.name || 'Map'}</span>
        <ChevronDown className="w-3.5 h-3.5 shrink-0 text-gray-400" />
      </button>

      <button
        onClick={() => {
          const next = maps[(idx + 1) % maps.length];
          onSwitch(next.id);
        }}
        className="p-1.5 rounded-lg hover:bg-white/10 text-gray-400 hover:text-white transition-colors"
        title="Next map"
      >
        <ChevronRight className="w-4 h-4" />
      </button>

      {open && (
        <>
          <div className="fixed inset-0 z-10" onClick={() => setOpen(false)} />
          <div className="absolute top-full left-0 mt-1 w-56 bg-slate-900 border border-white/20 rounded-xl shadow-2xl z-20 overflow-hidden">
            {sorted.map(m => (
              <button
                key={m.id}
                onClick={() => { onSwitch(m.id); setOpen(false); }}
                className={`w-full text-left px-3 py-2 text-sm flex items-center gap-2 hover:bg-white/10 transition-colors ${
                  m.id === activeMapId ? 'text-white font-medium bg-white/5' : 'text-gray-300'
                }`}
              >
                <span className={`text-[10px] px-1.5 py-0.5 rounded uppercase tracking-wide font-mono ${
                  m.type === 'world' ? 'bg-blue-900/50 text-blue-300' : 'bg-slate-700 text-gray-400'
                }`}>
                  {m.type === 'world' ? 'world' : 'area'}
                </span>
                <span className="truncate">{m.name}</span>
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
}

// ─── Main viewer ─────────────────────────────────────────────────────────────

export default function MapViewer({
  game,
  maps,          // all game maps
  activeMapId,
  onMapSwitch,   // (mapId) => void
  onUpdateGame,
  mode = 'modal', // 'modal' | 'panel'
  onClose,
  onExpand,      // () => void — panel mode only, opens fullscreen overlay
}) {
  const map = maps.find(m => m.id === activeMapId);
  const markers = map?.markers || [];

  const [scale, setScale]         = useState(1);
  const [translate, setTranslate] = useState({ x: 0, y: 0 });
  const [addMode, setAddMode]     = useState(false);
  const [filterCat, setFilterCat] = useState(null);
  const [editingMarker, setEditingMarker] = useState(null); // { marker } | { x, y } (new)
  const [showFilterMenu, setShowFilterMenu] = useState(false);

  // Crisp zoom: track natural image size and compute fit dimensions
  const [fitDims, setFitDims] = useState(null); // { w, h } at scale=1

  const containerRef = useRef(null);
  const imgRef       = useRef(null);
  const isDragging   = useRef(false);
  const lastPointer  = useRef({ x: 0, y: 0 });
  const lastDist     = useRef(null);

  // Refs that keep touch handlers in sync with current state without re-registering
  const scaleRef   = useRef(scale);
  const addModeRef = useRef(addMode);
  useEffect(() => { scaleRef.current = scale; },   [scale]);
  useEffect(() => { addModeRef.current = addMode; }, [addMode]);

  // Reset transform + fitDims when map changes
  useEffect(() => {
    setScale(1);
    setTranslate({ x: 0, y: 0 });
    setAddMode(false);
    setFitDims(null);
  }, [activeMapId]);

  // Compute fit dims from natural image size vs container size
  const computeFitDims = useCallback(() => {
    const img = imgRef.current;
    const el  = containerRef.current;
    if (!img || !el || !img.naturalWidth) return;
    const nw = img.naturalWidth;
    const nh = img.naturalHeight;
    const { width: cw, height: ch } = el.getBoundingClientRect();
    if (!cw || !ch) return;
    const fitScale = Math.min(cw / nw, ch / nh);
    setFitDims({ w: nw * fitScale, h: nh * fitScale });
    setScale(1);
    setTranslate({ x: 0, y: 0 });
  }, []);

  const handleImgLoad = useCallback(() => {
    computeFitDims();
  }, [computeFitDims]);

  // Recompute fit dims on container resize (panel width changes, window resize)
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const ro = new ResizeObserver(() => {
      if (imgRef.current?.naturalWidth) computeFitDims();
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, [computeFitDims]);

  const clampTranslate = useCallback((tx, ty, s) => {
    const el = containerRef.current;
    if (!el || !fitDims) return { x: tx, y: ty };
    const { width: cw, height: ch } = el.getBoundingClientRect();
    const imgW = fitDims.w * s;
    const imgH = fitDims.h * s;
    const maxX = Math.max(0, (imgW - cw) / 2);
    const maxY = Math.max(0, (imgH - ch) / 2);
    return { x: Math.max(-maxX, Math.min(maxX, tx)), y: Math.max(-maxY, Math.min(maxY, ty)) };
  }, [fitDims]);

  // ── Zoom ────────────────────────────────────────────────────────────────────
  const zoom = (delta) => {
    setScale(prev => {
      const next = Math.min(5, Math.max(0.5, prev + delta));
      scaleRef.current = next;
      setTranslate(t => clampTranslate(t.x, t.y, next));
      return next;
    });
  };

  // ── Mouse wheel zoom ────────────────────────────────────────────────────────
  const handleWheel = (e) => {
    e.preventDefault();
    zoom(e.deltaY < 0 ? 0.15 : -0.15);
  };

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    el.addEventListener('wheel', handleWheel, { passive: false });
    return () => el.removeEventListener('wheel', handleWheel);
  }, []);

  // ── Mouse drag ──────────────────────────────────────────────────────────────
  const onMouseDown = (e) => {
    if (addMode) return;
    isDragging.current = true;
    lastPointer.current = { x: e.clientX, y: e.clientY };
  };
  const onMouseMove = (e) => {
    if (!isDragging.current) return;
    const dx = e.clientX - lastPointer.current.x;
    const dy = e.clientY - lastPointer.current.y;
    lastPointer.current = { x: e.clientX, y: e.clientY };
    setTranslate(t => clampTranslate(t.x + dx, t.y + dy, scaleRef.current));
  };
  const onMouseUp = () => { isDragging.current = false; };

  // ── Touch handlers — registered via addEventListener to allow preventDefault ──
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;

    const handleTouchStart = (e) => {
      if (e.touches.length === 1 && !addModeRef.current) {
        isDragging.current = true;
        lastPointer.current = { x: e.touches[0].clientX, y: e.touches[0].clientY };
      }
      if (e.touches.length === 2) {
        isDragging.current = false;
        const dx = e.touches[0].clientX - e.touches[1].clientX;
        const dy = e.touches[0].clientY - e.touches[1].clientY;
        lastDist.current = Math.hypot(dx, dy);
      }
    };

    const handleTouchMove = (e) => {
      e.preventDefault();
      if (e.touches.length === 1 && isDragging.current) {
        const dx = e.touches[0].clientX - lastPointer.current.x;
        const dy = e.touches[0].clientY - lastPointer.current.y;
        lastPointer.current = { x: e.touches[0].clientX, y: e.touches[0].clientY };
        setTranslate(t => clampTranslate(t.x + dx, t.y + dy, scaleRef.current));
      }
      if (e.touches.length === 2 && lastDist.current !== null) {
        const dx = e.touches[0].clientX - e.touches[1].clientX;
        const dy = e.touches[0].clientY - e.touches[1].clientY;
        const dist = Math.hypot(dx, dy);
        const delta = (dist - lastDist.current) * 0.01;
        lastDist.current = dist;
        setScale(prev => {
          const next = Math.min(5, Math.max(0.5, prev + delta));
          scaleRef.current = next;
          setTranslate(t => clampTranslate(t.x, t.y, next));
          return next;
        });
      }
    };

    const handleTouchEnd = () => {
      isDragging.current = false;
      lastDist.current = null;
    };

    el.addEventListener('touchstart', handleTouchStart, { passive: false });
    el.addEventListener('touchmove',  handleTouchMove,  { passive: false });
    el.addEventListener('touchend',   handleTouchEnd);
    return () => {
      el.removeEventListener('touchstart', handleTouchStart);
      el.removeEventListener('touchmove',  handleTouchMove);
      el.removeEventListener('touchend',   handleTouchEnd);
    };
  }, [clampTranslate]);

  // ── Click on map to place marker ────────────────────────────────────────────
  const handleMapClick = (e) => {
    if (!addMode) return;
    const img = imgRef.current;
    if (!img) return;
    const rect = img.getBoundingClientRect();
    const x = ((e.clientX - rect.left) / rect.width) * 100;
    const y = ((e.clientY - rect.top)  / rect.height) * 100;
    setEditingMarker({ x, y }); // new marker
    setAddMode(false);
  };

  // ── Marker CRUD ──────────────────────────────────────────────────────────────
  const handleSaveMarker = (data) => {
    if (!map) return;
    let updated;
    if (editingMarker?.marker) {
      updated = updateMarker(game, map.id, editingMarker.marker.id, data);
    } else {
      updated = addMarker(game, map.id, {
        id: newId(),
        x: editingMarker.x,
        y: editingMarker.y,
        label: '',
        notes: '',
        category: 'note',
        createdAt: new Date().toISOString(),
        ...data,
      });
    }
    onUpdateGame(updated);
    setEditingMarker(null);
  };

  const handleDeleteMarker = () => {
    if (!map || !editingMarker?.marker) return;
    onUpdateGame(removeMarker(game, map.id, editingMarker.marker.id));
    setEditingMarker(null);
  };

  const visibleMarkers = filterCat ? markers.filter(m => m.category === filterCat) : markers;

  if (!map) return null;

  const isModal = mode === 'modal';

  const toolbar = (
    // z-10 ensures this stacking context sits above the map canvas (which also creates
    // a stacking context via opacity). Without it, the filter dropdown gets painted over.
    <div className="relative z-10 flex items-center gap-2 px-3 py-2 bg-black/60 backdrop-blur border-b border-white/10 flex-wrap shrink-0">
      {/* Map switcher */}
      <MapSwitcher maps={maps} activeMapId={activeMapId} onSwitch={onMapSwitch} />

      <div className="flex items-center gap-1 ml-auto">
        {/* Add marker toggle */}
        <button
          onClick={() => setAddMode(a => !a)}
          title={addMode ? 'Cancel — click to add marker' : 'Add marker'}
          className={`flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-xs font-medium transition-colors ${
            addMode
              ? 'bg-purple-600 text-white'
              : 'bg-white/10 hover:bg-white/20 text-gray-300'
          }`}
        >
          <Plus className="w-3.5 h-3.5" />
          {addMode ? 'Click map…' : 'Add'}
        </button>

        {/* Category filter */}
        <div className="relative">
          <button
            onClick={() => setShowFilterMenu(o => !o)}
            className={`p-1.5 rounded-lg transition-colors ${filterCat ? 'bg-purple-600/50 text-purple-300' : 'hover:bg-white/10 text-gray-400 hover:text-white'}`}
            title="Filter by category"
          >
            <Filter className="w-4 h-4" />
          </button>
          {showFilterMenu && (
            <>
              <div className="fixed inset-0 z-10" onClick={() => setShowFilterMenu(false)} />
              <div className="absolute right-0 mt-1 w-40 bg-slate-900 border border-white/20 rounded-xl shadow-xl z-20 overflow-hidden">
                <button
                  onClick={() => { setFilterCat(null); setShowFilterMenu(false); }}
                  className={`w-full text-left px-3 py-2 text-sm hover:bg-white/10 ${!filterCat ? 'text-white font-medium' : 'text-gray-300'}`}
                >
                  All
                </button>
                {CATEGORIES.map(c => (
                  <button
                    key={c.id}
                    onClick={() => { setFilterCat(c.id); setShowFilterMenu(false); }}
                    className={`w-full text-left px-3 py-2 text-sm flex items-center gap-2 hover:bg-white/10 ${filterCat === c.id ? 'text-white font-medium' : 'text-gray-300'}`}
                  >
                    <span className={`w-2 h-2 rounded-full ${c.color}`} />
                    {c.label}
                  </button>
                ))}
              </div>
            </>
          )}
        </div>

        {/* Zoom */}
        <button onClick={() => zoom(0.25)} className="p-1.5 rounded-lg hover:bg-white/10 text-gray-400 hover:text-white" title="Zoom in">
          <ZoomIn className="w-4 h-4" />
        </button>
        <button onClick={() => zoom(-0.25)} className="p-1.5 rounded-lg hover:bg-white/10 text-gray-400 hover:text-white" title="Zoom out">
          <ZoomOut className="w-4 h-4" />
        </button>
        <button
          onClick={() => { setScale(1); scaleRef.current = 1; setTranslate({ x: 0, y: 0 }); }}
          className="p-1.5 rounded-lg hover:bg-white/10 text-gray-400 hover:text-white"
          title="Reset zoom"
        >
          <RefreshCw className="w-4 h-4" />
        </button>

        {/* Fullscreen (panel mode only) */}
        {!isModal && onExpand && (
          <button
            onClick={onExpand}
            className="p-1.5 rounded-lg hover:bg-white/10 text-gray-400 hover:text-white"
            title="Fullscreen"
          >
            <Maximize2 className="w-4 h-4" />
          </button>
        )}

        {isModal && (
          <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-white/10 text-gray-400 hover:text-white ml-1" title="Close">
            <X className="w-4 h-4" />
          </button>
        )}
      </div>
    </div>
  );

  const mapCanvas = (
    <div
      ref={containerRef}
      className={`relative overflow-hidden bg-black/40 select-none ${addMode ? 'cursor-crosshair' : 'cursor-grab active:cursor-grabbing'} ${isModal ? 'flex-1' : 'h-full'}`}
      onMouseDown={onMouseDown}
      onMouseMove={onMouseMove}
      onMouseUp={onMouseUp}
      onMouseLeave={onMouseUp}
      onClick={handleMapClick}
    >
      {fitDims ? (
        <div
          style={{
            position: 'absolute',
            width:  fitDims.w * scale,
            height: fitDims.h * scale,
            left: '50%',
            top:  '50%',
            transform: `translate(calc(-50% + ${translate.x}px), calc(-50% + ${translate.y}px))`,
          }}
        >
          <img
            ref={imgRef}
            src={upgradeImageUrl(map.imageUrl)}
            alt={map.name}
            className="block w-full h-full object-contain pointer-events-none"
            draggable={false}
            onLoad={handleImgLoad}
          />

          {/* Markers */}
          {visibleMarkers.map(mk => (
            <button
              key={mk.id}
              onClick={(e) => { e.stopPropagation(); setEditingMarker({ marker: mk }); }}
              title={mk.label}
              style={{ left: `${mk.x}%`, top: `${mk.y}%` }}
              className="absolute -translate-x-1/2 -translate-y-full z-10 group"
            >
              <div className="relative">
                <MapPin
                  className="w-6 h-6 drop-shadow-lg transition-transform group-hover:scale-125"
                  style={{ color: CATEGORY_COLORS[mk.category] || '#facc15', fill: CATEGORY_COLORS[mk.category] || '#facc15' }}
                />
                {mk.label && (
                  <div className="absolute bottom-full left-1/2 -translate-x-1/2 mb-1 hidden group-hover:flex whitespace-nowrap bg-black/80 text-white text-xs px-2 py-1 rounded-lg pointer-events-none max-w-[160px] truncate">
                    {mk.label}
                  </div>
                )}
              </div>
            </button>
          ))}
        </div>
      ) : (
        <>
          {/* Hidden img triggers onLoad to compute fitDims */}
          <img
            ref={imgRef}
            src={upgradeImageUrl(map.imageUrl)}
            alt={map.name}
            className="sr-only"
            draggable={false}
            onLoad={handleImgLoad}
          />
          <div className="absolute inset-0 flex items-center justify-center">
            <Loader className="w-6 h-6 animate-spin text-gray-600" />
          </div>
        </>
      )}

      {addMode && (
        <div className="absolute inset-x-0 bottom-4 flex justify-center pointer-events-none">
          <span className="bg-purple-900/80 text-purple-200 text-xs px-3 py-1.5 rounded-full backdrop-blur">
            Tap anywhere on the map to place a marker
          </span>
        </div>
      )}
    </div>
  );

  if (isModal) {
    return (
      <>
        {/* safe-area-inset-top keeps toolbar below iOS status bar/notch in the modal overlay */}
        <div
          className="fixed inset-0 z-50 flex flex-col bg-black/90"
          style={{ paddingTop: 'env(safe-area-inset-top, 0px)' }}
        >
          {toolbar}
          {mapCanvas}
        </div>
        {editingMarker && (
          <MarkerEditModal
            marker={editingMarker.marker || null}
            onSave={handleSaveMarker}
            onDelete={handleDeleteMarker}
            onClose={() => setEditingMarker(null)}
          />
        )}
      </>
    );
  }

  // Panel mode (desktop)
  return (
    <>
      <div className="flex flex-col h-full">
        {toolbar}
        {mapCanvas}
      </div>
      {editingMarker && (
        <MarkerEditModal
          marker={editingMarker.marker || null}
          onSave={handleSaveMarker}
          onDelete={handleDeleteMarker}
          onClose={() => setEditingMarker(null)}
        />
      )}
    </>
  );
}
