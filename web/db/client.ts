import { drizzle } from "drizzle-orm/postgres-js";
import postgres, { type Sql } from "postgres";
import * as schema from "./schema";

function createDb(sql: Sql) {
  return drizzle({ client: sql, schema });
}

type CloudDb = ReturnType<typeof createDb>;
type CloudDbState = {
  db: CloudDb;
  sql: Sql;
  url: string;
};

const globalForDb = globalThis as typeof globalThis & {
  __cmuxCloudDb?: CloudDbState;
};

export function cloudDb(): CloudDb {
  const url = process.env.DIRECT_DATABASE_URL ?? process.env.DATABASE_URL;
  if (!url) {
    throw new Error("DATABASE_URL is required for Cloud VM database access");
  }

  if (globalForDb.__cmuxCloudDb?.url === url) {
    return globalForDb.__cmuxCloudDb.db;
  }

  const sql = postgres(url, {
    max: Number(process.env.CMUX_DB_POOL_MAX ?? "5"),
    prepare: false,
  });
  const db = createDb(sql);
  globalForDb.__cmuxCloudDb = { db, sql, url };
  return db;
}

export async function closeCloudDbForTests(): Promise<void> {
  const state = globalForDb.__cmuxCloudDb;
  globalForDb.__cmuxCloudDb = undefined;
  await state?.sql.end();
}
