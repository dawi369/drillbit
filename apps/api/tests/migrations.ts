import first from "../migrations/0001_initial.sql?raw";
import second from "../migrations/0002_scheduled_retries.sql?raw";
import third from "../migrations/0003_ai_usage.sql?raw";
import fourth from "../migrations/0004_practice_help.sql?raw";
import fifth from "../migrations/0005_companion.sql?raw";
import sixth from "../migrations/0006_interview.sql?raw";
export async function initializeDatabase(db: D1Database) {
  for (const sql of [first, second, third, fourth, fifth, sixth])
    for (const statement of sql.split(";").filter((s) => s.trim()))
      await db
        .prepare(
          statement
            .replace(/CREATE TABLE /g, "CREATE TABLE IF NOT EXISTS ")
            .replace(
              /CREATE UNIQUE INDEX /g,
              "CREATE UNIQUE INDEX IF NOT EXISTS ",
            )
            .replace(/CREATE INDEX /g, "CREATE INDEX IF NOT EXISTS "),
        )
        .run();
}
