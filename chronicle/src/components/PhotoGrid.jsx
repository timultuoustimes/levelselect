import { useState, useRef } from 'react'
import { X, Upload, ZoomIn } from 'lucide-react'
import { uploadPhoto, deletePhoto, getPhotoUrl } from '../utils/photos'

export default function PhotoGrid({ eventId, photos = [], onPhotosChange, editable = false }) {
  const [lightbox, setLightbox] = useState(null)
  const [uploading, setUploading] = useState(false)
  const fileRef = useRef()

  async function handleUpload(e) {
    const files = Array.from(e.target.files)
    if (!files.length) return
    setUploading(true)
    try {
      const uploaded = await Promise.all(files.map(f => uploadPhoto(eventId, f)))
      onPhotosChange?.([...photos, ...uploaded])
    } catch (err) {
      console.error('Upload failed', err)
    } finally {
      setUploading(false)
      e.target.value = ''
    }
  }

  async function handleDelete(photo) {
    try {
      await deletePhoto(photo.id, photo.storage_path)
      onPhotosChange?.(photos.filter(p => p.id !== photo.id))
    } catch (err) {
      console.error('Delete failed', err)
    }
  }

  if (!photos.length && !editable) return null

  return (
    <>
      <div className="grid grid-cols-3 gap-1.5">
        {photos
          .slice()
          .sort((a, b) => a.sort_order - b.sort_order)
          .map(photo => (
            <div key={photo.id} className="relative group aspect-square rounded-lg overflow-hidden bg-gray-100">
              <img
                src={getPhotoUrl(photo.storage_path)}
                alt={photo.caption ?? ''}
                className="w-full h-full object-cover"
              />
              <button
                onClick={() => setLightbox(photo)}
                className="absolute inset-0 bg-black/0 group-hover:bg-black/20 transition-colors flex items-center justify-center"
              >
                <ZoomIn className="w-5 h-5 text-white opacity-0 group-hover:opacity-100 transition-opacity" />
              </button>
              {editable && (
                <button
                  onClick={() => handleDelete(photo)}
                  className="absolute top-1 right-1 w-5 h-5 rounded-full bg-black/60 text-white flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity"
                >
                  <X className="w-3 h-3" />
                </button>
              )}
            </div>
          ))}

        {editable && (
          <button
            onClick={() => fileRef.current?.click()}
            disabled={uploading}
            className="aspect-square rounded-lg border-2 border-dashed border-gray-200 hover:border-gray-400 flex flex-col items-center justify-center gap-1 text-gray-400 hover:text-gray-600 transition-colors disabled:opacity-50"
          >
            <Upload className="w-5 h-5" />
            <span className="text-xs">{uploading ? 'Uploading…' : 'Add photo'}</span>
          </button>
        )}
      </div>

      <input
        ref={fileRef}
        type="file"
        accept="image/*"
        multiple
        className="hidden"
        onChange={handleUpload}
      />

      {lightbox && (
        <div
          className="fixed inset-0 z-50 bg-black/90 flex items-center justify-center p-4"
          onClick={() => setLightbox(null)}
        >
          <button className="absolute top-4 right-4 text-white/80 hover:text-white">
            <X className="w-6 h-6" />
          </button>
          <img
            src={getPhotoUrl(lightbox.storage_path)}
            alt={lightbox.caption ?? ''}
            className="max-w-full max-h-full object-contain rounded-lg"
            onClick={e => e.stopPropagation()}
          />
          {lightbox.caption && (
            <p className="absolute bottom-6 left-1/2 -translate-x-1/2 text-white/80 text-sm bg-black/50 px-3 py-1 rounded-full">
              {lightbox.caption}
            </p>
          )}
        </div>
      )}
    </>
  )
}
