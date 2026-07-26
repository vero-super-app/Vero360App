/**
 * Marketplace text + image label blocklists.
 * Text list: keep in sync with marketplace_moderation.dart
 * Image labels: matched against Cloud Vision LABEL_DETECTION / OBJECT_LOCALIZATION
 */

const BLOCKED_TERMS = [
  // Drugs
  'cocaine',
  'heroin',
  'meth',
  'methamphetamine',
  'fentanyl',
  'crack cocaine',
  'weed for sale',
  'sell weed',
  'weed',
  'drugs',
  'marijuana',
  'marihuana',
  'marijuana for sale',
  'ganja',
  'ganja sale',
  'chamba',
  'cha mba',
  'dagga',
  'mdma',
  'ecstasy pills',
  'lsd blotter',
  'opium',
  // Weapons
  'ak47',
  'ak-47',
  'm16',
  'gun',
  'pistol',
  'assault rifle',
  'handgun for sale',
  'pistol for sale',
  'gun for sale',
  'firearm',
  'ammunition for sale',
  'grenade',
  'bomb making',
  'silencer',
  'suppressor',
  'mfuti',
  // Stolen / illicit
  'stolen phone',
  'stolen goods',
  'hot phone',
  'cloned sim',
  'fake passport',
  'fake id',
  'counterfeit money',
  'counterfeit notes',
  'black money',
  // Adult / exploitation
  'escort service',
  'sex for sale',
  'prostitute',
  'child porn',
  'underage sex',
  'nude video sale',
  'kuchinda',
  'porno',
  'kubunyula',
  'nyere',
  'nyini',
  'machende',
  'mbolo',
  'hule',
  // Fraud
  'hacked account',
  'stolen card',
  'cvv for sale',
  'fullz',
];

/**
 * Vision label / object names (lowercase substrings) that should block a listing.
 * Prefer specific weapon/drug terms over generic words ("pipe", "syringe").
 * scoreMin: minimum Vision score (0–1) required to count as a hit.
 */
const IMAGE_LABEL_RULES = [
  // Weapons / explosives
  { term: 'firearm', scoreMin: 0.5, category: 'weapon' },
  { term: 'handgun', scoreMin: 0.5, category: 'weapon' },
  { term: 'pistol', scoreMin: 0.55, category: 'weapon' },
  { term: 'revolver', scoreMin: 0.5, category: 'weapon' },
  { term: 'rifle', scoreMin: 0.5, category: 'weapon' },
  { term: 'shotgun', scoreMin: 0.5, category: 'weapon' },
  { term: 'machine gun', scoreMin: 0.45, category: 'weapon' },
  { term: 'assault rifle', scoreMin: 0.45, category: 'weapon' },
  { term: 'submachine', scoreMin: 0.5, category: 'weapon' },
  { term: 'gun', scoreMin: 0.6, category: 'weapon' },
  { term: 'weapon', scoreMin: 0.7, category: 'weapon' },
  { term: 'ammunition', scoreMin: 0.55, category: 'weapon' },
  { term: 'bullet', scoreMin: 0.65, category: 'weapon' },
  { term: 'cartridge', scoreMin: 0.7, category: 'weapon' },
  { term: 'grenade', scoreMin: 0.5, category: 'weapon' },
  { term: 'explosive', scoreMin: 0.55, category: 'weapon' },
  { term: 'bomb', scoreMin: 0.65, category: 'weapon' },
  { term: 'knife', scoreMin: 0.75, category: 'weapon' },
  { term: 'dagger', scoreMin: 0.6, category: 'weapon' },
  { term: 'machete', scoreMin: 0.55, category: 'weapon' },
  { term: 'sword', scoreMin: 0.7, category: 'weapon' },
  { term: 'bayonet', scoreMin: 0.55, category: 'weapon' },
  { term: 'airsoft', scoreMin: 0.55, category: 'weapon' },
  { term: 'bb gun', scoreMin: 0.55, category: 'weapon' },
  { term: 'pellet gun', scoreMin: 0.55, category: 'weapon' },
  // Cannabis / weed / chamba (Vision usually returns English labels)
  { term: 'cannabis', scoreMin: 0.35, category: 'drugs' },
  { term: 'marijuana', scoreMin: 0.35, category: 'drugs' },
  { term: 'marihuana', scoreMin: 0.35, category: 'drugs' },
  { term: 'cannabis sativa', scoreMin: 0.35, category: 'drugs' },
  { term: 'cannabis indica', scoreMin: 0.35, category: 'drugs' },
  { term: 'hemp bud', scoreMin: 0.4, category: 'drugs' },
  { term: 'hemp flower', scoreMin: 0.4, category: 'drugs' },
  { term: 'marijuana plant', scoreMin: 0.35, category: 'drugs' },
  { term: 'cannabis plant', scoreMin: 0.35, category: 'drugs' },
  { term: 'weed', scoreMin: 0.45, category: 'drugs' },
  { term: 'ganja', scoreMin: 0.4, category: 'drugs' },
  { term: 'hashish', scoreMin: 0.4, category: 'drugs' },
  { term: 'hash oil', scoreMin: 0.4, category: 'drugs' },
  { term: 'thc', scoreMin: 0.45, category: 'drugs' },
  { term: 'cannabinoid', scoreMin: 0.45, category: 'drugs' },
  { term: 'sativa', scoreMin: 0.5, category: 'drugs' },
  { term: 'indica', scoreMin: 0.55, category: 'drugs' },
  { term: 'kush', scoreMin: 0.5, category: 'drugs' },
  { term: 'nug', scoreMin: 0.55, category: 'drugs' },
  { term: 'nugget', scoreMin: 0.7, category: 'drugs' },
  { term: 'bud', scoreMin: 0.72, category: 'drugs' },
  { term: 'hemp', scoreMin: 0.55, category: 'drugs' },
  { term: 'joint', scoreMin: 0.55, category: 'drugs' },
  { term: 'blunt', scoreMin: 0.55, category: 'drugs' },
  { term: 'spliff', scoreMin: 0.5, category: 'drugs' },
  { term: 'bong', scoreMin: 0.45, category: 'drugs' },
  { term: 'chamba', scoreMin: 0.35, category: 'drugs' },
  { term: 'dagga', scoreMin: 0.4, category: 'drugs' },
  { term: 'pot plant', scoreMin: 0.65, category: 'drugs' },
  { term: 'ma cheese', scoreMin: 0.45, category: 'drugs' },

  // Other drugs / paraphernalia
  { term: 'hookah', scoreMin: 0.7, category: 'drugs' },
  { term: 'cocaine', scoreMin: 0.45, category: 'drugs' },
  { term: 'heroin', scoreMin: 0.45, category: 'drugs' },
  { term: 'methamphetamine', scoreMin: 0.45, category: 'drugs' },
  { term: 'crystal meth', scoreMin: 0.45, category: 'drugs' },
  { term: 'narcotic', scoreMin: 0.5, category: 'drugs' },
  { term: 'opium', scoreMin: 0.5, category: 'drugs' },
  { term: 'drug', scoreMin: 0.65, category: 'drugs' },
  { term: 'controlled substance', scoreMin: 0.45, category: 'drugs' },
  { term: 'ecstasy', scoreMin: 0.5, category: 'drugs' },
  { term: 'mdma', scoreMin: 0.5, category: 'drugs' },
  { term: 'lsd', scoreMin: 0.55, category: 'drugs' },
  { term: 'fentanyl', scoreMin: 0.45, category: 'drugs' },
];

