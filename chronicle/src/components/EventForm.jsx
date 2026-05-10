import { useState, useEffect } from 'react'
import { X, Plus, Trash2 } from 'lucide-react'
import PhotoGrid from './PhotoGrid'
import { saveEvent } from '../utils/events'
import { today } from '../utils/format'

const EMPTY = {
  title: '', subtitle: '', start_date: '', end_date: '',
  category_id: '', notes: '', location: '',
  tags: [], people: [], links: [], parent_id: '',
}

export default function EventForm({ event, categories, allEvents, onSave, onClose }) {
  const isNew = !event?.id
  const [form, setForm]     = useState({ ...EMPTY, start_date: today(), ...(event ?? {}) })
  const [saving, setSaving] = useState(false)
  const [tagInput, setTagInput]       = useState('')
  const [personInput, setPersonInput] = useState('')

  // Photos are managed separately after the event is saved
  const [photos, setPhotos] = useState(event?.photos ?? [])

  // Sync photos back when event changes (e.g. re-opened for edit)
  useEffect(() => { setPhotos(event?.photos ?? []) }, [event?.id])

  function setField(key, value) {
    setForm(f => ({ ...f, [key]: value }))
  }

  function addChip(field, input, setInput) {
    const val = input.trim()
    if (!val) return
    const current = form[field] ?? []
    if (!current.includes(val)) setField(field, [...current, val])
    setInput('')
  }

  function removeChip(field, val) {
    setField(field, (form[field] ?? []).filter(v => v !== val))
  }

  function addLink() {
    setField('links', [...(form.links ?? []), { url: '', label: '' }])
  }

  function updateLink(i, key, value) {
    const links = [...(form.links ?? [])]
    links[i] = { ...links[i], [key]: value }
    setField('links', links)
  }

  function removeLink(i) {
    setField('links', (form.links ?? []).filter((_, idx) => idx !== i))
  }

  async function handleSubmit(e) {
    e.preventDefault()
    if (!form.title.trim() || !form.start_date) return
    setSaving(true)
    try {
      const saved = await saveEvent({
        ...form,
        title:       form.title.trim(),
        category_id: form.category_id || null,
        parent_id:   form.parent_id   || null,
        end_date:    form.end_date    || null,
        links:       (form.links ?? []).filter(l => l.url.trim()),
      })
      // Attach current photos to saved event for immediate display
      onSave({ ...saved, photos })
    } catch (err) {
      console.error(err)
    } finally {
      setSaving(false)
    }
  }

  const parentCandidates = allEvents.filter(e => e.id !== event?.id && !e.parent_id)

  return (
    <div className="fixed inset-0 z-40 flex items-end sm:items-center justify-center p-4 bg-black/40 backdrop-blur-sm">
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-xl max-h-[90vh] flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-gray-100">
          <h2 className="font-semibold text-gray-900">{isNew ? 'New Event' : 'Edit Event'}</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600">
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Form body */}
        <form onSubmit={handleSubmit} className="flex-1 overflow-y-auto px-6 py-5 flex flex-col gap-5">

          {/* Title */}
          <div>
            <Label required>Title</Label>
            <input
              type="text"
              required
              placeholder="What happened?"
              value={form.title}
              onChange={e => setField('title', e.target.value)}
              autoFocus
              className={input()}
            />
          </div>

          {/* Subtitle */}
          <div>
            <Label>Subtitle</Label>
            <input
              type="text"
              placeholder="One-line description (optional)"
              value={form.subtitle}
              onChange={e => setField('subtitle', e.target.value)}
              className={input()}
            />
          </div>

          {/* Dates */}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label required>Start date</Label>
              <input
                type="date"
                required
                value={form.start_date}
                onChange={e => setField('start_date', e.target.value)}
                className={input()}
              />
            </div>
            <div>
              <Label>End date</Label>
              <input
                type="date"
                value={form.end_date}
                min={form.start_date}
                onChange={e => setField('end_date', e.target.value)}
                className={input()}
              />
            </div>
          </div>

          {/* Category */}
          <div>
            <Label>Category</Label>
            <select
              value={form.category_id}
              onChange={e => setField('category_id', e.target.value)}
              className={input()}
            >
              <option value="">No category</option>
              {categories.map(c => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </select>
          </div>

          {/* Location */}
          <div>
            <Label>Location</Label>
            <input
              type="text"
              placeholder="Where did this happen?"
              value={form.location}
              onChange={e => setField('location', e.target.value)}
              className={input()}
            />
          </div>

          {/* Notes */}
          <div>
            <Label>Notes</Label>
            <textarea
              placeholder="More context, details, reflections…"
              value={form.notes}
              onChange={e => setField('notes', e.target.value)}
              rows={4}
              className={input() + ' resize-none'}
            />
          </div>

          {/* People */}
          <div>
            <Label>People</Label>
            <ChipInput
              chips={form.people}
              input={personInput}
              setInput={setPersonInput}
              placeholder="Add a name, press Enter"
              onAdd={() => addChip('people', personInput, setPersonInput)}
              onRemove={v => removeChip('people', v)}
            />
          </div>

          {/* Tags */}
          <div>
            <Label>Tags</Label>
            <ChipInput
              chips={form.tags}
              input={tagInput}
              setInput={setTagInput}
              placeholder="Add a tag, press Enter"
              onAdd={() => addChip('tags', tagInput, setTagInput)}
              onRemove={v => removeChip('tags', v)}
            />
          </div>

          {/* Links */}
          <div>
            <div className="flex items-center justify-between mb-2">
              <Label>Links</Label>
              <button
                type="button"
                onClick={addLink}
                className="text-xs text-gray-500 hover:text-gray-900 flex items-center gap-1"
              >
                <Plus className="w-3.5 h-3.5" /> Add link
              </button>
            </div>
            {(form.links ?? []).map((link, i) => (
              <div key={i} className="flex gap-2 mb-2">
                <input
                  type="url"
                  placeholder="https://…"
                  value={link.url}
                  onChange={e => updateLink(i, 'url', e.target.value)}
                  className={input() + ' flex-1'}
                />
                <input
                  type="text"
                  placeholder="Label"
                  value={link.label}
                  onChange={e => updateLink(i, 'label', e.target.value)}
                  className={input() + ' w-28'}
                />
                <button type="button" onClick={() => removeLink(i)} className="text-gray-300 hover:text-red-500">
                  <Trash2 className="w-4 h-4" />
                </button>
              </div>
            ))}
          </div>

          {/* Parent event */}
          {parentCandidates.length > 0 && (
            <div>
              <Label>Part of…</Label>
              <select
                value={form.parent_id}
                onChange={e => setField('parent_id', e.target.value)}
                className={input()}
              >
                <option value="">Standalone event</option>
                {parentCandidates.map(e => (
                  <option key={e.id} value={e.id}>{e.title}</option>
                ))}
              </select>
            </div>
          )}

          {/* Photos — only show for existing events */}
          {!isNew && (
            <div>
              <Label>Photos</Label>
              <PhotoGrid
                eventId={event.id}
                photos={photos}
                onPhotosChange={setPhotos}
                editable
              />
            </div>
          )}

          {isNew && (
            <p className="text-xs text-gray-400">You can add photos after saving the event.</p>
          )}
        </form>

        {/* Footer */}
        <div className="px-6 py-4 border-t border-gray-100 flex gap-3">
          <button
            type="button"
            onClick={onClose}
            className="flex-1 text-sm font-medium text-gray-600 border border-gray-200 rounded-xl py-2.5 hover:bg-gray-50"
          >
            Cancel
          </button>
          <button
            type="submit"
            form="event-form"
            onClick={handleSubmit}
            disabled={saving || !form.title.trim() || !form.start_date}
            className="flex-1 text-sm font-semibold text-white bg-gray-900 rounded-xl py-2.5 hover:bg-gray-700 disabled:opacity-50"
          >
            {saving ? 'Saving…' : isNew ? 'Add Event' : 'Save Changes'}
          </button>
        </div>
      </div>
    </div>
  )
}

function Label({ children, required }) {
  return (
    <label className="block text-xs font-semibold text-gray-500 uppercase tracking-wider mb-1.5">
      {children}{required && <span className="text-red-400 ml-0.5">*</span>}
    </label>
  )
}

function input() {
  return 'w-full text-sm border border-gray-200 rounded-xl px-3 py-2 focus:outline-none focus:ring-2 focus:ring-gray-900/10 focus:border-gray-300 bg-white'
}

function ChipInput({ chips, input, setInput, placeholder, onAdd, onRemove }) {
  return (
    <div className="flex flex-wrap gap-1.5 p-2 border border-gray-200 rounded-xl bg-white min-h-[42px]">
      {chips.map(chip => (
        <span key={chip} className="flex items-center gap-1 text-xs bg-gray-100 text-gray-700 rounded-full px-2.5 py-1">
          {chip}
          <button type="button" onClick={() => onRemove(chip)} className="text-gray-400 hover:text-gray-700">
            <X className="w-3 h-3" />
          </button>
        </span>
      ))}
      <input
        type="text"
        placeholder={chips.length ? '' : placeholder}
        value={input}
        onChange={e => setInput(e.target.value)}
        onKeyDown={e => {
          if (e.key === 'Enter' || e.key === ',') { e.preventDefault(); onAdd() }
          if (e.key === 'Backspace' && !input && chips.length) onRemove(chips[chips.length - 1])
        }}
        className="flex-1 min-w-[80px] text-sm outline-none bg-transparent placeholder:text-gray-400"
      />
    </div>
  )
}
