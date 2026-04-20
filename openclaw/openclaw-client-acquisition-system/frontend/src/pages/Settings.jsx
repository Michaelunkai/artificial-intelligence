import { useState } from 'react'
import { Save, Eye, EyeOff } from 'lucide-react'

export default function Settings() {
  const [smtp, setSmtp] = useState({
    host: 'smtp.gmail.com',
    port: '465',
    user: '',
    pass: '',
    from_name: 'OpenClaw Team',
  })
  const [showPass, setShowPass] = useState(false)
  const [keywords, setKeywords] = useState(
    '"law firm" contact email\n"insurance agency" contact email\n"real estate agent" email'
  )
  const [pricing, setPricing] = useState([
    { tier: 'Starter', price: 97, description: 'Up to 5 automations, email support' },
    { tier: 'Professional', price: 297, description: 'Unlimited automations, priority support' },
    { tier: 'Enterprise', price: 997, description: 'Custom integrations, dedicated onboarding' },
  ])
  const [saved, setSaved] = useState(false)

  const handleSave = (e) => {
    e.preventDefault()
    // In production, save these to backend/env
    setSaved(true)
    setTimeout(() => setSaved(false), 2500)
  }

  return (
    <div className="space-y-6 max-w-2xl">
      <div>
        <h2 className="text-2xl font-bold text-gray-900">Settings</h2>
        <p className="text-gray-500 text-sm">Configure SMTP, scraping, and pricing</p>
      </div>

      <form onSubmit={handleSave} className="space-y-6">
        {/* SMTP Settings */}
        <div className="card space-y-4">
          <h3 className="font-semibold text-gray-800 flex items-center gap-2">
            📧 SMTP Configuration (Gmail)
          </h3>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-gray-500 mb-1">SMTP Host</label>
              <input
                className="input"
                value={smtp.host}
                onChange={e => setSmtp(p => ({ ...p, host: e.target.value }))}
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-500 mb-1">Port</label>
              <input
                className="input"
                value={smtp.port}
                onChange={e => setSmtp(p => ({ ...p, port: e.target.value }))}
              />
            </div>
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1">Gmail Address</label>
            <input
              type="email"
              className="input"
              placeholder="yourname@gmail.com"
              value={smtp.user}
              onChange={e => setSmtp(p => ({ ...p, user: e.target.value }))}
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1">App Password</label>
            <div className="relative">
              <input
                type={showPass ? 'text' : 'password'}
                className="input pr-10"
                placeholder="Gmail App Password (not your login password)"
                value={smtp.pass}
                onChange={e => setSmtp(p => ({ ...p, pass: e.target.value }))}
              />
              <button
                type="button"
                className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600"
                onClick={() => setShowPass(!showPass)}
              >
                {showPass ? <EyeOff size={16} /> : <Eye size={16} />}
              </button>
            </div>
            <p className="text-xs text-gray-400 mt-1">
              Generate at: Google Account → Security → 2-Step Verification → App Passwords
            </p>
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1">From Name</label>
            <input
              className="input"
              value={smtp.from_name}
              onChange={e => setSmtp(p => ({ ...p, from_name: e.target.value }))}
            />
          </div>
        </div>

        {/* Scraping Keywords */}
        <div className="card space-y-3">
          <h3 className="font-semibold text-gray-800">🔍 Scraping Keywords</h3>
          <p className="text-xs text-gray-500">One search query per line. Used by the daily scraper.</p>
          <textarea
            className="input h-32 font-mono text-xs resize-none"
            value={keywords}
            onChange={e => setKeywords(e.target.value)}
          />
        </div>

        {/* Pricing Tiers */}
        <div className="card space-y-4">
          <h3 className="font-semibold text-gray-800">💰 Pricing Tiers</h3>
          <div className="space-y-3">
            {pricing.map((tier, i) => (
              <div key={i} className="flex gap-3 items-start p-3 bg-gray-50 rounded-lg">
                <div className="flex-1">
                  <input
                    className="input mb-2"
                    placeholder="Tier name"
                    value={tier.tier}
                    onChange={e => setPricing(prev => prev.map((t, j) => j === i ? { ...t, tier: e.target.value } : t))}
                  />
                  <input
                    className="input text-xs"
                    placeholder="Description"
                    value={tier.description}
                    onChange={e => setPricing(prev => prev.map((t, j) => j === i ? { ...t, description: e.target.value } : t))}
                  />
                </div>
                <div className="w-28">
                  <label className="block text-xs text-gray-400 mb-1">$/month</label>
                  <input
                    type="number"
                    className="input"
                    value={tier.price}
                    onChange={e => setPricing(prev => prev.map((t, j) => j === i ? { ...t, price: Number(e.target.value) } : t))}
                  />
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="flex items-center gap-3">
          <button type="submit" className="btn-primary flex items-center gap-2">
            <Save size={14} />
            Save Settings
          </button>
          {saved && (
            <span className="text-green-600 text-sm font-medium">✓ Settings saved!</span>
          )}
        </div>

        <div className="card bg-amber-50 border-amber-200">
          <h4 className="font-semibold text-amber-800 mb-1">⚠️ Production Note</h4>
          <p className="text-sm text-amber-700">
            SMTP credentials and settings should be stored as environment variables in production.
            Set <code className="bg-amber-100 px-1 rounded">SMTP_USER</code>, <code className="bg-amber-100 px-1 rounded">SMTP_PASS</code>, and other vars in your Render dashboard or <code className="bg-amber-100 px-1 rounded">.env</code> file locally.
          </p>
        </div>
      </form>
    </div>
  )
}
