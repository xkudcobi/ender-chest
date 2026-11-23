// Ender Chest piksel arayüz kiti: özgün "End" temalı palet, kabartmalı piksel kontroller,
// koyu pencere çerçevesi ve piksel font yönetimi. Windows Forms + GDI+ ile, C# 5 uyumlu.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class Px {
    public static Color H(string h) { return ColorTranslator.FromHtml(h); }
    public static readonly Color Void0 = H("#0b0913"), Void1 = H("#130f20"), Void2 = H("#1d1631"),
        Row = H("#151125"), RowAlt = H("#19142b"), Select = H("#123d39"),
        Face = H("#2b2246"), FaceHot = H("#3a2e5e"), Hi = H("#5b4a8c"), Lo = H("#07050e"), Edge = H("#000000"),
        TealFace = H("#1b6b62"), TealHot = H("#23887b"), TealHi = H("#5ae6d4"), TealLo = H("#0b3833"), Teal = H("#36d6c3"),
        Purple = H("#b07cff"), Gold = H("#f5c542"), Ink = H("#efe9ff"), Dim = H("#a197c8"), Faint = H("#665c8c"),
        Ok = H("#72e8a4"), Warn = H("#f5c542"), Bad = H("#ff6b7a"), Shadow = H("#05030a");

    // ---------- Fontlar ----------
    static PrivateFontCollection pfc;
    static FontFamily display, body;
    static readonly Dictionary<string, Font> cache = new Dictionary<string, Font>();
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
    static extern int AddFontResourceEx(string file, uint flags, IntPtr reserved);

    public static void LoadFonts(string dir) {
        pfc = new PrivateFontCollection();
        foreach (string n in new string[] { "PressStart2P-Regular.ttf", "PixelifySans-Regular.ttf", "PixelifySans-Bold.ttf" }) {
            string p = Path.Combine(dir, n);
            if (!File.Exists(p)) continue;
            try { pfc.AddFontFile(p); AddFontResourceEx(p, 0x10, IntPtr.Zero); } catch { }
        }
        foreach (FontFamily f in pfc.Families) {
            if (f.Name == "Press Start 2P") display = f;
            else if (f.Name == "Pixelify Sans") body = f;
        }
    }
    public static bool HasPixelFonts { get { return display != null && body != null; } }
    public static Font Display(float px) {
        string k = "D|" + px;
        Font f;
        if (!cache.TryGetValue(k, out f)) {
            f = display != null ? new Font(display, px, FontStyle.Regular, GraphicsUnit.Pixel) : new Font("Consolas", px, FontStyle.Bold, GraphicsUnit.Pixel);
            cache[k] = f;
        }
        return f;
    }
    public static Font Body(float px) { return Body(px, false); }
    public static Font Body(float px, bool bold) {
        string k = "B|" + px + "|" + bold;
        Font f;
        if (!cache.TryGetValue(k, out f)) {
            FontStyle st = bold ? FontStyle.Bold : FontStyle.Regular;
            f = body != null ? new Font(body, px, st, GraphicsUnit.Pixel) : new Font("Segoe UI", px * 0.8f, st, GraphicsUnit.Pixel);
            cache[k] = f;
        }
        return f;
    }
    static bool IsPixel(Font f) {
        string n = f.FontFamily.Name;
        return (display != null && n == display.Name) || (body != null && n == body.Name);
    }
    static Font Sys(string fam, float px, bool bold) {
        string k = "S|" + fam + "|" + px + "|" + bold;
        Font f;
        if (!cache.TryGetValue(k, out f)) { f = new Font(fam, px, bold ? FontStyle.Bold : FontStyle.Regular, GraphicsUnit.Pixel); cache[k] = f; }
        return f;
    }
    // Piksel fontta bulunmayan yazılar (Japonca, Çince, Korece, Arapça...) için sistem fontuna geçer.
    public static Font FontFor(string s, Font f) {
        if (string.IsNullOrEmpty(s) || !IsPixel(f)) return f;
        string fb = null;
        foreach (char c in s) {
            if (c <= 0x052F) continue;
            if (c >= 0x2000 && c <= 0x206F) continue;
            if (c >= 0x20A0 && c <= 0x20CF) continue;
            if (c >= 0x3040 && c <= 0x30FF) { fb = "Yu Gothic UI"; break; }
            if (c >= 0xAC00 && c <= 0xD7AF) { fb = "Malgun Gothic"; break; }
            if ((c >= 0x4E00 && c <= 0x9FFF) || (c >= 0x3000 && c <= 0x303F) || (c >= 0xFF00 && c <= 0xFFEF)) { if (fb == null) fb = "Microsoft YaHei UI"; continue; }
            if (fb == null) fb = "Segoe UI";
        }
        if (fb == null) return f;
        return Sys(fb, (float)Math.Max(12, Math.Round(f.Size * 0.86f)), f.Bold);
    }
    // Pixelify Sans'ta eksik iki Kiril büyük harfi görsel eşleriyle çizilir (О→O, П→Π).
    public static string Glyphs(string s, Font f) {
        if (string.IsNullOrEmpty(s) || body == null || f.FontFamily.Name != body.Name) return s;
        if (s.IndexOf('О') < 0 && s.IndexOf('П') < 0) return s;
        return s.Replace('О', 'O').Replace('П', 'Π');
    }
    static void Hint(Graphics g, Font f) {
        g.TextRenderingHint = IsPixel(f) ? TextRenderingHint.SingleBitPerPixelGridFit : TextRenderingHint.AntiAliasGridFit;
    }

    // ---------- Çizim ----------
    public static void Fill(Graphics g, Color c, int x, int y, int w, int h) {
        if (w <= 0 || h <= 0) return;
        using (SolidBrush b = new SolidBrush(c)) g.FillRectangle(b, x, y, w, h);
    }
    public static void Text(Graphics g, string s, Font f, Color c, Rectangle r, StringAlignment h, StringAlignment v, bool shadow, bool ellipsis) {
        if (string.IsNullOrEmpty(s)) return;
        Font use = FontFor(s, f);
        s = Glyphs(s, use);
        Hint(g, use);
        using (StringFormat sf = new StringFormat()) {
            sf.Alignment = h; sf.LineAlignment = v;
            if (ellipsis) { sf.Trimming = StringTrimming.EllipsisCharacter; sf.FormatFlags |= StringFormatFlags.NoWrap; }
            if (shadow) {
                int o = use.Size >= 20 ? 2 : 1;
                using (SolidBrush b = new SolidBrush(Shadow)) g.DrawString(s, use, b, new RectangleF(r.X + o, r.Y + o, r.Width, r.Height), sf);
            }
            using (SolidBrush b = new SolidBrush(c)) g.DrawString(s, use, b, r, sf);
        }
    }
    public static Size Measure(string s, Font f, int width) {
        if (string.IsNullOrEmpty(s)) return new Size(0, 0);
        using (Bitmap bmp = new Bitmap(1, 1))
        using (Graphics g = Graphics.FromImage(bmp)) {
            Font use = FontFor(s, f);
            s = Glyphs(s, use);
            Hint(g, use);
            SizeF z = g.MeasureString(s, use, width);
            return new Size((int)Math.Ceiling(z.Width), (int)Math.Ceiling(z.Height));
        }
    }
    // Kabartmalı blok: 2 px siyah dış hat, içte açık üst-sol / koyu alt-sağ kenar (inset'te tersi).
    public static void Bevel(Graphics g, Rectangle r, Color face, Color hi, Color lo, bool inset, int px) {
        Fill(g, Edge, r.X, r.Y, r.Width, r.Height);
        Rectangle i = Rectangle.Inflate(r, -2, -2);
        Fill(g, face, i.X, i.Y, i.Width, i.Height);
        Color tl = inset ? lo : hi, br = inset ? hi : lo;
        Fill(g, tl, i.X, i.Y, i.Width, px); Fill(g, tl, i.X, i.Y, px, i.Height);
        Fill(g, br, i.X, i.Bottom - px, i.Width, px); Fill(g, br, i.Right - px, i.Y, px, i.Height);
    }
    public static void Slot(Graphics g, Rectangle r) { Bevel(g, r, Void1, Hi, Lo, true, 3); }
    public static void Plate(Graphics g, Rectangle r) { Bevel(g, r, Void2, Hi, Lo, false, 3); }
    // Başlık şeridi: koyu, altında turkuaz-mor piksel çizgi.
    public static void Banner(Graphics g, int w, int h) {
        using (SolidBrush b = new SolidBrush(Color.FromArgb(185, Void1))) g.FillRectangle(b, 0, 0, w, h);
        Fill(g, Edge, 0, h - 6, w, 2);
        for (int x = 0; x < w; x += 8) Fill(g, ((x / 8) % 5 == 0) ? Purple : (((x / 8) % 2 == 0) ? Teal : TealFace), x, h - 4, 8, 2);
        Fill(g, Edge, 0, h - 2, w, 2);
    }

    // Özgün 16x16 sandık çizimi (uygulama ikonu ile aynı).
    static readonly string[] Art = {
        "................", "..............v.", ".v..............", "..############..",
        ".#LLLLLLLLLLLL#.", ".#LTTTTTTTTTTL#.", ".#TTTTTTTTTTTT#.", ".######GG######.",
        ".#BBBBBGGBBBBB#.", ".#BddddkkddddB#.", ".#BddddddddddB#.", ".#BddddddddddB#.",
        ".#BddddddddddB#.", ".#BBBBBBBBBBBB#.", ".##############.", "................" };
    static Color ArtColor(char c) {
        switch (c) {
            case '#': return H("#0d0b14"); case 'L': return H("#6fe3d6"); case 'T': return H("#2fa39a");
            case 'G': return H("#f5c542"); case 'k': return H("#b8862b"); case 'B': return H("#1d4744");
            case 'd': return H("#143533"); case 'v': return H("#c77dff");
        }
        return Color.Empty;
    }
    public static void Chest(Graphics g, int x, int y, int scale) {
        for (int r = 0; r < 16; r++)
            for (int c = 0; c < 16; c++) {
                char ch = Art[r][c];
                if (ch == '.') continue;
                Fill(g, ArtColor(ch), x + c * scale, y + r * scale, scale, scale);
            }
    }
    // Döşenebilir "boşluk" dokusu: rastgele koyu pikseller ve seyrek turkuaz/mor yıldızlar.
    public static Bitmap Texture(int w, int h, int scale, int seed) {
        Random rnd = new Random(seed);
        Bitmap bmp = new Bitmap(w * scale, h * scale);
        using (Graphics g = Graphics.FromImage(bmp)) {
            g.Clear(Void0);
            Color a = H("#0f0b1a"), b = H("#140f22"), c = H("#1a142d"), s1 = H("#3d2b70"), s2 = H("#1d6159");
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++) {
                    double v = rnd.NextDouble();
                    Color col;
                    if (v < 0.50) continue;
                    else if (v < 0.78) col = a;
                    else if (v < 0.94) col = b;
                    else if (v < 0.993) col = c;
                    else col = rnd.Next(3) == 0 ? s2 : s1;
                    Fill(g, col, x * scale, y * scale, scale, scale);
                }
        }
        return bmp;
    }
    static Bitmap sharedTexture;
    public static Bitmap SharedTexture { get { if (sharedTexture == null) sharedTexture = Texture(64, 64, 4, 1977); return sharedTexture; } }

    // ---------- Windows koyu çerçeve ----------
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);
    [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] static extern int SetWindowTheme(IntPtr h, string app, string id);
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
    static int Ref(Color c) { return c.R | (c.G << 8) | (c.B << 16); }
    public static void DarkTitle(Form f) {
        EventHandler apply = delegate(object s, EventArgs e) {
            try {
                IntPtr h = f.Handle;
                int on = 1; DwmSetWindowAttribute(h, 20, ref on, 4);
                int cap = Ref(Void1); DwmSetWindowAttribute(h, 35, ref cap, 4);
                int txt = Ref(Ink); DwmSetWindowAttribute(h, 36, ref txt, 4);
                int bor = Ref(Hi); DwmSetWindowAttribute(h, 34, ref bor, 4);
            } catch { }
        };
        if (f.IsHandleCreated) apply(f, EventArgs.Empty); else f.HandleCreated += apply;
    }
    public static void DarkScroll(Control c) { try { SetWindowTheme(c.Handle, "DarkMode_Explorer", null); } catch { } }
    // Şeffaflık yerine: pencere dokusunu kontrolün konumuna hizalayıp kendisi çizer (titreşim ve hayalet yok).
    public static void Backdrop(Graphics g, Control c) {
        using (TextureBrush tb = new TextureBrush(SharedTexture)) {
            tb.TranslateTransform(-c.Left, -c.Top);
            g.FillRectangle(tb, c.ClientRectangle);
        }
    }
    public static void DarkHeader(ListView lv) {
        try {
            IntPtr hdr = SendMessage(lv.Handle, 0x101F, IntPtr.Zero, IntPtr.Zero);
            if (hdr != IntPtr.Zero) SetWindowTheme(hdr, "DarkMode_ItemsView", null);
        } catch { }
    }
}

