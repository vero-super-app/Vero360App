// src/payments/payments.controller.ts
import { Body, Controller, Post } from '@nestjs/common';
import { PaymentsService } from './payments.service';

@Controller('payments')
export class PaymentsController {
  constructor(private readonly paymentsService: PaymentsService) {}

  /** PayChangu webhook / callback. */
  @Post('callback')
  async callback(@Body() body: Record<string, unknown>) {
    await this.paymentsService.handlePayChanguCallback(body as any);
    return { status: 'ok' };
  }

  /**
   * Marketplace refund request.
   * Refund settlement with the payer typically completes within 3 days.
   *
   * Body: { orderId, orderNumber, amount, currency, refundType, reason, tx_ref? }
   * refundType: `cancel_order` | `return_goods`
   */
  @Post('refund')
  async refund(@Body() body: Record<string, unknown>) {
    return this.paymentsService.requestRefund(body);
  }
}
