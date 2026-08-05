// src/payments/payments.service.ts
import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { VeroCourierService } from '../verocourier/airportpickup.service';

/** PayChangu callback/webhook payload (they may send tx_ref, reference, status, etc.). */
interface PayChanguCallbackPayload {
  tx_ref?: string;
  reference?: string;
  transaction_id?: string;
  charge_id?: string;
  status?: string;
  payment_status?: string;
  event_type?: string;
}

export interface RefundRequestBody {
  orderId?: string;
  orderNumber?: string;
  amount?: number | string;
  currency?: string;
  refundType?: string;
  reason?: string;
  tx_ref?: string;
  txRef?: string;
  itemName?: string;
  processingDays?: number | string;
  charge_id?: string;
  chargeId?: string;
}

@Injectable()
export class PaymentsService {
  private readonly logger = new Logger(PaymentsService.name);

  constructor(private readonly veroCourierService: VeroCourierService) {}

  /**
   * Handle PayChangu webhook/callback. Parses tx_ref (or reference):
   * - airport-{bookingId}-{timestamp} → mark airport pickup as paid
   */
  async handlePayChanguCallback(body: PayChanguCallbackPayload): Promise<void> {
    const txRef = (
      body?.tx_ref ??
      body?.reference ??
      body?.transaction_id ??
      ''
    ).toString();
    const rawStatus = (
      body?.status ??
      body?.payment_status ??
      ''
    ).toString().toLowerCase();

    const isSuccess =
      rawStatus === 'successful' ||
      rawStatus === 'success' ||
      rawStatus === 'paid' ||
      rawStatus === 'completed';

    if (!isSuccess) {
      return; // Ignore failed/cancelled – no update
    }

    // Airport pickup: tx_ref = "airport-{id}-{timestamp}"
    const airportMatch = txRef.match(/^airport-(\d+)-/);
    if (airportMatch) {
      const bookingId = parseInt(airportMatch[1], 10);
      if (!isNaN(bookingId)) {
        await this.veroCourierService.markAirportPickupPaid(bookingId);
      }
    }

    // Add other tx_ref patterns here (e.g. cart, digital products)
  }

  /**
   * Accept a marketplace refund request.
   *
   * `refundType`: `cancel_order` | `return_goods`
   * Settlement with the customer’s payment method typically takes up to 3 days.
   *
   * When PAYCHANGU_SECRET_KEY and a charge_id (or verified tx_ref) are available,
   * attempts PayChangu card refund: POST /charge-card/refund/{charge_id}.
   */
  async requestRefund(body: RefundRequestBody) {
    const orderId = (body?.orderId ?? '').toString().trim();
    const orderNumber = (body?.orderNumber ?? '').toString().trim();
    const reason = (body?.reason ?? '').toString().trim();
    const refundType = (body?.refundType ?? '').toString().trim().toLowerCase();
    const txRef = (body?.tx_ref ?? body?.txRef ?? '').toString().trim();
    const currency = (body?.currency ?? 'MWK').toString().trim() || 'MWK';
    const amount = Number(body?.amount ?? 0);
    const processingDays = Number(body?.processingDays ?? 3) || 3;

    if (!orderId) {
      throw new BadRequestException('orderId is required');
    }
    if (!reason) {
      throw new BadRequestException('reason is required');
    }
    if (
      refundType !== 'cancel_order' &&
      refundType !== 'return_goods'
    ) {
      throw new BadRequestException(
        'refundType must be cancel_order or return_goods',
      );
    }
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new BadRequestException('amount must be a positive number');
    }

    let paychanguStatus: string | null = null;
    let paychanguMessage: string | null = null;
    let chargeId = (body?.charge_id ?? body?.chargeId ?? '').toString().trim();

    const secret = (process.env.PAYCHANGU_SECRET_KEY ?? '').trim();
    if (secret) {
      try {
        if (!chargeId && txRef) {
          chargeId = (await this._resolveChargeId(txRef, secret)) ?? '';
        }
        if (chargeId) {
          const refundRes = await fetch(
            `https://api.paychangu.com/charge-card/refund/${encodeURIComponent(chargeId)}`,
            {
              method: 'POST',
              headers: {
                Accept: 'application/json',
                Authorization: `Bearer ${secret}`,
              },
            },
          );
          const text = await refundRes.text();
          let parsed: any = null;
          try {
            parsed = text ? JSON.parse(text) : null;
          } catch {
            parsed = null;
          }
          paychanguStatus = (parsed?.status ?? refundRes.status).toString();
          paychanguMessage = (
            parsed?.message ??
            (refundRes.ok ? 'Refund submitted to PayChangu' : text)
          )?.toString();
          this.logger.log(
            `PayChangu refund order=${orderId} charge=${chargeId} status=${paychanguStatus}`,
          );
        } else {
          this.logger.warn(
            `Refund queued without charge_id/tx_ref for order=${orderId}`,
          );
        }
      } catch (err) {
        this.logger.error(`PayChangu refund failed for order=${orderId}`, err as any);
        paychanguMessage =
          err instanceof Error ? err.message : 'PayChangu refund error';
      }
    }

    return {
      status: 'pending',
      message: `Refund request accepted. Funds are processed within ${processingDays} days.`,
      data: {
        orderId,
        orderNumber,
        amount,
        currency,
        refundType,
        reason,
        tx_ref: txRef || undefined,
        charge_id: chargeId || undefined,
        processingDays,
        paychanguStatus,
        paychanguMessage,
      },
    };
  }

  private async _resolveChargeId(
    txRef: string,
    secret: string,
  ): Promise<string | null> {
    try {
      const res = await fetch(
        `https://api.paychangu.com/transaction/verify/${encodeURIComponent(txRef)}`,
        {
          method: 'GET',
          headers: {
            Accept: 'application/json',
            Authorization: `Bearer ${secret}`,
          },
        },
      );
      if (!res.ok) return null;
      const json: any = await res.json();
      const data = json?.data ?? json;
      const charge =
        data?.charge_id ??
        data?.chargeId ??
        data?.reference ??
        data?.transaction?.charge_id;
      const id = (charge ?? '').toString().trim();
      return id || null;
    } catch (err) {
      this.logger.warn(`Could not resolve charge_id for tx_ref=${txRef}`, err as any);
      return null;
    }
  }
}
