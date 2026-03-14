export const APP_TABS = [
  {
    name: "index",
    label: "Params",
    icon: {
      sf: "slider.horizontal.3",
      md: "tune",
    },
  },
  {
    name: "memory",
    label: "Mem",
    icon: {
      sf: "clock.arrow.circlepath",
      md: "history",
    },
  },
] as const;

export type AppTabName = (typeof APP_TABS)[number]["name"];
