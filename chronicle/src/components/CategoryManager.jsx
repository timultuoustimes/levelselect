import { useState } from 'react'
import { Plus, Trash2, Check, X } from 'lucide-react'
import { saveCategory, deleteCategory } from '../utils/categories'

const PRESET_COLORS = [
  '#3b82f6', '#f97316', '#a855f7', '#22c55e', '#f59e0b',
  '#ef4444', '#06b6d4', '#ec4899', '#84cc16', '#6366f1',
]

export default function CategoryManager({ categories, onCategoriesChange }) {
  const [editing, setEditing]   = useState(null) // null | 'new' | category obj
  const [form, setForm]         = useState({})
  const [saving, setSaving]     = useState(false)

  function startNew() {
    setEditing('new')
    setForm({ name: '', color: PRESET_COLORS[0], icon: '' })
  }

  function startEdit(cat) {
    setEditing(cat)
    setForm({ name: cat.name, color: cat.color, icon: cat.icon ?? '' })
  }

  async function handleSave() {
    if (!form.name.trim()) return
    setSaving(true)
    try {
      const payload = {
        ...(editing !== 'new' ? { id: editing.id } : {}),
        name: form.name.trim(),
        color: form.color,
        icon: form.icon || null,
        sort_order: editing !== 'new' ? (editing.sort_order ?? 0) : categories.length,
      }
      const saved = await saveCategory(payload)
      if (editing === 'new') {
        onCategoriesChange([...categories, saved])
      } else {
        onCategoriesChange(categories.map(c => c.id === saved.id ? saved : c))
      }
      setEditing(null)
    } catch (err) {
      console.error(err)
    } finally {
      setSaving(false)
    }
  }

  async function handleDelete(cat) {
    if (!confirm(`Delete "${cat.name}"? Events in this category will be uncategorized.`)) return
    try {
      await deleteCategory(cat.id)
      onCategoriesChange(categories.filter(c => c.id !== cat.id))
    } catch (err) {
      console.error(err)
    }
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h3 className="font-semibold text-gray-900">Categories</h3>
        <button
          onClick={startNew}
          className="flex items-center gap-1 text-sm text-gray-600 hover:text-gray-900 border border-gray-200 rounded-lg px-3 py-1.5 bg-white hover:bg-gray-50"
        >
          <Plus className="w-4 h-4" />
          New
        </button>
      </div>

      <div className="flex flex-col gap-2">
        {categories.map(cat => (
          <div key={cat.id}>
            {editing === cat ? (
              <CategoryForm
                form={form}
                setForm={setForm}
                onSave={handleSave}
                onCancel={() => setEditing(null)}
                saving={saving}
              />
            ) : (
              <div className="flex items-center gap-3 bg-white border border-gray-100 rounded-xl px-4 py-3">
                <span className="w-4 h-4 rounded-full shrink-0" style={{ backgroundColor: cat.color }} />
                <span className="flex-1 text-sm font-medium text-gray-800">{cat.name}</span>
                <button
                  onClick={() => startEdit(cat)}
                  className="text-xs text-gray-400 hover:text-gray-700 px-2 py-1 rounded hover:bg-gray-100"
                >
                  Edit
                </button>
                <button
                  onClick={() => handleDelete(cat)}
                  className="text-gray-300 hover:text-red-500 transition-colors"
                >
                  <Trash2 className="w-4 h-4" />
                </button>
              </div>
            )}
          </div>
        ))}

        {editing === 'new' && (
          <CategoryForm
            form={form}
            setForm={setForm}
            onSave={handleSave}
            onCancel={() => setEditing(null)}
            saving={saving}
          />
        )}
      </div>
    </div>
  )
}

function CategoryForm({ form, setForm, onSave, onCancel, saving }) {
  return (
    <div className="bg-white border-2 border-gray-200 rounded-xl px-4 py-3 flex flex-col gap-3">
      <input
        type="text"
        placeholder="Category name"
        value={form.name}
        onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
        autoFocus
        className="text-sm border border-gray-200 rounded-lg px-3 py-1.5 focus:outline-none focus:ring-2 focus:ring-gray-900/10 focus:border-gray-300"
      />
      <div>
        <p className="text-xs text-gray-500 mb-2">Color</p>
        <div className="flex gap-2 flex-wrap">
          {PRESET_COLORS.map(c => (
            <button
              key={c}
              onClick={() => setForm(f => ({ ...f, color: c }))}
              className="w-6 h-6 rounded-full ring-offset-1 transition-all"
              style={{
                backgroundColor: c,
                ringColor: c,
                outline: form.color === c ? `2px solid ${c}` : 'none',
                outlineOffset: '2px',
              }}
            />
          ))}
        </div>
      </div>
      <div className="flex gap-2">
        <button
          onClick={onSave}
          disabled={saving || !form.name.trim()}
          className="flex items-center gap-1 text-sm bg-gray-900 text-white rounded-lg px-3 py-1.5 hover:bg-gray-700 disabled:opacity-50"
        >
          <Check className="w-4 h-4" />
          Save
        </button>
        <button
          onClick={onCancel}
          className="text-sm text-gray-500 border border-gray-200 rounded-lg px-3 py-1.5 hover:bg-gray-50"
        >
          Cancel
        </button>
      </div>
    </div>
  )
}
