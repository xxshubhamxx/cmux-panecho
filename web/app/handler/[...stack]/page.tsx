import { Suspense } from "react";
import { notFound } from "next/navigation";
import { StackHandler } from "@stackframe/stack";
import { stackServerApp } from "../../lib/stack";

export default function StackHandlerPage(props: { params: Promise<{ stack: string[] }> }) {
  if (!stackServerApp) {
    notFound();
  }

  return (
    <Suspense>
      <StackHandler fullPage app={stackServerApp} params={props.params} />
    </Suspense>
  );
}
