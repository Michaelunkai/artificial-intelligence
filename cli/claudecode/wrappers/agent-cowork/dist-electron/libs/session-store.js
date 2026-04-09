import Database from "better-sqlite3";
export class SessionStore {
    sessions = new Map();
    db;
    constructor(dbPath) {
        this.db = new Database(dbPath);
        this.initialize();
        this.loadSessions();
    }
    createSession(options) {
        const id = crypto.randomUUID();
        const now = Date.now();
        const session = {
            id,
            title: options.title,
            status: "idle",
            cwd: options.cwd,
            allowedTools: options.allowedTools,
            lastPrompt: options.prompt,
            pendingPermissions: new Map()
        };
        this.sessions.set(id, session);
        this.db
            .prepare(`insert into sessions
          (id, title, claude_session_id, status, cwd, allowed_tools, last_prompt, created_at, updated_at)
         values (?, ?, ?, ?, ?, ?, ?, ?, ?)`)
            .run(id, session.title, session.claudeSessionId ?? null, session.status, session.cwd ?? null, session.allowedTools ?? null, session.lastPrompt ?? null, now, now);
        return session;
    }
    getSession(id) {
        return this.sessions.get(id);
    }
    listSessions() {
        const rows = this.db
            .prepare(`select id, title, claude_session_id, status, cwd, allowed_tools, last_prompt, created_at, updated_at
         from sessions
         order by updated_at desc`)
            .all();
        return rows.map((row) => ({
            id: String(row.id),
            title: String(row.title),
            status: row.status,
            cwd: row.cwd ? String(row.cwd) : undefined,
            allowedTools: row.allowed_tools ? String(row.allowed_tools) : undefined,
            lastPrompt: row.last_prompt ? String(row.last_prompt) : undefined,
            claudeSessionId: row.claude_session_id ? String(row.claude_session_id) : undefined,
            createdAt: Number(row.created_at),
            updatedAt: Number(row.updated_at)
        }));
    }
    listRecentCwds(limit = 8) {
        const rows = this.db
            .prepare(`select cwd, max(updated_at) as latest
         from sessions
         where cwd is not null and trim(cwd) != ''
         group by cwd
         order by latest desc
         limit ?`)
            .all(limit);
        return rows.map((row) => String(row.cwd));
    }
    getSessionHistory(id) {
        const sessionRow = this.db
            .prepare(`select id, title, claude_session_id, status, cwd, allowed_tools, last_prompt, created_at, updated_at
         from sessions
         where id = ?`)
            .get(id);
        if (!sessionRow)
            return null;
        const messages = this.db
            .prepare(`select data from messages where session_id = ? order by created_at asc`)
            .all(id)
            .map((row) => JSON.parse(String(row.data)));
        return {
            session: {
                id: String(sessionRow.id),
                title: String(sessionRow.title),
                status: sessionRow.status,
                cwd: sessionRow.cwd ? String(sessionRow.cwd) : undefined,
                allowedTools: sessionRow.allowed_tools ? String(sessionRow.allowed_tools) : undefined,
                lastPrompt: sessionRow.last_prompt ? String(sessionRow.last_prompt) : undefined,
                claudeSessionId: sessionRow.claude_session_id ? String(sessionRow.claude_session_id) : undefined,
                createdAt: Number(sessionRow.created_at),
                updatedAt: Number(sessionRow.updated_at)
            },
            messages
        };
    }
    updateSession(id, updates) {
        const session = this.sessions.get(id);
        if (!session)
            return undefined;
        Object.assign(session, updates);
        this.persistSession(id, updates);
        return session;
    }
    setAbortController(id, controller) {
        const session = this.sessions.get(id);
        if (!session)
            return;
        session.abortController = controller;
    }
    recordMessage(sessionId, message) {
        const id = ('uuid' in message && message.uuid) ? String(message.uuid) : crypto.randomUUID();
        this.db
            .prepare(`insert or ignore into messages (id, session_id, data, created_at) values (?, ?, ?, ?)`)
            .run(id, sessionId, JSON.stringify(message), Date.now());
    }
    deleteSession(id) {
        const existing = this.sessions.get(id);
        if (existing) {
            this.sessions.delete(id);
        }
        this.db.prepare(`delete from messages where session_id = ?`).run(id);
        const result = this.db.prepare(`delete from sessions where id = ?`).run(id);
        const removedFromDb = result.changes > 0;
        return removedFromDb || Boolean(existing);
    }
    persistSession(id, updates) {
        const fields = [];
        const values = [];
        const updatable = {
            claudeSessionId: "claude_session_id",
            status: "status",
            cwd: "cwd",
            allowedTools: "allowed_tools",
            lastPrompt: "last_prompt"
        };
        for (const key of Object.keys(updates)) {
            const column = updatable[key];
            if (!column)
                continue;
            fields.push(`${column} = ?`);
            const value = updates[key];
            values.push(value === undefined ? null : value);
        }
        if (fields.length === 0)
            return;
        fields.push("updated_at = ?");
        values.push(Date.now());
        values.push(id);
        this.db
            .prepare(`update sessions set ${fields.join(", ")} where id = ?`)
            .run(...values);
    }
    initialize() {
        this.db.exec(`pragma journal_mode = WAL;`);
        this.db.exec(`create table if not exists sessions (
        id text primary key,
        title text,
        claude_session_id text,
        status text not null,
        cwd text,
        allowed_tools text,
        last_prompt text,
        created_at integer not null,
        updated_at integer not null
      )`);
        this.db.exec(`create table if not exists messages (
        id text primary key,
        session_id text not null,
        data text not null,
        created_at integer not null,
        foreign key (session_id) references sessions(id)
      )`);
        this.db.exec(`create index if not exists messages_session_id on messages(session_id)`);
    }
    loadSessions() {
        const rows = this.db
            .prepare(`select id, title, claude_session_id, status, cwd, allowed_tools, last_prompt
         from sessions`)
            .all();
        for (const row of rows) {
            const session = {
                id: String(row.id),
                title: String(row.title),
                claudeSessionId: row.claude_session_id ? String(row.claude_session_id) : undefined,
                status: row.status,
                cwd: row.cwd ? String(row.cwd) : undefined,
                allowedTools: row.allowed_tools ? String(row.allowed_tools) : undefined,
                lastPrompt: row.last_prompt ? String(row.last_prompt) : undefined,
                pendingPermissions: new Map()
            };
            this.sessions.set(session.id, session);
        }
    }
}
