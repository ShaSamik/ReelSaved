import React, { useEffect, useRef } from 'react';
import { Animated, Easing, StyleSheet, View, useWindowDimensions, AccessibilityInfo } from 'react-native';
import Svg, { Defs, RadialGradient, Stop, Rect } from 'react-native-svg';
import { LinearGradient } from 'expo-linear-gradient';
import { theme } from './theme';

/**
 * Slow-drifting colour blobs behind everything.
 *
 * React Native has no equivalent of SwiftUI's MeshGradient, so the same effect
 * comes from a few large radial-gradient circles translating past each other.
 * Only `transform` is animated, which keeps the whole thing on the native
 * driver — the JS thread stays free for downloads.
 *
 * A full cycle takes 26 seconds. Anything faster reads as a loading state
 * rather than atmosphere, and it has to stay calm underneath text.
 */
export function AnimatedBackground() {
  const { width, height } = useWindowDimensions();
  const progress = useRef(new Animated.Value(0)).current;
  const reduceMotion = useRef(false);

  useEffect(() => {
    let cancelled = false;

    AccessibilityInfo.isReduceMotionEnabled().then((enabled) => {
      if (cancelled) return;
      reduceMotion.current = enabled;
      if (enabled) return;

      Animated.loop(
        Animated.sequence([
          Animated.timing(progress, {
            toValue: 1,
            duration: 26000,
            easing: Easing.inOut(Easing.sin),
            useNativeDriver: true,
          }),
          Animated.timing(progress, {
            toValue: 0,
            duration: 26000,
            easing: Easing.inOut(Easing.sin),
            useNativeDriver: true,
          }),
        ]),
      ).start();
    });

    return () => {
      cancelled = true;
    };
  }, [progress]);

  return (
    <View style={StyleSheet.absoluteFill} pointerEvents="none">
      <View style={[StyleSheet.absoluteFill, { backgroundColor: theme.base }]} />

      {theme.blobs.map((blob, index) => (
        <Animated.View
          key={index}
          style={{
            position: 'absolute',
            width: blob.size,
            height: blob.size,
            transform: [
              {
                translateX: progress.interpolate({
                  inputRange: [0, 1],
                  outputRange: [blob.from.x, blob.to.x],
                }),
              },
              {
                translateY: progress.interpolate({
                  inputRange: [0, 1],
                  outputRange: [blob.from.y, blob.to.y],
                }),
              },
            ],
          }}
        >
          <Blob color={blob.color} size={blob.size} id={`blob${index}`} />
        </Animated.View>
      ))}

      {/* Darkens the edges so the centre reads as lit and cards have
          something to sit against at the top and bottom. */}
      <LinearGradient
        colors={['rgba(0,0,0,0.70)', 'transparent', 'transparent', 'rgba(0,0,0,0.80)']}
        locations={[0, 0.26, 0.6, 1]}
        style={[StyleSheet.absoluteFill, { width, height }]}
      />
    </View>
  );
}

function Blob({ color, size, id }: { color: string; size: number; id: string }) {
  return (
    <Svg width={size} height={size}>
      <Defs>
        <RadialGradient id={id} cx="50%" cy="50%" r="50%">
          <Stop offset="0%" stopColor={color} stopOpacity={0.85} />
          <Stop offset="55%" stopColor={color} stopOpacity={0.32} />
          <Stop offset="100%" stopColor={color} stopOpacity={0} />
        </RadialGradient>
      </Defs>
      <Rect x={0} y={0} width={size} height={size} fill={`url(#${id})`} />
    </Svg>
  );
}