public class PixelForm : Form {
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    // Gizli başlatılan süreçlerde Windows ilk pencereyi gizli/küçük açar; ikinci çağrı normal gösterir.
    protected override void OnShown(EventArgs e) {
        ShowWindow(Handle, WindowState == FormWindowState.Minimized ? 9 : 5);
        Activate();
        base.OnShown(e);
    }
    public PixelForm() {
        DoubleBuffered = true;
        AutoScaleMode = AutoScaleMode.None;
        BackColor = Px.Void0;
        ForeColor = Px.Ink;
        BackgroundImage = Px.SharedTexture;
        BackgroundImageLayout = ImageLayout.Tile;
        Px.DarkTitle(this);
    }
}

public class PixelLabel : Label {
    public bool Shadow = true, Ellipsis = false;
    public StringAlignment HAlign = StringAlignment.Near, VAlign = StringAlignment.Near;
    public PixelLabel() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.SupportsTransparentBackColor | ControlStyles.ResizeRedraw, true);
        BackColor = Color.Transparent; ForeColor = Px.Ink; AutoSize = false;
    }
    protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }
    protected override void OnPaint(PaintEventArgs e) {
        Px.Text(e.Graphics, Text, Font, ForeColor, ClientRectangle, HAlign, VAlign, Shadow, Ellipsis);
    }
}

