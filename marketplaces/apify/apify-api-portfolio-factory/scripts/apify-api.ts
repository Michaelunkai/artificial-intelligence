const API_BASE_URL = 'https://api.apify.com/v2';

export type ApiResult<T> = {
  data: T;
};

export function requireApifyToken(): string {
  const token = process.env.APIFY_TOKEN;
  if (!token) {
    throw new Error('APIFY_TOKEN is required in the current process environment.');
  }
  if (!token.startsWith('apify_api_')) {
    throw new Error('APIFY_TOKEN does not look like an Apify API token.');
  }
  return token;
}

export async function apifyRequest<T>(path: string, options: RequestInit = {}): Promise<T> {
  const token = requireApifyToken();
  const headers = new Headers(options.headers);
  headers.set('authorization', `Bearer ${token}`);
  if (options.body && !headers.has('content-type')) {
    headers.set('content-type', 'application/json');
  }

  const response = await fetch(`${API_BASE_URL}${path}`, {
    ...options,
    headers,
  });

  const body = await response.text();
  const parsed = body ? JSON.parse(body) as ApiResult<T> | T : undefined;

  if (!response.ok) {
    const message = typeof parsed === 'object' && parsed && 'error' in parsed
      ? JSON.stringify((parsed as { error: unknown }).error)
      : body;
    throw new Error(`Apify API ${response.status} ${response.statusText}: ${message}`);
  }

  if (parsed && typeof parsed === 'object' && 'data' in parsed) {
    return (parsed as ApiResult<T>).data;
  }

  return parsed as T;
}

export async function tryApifyRequest<T>(path: string, options: RequestInit = {}): Promise<T | undefined> {
  try {
    return await apifyRequest<T>(path, options);
  } catch (error) {
    if (error instanceof Error && error.message.includes('Apify API 404')) {
      return undefined;
    }
    throw error;
  }
}
