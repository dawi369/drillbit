import { NativeTabs } from "expo-router/unstable-native-tabs";
import { useEffect } from "react";

import { APP_TABS, DEV_TAB } from "@/constants/tabs";
import { APP_THEME_COLORS } from "@/constants/theme";
import { debugLog } from "@/lib/debug";

export default function TabsLayout() {
  const tabs = __DEV__ ? [...APP_TABS, DEV_TAB] : APP_TABS;

  useEffect(() => {
    debugLog("tabs-layout", "mounted");

    return () => {
      debugLog("tabs-layout", "unmounted");
    };
  }, []);

  return (
    <NativeTabs tintColor={APP_THEME_COLORS.accent}>
      {tabs.map((tab) => (
        <NativeTabs.Trigger key={tab.name} name={tab.name}>
          <NativeTabs.Trigger.Icon sf={tab.icon.sf} md={tab.icon.md} />
          <NativeTabs.Trigger.Label>{tab.label}</NativeTabs.Trigger.Label>
        </NativeTabs.Trigger>
      ))}
    </NativeTabs>
  );
}
