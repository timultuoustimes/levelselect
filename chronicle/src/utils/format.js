export function formatDate(dateStr) {
  if (!dateStr) return ''
  const [y, m, d] = dateStr.split('-').map(Number)
  return new Date(y, m - 1, d).toLocaleDateString('en-US', {
    month: 'short', day: 'numeric', year: 'numeric',
  })
}

export function formatDateShort(dateStr) {
  if (!dateStr) return ''
  const [y, m, d] = dateStr.split('-').map(Number)
  return new Date(y, m - 1, d).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

export function formatDateRange(startDate, endDate) {
  if (!endDate || startDate === endDate) return formatDateShort(startDate)
  const [sy, sm] = startDate.split('-').map(Number)
  const [ey, em] = endDate.split('-').map(Number)
  if (sy === ey && sm === em) {
    const d1 = new Date(sy, sm - 1, Number(startDate.split('-')[2]))
    const d2 = new Date(ey, em - 1, Number(endDate.split('-')[2]))
    return `${d1.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}–${d2.getDate()}`
  }
  return `${formatDateShort(startDate)}–${formatDateShort(endDate)}`
}

export function getDurationLabel(startDate, endDate) {
  if (!endDate || startDate === endDate) return null
  const days = Math.round((new Date(endDate) - new Date(startDate)) / 86400000) + 1
  if (days < 8) return `${days} day${days === 1 ? '' : 's'}`
  const weeks = Math.round(days / 7)
  return `${weeks} week${weeks === 1 ? '' : 's'}`
}

export function getYear(dateStr) {
  return dateStr ? dateStr.split('-')[0] : null
}

export function today() {
  return new Date().toISOString().split('T')[0]
}

export function groupEventsByYear(events) {
  const groups = {}
  for (const event of events) {
    const year = getYear(event.start_date) || 'Unknown'
    if (!groups[year]) groups[year] = []
    groups[year].push(event)
  }
  return Object.entries(groups).sort(([a], [b]) => b.localeCompare(a))
}
