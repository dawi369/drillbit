export const palettes = {
  dark: {
    bg: "#191F2B",
    surface: "#252E3E",
    ink: "#F4F6FC",
    muted: "#ABB8CD",
    line: "#354258",
    action: "#FFD071",
    onAction: "#27200F",
    selected: "#343329",
    accent: "#FFD071",
    signal: "#FFD071",
    live: "#75DECA",
  },
  light: {
    bg: "#F5F7FB",
    surface: "#FFFFFF",
    ink: "#202A3C",
    muted: "#5D6C83",
    line: "#D7DFEA",
    action: "#FFD071",
    onAction: "#27200F",
    selected: "#FFF0CE",
    accent: "#855700",
    signal: "#A26A08",
    live: "#167B69",
  },
};
export const brand = { gold: "#FFCC65", core: "#232834", contour: "#FFD071" };
export type Palette = typeof palettes.dark;
