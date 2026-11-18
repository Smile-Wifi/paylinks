import { supabase } from './supabase';
export async function createCharge(amountCentavos: number, description: string) {
  return supabase.rpc('create_charge', { p_amount_centavos: amountCentavos, p_description: description });
}
export async function confirmPayment(chargeId: string, checklist: object) {
  return supabase.rpc('confirm_payment', { p_charge_id: chargeId, p_checklist: checklist });
}
