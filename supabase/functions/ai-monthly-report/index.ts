// supabase/functions/ai-monthly-report/index.ts
// Edge Function: AI Monthly Text Report using Google Gemini
// PRD §4.5.2 — Laporan Tren Teks Otomatis

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

    // Get parameters from request
    const { store_id, start_date, end_date } = await req.json();
    if (!store_id) throw new Error("store_id is required");

    const startDate = start_date || new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    const endDate = end_date || new Date().toISOString();

    // 1. Fetch sales data for the period
    const { data: salesData, error: salesError } = await supabase
      .from("sales_log")
      .select("product_id, quantity, total_price, created_at, products(name, cost_price)")
      .eq("store_id", store_id)
      .gte("created_at", startDate)
      .lte("created_at", endDate);

    if (salesError) throw salesError;

    // 2. Fetch active debts data
    const { data: debtsData, error: debtsError } = await supabase
      .from("debts")
      .select("id, total_amount, paid_amount, remaining_amount, status")
      .eq("store_id", store_id)
      .neq("status", "paid");

    if (debtsError) throw debtsError;

    // Process Sales Data
    let totalRevenue = 0;
    let totalProfit = 0;
    let totalItemsSold = 0;
    const productSales: Record<string, { qty: number; revenue: number; profit: number }> = {};

    if (salesData && salesData.length > 0) {
      salesData.forEach((sale: any) => {
        const qty = sale.quantity || 0;
        const revenue = sale.total_price || 0;
        const name = sale.products?.name || "Unknown Product";
        const costPrice = sale.products?.cost_price || 0;
        const profit = revenue - (costPrice * qty);

        totalRevenue += revenue;
        totalProfit += profit;
        totalItemsSold += qty;

        if (!productSales[name]) {
          productSales[name] = { qty: 0, revenue: 0, profit: 0 };
        }
        productSales[name].qty += qty;
        productSales[name].revenue += revenue;
        productSales[name].profit += profit;
      });
    }

    // Get Top 5 Selling Products by Quantity
    const topProducts = Object.entries(productSales)
      .sort((a, b) => b[1].qty - a[1].qty)
      .slice(0, 5)
      .map(([name, data]) => ({ name, qty: data.qty, profit: data.profit }));

    // Process Debts Data
    let totalActiveDebt = 0;
    let debtCount = 0;
    if (debtsData && debtsData.length > 0) {
      debtCount = debtsData.length;
      debtsData.forEach((debt: any) => {
        totalActiveDebt += debt.remaining_amount || 0;
      });
    }

    // Build context for Gemini
    const prompt = `Kamu adalah AI Penasihat Bisnis (Business Advisor) yang ramah, profesional, dan pintar untuk aplikasi "WarungPintar".
Tugasmu adalah menganalisis data operasional toko berikut ini dan menghasilkan "Laporan Tren Teks Otomatis" untuk pemilik toko.

PERIODE DATA: ${startDate.split('T')[0]} sampai ${endDate.split('T')[0]}

RINGKASAN PENJUALAN:
- Total Pendapatan Kotor: Rp ${totalRevenue.toLocaleString("id-ID")}
- Estimasi Keuntungan (Profit): Rp ${totalProfit.toLocaleString("id-ID")}
- Total Barang Terjual: ${totalItemsSold} item

5 PRODUK PALING LAKU:
${topProducts.length > 0 ? topProducts.map((p, i) => `${i+1}. ${p.name} (Terjual: ${p.qty} item, Profit: Rp ${p.profit.toLocaleString("id-ID")})`).join('\n') : '- Belum ada penjualan'}

RINGKASAN PIUTANG (KASBON AKTIF):
- Jumlah Transaksi Kasbon yang Belum Lunas: ${debtCount}
- Total Uang yang Masih Nyangkut di Pelanggan (Piutang Aktif): Rp ${totalActiveDebt.toLocaleString("id-ID")}

INSTRUKSI:
Buatkan laporan singkat, jelas, dan menarik dalam Bahasa Indonesia.
Gunakan format Markdown agar rapi (boleh pakai bold, bullet points, dan emoji yang relevan).
Laporan harus terdiri dari:
1. Sapaan semangat & ringkasan singkat kinerja (1 paragraf).
2. Poin-poin pencapaian utama (produk laris, profit, dll).
3. "Perhatian / Catatan Bisnis" (Misalnya jika kasbon terlalu besar, ingatkan untuk menagih. Atau jika jualan sepi, beri semangat).
4. Satu "Saran Cerdas AI" untuk meningkatkan keuntungan bulan depan.

PENTING:
- Jangan memberikan saran yang tidak masuk akal untuk warung kecil/toko kelontong.
- Jika data penjualan nol/kosong, berikan pesan motivasi agar semangat berjualan.
- Jangan gunakan markdown code blocks \`\`\`markdown, langsung berikan teks format markdown-nya saja.`;

    // Call Gemini API
    const geminiRes = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${GEMINI_API_KEY}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: { temperature: 0.5, maxOutputTokens: 1024 },
        }),
      }
    );

    if (!geminiRes.ok) {
      const errText = await geminiRes.text();
      throw new Error(`Gemini API error: ${geminiRes.status} ${errText}`);
    }

    const geminiData = await geminiRes.json();
    let aiText = geminiData.candidates?.[0]?.content?.parts?.[0]?.text || "Maaf, AI gagal memproses laporan.";
    
    // Clean potential markdown fences around the response if Gemini adds them
    if (aiText.startsWith("```markdown")) {
        aiText = aiText.replace(/```markdown\n?/g, "").replace(/```\n?/g, "").trim();
    } else if (aiText.startsWith("```")) {
        aiText = aiText.replace(/```\n?/g, "").replace(/```\n?/g, "").trim();
    }

    return new Response(JSON.stringify({ report: aiText }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message, report: "Gagal menghasilkan laporan AI. Silakan coba lagi nanti." }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
