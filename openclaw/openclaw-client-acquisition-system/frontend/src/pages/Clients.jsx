import { useEffect, useState } from 'react'
import axios from 'axios'
import { RefreshCw, DollarSign, Edit2, Check, X } from 'lucide-react'

const API = import.meta.env.VITE_API_URL || ''

const NICHE_LABELS = {
  law_firm: '🏛️ Law Firm',
  insurance: '🛡️ Insurance',
  real_estate: '🏡 Real Estate',
  general: '📋 General',
}

function EditableRevenue({ client, onSave }) {
  const [editing, setEditing] = useState(false)
  const [val, setVal] = useState(client.revenue || 0)

  const save = async () => {
    await onSave(client.id, { revenue: parseFloat(val) })
    setEditing(false)
  }

  if (!editing) {
    return (
      <button
        onClick={() => setEditing(true)}
        className="flex items-center gap-1 text-gray-700 hover:text-violet-600 transition-colors group"
      >
        <span className="font-semibold">${(client.revenue || 0).toLocaleString()}</span>
        <Edit2 size={12} className="opacity-0 group-hover:opacity-100" />
      </button>
    )
  }

  return (
    <div className="flex items-center gap-1">
      <input
        type="number"
        className="input w-24 text-sm"
        value={val}
        onChange={e => setVal(e.target.value)}
        min={0}
        autoFocus
      />
      <button onClick={save} className="text-green-600 hover:text-green-700">
        <Check size={16} />
      </button>
      <button onClick={() => setEditing(false)} className="text-gray-400 hover:text-gray-600">
        <X size={16} />
      </button>
    </div>
  )
}

function EditableNotes({ client, onSave }) {
  const [editing, setEditing] = useState(false)
  const [val, setVal] = useState(client.notes || '')

  const save = async () => {
    await onSave(client.id, { notes: val })
    setEditing(false)
  }

  if (!editing) {
    return (
      <button
        onClick={() => setEditing(true)}
        className="text-left text-gray-500 hover:text-violet-600 text-sm transition-colors group flex items-start gap-1"
      >
        <span className="line-clamp-2">{client.notes || 'Click to add notes...'}</span>
        <Edit2 size={12} className="opacity-0 group-hover:opacity-100 flex-shrink-0 mt-0.5" />
      </button>
    )
  }

  return (
    <div className="space-y-1">
      <textarea
        className="input text-sm h-16 resize-none"
        value={val}
        onChange={e => setVal(e.target.value)}
        autoFocus
      />
      <div className="flex gap-2">
        <button onClick={save} className="text-xs text-green-600 font-medium hover:text-green-700">Save</button>
        <button onClick={() => setEditing(false)} className="text-xs text-gray-400 hover:text-gray-600">Cancel</button>
      </div>
    </div>
  )
}

export default function Clients() {
  const [clients, setClients] = useState([])
  const [loading, setLoading] = useState(true)

  const fetchClients = async () => {
    setLoading(true)
    try {
      const res = await axios.get(`${API}/api/clients/`)
      setClients(res.data)
    } catch (e) {
      console.error(e)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { fetchClients() }, [])

  const updateClient = async (id, data) => {
    await axios.patch(`${API}/api/clients/${id}`, data)
    setClients(prev => prev.map(c => c.id === id ? { ...c, ...data } : c))
  }

  const totalRevenue = clients.reduce((sum, c) => sum + (c.revenue || 0), 0)

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">Clients</h2>
          <p className="text-gray-500 text-sm">{clients.length} active clients</p>
        </div>
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2 bg-teal-50 border border-teal-200 px-4 py-2 rounded-lg">
            <DollarSign size={16} className="text-teal-600" />
            <span className="font-bold text-teal-700">${totalRevenue.toLocaleString()}</span>
            <span className="text-teal-600 text-sm">total revenue</span>
          </div>
          <button onClick={fetchClients} className="btn-secondary flex items-center gap-1">
            <RefreshCw size={14} className={loading ? 'animate-spin' : ''} />
          </button>
        </div>
      </div>

      {loading ? (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {[...Array(3)].map((_, i) => (
            <div key={i} className="card animate-pulse h-40 bg-gray-100" />
          ))}
        </div>
      ) : clients.length === 0 ? (
        <div className="card text-center py-16 text-gray-400">
          <p className="text-lg font-medium mb-2">No clients yet</p>
          <p className="text-sm">Clients appear here after prospects complete the intake form and are onboarded.</p>
          <a href="/intake" target="_blank" className="btn-primary mt-4 inline-block">
            View Intake Form
          </a>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {clients.map(client => (
            <div key={client.id} className="card space-y-3">
              <div className="flex items-start justify-between gap-2">
                <div>
                  <h3 className="font-semibold text-gray-900">{client.business_name}</h3>
                  <p className="text-sm text-gray-500">{client.email}</p>
                </div>
                <span className="badge bg-violet-100 text-violet-700 flex-shrink-0">
                  {NICHE_LABELS[client.niche] || client.niche}
                </span>
              </div>

              <div className="flex items-center gap-2 pt-1 border-t border-gray-50">
                <span className="text-xs text-gray-500 font-medium">Revenue:</span>
                <EditableRevenue client={client} onSave={updateClient} />
              </div>

              <div className="space-y-1">
                <span className="text-xs text-gray-500 font-medium">Notes:</span>
                <EditableNotes client={client} onSave={updateClient} />
              </div>

              <div className="text-xs text-gray-400 pt-1 border-t border-gray-50">
                Client since {new Date(client.created_at).toLocaleDateString()}
                {client.config_path && (
                  <span className="ml-2 text-green-600">✓ Config generated</span>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
