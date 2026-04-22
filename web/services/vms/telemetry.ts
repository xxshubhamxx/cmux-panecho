import {
  SpanStatusCode,
  trace,
  type Attributes,
  type Span,
} from "@opentelemetry/api";

type AttributeValue = string | number | boolean;
type MaybeAttributes = Record<string, AttributeValue | null | undefined>;

const tracer = trace.getTracer("cmux-vm");

export async function withVmSpan<T>(
  name: string,
  attributes: MaybeAttributes,
  fn: (span: Span) => Promise<T>,
): Promise<T> {
  const span = tracer.startSpan(name, { attributes: cleanAttributes(attributes) });
  const start = performance.now();
  try {
    return await fn(span);
  } catch (err) {
    recordSpanError(span, err);
    throw err;
  } finally {
    span.setAttribute("cmux.duration_ms", Math.round((performance.now() - start) * 100) / 100);
    span.end();
  }
}

export function setSpanAttributes(span: Span, attributes: MaybeAttributes): void {
  span.setAttributes(cleanAttributes(attributes));
}

export function recordSpanError(span: Span, err: unknown): void {
  if (err instanceof Error) {
    span.recordException(err);
    span.setStatus({ code: SpanStatusCode.ERROR, message: err.message });
    span.setAttributes({
      "cmux.error_name": err.name,
      "cmux.error_message": err.message,
    });
    return;
  }
  const message = String(err);
  span.recordException(message);
  span.setStatus({ code: SpanStatusCode.ERROR, message });
  span.setAttributes({
    "cmux.error_name": "NonError",
    "cmux.error_message": message,
  });
}

function cleanAttributes(attributes: MaybeAttributes): Attributes {
  const cleaned: Attributes = {};
  for (const [key, value] of Object.entries(attributes)) {
    if (value !== null && value !== undefined) {
      cleaned[key] = value;
    }
  }
  return cleaned;
}
