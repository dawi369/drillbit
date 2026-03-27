export function dateToTimeMinutes(date: Date) {
  return date.getHours() * 60 + date.getMinutes();
}

export function timeMinutesToDate(totalMinutes: number) {
  const date = new Date();
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;

  date.setHours(hours, minutes, 0, 0);

  return date;
}

export function formatTimeMinutes(totalMinutes: number) {
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  const meridiem = hours >= 12 ? "PM" : "AM";
  const twelveHour = hours % 12 || 12;

  return `${twelveHour}:${minutes.toString().padStart(2, "0")} ${meridiem}`;
}

export function getNextScheduledChallengeDate({
  from = new Date(),
  firstChallengeTimeMinutes = 9 * 60,
  challengeCadenceHours = 24,
}: {
  from?: Date;
  firstChallengeTimeMinutes?: number;
  challengeCadenceHours?: number;
}) {
  const cadenceMinutes = challengeCadenceHours * 60;
  const dayStart = new Date(from);
  dayStart.setHours(0, 0, 0, 0);

  const candidateMinutes: number[] = [];
  for (
    let totalMinutes = firstChallengeTimeMinutes;
    totalMinutes < 24 * 60;
    totalMinutes += cadenceMinutes
  ) {
    candidateMinutes.push(totalMinutes);
  }

  if (candidateMinutes.length === 0) {
    const fallback = new Date(dayStart);
    fallback.setMinutes(firstChallengeTimeMinutes, 0, 0);
    return fallback > from ? fallback : new Date(fallback.getTime() + 24 * 60 * 60_000);
  }

  for (const totalMinutes of candidateMinutes) {
    const candidate = new Date(dayStart);
    candidate.setMinutes(totalMinutes, 0, 0);

    if (candidate > from) {
      return candidate;
    }
  }

  const nextDayFirstSlot = new Date(dayStart);
  nextDayFirstSlot.setDate(nextDayFirstSlot.getDate() + 1);
  nextDayFirstSlot.setMinutes(candidateMinutes[0], 0, 0);
  return nextDayFirstSlot;
}