public class PixelButton : Button {
    public int Variant; // 0 normal, 1 birincil (turkuaz)
    protected bool hot, down;
    public PixelButton() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        FlatStyle = FlatStyle.Flat; FlatAppearance.BorderSize = 0; UseVisualStyleBackColor = false;
        BackColor = Px.Void0; ForeColor = Px.Ink; Cursor = Cursors.Hand;
    }
    protected override void OnMouseEnter(EventArgs e) { hot = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hot = false; down = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) { if (e.Button == MouseButtons.Left) { down = true; Invalidate(); } base.OnMouseDown(e); }
    protected override void OnMouseUp(MouseEventArgs e) { down = false; Invalidate(); base.OnMouseUp(e); }
    protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
    protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
    protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }
    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        Rectangle r = ClientRectangle;
        Color face, hi, lo;
        if (!Enabled) { face = Px.Void2; hi = Px.Void2; lo = Px.Lo; }
        else if (Variant == 1) { face = hot ? Px.TealHot : Px.TealFace; hi = Px.TealHi; lo = Px.TealLo; }
        else { face = hot ? Px.FaceHot : Px.Face; hi = Px.Hi; lo = Px.Lo; }
        Px.Bevel(g, r, face, hi, lo, down, 3);
        if (Focused && ShowFocusCues) {
            Px.Fill(g, Px.Gold, 6, 6, 4, 2); Px.Fill(g, Px.Gold, 6, 6, 2, 4);
            Px.Fill(g, Px.Gold, r.Width - 10, r.Height - 8, 4, 2); Px.Fill(g, Px.Gold, r.Width - 8, r.Height - 10, 2, 4);
        }
        Rectangle t = new Rectangle(8, 0, r.Width - 16, r.Height - 2);
        if (down) t.Offset(1, 2);
        PaintContent(g, t);
    }
    protected virtual void PaintContent(Graphics g, Rectangle t) {
        Px.Text(g, Text, Font, Enabled ? ForeColor : Px.Faint, t, StringAlignment.Center, StringAlignment.Center, Enabled, true);
    }
}

