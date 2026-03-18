import { useFocusEffect } from "expo-router";
import { Tabs } from "heroui-native";
import type { PropsWithChildren } from "react";
import { useCallback, useEffect, useState } from "react";
import { ScrollView, Text, View } from "react-native";

import { SectionTabLabel } from "@/components/section-tab-label";
import { cn } from "@/lib/cn";
import { subscribeToMemoryRefresh } from "@/lib/memory-refresh";
import { getMemoryOverview } from "@/lib/storage/repository";
import type {
  MemoryChallengeSummaryRow,
  MemoryOverview,
  MemoryTopicRollup,
} from "@/lib/storage/types";

function formatScore(score?: number) {
  if (typeof score !== "number") {
    return "-";
  }

  return `${Math.round(score)}%`;
}

function formatSessionDate(iso: string) {
  return new Date(iso).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
  });
}

function PageHeader() {
  return (
    <View className="flex-row items-start justify-between gap-4">
      <View className="min-w-0 flex-1 gap-2">
        <Text className="text-[40px] font-semibold tracking-tight text-foreground">
          memory
        </Text>
        <Text className="max-w-xl text-[15px] leading-6 text-muted">
          A lightweight replay of what keeps repeating, where you are strong,
          and what still needs more reps.
        </Text>
      </View>
    </View>
  );
}

function Surface({ children, className }: PropsWithChildren<{ className?: string }>) {
  return (
    <View
      className={cn(
        "rounded-[28px] border border-border/45 bg-surface-secondary/10 px-5 py-5",
        className,
      )}
    >
      {children}
    </View>
  );
}

function SectionHeading({
  eyebrow,
  title,
  description,
}: {
  eyebrow: string;
  title: string;
  description: string;
}) {
  return (
    <View className="gap-1 pb-4">
      <Text className="text-[11px] font-semibold uppercase tracking-[1.5px] text-muted">
        {eyebrow}
      </Text>
      <Text className="text-[22px] font-semibold tracking-tight text-foreground">
        {title}
      </Text>
      <Text className="text-sm leading-6 text-muted">{description}</Text>
    </View>
  );
}

function MetricChip({ label, value }: { label: string; value: string }) {
  return (
    <View className="min-w-[120px] flex-1 gap-1 rounded-[22px] border border-border/40 bg-background/65 px-4 py-4">
      <Text className="text-[11px] font-semibold uppercase tracking-[1.4px] text-muted">
        {label}
      </Text>
      <Text className="text-[24px] font-semibold tracking-tight text-foreground">
        {value}
      </Text>
    </View>
  );
}

function GraphPlaceholder({ overview }: { overview: MemoryOverview }) {
  const bars = overview.recentSessions.slice(0, 7).map((session) => {
    const score = typeof session.completionScore === "number" ? session.completionScore : 32;
    return Math.max(20, Math.min(100, Math.round(score)));
  });

  while (bars.length < 7) {
    bars.push(26 + bars.length * 8);
  }

  return (
    <Surface className="gap-5">
      <SectionHeading
        eyebrow="graph"
        title="Progress strip"
        description="Reserved space for the upcoming memory graph. For now it keeps a quick visual pulse of recent sessions."
      />

      <View className="rounded-[24px] border border-dashed border-border/45 bg-background/55 px-4 py-5">
        <View className="h-[180px] flex-row items-end gap-3">
          {bars.map((height, index) => (
            <View key={`memory-bar-${index}`} className="min-w-0 flex-1 items-center gap-3">
              <View className="h-full w-full max-w-10 justify-end rounded-full bg-surface-secondary/35">
                <View
                  className="w-full rounded-full bg-accent/75"
                  style={{ height: `${height}%` }}
                />
              </View>
              <Text className="text-[11px] font-medium uppercase tracking-[1.2px] text-muted">
                d{index + 1}
              </Text>
            </View>
          ))}
        </View>
      </View>
    </Surface>
  );
}

