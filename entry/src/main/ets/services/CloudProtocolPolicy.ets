import { DeadlineSyncEvent, DeadlineSyncProtocol } from './DeadlineSyncProtocol';

interface HistoricalCloudEnvelope {
  version: number; id: string; deadlineId: string; historicalPayload: string;
}

// Database version and marketing app version are not cloud compatibility contracts.
export class CloudProtocolPolicy {
  static readonly MIN_CLOUD_PROTOCOL: number = 2;
  static canExchange(protocol: number): boolean { return protocol === CloudProtocolPolicy.MIN_CLOUD_PROTOCOL; }
  static historicalId(eventId: string): string { return `history-v2:${encodeURIComponent(eventId)}`; }
  static canCarryHistorical(id: string, payload: string): boolean {
    try {
      const event: DeadlineSyncEvent = DeadlineSyncProtocol.decode(payload);
      return event.version === 1 && event.id === id && JSON.stringify(event) === payload;
    } catch (error) { return false; }
  }
  static wrapHistorical(event: DeadlineSyncEvent): string {
    if (event.version !== 1) { throw new Error('Only existing protocol-one history needs a carrier.'); }
    const envelope: HistoricalCloudEnvelope = { version: 2, id: CloudProtocolPolicy.historicalId(event.id),
      deadlineId: event.deadlineId, historicalPayload: JSON.stringify(DeadlineSyncProtocol.decode(JSON.stringify(event))) };
    return JSON.stringify(envelope);
  }
  static transportVersion(payload: string): number {
    const envelope: HistoricalCloudEnvelope = JSON.parse(payload) as HistoricalCloudEnvelope;
    return envelope.version;
  }
  static readTransport(id: string, deadlineId: string, payload: string): DeadlineSyncEvent {
    const envelope: HistoricalCloudEnvelope = JSON.parse(payload) as HistoricalCloudEnvelope;
    if (envelope === null) { throw new Error('Invalid transport.'); }
    if (envelope.historicalPayload !== undefined) {
      if (envelope.version !== 2 || typeof envelope.historicalPayload !== 'string' ||
        envelope.id !== id || envelope.deadlineId !== deadlineId || Object.keys(envelope).some((key: string) =>
          !['version','id','deadlineId','historicalPayload'].includes(key))) { throw new Error('Invalid historical carrier.'); }
      const event: DeadlineSyncEvent = DeadlineSyncProtocol.decode(envelope.historicalPayload);
      if (event.version !== 1 || event.deadlineId !== deadlineId || id !== CloudProtocolPolicy.historicalId(event.id) ||
        envelope.historicalPayload !== JSON.stringify(event)) {
        throw new Error('Invalid historical identity.');
      }
      return event;
    }
    const event: DeadlineSyncEvent = DeadlineSyncProtocol.decode(payload);
    if (event.id !== id || event.deadlineId !== deadlineId) { throw new Error('Invalid transport identity.'); }
    return event;
  }
  static canImport(owner: string, verifiedAccount: string, sourceAccount: string,
    complete: boolean, oldWritesStopped: boolean): boolean {
    return verifiedAccount.length > 0 && verifiedAccount === sourceAccount &&
      (owner.length === 0 || owner === verifiedAccount) && complete && oldWritesStopped;
  }
}