// Açılır seçici: piksel düğme + piksel menü.
public class PixelSelect : PixelButton {
    public List<string> Items = new List<string>();
    public string Prefix = "";
    int sel = -1;
    public event EventHandler SelectionChanged;
    public int SelectedIndex { get { return sel; } set { sel = value; Invalidate(); } }
    public string SelectedItem { get { return (sel >= 0 && sel < Items.Count) ? Items[sel] : null; } }
    protected override void OnClick(EventArgs e) {
        base.OnClick(e);
        ContextMenuStrip m = new ContextMenuStrip();
        m.Renderer = new PixelMenuRenderer();
        m.Font = Font;
        m.ShowImageMargin = false;
        m.ShowCheckMargin = true;
        for (int i = 0; i < Items.Count; i++) {
            int idx = i;
            ToolStripMenuItem it = new ToolStripMenuItem(Items[i]);
            it.Checked = (i == sel);
            it.Click += delegate {
                SelectedIndex = idx;
                if (SelectionChanged != null) SelectionChanged(this, EventArgs.Empty);
            };
            m.Items.Add(it);
        }
        m.MinimumSize = new Size(Width, 0);
        m.Closed += delegate { BeginInvoke(new MethodInvoker(m.Dispose)); };
        m.Show(this, new Point(0, Height));
    }
    protected override void PaintContent(Graphics g, Rectangle t) {
        Rectangle tx = new Rectangle(t.X + 4, t.Y, t.Width - 30, t.Height);
        Px.Text(g, Prefix + (SelectedItem ?? ""), Font, Enabled ? ForeColor : Px.Faint, tx, StringAlignment.Near, StringAlignment.Center, Enabled, true);
        int cx = t.Right - 12, cy = t.Y + t.Height / 2 - 3;
        for (int i = 0; i < 3; i++) Px.Fill(g, Enabled ? Px.Teal : Px.Faint, cx - 6 + i * 2, cy + i * 2, 12 - i * 4, 2);
    }
}

