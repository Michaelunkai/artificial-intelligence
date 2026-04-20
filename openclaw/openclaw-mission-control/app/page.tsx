"use client";

import { useState, useEffect } from "react";

interface AgentSession {
  id: string;
  name: string;
  status: "active" | "idle" | "error";
  currentTask?: string;
  progress?: number;
  runtime: string;
}

interface Failure {
  tool: string;
  message: string;
  count: number;
  lastSeen: string;
}

interface FoundryStats {
  extensions: number;
  skills: number;
  patterns: number;
  crystallized: number;
  pending: number;
  insights: number;
  unresolved: number;
}

export default function MissionControl() {
  const [sessions, setSessions] = useState<AgentSession[]>([]);
  const [failures, setFailures] = useState<Failure[]>([]);
  const [foundryStats, setFoundryStats] = useState<FoundryStats>({
    extensions: 0,
    skills: 11,
    patterns: 155,
    crystallized: 14,
    pending: 141,
    insights: 4853,
    unresolved: 137,
  });
  const [lastUpdate, setLastUpdate] = useState<Date>(new Date());

  // Simulated data fetching - replace with actual API calls
  useEffect(() => {
    const fetchData = async () => {
      // Mock data for demo
      setSessions([
        {
          id: "openclaw",
          name: "OpenClaw Main",
          status: "active",
          currentTask: "Building Mission Control",
          progress: 65,
          runtime: "2h 15m",
        },
        {
          id: "session2",
          name: "Session 2",
          status: "idle",
          runtime: "45m",
        },
      ]);

      setFailures([
        {
          tool: "read",
          message: "ENOENT: no such file or directory",
          count: 39,
          lastSeen: "2 hours ago",
        },
        {
          tool: "browser",
          message: "Can't reach browser control service",
          count: 7,
          lastSeen: "1 hour ago",
        },
        {
          tool: "browser",
          message: 'Profile "chrome" not found',
          count: 13,
          lastSeen: "30 minutes ago",
        },
      ]);

      setLastUpdate(new Date());
    };

    fetchData();
    const interval = setInterval(fetchData, 5000);
    return () => clearInterval(interval);
  }, []);

  const getStatusColor = (status: string) => {
    switch (status) {
      case "active":
        return "bg-green-500";
      case "idle":
        return "bg-yellow-500";
      case "error":
        return "bg-red-500";
      default:
        return "bg-gray-500";
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 via-gray-800 to-black text-white p-8">
      <header className="mb-8">
        <h1 className="text-5xl font-bold mb-2 bg-gradient-to-r from-blue-400 to-purple-500 bg-clip-text text-transparent">
          🎯 OpenClaw Mission Control
        </h1>
        <p className="text-gray-400">
          Last updated: {lastUpdate.toLocaleTimeString()}
        </p>
      </header>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-8">
        {/* Foundry Stats Card */}
        <div className="bg-gray-800 rounded-lg p-6 border border-gray-700 shadow-lg">
          <h2 className="text-2xl font-bold mb-4 flex items-center">
            🔨 Foundry Stats
          </h2>
          <div className="space-y-3">
            <div className="flex justify-between">
              <span className="text-gray-400">Skills Written:</span>
              <span className="font-bold text-blue-400">{foundryStats.skills}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">Total Patterns:</span>
              <span className="font-bold text-purple-400">{foundryStats.patterns}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">Crystallized:</span>
              <span className="font-bold text-green-400">{foundryStats.crystallized}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">Pending:</span>
              <span className="font-bold text-yellow-400">{foundryStats.pending}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">Insights:</span>
              <span className="font-bold text-cyan-400">{foundryStats.insights}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">Unresolved:</span>
              <span className="font-bold text-red-400">{foundryStats.unresolved}</span>
            </div>
          </div>
        </div>

        {/* Active Sessions Card */}
        <div className="bg-gray-800 rounded-lg p-6 border border-gray-700 shadow-lg lg:col-span-2">
          <h2 className="text-2xl font-bold mb-4 flex items-center">
            🤖 Active Sessions
          </h2>
          <div className="space-y-4">
            {sessions.map((session) => (
              <div
                key={session.id}
                className="bg-gray-700 rounded-lg p-4 border border-gray-600"
              >
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-3">
                    <div className={`w-3 h-3 rounded-full ${getStatusColor(session.status)}`} />
                    <span className="font-bold text-lg">{session.name}</span>
                  </div>
                  <span className="text-gray-400 text-sm">{session.runtime}</span>
                </div>
                {session.currentTask && (
                  <div className="mb-2">
                    <p className="text-gray-300 text-sm mb-1">{session.currentTask}</p>
                    {session.progress !== undefined && (
                      <div className="w-full bg-gray-600 rounded-full h-2">
                        <div
                          className="bg-blue-500 h-2 rounded-full transition-all duration-300"
                          style={{ width: `${session.progress}%` }}
                        />
                      </div>
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Recurring Failures Section */}
      <div className="bg-gray-800 rounded-lg p-6 border border-gray-700 shadow-lg mb-8">
        <h2 className="text-2xl font-bold mb-4 flex items-center">
          ⚠️ Recurring Failures
        </h2>
        <div className="space-y-3">
          {failures.map((failure, idx) => (
            <div
              key={idx}
              className="bg-gray-700 rounded-lg p-4 border border-red-900/50 flex justify-between items-center"
            >
              <div className="flex-1">
                <div className="flex items-center gap-2 mb-1">
                  <span className="font-mono text-red-400">{failure.tool}</span>
                  <span className="text-xs bg-red-900 px-2 py-1 rounded">
                    {failure.count}x
                  </span>
                </div>
                <p className="text-gray-300 text-sm">{failure.message}</p>
                <p className="text-gray-500 text-xs mt-1">Last seen: {failure.lastSeen}</p>
              </div>
              <button className="ml-4 bg-blue-600 hover:bg-blue-700 px-4 py-2 rounded text-sm transition">
                Fix
              </button>
            </div>
          ))}
        </div>
      </div>

      {/* Quick Actions */}
      <div className="bg-gray-800 rounded-lg p-6 border border-gray-700 shadow-lg">
        <h2 className="text-2xl font-bold mb-4">⚡ Quick Actions</h2>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <button className="bg-gradient-to-r from-blue-600 to-blue-700 hover:from-blue-700 hover:to-blue-800 p-4 rounded-lg transition shadow-lg">
            <div className="text-3xl mb-2">🔍</div>
            <div className="text-sm">View Patterns</div>
          </button>
          <button className="bg-gradient-to-r from-purple-600 to-purple-700 hover:from-purple-700 hover:to-purple-800 p-4 rounded-lg transition shadow-lg">
            <div className="text-3xl mb-2">💎</div>
            <div className="text-sm">Crystallize</div>
          </button>
          <button className="bg-gradient-to-r from-green-600 to-green-700 hover:from-green-700 hover:to-green-800 p-4 rounded-lg transition shadow-lg">
            <div className="text-3xl mb-2">🧬</div>
            <div className="text-sm">Evolve Tools</div>
          </button>
          <button className="bg-gradient-to-r from-red-600 to-red-700 hover:from-red-700 hover:to-red-800 p-4 rounded-lg transition shadow-lg">
            <div className="text-3xl mb-2">🛑</div>
            <div className="text-sm">Emergency Stop</div>
          </button>
        </div>
      </div>
    </div>
  );
}
