'use client';

import React, { useState, useEffect, useRef } from 'react';
import { sendChatCompletion } from '@/lib/ai';

interface Product {
  id: string;
  name: string;
  price: number;
  costPrice: number;
  currentStock: number;
  unit: string;
  itemType: 'RAW' | 'MIX';
}

interface Customer {
  id: string;
  name: string;
  phone?: string;
  isSupplier: boolean;
}

interface VoiceOrderModalProps {
  isOpen: boolean;
  onClose: () => void;
  products: Product[];
  customers: Customer[];
  onApply: (result: {
    customer?: Customer;
    paidAmount?: number;
    items: Array<{ product: Product; quantity: number; overridePrice?: number }>;
  }) => void;
}

export default function VoiceOrderModal({
  isOpen,
  onClose,
  products,
  customers,
  onApply,
}: VoiceOrderModalProps) {
  const [isListening, setIsListening] = useState(false);
  const [recognizedText, setRecognizedText] = useState('');
  const [status, setStatus] = useState('Nhấn vào nút micrô bên dưới để bắt đầu nói đơn hàng...');
  const [loading, setLoading] = useState(false);
  
  // AI Parse Results
  const [aiResult, setAiResult] = useState<any>(null);
  const [matchedCustomer, setMatchedCustomer] = useState<Customer | undefined>(undefined);
  const [matchedItems, setMatchedItems] = useState<Array<{
    originalText: string;
    product?: Product;
    quantity: number;
    price?: number;
  }>>([]);

  const recognitionRef = useRef<any>(null);

  useEffect(() => {
    // Initialize Web Speech API
    if (typeof window !== 'undefined') {
      const SpeechRecognition = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
      if (SpeechRecognition) {
        const rec = new SpeechRecognition();
        rec.lang = 'vi-VN';
        rec.continuous = false;
        rec.interimResults = true;

        rec.onstart = () => {
          setIsListening(true);
          setStatus('Hệ thống đang nghe, hãy nói rõ sản phẩm và số lượng...');
        };

        rec.onresult = (event: any) => {
          const transcript = Array.from(event.results)
            .map((result: any) => result[0])
            .map((result: any) => result.transcript)
            .join('');
          setRecognizedText(transcript);
        };

        rec.onerror = (event: any) => {
          console.error('Speech recognition error:', event.error);
          setStatus(`Lỗi nhận dạng: ${event.error}. Vui lòng thử lại.`);
          setIsListening(false);
        };

        rec.onend = () => {
          setIsListening(false);
          setStatus('Đã ghi nhận giọng nói xong. Bạn có thể sửa văn bản hoặc bấm Gửi AI.');
        };

        recognitionRef.current = rec;
      }
    }
  }, []);

  const toggleListening = () => {
    if (!recognitionRef.current) {
      alert('Trình duyệt của bạn không hỗ trợ Web Speech API nhận diện giọng nói. Vui lòng gõ nội dung vào ô text.');
      return;
    }

    if (isListening) {
      recognitionRef.current.stop();
    } else {
      setRecognizedText('');
      setAiResult(null);
      setMatchedItems([]);
      setMatchedCustomer(undefined);
      try {
        recognitionRef.current.start();
      } catch (err) {
        console.error(err);
      }
    }
  };

  // Normalize string for fuzzy match
  const normalizeStr = (str: string): string => {
    return str
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[đĐ]/g, 'd')
      .trim();
  };

  // Find closest product based on name
  const findProduct = (name: string): Product | undefined => {
    const normName = normalizeStr(name);
    
    // 1. Exact match normalized
    let found = products.find(p => normalizeStr(p.name) === normName);
    if (found) return found;

    // 2. Contains match
    found = products.find(p => normalizeStr(p.name).includes(normName) || normName.includes(normalizeStr(p.name)));
    if (found) return found;

    return undefined;
  };

  // Find closest customer
  const findCustomer = (name: string): Customer | undefined => {
    const normName = normalizeStr(name);
    let found = customers.find(c => normalizeStr(c.name) === normName);
    if (found) return found;

    found = customers.find(c => normalizeStr(c.name).includes(normName) || normName.includes(normalizeStr(c.name)));
    if (found) return found;

    return undefined;
  };

  const handleProcessAI = async () => {
    if (!recognizedText.trim()) return;

    setLoading(true);
    setStatus('Đang gửi AI phân tích nội dung...');
    setAiResult(null);

    const productNames = products.map(p => p.name).join(' | ');
    const customerNames = customers.map(c => c.name).join(' | ');

    const prompt = `
Phân tích lệnh giọng nói tiếng Việt này và trả về đúng một JSON object theo schema sau (không thêm text giải thích ngoài JSON):
{
  "customer": "tên khách hàng (nếu có)",
  "paidAmount": số tiền khách trả (nếu có),
  "items": [
    {
      "action": "add",
      "item": "tên sản phẩm",
      "quantity": số lượng,
      "price": giá bán nếu có nói trong lệnh
    }
  ]
}

Danh sách sản phẩm hiện có của cửa hàng:
${productNames}

Danh sách khách hàng hiện có:
${customerNames}

Lệnh giọng nói cần phân tích:
"${recognizedText}"
`;

    try {
      const responseText = await sendChatCompletion(prompt);
      let jsonResult: any = null;
      
      // Clean JSON formatting if AI adds markdown fences
      const cleanJson = responseText.replace(/```json/g, '').replace(/```/g, '').trim();
      
      try {
        jsonResult = JSON.parse(cleanJson);
      } catch (err) {
        throw new Error('Dữ liệu AI trả về không đúng định dạng JSON: ' + responseText);
      }

      setAiResult(jsonResult);
      setStatus('Xử lý AI thành công! Vui lòng kiểm tra lại đơn hàng bên dưới.');

      // Map Customer
      if (jsonResult.customer) {
        setMatchedCustomer(findCustomer(jsonResult.customer));
      } else {
        setMatchedCustomer(undefined);
      }

      // Map Items
      if (Array.isArray(jsonResult.items)) {
        const mapped = jsonResult.items.map((it: any) => {
          const prod = findProduct(it.item);
          return {
            originalText: it.item,
            product: prod,
            quantity: Number(it.quantity || 1),
            price: it.price ? Number(it.price) : undefined
          };
        });
        setMatchedItems(mapped);
      }
    } catch (err: any) {
      console.error(err);
      setStatus(`Lỗi xử lý AI: ${err.message}`);
    } finally {
      setLoading(false);
    }
  };

  const handleItemProductChange = (index: number, productId: string) => {
    const prod = products.find(p => p.id === productId);
    setMatchedItems(
      matchedItems.map((item, idx) => (idx === index ? { ...item, product: prod } : item))
    );
  };

  const handleApplyOrder = () => {
    // Only apply valid matched items
    const validItems = matchedItems
      .filter(item => item.product !== undefined)
      .map(item => ({
        product: item.product!,
        quantity: item.quantity,
        overridePrice: item.price
      }));

    if (validItems.length === 0) {
      alert('Không có sản phẩm nào được khớp chính xác để thêm vào giỏ hàng.');
      return;
    }

    onApply({
      customer: matchedCustomer,
      paidAmount: aiResult?.paidAmount ? Number(aiResult.paidAmount) : undefined,
      items: validItems
    });
    
    onClose();
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs animate-fade-in">
      <div className="glass w-full max-w-2xl rounded-2xl border border-white/10 shadow-2xl p-6 relative flex flex-col max-h-[85vh] animate-fade-in-up">
        {/* Header */}
        <div className="flex justify-between items-center mb-4 pb-2 border-b border-slate-800">
          <h3 className="text-lg font-bold text-white flex items-center gap-2">
            <span>🎤</span> Lên đơn hàng bằng giọng nói (AI)
          </h3>
          <button onClick={onClose} className="text-slate-400 hover:text-white cursor-pointer">✕</button>
        </div>

        {/* Text prompt status */}
        <div className="p-3 bg-slate-950/40 rounded-xl border border-slate-800 mb-4 text-xs text-slate-300">
          💡 Mẫu nói: <span className="text-indigo-300">"Chị Lan mua 2 ly cà phê sữa đá, 1 ly trà đào cam sả"</span> hoặc <span className="text-indigo-300">"Tạo đơn cho Anh Hùng mua 3 lon coca giá 15000, khách trả 50000"</span>.
        </div>

        {/* Recorder Box */}
        <div className="space-y-4">
          <div className="flex flex-col items-center justify-center p-6 bg-slate-950/20 border border-white/5 rounded-2xl relative overflow-hidden group">
            {isListening && (
              <div className="absolute inset-0 bg-red-500/5 animate-pulse z-0 pointer-events-none"></div>
            )}
            
            <button
              onClick={toggleListening}
              className={`w-16 h-16 rounded-full flex items-center justify-center text-2xl transition-all cursor-pointer z-10 ${
                isListening
                  ? 'bg-red-500 text-white animate-bounce shadow-glow-red'
                  : 'bg-indigo-600 hover:bg-indigo-500 text-white shadow-glow'
              }`}
            >
              {isListening ? '⏹️' : '🎤'}
            </button>
            <p className="text-xs font-bold text-slate-400 uppercase tracking-widest mt-4 z-10">
              {isListening ? 'ĐANG GHI ÂM (CLICK ĐỂ DỪNG)...' : 'CLICK ĐỂ BẮT ĐẦU NÓI'}
            </p>
          </div>

          {/* Transcript input/edit */}
          <div>
            <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Văn bản nhận diện</label>
            <textarea
              className="input h-20 text-slate-200"
              placeholder="Văn bản nhận diện giọng nói sẽ hiển thị ở đây để bạn có thể chỉnh sửa lại trước khi gửi..."
              value={recognizedText}
              onChange={(e) => setRecognizedText(e.target.value)}
            />
          </div>

          <div className="flex justify-between items-center">
            <span className="text-xs font-semibold text-slate-400 italic">Trạng thái: {status}</span>
            <button
              onClick={handleProcessAI}
              disabled={loading || !recognizedText.trim()}
              className="btn btn-primary text-xs shadow-glow flex items-center gap-1 cursor-pointer disabled:opacity-50"
            >
              {loading && <span className="animate-spin text-[10px]">🌀</span>}
              🧠 Gửi AI xử lý
            </button>
          </div>
        </div>

        {/* AI Processing Preview */}
        {matchedItems.length > 0 && (
          <div className="flex-1 overflow-y-auto mt-6 space-y-4 pt-4 border-t border-slate-800">
            <h4 className="font-bold text-indigo-300 text-xs uppercase tracking-wider">Xác nhận đơn hàng AI</h4>

            {/* Matched Customer */}
            <div className="flex items-center gap-3 bg-slate-950/30 p-3 rounded-xl border border-white/5 text-xs">
              <span className="text-sm">👤</span>
              <div className="flex-1">
                <p className="text-slate-400">Khách hàng được nhận diện:</p>
                {matchedCustomer ? (
                  <p className="font-bold text-white">{matchedCustomer.name} (Khớp 100%)</p>
                ) : aiResult?.customer ? (
                  <p className="text-rose-400 italic">Tìm kiếm "{aiResult.customer}" không khớp. Sẽ tạo dạng Khách vãng lai.</p>
                ) : (
                  <p className="text-slate-300">Khách vãng lai</p>
                )}
              </div>
              {aiResult?.paidAmount !== undefined && (
                <div className="text-right">
                  <p className="text-slate-400">Số tiền khách trả:</p>
                  <p className="font-bold text-emerald-400">{new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(aiResult.paidAmount)}</p>
                </div>
              )}
            </div>

            {/* Matched Products List */}
            <div className="space-y-2">
              {matchedItems.map((item, index) => (
                <div key={index} className="flex flex-col sm:flex-row sm:items-center justify-between p-3 bg-slate-950/20 border border-white/5 rounded-xl gap-3">
                  <div className="flex-1 text-xs">
                    <p className="text-slate-400">Từ lệnh: <span className="font-mono text-slate-200 font-semibold">"{item.originalText}"</span> (Số lượng: {item.quantity})</p>
                    {item.product ? (
                      <p className="text-emerald-400 font-bold mt-1">✓ Đã khớp: {item.product.name} ({new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(item.price || item.product.price)})</p>
                    ) : (
                      <p className="text-rose-400 font-bold mt-1">⚠️ Chưa khớp sản phẩm nào</p>
                    )}
                  </div>

                  {/* Manual picker if not matched */}
                  <div className="shrink-0">
                    <select
                      className="input text-xs py-1 px-2 h-auto w-48 bg-slate-900 border-white/10"
                      value={item.product?.id || ''}
                      onChange={(e) => handleItemProductChange(index, e.target.value)}
                    >
                      <option value="">-- Chọn sản phẩm khớp --</option>
                      {products.map(p => (
                        <option key={p.id} value={p.id}>{p.name} ({new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(p.price)})</option>
                      ))}
                    </select>
                  </div>
                </div>
              ))}
            </div>

            <div className="flex justify-end gap-3 pt-4 border-t border-slate-800">
              <button
                onClick={onClose}
                className="btn btn-secondary text-xs cursor-pointer"
              >
                Hủy
              </button>
              <button
                onClick={handleApplyOrder}
                className="btn btn-primary text-xs shadow-glow cursor-pointer"
              >
                📥 Áp dụng vào giỏ hàng
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