// Aç/kapa kutusu: ButtonBase'in kendi çizimine karışmaması için düz Control'den türetilir.
public class PixelCheck : Control {
    bool hot, isChecked;
    public event EventHandler CheckedChanged;
    public bool Checked {
        get { return isChecked; }
        set { if (isChecked == value) return; isChecked = value; Invalidate(); if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty); }
    }
    public PixelCheck() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
        BackColor = Px.Void0; ForeColor = Px.Ink; Cursor = Cursors.Hand; TabStop = true;
    }
    protected override void OnPaintBackground(PaintEventArgs e) { Px.Backdrop(e.Graphics, this); }
    protected override void OnMouseEnter(EventArgs e) { hot = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hot = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnClick(EventArgs e) { if (Enabled) Checked = !Checked; base.OnClick(e); }
    protected override void OnKeyDown(KeyEventArgs e) { if (e.KeyCode == Keys.Space && Enabled) Checked = !Checked; base.OnKeyDown(e); }
    protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }
    protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        int s = 22, y = (Height - s) / 2;
        Px.Bevel(g, new Rectangle(0, y, s, s), hot && Enabled ? Px.Void2 : Px.Void1, Px.Hi, Px.Lo, true, 2);
        if (isChecked) { Px.Fill(g, Px.TealFace, 6, y + 6, s - 12, s - 12); Px.Fill(g, Px.TealHi, 6, y + 6, s - 12, 2); Px.Fill(g, Px.TealHi, 6, y + 6, 2, s - 12); }
        Color c = Enabled ? ForeColor : Px.Faint;
        Px.Text(g, Text, Font, c, new Rectangle(s + 10, 0, Width - s - 10, Height), StringAlignment.Near, StringAlignment.Center, true, true);
    }
}

