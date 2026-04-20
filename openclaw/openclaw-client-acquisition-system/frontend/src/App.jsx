import { BrowserRouter, Routes, Route, NavLink, Navigate } from 'react-router-dom'
import {
  LayoutDashboard, Users, Mail, UserCheck, FileInput, Settings, Zap, Menu, X
} from 'lucide-react'
import { useState } from 'react'

import Dashboard from './pages/Dashboard.jsx'
import Leads from './pages/Leads.jsx'
import Outreach from './pages/Outreach.jsx'
import Clients from './pages/Clients.jsx'
import Intake from './pages/Intake.jsx'
import SettingsPage from './pages/Settings.jsx'

const navItems = [
  { to: '/dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/leads', label: 'Leads', icon: Users },
  { to: '/outreach', label: 'Outreach', icon: Mail },
  { to: '/clients', label: 'Clients', icon: UserCheck },
  { to: '/settings', label: 'Settings', icon: Settings },
]

function Sidebar({ mobile, onClose }) {
  return (
    <aside className={`
      ${mobile ? 'fixed inset-y-0 left-0 z-50 w-64 shadow-2xl' : 'hidden lg:flex w-64 flex-shrink-0'}
      flex flex-col bg-gradient-to-b from-violet-800 to-violet-900 text-white
    `}>
      {/* Logo */}
      <div className="flex items-center justify-between h-16 px-6 border-b border-white/10">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 bg-white/20 rounded-lg flex items-center justify-center">
            <Zap size={18} className="text-yellow-300" />
          </div>
          <span className="font-bold text-lg tracking-tight">OpenClaw</span>
        </div>
        {mobile && (
          <button onClick={onClose} className="text-white/70 hover:text-white">
            <X size={20} />
          </button>
        )}
      </div>

      {/* Navigation */}
      <nav className="flex-1 px-3 py-4 space-y-1 overflow-y-auto">
        <p className="px-3 text-xs font-semibold text-white/40 uppercase tracking-wider mb-2">Main</p>
        {navItems.map(({ to, label, icon: Icon }) => (
          <NavLink
            key={to}
            to={to}
            onClick={mobile ? onClose : undefined}
            className={({ isActive }) =>
              `sidebar-link text-white/70 ${isActive ? 'active' : ''}`
            }
          >
            <Icon size={18} />
            {label}
          </NavLink>
        ))}
        <div className="pt-4 border-t border-white/10 mt-4">
          <NavLink
            to="/intake"
            onClick={mobile ? onClose : undefined}
            className={({ isActive }) =>
              `sidebar-link text-white/70 ${isActive ? 'active' : ''}`
            }
          >
            <FileInput size={18} />
            Intake Form
          </NavLink>
        </div>
      </nav>

      {/* Footer */}
      <div className="px-6 py-4 border-t border-white/10 text-xs text-white/40">
        OpenClaw v1.0 · Client Acquisition
      </div>
    </aside>
  )
}

function Layout({ children }) {
  const [sidebarOpen, setSidebarOpen] = useState(false)

  return (
    <div className="flex h-screen overflow-hidden">
      {/* Desktop sidebar */}
      <Sidebar />

      {/* Mobile sidebar */}
      {sidebarOpen && (
        <>
          <div
            className="fixed inset-0 bg-black/50 z-40 lg:hidden"
            onClick={() => setSidebarOpen(false)}
          />
          <Sidebar mobile onClose={() => setSidebarOpen(false)} />
        </>
      )}

      {/* Main content */}
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        {/* Top bar */}
        <header className="h-16 bg-white border-b border-gray-100 flex items-center px-4 lg:px-6 gap-4 flex-shrink-0">
          <button
            className="lg:hidden text-gray-500 hover:text-gray-700"
            onClick={() => setSidebarOpen(true)}
          >
            <Menu size={22} />
          </button>
          <h1 className="text-lg font-semibold text-gray-800 flex-1">
            Client Acquisition System
          </h1>
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 bg-violet-100 rounded-full flex items-center justify-center text-violet-700 font-semibold text-sm">
              OC
            </div>
          </div>
        </header>

        {/* Page content */}
        <main className="flex-1 overflow-y-auto p-4 lg:p-6">
          {children}
        </main>
      </div>
    </div>
  )
}

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        {/* Public intake form — no sidebar */}
        <Route path="/intake" element={<Intake />} />

        {/* Admin routes — with sidebar */}
        <Route
          path="/*"
          element={
            <Layout>
              <Routes>
                <Route path="/" element={<Navigate to="/dashboard" replace />} />
                <Route path="/dashboard" element={<Dashboard />} />
                <Route path="/leads" element={<Leads />} />
                <Route path="/outreach" element={<Outreach />} />
                <Route path="/clients" element={<Clients />} />
                <Route path="/settings" element={<SettingsPage />} />
              </Routes>
            </Layout>
          }
        />
      </Routes>
    </BrowserRouter>
  )
}
