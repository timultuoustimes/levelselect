import React, { useState } from 'react';
import { X, Trash2 } from 'lucide-react';

const CATEGORIES = [
  { id: 'collectible', label: 'Collectible', color: 'bg-blue-500',   ring: 'ring-blue-500'   },
  { id: 'note',        label: 'Note',        color: 'bg-yellow-400', ring: 'ring-yellow-400' },
  { id: 'warning',     label: 'Warning',     color: 'bg-red-500',    ring: 'ring-red-500'    },
  { id: 'secret',      label: 'Secret',      color: 'bg-purple-500', ring: 'ring-purple-500' },
];

export default function MarkerEditModal({ marker, onSave, onDelete, onClose }) {
  const [label, setLabel]       = useState(marker?.label || '');
  const [notes, setNotes]       = useState(marker?.notes || '');
  const [category, setCategory] = useState(marker?.category || 'note');
  const [confirmDelete, setConfirmDelete] = useState(false);

  const handleSave = () => {
    if (!label.trim()) return;
    onSave({ label: label.trim(), notes: notes.trim(), category });
  };

  return (
    <div className="fixed inset-0 z-[60] flex items-end sm:items-center justify-center px-4 pb-4 sm:pb-0">
      <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" onClick={onClose} />
      <div className="relative bg-slate-900 border border-white/10 rounded-2xl shadow-2xl w-full max-w-sm z-10">
        <div className="flex items-center justify-between px-4 py-3 border-b border-white/10">
          <span className="font-semibold text-sm text-white">
            {marker ? 'Edit marker' : 'Add marker'}
          </span>
          <button onClick={onClose} className="text-gray-500 hover:text-white p-1">
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="px-4 py-4 space-y-3">
          <div>
            <label className="text-xs text-gray-400 block mb-1">Label</label>
            <input
              autoFocus
              type="text"
              value={label}
              onChange={e => setLabel(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && handleSave()}
              placeholder="Short name for this marker"
              className="input-field text-sm w-full"
            />
          </div>

          <div>
            <label className="text-xs text-gray-400 block mb-1">Notes</label>
            <textarea
              value={notes}
              onChange={e => setNotes(e.target.value)}
              placeholder="Any details, hints, or reminders…"
              rows={3}
              className="input-field text-sm w-full resize-none"
            />
          </div>

          <div>
            <label className="text-xs text-gray-400 block mb-2">Category</label>
            <div className="flex gap-2 flex-wrap">
              {CATEGORIES.map(c => (
                <button
                  key={c.id}
                  onClick={() => setCategory(c.id)}
                  className={`flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-xs font-medium border transition-all ${
                    category === c.id
                      ? `border-white/30 bg-white/10 ring-1 ${c.ring}`
                      : 'border-white/10 bg-white/5 text-gray-400'
                  }`}
                >
                  <span className={`w-2 h-2 rounded-full ${c.color}`} />
                  {c.label}
                </button>
              ))}
            </div>
          </div>
        </div>

        <div className="px-4 py-3 border-t border-white/10 flex gap-2">
          {marker && !confirmDelete && (
            <button
              onClick={() => setConfirmDelete(true)}
              className="btn-danger !px-3 !py-2 !min-h-0 text-xs"
            >
              <Trash2 className="w-3.5 h-3.5" />
            </button>
          )}
          {confirmDelete && (
            <>
              <button
                onClick={onDelete}
                className="btn-danger flex-1 text-sm"
              >
                Delete marker
              </button>
              <button
                onClick={() => setConfirmDelete(false)}
                className="btn-secondary flex-1 text-sm"
              >
                Cancel
              </button>
            </>
          )}
          {!confirmDelete && (
            <>
              <button onClick={onClose} className="btn-secondary flex-1 text-sm">
                Cancel
              </button>
              <button
                onClick={handleSave}
                disabled={!label.trim()}
                className="btn-primary flex-1 text-sm disabled:opacity-50"
              >
                {marker ? 'Save' : 'Add marker'}
              </button>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

export { CATEGORIES };