public class PixelList : ListView {
    public PixelList() {
        OwnerDraw = true; View = View.Details; FullRowSelect = true; HideSelection = false;
        BorderStyle = BorderStyle.None; HeaderStyle = ColumnHeaderStyle.None;
        BackColor = Px.Row; ForeColor = Px.Ink; DoubleBuffered = true;
        ImageList il = new ImageList(); il.ImageSize = new Size(1, 30); SmallImageList = il;
    }
    protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); Px.DarkScroll(this); }
    public void FitColumns() {
        if (Columns.Count == 0) return;
        int used = 0;
        for (int i = 0; i < Columns.Count - 1; i++) used += Columns[i].Width;
        int w = ClientSize.Width - used;
        if (w > 60) Columns[Columns.Count - 1].Width = w;
    }
    protected override void OnResize(EventArgs e) { base.OnResize(e); FitColumns(); }
    protected override void OnDrawColumnHeader(DrawListViewColumnHeaderEventArgs e) { e.DrawDefault = false; }
    protected override void OnDrawItem(DrawListViewItemEventArgs e) { }
    protected override void OnDrawSubItem(DrawListViewSubItemEventArgs e) {
        Graphics g = e.Graphics;
        Rectangle r = e.Bounds;
        if (e.ColumnIndex == 0) r.Width = Columns[0].Width;
        bool sel = e.Item.Selected;
        Px.Fill(g, sel ? Px.Select : (e.ItemIndex % 2 == 0 ? Px.Row : Px.RowAlt), r.X, r.Y, r.Width, r.Height);
        if (sel) {
            Px.Fill(g, Px.TealLo, r.X, r.Bottom - 2, r.Width, 2);
            if (e.ColumnIndex == 0) Px.Fill(g, Px.Teal, r.X, r.Y, 4, r.Height);
        }
        int pad = e.ColumnIndex == 0 ? 14 : 12;
        Color c = e.Item.UseItemStyleForSubItems ? e.Item.ForeColor : e.SubItem.ForeColor;
        Px.Text(g, e.SubItem.Text, Font, c, new Rectangle(r.X + pad, r.Y, r.Width - pad - 6, r.Height), StringAlignment.Near, StringAlignment.Center, false, true);
    }
}

// Listenin üstündeki piksel başlık şeridi (sütun genişliklerini listeden okur).
public class PixelHeader : Control {
    ListView list;
    public PixelHeader() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        BackColor = Px.Void2;
    }
    public ListView List {
        get { return list; }
        set {
            list = value;
            if (list != null) {
                list.ColumnWidthChanged += delegate { Invalidate(); };
                list.Resize += delegate { Invalidate(); };
            }
            Invalidate();
        }
    }
    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        Px.Fill(g, Px.Void2, 0, 0, Width, Height);
        Px.Fill(g, Px.Hi, 0, 0, Width, 2);
        Px.Fill(g, Px.Lo, 0, Height - 3, Width, 3);
        if (list == null) return;
        int x = 0;
        for (int i = 0; i < list.Columns.Count; i++) {
            int w = list.Columns[i].Width;
            if (i == list.Columns.Count - 1) w = Math.Max(w, Width - x);
            if (i > 0) Px.Fill(g, Px.Lo, x - 1, 7, 2, Height - 14);
            int pad = i == 0 ? 14 : 12;
            Px.Text(g, list.Columns[i].Text, Font, Px.TealHi, new Rectangle(x + pad, 0, w - pad - 6, Height - 3), StringAlignment.Near, StringAlignment.Center, true, true);
            x += list.Columns[i].Width;
        }
    }
}

// Segmentli piksel gösterge (ör. masaüstü düzeni).
public class PixelMeter : Control {
    public int Value, Maximum = 1;
    public string Caption = "", Detail = "";
    public PixelMeter() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        BackColor = Px.Void0; ForeColor = Px.Ink;
    }
    protected override void OnPaintBackground(PaintEventArgs e) { Px.Backdrop(e.Graphics, this); }
    public void SetValue(int value, int max, string caption, string detail) {
        Value = value; Maximum = Math.Max(1, max); Caption = caption; Detail = detail; Invalidate();
    }
    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        int cw = Math.Min(Px.Measure(Caption, Font, 400).Width + 4, Width / 3);
        int dw = Math.Min(Px.Measure(Detail, Font, 400).Width + 4, Width / 3);
        Px.Text(g, Caption, Font, Px.Dim, new Rectangle(0, 0, cw, Height), StringAlignment.Near, StringAlignment.Center, true, true);
        Px.Text(g, Detail, Font, Px.TealHi, new Rectangle(Width - dw, 0, dw, Height), StringAlignment.Far, StringAlignment.Center, true, true);
        Rectangle bar = new Rectangle(cw + 12, (Height - 20) / 2, Width - cw - dw - 24, 20);
        if (bar.Width < 40) return;
        Px.Bevel(g, bar, Px.Void1, Px.Hi, Px.Lo, true, 2);
        int inner = bar.Width - 10, seg = 10, n = Math.Max(1, inner / seg);
        int filled = (int)Math.Round(n * (double)Math.Min(Value, Maximum) / Maximum);
        for (int i = 0; i < n; i++) {
            int x = bar.X + 5 + i * seg;
            if (i < filled) { Px.Fill(g, Px.TealFace, x, bar.Y + 5, seg - 3, 10); Px.Fill(g, Px.TealHi, x, bar.Y + 5, seg - 3, 2); }
            else Px.Fill(g, Px.Void2, x, bar.Y + 5, seg - 3, 10);
        }
    }
}

