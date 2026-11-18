export type ChargeStatus = 'PENDING'|'CLAIMED'|'PAID'|'REJECTED'|'EXPIRED'|'CANCELLED'|'DISPUTED'|'FROZEN';
export type MerchantStatus = 'PENDING_VERIFICATION'|'VERIFIED'|'REJECTED'|'SUSPENDED'|'FROZEN';
export const DISCLAIMER = "Money goes directly from Customer GCash to Merchant GCash. PayLinks only records the proof of payment and supports manual verification. PayLinks does not receive or hold customer funds.";
export const DISCLAIMER_2 = "Submitting a payment reference number does not mean your payment has been verified. Only the authorized merchant operator can confirm receipt.";
