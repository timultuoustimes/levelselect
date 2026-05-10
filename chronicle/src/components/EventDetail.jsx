import { MapPin, Users, Tag, Link as LinkIcon, X, Edit2, Trash2, CalendarDays, ChevronRight } from 'lucide-react'
import PhotoGrid from './PhotoGrid'
import { formatDate, formatDateRange } from '../utils/format'

export default function EventDetail({ event, allEvents, onEdit, onDelete, onClose, onSelectEvent, onPhotosChange }) {
  if (!event) return null

  const children = allEvents.filter(e => e.parent_id === event.id)
    .sort((a, b) => a.start_date.localeCompare(b.start_date))

  const parent = event.parent_id ? allEvents.find(e => e.id === event.parent_id) : null
  const color = event.category?.color ?? '#94a3b8'

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="px-6 py-4 border-b border-gray-100 flex items-start justify-between gap-3">
        <div className="min-w-0">
          {event.category && (
            <div
              className="text-xs font-medium mb-1 flex items-center gap-1.5"
              style={{ color }}
            >
              <span className="w-2 h-2 rounded-full shrink-0" style={{ backgroundColor: color }} />
              {event.category.name}
            </div>
          )}
          <h2 className="font-semibold text-gray-900 text-base leading-snug">{event.title}</h2>
          <p className="text-sm text-gray-500 mt-0.5 flex items-center gap-1">
            <CalendarDays className="w-3.5 h-3.5 shrink-0" />
            {formatDateRange(event.start_date, event.end_date)}
          </p>
        </div>
        <button onClick={onClose} className="text-gray-400 hover:text-gray-600 shrink-0 mt-0.5">
          <X className="w-5 h-5" />
        </button>
      </div>

      {/* Scrollable body */}
      <div className="flex-1 overflow-y-auto px-6 py-5 flex flex-col gap-5">

        {/* Parent breadcrumb */}
        {parent && (
          <button
            onClick={() => onSelectEvent(parent)}
            className="flex items-center gap-2 text-sm text-gray-500 hover:text-gray-900 -mt-2 group"
          >
            <ChevronRight className="w-3.5 h-3.5 rotate-180 text-gray-400" />
            <span className="truncate group-hover:underline">{parent.title}</span>
          </button>
        )}

        {/* Subtitle */}
        {event.subtitle && (
          <p className="text-sm text-gray-600 leading-relaxed -mt-2">{event.subtitle}</p>
        )}

        {/* Photos */}
        {(event.photos?.length > 0) && (
          <section>
            <PhotoGrid
              eventId={event.id}
              photos={event.photos}
              onPhotosChange={onPhotosChange}
              editable={false}
            />
          </section>
        )}

        {/* Notes */}
        {event.notes && (
          <section>
            <SectionLabel>Notes</SectionLabel>
            <p className="text-sm text-gray-700 leading-relaxed whitespace-pre-wrap">{event.notes}</p>
          </section>
        )}

        {/* Location */}
        {event.location && (
          <section className="flex items-start gap-2">
            <MapPin className="w-4 h-4 text-gray-400 mt-0.5 shrink-0" />
            <span className="text-sm text-gray-700">{event.location}</span>
          </section>
        )}

        {/* People */}
        {event.people?.length > 0 && (
          <section>
            <SectionLabel>People</SectionLabel>
            <div className="flex flex-wrap gap-2">
              {event.people.map(person => (
                <span key={person} className="flex items-center gap-1.5 text-sm bg-gray-50 border border-gray-100 rounded-full px-3 py-1">
                  <span className="w-5 h-5 rounded-full bg-gray-200 flex items-center justify-center text-xs font-semibold text-gray-600 shrink-0">
                    {person[0]?.toUpperCase()}
                  </span>
                  {person}
                </span>
              ))}
            </div>
          </section>
        )}

        {/* Tags */}
        {event.tags?.length > 0 && (
          <section>
            <SectionLabel>Tags</SectionLabel>
            <div className="flex flex-wrap gap-1.5">
              {event.tags.map(tag => (
                <span key={tag} className="text-xs bg-gray-100 text-gray-600 px-2.5 py-1 rounded-full">
                  {tag}
                </span>
              ))}
            </div>
          </section>
        )}

        {/* Links */}
        {event.links?.length > 0 && (
          <section>
            <SectionLabel>Links</SectionLabel>
            <div className="flex flex-col gap-2">
              {event.links.map((link, i) => (
                <a
                  key={i}
                  href={link.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center gap-2 text-sm text-blue-600 hover:underline"
                >
                  <LinkIcon className="w-3.5 h-3.5 shrink-0 text-blue-400" />
                  {link.label || link.url}
                </a>
              ))}
            </div>
          </section>
        )}

        {/* Child events */}
        {children.length > 0 && (
          <section>
            <SectionLabel>{children.length} {children.length === 1 ? 'Event' : 'Events'}</SectionLabel>
            <div className="flex flex-col gap-2">
              {children.map(child => (
                <button
                  key={child.id}
                  onClick={() => onSelectEvent(child)}
                  className="flex items-center gap-3 bg-gray-50 rounded-xl border border-gray-100 px-4 py-2.5 text-left hover:bg-gray-100 transition-colors"
                >
                  <span
                    className="w-2 h-2 rounded-full shrink-0"
                    style={{ backgroundColor: child.category?.color ?? '#94a3b8' }}
                  />
                  <div className="min-w-0 flex-1">
                    <p className="text-sm font-medium text-gray-800 truncate">{child.title}</p>
                    <p className="text-xs text-gray-400">{formatDate(child.start_date)}</p>
                  </div>
                  <ChevronRight className="w-4 h-4 text-gray-300 shrink-0" />
                </button>
              ))}
            </div>
          </section>
        )}
      </div>

      {/* Footer actions */}
      <div className="px-6 py-4 border-t border-gray-100 flex gap-2">
        <button
          onClick={() => onEdit(event)}
          className="flex-1 flex items-center justify-center gap-2 text-sm font-medium text-gray-700 border border-gray-200 rounded-xl py-2 hover:bg-gray-50"
        >
          <Edit2 className="w-4 h-4" />
          Edit
        </button>
        <button
          onClick={() => onDelete(event)}
          className="flex-1 flex items-center justify-center gap-2 text-sm font-medium text-red-500 border border-red-100 rounded-xl py-2 hover:bg-red-50"
        >
          <Trash2 className="w-4 h-4" />
          Delete
        </button>
      </div>
    </div>
  )
}

function SectionLabel({ children }) {
  return (
    <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-2">{children}</p>
  )
}
