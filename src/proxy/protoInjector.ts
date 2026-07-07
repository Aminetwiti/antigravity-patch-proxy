/**
 * Protobuf injection logic for the GetAvailableModels response.
 * Pure functions — no I/O, no side effects, fully testable.
 */

import {
  parseProto,
  encodeVarint,
  findModelEntryFieldTag,
  extractFieldMapping,
  encodeModelEntryForGetModels,
} from './protobuf';
import { generateModelPlaceholderId } from './idGenerator';
import type { CustomModel } from './types';

/**
 * Result of injecting custom models into a GetAvailableModels protobuf response.
 */
export interface InjectionResult {
  /** The modified buffer (may be the same as input if no injection occurred). */
  buffer: Buffer;
  /** Number of models that were injected. */
  injectedCount: number;
  /** Whether the buffer was modified. */
  modified: boolean;
}

/**
 * Injects custom models into a Google GetAvailableModels protobuf response.
 *
 * The response format is gRPC-Web:
 *   - byte 0: flags
 *   - bytes 1-4: message length (big-endian uint32)
 *   - bytes 5+: protobuf-encoded message
 *
 * The function:
 *   1. Parses the protobuf message body
 *   2. Identifies the repeated model entry field
 *   3. Encodes each custom model with the same field mapping
 *   4. Re-wraps the message with the new length header
 *
 * @param responseBuf Raw gRPC-Web response buffer
 * @param customModels Custom models to inject
 * @returns Injection result with modified buffer and metadata
 */
export function injectCustomModelsIntoResponse(
  responseBuf: Buffer,
  customModels: CustomModel[],
): InjectionResult {
  // No injection if no custom models or buffer too small to contain header + body
  if (customModels.length === 0 || responseBuf.length <= 6) {
    return { buffer: responseBuf, injectedCount: 0, modified: false };
  }

  try {
    const flags = responseBuf[0];
    const msgLen = responseBuf.readUInt32BE(1);
    if (5 + msgLen > responseBuf.length) {
      return { buffer: responseBuf, injectedCount: 0, modified: false };
    }

    const msgBody = responseBuf.subarray(5, 5 + msgLen);
    const parsed = parseProto(msgBody, 0, msgBody.length);
    const modelTag = findModelEntryFieldTag(parsed);

    if (modelTag === null) {
      return { buffer: responseBuf, injectedCount: 0, modified: false };
    }

    const sampleEntry = parsed.find((f) => f.tag === modelTag && Array.isArray(f.value));
    if (!sampleEntry || !Array.isArray(sampleEntry.value)) {
      return { buffer: responseBuf, injectedCount: 0, modified: false };
    }

    const fieldMapping = extractFieldMapping(sampleEntry.value);
    const newParts: Buffer[] = [msgBody];

    for (const m of customModels) {
      const placeholderId = generateModelPlaceholderId(m);
      const entry = encodeModelEntryForGetModels(
        `models/${placeholderId}`,
        m.displayName,
        fieldMapping,
      );
      const tagBuf = encodeVarint(modelTag);
      const lenBuf = encodeVarint(entry.length);
      newParts.push(tagBuf, lenBuf, entry);
    }

    const newMsgBody = Buffer.concat(newParts);
    const newHeader = Buffer.alloc(5);
    newHeader[0] = flags;
    newHeader.writeUInt32BE(newMsgBody.length, 1);
    const modifiedBuf = Buffer.concat([newHeader, newMsgBody]);

    return { buffer: modifiedBuf, injectedCount: customModels.length, modified: true };
  } catch {
    return { buffer: responseBuf, injectedCount: 0, modified: false };
  }
}

/**
 * Builds a gRPC-Web frame for a single protobuf message body.
 * Format: [flags:1][length:4 BE][body:N]
 */
export function buildGrpcWebFrame(flags: number, body: Buffer): Buffer {
  const header = Buffer.alloc(5);
  header[0] = flags;
  header.writeUInt32BE(body.length, 1);
  return Buffer.concat([header, body]);
}

/**
 * Parses a gRPC-Web frame header.
 * @returns Object with flags and message length, or null if buffer is too short.
 */
export function parseGrpcWebHeader(buf: Buffer): { flags: number; msgLen: number } | null {
  if (buf.length < 5) return null;
  return {
    flags: buf[0],
    msgLen: buf.readUInt32BE(1),
  };
}
