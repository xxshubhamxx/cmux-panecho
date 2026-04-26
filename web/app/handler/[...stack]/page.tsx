import { Suspense } from "react";
import { StackHandler } from "@stackframe/stack";
import { notFound } from "next/navigation";
import { getStackServerApp, isStackConfigured } from "../../lib/stack";

export default function StackHandlerPage(props: { params: Promise<{ stack: string[] }> }) {
  if (!isStackConfigured()) {
    notFound();
  }

  const stackServerApp = getStackServerApp();
  return (
    <Suspense>
      <StackHandler fullPage app={stackServerApp} params={props.params} />
    </Suspense>
  );
}
