import { useEffect, useState } from 'react'
import axios from 'axios'
import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer,
  FunnelChart, Funnel, LabelList, Cell
} from 'recharts'
import { Users, Mail, TrendingUp, UserCheck, DollarSign, Eye, RefreshCw } from 'lucide-react'

const API = import.meta.env.VITE_API_URL || ''

const FUNNEL_COLORS = ['#7c3aed', '#8b5cf6', '#a78bfa', '#c4b5fd', '#ddd6fe']

function StatCard({ title, value, icon: Icon, color, sub }) {
  return (
    <div className="card flex items-start gap-4">
      <div className={`w-12 h-12 rounded-xl flex items-center justify-center flex-shrink-0 ${color}`}>
        <Icon size={22} className="text-white" />
      </div>
      <div className="min-w-0">
        <p className="text-sm text-gray-500 font-medium">{title}</p>
        <p className="text-2xl font-bold text-gray-900 mt-0.5">{value}</p>
        {sub && <p className="text-xs text-gray-400 mt-0.5">{sub}</p>}
      </div>
    </div>
  )
}

export default function Dashboard() {
  const [stats, setStats] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  const fetchStats = async () => {
    try {
      setLoading(true)
      const res = await axios.get(`${API}/api/stats`)
      setStats(res.data)
      setError(null)
    } catch (e) {
      setError('Could not load stats. Is the backend running?')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { fetchStats() }, [])

  const funnelData = stats ? [
    { name: 'Total Leads', value: stats.total_leads, fill: FUNNEL_COLORS[0] },
    { name: 'Emailed', value: stats.emails_sent_today, fill: FUNNEL_COLORS[1] },
    { name: 'Opened', value: Math.round(stats.emails_sent_today * (stats.open_rate / 100)), fill: FUNNEL_COLORS[2] },
    { name: 'Prospects', value: stats.total_prospects, fill: FUNNEL_COLORS[3] },
    { name: 'Clients', value: stats.total_clients, fill: FUNNEL_COLORS[4] },
  ] : []

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">Dashboard</h2>
          <p className="text-gray-500 text-sm mt-0.5">Client acquisition pipeline overview</p>
        </div>
        <button onClick={fetchStats} className="btn-secondary flex items-center gap-2">
          <RefreshCw size={14} className={loading ? 'animate-spin' : ''} />
          Refresh
        </button>
      </div>

      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 rounded-lg px-4 py-3 text-sm">
          {error}
        </div>
      )}

      {/* Stat cards */}
      {loading ? (
        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-4">
          {[...Array(6)].map((_, i) => (
            <div key={i} className="card animate-pulse h-24 bg-gray-100" />
          ))}
        </div>
      ) : stats ? (
        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-4">
          <StatCard
            title="Total Leads"
            value={stats.total_leads.toLocaleString()}
            icon={Users}
            color="bg-violet-600"
            sub="Scraped contacts in DB"
          />
          <StatCard
            title="Emails Sent Today"
            value={stats.emails_sent_today.toLocaleString()}
            icon={Mail}
            color="bg-blue-500"
            sub={`Max ${50}/day`}
          />
          <StatCard
            title="Open Rate"
            value={`${stats.open_rate}%`}
            icon={Eye}
            color="bg-emerald-500"
            sub="Of emails sent"
          />
          <StatCard
            title="Prospects"
            value={stats.total_prospects.toLocaleString()}
            icon={TrendingUp}
            color="bg-orange-500"
            sub="Intake form submissions"
          />
          <StatCard
            title="Clients"
            value={stats.total_clients.toLocaleString()}
            icon={UserCheck}
            color="bg-pink-500"
            sub="Onboarded clients"
          />
          <StatCard
            title="Est. Revenue"
            value={`$${stats.estimated_revenue.toLocaleString()}`}
            icon={DollarSign}
            color="bg-teal-500"
            sub="From active clients"
          />
        </div>
      ) : null}

      {/* Funnel Chart */}
      {stats && stats.total_leads > 0 && (
        <div className="card">
          <h3 className="font-semibold text-gray-800 mb-4">Acquisition Funnel</h3>
          <ResponsiveContainer width="100%" height={300}>
            <FunnelChart>
              <Tooltip formatter={(v, n) => [v, n]} />
              <Funnel
                dataKey="value"
                data={funnelData}
                isAnimationActive
              >
                <LabelList position="right" fill="#374151" stroke="none" dataKey="name" />
                {funnelData.map((entry, index) => (
                  <Cell key={index} fill={entry.fill} />
                ))}
              </Funnel>
            </FunnelChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* Quick actions */}
      <div className="card">
        <h3 className="font-semibold text-gray-800 mb-4">Quick Actions</h3>
        <div className="flex flex-wrap gap-3">
          <button
            onClick={async () => {
              await axios.post(`${API}/api/scrape/trigger`)
              alert('Scrape job triggered! Check back in a few minutes.')
            }}
            className="btn-primary"
          >
            🔍 Trigger Scrape Now
          </button>
          <button
            onClick={async () => {
              await axios.post(`${API}/api/outreach/trigger`)
              alert('Outreach emails triggered!')
            }}
            className="btn-primary"
          >
            📧 Send Outreach Now
          </button>
          <a href="/intake" target="_blank" className="btn-secondary">
            📋 View Intake Form
          </a>
        </div>
      </div>
    </div>
  )
}
