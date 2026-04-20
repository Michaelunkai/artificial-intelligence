import { useState } from 'react'
import axios from 'axios'
import { Send, Save, ToggleLeft, ToggleRight } from 'lucide-react'

const API = import.meta.env.VITE_API_URL || ''

const TEMPLATES = {
  law_firm: {
    subject: 'AI Automation for Law Firms — Free Setup Demo',
    preview: 'Hello {{business_name}},\n\nI hope this message finds you well. My name is Alex from OpenClaw, and I\'m reaching out because we specialize in helping law firms like yours eliminate repetitive administrative work using AI automation.\n\nHere\'s what our law firm clients are automating today:\n✓ Document Automation — Auto-generate contracts, briefs, and intake forms\n✓ Client Intake — Smart forms that qualify leads automatically\n✓ Legal Research Assist — AI-summarized case law, saving 3-5 hours per case\n✓ Deadline & Calendar Management — Never miss a filing deadline\n✓ Email & Follow-up Sequences — Automated client updates\n\nWe offer a completely free setup demo. Book yours at: https://openclaw.io/intake\n\nBest,\nAlex\nOpenClaw Automation Team',
  },
  insurance: {
    subject: 'Automate Your Insurance Workflow — No Code Required',
    preview: 'Hello {{business_name}},\n\nI\'m reaching out from OpenClaw because insurance professionals are losing thousands of hours to manual processes that AI can handle instantly.\n\nWhat insurance agencies automate with OpenClaw:\n✓ Claims Processing — Automatically triage and route claims\n✓ Client Follow-ups — Automated renewal reminders\n✓ Client Onboarding — Smart intake forms\n✓ Quote Generation — AI-assisted quote prep, 70% faster\n✓ Compliance Tracking — Automated deadline alerts\n\nNo coding required. Free demo at: https://openclaw.io/intake\n\nBest,\nAlex\nOpenClaw Automation Team',
  },
  real_estate: {
    subject: 'AI Tools for Real Estate Professionals',
    preview: 'Hello {{business_name}},\n\nReal estate moves fast — and the agents who close the most deals automate the time-wasters. I\'m from OpenClaw.\n\nTop agents use OpenClaw to automate:\n✓ Listing Research — Market analysis in minutes\n✓ Lead Nurturing — Automated follow-up sequences\n✓ Property Descriptions — AI-generated from basic data\n✓ Showing Scheduler — Smart calendar booking\n✓ CRM Updates — Auto-log calls and visits\n\nFree personalized demo: https://openclaw.io/intake\n\nBest,\nAlex\nOpenClaw Automation Team',
  },
}

export default function Outreach() {
  const [activeNiche, setActiveNiche] = useState('law_firm')
  const [templates, setTemplates] = useState(TEMPLATES)
  const [autoSend, setAutoSend] = useState(true)
  const [dailyLimit, setDailyLimit] = useState(50)
  const [sending, setSending] = useState(false)
  const [saveMsg, setSaveMsg] = useState('')

  const handleSave = () => {
    setSaveMsg('Template saved!')
    setTimeout(() => setSaveMsg(''), 2000)
  }

  const handleTriggerOutreach = async () => {
    setSending(true)
    try {
      const res = await axios.post(`${API}/api/outreach/trigger`)
      alert(res.data.message)
    } catch (e) {
      alert('Error triggering outreach: ' + (e.response?.data?.detail || e.message))
    } finally {
      setSending(false)
    }
  }

  const niches = [
    { key: 'law_firm', label: '🏛️ Law Firm' },
    { key: 'insurance', label: '🛡️ Insurance' },
    { key: 'real_estate', label: '🏡 Real Estate' },
  ]

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold text-gray-900">Outreach</h2>
        <p className="text-gray-500 text-sm">Manage email templates and outreach settings</p>
      </div>

      {/* Settings bar */}
      <div className="card flex flex-wrap items-center gap-6">
        <div className="flex items-center gap-3">
          <span className="text-sm font-medium text-gray-700">Auto-Send Daily</span>
          <button
            onClick={() => setAutoSend(!autoSend)}
            className={`transition-colors ${autoSend ? 'text-violet-600' : 'text-gray-400'}`}
          >
            {autoSend ? <ToggleRight size={32} /> : <ToggleLeft size={32} />}
          </button>
          <span className={`text-xs font-medium ${autoSend ? 'text-green-600' : 'text-gray-400'}`}>
            {autoSend ? 'Enabled (10am UTC)' : 'Disabled'}
          </span>
        </div>
        <div className="flex items-center gap-2">
          <label className="text-sm font-medium text-gray-700">Daily Limit:</label>
          <input
            type="number"
            className="input w-24"
            min={1}
            max={500}
            value={dailyLimit}
            onChange={e => setDailyLimit(Number(e.target.value))}
          />
          <span className="text-xs text-gray-400">emails/day</span>
        </div>
        <button
          onClick={handleTriggerOutreach}
          disabled={sending}
          className="btn-primary flex items-center gap-2 ml-auto"
        >
          <Send size={14} />
          {sending ? 'Sending...' : 'Send Now'}
        </button>
      </div>

      {/* Template editor */}
      <div className="card">
        <div className="flex flex-wrap items-center gap-3 mb-4">
          <h3 className="font-semibold text-gray-800">Email Templates</h3>
          <div className="flex gap-2 ml-auto">
            {niches.map(n => (
              <button
                key={n.key}
                onClick={() => setActiveNiche(n.key)}
                className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                  activeNiche === n.key
                    ? 'bg-violet-600 text-white'
                    : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                }`}
              >
                {n.label}
              </button>
            ))}
          </div>
        </div>

        <div className="space-y-3">
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1">Subject Line</label>
            <input
              className="input"
              value={templates[activeNiche].subject}
              onChange={e =>
                setTemplates(p => ({
                  ...p,
                  [activeNiche]: { ...p[activeNiche], subject: e.target.value },
                }))
              }
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1">
              Email Body (use {'{{business_name}}'} for personalization)
            </label>
            <textarea
              className="input font-mono text-xs h-64 resize-none"
              value={templates[activeNiche].preview}
              onChange={e =>
                setTemplates(p => ({
                  ...p,
                  [activeNiche]: { ...p[activeNiche], preview: e.target.value },
                }))
              }
            />
          </div>
          <div className="flex items-center gap-3">
            <button onClick={handleSave} className="btn-primary flex items-center gap-2">
              <Save size={14} />
              Save Template
            </button>
            {saveMsg && <span className="text-green-600 text-sm font-medium">{saveMsg}</span>}
          </div>
        </div>
      </div>

      {/* Info */}
      <div className="card bg-blue-50 border-blue-200">
        <h4 className="font-semibold text-blue-800 mb-2">💡 How Auto-Send Works</h4>
        <ul className="text-sm text-blue-700 space-y-1 list-disc ml-4">
          <li>Scraper runs daily at <strong>9:00 AM UTC</strong> — finds new leads on Google</li>
          <li>Outreach runs daily at <strong>10:00 AM UTC</strong> — sends to all "new" leads</li>
          <li>Each lead receives ONE email matched to their niche template</li>
          <li>Daily limit protects your sender reputation</li>
          <li>Lead status updates automatically: new → emailed</li>
        </ul>
      </div>
    </div>
  )
}
