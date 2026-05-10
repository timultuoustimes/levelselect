import { supabase } from './supabase'
import { getDeviceId } from './storage'

const BUCKET = 'event-photos'

export async function uploadPhoto(eventId, file) {
  const deviceId = getDeviceId()
  const ext = file.name.split('.').pop().toLowerCase()
  const path = `${deviceId}/${eventId}/${crypto.randomUUID()}.${ext}`

  const { error: uploadError } = await supabase.storage
    .from(BUCKET)
    .upload(path, file, { cacheControl: '3600', upsert: false })
  if (uploadError) throw uploadError

  const { data, error } = await supabase
    .from('event_photos')
    .insert({ event_id: eventId, device_id: deviceId, storage_path: path, sort_order: Date.now() })
    .select().single()
  if (error) throw error
  return data
}

export async function deletePhoto(photoId, storagePath) {
  const deviceId = getDeviceId()
  await supabase.storage.from(BUCKET).remove([storagePath])
  const { error } = await supabase
    .from('event_photos')
    .delete()
    .eq('id', photoId)
    .eq('device_id', deviceId)
  if (error) throw error
}

export function getPhotoUrl(storagePath) {
  const { data } = supabase.storage.from(BUCKET).getPublicUrl(storagePath)
  return data.publicUrl
}
