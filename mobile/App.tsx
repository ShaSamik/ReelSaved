import React, { useCallback, useEffect, useState, useSyncExternalStore } from 'react';
import {
  FlatList,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  SafeAreaView,
  StatusBar,
  StyleSheet,
  Text,
  TextInput,
  View,
  Modal,
} from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { VideoView, useVideoPlayer } from 'expo-video';

import { AnimatedBackground } from './src/ui/AnimatedBackground';
import { ReelCard } from './src/ui/ReelCard';
import { theme } from './src/ui/theme';
import { enqueue, getReels, hydrate, remove, retry, subscribe } from './src/state/library';
import { Reel } from './src/state/types';
import { mediaFile } from './src/state/storage';

export default function App() {
  const reels = useSyncExternalStore(subscribe, getReels);
  const [link, setLink] = useState('');
  const [playing, setPlaying] = useState<Reel | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  useEffect(() => {
    void hydrate();
  }, []);

  const submit = useCallback(async () => {
    const trimmed = link.trim();
    if (!trimmed) return;
    setLink('');
    try {
      await enqueue(trimmed);
    } catch (error) {
      setNotice((error as Error).message);
    }
  }, [link]);

  const canSubmit = /^https?:\/\/\S+$/i.test(link.trim());

  return (
    <View style={styles.root}>
      <StatusBar barStyle="light-content" />
      <AnimatedBackground />

      <SafeAreaView style={styles.safe}>
        <View style={styles.header}>
          <Text style={styles.titleText}>Reel Saver</Text>
          {reels.length > 0 && (
            <Text style={styles.subtitle}>
              {reels.length} {reels.length === 1 ? 'reel' : 'reels'}
            </Text>
          )}
        </View>

        {reels.length === 0 ? (
          <EmptyState />
        ) : (
          <FlatList
            data={reels}
            keyExtractor={(item) => item.shortcode}
            contentContainerStyle={styles.list}
            showsVerticalScrollIndicator={false}
            renderItem={({ item }) => (
              <ReelCard
                reel={item}
                onPress={() => setPlaying(item)}
                onRetry={() => void retry(item)}
                onDelete={() => remove(item)}
              />
            )}
          />
        )}

        {!!notice && (
          <Pressable onPress={() => setNotice(null)} style={styles.notice}>
            <Text style={styles.noticeText}>{notice}</Text>
          </Pressable>
        )}

        <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
          <View style={styles.pasteBar}>
            <Text style={styles.linkGlyph}>🔗</Text>
            <TextInput
              value={link}
              onChangeText={setLink}
              onSubmitEditing={submit}
              placeholder="Paste a reel link"
              placeholderTextColor={theme.textFaint}
              style={styles.input}
              autoCapitalize="none"
              autoCorrect={false}
              keyboardType="url"
              returnKeyType="go"
              selectionColor={theme.accent}
            />
            <Pressable onPress={submit} disabled={!canSubmit}>
              <LinearGradient
                colors={canSubmit ? [theme.accent, theme.accentSoft] : ['#2A2A33', '#2A2A33']}
                style={styles.submit}
              >
                <Text style={styles.submitGlyph}>↓</Text>
              </LinearGradient>
            </Pressable>
          </View>
        </KeyboardAvoidingView>
      </SafeAreaView>

      <PlayerModal reel={playing} onClose={() => setPlaying(null)} />
    </View>
  );
}

function EmptyState() {
  return (
    <View style={styles.empty}>
      <View style={styles.emptyRing}>
        <Text style={styles.emptyGlyph}>↓</Text>
      </View>
      <Text style={styles.emptyTitle}>No reels yet</Text>
      <Text style={styles.emptyBody}>
        Share a reel to this app, or paste a link below.
      </Text>
    </View>
  );
}

function PlayerModal({ reel, onClose }: { reel: Reel | null; onClose: () => void }) {
  return (
    <Modal visible={!!reel} animationType="slide" onRequestClose={onClose}>
      <View style={styles.player}>
        {reel?.filename ? (
          <VideoSurface uri={mediaFile(reel.filename).uri} />
        ) : (
          <Text style={styles.emptyBody}>The video is no longer on disk.</Text>
        )}
        <Pressable onPress={onClose} style={styles.close} hitSlop={10}>
          <Text style={styles.closeGlyph}>✕</Text>
        </Pressable>
      </View>
    </Modal>
  );
}

/** Kept separate so the player dependency is swapped in one place. */
function VideoSurface({ uri }: { uri: string }) {
  // Reels are a few seconds long, so looping saves reaching for replay.
  const player = useVideoPlayer(uri, (p) => {
    p.loop = true;
    p.play();
  });

  return <VideoView player={player} style={StyleSheet.absoluteFill} contentFit="contain" />;
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: theme.base },
  safe: { flex: 1 },
  header: { paddingHorizontal: 20, paddingTop: 8, paddingBottom: 16 },
  titleText: { color: theme.text, fontSize: 32, fontWeight: '700' },
  subtitle: { color: theme.textDim, fontSize: 14, marginTop: 2 },
  list: { paddingHorizontal: 16, paddingBottom: 24, gap: 12 },

  empty: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 14, paddingHorizontal: 48 },
  emptyRing: {
    width: 92,
    height: 92,
    borderRadius: 46,
    borderWidth: 1,
    borderColor: theme.cardBorder,
    backgroundColor: theme.cardFill,
    alignItems: 'center',
    justifyContent: 'center',
  },
  emptyGlyph: { color: theme.accent, fontSize: 34, fontWeight: '300' },
  emptyTitle: { color: theme.text, fontSize: 20, fontWeight: '600' },
  emptyBody: { color: theme.textDim, fontSize: 14, textAlign: 'center' },

  notice: {
    marginHorizontal: 16,
    marginBottom: 8,
    padding: 12,
    borderRadius: 14,
    backgroundColor: 'rgba(255,115,115,0.16)',
    borderWidth: 1,
    borderColor: 'rgba(255,115,115,0.4)',
  },
  noticeText: { color: theme.danger, fontSize: 13 },

  pasteBar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    marginHorizontal: 16,
    marginBottom: 10,
    paddingLeft: 14,
    paddingRight: 6,
    paddingVertical: 6,
    borderRadius: 28,
    backgroundColor: 'rgba(255,255,255,0.09)',
    borderWidth: 1,
    borderColor: theme.cardBorder,
  },
  linkGlyph: { fontSize: 14 },
  input: { flex: 1, color: theme.text, fontSize: 15, paddingVertical: 8 },
  submit: { width: 34, height: 34, borderRadius: 17, alignItems: 'center', justifyContent: 'center' },
  submitGlyph: { color: '#fff', fontSize: 16, fontWeight: '700' },

  player: { flex: 1, backgroundColor: '#000', alignItems: 'center', justifyContent: 'center' },
  videoPlaceholder: { padding: 24 },
  close: { position: 'absolute', top: 60, right: 20, width: 34, height: 34, borderRadius: 17, backgroundColor: 'rgba(255,255,255,0.15)', alignItems: 'center', justifyContent: 'center' },
  closeGlyph: { color: '#fff', fontSize: 14, fontWeight: '700' },
});
