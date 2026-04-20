import { useEffect, useState } from 'react'
import axios from 'axios'
import { Search, Filter, Plus, RefreshCw, ExternalLink } from 'lucide-react'

const API = import.meta.env.VITE_API_URL || ''

const STATUS_COLORS = {
  new: 'bg-gray-100 text-gray-700',
  emailed: 'bg-blue-100 text-blue-700',
  opened: 'bg-yellow-100 text-yellow-700',
  replied: 'bg-purple-100 text-purple-700',
  converted: 'bg-green-100 text-green-700',
}

const NICHE_LABELS = {
  law_firm: '🏛️ Law Firm',
  insurance: '🛡️ Insurance',
  real_estate: '🏡 Real Estate',
  general: '📋 General',
}

function StatusBadge({ status }) {
  return (
    <span className={`badge ${STATUS_COLORS[status] || 'bg-gray-100 text-gray-600'}`}>
      {status}
    </span>
  )
}

export default function Leads() {
  const [leads, setLeads] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [nicheFilter, setNicheFilter] = useState('')
  const [showAdd, setShowAdd] = useState(false)
  const [newLead, setNewLead] = useState({ business_name: '', email: '', niche: 'general', status: 'new' })

  const fetchLeads = async () => {
    setLoading(true)
    try {
      const params = {}
      if (search) params.search = search
      if (statusFilter) params.status = statusFilter
      if (nicheFilter) params.niche = nicheFilter
      const res = await axios.get(`${API}/api/leads/`, { params })
      setLeads(res.data)
    } catch (e) {
      console.error(e)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { fetchLeads() }, [search, statusFilter, nicheFilter])

  const updateStatus = async (id, status) => {
    await axios.patch(`${API}/api/leads/${id}`, { status })
    fetchLeads()
  }

  const addLead = async (e) => {
    e.preventDefault()
    try {
      await axios.post(`${API}/api/leads/`, newLead)
      setShowAdd(false)
      setNewLead({ business_name: '', email: '', niche: 'general', status: 'new' })
      fetchLeads()
    } catch (e) {
      alert(e.response?.data?.detail || 'Error adding lead')
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">Leads</h2>
          <p className="text-gray-500 text-sm">{leads.length} leads found</p>
        </div>
        <div className="flex gap-2">
          <button onClick={fetchLeads} className="btn-secondary flex items-center gap-1">
            <RefreshCw size={14} className={loading ? 'animate-spin' : ''} />
          </button>
          <button onClick={() => setShowAdd(!showAdd)} className="btn-primary flex items-center gap-1">
            <Plus size={14} />
            Add Lead
          </button>
        </div>
      </div>

      {/* Add lead form */}
      {showAdd && (
        <div className="card border-violet-200">
          <h3 className="font-semibold text-gray-800 mb-3">Add New Lead</h3>
          <form onSubmit={addLead} className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <input
              required
              className="input"
              placeholder="Business name"
              value={newLead.business_name}
              onChange={e => setNewLead(p => ({ ...p, business_name: e.target.value }))}
            />
            <input
              required
              type="email"
              className="input"
              placeholder="Email"
              value={newLead.email}
              onChange={e => setNewLead(p => ({ ...p, email: e.target.value }))}
            />
            <select
              className="input"
              value={newLead.niche}
              onChange={e => setNewLead(p => ({ ...p, niche: e.target.value }))}
            >
              <option value="general">General</option>
              <option value="law_firm">Law Firm</option>
              <option value="insurance">Insurance</option>
              <option value="real_estate">Real Estate</option>
            </select>
            <div className="flex gap-2">
              <button type="submit" className="btn-primary flex-1">Save</button>
              <button type="button" onClick={() => setShowAdd(false)} className="btn-secondary flex-1">Cancel</button>
            </div>
          </form>
        </div>
      )}

      {/* Filters */}
      <div className="flex flex-wrap gap-3">
        <div className="relative flex-1 min-w-[200px]">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
          <input
            className="input pl-9"
            placeholder="Search leads..."
            value={search}
            onChange={e => setSearch(e.target.value)}
          />
        </div>
        <select className="input w-auto" value={statusFilter} onChange={e => setStatusFilter(e.target.value)}>
          <option value="">All Status</option>
          <option value="new">New</option>
          <option value="emailed">Emailed</option>
          <option value="opened">Opened</option>
          <option value="replied">Replied</option>
          <option value="converted">Converted</option>
        </select>
        <select className="input w-auto" value={nicheFilter} onChange={e => setNicheFilter(e.target.value)}>
          <option value="">All Niches</option>
          <option value="law_firm">Law Firm</option>
          <option value="insurance">Insurance</option>
          <option value="real_estate">Real Estate</option>
          <option value="general">General</option>
        </select>
      </div>

      {/* Table */}
      <div className="card p-0 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-gray-100 bg-gray-50">
                <th className="text-left px-4 py-3 font-semibold text-gray-600">Business</th>
                <th className="text-left px-4 py-3 font-semibold text-gray-600">Email</th>
                <th className="text-left px-4 py-3 font-semibold text-gray-600">Niche</th>
                <th className="text-left px-4 py-3 font-semibold text-gray-600">Status</th>
                <th className="text-left px-4 py-3 font-semibold text-gray-600">Date</th>
                <th className="text-left px-4 py-3 font-semibold text-gray-600">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-50">
              {loading ? (
                <tr>
                  <td colSpan="6" className="text-center py-12 text-gray-400">Loading leads...</td>
                </tr>
              ) : leads.length === 0 ? (
                <tr>
                  <td colSpan="6" className="text-center py-12 text-gray-400">
                    No leads found. Try triggering a scrape from the Dashboard.
                  </td>
                </tr>
              ) : leads.map(lead => (
                <tr key={lead.id} className="hover:bg-gray-50 transition-colors">
                  <td className="px-4 py-3 font-medium text-gray-900">{lead.business_name || '—'}</td>
                  <td className="px-4 py-3 text-gray-600">{lead.email}</td>
                  <td className="px-4 py-3">
                    <span className="text-xs text-gray-600">{NICHE_LABELS[lead.niche] || lead.niche}</span>
                  </td>
                  <td className="px-4 py-3">
                    <StatusBadge status={lead.status} />
                  </td>
                  <td className="px-4 py-3 text-gray-400 text-xs">
                    {new Date(lead.created_at).toLocaleDateString()}
                  </td>
                  <td className="px-4 py-3">
                    <select
                      className="text-xs border border-gray-200 rounded px-2 py-1 text-gray-600 cursor-pointer"
                      value={lead.status}
                      onChange={e => updateStatus(lead.id, e.target.value)}
                    >
                      <option value="new">new</option>
                      <option value="emailed">emailed</option>
                      <option value="opened">opened</option>
                      <option value="replied">replied</option>
                      <option value="converted">converted</option>
                    </select>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
