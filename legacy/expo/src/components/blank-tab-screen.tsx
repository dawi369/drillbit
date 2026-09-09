import { ScrollView } from "react-native";

export function BlankTabScreen() {
  return (
    <ScrollView
      className="flex-1 bg-background"
      contentInsetAdjustmentBehavior="automatic"
      contentContainerClassName="flex-1"
    />
  );
}
