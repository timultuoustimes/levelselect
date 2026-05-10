import { MapPin, Users, ChevronRight, Image } from 'lucide-react'
import { formatDateRange, getDurationLabel } from '../utils/format'

export default function EventCard({ event, childCount = 0, isSelected, onClick, isChild = false }) {
  const color = event.category?.color ?? '#94a3b8'

  return (
    <button
      onClick={onClick}
      className={[
        'w-full text-left rounded-xl border overflow-hidden transition-all',
        'hover:shadow-md active:scale-[0.99]',
        isSelected
          ? 'border-gray-300 shadow-md'
          : 'border-gray-100 shadow-sm hover:border-gray-200',
        isChild ? 'bg-gray-50' : 'bg-white',
      ].join(' ')}
    >
      <div className="h-1 w-full" style={{ backgroundColor: color }} />
      <div className="px-4 py-3">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0 flex-1">
            {/* Category + duration */}
            <div className="flex items-center gap-2 mb-1 flex-wrap">
              {event.category && (
                <span
                  className="text-xs px-2 py-0.5 rounded-full font-medium border"
                  style={{
                    color,
                    backgroundColor: `${color}18`,
                    borderColor: `${color}40`,
                  }}
                >
                  {event.category.name}
                </span>
              )}
              {getDurationLabel(event.start_date, event.end_date) && (
                <span className="text-xs text-gray-400 bg-gray-100 px-2 py-0.5 rounded-full">
                  {getDurationLabel(event.start_date, event.end_date)}
                </span>
              )}
              {childCount > 0 && (
                <span className="text-xs text-gray-400 bg-gray-100 px-2 py-0.5 rounded-full">
                  {childCount} {childCount === 1 ? 'event' : 'events'}
                </span>
              )}
            </div>

            {/* Title */}
            <h3 className="font-semibold text-gray-900 text-sm leading-snug truncate">
              {event.title}
            </h3>

            {/* Subtitle */}
            {event.subtitle && (
              <p className="text-sm text-gray-500 mt-0.5 truncate">{event.subtitle}</p>
            )}

            {/* Meta row */}
            <div className="flex items-center gap-3 mt-1.5 flex-wrap">
              {event.location && (
                <span className="flex items-center gap-1 text-xs text-gray-400">
                  <MapPin className="w-3 h-3 shrink-0" />
                  <span className="truncate max-w-[120px]">{event.location}</span>
                </span>
              )}
              {event.people?.length > 0 && (
                <span className="flex items-center gap-1 text-xs text-gray-400">
                  <Users className="w-3 h-3 shrink-0" />
                  {event.people.slice(0, 3).join(', ')}
                  {event.people.length > 3 && ` +${event.people.length - 3}`}
                </span>
              )}
              {event.photos?.length > 0 && (
                <span className="flex items-center gap-1 text-xs text-gray-400">
                  <Image className="w-3 h-3 shrink-0" />
                  {event.photos.length}
                </span>
              )}
            </div>

            {/* Tags */}
            {event.tags?.length > 0 && (
              <div className="flex gap-1 mt-2 flex-wrap">
                {event.tags.slice(0, 4).map(tag => (
                  <span key={tag} className="text-xs bg-gray-100 text-gray-500 px-2 py-0.5 rounded-full">
                    {tag}
                  </span>
                ))}
                {event.tags.length > 4 && (
                  <span className="text-xs text-gray-400">+{event.tags.length - 4}</span>
                )}
              </div>
            )}
          </div>

          <ChevronRight className="w-4 h-4 text-gray-300 shrink-0 mt-1" />
        </div>
      </div>
    </button>
  )
}
