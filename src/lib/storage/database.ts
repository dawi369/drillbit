import { openDatabaseAsync, type SQLiteDatabase } from "expo-sqlite";

import {
  CREATE_ALL_TABLES_SQL,
  DATABASE_NAME,
  DATABASE_SCHEMA_VERSION,
} from "@/lib/storage/schema";

let databasePromise: Promise<SQLiteDatabase> | null = null;

async function migrateDatabase(db: SQLiteDatabase) {
  const [{ user_version: userVersion }] = await db.getAllAsync<{ user_version: number }>(
    "PRAGMA user_version",
  );

  if (userVersion >= DATABASE_SCHEMA_VERSION) {
    return;
  }

  await db.withTransactionAsync(async () => {
    for (const statement of CREATE_ALL_TABLES_SQL) {
      await db.execAsync(statement);
    }

    await db.execAsync(`PRAGMA user_version = ${DATABASE_SCHEMA_VERSION}`);
  });
}

export async function getDatabase() {
  if (!databasePromise) {
    databasePromise = openDatabaseAsync(DATABASE_NAME).then(async (db) => {
      await db.execAsync("PRAGMA foreign_keys = ON");
      await migrateDatabase(db);
      return db;
    });
  }

  return databasePromise;
}

export async function initializeDatabase() {
  return getDatabase();
}
