import { supabase } from './supabase';
export async function createCharge(amountCentavos: number, description: string) {
  return supabase.rpc('create_charge', { p_amount_centavos: amountCentavos, p_description: description });
}
export async function confirmPayment(chargeId: string, checklist: object) {
  return supabase.rpc('confirm_payment', { p_charge_id: chargeId, p_checklist: checklist });
}
export async function getPublicCharge(chargeId: string) {
  return supabase.rpc('get_public_charge', { p_charge_id: chargeId });
}
export async function claimPayment(chargeId: string, payerName: string, payerRef: string, paymentTime?: string, proofImage?: string) {
  return supabase.rpc('claim_payment', { p_charge_id: chargeId, p_payer_name: payerName, p_payer_ref: payerRef, p_payment_time: paymentTime || null, p_proof_image: proofImage || null });
}
export async function rejectPayment(chargeId: string, reason: string) {
  return supabase.rpc('reject_payment', { p_charge_id: chargeId, p_reason: reason });
}
export async function reportDispute(chargeId: string, customerName: string, reason: string, description?: string) {
  return supabase.rpc('report_dispute', { p_charge_id: chargeId, p_customer_name: customerName, p_reason: reason, p_description: description || null, p_evidence_url: null });
}
