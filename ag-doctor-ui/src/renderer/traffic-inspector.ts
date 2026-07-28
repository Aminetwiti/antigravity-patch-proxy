/**
 * ag-doctor UI — Traffic Inspector Module
 * Real-time network request/response logger & payload translator inspector.
 * Captures intercepted Cloud Code API calls, latencies, status codes, and format conversions.
 */

export interface TrafficEntry {
  id: string;
  timestamp: number;
  method: string;
  path: string;
  targetModel: string;
  translatedProvider: string;
  statusCode: number;
  latencyMs: number;
  requestPayload?: string;
  responsePayload?: string;
}

export class TrafficInspectorEngine {
  private entries: TrafficEntry[] = [];
  private maxEntries = 200;

  public logTraffic(entry: Omit<TrafficEntry, 'id' | 'timestamp'>): TrafficEntry {
    const fullEntry: TrafficEntry = {
      ...entry,
      id: `tr-${Date.now()}-${Math.random().toString(36).substring(2, 6)}`,
      timestamp: Date.now(),
    };

    this.entries.unshift(fullEntry);
    if (this.entries.length > this.maxEntries) {
      this.entries.pop();
    }
    return fullEntry;
  }

  public getEntries(): TrafficEntry[] {
    return [...this.entries];
  }

  public filterEntries(query: string, providerFilter = 'all'): TrafficEntry[] {
    const q = query.trim().toLowerCase();
    return this.entries.filter((entry) => {
      const matchesProvider = providerFilter === 'all' || entry.translatedProvider.toLowerCase() === providerFilter.toLowerCase();
      const matchesQuery =
        !q ||
        entry.path.toLowerCase().includes(q) ||
        entry.targetModel.toLowerCase().includes(q) ||
        entry.translatedProvider.toLowerCase().includes(q) ||
        entry.statusCode.toString().includes(q);

      return matchesProvider && matchesQuery;
    });
  }

  public clear(): void {
    this.entries = [];
  }

  public async replayEntry(id: string, executor: (entry: TrafficEntry) => Promise<{ statusCode: number; latencyMs: number }>): Promise<TrafficEntry | null> {
    const original = this.entries.find((e) => e.id === id);
    if (!original) return null;

    const start = Date.now();
    try {
      const res = await executor(original);
      const replayed = this.logTraffic({
        method: original.method,
        path: original.path + ' (Replayed)',
        targetModel: original.targetModel,
        translatedProvider: original.translatedProvider,
        statusCode: res.statusCode,
        latencyMs: res.latencyMs || (Date.now() - start),
        requestPayload: original.requestPayload,
        responsePayload: 'Replayed response payload',
      });
      return replayed;
    } catch (err: any) {
      const replayed = this.logTraffic({
        method: original.method,
        path: original.path + ' (Replayed Fail)',
        targetModel: original.targetModel,
        translatedProvider: original.translatedProvider,
        statusCode: 500,
        latencyMs: Date.now() - start,
        requestPayload: original.requestPayload,
        responsePayload: JSON.stringify({ error: err.message }),
      });
      return replayed;
    }
  }

  public generateDiffView(entry: TrafficEntry): { reqRaw: string; resRaw: string; isError: boolean } {
    return {
      reqRaw: entry.requestPayload || '{}',
      resRaw: entry.responsePayload || '{}',
      isError: entry.statusCode >= 400,
    };
  }
}

// CJS/global hookup for <script> tag use (no bundler required in renderer).
if (typeof window !== 'undefined') {
  (window as unknown as { AgTraffic?: unknown }).AgTraffic = {
    TrafficInspectorEngine,
  };
}
