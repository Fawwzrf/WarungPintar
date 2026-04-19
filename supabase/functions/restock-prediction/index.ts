// supabase/functions/restock-prediction/index.ts
// Edge Function: AI Restock Prediction using Google Gemini
// PRD §4.5.1 — Prediksi Restock Cerdas

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
    if (!GEMINI_API_KEY) throw new Error("GEMINI_API_KEY not set");

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Get store_id from request
    const { store_id } = await req.json();
    if (!store_id) throw new Error("store_id is required");

    // Fetch sales data (30 days)
    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    const { data: salesData, error: salesError } = await supabase
      .from("sales_log")
      .select("product_id, quantity, created_at, products(name, stock, min_stock, unit, selling_price)")
      .eq("store_id", store_id)
      .gte("created_at", thirtyDaysAgo)
      .order("created_at", { ascending: false });

    if (salesError) throw salesError;

    // Also fetch products with low stock
    const { data: lowStockProducts } = await supabase
      .from("products")
      .select("id, name, stock, min_stock, unit, selling_price, cost_price")
      .eq("store_id", store_id)
      .eq("is_active", true)
      .order("stock", { ascending: true })
      .limit(20);

    // Build context for Gemini
    const salesSummary = salesData?.reduce((acc: Record<string, any>, sale: any) => {
      const name = sale.products?.name || "Unknown";
      if (!acc[name]) {
        acc[name] = {
          name,
          totalSold: 0,
          currentStock: sale.products?.stock || 0,
          minStock: sale.products?.min_stock || 5,
          unit: sale.products?.unit || "pcs",
          price: sale.products?.selling_price || 0,
        };
      }
      acc[name].totalSold += sale.quantity;
      return acc;
    }, {});

    const prompt = `Kamu adalah asisten AI untuk aplikasi manajemen toko "WarungPintar". 
Analisis data penjualan 30 hari terakhir dan stok saat ini, lalu berikan rekomendasi restock.

DATA PENJUALAN 30 HARI:
${JSON.stringify(Object.values(salesSummary || {}), null, 2)}

PRODUK STOK RENDAH:
${JSON.stringify(lowStockProducts || [], null, 2)}

Berikan response dalam format JSON SAJA (tanpa markdown) dengan struktur:
{
  "recommendations": [
    {
      "product_name": "nama produk",
      "current_stock": angka,
      "daily_avg_sales": angka,
      "days_until_empty": angka,
      "suggested_restock_qty": angka,
      "urgency": "critical" | "soon" | "normal",
      "reason": "penjelasan singkat dalam Bahasa Indonesia"
    }
  ],
  "summary": "ringkasan tren penjualan dalam 2-3 kalimat Bahasa Indonesia",
  "top_selling": "nama produk terlaris"
}

Maksimal 5 rekomendasi, urutkan dari yang paling urgent.`;

    // Call Gemini API
    const geminiRes = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${GEMINI_API_KEY}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: { temperature: 0.3, maxOutputTokens: 1024 },
        }),
      }
    );

    if (!geminiRes.ok) {
      const errText = await geminiRes.text();
      throw new Error(`Gemini API error: ${geminiRes.status} ${errText}`);
    }

    const geminiData = await geminiRes.json();
    const aiText = geminiData.candidates?.[0]?.content?.parts?.[0]?.text || "{}";
    
    // Parse JSON from AI response (strip markdown fences if present)
    const cleanJson = aiText.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
    const aiResult = JSON.parse(cleanJson);

    return new Response(JSON.stringify(aiResult), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message, recommendations: [], summary: "Gagal menganalisis data." }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
