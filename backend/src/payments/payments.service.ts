// src/payments/payments.service.ts
import { Injectable } from '@nestjs/common';
import { VeroCourierService } from '../verocourier/airportpickup.service';

/** PayChangu callback/webhook payload (they may send tx_ref, reference, status, etc.). */
interface PayChanguCallbackPayload {
  tx_ref?: string;
  reference?: string;
  transaction_id?: string;
  status?: string;
  payment_status?: string;
  event_type?: string;
}

@Injectable()
export class PaymentsService {
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
}
