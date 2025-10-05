// Centralized type definitions

// Re-export all types
export * from "./deploy";

// Monorail Pathfinder API types

export interface Split {
  fee: string;
  percentage: string;
  price_impact: string;
  protocol: string;
}

export interface Route {
  from: string;
  from_symbol: string;
  to: string;
  to_symbol: string;
  weighted_price_impact: string;
  splits: Split[];
}

export interface ProtocolFees {
  fee_share_amount: string;
  fee_share_bps: number;
  protocol_amount: string;
  protocol_bps: number;
}

export interface GeneratedTransaction {
  data: string;
  to: string;
  value: string;
}

export interface QuoteResponse {
  block: number;
  compound_impact: string;
  fees: ProtocolFees;
  from: string;
  gas_estimate: number;
  generated_at: number;
  hops: number;
  input: string;
  input_formatted: string;
  min_output: string;
  min_output_formatted: string;
  optimisation: string;
  output: string;
  output_formatted: string;
  quote_id: string;
  referrer_id: string;
  routes: Route[][];
  to: string;
  transaction?: GeneratedTransaction;
}

export interface ErrorResponse {
  message: string;
}

export interface QuoteParams {
  source: string;
  from: string;
  to: string;
  amount: string;
  sender?: string;
  max_slippage?: number;
  deadline?: number;
  destination?: string;
}