function PatternList({
  title,
  description,
  items,
  tone,
}: {
  title: string;
  description: string;
  items: string[];
  tone: "strength" | "gap";
}) {
  return (
    <Surface className="flex-1 gap-4">
      <View className="gap-1">
        <Text className="text-[18px] font-semibold tracking-tight text-foreground">
          {title}
        </Text>
        <Text className="text-sm leading-6 text-muted">{description}</Text>
      </View>

      <View className="gap-2.5">
        {items.length > 0 ? (
          items.map((item) => (
            <View
              key={`${tone}-${item}`}
              className={cn(
                "rounded-[20px] border px-4 py-3",
                tone === "strength"
                  ? "border-emerald-500/20 bg-emerald-500/8"
                  : "border-amber-500/20 bg-amber-500/8",
              )}
            >
              <Text className="text-sm leading-6 text-foreground">{item}</Text>
            </View>
          ))
        ) : (
          <Text className="text-sm leading-6 text-muted">
            No repeated patterns yet. Finish a few sessions and this section will fill in.
          </Text>
        )}
      </View>
    </Surface>
  );
}

function SessionRow({ session }: { session: MemoryChallengeSummaryRow }) {
  return (
    <View className="gap-2 rounded-[22px] border border-border/35 bg-background/60 px-4 py-4">
      <View className="flex-row items-start justify-between gap-3">
        <View className="min-w-0 flex-1 gap-1">
          <Text className="text-[15px] font-semibold text-foreground">
            {session.challengeTitle}
          </Text>
          <Text className="text-sm leading-6 text-muted">
            {session.challengeTopic}
            {session.challengeDifficulty ? ` · ${session.challengeDifficulty}` : ""}
          </Text>
        </View>

        <View className="items-end gap-1 pt-0.5">
          <Text className="text-sm font-semibold text-foreground">
            {formatScore(session.completionScore)}
          </Text>
          <Text className="text-[11px] font-medium uppercase tracking-[1.3px] text-muted">
            {formatSessionDate(session.generatedAt)}
          </Text>
        </View>
      </View>

      <Text className="text-sm leading-6 text-muted">{session.shortFeedback}</Text>
    </View>
  );
}

function TopicRollupRow({ rollup }: { rollup: MemoryTopicRollup }) {
  return (
    <View className="gap-3 rounded-[22px] border border-border/35 bg-background/60 px-4 py-4">
      <View className="flex-row items-start justify-between gap-3">
        <View className="min-w-0 flex-1 gap-1">
          <Text className="text-[15px] font-semibold text-foreground">
            {rollup.topic}
          </Text>
          <Text className="text-sm leading-6 text-muted">
            {rollup.count} {rollup.count === 1 ? "session" : "sessions"}
          </Text>
        </View>
        <Text className="pt-0.5 text-sm font-semibold text-foreground">
          {formatScore(rollup.averageCompletionScore)}
        </Text>
      </View>

      <View className="gap-2">
        <Text className="text-[11px] font-semibold uppercase tracking-[1.3px] text-muted">
          top strengths
        </Text>
        <Text className="text-sm leading-6 text-foreground">
          {rollup.topStrengths.length > 0 ? rollup.topStrengths.join(" · ") : "No repeated strengths yet."}
        </Text>
      </View>

      <View className="gap-2">
        <Text className="text-[11px] font-semibold uppercase tracking-[1.3px] text-muted">
          top gaps
        </Text>
        <Text className="text-sm leading-6 text-foreground">
          {rollup.topWeaknesses.length > 0 ? rollup.topWeaknesses.join(" · ") : "No repeated gaps yet."}
        </Text>
      </View>
    </View>
  );
}

function EmptyMemoryState() {
  return (
    <Surface className="gap-3">
      <Text className="text-[22px] font-semibold tracking-tight text-foreground">
        Nothing here yet
      </Text>
      <Text className="text-sm leading-6 text-muted">
        Finish a challenge and save a summary to start building your memory view.
        This screen refreshes automatically in the background.
      </Text>
    </Surface>
  );
}

