import axios, { AxiosInstance } from "axios";
import { QuoteParams, QuoteResponse, ErrorResponse } from "../types";

/**
 * Monorail Pathfinder API Client
 */
export class MonorailClient {
  private client: AxiosInstance;
  private readonly baseUrl: string;
  private readonly version: string;

  /**
   * Create a new MonorailClient instance
   * @param appId Your Monorail application ID
   * @param baseUrl The API base URL (default: 'https://testnet-pathfinder.monorail.xyz')
   * @param version The API version (default: 'v4')
   */
  constructor(
    private readonly appId: string,
    baseUrl: string = "https://testnet-pathfinder.monorail.xyz",
    version: string = "v4"
  ) {
    this.baseUrl = baseUrl;
    this.version = version;
    this.client = axios.create({
      baseURL: `${this.baseUrl}/${this.version}`,
    });
  }

  /**
   * Get a quote for swapping tokens
   * @param params Quote parameters
   * @returns A quote response
   */
  public async getQuote(
    params: Omit<QuoteParams, "source">
  ): Promise<QuoteResponse> {
    try {
      // Add the app ID to the parameters
      const fullParams = {
        ...params,
        source: this.appId,
      };

      const response = await this.client.get<QuoteResponse>("/quote", {
        params: fullParams,
      });

      return response.data;
    } catch (error) {
      if (axios.isAxiosError(error) && error.response) {
        const errorData = error.response.data as ErrorResponse;
        throw new Error(
          `Monorail API Error: ${errorData.message || error.message}`
        );
      }
      throw error;
    }
  }
}
