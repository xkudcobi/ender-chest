# Changelog

## 3.4 • Pixel UI & languages
- New original pixel/voxel "End" design: custom-drawn buttons, list, dropdowns, dialogs, menus and a dark title bar.
- Fonts: Press Start 2P (titles) and Pixelify Sans (text), both SIL OFL. Japanese/Chinese fall back to system fonts automatically.
- 9 languages (Türkçe, English, Deutsch, Español, Français, Português, Русский, 日本語, 简体中文). Asked on first start, switchable live from the panel.
- Desktop tidiness meter, demo/snapshot mode (`-Demo`, `-Snapshot`) for screenshots without touching real folders.
- Fix: windows of a hidden-started process could open hidden or minimized.
- Tests: `-LangTest` (keys, placeholders, pixel-font glyph coverage, live switch).

### 3.1 • Eski yolu onarma
3.0 penceresini kapatıp yeni paketi aç. Sandıktaki adıyla eski masaüstü adı aynı olan projeleri, dosyalarını taşımadan bağlamak için “Eski masaüstü yolunu onar…” düğmesini kullan. İzleyici ayrıca kaynağını görmediği klasörlerde eski konumu doğrulamanı ister. Mevcut bir dosya veya farklı klasörün üzerine yazmaz. Aynı sandığa ait eski bağlantılar gizli + sistem öznitelikleriyle güncellenir. Korunan işletim sistemi dosyalarını gösteriyorsan simgeleri hâlâ görebilirsin.

### 3.2 • Güvenlik
- **İşlem günlüğü:** Her taşıma ve geri taşıma önce sandıktaki gizli `.enderchest` klasörüne yazılır. Uygulama işlemin ortasında kapanırsa bir sonraki açılışta işlem tamamlanır (eski yol yeniden bağlanır ya da geri taşıma bitirilir) ve sana bildirilir. İki tarafta da gerçek klasör varsa hiçbirine dokunulmaz.
- **Kullanımdaki klasörler:** Taşımadan önce klasörü kullanan programlar (terminal, sunucu vb.) listelenir. Klasör kullanımdaysa taşıma hiçbir şeyi değiştirmeden iptal edilir ve nedeni açıkça yazılır. Sandıkta aynı adlı bir öğe varsa taşıma hiç başlamaz.
- **Kalıcı dizin:** Masaüstü klasörlerinin kimlikleri `.enderchest\index.json` dosyasına kaydedilir. Panel kapalıyken Gezgin ile sandığa taşınan projeler bir sonraki açılışta sormadan bağlanır. “Eksik masaüstü yolları” sorusuna verilen cevap da hatırlanır.
- **Dayanıklı izleme:** Okunamayan tek bir klasör artık tüm izlemeyi durdurmaz.
- `.enderchest` klasörünü silme veya taşıma; projelerine etkisi yoktur ama kurtarma bilgisi kaybolur.
- Masaüstündeki gizli bağlantıları Gezgin dışındaki araçlarla (`Remove-Item -Recurse`, temizlik programları) silme: bazı araçlar bağlantının içine girip gerçek proje dosyalarını siler.

Testler:
- `./EnderChest.ps1 -SafetyTest` — yarıda kalan taşıma/geri taşıma, bozuk günlük, kilitli klasör, isim çakışması ve kalıcı dizin.
- `./EnderChest.ps1 -FeatureTest` — proje türü algılama, hariç tutma, toplu seçim, kısmi toplu taşıma, proje kaydı ve sağlık ekranı.

Başlatıcı ve ikon: `tools\Build.ps1` (`Launcher.cs` → `EnderChest.exe`, `tools\Make-Icon.ps1` → `EnderChest.ico`). Durum dosyaları sandıktaki gizli `.enderchest` klasöründedir: `index.json`, `projects.json`, `settings.json` ve yarım kalan işlemler için `pending-*.json`.

### 3.3 • Gruplar
Sandığın içinde projeleri gruplayabilirsin (ör. Web, Araçlar, Arşiv). Masaüstündeki eski yollar her zaman çalışmaya devam eder.
- **Yeni grup…** düğmesiyle grup oluştur. Grup klasöründe gizli bir `.enderchest-group` dosyası bulunur; bu sayede uygulama onu proje sanmaz. Gruplar tek seviyedir.
- Paneldeki **Grup** listesinden hedefi seç: **Sandığa taşı** projeleri doğrudan o gruba taşır. Sandıktaki projeleri başka gruba (veya köke) almak için onları seçip **Gruba taşı** de.
- Gezgin ile de gruplar arasında sürükleyebilir, projeyi sandıkta yeniden adlandırabilir ya da masaüstünden doğrudan bir grubun içine bırakabilirsin. Uygulama klasörü kimliğinden tanır ve eski yolu yeni konuma yönlendirir.
- Sandıkta elle açtığın boş bir klasörü **Bağlantı sağlığı → Grup yap** ile gruba çevirebilirsin (proje dosyası içeren klasörler grup yapılmaz).
- Proje adları sandığın tamamında benzersiz olmalı; başka grupta aynı adlı proje varsa taşıma başlamaz.
- Düzeltme: durum dosyaları (`index.json`, `settings.json`, `projects.json`) 3.2'de yalnız ilk kez yazılabiliyordu; artık her değişiklik kaydedilir.

Test: `./EnderChest.ps1 -GroupTest`.
