import React, {
  createContext,
  use,
  useState,
  useEffect,
  type PropsWithChildren,
} from "react";
import { Appearance } from "react-native";
import { palettes } from "./palette";
const ThemeContext = createContext({
  mode: "dark" as "dark" | "light",
  colors: palettes.dark,
  toggle: () => {},
});
export function LabTheme({ children }: PropsWithChildren) {
  const [mode, setMode] = useState<"dark" | "light">("dark");
  useEffect(() => {
    Appearance.setColorScheme(mode);
    return () => Appearance.setColorScheme("unspecified");
  }, [mode]);
  return (
    <ThemeContext
      value={{
        mode,
        colors: palettes[mode],
        toggle: () => setMode((v) => (v === "dark" ? "light" : "dark")),
      }}
    >
      {children}
    </ThemeContext>
  );
}
export function useLabTheme() {
  return use(ThemeContext);
}
