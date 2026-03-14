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
