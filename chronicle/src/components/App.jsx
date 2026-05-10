import { useState, useEffect, useCallback } from 'react'
import { List, Settings as SettingsIcon, Plus } from 'lucide-react'
import Timeline from './Timeline'
import EventDetail from './EventDetail'
import EventForm from './EventForm'
import FilterBar from './FilterBar'
import Settings from './Settings'
import { fetchEvents, saveEvent, deleteEvent, applyFilters } from '../utils/events'
import { fetchCategories, seedDefaultCategories } from '../utils/categories'
import { ensureDevice, checkAndAdoptFromUrl } from '../utils/storage'

export default function App() {
  const [events, setEvents]           = useState([])
  const [categories, setCategories]   = useState([])
  const [filters, setFilters]         = useState({})
  const [selectedEvent, setSelectedEvent] = useState(null)
  const [editingEvent, setEditingEvent]   = useState(null) // null=closed, obj=edit/new
  const [view, setView]               = useState('timeline') // 'timeline' | 'settings'
  const [loading, setLoading]         = useState(true)
  const [error, setError]             = useState(null)

  // On mount: adopt device from URL if present, then init
  useEffect(() => {
    checkAndAdoptFromUrl()
    init()
  }, [])

  async function init() {
    try {
      await ensureDevice()
      let cats = await fetchCategories()
      if (cats.length === 0) {
        await seedDefaultCategories()
        cats = await fetchCategories()
      }
      const evts = await fetchEvents()
      setCategories(cats)
      setEvents(evts)
    } catch (err) {
      setError('Failed to connect to Supabase. Check your .env configuration.')
      console.error(err)
    } finally {
      setLoading(false)
    }
  }

  const refresh = useCallback(async () => {
    const evts = await fetchEvents()
    setEvents(evts)
  }, [])

  async function handleSaveEvent(eventData) {
    const saved = await saveEvent(eventData)
    setEvents(prev => {
      const idx = prev.findIndex(e => e.id === saved.id)
      return idx >= 0 ? prev.map(e => e.id === saved.id ? saved : e) : [saved, ...prev]
    })
    setEditingEvent(null)
    setSelectedEvent(saved)
  }

  async function handleDeleteEvent(event) {
    if (!confirm(`Delete "${event.title}"? This cannot be undone.`)) return
    await deleteEvent(event.id)
    setEvents(prev => prev.filter(e => e.id !== event.id && e.parent_id !== event.id))
    setSelectedEvent(null)
  }

  function handlePhotosChange(updatedPhotos) {
    if (!selectedEvent) return
    const updated = { ...selectedEvent, photos: updatedPhotos }
    setSelectedEvent(updated)
    setEvents(prev => prev.map(e => e.id === updated.id ? updated : e))
  }

  const filteredEvents = applyFilters(events, filters)

  if (loading) {
    return (
      <div className="flex items-center justify-center h-screen bg-gray-50">
        <div className="text-center">
          <div className="w-8 h-8 border-2 border-gray-300 border-t-gray-900 rounded-full animate-spin mx-auto mb-3" />
          <p className="text-sm text-gray-500">Loading Chronicle…</p>
        </div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="flex items-center justify-center h-screen bg-gray-50 p-8">
        <div className="bg-white rounded-2xl border border-red-100 p-8 max-w-md text-center shadow-sm">
          <p className="font-semibold text-gray-900 mb-2">Couldn't connect</p>
          <p className="text-sm text-gray-500 mb-4">{error}</p>
          <p className="text-xs text-gray-400 font-mono bg-gray-50 rounded-lg p-3 text-left">
            VITE_SUPABASE_URL=...<br />
            VITE_SUPABASE_ANON_KEY=...
          </p>
        </div>
      </div>
    )
  }

  return (
    <div className="flex h-screen bg-gray-50 overflow-hidden">

      {/* Sidebar */}
      <aside className="w-48 bg-white border-r border-gray-100 flex flex-col py-6 px-4 shrink-0">
        <div className="mb-8">
          <span className="text-lg font-semibold tracking-tight text-gray-900">Chronicle</span>
        </div>

        {/* Nav */}
        <nav className="flex flex-col gap-1 text-sm">
          <NavItem
            icon={<List className="w-4 h-4" />}
            label="Timeline"
            active={view === 'timeline'}
            onClick={() => setView('timeline')}
          />
          <NavItem
            icon={<SettingsIcon className="w-4 h-4" />}
            label="Settings"
            active={view === 'settings'}
            onClick={() => setView('settings')}
          />
        </nav>

        {/* Category legend */}
        {view === 'timeline' && categories.length > 0 && (
          <div className="mt-8">
            <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-3">Categories</p>
            <div className="flex flex-col gap-2">
              {categories.map(cat => (
                <div key={cat.id} className="flex items-center gap-2">
                  <span className="w-2.5 h-2.5 rounded-full shrink-0" style={{ backgroundColor: cat.color }} />
                  <span className="text-sm text-gray-600 truncate">{cat.name}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* New event button */}
        <div className="mt-auto">
          <button
            onClick={() => { setEditingEvent({}); setView('timeline') }}
            className="w-full flex items-center justify-center gap-2 bg-gray-900 text-white text-sm font-medium rounded-xl px-3 py-2.5 hover:bg-gray-700 transition-colors"
          >
            <Plus className="w-4 h-4" />
            New Event
          </button>
        </div>
      </aside>

      {/* Main */}
      <div className="flex flex-1 overflow-hidden min-w-0">

        {view === 'settings' ? (
          <div className="flex-1 overflow-y-auto">
            <Settings
              categories={categories}
              events={events}
              onCategoriesChange={setCategories}
            />
          </div>
        ) : (
          <>
            {/* Timeline column */}
            <div className="flex-1 flex flex-col overflow-hidden min-w-0">
              <FilterBar
                categories={categories}
                filters={filters}
                onFiltersChange={setFilters}
              />
              <div className="flex-1 overflow-y-auto no-scrollbar">
                <Timeline
                  events={filteredEvents}
                  selectedEventId={selectedEvent?.id}
                  onSelectEvent={setSelectedEvent}
                />
              </div>
            </div>

            {/* Detail panel */}
            {selectedEvent && (
              <div className="w-80 bg-white border-l border-gray-100 overflow-hidden flex flex-col shrink-0">
                <EventDetail
                  event={selectedEvent}
                  allEvents={events}
                  onEdit={setEditingEvent}
                  onDelete={handleDeleteEvent}
                  onClose={() => setSelectedEvent(null)}
                  onSelectEvent={setSelectedEvent}
                  onPhotosChange={handlePhotosChange}
                />
              </div>
            )}
          </>
        )}
      </div>

      {/* Event form modal */}
      {editingEvent !== null && (
        <EventForm
          event={editingEvent?.id ? editingEvent : null}
          categories={categories}
          allEvents={events}
          onSave={handleSaveEvent}
          onClose={() => setEditingEvent(null)}
        />
      )}
    </div>
  )
}

function NavItem({ icon, label, active, onClick }) {
  return (
    <button
      onClick={onClick}
      className={[
        'flex items-center gap-2 px-3 py-2 rounded-lg text-sm text-left transition-colors',
        active ? 'bg-gray-100 font-medium text-gray-900' : 'text-gray-500 hover:bg-gray-50 hover:text-gray-900',
      ].join(' ')}
    >
      {icon}
      {label}
    </button>
  )
}