public class PixelMenuRenderer : ToolStripRenderer {
    protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e) {
        Px.Fill(e.Graphics, Px.Void1, 0, 0, e.ToolStrip.Width, e.ToolStrip.Height);
    }
    protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e) {
        Graphics g = e.Graphics; int w = e.ToolStrip.Width, h = e.ToolStrip.Height;
        Px.Fill(g, Px.Edge, 0, 0, w, 2); Px.Fill(g, Px.Edge, 0, h - 2, w, 2);
        Px.Fill(g, Px.Edge, 0, 0, 2, h); Px.Fill(g, Px.Edge, w - 2, 0, 2, h);
        Px.Fill(g, Px.Hi, 2, 2, w - 4, 2); Px.Fill(g, Px.Hi, 2, 2, 2, h - 4);
        Px.Fill(g, Px.Lo, 2, h - 4, w - 4, 2); Px.Fill(g, Px.Lo, w - 4, 2, 2, h - 4);
    }
    protected override void OnRenderImageMargin(ToolStripRenderEventArgs e) { }
    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e) {
        if (!e.Item.Selected || !e.Item.Enabled) return;
        Px.Fill(e.Graphics, Px.Select, 4, 0, e.Item.Width - 8, e.Item.Height);
        Px.Fill(e.Graphics, Px.Teal, 4, 0, 3, e.Item.Height);
    }
    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e) {
        Color c = !e.Item.Enabled ? Px.Faint : (e.Item.Selected ? Px.TealHi : Px.Ink);
        Rectangle r = e.TextRectangle; r.Width += 24;
        Px.Text(e.Graphics, e.Text, e.TextFont, c, r, StringAlignment.Near, StringAlignment.Center, true, false);
    }
    protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e) {
        int y = e.Item.Height / 2;
        Px.Fill(e.Graphics, Px.Lo, 8, y - 1, e.Item.Width - 16, 2);
        Px.Fill(e.Graphics, Px.Hi, 8, y + 1, e.Item.Width - 16, 1);
    }
    protected override void OnRenderItemCheck(ToolStripItemImageRenderEventArgs e) {
        Rectangle r = e.ImageRectangle; int s = 8;
        Px.Fill(e.Graphics, Px.Teal, r.X + (r.Width - s) / 2, r.Y + (r.Height - s) / 2, s, s);
    }
    protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e) { e.ArrowColor = Px.Ink; base.OnRenderArrow(e); }
}

// Temalı mesaj, onay, metin girişi ve seçim pencereleri.
public class PixelDialog : PixelForm {
    public static Icon AppIcon;
    public int Result = -1;
    Rectangle slot = Rectangle.Empty;
    const int W = 540, Pad = 24;