function normalize(raw) {
  return String(raw || '')
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * @param {string} title
 * @param {string} [description]
 * @returns {string[]} matching blocked terms
 */
function findBlockedTerms(title, description) {
  const hay = normalize(`${title || ''} ${description || ''}`);
  if (!hay) return [];
  const hits = [];
  for (const term of BLOCKED_TERMS) {
    const t = normalize(term);
    if (!t) continue;
    if (hay.includes(t)) hits.push(term);
  }
  return hits;
}

/**
 * Match Vision labels/objects against IMAGE_LABEL_RULES.
 * @param {{description?: string, name?: string, score?: number, mid?: string}[]} annotations
 * @returns {{ term: string, label: string, score: number, category: string }[]}
 */
function findBlockedImageLabels(annotations) {
  if (!Array.isArray(annotations) || !annotations.length) return [];
  const hits = [];
  const seen = new Set();

  for (const ann of annotations) {
    const label = normalize(ann.description || ann.name || '');
    if (!label) continue;
    const score = typeof ann.score === 'number' ? ann.score : 0;
    for (const rule of IMAGE_LABEL_RULES) {
      const term = normalize(rule.term);
      if (!term) continue;
      if (!label.includes(term) && term !== label) continue;
      // Prefer whole-word-ish: "gun" should not match "gung ho" weirdness; substring OK for "handgun"
      if (score < (rule.scoreMin || 0.6)) continue;
      const key = `${rule.category}:${term}:${label}`;
      if (seen.has(key)) continue;
      seen.add(key);
      hits.push({
        term: rule.term,
        label,
        score,
        category: rule.category,
      });
    }
  }
  return hits;
}

/**
 * Weed photos often get generic labels (hemp + flower/plant/leaf) without
 * always saying "marijuana". Require two signals so normal plants are less likely.
 * @param {{description?: string, name?: string, score?: number}[]} annotations
 * @returns {{ term: string, label: string, score: number, category: string }|null}
 */
function detectCannabisCombo(annotations) {
  if (!Array.isArray(annotations) || !annotations.length) return null;

  const strong = [
    'cannabis',
    'marijuana',
    'marihuana',
    'ganja',
    'hashish',
    'chamba',
    'dagga',
    'thc',
  ];
  const plantish = [
    'hemp',
    'herb',
    'herbal',
    'leaf',
    'plant',
    'flower',
    'flora',
    'bud',
  ];

  let strongHit = null;
  let plantHit = null;
  for (const ann of annotations) {
    const label = normalize(ann.description || ann.name || '');
    const score = typeof ann.score === 'number' ? ann.score : 0;
    if (!label) continue;
    for (const t of strong) {
      if (label.includes(t) && score >= 0.3) {
        strongHit = { label, score, term: t };
      }
    }
    for (const t of plantish) {
      if (label.includes(t) && score >= 0.45) {
        if (!plantHit || score > plantHit.score) {
          plantHit = { label, score, term: t };
        }
      }
    }
  }

  if (strongHit) {
    return {
      term: strongHit.term,
      label: strongHit.label,
      score: strongHit.score,
      category: 'drugs',
    };
  }

  // hemp + flower/leaf/plant together is a common Vision pattern for weed photos
  const labels = annotations
    .map((a) => normalize(a.description || a.name || ''))
    .filter(Boolean);
  const hasHemp = labels.some((l) => l.includes('hemp'));
  const hasFlowerish = labels.some(
    (l) =>
      l.includes('flower') ||
      l.includes('bud') ||
      l.includes('leaf') ||
      l.includes('herb'),
  );
  if (hasHemp && hasFlowerish && plantHit) {
    return {
      term: 'hemp+flower',
      label: `${plantHit.label}`,
      score: plantHit.score,
      category: 'drugs',
    };
  }
  return null;
}

module.exports = {
  BLOCKED_TERMS,
  IMAGE_LABEL_RULES,
  normalize,
  findBlockedTerms,
  findBlockedImageLabels,
  detectCannabisCombo,
};
