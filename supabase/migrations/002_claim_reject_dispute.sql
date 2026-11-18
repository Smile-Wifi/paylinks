-- 002: Public claim, reject, dispute - NO fake payment, NO customer self-confirm

create or replace function public.get_public_charge(p_charge_id text)
returns jsonb language plpgsql security definer as $$
declare v jsonb;
begin
  update public.charges set status='EXPIRED' where id=p_charge_id and status='PENDING' and expires_at < now();
  select jsonb_build_object(
    'id', c.id, 'amount_centavos', c.amount_centavos, 'currency', c.currency,
    'description', c.description, 'reference', c.reference, 'status', c.status,
    'expires_at', c.expires_at, 'created_at', c.created_at,
    'business_name', m.business_name, 'logo_url', m.logo_url,
    'gcash_name', m.gcash_name, 'gcash_number', m.gcash_number,
    'qr_image', m.qr_image, 'verification_status', m.verification_status,
    'merchant_status', m.status
  ) into v from public.charges c join public.merchants m on m.id=c.merchant_id where c.id=p_charge_id;
  return v;
end; $$;

create or replace function public.claim_payment(p_charge_id text, p_payer_name text, p_payer_ref text, p_payment_time timestamptz default null, p_proof_image text default null)
returns public.charges language plpgsql security definer as $$
declare v_charge public.charges;
begin
  if trim(coalesce(p_payer_name,''))='' then raise exception 'Payer name required'; end if;
  if length(trim(coalesce(p_payer_ref,''))) < 6 then raise exception 'Valid GCash reference required'; end if;
  begin
    update public.charges set status='CLAIMED', payer_name=trim(p_payer_name), payer_ref=upper(trim(p_payer_ref)),
      payer_payment_time=p_payment_time, proof_image=p_proof_image, claimed_at=now()
    where id=p_charge_id and status='PENDING' and expires_at > now()
    returning * into v_charge;
  exception when unique_violation then raise exception 'Duplicate payment reference detected';
  end;
  if v_charge.id is null then raise exception 'Cannot claim: expired, already claimed, or not found'; end if;
  insert into public.charge_audit(charge_id, merchant_id, actor_role, action, previous_status, new_status)
  values (v_charge.id, v_charge.merchant_id, 'customer','CLAIMED','PENDING','CLAIMED');
  return v_charge;
end; $$;

create or replace function public.reject_payment(p_charge_id text, p_reason text)
returns public.charges language plpgsql security definer as $$
declare v_charge public.charges;
begin
  if trim(coalesce(p_reason,''))='' then raise exception 'Rejection reason required'; end if;
  update public.charges set status='REJECTED', rejection_reason=trim(p_reason)
  where id=p_charge_id and merchant_id=public.my_merchant_id() and status='CLAIMED'
  returning * into v_charge;
  if v_charge.id is null then raise exception 'Cannot reject: not CLAIMED or not yours'; end if;
  insert into public.charge_audit(charge_id, merchant_id, actor_id, actor_role, action, previous_status, new_status, metadata)
  values (v_charge.id, v_charge.merchant_id, auth.uid(),'merchant','REJECTED','CLAIMED','REJECTED', jsonb_build_object('reason',p_reason));
  return v_charge;
end; $$;

create or replace function public.report_dispute(p_charge_id text, p_customer_name text, p_reason text, p_description text default null, p_evidence_url text default null)
returns public.disputes language plpgsql security definer as $$
declare v_charge public.charges; v_dispute public.disputes;
begin
  select * into v_charge from public.charges where id=p_charge_id;
  if v_charge.id is null then raise exception 'Charge not found'; end if;
  insert into public.disputes(charge_id, merchant_id, customer_name, reason, description, evidence_url)
  values (p_charge_id, v_charge.merchant_id, p_customer_name, p_reason, p_description, p_evidence_url) returning * into v_dispute;
  if v_charge.status='CLAIMED' then
    update public.charges set status='DISPUTED' where id=p_charge_id;
    insert into public.charge_audit(charge_id, merchant_id, actor_role, action, previous_status, new_status) values (p_charge_id, v_charge.merchant_id,'customer','DISPUTED','CLAIMED','DISPUTED');
  end if;
  return v_dispute;
end; $$;

grant execute on function public.get_public_charge(text) to anon, authenticated;
grant execute on function public.claim_payment(text,text,text,timestamptz,text) to anon, authenticated;
grant execute on function public.report_dispute(text,text,text,text,text) to anon, authenticated;
grant execute on function public.reject_payment(text,text) to authenticated;
