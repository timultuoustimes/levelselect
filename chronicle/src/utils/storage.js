import { supabase } from './supabase'

const DEVICE_ID_KEY = 'chronicle_device_id'

export function getDeviceId() {
  let id = localStorage.getItem(DEVICE_ID_KEY)
  if (!id) {
    id = crypto.randomUUID()
    localStorage.setItem(DEVICE_ID_KEY, id)
  }
  return id
}

export async function ensureDevice() {
  const deviceId = getDeviceId()
  await supabase.from('devices').upsert({ id: deviceId }, { onConflict: 'id' })
  return deviceId
}

export function getShareLink() {
  const deviceId = getDeviceId()
  const url = new URL(window.location.href)
  url.searchParams.set('adopt', deviceId)
  return url.toString()
}

export function checkAndAdoptFromUrl() {
  const url = new URL(window.location.href)
  const adopt = url.searchParams.get('adopt')
  if (adopt && adopt !== getDeviceId()) {
    localStorage.setItem(DEVICE_ID_KEY, adopt)
    url.searchParams.delete('adopt')
    window.history.replaceState({}, '', url.toString())
    return adopt
  }
  return null
}
