export const APP_TABS = [
  {
    name: "index",
    label: "params",
    icon: {
      sf: "slider.horizontal.3",
      md: "tune",
    },
  },
  {
    name: "memory",
    label: "memory",
    icon: {
      sf: "square.stack.3d.up.fill",
      md: "layers",
    },
  },
] as const;

export const DEV_TAB = {
  name: "dev",
  label: "lab",
  icon: {
    sf: "hammer",
    md: "construction",
  },
} as const;

export type AppTabName = (typeof APP_TABS)[number]["name"];
