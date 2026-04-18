import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { store_id } = await req.json();
    if (!store_id) {
      throw new Error("store_id is required");
    }

    // Initialize Supabase Client
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const supabaseKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
    const supabase = createClient(supabaseUrl, supabaseKey, {
      global: { headers: { Authorization: req.headers.get('Authorization')! } }
    });

    // 1. Fetch active products for the store
    const { data: products, error: productsErr } = await supabase
      .from('products')
      .select('id, name, stock')
      .eq('store_id', store_id)
      .eq('is_active', true);

    if (productsErr || !products) throw productsErr;

    const productMap = new Map();
    products.forEach(p => {
      productMap.set(p.id, {
        product_id: p.id,
        product_name: p.name,
        current_stock: p.stock,
        total_sold_30d: 0,
      });
    });

    // 2. Fetch sales_log for the last 30 days
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    
    // We get sales_log by joining with products through Supabase PostgREST matching
    const { data: sales, error: salesErr } = await supabase
      .from('sales_log')
      .select('product_id, quantity, products!inner(store_id)')
      .eq('products.store_id', store_id)
      .gte('created_at', thirtyDaysAgo.toISOString());

    if (salesErr) throw salesErr;

    // Aggregate sales
    if (sales) {
      sales.forEach((sale: any) => {
        if (productMap.has(sale.product_id)) {
          productMap.get(sale.product_id).total_sold_30d += sale.quantity;
        }
      });
    }

    // Also include debt_items (kasbon) as sales
    const { data: debts, error: debtsErr } = await supabase
      .from('debt_items')
      .select('product_id, quantity, products!inner(store_id)')
      .eq('products.store_id', store_id)
      .gte('created_at', thirtyDaysAgo.toISOString());

    if (!debtsErr && debts) {
      debts.forEach((debt: any) => {
        if (productMap.has(debt.product_id)) {
          productMap.get(debt.product_id).total_sold_30d += debt.quantity;
        }
      });
    }

    // 3. Calculate metrics and project stockout
    const analysis = Array.from(productMap.values()).map(p => {
      const avg_daily_sales = p.total_sold_30d / 30;
      const days_until_empty = avg_daily_sales > 0 
        ? Math.max(0, Math.floor(p.current_stock / avg_daily_sales))
        : 9999; // Represents infinity/no sales
      
      const recommended_qty = Math.ceil(avg_daily_sales * 14); // Recommend 2 weeks stock

      return {
        ...p,
        avg_daily_sales: Number(avg_daily_sales.toFixed(2)),
        days_until_empty,
        recommended_qty
      };
    });

    // 4. Rank by urgency (lowest days_until_empty first)
    analysis.sort((a, b) => a.days_until_empty - b.days_until_empty);
    
    // Get Top 5 that have active sales
    const topProducts = analysis.filter(p => p.avg_daily_sales > 0).slice(0, 5);

    // 5. Call Gemini API for summary (if API key is available)
    let ai_summary = "";
    const geminiKey = Deno.env.get('GEMINI_API_KEY');
    
    if (geminiKey && topProducts.length > 0) {
      try {
        const promptParams = topProducts.map(p => 
          `- ${p.product_name}: Sisa stok ${p.current_stock}, habis dalam ${p.days_until_empty} hari. (Rata-rata terjual ${p.avg_daily_sales}/hari)`
        ).join('\n');

        const prompt = `Anda adalah asisten cerdas untuk pemilik toko kelontong (Warung) di Indonesia. Tugas Anda adalah menganalisa data stok dan memberikan rekomendasi restock yang praktis.
KRITERIA OUTPUT:
- Gunakan Bahasa Indonesia yang ramah (semi-formal/santai).
- Maksimal 3 kalimat pendek.
- Sebutkan produk yang paling kritis, perkiraan hari habis, dan jumlah restock yang disarankan.

DATA INPUT:
${promptParams}
`.trim();

        const geminiRes = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${geminiKey}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            contents: [{ parts: [{ text: prompt }] }],
            generationConfig: { temperature: 0.3 }
          })
        });

        if (geminiRes.ok) {
          const geminiData = await geminiRes.json();
          ai_summary = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text?.trim() ?? "";
        }
      } catch (geminiError) {
        console.error("Gemini API Error:", geminiError);
        // Fallback to empty string if API fails
      }
    } else if (topProducts.length === 0) {
      ai_summary = "Belum ada cukup data penjualan untuk membuat prediksi stok.";
    }

    // 6. Return response
    return new Response(
      JSON.stringify({
        top_products: topProducts,
        ai_summary: ai_summary,
        timestamp: new Date().toISOString()
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (err: any) {
    console.error("Function Error:", err.message);
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
