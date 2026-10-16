const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const axios = require('axios');

/**
 * Spotify track search for tagging a song on a reel.
 * Flutter calls: FirebaseFunctions.instance.httpsCallable('spotifySearch')
 *
 * Prerequisites:
 *   firebase functions:secrets:set SPOTIFY_CLIENT_ID
 *   firebase functions:secrets:set SPOTIFY_CLIENT_SECRET
 *   firebase deploy --only functions:spotifySearch
 */
const spotifyClientId = defineSecret('SPOTIFY_CLIENT_ID');
const spotifyClientSecret = defineSecret('SPOTIFY_CLIENT_SECRET');

// Client-credentials tokens last an hour; reuse across warm invocations.
let cachedToken = null;
let cachedTokenExpiresAt = 0;

async function getAppToken() {
  if (cachedToken && Date.now() < cachedTokenExpiresAt - 60 * 1000) {
    return cachedToken;
  }
  const id = String(spotifyClientId.value() || '').trim();
  const secret = String(spotifyClientSecret.value() || '').trim();
  if (!id || !secret) {
    throw new HttpsError(
      'failed-precondition',
      'Spotify is not configured on the server.',
    );
  }
  let res;
  try {
    res = await axios.post(
      'https://accounts.spotify.com/api/token',
      new URLSearchParams({ grant_type: 'client_credentials' }).toString(),
      {
        headers: {
          Authorization: `Basic ${Buffer.from(`${id}:${secret}`).toString('base64')}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        timeout: 10000,
      },
    );
  } catch (e) {
    console.error(
      'spotifySearch token failed',
      e.response ? e.response.status : e.message,
      e.response ? JSON.stringify(e.response.data) : '',
    );
    throw new HttpsError(
      'failed-precondition',
      'Spotify rejected the app credentials.',
    );
  }
  cachedToken = res.data.access_token;
  cachedTokenExpiresAt = Date.now() + Number(res.data.expires_in || 3600) * 1000;
  return cachedToken;
}

function pickImage(images) {
  if (!Array.isArray(images) || images.length === 0) return '';
  // Spotify lists largest first; ~300px is enough for a disc thumbnail.
  const medium = images.find((i) => i && i.width && i.width <= 320);
  return String((medium || images[images.length - 1] || images[0]).url || '');
}

exports.spotifySearch = onCall({ secrets: [spotifyClientId, spotifyClientSecret] }, async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  const query = String((request.data && request.data.query) || '').trim();
  if (!query) return { tracks: [] };
  if (query.length > 100) {
    throw new HttpsError('invalid-argument', 'Search is too long.');
  }

  const search = async (token) =>
    axios.get('https://api.spotify.com/v1/search', {
      // Development-mode apps are capped at 10 search results.
      params: { q: query, type: 'track', limit: 10 },
      headers: { Authorization: `Bearer ${token}` },
      timeout: 10000,
    });

  let res;
  try {
    res = await search(await getAppToken());
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    if (e.response && e.response.status === 401) {
      cachedToken = null;
      res = await search(await getAppToken());
    } else {
      console.error(
        'spotifySearch failed',
        e.response ? e.response.status : e.message,
        e.response ? JSON.stringify(e.response.data) : '',
      );
      throw new HttpsError('unavailable', 'Spotify search is unavailable right now.');
    }
  }

  const items = (res.data && res.data.tracks && res.data.tracks.items) || [];
  const tracks = items
    .filter((t) => t && t.id)
    .map((t) => ({
      id: String(t.id),
      name: String(t.name || ''),
      artist: (t.artists || []).map((a) => a && a.name).filter(Boolean).join(', '),
      image: pickImage(t.album && t.album.images),
      url: String((t.external_urls && t.external_urls.spotify) || `https://open.spotify.com/track/${t.id}`),
      durationMs: Number(t.duration_ms || 0),
      explicit: Boolean(t.explicit),
    }));
  return { tracks };
});
