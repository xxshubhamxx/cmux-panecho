import * as Data from "effect/Data";
import type { ProviderId } from "./drivers";

export class VmDatabaseError extends Data.TaggedError("VmDatabaseError")<{
  readonly operation: string;
  readonly cause: unknown;
}> {}

export class VmProviderOperationError extends Data.TaggedError("VmProviderOperationError")<{
  readonly provider: ProviderId;
  readonly operation: string;
  readonly cause: unknown;
}> {}

export class VmNotFoundError extends Data.TaggedError("VmNotFoundError")<{
  readonly vmId: string;
}> {}

export class VmCreateInProgressError extends Data.TaggedError("VmCreateInProgressError")<{
  readonly idempotencyKey: string;
}> {}

export class VmCreateFailedError extends Data.TaggedError("VmCreateFailedError")<{
  readonly idempotencyKey: string;
  readonly message: string;
}> {}

export class VmLimitExceededError extends Data.TaggedError("VmLimitExceededError")<{
  readonly kind: "active_vms";
  readonly billingTeamId: string;
  readonly limit: number;
}> {}

export type VmWorkflowError =
  | VmDatabaseError
  | VmProviderOperationError
  | VmNotFoundError
  | VmCreateInProgressError
  | VmCreateFailedError
  | VmLimitExceededError;

export function isVmNotFoundError(err: unknown): err is VmNotFoundError {
  return (err as { _tag?: string } | null)?._tag === "VmNotFoundError";
}

export function isVmCreateInProgressError(err: unknown): err is VmCreateInProgressError {
  return (err as { _tag?: string } | null)?._tag === "VmCreateInProgressError";
}

export function isVmCreateFailedError(err: unknown): err is VmCreateFailedError {
  return (err as { _tag?: string } | null)?._tag === "VmCreateFailedError";
}

export function isVmLimitExceededError(err: unknown): err is VmLimitExceededError {
  return (err as { _tag?: string } | null)?._tag === "VmLimitExceededError";
}
