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
    label: "Memory",
    icon: {
      sf: "books.vertical.fill",
      md: "auto_stories",
    },
  },
] as const;

export type AppTabName = (typeof APP_TABS)[number]["name"];
