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

  const baseSlot = new Date(dayStart);
  baseSlot.setMinutes(firstChallengeTimeMinutes, 0, 0);

  const slotsToCheck = Math.ceil((48 * 60) / cadenceMinutes) + 2;

  for (let index = 0; index < slotsToCheck; index += 1) {
    const candidate = new Date(baseSlot.getTime() + index * cadenceMinutes * 60_000);

    if (candidate > from) {
      return candidate;
    }
  }

  return new Date(from.getTime() + cadenceMinutes * 60_000);
}
