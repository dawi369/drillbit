let hasBootstrappedWidgets = false;

export async function bootstrapWidgets() {
  if (process.env.EXPO_OS !== "ios" || hasBootstrappedWidgets) {
    return;
  }

  hasBootstrappedWidgets = true;

  const { seedDrillbitWidget } = await import("@/widgets/drillbit-widget");
  seedDrillbitWidget();
}
