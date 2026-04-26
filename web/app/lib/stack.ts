import { StackServerApp } from "@stackframe/stack";
import { env } from "../env";

let stackServerApp: StackServerApp<true> | null = null;

export function isStackConfigured(): boolean {
  return Boolean(
    env.NEXT_PUBLIC_STACK_PROJECT_ID &&
      env.NEXT_PUBLIC_STACK_PUBLISHABLE_CLIENT_KEY &&
      env.STACK_SECRET_SERVER_KEY
  );
}

export function getStackServerApp(): StackServerApp<true> {
  if (!isStackConfigured()) {
    throw new Error("Stack Auth is not configured");
  }

  // env.ts trims every runtimeEnv source, so consumers receive sanitized values
  // regardless of whether zod validation is skipped.
  stackServerApp ??= new StackServerApp({
    projectId: env.NEXT_PUBLIC_STACK_PROJECT_ID,
    publishableClientKey: env.NEXT_PUBLIC_STACK_PUBLISHABLE_CLIENT_KEY,
    secretServerKey: env.STACK_SECRET_SERVER_KEY,
    tokenStore: "nextjs-cookie",
    urls: {
      afterSignIn: "/handler/after-sign-in",
      afterSignUp: "/handler/after-sign-in",
    },
  });
  return stackServerApp;
}
