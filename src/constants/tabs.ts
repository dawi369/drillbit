export const APP_TABS = [
  {
    name: "index",
    label: "params",
    icon: {
      sf: "line.3.horizontal.decrease.circle.fill",
      md: "tune",
    },
  },
  {
    name: "memory",
    label: "memory",
    icon: {
      sf: "brain.head.profile",
      md: "psychology",
    },
  },
] as const;

export const DEV_TAB = {
  name: "dev",
  label: "dev",
  icon: {
    sf: "hammer.circle.fill",
    md: "build_circle",
  },
} as const;

export type AppTabName = (typeof APP_TABS)[number]["name"];
