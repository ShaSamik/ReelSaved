export const theme = {
  base: '#09080F',
  accent: '#9E73FF',
  accentSoft: '#6BB3FF',
  success: '#4CD98A',
  danger: '#FF7373',
  text: '#FFFFFF',
  textDim: 'rgba(255,255,255,0.55)',
  textFaint: 'rgba(255,255,255,0.40)',
  cardBorder: 'rgba(255,255,255,0.12)',
  cardFill: 'rgba(255,255,255,0.07)',
  track: 'rgba(255,255,255,0.14)',

  /** Soft colour blobs that drift behind everything. */
  blobs: [
    { color: '#5B2BA6', size: 460, from: { x: -90, y: -40 }, to: { x: 40, y: 120 } },
    { color: '#2B3FA6', size: 420, from: { x: 170, y: 260 }, to: { x: 60, y: 420 } },
    { color: '#7A2E8F', size: 380, from: { x: 20, y: 520 }, to: { x: 180, y: 380 } },
  ],
} as const;
