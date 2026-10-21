import React from 'react';
import { Image, Pressable, StyleSheet, Text, View, ActivityIndicator } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { Reel, displayTitle, progressOf, stateLabel } from '../state/types';
import { theme } from './theme';

interface Props {
  reel: Reel;
  onPress: () => void;
  onRetry: () => void;
  onDelete: () => void;
}

export function ReelCard({ reel, onPress, onRetry, onDelete }: Props) {
  const done = reel.state === 'completed';

  return (
    <Pressable
      onPress={done ? onPress : undefined}
      onLongPress={onDelete}
      style={({ pressed }) => [styles.card, pressed && done && styles.pressed]}
    >
      <View style={styles.thumb}>
        {reel.thumbnailUrl ? (
          <Image source={{ uri: reel.thumbnailUrl }} style={StyleSheet.absoluteFill} />
        ) : (
          <View style={[StyleSheet.absoluteFill, styles.thumbEmpty]} />
        )}
        {done && (
          <View style={styles.playBadge}>
            <Text style={styles.playGlyph}>▶</Text>
          </View>
        )}
      </View>

      <View style={styles.body}>
        <Text style={styles.title} numberOfLines={1}>
          {displayTitle(reel)}
        </Text>
        {!!reel.caption && (
          <Text style={styles.caption} numberOfLines={2}>
            {reel.caption}
          </Text>
        )}
        <Status reel={reel} />
      </View>

      <Trailing reel={reel} onRetry={onRetry} />
    </Pressable>
  );
}

function Status({ reel }: { reel: Reel }) {
  if (reel.state === 'downloading' && reel.bytesExpected > 0) {
    return (
      <View style={styles.progressWrap}>
        <View style={styles.track}>
          <LinearGradient
            colors={[theme.accent, theme.accentSoft]}
            start={{ x: 0, y: 0 }}
            end={{ x: 1, y: 0 }}
            style={[styles.fill, { width: `${Math.max(4, progressOf(reel) * 100)}%` }]}
          />
        </View>
        <Text style={styles.meta}>
          {formatBytes(reel.bytesDownloaded)} of {formatBytes(reel.bytesExpected)}
        </Text>
      </View>
    );
  }

  if (reel.state === 'failed') {
    return (
      <Text style={styles.error} numberOfLines={2}>
        {reel.errorMessage ?? 'Failed'}
      </Text>
    );
  }

  if (reel.state === 'completed') {
    return <Text style={styles.meta}>{formatBytes(reel.bytesDownloaded)}</Text>;
  }

  return (
    <View style={styles.row}>
      <ActivityIndicator size="small" color={theme.accent} />
      <Text style={[styles.meta, { marginLeft: 6 }]}>{stateLabel[reel.state]}</Text>
    </View>
  );
}

function Trailing({ reel, onRetry }: { reel: Reel; onRetry: () => void }) {
  if (reel.state === 'completed') {
    return (
      <Text style={[styles.tick, { color: reel.savedToLibrary ? theme.success : theme.textFaint }]}>
        {reel.savedToLibrary ? '✓' : '⤓'}
      </Text>
    );
  }
  if (reel.state === 'failed') {
    return (
      <Pressable onPress={onRetry} style={styles.retry} hitSlop={8}>
        <Text style={styles.retryGlyph}>↻</Text>
      </Pressable>
    );
  }
  return null;
}

function formatBytes(bytes: number): string {
  if (bytes <= 0) return 'Saved';
  const units = ['B', 'KB', 'MB', 'GB'];
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value < 10 && unit > 0 ? value.toFixed(1) : Math.round(value)} ${units[unit]}`;
}

const styles = StyleSheet.create({
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    padding: 12,
    borderRadius: 20,
    backgroundColor: theme.cardFill,
    borderWidth: 1,
    borderColor: theme.cardBorder,
  },
  pressed: { opacity: 0.7 },
  thumb: {
    width: 58,
    height: 78,
    borderRadius: 12,
    overflow: 'hidden',
    backgroundColor: 'rgba(255,255,255,0.08)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  thumbEmpty: { backgroundColor: 'rgba(255,255,255,0.08)' },
  playBadge: {
    width: 26,
    height: 26,
    borderRadius: 13,
    backgroundColor: 'rgba(0,0,0,0.45)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  playGlyph: { color: '#fff', fontSize: 10, marginLeft: 2 },
  body: { flex: 1, gap: 4 },
  title: { color: theme.text, fontSize: 16, fontWeight: '600' },
  caption: { color: theme.textDim, fontSize: 12 },
  meta: { color: theme.textFaint, fontSize: 12 },
  error: { color: theme.danger, fontSize: 12 },
  row: { flexDirection: 'row', alignItems: 'center' },
  progressWrap: { gap: 4, maxWidth: 190 },
  track: { height: 5, borderRadius: 3, backgroundColor: theme.track, overflow: 'hidden' },
  fill: { height: 5, borderRadius: 3 },
  tick: { fontSize: 20, fontWeight: '700' },
  retry: {
    width: 34,
    height: 34,
    borderRadius: 17,
    backgroundColor: 'rgba(255,255,255,0.12)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  retryGlyph: { color: theme.text, fontSize: 16 },
});
