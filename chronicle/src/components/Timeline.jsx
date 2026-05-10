import EventCard from './EventCard'
import { formatDateRange, groupEventsByYear } from '../utils/format'

export default function Timeline({ events, selectedEventId, onSelectEvent }) {
  // Separate top-level events from children
  const topLevel = events.filter(e => !e.parent_id)
  const childrenByParent = {}
  for (const e of events) {
    if (e.parent_id) {
      if (!childrenByParent[e.parent_id]) childrenByParent[e.parent_id] = []
      childrenByParent[e.parent_id].push(e)
    }
  }

  const groups = groupEventsByYear(topLevel)

  if (events.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center h-96 text-center px-8">
        <div className="w-12 h-12 rounded-full bg-gray-100 flex items-center justify-center mb-4">
          <svg className="w-6 h-6 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
        </div>
        <p className="text-gray-900 font-medium">No events yet</p>
        <p className="text-gray-500 text-sm mt-1">Add your first event to start your timeline.</p>
      </div>
    )
  }

  return (
    <div className="px-6 py-6">
      {groups.map(([year, yearEvents]) => (
        <div key={year} className="mb-8">
          {/* Year header */}
          <div className="flex items-center gap-4 mb-5">
            <div className="w-24 text-right">
              <span className="text-xs font-bold text-gray-400 uppercase tracking-widest">{year}</span>
            </div>
            <div className="flex-1 border-t border-gray-200" />
          </div>

          {/* Events for this year */}
          <div className="relative">
            {/* Vertical rail */}
            <div className="absolute left-[6.1rem] top-0 bottom-0 w-px bg-gray-100" />

            <div className="flex flex-col gap-4">
              {yearEvents.map(event => {
                const children = (childrenByParent[event.id] ?? []).sort(
                  (a, b) => a.start_date.localeCompare(b.start_date)
                )

                return (
                  <div key={event.id} className="flex gap-4">
                    {/* Date column */}
                    <div className="w-24 text-right pt-3 shrink-0">
                      <span className="text-xs font-medium text-gray-400 leading-snug">
                        {formatDateRange(event.start_date, event.end_date)}
                      </span>
                    </div>

                    {/* Dot */}
                    <div className="relative flex flex-col items-center shrink-0 w-4">
                      <div
                        className="w-2.5 h-2.5 rounded-full border-2 border-white mt-3 shrink-0 z-10"
                        style={{ backgroundColor: event.category?.color ?? '#94a3b8' }}
                      />
                    </div>

                    {/* Card + children */}
                    <div className="flex-1 min-w-0">
                      <EventCard
                        event={event}
                        childCount={children.length}
                        isSelected={selectedEventId === event.id}
                        onClick={() => onSelectEvent(event)}
                      />

                      {/* Children */}
                      {children.length > 0 && (
                        <div className="mt-2 ml-4 border-l-2 border-gray-100 pl-3 flex flex-col gap-2">
                          {children.map(child => (
                            <EventCard
                              key={child.id}
                              event={child}
                              isChild
                              isSelected={selectedEventId === child.id}
                              onClick={() => onSelectEvent(child)}
                            />
                          ))}
                        </div>
                      )}
                    </div>
                  </div>
                )
              })}
            </div>
          </div>
        </div>
      ))}
    </div>
  )
}