    PixelDialog(string title) {
        Text = title;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false; MinimizeBox = false; ShowInTaskbar = false;
        StartPosition = FormStartPosition.CenterParent;
        Font = Px.Body(16);
        KeyPreview = true;
        if (AppIcon != null) Icon = AppIcon;
        PixelLabel head = new PixelLabel();
        head.Font = Px.Display(12); head.ForeColor = Px.TealHi; head.Text = title; head.Ellipsis = true;
        head.VAlign = StringAlignment.Center;
        head.SetBounds(Pad + 44, Pad, W - 2 * Pad - 44, 32);
        Controls.Add(head);
        KeyDown += delegate(object s, KeyEventArgs e) { if (e.KeyCode == Keys.Escape) { Result = -1; Close(); } };
    }
    protected override void OnPaint(PaintEventArgs e) {
        base.OnPaint(e);
        Px.Chest(e.Graphics, Pad, Pad, 2);
        Px.Fill(e.Graphics, Px.Lo, Pad, Pad + 40, W - 2 * Pad, 2);
        Px.Fill(e.Graphics, Px.Hi, Pad, Pad + 42, W - 2 * Pad, 1);
        if (!slot.IsEmpty) Px.Slot(e.Graphics, slot);
    }
    int AddBody(string text) {
        int top = Pad + 56;
        Size sz = Px.Measure(text, Font, W - 2 * Pad);
        if (sz.Height > 360) {
            TextBox tb = new TextBox();
            tb.Multiline = true; tb.ReadOnly = true; tb.ScrollBars = ScrollBars.Vertical; tb.BorderStyle = BorderStyle.None;
            tb.BackColor = Px.Void1; tb.ForeColor = Px.Ink; tb.Font = Font;
            tb.Text = text.Replace("\r\n", "\n").Replace("\n", "\r\n");
            tb.SetBounds(Pad + 10, top + 10, W - 2 * Pad - 20, 340);
            tb.HandleCreated += delegate { Px.DarkScroll(tb); };
            Controls.Add(tb);
            slot = new Rectangle(Pad, top, W - 2 * Pad, 360);
            return top + 360;
        }
        PixelLabel l = new PixelLabel();
        l.Text = text;
        l.SetBounds(Pad, top, W - 2 * Pad, sz.Height + 6);
        Controls.Add(l);
        return top + sz.Height + 6;
    }
    int AddButtons(string[] buttons, int primary, int y) {
        int x = W - Pad;
        for (int i = buttons.Length - 1; i >= 0; i--) {
            PixelButton b = new PixelButton();
            b.Text = buttons[i];
            b.Font = Px.Body(16, true);
            int bw = Math.Max(124, Px.Measure(buttons[i], b.Font, 400).Width + 44);
            x -= bw;
            b.SetBounds(x, y, bw, 44);
            b.Variant = i == primary ? 1 : 0;
            int idx = i;
            b.Click += delegate { Result = idx; Close(); };
            Controls.Add(b);
            if (i == primary) AcceptButton = b;
            x -= 10;
        }
        return y + 44;
    }
    int ShowModal(IWin32Window owner) {
        Form o = owner as Form;
        if (o != null && o.Visible && o.WindowState != FormWindowState.Minimized) ShowDialog(owner);
        else { StartPosition = FormStartPosition.CenterScreen; ShowInTaskbar = true; TopMost = true; ShowDialog(); }
        return Result;
    }
    public static int Show(IWin32Window owner, string title, string text, string[] buttons, int primary) {
        using (PixelDialog d = new PixelDialog(title)) {
            int y = d.AddBody(text) + 20;
            y = d.AddButtons(buttons, primary, y);
            d.ClientSize = new Size(W, y + Pad);
            return d.ShowModal(owner);
        }
    }
    public static string Input(IWin32Window owner, string title, string prompt, string ok, string cancel, string initial) {
        using (PixelDialog d = new PixelDialog(title)) {
            int y = d.AddBody(prompt) + 12;
            d.slot = new Rectangle(Pad, y, W - 2 * Pad, 46);
            TextBox tb = new TextBox();
            tb.BorderStyle = BorderStyle.None; tb.BackColor = Px.Void1; tb.ForeColor = Px.Ink; tb.Font = Px.Body(20);
            tb.Text = initial ?? "";
            tb.SetBounds(Pad + 12, y + 12, W - 2 * Pad - 24, 26);
            d.Controls.Add(tb);
            d.Shown += delegate { tb.Focus(); tb.SelectAll(); };
            y = d.AddButtons(new string[] { cancel, ok }, 1, y + 46 + 20);
            d.ClientSize = new Size(W, y + Pad);
            return d.ShowModal(owner) == 1 ? tb.Text : null;
        }
    }
    public static int Choose(IWin32Window owner, string title, string text, string[] labels, int selected) {
        using (PixelDialog d = new PixelDialog(title)) {
            int y = d.AddBody(text) + 16;
            int cols = 3, gap = 10, bw = (W - 2 * Pad - gap * (cols - 1)) / cols;
            for (int i = 0; i < labels.Length; i++) {
                PixelButton b = new PixelButton();
                b.Text = labels[i];
                b.Font = Px.Body(16, true);
                b.Variant = i == selected ? 1 : 0;
                b.SetBounds(Pad + (i % cols) * (bw + gap), y + (i / cols) * 54, bw, 44);
                int idx = i;
                b.Click += delegate { d.Result = idx; d.Close(); };
                d.Controls.Add(b);
                if (i == selected) d.AcceptButton = b;
            }
            y += ((labels.Length + cols - 1) / cols) * 54;
            d.ClientSize = new Size(W, y + Pad);
            return d.ShowModal(owner);
        }
    }
}
