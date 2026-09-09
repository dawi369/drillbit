import {
  ALLOWED_CHALLENGE_CADENCE_HOURS,
  type ChallengeCadenceHours,
} from "@/lib/storage/types";
import type { ChallengeDifficulty, ChallengeMode } from "@/lib/widgets/types";

export const DIFFICULTY_OPTIONS: {
  value: ChallengeDifficulty;
  label: string;
}[] = [
  { value: "easy", label: "easy" },
  { value: "medium", label: "medium" },
  { value: "hard", label: "hard" },
];

export const MODE_OPTIONS: {
  value: ChallengeMode;
  label: string;
  description: string;
}[] = [
  {
    value: "solo",
    label: "solo",
    description:
      "Clean prompt, private reasoning, and no AI steering unless you switch later.",
  },
  {
    value: "coach",
    label: "ai coach",
    description:
      "Socratic pressure with hints, trade-offs, and probing follow-ups instead of spoilers.",
  },
  {
    value: "reveal",
    label: "reveal",
    description:
      "A direct model answer with components, alternatives, failure modes, and pitfalls.",
  },
];

export const CADENCE_OPTIONS: {
  value: ChallengeCadenceHours;
  label: string;
}[] = ALLOWED_CHALLENGE_CADENCE_HOURS.map((value) => ({
  value,
  label: value === 24 ? "daily" : `${value}h`,
}));
