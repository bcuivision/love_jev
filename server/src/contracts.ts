export interface AnalyzeRequest {
  sessionID: string;
  revision: number;
  context: string;
  source: "replaykit-ocr" | "test";
}

export interface AnalyzeResponse {
  sessionID: string;
  revision: number;
  recommendation: string;
  intimacy: number | null;
  explanation: string;
  reason: RecommendationReason | null;
  isDemo: boolean;
}

// A concise decision summary, never the model's private reasoning trace.
export interface RecommendationReason {
  relationshipStage: string;
  observation: string;
  action: string;
  expectedResult: string;
}

export interface IntimacyAssessment {
  sessionID: string;
  revision: number;
  intimacy: number | null;
  isDemo: boolean;
}
export type Analyze = (input: AnalyzeRequest, signal: AbortSignal,
  onAssessment?: (value: IntimacyAssessment) => void) => Promise<AnalyzeResponse>;

export interface DraftImpactRequest extends AnalyzeRequest {
  draft: string;
  draftID: string;
}
export interface DraftImpactResponse {
  sessionID: string;
  revision: number;
  draftID: string;
  before: number | null;
  after: number | null;
  delta: number | null;
  explanation: string;
  isDemo: boolean;
}
export type AnalyzeDraft = (input: DraftImpactRequest, signal: AbortSignal) => Promise<DraftImpactResponse>;

export function parseDraftRequest(value: unknown): DraftImpactRequest {
  const context = parseRequest(value);
  const v = value as Record<string, unknown>;
  if (typeof v.draft !== "string" || !v.draft.trim() || v.draft.length > 2_000
      || typeof v.draftID !== "string" || !/^[\w-]{1,128}$/.test(v.draftID)) {
    throw new ServiceError(400, "invalid_draft");
  }
  return { ...context, draft: v.draft.trim(), draftID: v.draftID };
}

export class ServiceError extends Error {
  readonly status: number;
  readonly code: string;
  constructor(status: number, code: string) {
    super(code); this.status = status; this.code = code;
  }
}

export function parseRequest(value: unknown): AnalyzeRequest {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new ServiceError(400, "invalid_request");
  const v = value as Record<string, unknown>;
  if (typeof v.sessionID !== "string" || !/^[\w-]{1,128}$/.test(v.sessionID)
      || typeof v.revision !== "number" || !Number.isSafeInteger(v.revision) || v.revision < 0
      || typeof v.context !== "string" || !v.context.trim() || v.context.length > 10_000
      || !["replaykit-ocr", "test"].includes(String(v.source))) throw new ServiceError(400, "invalid_request");
  return { sessionID: v.sessionID, revision: v.revision, context: v.context.trim(), source: v.source as AnalyzeRequest["source"] };
}
