"""CLU Engine - Extract Claude Desktop session key and fetch real-time usage.
Outputs JSON to stdout. No manual auth needed - uses DPAPI auto-decrypt."""
import sqlite3, os, sys, json, base64, ctypes, ctypes.wintypes, shutil

class DATA_BLOB(ctypes.Structure):
    _fields_ = [('cbData', ctypes.wintypes.DWORD), ('pbData', ctypes.POINTER(ctypes.c_char))]

def dpapi_decrypt(data):
    blob_in = DATA_BLOB(len(data), ctypes.create_string_buffer(data, len(data)))
    blob_out = DATA_BLOB()
    if ctypes.windll.crypt32.CryptUnprotectData(
        ctypes.byref(blob_in), None, None, None, None, 0, ctypes.byref(blob_out)
    ):
        result = ctypes.string_at(blob_out.pbData, blob_out.cbData)
        ctypes.windll.kernel32.LocalFree(blob_out.pbData)
        return result
    return None

def error_exit(msg):
    print(json.dumps({"error": msg}))
    sys.exit(1)

def get_session_key():
    """Extract sessionKey from Claude Desktop's encrypted cookie database."""
    appdata = os.environ.get('APPDATA', '')
    
    local_state_path = os.path.join(appdata, 'Claude', 'Local State')
    if not os.path.exists(local_state_path):
        error_exit("Claude Desktop not installed (no Local State)")
    
    cookie_db = os.path.join(appdata, 'Claude', 'Network', 'Cookies')
    if not os.path.exists(cookie_db):
        error_exit("No Claude Desktop cookie database")
    
    # Get AES decryption key via DPAPI
    with open(local_state_path, 'r') as f:
        local_state = json.load(f)
    
    enc_key_b64 = local_state.get('os_crypt', {}).get('encrypted_key')
    if not enc_key_b64:
        error_exit("No encryption key in Claude Desktop config")
    
    enc_key = base64.b64decode(enc_key_b64)
    aes_key = dpapi_decrypt(enc_key[5:])  # Strip 'DPAPI' prefix
    if not aes_key:
        error_exit("DPAPI decryption failed - wrong Windows user?")
    
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    except ImportError:
        os.system(f'"{sys.executable}" -m pip install cryptography -q')
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    
    # Copy cookie DB (might be locked by Claude Desktop)
    temp_db = os.path.join(os.environ['TEMP'], 'clu_cookies.db')
    try:
        shutil.copy2(cookie_db, temp_db)
    except PermissionError:
        error_exit("Cookie DB locked - is Claude Desktop running? (try closing it briefly)")
    
    conn = sqlite3.connect(temp_db)
    cur = conn.cursor()
    cur.execute(
        "SELECT encrypted_value FROM cookies "
        "WHERE name='sessionKey' AND host_key LIKE '%claude%'"
    )
    row = cur.fetchone()
    conn.close()
    
    try:
        os.remove(temp_db)
    except:
        pass
    
    if not row or not row[0]:
        error_exit("No sessionKey cookie - log into claude.ai in Claude Desktop first")
    
    # Decrypt: v10 format = version(3) + nonce(12) + ciphertext
    enc_val = row[0]
    nonce = enc_val[3:15]
    ciphertext = enc_val[15:]
    
    try:
        decrypted = AESGCM(aes_key).decrypt(nonce, ciphertext, None)
    except Exception as e:
        error_exit(f"Cookie decryption failed: {e}")
    
    # Find session key in decrypted bytes (has prefix padding)
    idx = decrypted.find(b'sk-ant-')
    if idx < 0:
        error_exit("Decrypted cookie doesn't contain valid session key")
    
    return decrypted[idx:].decode('ascii')

def fetch_usage(session_key):
    """Fetch real-time usage from claude.ai API."""
    import urllib.request
    
    headers = {
        'Cookie': f'sessionKey={session_key}',
        'Accept': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    }
    
    # Get org ID
    req = urllib.request.Request('https://claude.ai/api/organizations', headers=headers)
    try:
        resp = urllib.request.urlopen(req, timeout=10)
        orgs = json.loads(resp.read())
        org_id = orgs[0]['uuid']
    except Exception as e:
        error_exit(f"Auth failed (session expired?): {e}")
    
    # Get usage
    req2 = urllib.request.Request(
        f'https://claude.ai/api/organizations/{org_id}/usage',
        headers=headers
    )
    try:
        resp2 = urllib.request.urlopen(req2, timeout=10)
        return json.loads(resp2.read())
    except Exception as e:
        error_exit(f"Usage fetch failed: {e}")

def main():
    # Check for cached session key first (faster)
    cache_path = os.path.join(os.environ['USERPROFILE'], '.openclaw', 'claude-session.txt')
    session_key = None
    
    if os.path.exists(cache_path):
        with open(cache_path, 'r') as f:
            cached = f.read().strip()
        if cached.startswith('sk-ant-'):
            # Try cached key first
            try:
                usage = fetch_usage(cached)
                print(json.dumps(usage))
                return
            except SystemExit:
                pass  # Cached key expired, extract fresh one
    
    # Extract fresh session key
    session_key = get_session_key()
    
    # Cache it
    os.makedirs(os.path.dirname(cache_path), exist_ok=True)
    with open(cache_path, 'w') as f:
        f.write(session_key)
    
    # Fetch and output usage
    usage = fetch_usage(session_key)
    print(json.dumps(usage))

if __name__ == '__main__':
    main()
