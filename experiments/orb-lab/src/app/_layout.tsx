import React from "react";
import { useSegments } from "expo-router";
import { NativeTabs } from "expo-router/unstable-native-tabs";
import { LabTheme, useLabTheme } from "../theme";
import { particlePalette } from "../particle-palette";
function Tabs() {
  const { colors } = useLabTheme();
  const particle = (useSegments() as readonly string[]).includes("(particle)");
  return (
    <NativeTabs
      hidden={particle}
      backgroundColor={particle ? particlePalette.top : colors.bg}
      tintColor={particle ? particlePalette.coral : colors.ink}
    >
      <NativeTabs.Trigger name="(lab)">
        <NativeTabs.Trigger.Label>Orb Lab</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf="waveform.circle" />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger
        name="(particle)"
        contentStyle={{ backgroundColor: particlePalette.top }}
      >
        <NativeTabs.Trigger.Label>Particle</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf="circle.dotted" />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="(notes)">
        <NativeTabs.Trigger.Label>Research</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf="doc.text.magnifyingglass" />
      </NativeTabs.Trigger>
    </NativeTabs>
  );
}
export default function Layout() {
  return (
    <LabTheme>
      <Tabs />
    </LabTheme>
  );
}
