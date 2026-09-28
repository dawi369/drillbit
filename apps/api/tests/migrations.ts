import first from "../migrations/0001_initial.sql?raw";
import second from "../migrations/0002_scheduled_retries.sql?raw";
import third from "../migrations/0003_ai_usage.sql?raw";
import fourth from "../migrations/0004_practice_help.sql?raw";
import fifth from "../migrations/0005_companion.sql?raw";
import sixth from "../migrations/0006_interview.sql?raw";
import seventh from "../migrations/0007_interview_streams.sql?raw";
import eighth from "../migrations/0008_question_library.sql?raw";
import ninth from "../migrations/0009_voice.sql?raw";
import tenth from "../migrations/0010_daily_visits.sql?raw";
import eleventh from "../migrations/0011_learning_loop.sql?raw";
import twelfth from "../migrations/0012_credential_model.sql?raw";
import thirteenth from "../migrations/0013_tickets_and_tomorrow.sql?raw";
export async function initializeDatabase(db: D1Database) {
  for (const sql of [first, second, third, fourth, fifth, sixth, seventh, eighth, ninth, tenth, eleventh])
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
  // ADD COLUMN has no IF NOT EXISTS; a repeat initialisation already has it.
  for (const statement of twelfth.split(";").filter((s) => s.trim()))
    await db.prepare(statement).run().catch((error: Error) => {
      if (!/duplicate column/i.test(error.message)) throw error;
    });
  for (const statement of thirteenth.split(";").filter((s) => s.trim()))
    await db.prepare(statement.replace(/CREATE TABLE /g, "CREATE TABLE IF NOT EXISTS ")).run();
}
