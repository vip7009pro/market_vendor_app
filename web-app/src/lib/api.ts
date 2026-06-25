const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3007';

interface ApiOptions {
  method?: string;
  body?: any;
  headers?: Record<string, string>;
}

class ApiClient {
  private baseUrl: string;

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl;
  }

  private getToken(): string | null {
    if (typeof window === 'undefined') return null;
    return localStorage.getItem('token');
  }

  async fetch<T = any>(endpoint: string, options: ApiOptions = {}): Promise<T> {
    const { method = 'GET', body, headers = {} } = options;
    const token = this.getToken();

    const config: RequestInit = {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(token && { Authorization: `Bearer ${token}` }),
        ...headers,
      },
    };

    if (body) {
      config.body = JSON.stringify(body);
    }

    const res = await fetch(`${this.baseUrl}${endpoint}`, config);

    if (!res.ok) {
      const error = await res.json().catch(() => ({ error: 'Request failed' }));
      throw new Error(error.error || `HTTP ${res.status}`);
    }

    return res.json();
  }

  // Auth
  async register(email: string, password: string, name: string) {
    return this.fetch('/auth/register', { method: 'POST', body: { email, password, name } });
  }

  async login(email: string, password: string) {
    return this.fetch('/auth/login', { method: 'POST', body: { email, password } });
  }

  async loginGoogle(idToken: string) {
    return this.fetch('/auth/google', { method: 'POST', body: { idToken } });
  }

  async getMe() {
    return this.fetch('/auth/me');
  }

  // Products
  async getProducts(params?: Record<string, string>) {
    const qs = params ? '?' + new URLSearchParams(params).toString() : '';
    return this.fetch(`/api/products${qs}`);
  }

  async createProduct(data: any) {
    return this.fetch('/api/products', { method: 'POST', body: data });
  }

  async updateProduct(id: string, data: any) {
    return this.fetch(`/api/products/${id}`, { method: 'PUT', body: data });
  }

  async deleteProduct(id: string) {
    return this.fetch(`/api/products/${id}`, { method: 'DELETE' });
  }

  // Sales
  async getSales(params?: Record<string, string>) {
    const qs = params ? '?' + new URLSearchParams(params).toString() : '';
    return this.fetch(`/api/sales${qs}`);
  }

  async createSale(data: any) {
    return this.fetch('/api/sales', { method: 'POST', body: data });
  }

  async deleteSale(id: string) {
    return this.fetch(`/api/sales/${id}`, { method: 'DELETE' });
  }

  // Customers
  async getCustomers(params?: Record<string, string>) {
    const qs = params ? '?' + new URLSearchParams(params).toString() : '';
    return this.fetch(`/api/customers${qs}`);
  }

  async createCustomer(data: any) {
    return this.fetch('/api/customers', { method: 'POST', body: data });
  }

  // Debts
  async getDebts(params?: Record<string, string>) {
    const qs = params ? '?' + new URLSearchParams(params).toString() : '';
    return this.fetch(`/api/debts${qs}`);
  }

  async addDebtPayment(debtId: string, data: any) {
    return this.fetch(`/api/debts/${debtId}/payments`, { method: 'POST', body: data });
  }

  // Reports
  async getDashboard(params?: Record<string, string>) {
    const qs = params ? '?' + new URLSearchParams(params).toString() : '';
    return this.fetch(`/api/reports/dashboard${qs}`);
  }

  // Expenses
  async getExpenses(params?: Record<string, string>) {
    const qs = params ? '?' + new URLSearchParams(params).toString() : '';
    return this.fetch(`/api/expenses${qs}`);
  }

  async createExpense(data: any) {
    return this.fetch('/api/expenses', { method: 'POST', body: data });
  }
}

export const api = new ApiClient(API_URL);
export default api;
