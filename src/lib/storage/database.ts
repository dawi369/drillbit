import { deleteDatabaseAsync, openDatabaseAsync, type SQLiteDatabase } from "expo-sqlite";

import {
  CREATE_ALL_TABLES_SQL,
  DATABASE_NAME,
} from "@/lib/storage/schema";

let databasePromise: Promise<SQLiteDatabase> | null = null;
let databaseInstance: SQLiteDatabase | null = null;

async function createTables(db: SQLiteDatabase) {
  await db.withTransactionAsync(async () => {
    for (const statement of CREATE_ALL_TABLES_SQL) {
      await db.execAsync(statement);
    }

    const sessionColumns = await db.getAllAsync<{ name: string }>(
      "PRAGMA table_info(challenge_sessions)",
    );
    const hasAssistantDraftColumn = sessionColumns.some(
      (column) => column.name === "assistant_draft",
    );

    if (!hasAssistantDraftColumn) {
      await db.execAsync(
        "ALTER TABLE challenge_sessions ADD COLUMN assistant_draft TEXT",
      );
      await db.execAsync(
        "UPDATE challenge_sessions SET assistant_draft = conversation_summary WHERE assistant_draft IS NULL",
      );
    }
  });
}

export async function getDatabase() {
  if (!databasePromise) {
    databasePromise = openDatabaseAsync(DATABASE_NAME).then(async (db) => {
      await db.execAsync("PRAGMA foreign_keys = ON");
      await createTables(db);
      databaseInstance = db;
      return db;
    });
  }

  return databasePromise;
}

export async function resetDatabase() {
  const existing = databaseInstance ?? (databasePromise ? await databasePromise : null);

  databaseInstance = null;
  databasePromise = null;

  if (existing) {
    await existing.closeAsync();
  }

  await new Promise((resolve) => setTimeout(resolve, 50));
  await deleteDatabaseAsync(DATABASE_NAME);

  return getDatabase();
}
