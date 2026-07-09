import { NextResponse } from 'next/server';
import { callFormRpc } from '@/lib/rpc/server-rpc';

export async function POST(request) {
  const payload = await request.json();
  const data = await callFormRpc('forms_request_upload_ticket_v3', payload);
  return NextResponse.json(data);
}
