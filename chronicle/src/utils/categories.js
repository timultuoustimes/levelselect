import { supabase } from './supabase'
import { getDeviceId } from './storage'

export const DEFAULT_CATEGORIES = [
  { name: 'Health',   color: '#3b82f6', icon: 'Heart',  sort_order: 0 },
  { name: 'Travel',   color: '#f97316', icon: 'Plane',  sort_order: 1 },
  { name: 'Projects', color: '#a855f7', icon: 'Folder', sort_order: 2 },
  { name: 'Family',   color: '#22c55e', icon: 'Users',  sort_order: 3 },
  { name: 'Home',     color: '#f59e0b', icon: 'Home',   sort_order: 4 },
]

export async function fetchCategories() {
  const deviceId = getDeviceId()
  const { data, error } = await supabase
    .from('categories')
    .select('*')
    .eq('device_id', deviceId)
    .order('sort_order', { ascending: true })
  if (error) throw error
  return data
}

export async function saveCategory(category) {
  const deviceId = getDeviceId()
  if (category.id) {
    const { data, error } = await supabase
      .from('categories')
      .update({ name: category.name, color: category.color, icon: category.icon, sort_order: category.sort_order ?? 0 })
      .eq('id', category.id)
      .eq('device_id', deviceId)
      .select().single()
    if (error) throw error
    return data
  }
  const { data, error } = await supabase
    .from('categories')
    .insert({ ...category, device_id: deviceId })
    .select().single()
  if (error) throw error
  return data
}

export async function deleteCategory(id) {
  const deviceId = getDeviceId()
  const { error } = await supabase
    .from('categories').delete().eq('id', id).eq('device_id', deviceId)
  if (error) throw error
}

export async function seedDefaultCategories() {
  const deviceId = getDeviceId()
  const rows = DEFAULT_CATEGORIES.map(c => ({ ...c, device_id: deviceId }))
  const { error } = await supabase.from('categories').insert(rows)
  if (error) throw error
}
