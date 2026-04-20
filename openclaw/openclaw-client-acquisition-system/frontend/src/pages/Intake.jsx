import { useState } from 'react'
import axios from 'axios'
import { Zap, CheckCircle, Loader } from 'lucide-react'

const API = import.meta.env.VITE_API_URL || ''

export default function Intake() {
  const [form, setForm] = useState({
    business_name: '',
    industry: 'Law Firm',
    pain_point: '',
    email: '',
    phone: '',
    schedule_call: false,
  })
  const [loading, setLoading] = useState(false)
  const [submitted, setSubmitted] = useState(false)
  const [error, setError] = useState(null)

  const update = (key, val) => setForm(p => ({ ...p, [key]: val }))

  const handleSubmit = async (e) => {
    e.preventDefault()
    setLoading(true)
    setError(null)
    try {
      await axios.post(`${API}/api/prospects/`, form)
      setSubmitted(true)
    } catch (err) {
      setError(err.response?.data?.detail || 'Something went wrong. Please try again.')
    } finally {
      setLoading(false)
    }
  }

  if (submitted) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-violet-50 to-purple-100 flex items-center justify-center p-4">
        <div className="max-w-md w-full text-center space-y-6">
          <div className="w-20 h-20 bg-green-100 rounded-full flex items-center justify-center mx-auto">
            <CheckCircle size={42} className="text-green-600" />
          </div>
          <h1 className="text-3xl font-bold text-gray-900">You're all set! 🎉</h1>
          <p className="text-gray-600 text-lg">
            Thank you, <strong>{form.business_name}</strong>! We've received your submission.
          </p>
          <div className="bg-white rounded-xl p-6 shadow-sm border border-gray-100 text-left space-y-3">
            <h3 className="font-semibold text-gray-800">What happens next:</h3>
            <div className="flex items-start gap-3">
              <span className="w-6 h-6 bg-violet-100 text-violet-700 rounded-full flex items-center justify-center text-sm font-bold flex-shrink-0">1</span>
              <p className="text-sm text-gray-600">We're generating your custom OpenClaw workspace config for <strong>{form.industry}</strong></p>
            </div>
            <div className="flex items-start gap-3">
              <span className="w-6 h-6 bg-violet-100 text-violet-700 rounded-full flex items-center justify-center text-sm font-bold flex-shrink-0">2</span>
              <p className="text-sm text-gray-600">You'll receive a welcome email at <strong>{form.email}</strong> with your config file</p>
            </div>
            <div className="flex items-start gap-3">
              <span className="w-6 h-6 bg-violet-100 text-violet-700 rounded-full flex items-center justify-center text-sm font-bold flex-shrink-0">3</span>
              <p className="text-sm text-gray-600">
                {form.schedule_call
                  ? 'Our team will reach out to schedule your onboarding call'
                  : 'Follow the setup instructions in your welcome email to get started'}
              </p>
            </div>
          </div>
          <a href="https://openclaw.io" className="btn-primary inline-block">
            Visit openclaw.io →
          </a>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-violet-50 to-purple-100 flex items-center justify-center p-4">
      <div className="max-w-lg w-full">
        {/* Header */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center gap-2 bg-violet-700 text-white px-4 py-2 rounded-full mb-4">
            <Zap size={16} className="text-yellow-300" />
            <span className="font-semibold text-sm">OpenClaw Automation</span>
          </div>
          <h1 className="text-4xl font-bold text-gray-900 mb-3">
            Automate Your Business
          </h1>
          <p className="text-gray-600 text-lg">
            Tell us about your business and we'll build a custom AI automation workspace for you — <strong>free</strong>.
          </p>
        </div>

        {/* Form */}
        <div className="bg-white rounded-2xl shadow-lg border border-gray-100 p-8">
          <form onSubmit={handleSubmit} className="space-y-5">
            {error && (
              <div className="bg-red-50 border border-red-200 text-red-700 rounded-lg px-4 py-3 text-sm">
                {error}
              </div>
            )}

            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1.5">
                Business Name <span className="text-red-500">*</span>
              </label>
              <input
                required
                className="input"
                placeholder="e.g. Smith & Associates Law Firm"
                value={form.business_name}
                onChange={e => update('business_name', e.target.value)}
              />
            </div>

            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1.5">
                Industry <span className="text-red-500">*</span>
              </label>
              <select
                required
                className="input"
                value={form.industry}
                onChange={e => update('industry', e.target.value)}
              >
                <option value="Law Firm">🏛️ Law Firm</option>
                <option value="Insurance">🛡️ Insurance Agency</option>
                <option value="Real Estate">🏡 Real Estate</option>
                <option value="Other">📋 Other</option>
              </select>
            </div>

            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1.5">
                What's your biggest time-waster? <span className="text-gray-400 font-normal">(optional)</span>
              </label>
              <textarea
                className="input h-24 resize-none"
                placeholder="e.g. I spend 3 hours/day on client intake paperwork and follow-up emails..."
                value={form.pain_point}
                onChange={e => update('pain_point', e.target.value)}
              />
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-semibold text-gray-700 mb-1.5">
                  Email <span className="text-red-500">*</span>
                </label>
                <input
                  required
                  type="email"
                  className="input"
                  placeholder="you@example.com"
                  value={form.email}
                  onChange={e => update('email', e.target.value)}
                />
              </div>
              <div>
                <label className="block text-sm font-semibold text-gray-700 mb-1.5">
                  Phone <span className="text-gray-400 font-normal">(optional)</span>
                </label>
                <input
                  type="tel"
                  className="input"
                  placeholder="+1 (555) 000-0000"
                  value={form.phone}
                  onChange={e => update('phone', e.target.value)}
                />
              </div>
            </div>

            <label className="flex items-start gap-3 cursor-pointer group">
              <input
                type="checkbox"
                className="mt-0.5 h-4 w-4 rounded border-gray-300 text-violet-600 focus:ring-violet-500 cursor-pointer"
                checked={form.schedule_call}
                onChange={e => update('schedule_call', e.target.checked)}
              />
              <span className="text-sm text-gray-700">
                <span className="font-medium">Schedule a free setup call</span>
                <span className="text-gray-500"> — We'll personally configure your workspace together (30 min)</span>
              </span>
            </label>

            <button
              type="submit"
              disabled={loading}
              className="w-full py-3.5 bg-gradient-to-r from-violet-600 to-purple-600 text-white rounded-xl font-semibold text-base hover:from-violet-700 hover:to-purple-700 transition-all disabled:opacity-60 flex items-center justify-center gap-2"
            >
              {loading ? (
                <>
                  <Loader size={18} className="animate-spin" />
                  Setting up your workspace...
                </>
              ) : (
                <>
                  <Zap size={18} />
                  Get My Free AI Workspace
                </>
              )}
            </button>

            <p className="text-center text-xs text-gray-400">
              No credit card required. No spam. Unsubscribe anytime.
            </p>
          </form>
        </div>
      </div>
    </div>
  )
}
