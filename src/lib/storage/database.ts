import { openDatabaseAsync, type SQLiteDatabase } from "expo-sqlite";

import {
  CREATE_ALL_TABLES_SQL,
  DATABASE_NAME,
} from "@/lib/storage/schema";

let databasePromise: Promise<SQLiteDatabase> | null = null;

async function createTables(db: SQLiteDatabase) {
  await db.withTransactionAsync(async () => {
    for (const statement of CREATE_ALL_TABLES_SQL) {
      await db.execAsync(statement);
    }
  });
}

export async function getDatabase() {
  if (!databasePromise) {
    databasePromise = openDatabaseAsync(DATABASE_NAME).then(async (db) => {
      await db.execAsync("PRAGMA foreign_keys = ON");
      await createTables(db);
      return db;
    });
  }

  return databasePromise;
}

export async function initializeDatabase() {
  return getDatabase();
}
