import { supabase } from './supabase'
import { getDeviceId } from './storage'

const EVENT_SELECT = `
  *,
  category:categories(id, name, color, icon),
  photos:event_photos(id, storage_path, caption, sort_order)
`

export async function fetchEvents() {
  const deviceId = getDeviceId()
  const { data, error } = await supabase
    .from('events')
    .select(EVENT_SELECT)
    .eq('device_id', deviceId)
    .order('start_date', { ascending: false })
  if (error) throw error
  return data
}

export async function saveEvent(event) {
  const deviceId = getDeviceId()
  const payload = {
    title:       event.title,
    subtitle:    event.subtitle    || null,
    start_date:  event.start_date,
    end_date:    event.end_date    || null,
    category_id: event.category_id || null,
    notes:       event.notes       || null,
    location:    event.location    || null,
    tags:        event.tags        || [],
    people:      event.people      || [],
    links:       event.links       || [],
    parent_id:   event.parent_id   || null,
    updated_at:  new Date().toISOString(),
  }
  if (event.id) {
    const { data, error } = await supabase
      .from('events')
      .update(payload)
      .eq('id', event.id)
      .eq('device_id', deviceId)
      .select(EVENT_SELECT).single()
    if (error) throw error
    return data
  }
  const { data, error } = await supabase
    .from('events')
    .insert({ ...payload, device_id: deviceId })
    .select(EVENT_SELECT).single()
  if (error) throw error
  return data
}

export async function deleteEvent(id) {
  const deviceId = getDeviceId()
  const { error } = await supabase
    .from('events').delete().eq('id', id).eq('device_id', deviceId)
  if (error) throw error
}

export function applyFilters(events, filters) {
  let result = events
  if (filters.categoryIds?.length) {
    result = result.filter(e => filters.categoryIds.includes(e.category_id))
  }
  if (filters.dateFrom) {
    result = result.filter(e => e.start_date >= filters.dateFrom)
  }
  if (filters.dateTo) {
    result = result.filter(e => e.start_date <= filters.dateTo)
  }
  if (filters.tags?.length) {
    result = result.filter(e => filters.tags.some(t => e.tags?.includes(t)))
  }
  if (filters.people?.length) {
    result = result.filter(e => filters.people.some(p => e.people?.includes(p)))
  }
  if (filters.search) {
    const q = filters.search.toLowerCase()
    result = result.filter(e =>
      e.title?.toLowerCase().includes(q) ||
      e.subtitle?.toLowerCase().includes(q) ||
      e.notes?.toLowerCase().includes(q) ||
      e.location?.toLowerCase().includes(q)
    )
  }
  return result
}
