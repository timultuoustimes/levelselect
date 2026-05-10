import { useState } from 'react'
import { Search, X, ChevronDown, Calendar } from 'lucide-react'

export default function FilterBar({ categories, filters, onFiltersChange }) {
  const [showDatePicker, setShowDatePicker] = useState(false)

  function toggleCategory(id) {
    const current = filters.categoryIds ?? []
    const next = current.includes(id)
      ? current.filter(c => c !== id)
      : [...current, id]
    onFiltersChange({ ...filters, categoryIds: next })
  }

  function setDateRange(from, to) {
    onFiltersChange({ ...filters, dateFrom: from, dateTo: to })
    setShowDatePicker(false)
  }

  const hasFilters = filters.search || filters.categoryIds?.length || filters.dateFrom

  return (
    <div className="sticky top-0 z-10 bg-gray-50/90 backdrop-blur border-b border-gray-100 px-6 py-3">
      <div className="flex items-center gap-3 flex-wrap">
        {/* Search */}
        <div className="relative">
          <Search className="w-4 h-4 text-gray-400 absolute left-3 top-1/2 -translate-y-1/2" />
          <input
            type="text"
            placeholder="Search events…"
            value={filters.search ?? ''}
            onChange={e => onFiltersChange({ ...filters, search: e.target.value })}
            className="pl-9 pr-4 py-1.5 text-sm bg-white border border-gray-200 rounded-lg w-48 focus:outline-none focus:ring-2 focus:ring-gray-900/10 focus:border-gray-300"
          />
        </div>

        {/* Category pills */}
        <div className="flex items-center gap-1.5 flex-wrap">
          <button
            onClick={() => onFiltersChange({ ...filters, categoryIds: [] })}
            className={[
              'text-xs px-3 py-1.5 rounded-full font-medium transition-colors',
              !filters.categoryIds?.length
                ? 'bg-gray-900 text-white'
                : 'border border-gray-200 bg-white text-gray-600 hover:bg-gray-50',
            ].join(' ')}
          >
            All
          </button>
          {categories.map(cat => {
            const active = filters.categoryIds?.includes(cat.id)
            return (
              <button
                key={cat.id}
                onClick={() => toggleCategory(cat.id)}
                className={[
                  'text-xs px-3 py-1.5 rounded-full border font-medium transition-colors flex items-center gap-1.5',
                  active
                    ? 'text-white border-transparent'
                    : 'bg-white text-gray-600 border-gray-200 hover:bg-gray-50',
                ].join(' ')}
                style={active ? { backgroundColor: cat.color, borderColor: cat.color } : {}}
              >
                <span
                  className="w-2 h-2 rounded-full shrink-0"
                  style={{ backgroundColor: active ? 'rgba(255,255,255,0.8)' : cat.color }}
                />
                {cat.name}
              </button>
            )
          })}
        </div>

        {/* Date range */}
        <div className="ml-auto flex items-center gap-2">
          {filters.dateFrom && (
            <span className="text-xs text-gray-500 bg-white border border-gray-200 px-2 py-1 rounded-lg flex items-center gap-1">
              {filters.dateFrom}
              {filters.dateTo ? ` → ${filters.dateTo}` : ''}
              <button
                onClick={() => onFiltersChange({ ...filters, dateFrom: undefined, dateTo: undefined })}
                className="ml-1 text-gray-400 hover:text-gray-600"
              >
                <X className="w-3 h-3" />
              </button>
            </span>
          )}
          <div className="relative">
            <button
              onClick={() => setShowDatePicker(p => !p)}
              className="text-xs px-3 py-1.5 rounded-lg border border-gray-200 bg-white text-gray-600 hover:bg-gray-50 flex items-center gap-1"
            >
              <Calendar className="w-3.5 h-3.5" />
              Date range
              <ChevronDown className="w-3 h-3" />
            </button>
            {showDatePicker && (
              <DateRangeDropdown
                current={{ from: filters.dateFrom, to: filters.dateTo }}
                onApply={setDateRange}
                onClose={() => setShowDatePicker(false)}
              />
            )}
          </div>

          {hasFilters && (
            <button
              onClick={() => onFiltersChange({})}
              className="text-xs text-gray-400 hover:text-gray-600 flex items-center gap-1"
            >
              <X className="w-3.5 h-3.5" />
              Clear
            </button>
          )}
        </div>
      </div>
    </div>
  )
}

function DateRangeDropdown({ current, onApply, onClose }) {
  const [from, setFrom] = useState(current.from ?? '')
  const [to, setTo]     = useState(current.to   ?? '')

  const presets = [
    { label: 'Last 3 months', from: offset(-90), to: '' },
    { label: 'Last year',     from: offset(-365), to: '' },
    { label: 'Last 3 years',  from: offset(-365 * 3), to: '' },
    { label: 'Last 5 years',  from: offset(-365 * 5), to: '' },
    { label: 'All time',      from: '', to: '' },
  ]

  return (
    <>
      <div className="fixed inset-0 z-20" onClick={onClose} />
      <div className="absolute right-0 top-full mt-1 z-30 bg-white border border-gray-200 rounded-xl shadow-lg p-4 w-64">
        <div className="flex flex-col gap-1 mb-3">
          {presets.map(p => (
            <button
              key={p.label}
              onClick={() => onApply(p.from, p.to)}
              className="text-sm text-left px-3 py-1.5 rounded-lg hover:bg-gray-100 text-gray-700"
            >
              {p.label}
            </button>
          ))}
        </div>
        <div className="border-t border-gray-100 pt-3 flex flex-col gap-2">
          <div>
            <label className="text-xs text-gray-500 mb-1 block">From</label>
            <input
              type="date"
              value={from}
              onChange={e => setFrom(e.target.value)}
              className="w-full text-sm border border-gray-200 rounded-lg px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-gray-900/10"
            />
          </div>
          <div>
            <label className="text-xs text-gray-500 mb-1 block">To</label>
            <input
              type="date"
              value={to}
              onChange={e => setTo(e.target.value)}
              className="w-full text-sm border border-gray-200 rounded-lg px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-gray-900/10"
            />
          </div>
          <button
            onClick={() => onApply(from, to)}
            className="w-full bg-gray-900 text-white text-sm rounded-lg py-1.5 mt-1 hover:bg-gray-700"
          >
            Apply
          </button>
        </div>
      </div>
    </>
  )
}

function offset(days) {
  const d = new Date()
  d.setDate(d.getDate() + days)
  return d.toISOString().split('T')[0]
}