export function MemoryScreen() {
  const [activeTab, setActiveTab] = useState("overview");
  const [overview, setOverview] = useState<MemoryOverview | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const loadOverview = useCallback(async (refresh: boolean = false) => {
    if (!refresh) {
      setIsLoading(true);
    }

    try {
      const nextOverview = await getMemoryOverview();
      setOverview(nextOverview);
      setErrorMessage(null);
    } catch (error) {
      setErrorMessage(
        error instanceof Error ? error.message : "Could not load memory overview.",
      );
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadOverview();
  }, [loadOverview]);

  useEffect(() => {
    return subscribeToMemoryRefresh(() => {
      void loadOverview(true);
    });
  }, [loadOverview]);

  useFocusEffect(
    useCallback(() => {
      void loadOverview(true);
    }, [loadOverview]),
  );

  return (
    <ScrollView
      className="flex-1 bg-background"
      contentInsetAdjustmentBehavior="automatic"
      contentContainerClassName="gap-10 px-5 pb-safe-offset-10 pt-safe-offset-7"
    >
      <PageHeader />

      {isLoading ? (
        <Surface>
          <Text className="text-sm leading-6 text-muted">Loading memory...</Text>
        </Surface>
      ) : null}

      {errorMessage ? (
        <Surface>
          <Text selectable className="text-sm leading-6 text-foreground">
            {errorMessage}
          </Text>
        </Surface>
      ) : null}

      {!isLoading && !errorMessage && overview ? (
        <Tabs
          value={activeTab}
          onValueChange={setActiveTab}
          variant="secondary"
          className="gap-5"
        >
          <Tabs.List className="px-1">
            <Tabs.ScrollView
              scrollAlign="center"
              contentContainerClassName="min-w-full justify-center gap-2"
            >
              <Tabs.Indicator />
              <Tabs.Trigger value="overview">
                {({ isSelected }) => <SectionTabLabel label="overview" selected={isSelected} />}
              </Tabs.Trigger>
              <Tabs.Trigger value="recent">
                {({ isSelected }) => <SectionTabLabel label="recent" selected={isSelected} />}
              </Tabs.Trigger>
              <Tabs.Trigger value="topics">
                {({ isSelected }) => <SectionTabLabel label="topics" selected={isSelected} />}
              </Tabs.Trigger>
            </Tabs.ScrollView>
          </Tabs.List>

          <Tabs.Content value="overview">
            {overview.totalCompleted > 0 ? (
              <View className="gap-6">
                <Surface className="gap-5">
                  <SectionHeading
                    eyebrow="overview"
                    title="What your recent history says"
                    description="A compact read on completed sessions, recent scoring, and repeated themes from stored summaries."
                  />

                  <View className="flex-row flex-wrap gap-3">
                    <MetricChip label="completed" value={String(overview.totalCompleted)} />
                    <MetricChip
                      label="average score"
                      value={formatScore(overview.averageCompletionScore)}
                    />
                  </View>
                </Surface>

                <GraphPlaceholder overview={overview} />

                <View className="gap-3 md:flex-row">
                  <PatternList
                    title="Repeated strengths"
                    description="Themes that keep showing up when you do well."
                    items={overview.strongestPatterns}
                    tone="strength"
                  />
                  <PatternList
                    title="Repeated gaps"
                    description="Concepts worth reinforcing in future drills."
                    items={overview.weakestPatterns}
                    tone="gap"
                  />
                </View>
              </View>
            ) : (
              <EmptyMemoryState />
            )}
          </Tabs.Content>

          <Tabs.Content value="recent">
            {overview.recentSessions.length > 0 ? (
              <Surface className="gap-4">
                <SectionHeading
                  eyebrow="recent"
                  title="Recent sessions"
                  description="The latest summaries kept locally for fast replay and pattern spotting."
                />

                <View className="gap-3">
                  {overview.recentSessions.map((session) => (
                    <SessionRow key={session.id} session={session} />
                  ))}
                </View>
              </Surface>
            ) : (
              <EmptyMemoryState />
            )}
          </Tabs.Content>

          <Tabs.Content value="topics">
            {overview.topicRollups.length > 0 ? (
              <Surface className="gap-4">
                <SectionHeading
                  eyebrow="topics"
                  title="By topic"
                  description="A simple rollup of where your recent practice clusters and how each area is trending."
                />

                <View className="gap-3">
                  {overview.topicRollups.map((rollup) => (
                    <TopicRollupRow key={rollup.topic} rollup={rollup} />
                  ))}
                </View>
              </Surface>
            ) : (
              <EmptyMemoryState />
            )}
          </Tabs.Content>
        </Tabs>
      ) : null}
    </ScrollView>
  );
}
