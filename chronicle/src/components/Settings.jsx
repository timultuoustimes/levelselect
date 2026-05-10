import { useState } from 'react'
import { Copy, Check, Download } from 'lucide-react'
import CategoryManager from './CategoryManager'
import { getShareLink } from '../utils/storage'

export default function Settings({ categories, events, onCategoriesChange }) {
  return (
    <div className="max-w-xl mx-auto px-6 py-8 flex flex-col gap-8">
      <h1 className="text-xl font-semibold text-gray-900">Settings</h1>

      <CategoryManager categories={categories} onCategoriesChange={onCategoriesChange} />

      <DeviceSync />

      <DataExport events={events} categories={categories} />
    </div>
  )
}

function DeviceSync() {
  const [copied, setCopied] = useState(false)
  const [link, setLink]     = useState(null)

  function handleCopy() {
    const url = getShareLink()
    setLink(url)
    navigator.clipboard.writeText(url).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 2500)
    })
  }

  return (
    <section>
      <h3 className="font-semibold text-gray-900 mb-1">Sync to another device</h3>
      <p className="text-sm text-gray-500 mb-3">
        Open this link on another device to adopt your Chronicle data there. Both devices will share the same timeline.
      </p>
      <button
        onClick={handleCopy}
        className="flex items-center gap-2 text-sm font-medium border border-gray-200 rounded-xl px-4 py-2.5 bg-white hover:bg-gray-50 transition-colors"
      >
        {copied ? <Check className="w-4 h-4 text-green-500" /> : <Copy className="w-4 h-4 text-gray-500" />}
        {copied ? 'Link copied!' : 'Copy sync link'}
      </button>
      {link && (
        <p className="text-xs text-gray-400 mt-2 break-all font-mono">{link}</p>
      )}
    </section>
  )
}

function DataExport({ events, categories }) {
  function handleExport() {
    const payload = JSON.stringify({ events, categories }, null, 2)
    const blob    = new Blob([payload], { type: 'application/json' })
    const url     = URL.createObjectURL(blob)
    const a       = document.createElement('a')
    a.href        = url
    a.download    = `chronicle-export-${new Date().toISOString().split('T')[0]}.json`
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <section>
      <h3 className="font-semibold text-gray-900 mb-1">Export data</h3>
      <p className="text-sm text-gray-500 mb-3">
        Download all your events and categories as JSON.
      </p>
      <button
        onClick={handleExport}
        className="flex items-center gap-2 text-sm font-medium border border-gray-200 rounded-xl px-4 py-2.5 bg-white hover:bg-gray-50 transition-colors"
      >
        <Download className="w-4 h-4 text-gray-500" />
        Export JSON
      </button>
    </section>
  )
}
